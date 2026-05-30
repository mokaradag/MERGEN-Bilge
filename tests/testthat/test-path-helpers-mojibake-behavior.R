# ==============================================================================
# Dosya Yolu: tests/testthat/test-path-helpers-mojibake-behavior.R
# Açıklama: R/utils_path_helpers.R saf yol yardımcılarının DAVRANIŞSAL testleri.
#           Skaler yol normalleştirme, varlık kontrolü, Türkçe mojibake yol
#           tespiti/onarımı ve ortam değişkeni yol güvenliği gerçek üretim
#           fonksiyonları çağrılarak doğrulanır. Üretim onarım yolu
#           R/utils_text_encoding.R yardımcısını kullanır; bu yüzden o da yüklenir.
# ==============================================================================

.pathhelp_source_once <- function() {
  if (!exists("normalize_text_utf8", envir = globalenv(),
              mode = "function", inherits = TRUE)) {
    source(
      file.path(resolve_repo_root_for_tests(), "R", "utils_text_encoding.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  if (!exists("repair_turkish_mojibake_path", envir = globalenv(),
              mode = "function", inherits = TRUE)) {
    source(
      file.path(resolve_repo_root_for_tests(), "R", "utils_path_helpers.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  invisible(TRUE)
}

testthat::test_that(".as_scalar_path NULL/NA/boş/vektör girdiyi güvenle tek dizeye indirir", {
  .pathhelp_source_once()
  testthat::expect_identical(.as_scalar_path(NULL), "")
  testthat::expect_identical(.as_scalar_path(character(0)), "")
  testthat::expect_identical(.as_scalar_path(NA), "")
  testthat::expect_identical(.as_scalar_path(""), "")
  testthat::expect_identical(.as_scalar_path("C:/proje"), "C:/proje")
  # Vektörde ilk öğe alınır.
  testthat::expect_identical(.as_scalar_path(c("ilk", "ikinci")), "ilk")
})

testthat::test_that(".path_exists_any gerçek dosyayı bulur, olmayanı bulmaz", {
  .pathhelp_source_once()
  f <- tempfile(); file.create(f); on.exit(unlink(f), add = TRUE)
  testthat::expect_true(.path_exists_any(f))
  testthat::expect_false(.path_exists_any(file.path(tempdir(), "kesinlikle-yok-12345")))
  testthat::expect_false(.path_exists_any(""))
  testthat::expect_false(.path_exists_any(NULL))
})

testthat::test_that("path_has_turkish_mojibake bozuk Türkçe yolu tespit eder, temizi atlar", {
  .pathhelp_source_once()
  testthat::expect_true(path_has_turkish_mojibake("TÃ¼rkiye/dosya.pdf"))
  testthat::expect_true(path_has_turkish_mojibake("baÅŸkent_raporu.xlsx"))
  # Doğru Türkçe yol mojibake DEĞİL.
  testthat::expect_false(path_has_turkish_mojibake("Türkçe/dosya.pdf"))
  # Saf ASCII yol mojibake değil.
  testthat::expect_false(path_has_turkish_mojibake("C:/proje/rapor.pdf"))
  testthat::expect_false(path_has_turkish_mojibake(""))
})

testthat::test_that("repair_turkish_mojibake_path bozuk Türkçe yolu onarır", {
  .pathhelp_source_once()
  testthat::expect_identical(
    repair_turkish_mojibake_path("TÃ¼rkiye/dosya.pdf"),
    "Türkiye/dosya.pdf"
  )
  # Doğru yol değişmez.
  testthat::expect_identical(
    repair_turkish_mojibake_path("Türkçe/rapor.xlsx"),
    "Türkçe/rapor.xlsx"
  )
  testthat::expect_identical(repair_turkish_mojibake_path(""), "")
})

testthat::test_that(".build_fallback_mojibake_pair kod noktalarından bad/good çiftleri üretir", {
  .pathhelp_source_once()
  # 195,188 -> "Ã¼" (ü mojibake), 252 -> "ü"
  pair <- .build_fallback_mojibake_pair(c(195L, 188L), c(252L))
  testthat::expect_identical(pair$bad, "\U00C3\U00BC")
  testthat::expect_identical(pair$good, "\U00FC")  # ü
  # Yedek çift listesi boş olmamalı ve yapısı doğru olmalı.
  pairs <- .get_fallback_turkish_mojibake_pairs()
  testthat::expect_true(length(pairs) >= 10L)
  testthat::expect_true(all(vapply(pairs, function(p) all(c("bad", "good") %in% names(p)), logical(1))))
})

testthat::test_that("read_env_path_safe mojibake ortam yolunu onarır, temizi ve boşu doğru işler", {
  .pathhelp_source_once()
  var <- "MERGEN_TEST_PATH_MOJIBAKE_VAR"
  old <- Sys.getenv(var, unset = NA)
  on.exit({
    if (is.na(old)) Sys.unsetenv(var) else Sys.setenv(MERGEN_TEST_PATH_MOJIBAKE_VAR = old)
  }, add = TRUE)

  # Bozuk Türkçe değer onarılır (disk üzerinde yok -> onarılmış döner).
  Sys.setenv(MERGEN_TEST_PATH_MOJIBAKE_VAR = "/veri/TÃ¼rkiye_klasoru")
  testthat::expect_identical(
    read_env_path_safe(var, fallback = "/yedek"),
    "/veri/Türkiye_klasoru"
  )

  # Temiz değer aynen döner.
  Sys.setenv(MERGEN_TEST_PATH_MOJIBAKE_VAR = "/veri/duz_klasor")
  testthat::expect_identical(read_env_path_safe(var, fallback = "/yedek"), "/veri/duz_klasor")

  # Tanımsız değişken fallback döndürür.
  Sys.unsetenv(var)
  testthat::expect_identical(read_env_path_safe(var, fallback = "/yedek"), "/yedek")
})

testthat::test_that("safe_windows_short_path Windows dışında yolu değiştirmeden döndürür", {
  .pathhelp_source_once()
  # Linux/Mac'te (test ortamı) yol olduğu gibi döner.
  if (.Platform$OS.type != "windows") {
    testthat::expect_identical(safe_windows_short_path("/home/user/proje"), "/home/user/proje")
  } else {
    testthat::skip("Windows-özel davranış bu ortamda test edilmiyor")
  }
})
