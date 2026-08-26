# ==============================================================================
# Dosya Yolu: tests/testthat/test-windows-cp1254-source-safety-contract.R
# Açıklama: R kaynak dosyalarının Windows VM (Türkçe yerel, WINDOWS-1254 kod
#           sayfası) üzerinde `source(..., encoding = "UTF-8")` ile SESSİZCE
#           BOZULMADAN okunabildiğini garanti eder.
#
#           NEDEN: Windows VM'de R'nin yerel kodlaması WINDOWS-1254'tür.
#           `source(dosya, encoding = "UTF-8")` içeriği yerel kodlamaya çevirir.
#           WINDOWS-1254'te KARŞILIĞI OLMAYAN bir karakter (ör. lira işareti
#           U+20BA, kesişim U+2229, sağ ok U+2192, birleştirici işaretler,
#           emoji) çeviriyi
#           bozar: R "giriş bağlantısında geçersiz giriş bulundu" uyarısı verir
#           ve dosyayı O NOKTADA KESER. Kesilen dosya "unexpected end of input"
#           ile ayrıştırılamaz; sonrasındaki tüm fonksiyonlar tanımsız kalır ve
#           testler yüzlerce ardıl hata üretir.
#
#           Bu, Türkçe metin bütünlüğü kuralının KARŞITI DEĞİLDİR: ç ğ ı İ ö ş ü
#           gibi Türkçe karakterlerin TAMAMI WINDOWS-1254'te temsil edilir ve
#           serbestçe kullanılmaya devam eder. Yalnızca temsil EDİLEMEYEN
#           karakterler yasaktır; bunlar dizelerde `"\uXXXX"` kaçışıyla (değer
#           bayt düzeyinde AYNI kalır) ya da yorumlarda ASCII karşılığıyla
#           yazılmalıdır.
#
#           Test çevrimdışı ve deterministiktir: DB, LLM, tarayıcı, ağ yoktur.
# ==============================================================================

testthat::test_that("R kaynak dosyaları WINDOWS-1254 yerelinde bozulmadan okunabilir", {
  # Repo kökü çözümü, repo genelindeki test sözleşmesiyle aynıdır
  # (bkz. tests/testthat/helper_bootstrap.R); ek paket bağımlılığı yoktur.
  kok <- if (exists("repo_root_for_tests", inherits = TRUE)) {
    get("repo_root_for_tests", inherits = TRUE)
  } else {
    aday <- c(".", "..", "../..")
    uygun <- aday[vapply(
      aday,
      function(p) file.exists(file.path(p, "app.R")) && dir.exists(file.path(p, "R")),
      logical(1)
    )]
    testthat::skip_if(length(uygun) == 0L, "Repo kökü bulunamadı")
    normalizePath(uygun[1], winslash = "/", mustWork = TRUE)
  }

  dizinler <- file.path(kok, c("R", "tests/testthat", "tests/scripts", "tools"))
  dizinler <- dizinler[dir.exists(dizinler)]

  dosyalar <- unlist(lapply(
    dizinler,
    function(d) list.files(d, pattern = "\\.[Rr]$", full.names = TRUE, recursive = TRUE)
  ), use.names = FALSE)

  # KÖK DİZİNDE YALNIZCA DEPOYA AİT GİRİŞ DOSYALARI taranır.
  #
  # `list.files(kok)` çalışma kopyasındaki HER `.R` dosyasını görür; Windows
  # VM'de operatörün kök dizinde tuttuğu deneme betikleri (izlenmeyen, depoya
  # ait olmayan dosyalar) de buna dâhildir. Bunlar uygulama tarafından hiç
  # `source()` edilmez, dolayısıyla bu sözleşmenin konusu DEĞİLDİR; taranırlarsa
  # depo kodu kusursuz olduğu hâlde suite kırmızıya döner. Kök dizindeki
  # çalışma zamanı dosyaları kapalı bir kümedir (seam kaydı `extra_runtime_files`
  # ile aynı sınır); yeni bir kök dosyası eklendiğinde bu liste de bilinçli
  # olarak güncellenir.
  kok_calisma_zamani <- c(
    "app.R", "global.R", "server.R", "ui.R",
    "welcome_screen.R", "run_mergen_prod.R"
  )
  kok_dosyalar <- file.path(kok, kok_calisma_zamani)
  kok_dosyalar <- kok_dosyalar[file.exists(kok_dosyalar)]
  dosyalar <- unique(c(dosyalar, kok_dosyalar))

  testthat::expect_gt(length(dosyalar), 0L)

  # Her dosya BAYT olarak okunur (kesilme riski olmadan), sonra WINDOWS-1254'e
  # çevrilebilirliği sınanır. `iconv()` çevrilemeyen ögeler için NA döndürür.
  kirik <- vapply(dosyalar, function(f) {
    satirlar <- tryCatch(
      readLines(f, encoding = "UTF-8", warn = FALSE),
      error = function(e) NA_character_
    )
    if (length(satirlar) == 1L && is.na(satirlar[1])) return(NA_integer_)
    # BOM İLK SATIRDA KALABİLİR.
    #
    # `readLines(encoding = "UTF-8")` yalnızca kodlamayı ETİKETLER; BOM'u
    # ayıklamaz. U+FEFF'in CP1254 karşılığı YOKTUR, dolayısıyla BOM'lu ama
    # tamamen geçerli bir kaynak dosya ilk satırında `NA` üretir ve test onu
    # HATALI olarak reddederdi.
    if (length(satirlar)) {
      satirlar[1] <- sub("^\ufeff", "", satirlar[1], useBytes = FALSE)
    }
    cevrilen <- suppressWarnings(iconv(satirlar, from = "UTF-8", to = "WINDOWS-1254"))
    kotu <- which(is.na(cevrilen) & !is.na(satirlar))
    if (length(kotu)) kotu[1] else NA_integer_
  }, integer(1))

  sorunlu <- which(!is.na(kirik))

  # Hata mesajı doğrudan eyleme dönüştürülebilir olsun: dosya + ilk kırık satır.
  ayrinti <- if (length(sorunlu)) {
    paste0(
      "\n  - ",
      vapply(names(kirik)[sorunlu], function(yol) {
        onek <- paste0(kok, "/")
        if (startsWith(yol, onek)) substring(yol, nchar(onek) + 1L) else yol
      }, character(1)),
      " (satır ", kirik[sorunlu], ")",
      collapse = ""
    )
  } else ""

  testthat::expect_identical(
    length(sorunlu), 0L,
    info = paste0(
      "Aşağıdaki R dosyaları WINDOWS-1254'e çevrilemeyen karakter içeriyor ve ",
      "Windows VM'de `source(..., encoding = \"UTF-8\")` sırasında KESİLİR. ",
      "Dizelerde \"\\uXXXX\" kaçışı, yorumlarda ASCII karşılık kullanın:",
      ayrinti
    )
  )
})

# ==============================================================================
# KAÇIŞ + LİTERAL KARIŞIMI (test kaynaklarında)
# ==============================================================================
#
# NEDEN: `source(dosya, encoding = "UTF-8")` ayrıştırıcıya kaynağın UTF-8
# olduğunu BİLDİRİR; çalışma zamanı `R/` dosyaları bu yoldan yüklendiği için
# güvenlidir. Test dosyaları ise testthat tarafından bu bildirim OLMADAN
# ayrıştırılabilir. Böyle bir ayrıştırmada bir dize sabiti `\u`/`\U` kaçışı
# içeriyorsa R o sabiti UTF-8'e YÜKSELTMEK zorunda kalır ve AYNI sabitteki
# LİTERAL Türkçe baytları YEREL kodlama sanarak bir kez daha çevirir. Sonuç
# sessiz çift kodlamadır: `Veritabanı Hatası` -> `VeritabanÄ± HatasÄ±`. Emoji
# doğru görünmeye devam ettiği için kusur gözden kaçar; yalnızca Türkçe kısmı
# karşılaştıran sözleşme başarısız olur ve neden Windows VM'e özgüdür.
#
# ÇÖZÜM: kaçış ile literal Türkçe AYNI sabitte birleştirilmez; `paste0()` ile
# iki ayrı sabit olarak yazılır. Değer bayt düzeyinde AYNI kalır.
testthat::test_that("test kaynaklarında kaçış ve literal Türkçe aynı dizede birleşmez", {
  kok <- if (exists("repo_root_for_tests", inherits = TRUE)) {
    get("repo_root_for_tests", inherits = TRUE)
  } else {
    aday <- c(".", "..", "../..")
    uygun <- aday[vapply(
      aday,
      function(p) file.exists(file.path(p, "app.R")) && dir.exists(file.path(p, "R")),
      logical(1)
    )]
    testthat::skip_if(length(uygun) == 0L, "Repo kökü bulunamadı")
    normalizePath(uygun[1], winslash = "/", mustWork = TRUE)
  }

  dosyalar <- list.files(
    file.path(kok, "tests", "testthat"),
    pattern = "\\.[Rr]$", full.names = TRUE
  )
  testthat::expect_gt(length(dosyalar), 0L)

  # `"..."` VE `'...'` dize sabitleri (kaçırılmış tırnaklar dâhil) taranır. R
  # her iki tırnak biçimini de destekler; yalnızca çift tırnak taranırsa hem
  # `\u` kaçışı hem literal Türkçe içeren TEK TIRNAKLI bir dize sessizce
  # atlanır ve bulgu kaçırılırdı. Yorum SATIRLARI atlanır; satır içi yorumda
  # dize sabiti olabileceği için satırın tamamı değil yalnızca tümüyle yorum
  # olan satırlar elenir.
  dize_deseni <- "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'"
  kacis_deseni <- "\\\\[uU]\\{?[0-9A-Fa-f]{1,8}\\}?"

  bulgular <- character(0)
  for (yol in dosyalar) {
    ham <- readBin(yol, "raw", file.info(yol)$size)
    satirlar <- strsplit(
      iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte"),
      "\n", fixed = TRUE
    )[[1]]

    for (i in seq_along(satirlar)) {
      satir <- satirlar[i]
      if (grepl("^\\s*#", satir)) next

      dizeler <- regmatches(satir, gregexpr(dize_deseni, satir, perl = TRUE))[[1]]
      if (!length(dizeler)) next

      for (dize in dizeler) {
        if (!grepl(kacis_deseni, dize, perl = TRUE)) next
        kalan <- gsub(kacis_deseni, "", dize, perl = TRUE)
        if (grepl("[^\001-\177]", kalan, perl = TRUE)) {
          bulgular <- c(bulgular, sprintf(
            "%s (satır %d): %s", basename(yol), i, substr(dize, 1L, 90L)
          ))
        }
      }
    }
  }

  testthat::expect_identical(
    length(bulgular), 0L,
    info = paste0(
      "Aşağıdaki dize sabitleri hem \\u/\\U kaçışı hem LİTERAL Türkçe içeriyor; ",
      "Windows VM'de Türkçe kısım SESSİZCE çift kodlanır. `paste0()` ile ikiye ",
      "ayırın:\n  - ",
      paste(bulgular, collapse = "\n  - ")
    )
  )
})
