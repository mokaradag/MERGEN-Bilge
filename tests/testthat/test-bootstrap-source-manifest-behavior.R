# ==============================================================================
# Dosya Yolu: tests/testthat/test-bootstrap-source-manifest-behavior.R
# Açıklama: R/bootstrap_source_manifest.R saf manifest doğrulama yardımcılarının
#           DAVRANIŞSAL testleri. Bu dosya davranışsal olarak daha önce test
#           edilmiyordu (yalnızca yapısal sözleşme testlerinde adı geçiyordu).
#
#           Kapsananlar:
#           - source_manifest_validate_files(): boş/yinelenen/eksik dosya tespiti.
#           - source_manifest_validate_order(): kritik sıra kuralı ihlali tespiti.
#           - source_manifest_validate_order_rule_targets(): kural hedeflerinin
#             manifest/boot allowlist içinde olması.
#           - source_manifest_validate_parse(): UTF-8 parse doğrulaması.
#
#           Hatalar "Kaynak manifesti doğrulaması başarısız: ..." önekiyle gelir.
#           Yan etkisiz; gerçek uygulama yüklenmez. Geçici dosyalarla deterministik.
# ==============================================================================

.source_manifest_bootstrap_for_test <- function() {
  env <- new.env(parent = globalenv())
  source(
    file.path(resolve_repo_root_for_tests(), "R", "bootstrap_source_manifest.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# Geçici repo kökü altında gerçek R dosyaları üretir.
.make_manifest_repo <- function(files) {
  tmp <- withr::local_tempdir(.local_envir = parent.frame())
  for (rel in names(files)) {
    full <- file.path(tmp, rel)
    dir.create(dirname(full), recursive = TRUE, showWarnings = FALSE)
    writeLines(files[[rel]], full, useBytes = TRUE)
  }
  tmp
}

# ------------------------------------------------------------------------------
# source_manifest_validate_files
# ------------------------------------------------------------------------------
testthat::test_that("validate_files karakter olmayan veya boş manifesti reddeder", {
  env <- .source_manifest_bootstrap_for_test()
  testthat::expect_error(env$source_manifest_validate_files(NULL),
                         regexp = "karakter vektörü değil")
  testthat::expect_error(env$source_manifest_validate_files(character(0)),
                         regexp = "karakter vektörü değil")
})

testthat::test_that("validate_files boş/yalnızca-boşluk dosya yolunu reddeder", {
  env <- .source_manifest_bootstrap_for_test()
  testthat::expect_error(
    env$source_manifest_validate_files(c("R/a.R", "   ")),
    regexp = "boş dosya yolu"
  )
})

testthat::test_that("validate_files yinelenen dosya yollarını reddeder", {
  env <- .source_manifest_bootstrap_for_test()
  repo <- .make_manifest_repo(list("R/a.R" = "x <- 1", "R/b.R" = "y <- 2"))
  testthat::expect_error(
    env$source_manifest_validate_files(c("R/a.R", "R/b.R", "R/a.R"), repo_root = repo),
    regexp = "tekrar eden kaynak dosya"
  )
})

testthat::test_that("validate_files eksik dosyaları açık adla raporlar", {
  env <- .source_manifest_bootstrap_for_test()
  repo <- .make_manifest_repo(list("R/a.R" = "x <- 1"))
  testthat::expect_error(
    env$source_manifest_validate_files(c("R/a.R", "R/yok.R"), repo_root = repo),
    regexp = "eksik kaynak dosya"
  )
})

testthat::test_that("validate_files tüm dosyalar mevcutsa TRUE döner", {
  env <- .source_manifest_bootstrap_for_test()
  repo <- .make_manifest_repo(list("R/a.R" = "x <- 1", "R/b.R" = "y <- 2"))
  testthat::expect_true(env$source_manifest_validate_files(c("R/a.R", "R/b.R"), repo_root = repo))
})

# ------------------------------------------------------------------------------
# source_manifest_validate_order
# ------------------------------------------------------------------------------
testthat::test_that("validate_order boş kural listesinde TRUE döner", {
  env <- .source_manifest_bootstrap_for_test()
  testthat::expect_true(env$source_manifest_validate_order(c("R/a.R", "R/b.R"), list()))
})

testthat::test_that("validate_order doğru sırada TRUE, ihlalde hata verir", {
  env <- .source_manifest_bootstrap_for_test()
  paths <- c("R/a.R", "R/b.R", "R/c.R")
  # a, b'den önce -> doğru.
  testthat::expect_true(
    env$source_manifest_validate_order(paths, list(c("R/a.R", "R/b.R")))
  )
  # c, a'dan önce yüklenmeli kuralı ama c sonra geliyor -> ihlal.
  testthat::expect_error(
    env$source_manifest_validate_order(paths, list(c("R/c.R", "R/a.R"))),
    regexp = "yanlış kaynak sırası"
  )
})

testthat::test_that("validate_order manifestte olmayan kural hedeflerinde sıra kontrolünü atlar", {
  env <- .source_manifest_bootstrap_for_test()
  paths <- c("R/a.R", "R/b.R")
  # Kuraldaki R/x.R manifestte yok -> sıra karşılaştırması atlanır, TRUE.
  testthat::expect_true(
    env$source_manifest_validate_order(paths, list(c("R/a.R", "R/x.R")))
  )
})

testthat::test_that("validate_order geçersiz kural tanımını (uzunluk != 2) reddeder", {
  env <- .source_manifest_bootstrap_for_test()
  testthat::expect_error(
    env$source_manifest_validate_order(c("R/a.R"), list("R/a.R")),
    regexp = "geçersiz sıra kuralı"
  )
})

# ------------------------------------------------------------------------------
# source_manifest_validate_order_rule_targets
# ------------------------------------------------------------------------------
testthat::test_that("validate_order_rule_targets manifest dışı hedefi reddeder", {
  env <- .source_manifest_bootstrap_for_test()
  testthat::expect_error(
    env$source_manifest_validate_order_rule_targets(
      paths = c("R/a.R", "R/b.R"),
      order_rules = list(c("R/a.R", "R/dishedef.R"))
    ),
    regexp = "manifest/boot allowlist dışında"
  )
})

testthat::test_that("validate_order_rule_targets optional_paths ile karşılanan hedefi kabul eder", {
  env <- .source_manifest_bootstrap_for_test()
  testthat::expect_true(
    env$source_manifest_validate_order_rule_targets(
      paths = c("R/a.R"),
      order_rules = list(c("R/a.R", "R/boot.R")),
      optional_paths = c("R/boot.R")
    )
  )
})

# ------------------------------------------------------------------------------
# source_manifest_validate_parse
# ------------------------------------------------------------------------------
testthat::test_that("validate_parse geçerli R dosyalarında TRUE döner", {
  env <- .source_manifest_bootstrap_for_test()
  repo <- .make_manifest_repo(list("R/ok.R" = c("f <- function(x) {", "  x + 1", "}")))
  testthat::expect_true(env$source_manifest_validate_parse("R/ok.R", repo_root = repo))
})

testthat::test_that("validate_parse söz dizimi hatalı dosyayı reddeder", {
  env <- .source_manifest_bootstrap_for_test()
  repo <- .make_manifest_repo(list("R/bozuk.R" = c("f <- function(x {", "  x + 1")))
  testthat::expect_error(
    env$source_manifest_validate_parse("R/bozuk.R", repo_root = repo),
    regexp = "parse edilemedi"
  )
})
