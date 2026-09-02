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
#' @return Yalnızca ve yalnızca izole dizin; oluşturulamazsa `NULL`.
pk_export_run_dir <- function(base_dir = NULL) {
  kok <- base_dir %||% file.path(tempdir(), "pk_export")
  if (!dir.exists(kok)) dir.create(kok, recursive = TRUE, showWarnings = FALSE)

  yol <- tempfile(pattern = "run_", tmpdir = kok)
  dir.create(yol, recursive = TRUE, showWarnings = FALSE)

  # PAYLAŞILAN KÖKE GERİ DÜŞÜLMEZ (güvenlik sınırı).
  #
  # Eskiden izole `run_` dizini oluşturulamadığında paylaşılan `pk_export`
  # kökü dönüyordu. Dosya adları yalnızca sorgudan türeyen taban ad ve SANİYE
  # çözünürlüklü zaman damgası taşır; aynı saniyede aynı sorguyu dışa aktaran
  # iki oturum böylece AYNI yola yazabilir ve ilk oturumun kayıtlı indirme
  # bağlantısı ikinci kullanıcının RLS ile süzülmüş verisini sunabilirdi.
  # İzolasyon sağlanamıyorsa dışa aktarım BAŞARISIZ olur.
  if (!dir.exists(yol)) return(NULL)
  yol
}

# ELEKTRONİK TABLO FORMÜL ENJEKSİYONU ETKİSİZLEŞTİRİLİR.
#
# `=`, `+`, `-`, `@` (ve satır başı/sekme öncüleri) ile başlayan bir metin
# hücresi Excel/LibreOffice'te FORMÜL olarak yorumlanır. Açıklama/yorum alanları
# kullanıcı denetimindedir, yani RLS uygulanmış bir dışa aktarım açıldığında
# hücre çalıştırılabilir hâle gelirdi. Değer bir tek tırnakla ön eklenir: bu,
# elektronik tabloların METİN olarak yorumlama sözleşmesidir; veri KAYBOLMAZ.
#
# Doğrulayıcı da AYNI gösterimle karşılaştırır (bkz. `pk_export_csv_neutralize`
# çağrısı), aksi hâlde yuvarlak yolculuk denetimi yanlış pozitif verirdi.
.PK_CSV_FORMULA_LEADS <- c("=", "+", "-", "@")

pk_export_csv_neutralize <- function(df) {
  if (!is.data.frame(df) || !ncol(df)) return(df)

  for (ad in names(df)) {
    sutun <- df[[ad]]
    if (is.factor(sutun)) sutun <- as.character(sutun)
    if (!is.character(sutun)) next

    bas <- sub("^[\t\r\n ]+", "", sutun)
    riskli <- !is.na(sutun) & nzchar(sutun) &
      substr(bas, 1L, 1L) %in% .PK_CSV_FORMULA_LEADS
    if (any(riskli)) sutun[riskli] <- paste0("'", sutun[riskli])
    df[[ad]] <- sutun
  }

  df
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

  df <- pk_export_csv_neutralize(df)

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

  # DOĞRULAMA, GERÇEKTEN YAZILAN GÖSTERİMLE karşılaştırılır: formül öncüsü
  # taşıyan hücreler yazımda etkisizleştirilir (bkz. `pk_export_csv_neutralize`).
  expected <- pk_export_csv_neutralize(expected)

  # DOĞRULAMA BELLEK SINIRLIDIR (PARÇA PARÇA GERİ OKUMA).
  #
  # Eskiden tüm CSV parçası `read.csv(..., colClasses = "character")` ile
  # BİR KEREDE belleğe alınıyordu. Bu yol tam da XLSX'in bellek açısından
  # ağır bulunduğu sonuçlar için seçilir; hâlâ canlı olan kaynak/sonuç
  # çerçevelerinin ÜZERİNE çok büyük bir karakter çerçevesi eklemek, bellek
  # güvenliği için yönlendirilen isteği işçiyi tüketerek düşürebiliyordu.
  #
  # `read.csv()` AÇIK bir bağlantıdan `nrows` ile okurken KAYIT bazlı çalışır;
  # tırnak içine alınmış gömülü satır sonları doğru ayrıştırılır. Karşılaştırma
  # da aynı dilim üzerinde yapılır, böylece bellek parça boyutuyla sınırlıdır.
  karsilastir_dilim <- function(okunan, bek_dilim, sutun_adlari) {
    if (!identical(names(okunan), sutun_adlari)) {
      return("Sutun basliklari kaynakla ayni degil.")
    }
    for (i in seq_along(bek_dilim)) {
      bek <- bek_dilim[[i]]
      ger <- okunan[[i]]

      # `integer64` TAM ONDALIK METİN olarak karşılaştırılır.
      #
      # `bit64::integer64` `is.numeric()` denetimini GEÇER; iki tarafı da
      # `as.numeric()` ile çevirmek 2^53 üstünde AYNI yuvarlamayı uygular ve
      # DEĞİŞMİŞ bir kimlik "doğrulandı" sayılırdı. XLSX doğrulayıcısı
      # (`.pk_export_compare_column()`) zaten metin karşılaştırır; iki
      # doğrulayıcı TEK sözleşmeye bağlanır.
      if (inherits(bek, "integer64")) {
        bek_metin <- trimws(as.character(bek))
        bek_metin[is.na(bek_metin)] <- ""
        if (!identical(bek_metin, trimws(as.character(ger)))) {
          return(sprintf("'%s' sutununda tam sayi degeri degismis (integer64).",
                         sutun_adlari[i]))
        }
        next
      }

      if (is.numeric(bek)) {
        ger_sayi <- suppressWarnings(as.numeric(ger))
        bek_sayi <- as.numeric(bek)
        bos <- is.na(bek_sayi)
        if (!identical(bos, is.na(ger_sayi))) {
          return(sprintf("'%s' sutununda bos deger deseni degismis.", sutun_adlari[i]))
        }
        sonsuz_bek <- !bos & is.infinite(bek_sayi)
        sonsuz_ger <- !bos & is.infinite(ger_sayi)
        if (!identical(sonsuz_bek, sonsuz_ger) ||
            any(sonsuz_bek & (sign(bek_sayi) != sign(ger_sayi)))) {
          return(sprintf("'%s' sutununda sonsuz deger deseni degismis.", sutun_adlari[i]))
        }
        # KANONİK GÖSTERİM KARŞILAŞTIRILIR, BÜYÜKLÜĞE ÖLÇEKLİ TOLERANS DEĞİL.
        #
        # Eski eşik `max(1e-9, |beklenen| * 1e-12)` idi: `1e12` civarında BİR
        # birimlik, `1e15` civarında BİN birimlik değişim "doğrulandı" sayılır;
        # oysa bu geri okuma tam da sadakati KANITLAMAK için yapılıyor ve
        # maddi olarak değişmiş bir kimlik/adet/tutar sessizce onaylanırdı.
        # `utils::write.csv()` ondalık metin yazar (15 anlamlı basamak);
        # aynı gösterime indirgenen iki değer CSV'de AYIRT EDİLEMEZ, farklı
        # gösterime düşen her fark ise GERÇEK bir sapmadır.
        kanonik <- function(x) {
          x[x == 0] <- 0  # `-0` ile `0` CSV'de aynı yazılır.
          sprintf("%.15g", x)
        }
        sonlu <- !bos & !sonsuz_bek
        if (any(sonlu) &&
            !identical(kanonik(bek_sayi[sonlu]), kanonik(ger_sayi[sonlu]))) {
          return(sprintf("'%s' sutununda sayisal deger degismis.", sutun_adlari[i]))
        }
        next
      }

      if (!identical(.pk_csv_expected_chr(bek), as.character(ger))) {
        return(sprintf("'%s' sutununda metin degeri degismis.", sutun_adlari[i]))
      }
    }
    NA_character_
  }

  tryCatch({
    baglanti <- file(path, open = "r", encoding = "UTF-8-BOM")
    on.exit(try(close(baglanti), silent = TRUE), add = TRUE)

    parca_satir <- .PK_CSV_CHUNK_ROWS
    # BOŞ SATIR ATLANMAZ: `write.csv(..., na = "")` TEK sütunlu bir sonuçta
    # değeri `NA` olan satır için BOŞ bir satır yazar; `read.csv()` varsayılan
    # `blank.lines.skip = TRUE` ile o satırı düşürür. Okunan satır sayısı
    # beklenenin altında kalıyor, `pk_export_csv_verify()` "Satir sayisi
    # uyusmuyor" diyor, geçerli dosya SİLİNİYOR ve kullanıcıya HİÇ dosya
    # gitmiyordu.
    ilk <- utils::read.csv(
      baglanti, nrows = parca_satir, header = TRUE,
      colClasses = "character", check.names = FALSE,
      na.strings = character(0), stringsAsFactors = FALSE,
      blank.lines.skip = FALSE
    )
    okunan <- ilk
    sutun_adlari <- names(ilk)

    if (ncol(okunan) != ncol(expected)) {
      return(list(ok = FALSE, reason = sprintf(
        "Sutun sayisi uyusmuyor: beklenen %d, okunan %d.", ncol(expected), ncol(okunan)
      )))
    }
    if (!identical(sutun_adlari, names(expected))) {
      return(list(ok = FALSE, reason = "Sutun basliklari kaynakla ayni degil."))
    }
    if (anyDuplicated(names(expected)) > 0L) {
      return(list(ok = FALSE, reason = "Mukerrer sutun basligi: etiketler belirsiz."))
    }

    toplam_beklenen <- nrow(expected)
    okunan_toplam <- 0L

    repeat {
      okunan_satir <- nrow(okunan)
      if (okunan_satir > 0L) {
        if (okunan_toplam + okunan_satir > toplam_beklenen) {
          return(list(ok = FALSE, reason = sprintf(
            "Satir sayisi uyusmuyor: beklenen %d, okunan en az %d.",
            toplam_beklenen, okunan_toplam + okunan_satir
          )))
        }

        dilim <- expected[(okunan_toplam + 1L):(okunan_toplam + okunan_satir), ,
                          drop = FALSE]
        hata <- karsilastir_dilim(okunan, dilim, sutun_adlari)
        if (!is.na(hata)) return(list(ok = FALSE, reason = hata))

        okunan_toplam <- okunan_toplam + okunan_satir
      }

      if (okunan_satir < parca_satir) break

      # DOSYA SONUNDA YENİDEN OKUNMAZ.
      #
      # Beklenen satır sayısı tamamlandığında bir sonraki okuma bağlantının
      # SONUNDA yapılırdı. `read.table()` tükenmiş bir bağlantıda R sürümüne ve
      # sütun bilgisine göre "no lines available in input" hatası verebilir; bu
      # hata `tryCatch` tarafından yakalanıp GEÇERLİ bir CSV parçası "geri okuma
      # hatası" olarak reddedilirdi. Tetikleyici, parça satır sayısının
      # `.PK_CSV_CHUNK_ROWS` katı olmasıdır (varsayılan parça boyutu tam 20
      # katıdır). Fazladan içerik varsa AÇIKÇA raporlanır.
      if (okunan_toplam >= toplam_beklenen) {
        fazla <- tryCatch(readLines(baglanti, n = 1L, warn = FALSE),
                          error = function(e) character(0))
        if (length(fazla) && nzchar(trimws(fazla[1]))) {
          return(list(ok = FALSE, reason = sprintf(
            "Satir sayisi uyusmuyor: beklenen %d, dosyada fazladan satir var.",
            toplam_beklenen
          )))
        }
        break
      }

      okunan <- utils::read.csv(
        baglanti, nrows = parca_satir, header = FALSE,
        col.names = sutun_adlari, colClasses = "character", check.names = FALSE,
        na.strings = character(0), stringsAsFactors = FALSE,
        blank.lines.skip = FALSE
      )
      if (!nrow(okunan)) break
    }

    if (okunan_toplam != toplam_beklenen) {
      return(list(ok = FALSE, reason = sprintf(
        "Satir sayisi uyusmuyor: beklenen %d, okunan %d.", toplam_beklenen, okunan_toplam
      )))
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
#' @param transform İSTEĞE BAĞLI, parça başına uygulanan saf dönüşüm. `NULL`
#'   ise `body` zaten hazırlanmış kabul edilir (eski davranış). Verildiğinde
#'   `body` HAM çerçevedir ve dönüşüm her dilime AYRI uygulanır; böylece tam
#'   boyutlu ikinci bir kopya hiç oluşturulmaz.
#' @param stop_check İSTEĞE BAĞLI iptal/son tarih kapısı; PARÇALAR ARASINDA
#'   yoklanır.
pk_export_csv_bundle <- function(dir, base_name, plan, body,
                                 summary_sheet = NULL, info_sheet = NULL,
                                 transform = NULL, stop_check = NULL) {
  dosyalar <- list()
  uretilenler <- character(0)
  tamamlandi <- FALSE

  geri_al <- function(reason) {
    if (exists("safe_unlink_if_exists", mode = "function", inherits = TRUE)) {
      for (y in uretilenler) safe_unlink_if_exists(y)
    }
    list(ok = FALSE, files = list(), reason = reason)
  }

  # İSTİSNA DA YARIM PAKET BIRAKAMAZ.
  #
  # `geri_al()` yalnızca DÖNÜŞ yollarında çalışır. `transform()` ya da
  # `pk_export_neutralize_csv()` hata fırlattığında yığın `geri_al()`i ATLAYARAK
  # çözülüyor, çağıran tarafta hata `ok = FALSE`a çevriliyor ve o ana kadar
  # yazılmış RLS süzülmüş CSV parçaları çalışma dizininde SAHİPSİZ kalıyordu:
  # `.pk_export_track_artifact()` de yalnızca başarı yolunda çağrılır.
  on.exit({
    if (!isTRUE(tamamlandi) &&
        exists("safe_unlink_if_exists", mode = "function", inherits = TRUE)) {
      for (y in uretilenler) try(safe_unlink_if_exists(y), silent = TRUE)
    }
  }, add = TRUE)

  # İPTAL/SON TARİH PARÇALAR ARASINDA YOKLANIR.
  #
  # Eskiden kapı yalnızca tüm paket üretildikten SONRA yoklanıyordu; büyük ama
  # izinli bir dışa aktarım Durdur'a ya da mutlak son tarihe rağmen her parçayı
  # yazıp geri okumaya devam ediyor, senkron geri düşmede tüm oturumları
  # bloke ediyordu.
  durduruldu <- function() {
    is.function(stop_check) && isTRUE(tryCatch(stop_check(), error = function(e) FALSE))
  }

  for (parca in plan$parts) {
    if (durduruldu()) return(geri_al("Dışa aktarım durduruldu."))

    alt <- body[parca$ordinals, , drop = FALSE]
    rownames(alt) <- NULL
    attr(alt, "pk_source_columns") <- NULL
    # Dönüşüm PARÇA BAŞINA uygulanır: yüzde/etiket hazırlığı yalnızca
    # metadata'ya bağlıdır, dolayısıyla dilim dilim uygulamak tüm çerçeveyi
    # dönüştürüp bölmekle AYNI sonucu verir ve ikinci tam kopyayı önler.
    if (is.function(transform)) alt <- transform(alt)
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

  tamamlandi <- TRUE
  list(ok = TRUE, files = dosyalar, reason = NULL)
}
