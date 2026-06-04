# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-manager-session-registry-behavior.R
# Açıklama: R/helpers_file_manager_session_registry.R oturum dosya kayıt defteri
#           yardımcılarının davranış testleri. Bu yardımcılar daha önce doğrudan
#           test edilmiyordu. Gerçek Shiny oturumu, DB veya dosya sistemi
#           GEREKMEZ; sahte environment-tabanlı oturum kullanılır.
# ==============================================================================

.source_fm_registry <- function() {
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_file_manager_session_registry.R"),
    encoding = "UTF-8", local = env
  )
  env
}

# Environment-tabanlı sahte oturum: userData bir environment olduğundan
# içindeki current_session_files referansla güncellenebilir.
.fake_session <- function(with_userdata = TRUE) {
  s <- new.env()
  if (isTRUE(with_userdata)) {
    s$userData <- new.env()
  } else {
    s$userData <- NULL
  }
  s
}

testthat::test_that(".fm_registry_chr boş/NA/NULL için default döndürür", {
  env <- .source_fm_registry()
  testthat::expect_identical(env$.fm_registry_chr(NULL, default = "x"), "x")
  testthat::expect_identical(env$.fm_registry_chr(NA, default = "x"), "x")
  testthat::expect_identical(env$.fm_registry_chr(character(0), default = "x"), "x")
  testthat::expect_identical(env$.fm_registry_chr("   ", default = "yedek"), "yedek")
})

testthat::test_that(".fm_registry_chr geçerli değeri trimler ve döndürür", {
  env <- .source_fm_registry()
  testthat::expect_identical(env$.fm_registry_chr("  rapor.xlsx "), "rapor.xlsx")
  # İlk eleman alınır.
  testthat::expect_identical(env$.fm_registry_chr(c("ilk", "ikinci")), "ilk")
})

testthat::test_that("fm_session_registry_entry geçerli girdi için tam giriş üretir", {
  env <- .source_fm_registry()
  entry <- env$fm_session_registry_entry("Türkçe_dosya.xlsx", "/veri/Türkçe_dosya.xlsx")
  testthat::expect_type(entry, "list")
  testthat::expect_identical(entry$name, "Türkçe_dosya.xlsx")
  testthat::expect_identical(entry$datapath, "/veri/Türkçe_dosya.xlsx")
  testthat::expect_identical(entry$path, "/veri/Türkçe_dosya.xlsx")
  testthat::expect_identical(entry$persisted_path, "/veri/Türkçe_dosya.xlsx")
})

testthat::test_that("fm_session_registry_entry eksik isim/yol için NULL döndürür", {
  env <- .source_fm_registry()
  testthat::expect_null(env$fm_session_registry_entry("", "/veri/x.xlsx"))
  testthat::expect_null(env$fm_session_registry_entry("x.xlsx", ""))
  testthat::expect_null(env$fm_session_registry_entry(NULL, NULL))
})

testthat::test_that("fm_normalize_session_registry_path var olmayan yolu normalize eder ve slash çevirir", {
  env <- .source_fm_registry()
  norm <- env$fm_normalize_session_registry_path(
    "C:\\Kullanici\\rapor.xlsx",
    path_exists_fn = function(p) FALSE,
    normalize_path_fn = function(p) p
  )
  testthat::expect_identical(norm, "C:/Kullanici/rapor.xlsx")
})

testthat::test_that("fm_normalize_session_registry_path var olan yolu olduğu gibi (slash çevrilmiş) korur", {
  env <- .source_fm_registry()
  norm <- env$fm_normalize_session_registry_path(
    "/veri/var.xlsx",
    path_exists_fn = function(p) TRUE,
    normalize_path_fn = function(p) stop("çağrılmamalı")
  )
  testthat::expect_identical(norm, "/veri/var.xlsx")
})

testthat::test_that("fm_ensure_session_registry eksik kayıt defterini başlatır", {
  env <- .source_fm_registry()
  s <- .fake_session()
  res <- env$fm_ensure_session_registry(s)
  testthat::expect_true(res)
  testthat::expect_true(is.list(s$userData$current_session_files))
  testthat::expect_length(s$userData$current_session_files, 0L)
})

testthat::test_that("fm_ensure_session_registry mevcut listeyi korur (FALSE döner)", {
  env <- .source_fm_registry()
  s <- .fake_session()
  s$userData$current_session_files <- list(a = list(name = "a"))
  res <- env$fm_ensure_session_registry(s)
  testthat::expect_false(res)
  testthat::expect_length(s$userData$current_session_files, 1L)
})

testthat::test_that("fm_register_session_file kayıt ekler ve sonra kaldırır", {
  env <- .source_fm_registry()
  s <- .fake_session()

  ok <- env$fm_register_session_file(
    s, "rapor.xlsx", "/veri/rapor.xlsx",
    path_exists_fn = function(p) TRUE,
    normalize_path_fn = function(p) p
  )
  testthat::expect_true(ok)
  testthat::expect_true("rapor.xlsx" %in% names(s$userData$current_session_files))
  testthat::expect_identical(s$userData$current_session_files[["rapor.xlsx"]]$datapath, "/veri/rapor.xlsx")

  removed <- env$fm_unregister_session_file(s, "rapor.xlsx")
  testthat::expect_true(removed)
  testthat::expect_false("rapor.xlsx" %in% names(s$userData$current_session_files))
})

testthat::test_that("fm_register_session_file userData yoksa güvenli FALSE döner", {
  env <- .source_fm_registry()
  s <- .fake_session(with_userdata = FALSE)
  ok <- env$fm_register_session_file(s, "x.xlsx", "/veri/x.xlsx")
  testthat::expect_false(ok)
})

testthat::test_that("fm_register_session_file boş dosya adında FALSE döner", {
  env <- .source_fm_registry()
  s <- .fake_session()
  ok <- env$fm_register_session_file(s, "  ", "/veri/x.xlsx")
  testthat::expect_false(ok)
  testthat::expect_null(s$userData$current_session_files)
})
