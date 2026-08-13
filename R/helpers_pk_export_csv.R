# ==============================================================================
# Dosya Yolu: R/helpers_pk_export_csv.R
# Açıklama: Proje ve Kaynak Analizi dışa aktarımının ORTAK G/Ç TABANI ve CSV
#           yedeği (master plan §5.9).
#
#           Burada üç sorumluluk vardır:
#             1. ÇAKIŞMASIZ DOSYA YOLU. Dışa aktarım dosyaları kullanıcıya özel
#                RLS filtreli veridir. Yalnızca saniye çözünürlüklü bir zaman
#                damgası, süreç genelinde ORTAK olan `tempdir()/pk_export`
#                altında iki kullanıcı için AYNI yolu üretebilir; ikinci yazım
#                birincinin baytlarını ezer ve her iki oturumun temizliği de
#                paylaşılan dosyayı siler. Bu yüzden her dışa aktarım kendi
#                TEKİL çalışma dizinine yazar (`pk_export_run_dir()`).
#             2. AKIŞLI CSV YAZIMI. `capture.output()` + `paste()` + `charToRaw()`
#                zinciri tüm dosyayı birkaç kez bellekte oluştururdu; izin
#                verilen tavanda (20 x 100.000 satır) bu, XLSX zaten
#                başarısız olmuşken paylaşılan Shiny sürecini tüketebilir.
#                Yazım parça parça yapılır ve bellek parça boyutuyla sınırlıdır.
#             3. DOĞRULANMIŞ YEDEK. XLSX geri okunup doğrulanırken CSV'nin
#                "yazma çağrısı hata vermedi" varsayımıyla eksiksiz sayılması
#                tutarsızdı. Her parça geri okunur; başlık, satır/sütun sayısı
#                ve hücre değerleri karşılaştırılır. Parçalardan biri bile
#                doğrulanamazsa TÜM yedek reddedilir (yarım küme sunulmaz) ve
#                `Ozet`/`Bilgi` denetim bağlamı yan dosya olarak yazılır.
#
#           UTF-8 **BOM** zorunludur: Excel BOM'suz UTF-8'i ANSI sanar ve Türkçe
#           bozulur (Bilge Yolaç `.txt` sözleşmesiyle aynı kural).
#
#           Dosya G/Ç yapar; saf DEĞİLDİR. Saf kararlar
#           `R/helpers_pk_export_plan.R` içindedir.
# ==============================================================================

# Bir CSV parçası tek seferde değil, bu kadar satırlık bloklar hâlinde yazılır.
.PK_CSV_CHUNK_ROWS <- 5000L

#' Dışa aktarım dosya adı (kullanıcıya görünen ad)
#'
#' Tekillik DİZİNDEN gelir (`pk_export_run_dir()`); ad okunabilir kalır.
.pk_export_filename <- function(base, ext, index = NULL, total = 1L) {
  temiz <- gsub("[^A-Za-z0-9_.-]+", "_", as.character(base %||% "analiz")[1])
  temiz <- gsub("^_+|_+$", "", temiz)
  if (!nzchar(temiz)) temiz <- "analiz"

  damga <- format(Sys.time(), "%Y%m%d_%H%M%S")
  parca <- if (!is.null(index) && total > 1L) sprintf("_%03d", as.integer(index)) else ""
  sprintf("%s_%s%s.%s", temiz, damga, parca, ext)
}

#' Bu dışa aktarıma ÖZEL, çakışmasız çalışma dizini
#'
#' Aynı saniyede aynı sorguyu dışa aktaran iki kullanıcı ayrı dizinlere yazar;
#' kayıtlı indirme bağlantısı böylece DEĞİŞMEZ kalır ve bir oturumun temizliği
#' diğerinin dosyasını silemez.
pk_export_run_dir <- function(base_dir = NULL) {
  kok <- base_dir %||% file.path(tempdir(), "pk_export")
  if (!dir.exists(kok)) dir.create(kok, recursive = TRUE, showWarnings = FALSE)

  yol <- tempfile(pattern = "run_", tmpdir = kok)
  dir.create(yol, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(yol)) return(kok)
  yol
}

#' UTF-8 BOM'lu CSV'yi PARÇA PARÇA yaz (tam kopya materyalize edilmez)
.pk_export_write_csv_bom <- function(path, df, chunk_rows = .PK_CSV_CHUNK_ROWS) {
  chunk_rows <- max(1L, suppressWarnings(as.integer(chunk_rows)))
  if (is.na(chunk_rows)) chunk_rows <- .PK_CSV_CHUNK_ROWS

  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(as.raw(c(0xEF, 0xBB, 0xBF)), con)

  yaz <- function(parca, basligi_yaz) {
    metin <- utils::capture.output(
      utils::write.csv(parca, row.names = FALSE, na = "")
    )
    if (!basligi_yaz && length(metin)) metin <- metin[-1L]
    if (!length(metin)) return(invisible(NULL))
    writeBin(charToRaw(enc2utf8(paste0(paste(metin, collapse = "\n"), "\n"))), con)
    invisible(NULL)
  }

  toplam <- nrow(df)
  if (toplam == 0L) {
    yaz(df, TRUE)
    return(invisible(path))
  }

  bas <- 1L
  ilk <- TRUE
  while (bas <= toplam) {
    son <- min(bas + chunk_rows - 1L, toplam)
    yaz(df[bas:son, , drop = FALSE], ilk)
    ilk <- FALSE
    bas <- son + 1L
  }

  invisible(path)
}

# CSV yuvarlak yolculuğunda NA ile "" ayırt EDİLEMEZ (`na = ""` yazılır). Bu
# yüzden beklenen çerçeve de aynı sözleşmeye indirgenerek karşılaştırılır.
.pk_csv_expected_chr <- function(x) {
  ham <- if (inherits(x, "Date") || inherits(x, "POSIXt")) {
    format(x)
  } else {
    as.character(x)
  }
  ham[is.na(ham)] <- ""
  ham
}

#' Yazılan CSV parçasını geri okuyup doğrula
#'
#' Başlıklar BİREBİR karşılaştırılır (yeniden adlandırılmış/kaymış bir başlık
#' değerleri yanlış etiket altında sunar). Sayısal sütunlar sayısal olarak,
#' diğerleri metin olarak ve SIRA KORUNARAK karşılaştırılır.
pk_export_csv_verify <- function(path, expected) {
  if (!file.exists(path)) return(list(ok = FALSE, reason = "CSV dosyasi olusmadi."))
  if (!is.data.frame(expected)) {
    return(list(ok = FALSE, reason = "Karsilastirilacak cerceve yok."))
  }

  tryCatch({
    okunan <- utils::read.csv(
      path, colClasses = "character", check.names = FALSE,
      fileEncoding = "UTF-8-BOM", na.strings = character(0),
      stringsAsFactors = FALSE
    )

    if (ncol(okunan) != ncol(expected)) {
      return(list(ok = FALSE, reason = sprintf(
        "Sutun sayisi uyusmuyor: beklenen %d, okunan %d.", ncol(expected), ncol(okunan)
      )))
    }
    if (nrow(okunan) != nrow(expected)) {
      return(list(ok = FALSE, reason = sprintf(
        "Satir sayisi uyusmuyor: beklenen %d, okunan %d.", nrow(expected), nrow(okunan)
      )))
    }
    if (!identical(names(okunan), names(expected))) {
      return(list(ok = FALSE, reason = "Sutun basliklari kaynakla ayni degil."))
    }
    if (anyDuplicated(names(expected)) > 0L) {
      return(list(ok = FALSE, reason = "Mukerrer sutun basligi: etiketler belirsiz."))
    }

    if (!nrow(expected)) return(list(ok = TRUE, reason = NULL))

    for (i in seq_along(expected)) {
      bek <- expected[[i]]
      ger <- okunan[[i]]

      if (is.numeric(bek)) {
        ger_sayi <- suppressWarnings(as.numeric(ger))
        bek_sayi <- as.numeric(bek)
        bos <- is.na(bek_sayi)
        if (!identical(bos, is.na(ger_sayi))) {
          return(list(ok = FALSE, reason = sprintf(
            "'%s' sutununda bos deger deseni degismis.", names(expected)[i]
          )))
        }
        # SONSUZ DEĞERLER AYRI KARŞILAŞTIRILIR.
        #
        # Geçerli bir sonuç `Inf`/`-Inf` içerdiğinde (ör. sıfıra bölünen bir
        # oran) başarılı bir gidiş-dönüş aynı sonsuz değeri üretir; ancak
        # `Inf - Inf` = `NaN` olur, karşılaştırma `NA` döner, `any(...)` `NA`
        # döner ve saran `if` HATA atardı. Dıştaki tryCatch bunu "doğrulama
        # başarısız" sayıp GEÇERLİ CSV'yi siliyordu.
        sonsuz_bek <- !bos & is.infinite(bek_sayi)
        sonsuz_ger <- !bos & is.infinite(ger_sayi)
        if (!identical(sonsuz_bek, sonsuz_ger) ||
            any(sonsuz_bek & (sign(bek_sayi) != sign(ger_sayi)))) {
          return(list(ok = FALSE, reason = sprintf(
            "'%s' sutununda sonsuz deger deseni degismis.", names(expected)[i]
          )))
        }

        sonlu <- !bos & !sonsuz_bek
        if (any(sonlu) &&
            any(abs(ger_sayi[sonlu] - bek_sayi[sonlu]) >
                  pmax(1e-9, abs(bek_sayi[sonlu]) * 1e-12))) {
          return(list(ok = FALSE, reason = sprintf(
            "'%s' sutununda sayisal deger degismis.", names(expected)[i]
          )))
        }
        next
      }

      if (!identical(.pk_csv_expected_chr(bek), as.character(ger))) {
        return(list(ok = FALSE, reason = sprintf(
          "'%s' sutununda metin degeri degismis.", names(expected)[i]
        )))
      }
    }

    list(ok = TRUE, reason = NULL)
  }, error = function(e) {
    list(ok = FALSE, reason = sprintf("CSV geri okuma hatasi: %s", conditionMessage(e)))
  })
}

# Tek bir CSV dosyası yaz + doğrula. Başarısızlıkta yarım dosya BIRAKILMAZ.
.pk_export_csv_emit <- function(dir, name, df, verify = TRUE) {
  yol <- file.path(dir, name)

  yazildi <- tryCatch({
    .pk_export_write_csv_bom(yol, df)
    TRUE
  }, error = function(e) {
    cat(sprintf("[PK_ANALIZ] CSV yazilamadi (%s): %s\n", name, conditionMessage(e)))
    FALSE
  })

  if (!yazildi) {
    if (exists("safe_unlink_if_exists", mode = "function", inherits = TRUE)) {
      safe_unlink_if_exists(yol)
    }
    return(list(ok = FALSE, reason = "CSV yazilamadi.", path = yol))
  }

  if (isTRUE(verify)) {
    dogrulama <- pk_export_csv_verify(yol, df)
    if (!isTRUE(dogrulama$ok)) {
      if (exists("safe_unlink_if_exists", mode = "function", inherits = TRUE)) {
        safe_unlink_if_exists(yol)
      }
      return(list(ok = FALSE, reason = dogrulama$reason, path = yol))
    }
  }

  list(ok = TRUE, reason = NULL, path = yol)
}

#' CSV yedeğini EKSİKSİZ üret (hepsi ya da hiçbiri) + denetim yan dosyaları
#'
#' XLSX artefaktı `Ozet` ve `Bilgi` sayfalarını taşır. Yedek yalnızca ham veri
#' parçalarını yazsaydı indirilen/paylaşılan dosya hangi popülasyonu ve hangi
#' filtreleri temsil ettiğini kaybederdi; bu yüzden aynı iki içerik yan dosya
#' olarak yazılır.
#'
#' @param body Yüzde sözleşmesi CSV için hazırlanmış (ölçeklenmemiş) gövde.
#' @return `list(ok=, files=, reason=)`
pk_export_csv_bundle <- function(dir, base_name, plan, body,
                                 summary_sheet = NULL, info_sheet = NULL) {
  dosyalar <- list()
  uretilenler <- character(0)

  geri_al <- function(reason) {
    if (exists("safe_unlink_if_exists", mode = "function", inherits = TRUE)) {
      for (y in uretilenler) safe_unlink_if_exists(y)
    }
    list(ok = FALSE, files = list(), reason = reason)
  }

  for (parca in plan$parts) {
    alt <- body[parca$ordinals, , drop = FALSE]
    rownames(alt) <- NULL
    attr(alt, "pk_source_columns") <- NULL
    alt <- pk_export_neutralize_csv(alt)

    ad <- .pk_export_filename(base_name, "csv", parca$index, length(plan$parts))
    sonuc <- .pk_export_csv_emit(dir, ad, alt)
    if (!isTRUE(sonuc$ok)) {
      return(geri_al(sprintf("CSV parcasi dogrulanamadi (%s): %s", ad,
                             as.character(sonuc$reason %||% "?")[1])))
    }

    uretilenler <- c(uretilenler, sonuc$path)
    dosyalar[[length(dosyalar) + 1L]] <- list(
      path = sonuc$path, name = ad, rows = parca$rows, cols = ncol(alt), format = "csv"
    )
  }

  if (length(dosyalar) != length(plan$parts)) {
    return(geri_al("CSV parca sayisi plan ile uyusmuyor."))
  }

  # Denetim bağlamı: XLSX'teki `Ozet`/`Bilgi` ile aynı içerik.
  yan_dosyalar <- list(Ozet = summary_sheet, Bilgi = info_sheet)
  for (etiket in names(yan_dosyalar)) {
    df <- yan_dosyalar[[etiket]]
    if (!is.data.frame(df)) next

    ad <- .pk_export_filename(paste0(base_name, "_", etiket), "csv")
    sonuc <- .pk_export_csv_emit(dir, ad, pk_export_neutralize_csv(df))
    if (!isTRUE(sonuc$ok)) {
      return(geri_al(sprintf("Denetim yan dosyasi yazilamadi (%s): %s", etiket,
                             as.character(sonuc$reason %||% "?")[1])))
    }

    uretilenler <- c(uretilenler, sonuc$path)
    dosyalar[[length(dosyalar) + 1L]] <- list(
      path = sonuc$path, name = ad, rows = nrow(df), cols = ncol(df), format = "csv"
    )
  }

  list(ok = TRUE, files = dosyalar, reason = NULL)
}
