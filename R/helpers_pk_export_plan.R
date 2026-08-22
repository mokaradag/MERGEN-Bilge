# ==============================================================================
# Dosya Yolu: R/helpers_pk_export_plan.R
# Açıklama: Excel/CSV dışa aktarımının SAF karar katmanı (master plan §5.9).
#
#           Burada dosya yazılmaz; yalnızca "ne yazılacağı" kararlaştırılır:
#             * kararlı satır sırası (`.pk_export_row_id`) ve parça bölmesi,
#             * parça tavanının aşıldığı durumda AÇIK RET (sessiz kırpma YOK),
#             * yazıcıya özgü yüzde sözleşmesi (writexl tabanı vs openxlsx),
#             * CSV'ye özgü formül etkisizleştirme (yalnızca KARAKTER sütunlar),
#             * `Bilgi` ve `Özet` sayfalarının içeriği.
#
#           Yüzde sözleşmesi kritiktir: Excel'in `0.0%` biçimi saklanan değeri
#           100 ile ÇARPAR. Yüzde-puan olarak saklanan 61,3 bu biçimle
#           **%6130,0** görünür — yönetim raporuna giden bir dosyada iki
#           büyüklük mertebesi hata. İki yol da sayısaldır ve ikisi de bu hatayı
#           üretemez:
#             writexl tabanı : 61.3 saklanır, baslik "... (%)"
#             openxlsx varsa : 0.613 saklanir + `0.0%` stili, baslik "..."
#
#           `Bilgi` sayfasına RLS ÖNCESİ satır sayısı ASLA yazılmaz; yalnızca
#           yetkili popülasyon ve filtre sonrası popülasyon yer alır.
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ/LLM bağımlılığı yoktur.
# ==============================================================================

PK_EXPORT_ROW_ID <- ".pk_export_row_id"

.pk_export_cfg <- function(key, query_meta = NULL, fallback) {
  if (!exists("pk_config_resolve", mode = "function", inherits = TRUE)) return(fallback)
  tryCatch(pk_config_resolve(key, query_meta = query_meta), error = function(e) fallback)
}

#' Sayfa adını Excel kurallarına indirge (<=31 karakter, yasak karakter yok)
#'
#' Türkçe karakterler sayfa adında SERBESTTİR; yalnızca Excel'in reddettiği
#' `[ ] : * ? / \` karakterleri ve tek tırnak temizlenir.
pk_export_sheet_name <- function(base, index = NULL) {
  ad <- as.character(base %||% "Veri")[1]
  if (is.na(ad) || !nzchar(trimws(ad))) ad <- "Veri"

  ad <- gsub("[\\[\\]:*?/\\\\]", " ", ad, perl = TRUE)
  ad <- gsub("'", " ", ad, fixed = TRUE)
  ad <- trimws(gsub("[[:space:]]+", " ", ad))
  if (!nzchar(ad)) ad <- "Veri"

  ek <- if (is.null(index)) "" else sprintf("_%03d", as.integer(index))
  kalan <- 31L - nchar(ek)
  if (nchar(ad) > kalan) ad <- substr(ad, 1L, kalan)

  paste0(ad, ek)
}

#' Kararlı satır sırası ata
#'
#' Sıra numarası, tam yetkili+filtreli çerçeve üzerinde verilir ve parça
#' bölmesini deterministik yapar. MEŞRU MÜKERRER SATIRLAR KORUNUR; hiçbir
#' aşamada tekilleştirme yapılmaz.
pk_export_row_ordinals <- function(data) {
  if (!is.data.frame(data)) return(integer(0))
  seq_len(nrow(data))
}

#' Parça planı: tam aktarım, çok parçalı aktarım veya AÇIK RET
#'
#' @return `list(status = "ok"|"refuse", parts=, total_rows=, message=)`
pk_export_plan <- function(data, base_name = "Veri", query_meta = NULL,
                           max_rows = NULL, max_parts = NULL) {
  toplam <- if (is.data.frame(data)) nrow(data) else 0L

  max_rows <- suppressWarnings(as.integer(
    max_rows %||% .pk_export_cfg("MERGEN_PK_EXPORT_MAX_ROWS", query_meta, 100000L)
  ))
  if (is.na(max_rows) || max_rows < 1L) max_rows <- 100000L

  max_parts <- suppressWarnings(as.integer(
    max_parts %||% .pk_export_cfg("MERGEN_PK_EXPORT_MAX_PARTS", query_meta, 20L)
  ))
  if (is.na(max_parts) || max_parts < 1L) max_parts <- 20L

  if (toplam == 0L) {
    return(list(status = "empty", parts = list(), total_rows = 0L, max_rows = max_rows,
                message = "Aktarilacak satir yok."))
  }

  parca_sayisi <- as.integer(ceiling(toplam / max_rows))

  if (parca_sayisi > max_parts) {
    return(list(
      status = "refuse", parts = list(), total_rows = toplam, max_rows = max_rows,
      message = sprintf(paste0(
        "Sonuç kümesi çok büyük: %s satır, güvenli dışa aktarım tavanı %s parça x %s satır. ",
        "Dosya SESSİZCE KIRPILMADI; lütfen sorunuzu daraltın (ör. tarih aralığı ",
        "veya proje kısıtı ekleyin)."
      ), format(toplam, scientific = FALSE), format(max_parts, scientific = FALSE),
      format(max_rows, scientific = FALSE))
    ))
  }

  parcalar <- lapply(seq_len(parca_sayisi), function(i) {
    bas <- (i - 1L) * max_rows + 1L
    son <- min(i * max_rows, toplam)
    list(
      index = i,
      from = bas,
      to = son,
      rows = son - bas + 1L,
      ordinals = bas:son,
      sheet = if (parca_sayisi == 1L) {
        pk_export_sheet_name(base_name)
      } else {
        pk_export_sheet_name(base_name, i)
      }
    )
  })

  list(status = "ok", parts = parcalar, total_rows = toplam, max_rows = max_rows,
       message = NULL)
}

#' Yazıcıya özgü yüzde hazırlığı (§5.9 madde 2)
#'
#' @param formatted `TRUE` ise openxlsx yolu (kesir + `0.0%` stili),
#'   `FALSE` ise writexl tabanı (yüzde-puan + "(%)" başlığı).
pk_export_prepare_percent <- function(data, meta = list(), formatted = FALSE) {
  if (!is.data.frame(data) || !ncol(data)) {
    return(list(data = data, headers = character(0), percent_columns = character(0),
                notes = character(0)))
  }

  sutun_meta <- if (is.list(meta) && is.list(meta$column_meta)) meta$column_meta else list()
  basliklar <- names(data)
  yuzde_sutunlari <- character(0)
  notlar <- character(0)

  for (i in seq_along(names(data))) {
    sutun <- names(data)[i]
    cmeta <- sutun_meta[[sutun]]
    if (!is.list(cmeta)) next

    birim <- as.character(cmeta$unit %||% "")[1]
    if (is.na(birim) || !identical(birim, "%")) next
    if (!is.numeric(data[[sutun]])) next

    etiket <- as.character(cmeta$label %||% sutun)[1]
    olcek <- as.character(cmeta$percent_scale %||% "")[1]

    if (!olcek %in% c("points", "fraction")) {
      # percent_scale beyan edilmemiş: DEĞER ÖLÇEKLENMEZ. Ölçeği tahmin etmek
      # tam da %6130,0 hatasını üreten davranıştır.
      basliklar[i] <- sprintf("%s (%%)", etiket)
      notlar <- c(notlar, sprintf(
        "'%s' sutunu icin percent_scale beyan edilmemis; deger olceklenmeden yazildi.",
        sutun
      ))
      next
    }

    yuzde_sutunlari <- c(yuzde_sutunlari, sutun)

    if (isTRUE(formatted)) {
      if (identical(olcek, "points")) data[[sutun]] <- data[[sutun]] / 100
      basliklar[i] <- etiket
    } else {
      if (identical(olcek, "fraction")) data[[sutun]] <- data[[sutun]] * 100
      basliklar[i] <- sprintf("%s (%%)", etiket)
    }
  }

  list(data = data, headers = basliklar, percent_columns = yuzde_sutunlari, notes = notlar)
}

#' CSV yedeğinde formül benzeri METİN değerleri etkisizleştir (§5.9 madde 8)
#'
#' Metni `=`, `+`, `-`, `@`, sekme veya satır başı ile başlayan METİN BENZERİ
#' hücrelere uygulanır. Sayısal `-125.50` SAYI KALIR; karakter `-KAPALI-`
#' etkisizleştirilir. `factor` (ve benzeri etiketli metin) sütunları da
#' kapsanır: `write.csv()` bir faktör düzeyini metin olarak yazar, dolayısıyla
#' `=HYPERLINK(...)` düzeyi CSV açıldığında Excel'de yine formül olur. Bu kural
#' CSV'ye özgüdür — writexl metni zaten metin olarak saklar.
pk_export_neutralize_csv <- function(data) {
  if (!is.data.frame(data) || !ncol(data)) return(data)

  for (sutun in names(data)) {
    degerler <- data[[sutun]]
    if (is.numeric(degerler) || is.logical(degerler) ||
        inherits(degerler, "Date") || inherits(degerler, "POSIXt")) {
      next
    }

    degerler <- as.character(degerler)
    riskli <- !is.na(degerler) & grepl("^[=+@\\-\t\r]", degerler, perl = TRUE)
    if (any(riskli)) degerler[riskli] <- paste0("'", degerler[riskli])
    data[[sutun]] <- degerler
  }

  data
}

#' `Bilgi` sayfası içeriği
#'
#' RLS ÖNCESİ satır sayısı BURAYA YAZILMAZ (§5.9 madde 5). Kapsamlı kullanıcı
#' için "yetkili popülasyon" ve "filtre sonrası" yeterlidir; yetkisi dışındaki
#' satır sayısı korunan bilgidir.
pk_export_info_sheet <- function(context = list(), plan = list()) {
  context <- if (is.list(context)) context else list()

  filtreler <- context$filters %||% list()
  filtre_metni <- if (length(filtreler)) {
    paste(vapply(filtreler, function(f) {
      sprintf("%s %s %s", as.character(f$column %||% "?")[1],
              as.character(f$operation %||% "=")[1],
              paste(as.character(f$value %||% ""), collapse = ", "))
    }, character(1)), collapse = " ; ")
  } else {
    "Uygulanmadi"
  }

  parca_metni <- if (identical(plan$status, "ok")) {
    if (length(plan$parts) > 1L) {
      sprintf("%d parca (%s)", length(plan$parts),
              paste(vapply(plan$parts, function(p) p$sheet, character(1)), collapse = ", "))
    } else {
      "Tek parca"
    }
  } else {
    as.character(plan$status %||% "?")[1]
  }

  alanlar <- c(
    "Sorgu ID", "Sorgu Adi", "Calisma Zamani", "Kullanici",
    "Uygulanan Filtreler", "Cozumlenen Degerler", "Yetki Kapsami",
    "Yetkiniz Dahilindeki Satir", "Filtre Sonrasi Satir", "Parca Bilgisi", "Not"
  )

  degerler <- c(
    as.character(context$query_id %||% "?")[1],
    as.character(context$query_name %||% "?")[1],
    format(context$timestamp %||% Sys.time(), "%Y-%m-%d %H:%M:%S"),
    as.character(context$username %||% "?")[1],
    filtre_metni,
    paste(as.character(context$resolved_values %||% character(0)), collapse = ", "),
    as.character(context$rls_scope %||% "-")[1],
    as.character(context$authorized_rows %||% "?")[1],
    as.character(context$filtered_rows %||% "?")[1],
    parca_metni,
    as.character(context$note %||% "-")[1]
  )

  data.frame(Alan = alanlar, Deger = degerler, stringsAsFactors = FALSE)
}

#' `Özet` sayfası içeriği — R tarafından hesaplanan olgular
pk_export_summary_sheet <- function(packet) {
  olgular <- Filter(function(o) is.list(o), (packet$facts %||% list()))
  if (!length(olgular)) {
    return(data.frame(
      Olcu = character(0), Toplulastirma = character(0), Deger = numeric(0),
      Birim = character(0), Durum = character(0), SonluGozlem = integer(0),
      stringsAsFactors = FALSE
    ))
  }

  data.frame(
    Olcu = vapply(olgular, function(o) as.character(o$label %||% o$column)[1], character(1)),
    Toplulastirma = vapply(olgular, function(o) as.character(o$aggregation)[1], character(1)),
    Deger = vapply(olgular, function(o) if (is.null(o$value)) NA_real_ else as.numeric(o$value),
                   numeric(1)),
    Birim = vapply(olgular, function(o) as.character(o$unit %||% "")[1], character(1)),
    Durum = vapply(olgular, function(o) as.character(o$status)[1], character(1)),
    SonluGozlem = vapply(olgular, function(o) {
      n <- suppressWarnings(as.integer(o$n_finite))
      if (length(n) != 1L || is.na(n)) NA_integer_ else n
    }, integer(1)),
    stringsAsFactors = FALSE
  )
}

# Elektronik tablo yazıcıları boş metni ve eksik değeri AYNI boş hücre olarak
# saklar; geri okuyucu ikisini de `NA` verir. Sözleşme bu yüzden "boş <-> boş"
# eşdeğerliğidir. Beklenen `NA` iken okunanın `"NA"` METNİ olması ise eşdeğer
# DEĞİLDİR; eski `paste()` tabanlı anahtar bu ayrımı kaybediyordu.
.pk_export_blank <- function(x) {
  if (is.character(x)) return(is.na(x) | !nzchar(x))
  is.na(x)
}

# Tek bir sütunu TİPİYLE BİRLİKTE ve SIRA KORUNARAK karşılaştırır. Hata varsa
# Türkçe gerekçe, yoksa NULL döner.
.pk_export_compare_column <- function(bek, ger, ad) {
  bek_bos <- unname(.pk_export_blank(bek))
  ger_bos <- unname(.pk_export_blank(ger))

  if (!identical(bek_bos, ger_bos)) {
    return(sprintf("'%s' sutununda bos hucre deseni degismis.", ad))
  }
  # Tüm hücreler boşsa okuyucu sütun tipini düşürebilir; bu meşru bir yuvarlak
  # yolculuk artefaktıdır ve tip karşılaştırması yapılmaz.
  if (all(bek_bos)) return(NULL)

  dolu <- !bek_bos

  # `integer64` TAM ONDALIK METİN olarak karşılaştırılır.
  #
  # XLSX yazıcısı bu sütunu `double`a çevirir ve 2^53 üstü değeri YUVARLAR;
  # doğrulayıcı da BEKLENEN sütuna AYNI `as.numeric()`i uyguladığı için iki
  # taraf aynı biçimde bozuluyor ve bozuk çalışma kitabı "doğrulandı" sayılıp
  # tam-CSV yedeğine düşülmüyordu.
  if (inherits(bek, "integer64") || inherits(ger, "integer64")) {
    b <- trimws(as.character(bek))[dolu]
    g <- trimws(as.character(ger))[dolu]
    # Elektronik tablo geri okuması ondalık kuyruk ekleyebilir ("42" -> "42.0").
    g <- sub("\\.0+$", "", g)
    b <- sub("\\.0+$", "", b)
    if (!identical(b, g)) {
      return(sprintf("'%s' sutununda tam sayi degeri degismis (integer64).", ad))
    }
    return(NULL)
  }

  if (is.numeric(bek)) {
    if (!is.numeric(ger)) {
      return(sprintf("'%s' sutunu sayisal degil metin olarak yazilmis.", ad))
    }
    b <- as.numeric(bek)[dolu]
    g <- as.numeric(ger)[dolu]
    # Sabit 6 basamağa yuvarlamak, metadata'nın 9 basamağa kadar izin verdiği
    # bir ölçüde bozulmuş değeri geçirebilirdi. Tolerans yalnızca ikili kayan
    # nokta gürültüsü kadardır.
    if (any(abs(b - g) > pmax(1e-9, abs(b) * 1e-12))) {
      return(sprintf("'%s' sutununda sayisal deger degismis.", ad))
    }
    return(NULL)
  }

  if (inherits(bek, "Date")) {
    if (!(inherits(ger, "Date") || inherits(ger, "POSIXt"))) {
      return(sprintf("'%s' sutunu tarih olarak yazilmamis.", ad))
    }
    if (!identical(format(as.Date(bek))[dolu],
                   format(as.Date(ger, tz = "UTC"))[dolu])) {
      return(sprintf("'%s' sutununda tarih degeri degismis.", ad))
    }
    return(NULL)
  }

  if (inherits(bek, "POSIXt")) {
    if (!inherits(ger, "POSIXt")) {
      return(sprintf("'%s' sutunu zaman damgasi olarak yazilmamis.", ad))
    }
    if (!identical(format(bek, "%Y-%m-%d %H:%M:%S", tz = "UTC")[dolu],
                   format(ger, "%Y-%m-%d %H:%M:%S", tz = "UTC")[dolu])) {
      return(sprintf("'%s' sutununda zaman damgasi degismis.", ad))
    }
    return(NULL)
  }

  if (is.logical(bek)) {
    if (!is.logical(ger)) return(sprintf("'%s' sutunu mantiksal yazilmamis.", ad))
    if (!identical(bek[dolu], ger[dolu])) {
      return(sprintf("'%s' sutununda mantiksal deger degismis.", ad))
    }
    return(NULL)
  }

  if (is.numeric(ger)) {
    return(sprintf("'%s' sutunu metin yerine sayi olarak yazilmis.", ad))
  }
  if (!identical(as.character(bek)[dolu], as.character(ger)[dolu])) {
    return(sprintf("'%s' sutununda metin degeri degismis.", ad))
  }

  NULL
}

#' Yazılan parçayı kaynak parçayla karşılaştır (mükerrer satırları KORUYARAK)
#'
#' Karşılaştırma SIRA ve TİP KORUNARAK yapılır. Sıralanmış çoklu-küme
#' karşılaştırması satırların herhangi bir permütasyonunu geçirirdi; oysa sıra
#' sıralamalı/kronolojik sorgu sonuçlarında anlam taşır ve ters çevrilmiş bir
#' sıralama "doğrulanmış" diye sunulamaz. Meşru mükerrer satırlar korunur;
#' hiçbir aşamada tekilleştirme yapılmaz.
pk_export_verify_multiset <- function(expected, actual) {
  if (!is.data.frame(expected) || !is.data.frame(actual)) {
    return(list(ok = FALSE, reason = "Karsilastirilacak cerceve yok."))
  }
  if (nrow(expected) != nrow(actual)) {
    return(list(ok = FALSE, reason = sprintf(
      "Satir sayisi uyusmuyor: beklenen %d, okunan %d.", nrow(expected), nrow(actual)
    )))
  }
  if (ncol(expected) != ncol(actual)) {
    return(list(ok = FALSE, reason = sprintf(
      "Sutun sayisi uyusmuyor: beklenen %d, okunan %d.", ncol(expected), ncol(actual)
    )))
  }

  # Başlıklar da doğrulanır: yeniden adlandırılmış/kaymış bir başlık, değerler
  # eşleşse bile kullanıcıya YANLIŞ ETİKET altında veri sunar.
  if (!identical(names(expected), names(actual))) {
    return(list(ok = FALSE, reason = "Sutun basliklari kaynakla ayni degil."))
  }
  if (anyDuplicated(names(expected)) > 0L) {
    return(list(ok = FALSE, reason = "Mukerrer sutun basligi: etiketler belirsiz."))
  }

  if (!nrow(expected)) return(list(ok = TRUE, reason = NULL))

  for (i in seq_along(expected)) {
    hata <- .pk_export_compare_column(expected[[i]], actual[[i]], names(expected)[i])
    if (!is.null(hata)) return(list(ok = FALSE, reason = hata))
  }

  list(ok = TRUE, reason = NULL)
}

# XLSX yolunun tahmini bayt tavanı (bayt cinsinden).
#
# `object.size()` çerçeveyi KOPYALAMAZ; yalnızca yürür. Geçici kopya payı
# çarpanı burada uygulanır: XLSX yolu normalleştirilmiş bir kopya ve onun
# yanında çalışma kitabı kurar.
.pk_export_byte_ceiling <- function(query_meta = NULL) {
  mb <- if (!exists("pk_config_resolve", mode = "function", inherits = TRUE)) {
    128L
  } else {
    tryCatch(
      pk_config_resolve("MERGEN_PK_EXPORT_MAX_BYTES_MB", query_meta = query_meta),
      error = function(e) 128L
    )
  }
  mb <- suppressWarnings(as.integer(mb))
  if (length(mb) != 1L || is.na(mb) || mb < 1L) mb <- 128L
  as.numeric(mb) * 1024 * 1024
}
