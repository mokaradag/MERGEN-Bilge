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
# bastığı `%25,0` biçimindeki iddiayı `unit_mismatch` yapıyor ve `block`
# kipinde GEÇERLİ yanıtı determinist yedekle değiştiriyordu.
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
#' üretir; kimlikler yazıcının bastığı `[fact:...]` işaretleriyle BİREBİR
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
    )))
  }

  for (k in (packet$categorical %||% list())) {
    tanimlar <- c(tanimlar, list(
      list(id = k$column, agg = "distinct_count", value = k$distinct,
           label = sprintf("%s farkli deger", k$label %||% k$column)),
      list(id = k$column, agg = "other_rows",
           value = if ((k$other_rows %||% 0L) > 0L) k$other_rows else NULL,
           label = sprintf("%s diger satir", k$label %||% k$column)),
      # YAZICININ BASTIĞI HER SAYININ BİR OLGUSU OLMALIDIR: "Diger" satırındaki
      # FARKLI DEĞER sayısı işaretsiz basılıyordu ve `block` kipinde köksüz
      # iddia sayılıp geçerli bir yanıtı düşürebiliyordu.
      list(id = k$column, agg = "other_values",
           value = if ((k$other_values %||% 0L) > 0L) k$other_values else NULL,
           label = sprintf("%s diger deger", k$label %||% k$column)),
      list(id = k$column, agg = "other_share",
           value = if ((k$other_rows %||% 0L) > 0L && is.numeric(k$total) &&
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
      # PAY DA KENDİ OLGUSUNU TAŞIR. Eskiden sayım işareti yüzdeden SONRA
      # basılıyordu: köken ayrıştırıcısı işaretin HEMEN ÖNÜNDEKİ sayı olarak
      # YÜZDEYİ okuyor ve onu SAYIM değeriyle karşılaştırıp `value_mismatch`
      # üretiyordu; `block` kipinde geçerli bir kategori iddiası düşüyordu.
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
         value = if ((g$other_groups %||% 0L) > 0L) g$other_groups else NULL,
         label = "Daraltilan grup sayisi"),
    list(id = gruplama, agg = "other_rows",
         value = if ((g$other_groups %||% 0L) > 0L) g$other_rows else NULL,
         label = "Daraltilan gruplardaki satir")
  ))
  for (satir in (g$top %||% list())) {
    tanimlar <- c(tanimlar, list(list(
      id = gruplama, agg = "group_rows", value = satir$rows,
      label = sprintf("%s satir sayisi", satir$group), group = satir$group
    )))
  }

  # Yazıcının bastığı "Sonlu gozlem / disarida birakilan" sayıları da OLGUDUR:
  # dört haneli işaretsiz bir sayım `block` kipinde `missing_fact_marker` üretip
  # TÜM yanıtı determinist yedekle değiştirirdi. TERS gezilir: son yazan kazandığı için yazıcıyla AYNI (sütunun İLK) olgusu geçerli olur.
  for (o in rev(packet$facts %||% list())) tanimlar <- c(tanimlar, list(
    list(id = o$column, agg = "finite_count", value = o$n_finite,
         label = sprintf("%s sonlu gozlem", o$column)),
    list(id = o$column, agg = "excluded_count", value = o$n_excluded,
         label = sprintf("%s disarida birakilan", o$column))))

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

#' Paketin DOĞRULANABİLİR tüm olguları (ölçü + grup + bağlam)
#'
#' Grup kırılımındaki ölçü olguları da `[fact:...]` işaretiyle basıldığı hâlde
#' indekse girmiyordu; doğru alıntılanmış bir grup toplamı `unknown_fact`
#' sayılırdı (kimliğe göre tekilleştirilir).
pk_packet_all_facts <- function(packet) {
  grup_olgulari <- unlist(
    lapply(packet$groups$top %||% list(), function(satir) satir$facts %||% list()),
    recursive = FALSE
  )

  hepsi <- c(packet$facts %||% list(), grup_olgulari %||% list(),
             pk_packet_context_facts(packet, scope = packet$scope$scope_signature))

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
