# ==============================================================================
# Dosya Yolu: tests/testthat/test-misc-runtime-predicates-behavior.R
# Açıklama: Küçük ama davranışsal test edilmemiş runtime yardımcıları:
#           - utils_path_helpers.R .path_text_encoding_helper_available()
#           - helpers_file_manager_runtime.R .fm_runtime_is_reactivevalues()
#           - config_ui_asset_zones.R ui_asset_zone_get()
#           Hepsi saf/deterministik; gerçek DB/ağ/dosya gerektirmez.
# ==============================================================================

suppressMessages(library(shiny))

.miscPredicatesSource <- function(rel_path) {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), rel_path), encoding = "UTF-8", local = env)
  env
}

testthat::test_that(".path_text_encoding_helper_available normalize_text_utf8 görünürlüğünü yansıtır", {
  env <- .miscPredicatesSource("R/utils_path_helpers.R")
  f <- env$.path_text_encoding_helper_available

  # Arama yolunda normalize_text_utf8 yokken FALSE (fonksiyon ortamını izole et)
  bos_env <- new.env(parent = baseenv())
  environment(f) <- bos_env
  testthat::expect_false(f())

  # normalize_text_utf8 görünür olduğunda TRUE
  dolu_env <- new.env(parent = baseenv())
  dolu_env$normalize_text_utf8 <- function(value, ...) value
  environment(f) <- dolu_env
  testthat::expect_true(f())

  # Fonksiyon (mode='function') değil de değişkense yine FALSE
  degisken_env <- new.env(parent = baseenv())
  degisken_env$normalize_text_utf8 <- "ben bir metnim"
  environment(f) <- degisken_env
  testthat::expect_false(f())
})

testthat::test_that(".fm_runtime_is_reactivevalues yalnızca reactivevalues için TRUE döner", {
  env <- .miscPredicatesSource("R/helpers_file_manager_runtime.R")
  f <- env$.fm_runtime_is_reactivevalues

  rv <- shiny::reactiveValues(a = 1)
  testthat::expect_true(f(rv))

  testthat::expect_false(f(list(a = 1)))
  testthat::expect_false(f(NULL))
  testthat::expect_false(f(data.frame(x = 1)))
  testthat::expect_false(f("metin"))
})

testthat::test_that("ui_asset_zone_get geçerli id'de bölgeyi döndürür, geçersizde durur", {
  env <- .miscPredicatesSource("R/config_ui_asset_zones.R")
  f <- env$ui_asset_zone_get

  ornek <- list(
    benim_bolge = list(title = "Test", owner_seam = "frontend_varlik")
  )

  zone <- f("benim_bolge", zones = ornek)
  testthat::expect_identical(zone$title, "Test")
  testthat::expect_identical(zone$owner_seam, "frontend_varlik")

  # Geçersiz id türleri durdurur
  testthat::expect_error(f("", zones = ornek), "boş olmayan karakter")
  testthat::expect_error(f(c("a", "b"), zones = ornek), "boş olmayan karakter")
  testthat::expect_error(f(42L, zones = ornek), "boş olmayan karakter")

  # Bilinmeyen id açıklayıcı mesajla durdurur
  testthat::expect_error(f("yok_boyle_bir_bolge", zones = ornek), "bulunamadı")
})

testthat::test_that("ui_asset_zone_get gerçek sahiplik haritasından bilinen bölgeyi çözer", {
  env <- .miscPredicatesSource("R/config_ui_asset_zones.R")
  # Varsayılan zones = ui_asset_ownership_zones (aynı dosyada tanımlı)
  zone <- env$ui_asset_zone_get("vendor_codemirror")
  testthat::expect_identical(zone$owner_seam, "frontend_varlik")
  testthat::expect_true("codemirror" %in% zone$css_groups)
})
