# ==============================================================================
# Dosya Yolu: R/helpers_pk_analysis_packet.R
# Açıklama: Proje ve Kaynak Analizi v2 ANALİZ PAKETİ (master plan §5.7).
#
#           `generate_statistical_summary()`in yerini alır ve şu kusurları
#           kapatır:
#             D17 — Eski özet her kategorik sütun için `top5` hesaplayıp
#                   yalnızca `top5[1]`i kullanıyordu ve SADECE İLK BEŞ
#                   kategorik sütunu özetliyordu (`head(cat_cols, 5)`),
#                   üstelik sessizce. Paket TÜM boyut sütunlarını, ilk-K değeri
#                   adet VE pay ile birlikte, "Diğer (N)" toplamasıyla verir;
#                   bütçe nedeniyle bir şey düşerse bunu SÖYLER.
#             D18 — Eski örnek satır kümesi `head(data, 500)` idi; yani SQL'in
#                   döndürdüğü sıraya göre KONUMSAL YANLI bir örnekti. Paket
#                   ilk-N + son-N + uç değer + SABİT TOHUMLU TABAKALI örnek
#                   kullanır.
#             D19 — Sayılar `capture.output(print(...))` ile bilimsel gösterime
#                   düşüyordu. Paketteki her sayı `pk_fmt_number()` ile
#                   biçimlenir.
#
#           KAYNAK SINIRLARI (inceleme bulgusu): bu dosya PAYLAŞILAN Shiny
#           sürecinde, yetkili sonucun TAMAMI üzerinde çalışır. Bu yüzden hiçbir
#           adım "önce her şeyi materyalize et, sonra ilk-N'i al" yapmaz:
#           gruplar önce SAYILIR (satır indeksleri yalnızca görünür gruplar
#           için kurulur), yüksek kardinaliteli boyutlar tam frekans tablosuna
#           sokulmaz ve tabakalı örnek sınırlı bir aday havuzundan çekilir.
#
#           BİRLEŞİK ANAHTARLAR ENJEKTİFTİR: değerler uzunluk ön ekiyle
#           kodlanır. Düz ayraçla birleştirme `("A | B", "C")` ile
#           `("A", "B | C")` satırlarını AYNI gruba koyardı.
#
#           İstatistikler TÜM satırlar üzerinden hesaplanır; örneklem değildir.
#           Modele giden pakette RLS ÖNCESİ satır sayısı BULUNMAZ; yalnızca
#           yetkili popülasyon ve filtre sonrası popülasyon vardır.
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ/LLM bağımlılığı yoktur.
#           Yalnızca MERGEN_PK_ENGINE=v2 altında çağrılır.
# ==============================================================================

# Tam frekans tablosu kurulmadan önceki kardinalite tavanı. Aşan boyut sütunu
# (ör. serbest metin, kimlik) yalnızca farklı değer sayısıyla raporlanır.
.PK_DIM_MAX_DISTINCT <- 5000L

# Tabakalı örnek için sınırlı aday havuzu: kotanın bu katı kadar satır rastgele
# seçilir, tabakalama bu havuz üzerinde yapılır.
.PK_SAMPLE_POOL_FACTOR <- 50L

.pk_packet_cfg <- function(key, query_meta = NULL, fallback) {
  if (!exists("pk_config_resolve", mode = "function", inherits = TRUE)) return(fallback)
  tryCatch(pk_config_resolve(key, query_meta = query_meta), error = function(e) fallback)
}

.pk_packet_column_spec <- function(meta, column) {
  cmeta <- if (is.list(meta) && is.list(meta$column_meta)) meta$column_meta[[column]] else NULL
  if (!is.list(cmeta)) cmeta <- list()

  list(
    label = if (is.character(cmeta$label) && nzchar(cmeta$label %||% "")) cmeta$label else column,
    unit = cmeta$unit,
    decimals = cmeta$decimals,
    capability = cmeta$capability,
    role = cmeta$role,
    additive = isTRUE(cmeta$additive),
    aggregate = cmeta$aggregate,
    weight_by = cmeta$weight_by,
    latest_by = cmeta$latest_by,
    latest_tie_by = cmeta$latest_tie_by,
    percent_scale = cmeta$percent_scale
  )
}

.pk_packet_meta <- function(query) {
  if (is.list(query) && is.list(query$meta)) return(query$meta)
  list()
}

# Boş/yalnızca boşluk metin, SQL sonuçlarında yaygın bir "eksik" biçimidir.
# `NA` sayılmazsa kapsama raporu eksikliği olduğundan az gösterir ve boş dize
# kategorik dağılımda gerçek (çoğu zaman ilk sıradaki) bir değer olur.
.pk_blank_to_na <- function(x) {
  if (!is.character(x)) return(x)
  x[!is.na(x) & !nzchar(trimws(x))] <- NA_character_
  x
}

# Ayraç çakışmasız birleşik anahtar: her parça bayt uzunluğu ön ekiyle yazılır,
# eksik değer ayrı bir jetonla kodlanır.
.pk_join_key <- function(data, columns) {
  parcalar <- lapply(columns, function(s) {
    v <- data[[s]]
    # KESİRLİ SANİYE KAYBEDİLEMEZ.
    #
    # `format.POSIXct()` varsayılanı kesirli saniyeyi YAZMAZ; aynı saniye
    # içindeki FARKLI damgalar tek anahtara düşüyor, bu da ya sahte "tanecik
    # mükerrerliği" (geçerli toplulaştırmayı bloklar) ya da iki ayrı
    # `default_group_by` kovasının BİRLEŞMESİ (yanlış grup olgusu) demekti.
    # Kayıpsız temsil: sayısal an (epoch saniye, tam basamakla).
    ch <- if (inherits(v, "POSIXt")) {
      sprintf("%.6f", as.numeric(v))
    } else if (inherits(v, "Date")) {
      format(v)
    } else {
      as.character(v)
    }
    ch[is.na(v)] <- NA_character_
    out <- paste0(nchar(ch, type = "bytes"), ":", ch)
    out[is.na(ch)] <- "<NA>:"
    out
  })
  do.call(paste, c(parcalar, list(sep = "|")))
}

# Kullanıcıya/model paketine görünen grup etiketi. ENJEKTİF olmak ZORUNDADIR:
# `group_keys` olarak olgu kayıtlarına geçer, yani OLGU KİMLİĞİNİN parçasıdır.
# Düz `" | "` birleşimi `("A | B", "C")` ile `("A", "B | C")` gruplarını AYNI
# gösterirdi; kaçışsız tırnak ise `ProjeAdi = 'A", Yil="1'` + `Yil = 2` ile
# `ProjeAdi = "A"` + `Yil = 1` çiftini tek dizeye çökertir; köken doğrulaması o
# zaman geçerli bir olguyu reddeder ya da değeri YANLIŞ gruba bağlar. Ters bölü
# ÖNCE kaçışlanır; aksi hâlde `\"` dizisi belirsiz kalırdı.
.pk_group_label <- function(data, columns, index) {
  paste(vapply(columns, function(s) {
    v <- data[[s]][index]
    ch <- if (inherits(v, "Date") || inherits(v, "POSIXt")) format(v) else as.character(v)
    if (length(ch) != 1L || is.na(ch)) return(sprintf("%s=(bos)", s))
    ch <- gsub("\"", "\\\"", gsub("\\", "\\\\", ch, fixed = TRUE), fixed = TRUE)
    sprintf("%s=\"%s\"", s, ch)
  }, character(1)), collapse = ", ")
}

# Metadata `role = "date"` diyebilir ama `convert_date_columns()` ayrıştırma
# oranı düşük olduğunda sütunu BİLEREK karakter bırakır. Ayrıştırılamayan bir
# sütuna `as.Date()` uygulamak tüm v2 isteğini düşürürdü.
.pk_as_date_safe <- function(values) {
  if (inherits(values, "Date")) return(values)
  if (inherits(values, "POSIXt")) {
    # ZAMAN DİLİMİ KORUNUR.
    #
    # `as.Date.POSIXct()` varsayılan olarak UTC uygular; `tzone` alanını YOK
    # SAYAR. `Europe/Istanbul` ile saklanan `2024-03-01 00:30` bu yüzden
    # `2024-02-29` oluyor ve yerel gece yarısına yakın kayıtlar YANLIŞ güne/aya
    # düşüyordu (paket zaman penceresi ve aylık dağılım hatalı yayımlanırdı).
    tz <- attr(values, "tzone")
    tz <- if (is.character(tz) && length(tz) >= 1L && !is.na(tz[1]) && nzchar(tz[1])) {
      tz[1]
    } else {
      # `Sys.timezone()` platform saat dilimi çözülemediğinde `NA_character_`
      # döner; depo `%||%` yalnızca `is.null()` denetler, dolayısıyla NA
      # geçip `as.Date(..., tz = NA)` "invalid 'tz' value" hatası verirdi.
      yerel <- tryCatch(Sys.timezone(), error = function(e) NA_character_)
      if (is.character(yerel) && length(yerel) == 1L &&
          !is.na(yerel) && nzchar(yerel)) yerel else "UTC"
    }
    return(as.Date(values, tz = tz))
  }

  cikti <- suppressWarnings(tryCatch(as.Date(values), error = function(e) NULL))
  if (is.null(cikti) || !inherits(cikti, "Date")) return(NULL)
  if (all(is.na(cikti)) && any(!is.na(values))) return(NULL)
  cikti
}

# Kimlik benzeri sayısal sütun sezgisi (yalnızca metadata YOKKEN kullanılır).
# Üretim sorguları bugün Tier-0 olduğu için proje/WBS kodları, yıllar ve durum
# kodları aksi hâlde medyan/yüzdelik olguları üretirdi.
.pk_looks_like_identifier <- function(values, column) {
  if (grepl("(^|[_ .])(id|kod|code|no|num|numara|yil|year|ay|month)([_ .]|$)",
            column, ignore.case = TRUE, perl = TRUE)) {
    return(TRUE)
  }

  v <- suppressWarnings(as.numeric(values))
  v <- v[!is.na(v) & is.finite(v)]
  # Değer tabanlı sezgi BİLEREK dardır: "hepsi farklı tam sayı" ölçüt olsaydı
  # küçük bir sonuçtaki gerçek bir tutar/süre sütunu da kimlik sayılırdı.
  # Yalnızca YOĞUN ARDIŞIK tam sayı dizisi (klasik satır kimliği) işaretlenir.
  if (length(v) < 10L) return(FALSE)
  if (!all(v == trunc(v)) || any(v < 0)) return(FALSE)
  if (length(unique(v)) != length(v)) return(FALSE)

  isTRUE((max(v) - min(v) + 1) == length(v))
}

# Rol sınıflandırması: metadata varsa ona, yoksa R sınıfına göre.
.pk_packet_roles <- function(data, meta) {
  out <- list(measure = character(0), dimension = character(0),
              date = character(0), id = character(0))
  cikarilan <- character(0)

  for (sutun in names(data)) {
    cmeta <- if (is.list(meta$column_meta)) meta$column_meta[[sutun]] else NULL
    beyanli <- is.list(cmeta) && is.character(cmeta$role) && length(cmeta$role) == 1L

    rol <- if (beyanli) {
      cmeta$role
    } else if (inherits(data[[sutun]], "Date") || inherits(data[[sutun]], "POSIXt")) {
      "date"
    } else if (is.numeric(data[[sutun]])) {
      if (.pk_looks_like_identifier(data[[sutun]], sutun)) {
        cikarilan <- c(cikarilan, sutun)
        "id"
      } else {
        "measure"
      }
    } else {
      "dimension"
    }

    if (!rol %in% names(out)) rol <- "dimension"
    out[[rol]] <- c(out[[rol]], sutun)
  }

  out$inferred_identifiers <- cikarilan
  out
}

# Kapsama: sütun bazlı boş oranı + beyan edilen grain'de mükerrer satır sayısı.
pk_packet_coverage <- function(data, meta) {
  toplam <- nrow(data)
  bos_oranlari <- lapply(names(data), function(sutun) {
    bos <- sum(is.na(.pk_blank_to_na(data[[sutun]])))
    list(column = sutun, missing = bos,
         share = if (toplam > 0) bos / toplam else NA_real_)
  })

  beyan <- as.character(meta$grain_columns %||% character(0))
  eksik <- setdiff(beyan, names(data))
  grain_sutunlari <- beyan[beyan %in% names(data)]

  # Kısmi anahtarla tanecik doğrulanamaz: `(Proje, Ay)` beyanında `Ay` sonuçta
  # yoksa her çok aylı proje YANLIŞLIKLA mükerrer görünürdü.
  mukerrer <- if (length(eksik) || !length(grain_sutunlari) || !toplam) {
    NA_integer_
  } else {
    sum(duplicated(.pk_join_key(data, grain_sutunlari)))
  }

  list(
    rows = toplam,
    columns = length(data),
    missing = bos_oranlari,
    grain_columns = grain_sutunlari,
    grain_missing_columns = eksik,
    duplicate_rows_at_grain = mukerrer
  )
}

# Kategorik özet: TÜM boyut sütunları, ilk-K değer adet VE pay ile (D17).
pk_packet_categorical <- function(data, meta, columns, top_k = 10L) {
  top_k <- max(1L, suppressWarnings(as.integer(top_k)))
  toplam <- nrow(data)

  lapply(columns, function(sutun) {
    degerler <- .pk_blank_to_na(as.character(data[[sutun]]))
    gecerli <- degerler[!is.na(degerler)]
    farkli <- unique(gecerli)

    temel <- list(
      column = sutun,
      label = .pk_packet_column_spec(meta, sutun)$label,
      distinct = length(farkli),
      missing = sum(is.na(degerler)),
      total = toplam
    )

    # Yüksek kardinalite: tam frekans tablosu + sıralama, ilk-K çıktısından
    # bağımsız olarak birkaç tam vektör ayırırdı. Böyle bir sütun yalnızca
    # farklı değer sayısıyla raporlanır.
    if (length(farkli) > .PK_DIM_MAX_DISTINCT) {
      return(c(temel, list(top = list(), other_values = length(farkli),
                           other_rows = length(gecerli), high_cardinality = TRUE)))
    }

    tablo <- sort(table(gecerli), decreasing = TRUE)
    ilk <- utils::head(tablo, top_k)
    kalan_adet <- max(0L, length(tablo) - length(ilk))
    kalan_satir <- if (kalan_adet > 0L) sum(tablo) - sum(ilk) else 0L

    c(temel, list(
      top = lapply(seq_along(ilk), function(i) {
        list(value = names(ilk)[i], count = as.integer(ilk[i]),
             share = if (toplam > 0) as.numeric(ilk[i]) / toplam else NA_real_)
      }),
      other_values = kalan_adet,
      other_rows = as.integer(kalan_satir),
      high_cardinality = FALSE
    ))
  })
}

# Tarih özeti: aralık + aya göre satır histogramı.
pk_packet_dates <- function(data, meta, columns, max_buckets = 24L) {
  lapply(columns, function(sutun) {
    etiket <- .pk_packet_column_spec(meta, sutun)$label
    bos <- list(column = sutun, label = etiket, n = 0L,
                from = NA_character_, to = NA_character_, buckets = list())

    tarihler <- .pk_as_date_safe(data[[sutun]])
    if (is.null(tarihler)) {
      return(c(bos, list(unavailable = "Tarih olarak ayristirilamadi")))
    }

    gecerli <- tarihler[!is.na(tarihler)]
    if (!length(gecerli)) return(bos)

    tablo <- table(format(gecerli, "%Y-%m"))
    tablo <- tablo[order(names(tablo))]
    kirpildi <- length(tablo) > max_buckets
    if (kirpildi) tablo <- utils::tail(tablo, max_buckets)

    list(
      column = sutun, label = etiket, n = length(gecerli),
      from = as.character(min(gecerli)), to = as.character(max(gecerli)),
      truncated = kirpildi,
      buckets = lapply(seq_along(tablo), function(i) {
        list(bucket = names(tablo)[i], count = as.integer(tablo[i]))
      })
    )
  })
}

# Sabit tohum yalnızca bu örneklemeyi etkiler; global RNG durumu geri yüklenir.
.pk_sample_seed <- function(seed) {
  ham <- suppressWarnings(as.integer(seed))
  if (length(ham) != 1L || is.na(ham)) 42L else ham
}

# Sınırlı aday havuzundan tabakalı seçim. Tabaka sırası SABİT TOHUMLA
# rastgeleleştirilir: `split()` tabakaları alfabetik verir ve kota tabaka
# sayısından küçükse hep ilk alfabetik tabakalar temsil edilirdi.
.pk_sample_stratified <- function(remaining, strata, quota) {
  if (quota <= 0L || !length(remaining)) return(integer(0))

  havuz_boyutu <- min(length(remaining), max(1000L, quota * .PK_SAMPLE_POOL_FACTOR))
  if (length(remaining) > havuz_boyutu) {
    sec <- sample.int(length(remaining), havuz_boyutu)
    remaining <- remaining[sec]
    strata <- strata[sec]
  }

  gruplar <- split(remaining, strata)
  sira <- names(gruplar)[sample.int(length(gruplar))]
  sira <- utils::head(sira, quota)

  secilen <- integer(0)
  while (quota > 0L && length(sira)) {
    kalanlar <- character(0)
    for (isim in sira) {
      if (quota <= 0L) {
        kalanlar <- c(kalanlar, isim)
        next
      }
      havuz <- gruplar[[isim]]
      if (!length(havuz)) next

      # `sample(idx, 1)` tek elemanlı sayısal vektörde `1:idx` gibi davranır ve
      # BAŞKA bir satırı seçebilir; konum örneklemesi bu tuzağı taşımaz.
      poz <- sample.int(length(havuz), 1L)
      secilen <- c(secilen, havuz[poz])
      gruplar[[isim]] <- havuz[-poz]
      quota <- quota - 1L
      if (length(gruplar[[isim]])) kalanlar <- c(kalanlar, isim)
    }
    if (!length(kalanlar)) break
    sira <- kalanlar
  }

  secilen
}

# Örnek satırlar: uç değer + ilk/son sınır satırı + SABİT TOHUMLU TABAKALI
# örnek (D18). Seçim ÖNCELİK SIRASINDA toplanır; kota aşılırsa kırpma da
# önceliğe göre yapılır (kaynak satır sırasına göre DEĞİL).
pk_packet_examples <- function(data, meta, measure_column = NULL,
                               stratify_column = NULL, n = 30L, seed = 42L) {
  n <- max(1L, suppressWarnings(as.integer(n)))
  toplam <- nrow(data)
  if (toplam == 0L) return(list(rows = data, method = "empty", requested = n))

  if (toplam <= n) {
    return(list(rows = data, method = "tam_kume", requested = n,
                indices = seq_len(toplam)))
  }

  secilen <- integer(0)
  yontemler <- character(0)
  pay <- max(1L, floor(n / 5))

  if (!is.null(measure_column) && measure_column %in% names(data) &&
      is.numeric(data[[measure_column]])) {
    v <- suppressWarnings(as.numeric(data[[measure_column]]))
    # `na.last = NA` yalnızca NA'yı atar; Inf/-Inf sıralamada uçlara oturup
    # olgu kümesinin DIŞLADIĞI değerleri örnek satır olarak öne çıkarırdı.
    sonlu_idx <- which(is.finite(v))
    if (length(sonlu_idx)) {
      sirali <- sonlu_idx[order(v[sonlu_idx], decreasing = TRUE)]
      secilen <- c(secilen, utils::head(sirali, pay), utils::tail(sirali, pay))
      yontemler <- c(yontemler, "en_yuksek", "en_dusuk")

      sonlu <- v[sonlu_idx]
      if (length(sonlu) >= 4L) {
        q <- suppressWarnings(stats::quantile(sonlu, c(0.25, 0.75), na.rm = TRUE, names = FALSE))
        iqr <- q[2] - q[1]
        if (is.finite(iqr)) {
          uc <- sonlu_idx[sonlu < q[1] - 1.5 * iqr | sonlu > q[2] + 1.5 * iqr]
          if (length(uc)) {
            secilen <- c(secilen, utils::head(uc, pay))
            yontemler <- c(yontemler, "uc_deger")
          }
        }
      }
    }
  }

  # Kaynak sırası kronolojik/sıralı olabilir; ilk ve son satırlar sözleşmenin
  # açıkça vaat ettiği sınır kayıtlarıdır.
  sinir <- max(1L, floor(n / 10))
  secilen <- c(secilen, utils::head(seq_len(toplam), sinir),
               utils::tail(seq_len(toplam), sinir))
  yontemler <- c(yontemler, "ilk_son")

  kalan <- setdiff(seq_len(toplam), unique(secilen))
  kota <- n - length(unique(secilen))

  if (kota > 0L && length(kalan)) {
    eski_tohum <- if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
      get(".Random.seed", envir = globalenv())
    } else {
      NULL
    }
    on.exit({
      if (is.null(eski_tohum)) {
        suppressWarnings(rm(".Random.seed", envir = globalenv()))
      } else {
        assign(".Random.seed", eski_tohum, envir = globalenv())
      }
    }, add = TRUE)

    set.seed(.pk_sample_seed(seed))

    tabaka <- if (!is.null(stratify_column) && stratify_column %in% names(data)) {
      as.character(data[[stratify_column]])[kalan]
    } else {
      rep("tek_tabaka", length(kalan))
    }
    tabaka[is.na(tabaka)] <- "(bos)"

    ek <- .pk_sample_stratified(kalan, tabaka, kota)
    if (length(ek)) {
      secilen <- c(secilen, ek)
      yontemler <- c(yontemler,
                     if (length(unique(tabaka)) > 1L) "tabakali_ornek" else "rastgele_ornek")
    }
  }

  # Kırpma ÖNCELİK sırasında; sunum için ancak ondan sonra sıralanır.
  secilen <- utils::head(unique(secilen), n)
  secilen <- sort(secilen)

  list(
    rows = data[secilen, , drop = FALSE],
    method = paste(unique(yontemler), collapse = "+"),
    requested = n,
    indices = secilen
  )
}

# Bir gruptaki ölçü için beyan edilen toplulaştırmayı UYGULA. Grup kırılımının
# yalnızca dağılım istatistiği vermesi, sorgunun beyan ettiği metriği (ağırlıklı
# ortalama / en yeni değer) sessizce başka bir şeyle değiştirmek olurdu.
.pk_group_measure_facts <- function(data, index, olcu, spec, scope, etiket,
                                    aggregate_blocked = FALSE) {
  agg <- as.character(spec$aggregate %||% "none")[1]

  if (identical(agg, "weighted_mean")) {
    # TANECİK İHLALİ GRUP KIRILIMINDA DA GEÇERLİDİR.
    #
    # `aggregate_blocked` bayrağı yalnızca `pk_measure_facts()` yoluna
    # aktarılıyordu; ağırlıklı ortalama dalı onu YOK SAYIYORDU. Beyan edilen
    # tanecikte mükerrer satır varsa hem PAY hem PAYDA bozulur, bu yüzden
    # grup ağırlıklı ortalaması SAYISAL OLARAK YANLIŞ olabilir; paket genel
    # olguyu `grain_violation` diye işaretlerken grup olgularını `ok` yayımlamak
    # modele çelişkili kanıt verir.
    if (isTRUE(aggregate_blocked)) {
      return(list(pk_fact_record(
        kind = "measure", column = olcu, aggregation = "weighted_mean", value = NULL,
        spec = spec, status = PK_FACT_GRAIN_VIOLATION, scope = scope,
        group_keys = etiket,
        note = paste("Beyan edilen tanecikte mukerrer satir var;",
                     "grup agirlikli ortalamasi HESAPLANMADI.")
      )))
    }

    agirlik <- as.character(spec$weight_by %||% "")[1]
    if (nzchar(agirlik) && agirlik %in% names(data)) {
      return(list(pk_weighted_mean_fact(
        data[[olcu]][index], data[[agirlik]][index], olcu, spec, scope = scope,
        group_keys = etiket, weight_column = agirlik
      )))
    }
    return(list(pk_fact_record(
      kind = "measure", column = olcu, aggregation = "weighted_mean", value = NULL,
      spec = spec, status = PK_FACT_WEIGHTED_UNAVAILABLE, scope = scope,
      group_keys = etiket,
      note = "Agirlik sutunu sonucta yok; grup icin agirlikli ortalama URETILMEDI."
    )))
  }

  if (identical(agg, "latest")) {
    return(list(pk_latest_fact(
      data[index, , drop = FALSE], olcu, spec, scope = scope, group_keys = etiket
    )))
  }


  pk_measure_facts(
    data[[olcu]][index], olcu, spec, scope = scope, group_keys = etiket,
    aggregate_mode = agg, additive = spec$additive,
    aggregate_blocked = aggregate_blocked
  )
}

# Grup kırılımı: default_group_by x default_measures, ilk-N + "Diğer".
pk_packet_groups <- function(data, meta, scope = NULL, top_n = 15L,
                             exclude_measures = character(0),
                             aggregate_blocked = FALSE) {
  gruplar <- as.character(meta$default_group_by %||% character(0))
  olculer <- as.character(meta$default_measures %||% character(0))

  # Eksik bir gruplama sütunu, kalan sütunlar üzerinden BAŞKA bir kırılım
  # üretirdi: `(Proje, Yil)` beyanında `Yil` yoksa tüm yıllar tek projede
  # toplanır ve sonuç yetkili grup olgusu diye yayımlanırdı.
  # Hiç gruplama beyan edilmemişse bölüm HİÇ üretilmez (Faz 2 sözleşmesi).
  if (!length(gruplar)) return(list())

  if (!all(gruplar %in% names(data))) {
    return(list(group_by = gruplar, measures = character(0), top = list(),
                other_groups = 0L, other_rows = 0L,
                unavailable = sprintf(
                  "Beyan edilen gruplama sutunlari sonucta eksik: %s.",
                  paste(setdiff(gruplar, names(data)), collapse = ", ")
                )))
  }

  # Ölçü olmayan (metin/kimlik) bir "default_measure" `as.numeric()` ile
  # sessizce sayıya zorlanırdı.
  olculer <- Filter(function(s) {
    s %in% names(data) && !(s %in% exclude_measures) && is.numeric(data[[s]])
  }, olculer)

  if (!length(olculer)) {
    return(list(group_by = gruplar, measures = character(0), top = list(),
                other_groups = 0L, other_rows = 0L,
                unavailable = "Gecerli sayisal olcu sutunu yok; grup kirilimi URETILMEDI."))
  }

  # ÖNCE SAY, SONRA indeks kur: `split()` tüm satır indekslerini gruplara
  # dağıtırdı ve yüksek kardinaliteli bir anahtarda milyonlarca liste elemanı
  # üretebilirdi.
  anahtar <- .pk_join_key(data, gruplar)
  sayimlar <- table(anahtar)
  sirali <- names(sayimlar)[order(as.integer(sayimlar), decreasing = TRUE)]
  gorunur <- utils::head(sirali, max(1L, suppressWarnings(as.integer(top_n))))

  # İNDEKS HARİTASI TEK GEÇİŞTE KURULUR: `which(anahtar == ad)` `lapply()` içinde çağrıldığında anahtar vektörü GÖRÜNÜR GRUP SAYISI kadar (varsayılan `MERGEN_PK_GROUP_TOPN` = 15) baştan sona taranıyordu. `split()` aynı haritayı tek geçişte üretir; grup SIRASI `gorunur` tarafından belirlendiği için çıktı DEĞİŞMEZ.
  indeks_haritasi <- local({ k <- which(anahtar %in% gorunur); split(k, anahtar[k]) })  # İNDEKS HARİTASI YALNIZCA GÖRÜNÜR GRUPLAR İÇİN KURULUR: tam `split()` FARKLI grup sayısı kadar liste ögesi ayırırdı (yüksek kardinaliteli `default_group_by` sütununda yüz binlerce öge). Tek geçiş ve çıktı sırası DEĞİŞMEZ.
  satirlar <- lapply(gorunur, function(ad) {
    idx <- indeks_haritasi[[ad]]
    etiket <- .pk_group_label(data, gruplar, idx[1])
    olgular <- lapply(olculer, function(olcu) .pk_group_measure_facts(
      data, idx, olcu, .pk_packet_column_spec(meta, olcu), scope, etiket, aggregate_blocked
    ))
    list(group = etiket, rows = length(idx), facts = unlist(olgular, recursive = FALSE))
  })
  digerler <- setdiff(sirali, gorunur)
  list(
    group_by = gruplar,
    measures = olculer,
    top = satirlar,
    other_groups = length(digerler),
    other_rows = if (length(digerler)) sum(as.integer(sayimlar[digerler])) else 0L
  )
}

# Zaman penceresi YALNIZCA tek bir tarih sütunu varken küresel olarak atanır.
# Birden çok tarih sütununda "sonuçta ilk gelen" seçimi, SQL sütun sırası
# değişince raporlanan kapsamı değiştirirdi.
.pk_packet_time_window <- function(data, date_columns) {
  if (length(date_columns) != 1L) return(NULL)

  tarihler <- .pk_as_date_safe(data[[date_columns]])
  if (is.null(tarihler)) return(NULL)

  gecerli <- tarihler[!is.na(tarihler)]
  if (!length(gecerli)) return(NULL)

  list(column = date_columns, from = as.character(min(gecerli)),
       to = as.character(max(gecerli)))
}

#' Analiz paketini kur (§5.7)
#'
#' @param data Yetki VE kullanıcı filtresi UYGULANMIŞ veri çerçevesi.
#' @param query Seçilen sorgu tanımı (`meta` alanı Faz 3a sözleşmesindedir).
#' @param context `list(authorized_rows=, filtered_rows=, filters=,
#'   filter_status=, degradations=, pre_aggregated_columns=)`
pk_packet_build <- function(data, query, context = list()) {
  meta <- .pk_packet_meta(query)
  context <- if (is.list(context)) context else list()
  if (!is.data.frame(data)) data <- data.frame()

  yetkili <- context$authorized_rows
  filtreli <- context$filtered_rows %||% nrow(data)
  kapsam <- pk_scope_signature(yetkili, filtreli)

  roller <- .pk_packet_roles(data, meta)
  onceden_toplu <- as.character(context$pre_aggregated_columns %||% character(0))
  olcu_sutunlari <- setdiff(roller$measure, onceden_toplu)

  top_k <- .pk_packet_cfg("MERGEN_PK_TOPK_CATEGORIES", meta, 10L)
  grup_n <- .pk_packet_cfg("MERGEN_PK_GROUP_TOPN", meta, 15L)
  ornek_n <- .pk_packet_cfg("MERGEN_PK_SAMPLE_ROWS", meta, 30L)
  tohum <- .pk_packet_cfg("MERGEN_PK_SAMPLE_SEED", meta, 42L)

  zaman_penceresi <- .pk_packet_time_window(data, roller$date)
  kapsama <- pk_packet_coverage(data, meta)

  olgular <- list()
  sinirliliklar <- character(0)

  # Tanecik ihlali TOPLULAŞTIRMAYI GEÇERSİZ KILAR: mükerrer grain anahtarı,
  # toplam ve ortalamayı çift sayar. Bunu yalnızca bilgi amaçlı bir sayı olarak
  # raporlamak, çift sayılmış bir toplamı yetkili olgu diye yayımlamaktı.
  tanecik_ihlali <- !is.na(kapsama$duplicate_rows_at_grain) &&
    kapsama$duplicate_rows_at_grain > 0L
  if (tanecik_ihlali) {
    sinirliliklar <- c(sinirliliklar, sprintf(
      paste("Beyan edilen tanecikte %d mukerrer satir var; TOPLAM ve ORTALAMA",
            "olgulari URETILMEDI (cift sayim riski). Dagilim istatistikleri",
            "donen satirlari betimler ve gecerlidir."),
      as.integer(kapsama$duplicate_rows_at_grain)
    ))
  }
  if (length(kapsama$grain_missing_columns)) {
    sinirliliklar <- c(sinirliliklar, sprintf(
      "Beyan edilen tanecik sutunlari sonucta eksik (%s); mukerrer satir denetimi YAPILAMADI.",
      paste(kapsama$grain_missing_columns, collapse = ", ")
    ))
  }
  if (length(roller$inferred_identifiers)) {
    sinirliliklar <- c(sinirliliklar, sprintf(
      paste("Metadata olmadigi icin kimlik benzeri sayisal sutunlar olcu",
            "SAYILMADI: %s. Bu sutunlar icin istatistik uretilmedi."),
      paste(roller$inferred_identifiers, collapse = ", ")
    ))
  }

  for (sutun in olcu_sutunlari) {
    spec <- .pk_packet_column_spec(meta, sutun)
    olgular <- c(olgular, pk_measure_facts(
      data[[sutun]], sutun, spec, scope = kapsam, time_window = zaman_penceresi,
      aggregate_mode = spec$aggregate %||% "none", additive = spec$additive,
      aggregate_blocked = tanecik_ihlali
    ))

    if (identical(spec$aggregate, "latest")) {
      olgular <- c(olgular, list(pk_latest_fact(
        data, sutun, spec, scope = kapsam, time_window = zaman_penceresi
      )))
    }

    if (identical(spec$aggregate, "weighted_mean")) {
      agirlik <- spec$weight_by

      # TANECİK İHLALİ AĞIRLIKLI ORTALAMAYI DA BLOKLAR.
      #
      # `pk_measure_facts()` mükerrer satır varken `sum`/`mean` olgularını
      # ihlal olarak işaretliyordu, ama bu AYRI çağrı aynı mükerrer satırlar
      # üzerinden `ok` durumlu bir ağırlıklı ortalama YAYIMLIYORDU. Yalnızca
      # BAZI tanecik varlıklarının çoğallanması hem payı hem paydayı değiştirir
      # ve sonucu belirgin biçimde yanlıltabilir; bu yüzden ihlal buraya da
      # taşınır ve tipli bir ihlal olgusu üretilir.
      if (isTRUE(tanecik_ihlali)) {
        olgular <- c(olgular, list(pk_fact_record(
          kind = "measure", column = sutun, aggregation = "weighted_mean",
          value = NULL, spec = spec, status = PK_FACT_GRAIN_VIOLATION,
          scope = kapsam, time_window = zaman_penceresi,
          note = "Beyan edilen tanecikte mukerrer satir var; cift sayim riski nedeniyle URETILMEDI."
        )))
      } else if (is.character(agirlik) && length(agirlik) == 1L && agirlik %in% names(data)) {
        olgular <- c(olgular, list(pk_weighted_mean_fact(
          data[[sutun]], data[[agirlik]], sutun, spec, scope = kapsam,
          time_window = zaman_penceresi, weight_column = agirlik
        )))
      } else {
        sinirliliklar <- c(sinirliliklar, sprintf(
          "'%s' agirlikli ortalama istiyor ama agirlik sutunu (%s) sonucta yok; agirlikli ortalama URETILMEDI.",
          sutun, as.character(agirlik %||% "tanimsiz")[1]
        ))
      }
    }
  }

  if (length(onceden_toplu)) {
    sinirliliklar <- c(sinirliliklar, sprintf(
      "Onceden toplulastirilmis sutunlar istatistik disi birakildi: %s.",
      paste(intersect(onceden_toplu, names(data)), collapse = ", ")
    ))
  }

  # Tier YALNIZCA metadata TÜM sonuç sütunlarını kapsıyorsa 3'tür; kısmi bir
  # açıklama, kalan sütunların yedek anlambilimle özetlendiğini gizlerdi. KAPSAM
  # TEK BAŞINA YETMEZ: `pk_meta_tier0_column_meta()` HER yapısal sütun için
  # `tier = 0` / `inferred_from = "structural_schema"` girdisi üretir; yalnızca
  # kapsama bakan eski kural, küre edilmiş anlambilimi olmayan sorguyu "tam
  # Tier-3" ilan ediyordu. Tier artık GİRDİLERİN kendi beyanından türetilir.
  sutun_meta <- meta$column_meta %||% list()
  kapsanmayan <- setdiff(names(data), names(sutun_meta))
  cikarim_sutunlari <- if (length(sutun_meta)) {
    names(sutun_meta)[vapply(sutun_meta, function(m) {
      is.list(m) &&
        (identical(as.character(m$inferred_from %||% "")[1], "structural_schema") ||
           identical(suppressWarnings(as.integer(m$tier %||% NA_integer_)[1]), 0L))
    }, logical(1))]
  } else character(0)

  tier <- if (length(sutun_meta) && !length(kapsanmayan) &&
              !length(cikarim_sutunlari)) 3L else 0L

  if (length(sutun_meta) && length(cikarim_sutunlari)) {
    sinirliliklar <- c(sinirliliklar, sprintf(paste(
      "Metadata YAPISAL CIKARIMDIR (Tier-0): %s sutunu icin kure edilmis",
      "anlamsal beyan yok; rol/birim semadan tahmin edildi."
    ), paste(cikarim_sutunlari, collapse = ", ")))
  }

  if (!length(sutun_meta)) {
    sinirliliklar <- c(sinirliliklar, paste(
      "Bu sorgu icin anlamsal metadata (Tier-0) yok:",
      "additive dogrulanmadigi icin TOPLAM ve ORTALAMA uretilmedi;",
      "grain bilinmedigi icin mukerrer satir elemesi yapilmadi."
    ))
  } else if (length(kapsanmayan)) {
    sinirliliklar <- c(sinirliliklar, sprintf(
      paste("Metadata KISMIDIR (Tier-0 muamelesi): %s sutunu icin anlamsal",
            "beyan yok ve bu sutunlar yedek anlambilimle ozetlendi."),
      paste(kapsanmayan, collapse = ", ")
    ))
  }

  birincil_olcu <- {
    toplanabilir <- Filter(function(s) .pk_packet_column_spec(meta, s)$additive, olcu_sutunlari)
    if (length(toplanabilir)) toplanabilir[1] else if (length(olcu_sutunlari)) olcu_sutunlari[1] else NULL
  }
  tabaka <- {
    aday <- as.character(meta$default_group_by %||% character(0))
    aday <- aday[aday %in% names(data)]
    if (length(aday)) aday[1] else if (length(roller$dimension)) roller$dimension[1] else NULL
  }

  # Uygulanan filtre bilgisi, satır sayısının düşüp düşmediğinden DEĞİL kabul
  # edilen filtre kümesinden gelir: tüm yetkili satırlara uyan gerçek bir filtre
  # de spesifik bir popülasyonu temsil eder ve payda uyarısını hak eder.
  # `authorized_rows` NA OLABİLİR (`execute_single_deep_query()` ilklendirmesi): `FALSE || NA` -> NA yayınlanınca `if (...user_filter_applied)` ile dallanan tüketici "missing value where TRUE/FALSE needed" ile DÜŞÜYORDU.
  filtre_uygulandi <- length(context$filters %||% list()) > 0L ||
    isTRUE(!is.null(yetkili) && !is.null(filtreli) && isTRUE(as.integer(yetkili) > as.integer(filtreli)))

  list(
    scope = list(
      query_id = query$id %||% NA_character_,
      query_name = query$name %||% NA_character_,
      grain = meta$grain,
      grain_columns = as.character(meta$grain_columns %||% character(0)),
      tier = tier,
      authorized_rows = yetkili,
      filtered_rows = filtreli,
      scope_signature = kapsam,
      time_window = zaman_penceresi
    ),
    filters = list(
      status = context$filter_status,
      applied = context$filters %||% list(),
      degradations = context$degradations %||% list(),
      user_filter_applied = filtre_uygulandi
    ),
    coverage = kapsama,
    facts = olgular,
    categorical = pk_packet_categorical(data, meta, roller$dimension, top_k),
    dates = pk_packet_dates(data, meta, roller$date),
    groups = pk_packet_groups(data, meta, kapsam, grup_n,
                              exclude_measures = onceden_toplu,
                              aggregate_blocked = tanecik_ihlali),
    examples = pk_packet_examples(data, meta, birincil_olcu, tabaka, ornek_n, tohum),
    limitations = sinirliliklar,
    roles = roller
  )
}
