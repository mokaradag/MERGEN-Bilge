# ==============================================================================
# Dosya Yolu: R/helpers_pk_packet_context_facts.R
# Açıklama: Proje ve Kaynak Analizi v2 paketinin BAĞLAM OLGULARI katmanı
#           (master plan §5.11).
#
#           `R/helpers_pk_packet_stats.R` sayısal ÇEKİRDEĞİ (biçimleme, olgu
#           kaydı, ölçü/latest/ağırlıklı ortalama istatistikleri) sahiplenir.
#           Bu dosya, MODELE GÖRÜNEN ama ölçü OLMAYAN sayıların (kapsam, eksik
#           değer, kategorik dağılım, tarih kovaları, grup satırları) olgu
#           kümesini ve paketin doğrulanabilir TÜM olgularının birleşimini
#           sahiplenir. Ayrım, çekirdek dosyayı 800 satır / 25 fonksiyon
#           bakım tavanının ALTINDA tutar.
#
#           Dosya bilerek SAFTIR: Shiny/reaktif/DB/ağ/LLM bağımlılığı YOKTUR.
#           Yükleme sırası: `R/helpers_pk_packet_stats.R` dosyasından SONRA,
#           `R/helpers_pk_analysis_packet.R` dosyasından ÖNCE.
# ==============================================================================

# Sayım/kapsam olguları için kısa kayıt kurucusu (birimsiz, tam sayı).
# `unit`/`decimals` PARAMETREDİR, sabit DEĞİL. Bağlam olgularının çoğu tam
# sayı SAYIMDIR; ancak `other_share` / `category_share` bir ondalıkla
# yuvarlanmış YÜZDE taşır. Sabit `decimals = 0L` ve birimsiz kayıt, yazıcının
# bastığı `%25,0` gösterimini olgu kaydından AYIRIYORDU; artık yanıta basılan
# değer doğrudan bu kayıttan geldiği için ölçek/birim burada doğru olmalıdır.
# `%||%` YALNIZCA `NULL` ATLAR: paket kurucusu daraltılmış satır/grup sayısını `NA_integer_` olarak da bildirebilir; `if (NA > 0L)` "missing value where TRUE/FALSE needed" hatasıyla TÜM olgu üretimini düşürüyordu. `R/helpers_pk_packet_render.R` içindeki `.pk_render_count()` ile AYNI indirgeme, izole kullanım için yerel tutulur.
.pk_ctx_count <- function(x) {
  d <- suppressWarnings(as.numeric(x)[1])
  if (length(d) != 1L || is.na(d) || !is.finite(d)) 0 else d
}

.pk_count_fact <- function(identity, aggregation, value, label,
                           group_keys = character(0), scope = NULL,
                           unit = NULL, decimals = 0L) {
  pk_fact_record(
    kind = "context", column = identity, aggregation = aggregation,
    value = value, spec = list(label = label, decimals = decimals, unit = unit),
    status = PK_FACT_OK, scope = scope, group_keys = group_keys
  )
}

#' Pakette MODELE GÖRÜNEN ama ölçü olmayan sayılar için olgu kümesi
#'
#' Kategorik dağılım, tarih, kapsama ve grup satır sayıları modele gönderilir
#' ama §5.11 doğrulayıcısı yalnızca `packet$facts` indeksini okurdu. Model bu
#' bulgulardan birini alıntılamak istediğinde ya sayıyı atlamak, ya olmayan bir
#' kimlik uydurmak, ya da doğrulamayı atlayan işaretsiz bir sayı yazmak
#' zorunda kalıyordu. Bu fonksiyon aynı sayılar için yapılandırılmış olgu
#' üretir; kimlikler yazıcının bastığı `{{fact:...}}` yuvalarıyla BİREBİR
#' aynıdır.
pk_packet_context_facts <- function(packet, scope = NULL) {
  tanimlar <- list()

  s <- packet$scope %||% list()
  kapsama <- packet$coverage %||% list()

  tanimlar <- c(tanimlar, list(
    list(id = "__kapsam__", agg = "authorized_rows", value = s$authorized_rows,
         label = "Yetkiniz dahilindeki satir"),
    list(id = "__kapsam__", agg = "filtered_rows", value = s$filtered_rows,
         label = "Analiz edilen satir"),
    list(id = "__kapsama__", agg = "row_count", value = kapsama$rows,
         label = "Satir sayisi"),
    list(id = "__kapsama__", agg = "column_count", value = kapsama$columns,
         label = "Sutun sayisi"),
    list(id = "__kapsama__", agg = "grain_duplicates",
         value = kapsama$duplicate_rows_at_grain, label = "Tanecikte mukerrer satir")
  ))

  for (m in (kapsama$missing %||% list())) {
    tanimlar <- c(tanimlar, list(list(
      id = m$column, agg = "missing_count", value = m$missing,
      label = sprintf("%s bos deger", m$column)
    ), list(
      # Yazıcının bastığı boş değer ORANI da olgudur (`pk_fmt_share()` ile aynı
      # kapı: satır sayısı sonlu ve pozitif değilse pay basılmaz).
      id = m$column, agg = "missing_share",
      value = if (.pk_ctx_count(kapsama$rows) > 0) {
        round(as.numeric(m$missing) / as.numeric(kapsama$rows) * 100, 1L)
      } else NULL,
      label = sprintf("%s bos deger payi", m$column), unit = "%", decimals = 1L
    )))
  }

  for (k in (packet$categorical %||% list())) {
    tanimlar <- c(tanimlar, list(
      list(id = k$column, agg = "distinct_count", value = k$distinct,
           label = sprintf("%s farkli deger", k$label %||% k$column)),
      list(id = k$column, agg = "other_rows",
           value = if (.pk_ctx_count(k$other_rows) > 0) k$other_rows else NULL,
           label = sprintf("%s diger satir", k$label %||% k$column)),
      # YAZICININ BASTIĞI HER SAYININ BİR OLGUSU OLMALIDIR: "Diger" satırındaki
      # FARKLI DEĞER sayısı işaretsiz basılıyordu ve `block` kipinde köksüz
      # iddia sayılıp geçerli bir yanıtı düşürebiliyordu.
      list(id = k$column, agg = "other_values",
           value = if (.pk_ctx_count(k$other_values) > 0) k$other_values else NULL,
           label = sprintf("%s diger deger", k$label %||% k$column)),
      list(id = k$column, agg = "other_share",
           value = if (.pk_ctx_count(k$other_rows) > 0 && is.numeric(k$total) &&
                       length(k$total) == 1L && is.finite(k$total) && k$total > 0) {
             round(as.numeric(k$other_rows) / as.numeric(k$total) * 100, 1L)
           } else {
             NULL
           },
           label = sprintf("%s diger payi", k$label %||% k$column),
           unit = "%", decimals = 1L)
    ))
    for (t in (k$top %||% list())) {
      tanimlar <- c(tanimlar, list(list(
        id = k$column, agg = "category_count", value = t$count,
        label = sprintf("%s: %s", k$label %||% k$column, as.character(t$value)[1]),
        group = as.character(t$value)[1]
      )))
      # PAY DA KENDİ OLGUSUNU TAŞIR: sayım ve pay AYRI yuvalardır, böylece
      # model ikisinden hangisini anlattığını kimlikle söyler ve değerlerini
      # R ayrı ayrı basar.
      pay_degeri <- if (is.numeric(k$total) && length(k$total) == 1L &&
                        is.finite(k$total) && k$total > 0) {
        round(as.numeric(t$count) / as.numeric(k$total) * 100, 1L)
      } else {
        NULL
      }
      tanimlar <- c(tanimlar, list(list(
        id = k$column, agg = "category_share", value = pay_degeri,
        label = sprintf("%s: %s payi", k$label %||% k$column, as.character(t$value)[1]),
        group = as.character(t$value)[1], unit = "%", decimals = 1L
      )))
    }
  }

  for (t in (packet$dates %||% list())) {
    tanimlar <- c(tanimlar, list(list(
      id = t$column, agg = "date_count", value = t$n,
      label = sprintf("%s gecerli tarih", t$label %||% t$column)
    )))
    # Yazıcının bastığı her aylık kova işaretinin BİREBİR karşılığı.
    for (b in (t$buckets %||% list())) {
      kova <- as.character(b$bucket %||% "")[1]
      if (is.na(kova) || !nzchar(kova)) next
      tanimlar <- c(tanimlar, list(list(
        id = t$column, agg = "bucket_count", value = b$count,
        label = sprintf("%s %s", t$label %||% t$column, kova),
        group = kova
      )))
    }
  }

  g <- packet$groups %||% list()
  # GRUP OLGU KİMLİĞİ AD ALANLANIR.
  #
  # Kimlik `paste(group_by, collapse = "+")` ile üretiliyordu. Tek sütunlu bir
  # kırılımda bu dize AYNI adı taşıyan kategorik sütunun kimliğine EŞİT olur:
  # grup `other_rows` olgusu ile kategorik `other_rows` olgusu tek bir
  # `pk_fact_id()` paylaşır, kimliğe göre biriktirilen kayıtlardan biri DÜŞER
  # ve basılan kategorik sayım GRUP değerine karşı doğrulanır. Ön ek yazıcıyla
  # (`R/helpers_pk_packet_render.R`) AYNI olmak zorundadır.
  gruplama <- .pk_group_fact_id(g$group_by)
  # DARALTILAN GRUPLARIN SAYILARI DA OLGUDUR: yazıcı "Diger (N grup, M satir)"
  # satırını ÇIPLAK sayılarla basıyor, burada ise yalnızca GÖRÜNÜR `group_rows`
  # olguları üretiliyordu; model bu iki toplamı alıntılayamıyordu.
  tanimlar <- c(tanimlar, list(
    list(id = gruplama, agg = "other_groups",
         value = if (.pk_ctx_count(g$other_groups) > 0) g$other_groups else NULL,
         label = "Daraltilan grup sayisi"),
    list(id = gruplama, agg = "other_rows",
         value = if (.pk_ctx_count(g$other_groups) > 0) g$other_rows else NULL,
         label = "Daraltilan gruplardaki satir")
  ))
  for (satir in (g$top %||% list())) {
    tanimlar <- c(tanimlar, list(list(
      id = gruplama, agg = "group_rows", value = satir$rows,
      label = sprintf("%s satir sayisi", satir$group), group = satir$group
    )))
  }

  # Yazıcının bastığı "Sonlu gozlem / disarida birakilan" sayıları da OLGUDUR:
  # yuvası olmayan bir sayıyı model ancak ELLE yazabilir ve o sayı R'ye ait
  # olmaz. TERS gezilir: son yazan kazandığı için yazıcıyla AYNI (sütunun İLK) olgusu geçerli olur.
  for (o in rev(packet$facts %||% list())) tanimlar <- c(tanimlar, list(
    list(id = o$column, agg = "finite_count", value = o$n_finite,
         label = sprintf("%s sonlu gozlem", o$column)),
    list(id = o$column, agg = "excluded_count", value = o$n_excluded,
         label = sprintf("%s disarida birakilan", o$column))))

  # IQR uç değer SINIRLARI: yazıcı nottaki iki sınırı yuvayla basar
  # (`.pk_render_iqr_bounds()`); gösterim ölçek/ondalık sözleşmesi AYNIDIR.
  for (o in (packet$facts %||% list())) {
    sinir <- suppressWarnings(as.numeric(o$bounds %||% numeric(0)))
    if (!identical(o$aggregation, "iqr_outliers") || length(sinir) != 2L) next
    tanimlar <- c(tanimlar, lapply(1:2, function(i) list(
      id = o$column, agg = c("iqr_lower", "iqr_upper")[i], value = sinir[i],
      label = sprintf("%s IQR %s sinir", o$column, c("alt", "ust")[i]),
      decimals = o$bounds_decimals %||% NA_integer_, unit = o$bounds_unit)))
  }

  out <- list()
  for (t in tanimlar) {
    deger <- suppressWarnings(as.numeric(t$value %||% NA_real_))
    if (length(deger) != 1L || is.na(deger) || !is.finite(deger)) next
    olgu <- .pk_count_fact(t$id, t$agg, deger, t$label,
                           group_keys = as.character(t$group %||% character(0)),
                           scope = scope, unit = t$unit,
                           decimals = as.integer(t$decimals %||% 0L))
    out[[olgu$fact_id]] <- olgu
  }

  unname(out)
}

# İSTEK DEĞERİ METNİ: tek satır, yuva söz dizimi taşımaz, sınırlı uzunluk.
# Bu metin KULLANICIYA GÖRÜNEN yanıta yerleştirilebildiği için veriden/LLM'den
# gelen bir filtre değeri yapıyı bozamaz ya da sahte bir referans kuramaz.
.pk_request_safe_text <- function(x, max_chars = 80L) {
  txt <- suppressWarnings(as.character(x %||% "")[1])
  if (length(txt) != 1L || is.na(txt)) return("")
  txt <- gsub("[[:cntrl:]]+", " ", txt)
  txt <- gsub("[][{}`|]", "", txt)
  txt <- trimws(gsub("[[:space:]]+", " ", txt))
  if (nchar(txt) > max_chars) txt <- paste0(substr(txt, 1L, max_chars), "…")
  txt
}

#' Kullanıcı sorusundaki DÖNEM sayıları ("son 6 ayda", "30 günden az")
#'
#' Filtre çıkarıcı göreli dönemi çoğu zaman MUTLAK bir tarihe çevirir ve özgün
#' sayı kaybolur; model onu yeniden anınca ("6 ay içinde") kaynaksız sayı
#' sayılıyordu. Yalnızca gün/ay/yıl birimli sayılar alınır (dar kapsam); ham
#' soru pakette SAKLANMAZ, yalnızca "6 ay" biçimli değerler taşınır.
pk_request_period_values <- function(text, max_values = 5L) {
  txt <- .pk_request_safe_text(text, 2000L)
  if (!nzchar(txt)) return(character(0))
  esle <- regmatches(txt, gregexpr("(?i)(?<![0-9.,])([0-9]{1,4})[[:space:]]*(gün|gun|ay|yıl|yil)",
                                   txt, perl = TRUE))[[1]]
  if (!length(esle)) return(character(0))
  sayi <- sub("^([0-9]+).*$", "\\1", esle, perl = TRUE)
  # Birim kanonik yazıma indirgenir (büyük harf / ASCII yazım farkı).
  ilk <- tolower(substr(sub("^[0-9]+[[:space:]]*", "", esle, perl = TRUE), 1L, 1L))
  birim <- ifelse(ilk == "g", "gün", ifelse(ilk == "a", "ay", "yıl"))
  utils::head(unique(paste(sayi, birim)), max_values)
}

#' GÜVENİLİR İSTEK GİRDİLERİ: kullanıcının kendi kriterleri (§5.11)
#'
#' "Bitişine 30 günden az kalan aktiviteler" isteğindeki `30` KULLANICIDAN
#' gelir; hesaplanmış bir veritabanı ölçüsü DEĞİLDİR ve ölçü olgularıyla aynı
#' kökenlilik yolundan geçmemelidir. Bu değerler `kind = "request_input"`
#' türünde AÇIKÇA taşınır; böylece:
#'   * model onları da bir yuva jetonuyla anabilir (gösterimi yine R basar),
#'   * sayı tarayıcısı onları TAHMİNLE değil, taşınan kümeye karşı TAM
#'     eşleşmeyle tanır ve protokol ihlali saymaz.
#'
#' Kaynak, LLM'in ÇIKARDIĞI ham küme değil, gerçekten UYGULANAN filtre
#' kümesidir; düşürülen bir filtre buraya girmez.
pk_packet_request_facts <- function(packet) {
  uygulanan <- packet$filters$applied %||% list()
  out <- list()
  for (i in seq_along(uygulanan)) {
    f <- uygulanan[[i]]
    if (!is.list(f)) next
    sutun <- .pk_request_safe_text(f$column %||% "?", 60L)
    islem <- .pk_request_safe_text(f$operation %||% "exact_match", 40L)
    ham <- (f[["values"]] %||% f[["value"]]) %||% character(0)
    degerler <- vapply(as.character(ham), .pk_request_safe_text, character(1),
                       USE.NAMES = FALSE)
    degerler <- degerler[nzchar(degerler)]
    if (!nzchar(sutun) || !length(degerler)) next

    gosterim <- paste(degerler, collapse = ", ")
    # SAYISAL DEĞER KANONİK ANAHTARDAN ÇÖZÜLÜR: düz virgül->nokta çevirisi
    # binlik ayracını ondalık sanıyor ("12.500" -> 12,5) ve olgu değeri gerçek
    # istekten sapıyordu.
    anahtar <- pk_fact_number_key(degerler[1])
    sayisal <- if (nzchar(anahtar)) suppressWarnings(as.numeric(anahtar)) else NA_real_
    out[[length(out) + 1L]] <- list(
      fact_id = pk_fact_id(paste0("__istek__:", sutun), islem, degerler),
      kind = "request_input",
      column = sutun,
      label = sprintf("Istek kriteri: %s (%s)", sutun, islem),
      measure_capability = NULL,
      aggregation = islem,
      value = if (length(degerler) == 1L && length(sayisal) == 1L &&
                  !is.na(sayisal) && is.finite(sayisal)) sayisal else NULL,
      unit = NULL, decimals = NULL,
      status = PK_FACT_OK,
      scope = packet$scope$scope_signature,
      group_keys = character(0),
      # Ham değerler AYRI taşınır: çok değerli bir kriterde ("30, 60") birleşik
      # gösterimin rakam anahtarı tek tek değerlerle eşleşmezdi.
      request_values = degerler,
      # Yazıcı, hangi filtre satırının hangi yuvayı taşıdığını KONUMSAL
      # tahminle değil bu alanla bulur (geçersiz filtreler atlandığı için
      # iki listenin sırası ayrışabilir).
      source_index = i,
      n_finite = NA_integer_, n_excluded = NA_integer_, note = NULL,
      display = gosterim
    )
  }

  # Sorudaki DÖNEM sayıları da istek girdisidir: gösterim yalnızca sayıdır
  # ("Son {{yuva}} ayda" doğal okunur); birimli ham değer, modelin "6 ay"
  # yazdığı yinelemeyi sayı + birim anahtarıyla tanıtır.
  for (donem in as.character(packet$filters$request_periods %||% character(0))) {
    parca <- strsplit(donem, " ", fixed = TRUE)[[1]]
    if (length(parca) != 2L || !grepl("^[0-9]{1,4}$", parca[1])) next
    out[[length(out) + 1L]] <- list(
      fact_id = pk_fact_id("__istek_donem__", parca[2], parca[1]),
      kind = "request_input", column = "__istek_donem__",
      label = sprintf("Istek donemi: %s", donem), measure_capability = NULL,
      aggregation = "period", value = as.numeric(parca[1]), unit = NULL,
      decimals = 0L, status = PK_FACT_OK, scope = packet$scope$scope_signature,
      group_keys = character(0), request_values = donem, source_index = NA_integer_,
      n_finite = NA_integer_, n_excluded = NA_integer_, note = NULL,
      display = parca[1]
    )
  }

  out
}

#' Paketin DOĞRULANABİLİR tüm olguları (ölçü + grup + bağlam + istek girdisi)
#'
#' Grup kırılımındaki ölçü olguları da yuva jetonuyla basıldığı hâlde indekse
#' girmiyordu; doğru alıntılanmış bir grup toplamı `unknown_fact` sayılırdı
#' (kimliğe göre tekilleştirilir).
pk_packet_all_facts <- function(packet) {
  grup_olgulari <- unlist(
    lapply(packet$groups$top %||% list(), function(satir) satir$facts %||% list()),
    recursive = FALSE
  )

  hepsi <- c(packet$facts %||% list(), grup_olgulari %||% list(),
             pk_packet_context_facts(packet, scope = packet$scope$scope_signature),
             pk_packet_request_facts(packet))

  # ÇAKIŞAN KİMLİKLER DOĞRULAYICIYA ULAŞMADAN ATILMAZ.
  #
  # `pk_facts_index()` aynı kimliğe düşen İKİ FARKLI olguyu bilerek "belirsiz"
  # işaretler ve o kimlik üzerinden hiçbir iddiayı kabul etmez. Eski "ilk
  # kazanır" tekilleştirmesi ikinci olguyu doğrulayıcı görmeden siliyordu;
  # kimlik yeteneğe/toplulaştırmaya göre üretildiği için aynı yeteneği paylaşan
  # iki ölçü sütunu meşru biçimde çakışabiliyor ve provenans, ikinci sütuna
  # atfedilen bir sayıyı BİRİNCİ sütunun değeriyle doğrulayabiliyordu.
  #
  # BİREBİR AYNI olgu (aynı kimlik + aynı değer + aynı durum) yinelemesi
  # gerçek bir çakışma değildir; yalnızca o eleniyor.
  out <- list()
  imza <- character(0)
  for (o in hepsi) {
    if (!is.list(o) || !is.character(o$fact_id) || !nzchar(o$fact_id)) next
    # DEĞER TAM DUYARLIKLA KARŞILAŞTIRILIR. `format()` `getOption("digits")`
    # (varsayılan 7) ile YUVARLAR: aynı kimlikli ama FARKLI değerli iki olgu
    # aynı imzayı üretip biri "birebir yineleme" diye ELENİYOR, kimlik
    # `ambiguous_fact_id` işaretlenmiyor ve elenen değeri alıntılayan iddia
    # HAYATTA KALAN değere karşı doğrulanıyordu.
    # DEĞER SKALERE İNDİRGENİR: çok ögeli bir `value` alanı `paste()` içinde
    # VEKTÖR üretir ve `if (kimlik %in% imza)` "condition has length > 1" ile
    # PATLAR; olgu birleşimi ham R hatasıyla düşerdi.
    ham_deger <- o$value %||% NA
    if (length(ham_deger) != 1L) ham_deger <- NA
    kimlik <- paste(o$fact_id, o$column %||% "", o$aggregation %||% "",
                    o$status %||% "",
                    format(ham_deger, digits = 22L, scientific = TRUE),
                    sep = "\u0001")
    if (kimlik %in% imza) next
    imza <- c(imza, kimlik)
    out[[length(out) + 1L]] <- o
  }

  out
}
