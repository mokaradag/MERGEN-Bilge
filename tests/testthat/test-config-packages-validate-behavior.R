# ==============================================================================
# Dosya Yolu: tests/testthat/test-config-packages-validate-behavior.R
# Açıklama: R/config_packages.R validate_required_packages() davranışsal testi.
#           Fonksiyon, namespace_checker FALSE dönen paketleri (eksik) döndürür.
#           Not: dosya kaynak yüklenirken üst düzeyde eksik paket varsa stop()
#           eder; ancak fonksiyon tanımları stop'tan ÖNCE yapıldığından kısmi
#           kaynak yüklemesi (hata yutulur) ile fonksiyon ortamda kalır.
# ==============================================================================

testthat::local_edition(3)

.cp_env <- new.env(parent = globalenv())
# Üst düzey "eksik paket -> stop" davranışını yut; fonksiyonlar zaten tanımlı kalır.
suppressWarnings(tryCatch(
  source(
    file.path(resolve_repo_root_for_tests(), "R", "config_packages.R"),
    encoding = "UTF-8",
    local = .cp_env
  ),
  error = function(e) invisible(NULL)
))

test_that("config_packages kısmi kaynak yüklemesi sonrası validate_required_packages tanımlıdır", {
  expect_true(is.function(.cp_env$validate_required_packages))
})

test_that("validate_required_packages enjekte edilen checker'a göre eksik paketleri döndürür", {
  # Hiçbiri eksik değil.
  expect_length(
    .cp_env$validate_required_packages(c("a", "b"), namespace_checker = function(pkg) TRUE),
    0
  )
  # Yalnızca 'b' mevcut; 'a' ve 'c' eksik döner (sıra korunur).
  expect_equal(
    .cp_env$validate_required_packages(c("a", "b", "c"), namespace_checker = function(pkg) pkg == "b"),
    c("a", "c")
  )
  # Hepsi eksik.
  expect_equal(
    .cp_env$validate_required_packages(c("x", "y"), namespace_checker = function(pkg) FALSE),
    c("x", "y")
  )
})

test_that("validate_required_packages varsayılan requireNamespace checker'ı ile gerçek paketleri çözer", {
  # base/stats/utils her zaman mevcuttur -> eksik yok.
  expect_length(
    .cp_env$validate_required_packages(
      c("base", "stats", "utils"),
      namespace_checker = function(pkg) requireNamespace(pkg, quietly = TRUE)
    ),
    0
  )
  # Var olmayan paket eksik olarak raporlanmalı.
  eksik <- .cp_env$validate_required_packages(
    c("base", "kesinlikleYokPaket_123"),
    namespace_checker = function(pkg) requireNamespace(pkg, quietly = TRUE)
  )
  expect_true("kesinlikleYokPaket_123" %in% eksik)
  expect_false("base" %in% eksik)
})
