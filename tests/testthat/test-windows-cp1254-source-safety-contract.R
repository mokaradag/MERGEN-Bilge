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

  kok_dosyalar <- list.files(kok, pattern = "\\.[Rr]$", full.names = TRUE)
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
