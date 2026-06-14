# ==============================================================================
# Dosya Yolu: tests/testthat/test-config-packages-attach-behavior.R
# Açıklama: config_packages.R içindeki attach_required_packages davranışını
#           doğrular. Bu yardımcı verilen paket listesindeki her paketi
#           library(..., character.only = TRUE) ile yükler. library() env'e
#           kaydedici stub edilir; gerçek paket yüklemesi YOKTUR. Kaynak-zamanı
#           validate + stop + attach yan etkileri tryCatch ile yutulur (fonksiyon
#           tanımı stop'tan ÖNCE gelir, env'de kalır). Çevrimdışı, deterministik.
# ==============================================================================

# Türkçe yorum: config_packages.R'yi library() stub'lı ortama yükler. Kaynak-zamanı
# validate_required_packages eksik paket bulursa stop eder; bu tryCatch ile yutulur
# ve attach_required_packages tanımı (stop'tan önce) env'de kalır. library stub'ı
# tüm çağrıları kaydeder.
.configPackagesEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  rec <- new.env(parent = emptyenv())
  rec$pkgs <- character(0)
  rec$char_only <- logical(0)
  env$library <- function(package, character.only = FALSE, ...) {
    rec$pkgs <- c(rec$pkgs, as.character(package)[1])
    rec$char_only <- c(rec$char_only, isTRUE(character.only))
    invisible(TRUE)
  }
  suppressWarnings(suppressMessages(tryCatch(
    source(file.path(kok, "R", "config_packages.R"), encoding = "UTF-8", local = env),
    error = function(e) NULL
  )))
  list(env = env, rec = rec)
}

test_that("attach_required_packages config_packages.R sourcing sonrası tanımlıdır", {
  h <- .configPackagesEnv()
  expect_true(is.function(h$env$attach_required_packages))
})

test_that("attach_required_packages verilen her paketi character.only=TRUE ile yükler", {
  h <- .configPackagesEnv()
  h$rec$pkgs <- character(0)       # kaynak-zamanı attach gürültüsünü sıfırla
  h$rec$char_only <- logical(0)
  h$env$attach_required_packages(c("alpha", "beta", "gamma"))
  expect_identical(h$rec$pkgs, c("alpha", "beta", "gamma"))
  # Türkçe yorum: her çağrıda character.only = TRUE geçirilmeli (string paket adı)
  expect_true(all(h$rec$char_only))
})

test_that("attach_required_packages paket sırasını korur", {
  h <- .configPackagesEnv()
  h$rec$pkgs <- character(0)
  h$env$attach_required_packages(c("zeta", "alpha"))
  expect_identical(h$rec$pkgs, c("zeta", "alpha"))
})

test_that("attach_required_packages varsayılan required_packages listesini kullanır", {
  h <- .configPackagesEnv()
  h$rec$pkgs <- character(0)
  h$env$attach_required_packages()  # varsayılan = env$required_packages (gerçek manifest)
  # Türkçe yorum: manifest boş değildir; bilinen çekirdek paketler listede olmalı
  expect_true(length(h$rec$pkgs) > 0)
  expect_true("shiny" %in% h$rec$pkgs)
  expect_true("jsonlite" %in% h$rec$pkgs)
})
