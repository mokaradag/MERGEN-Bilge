# ==============================================================================
# Dosya Yolu: tests/testthat/test-health-check-runtime-contract.R
# Açıklama: Sistem Durumu çalışma zamanı kontrollerinin temel sözleşmesini test eder.
# ==============================================================================

.bootstrap_health_runtime_tests <- function() {
  helper_candidates <- c("tests/testthat/helper_bootstrap.R", "testthat/helper_bootstrap.R", "helper_bootstrap.R")
  helper_path <- helper_candidates[file.exists(helper_candidates)][1]
  if (!is.na(helper_path) && nzchar(helper_path)) source(helper_path, encoding = "UTF-8", local = globalenv())
  if (!exists("resolve_repo_root_for_tests", mode = "function", inherits = TRUE)) {
    resolve_repo_root_for_tests <<- function() normalizePath(if (file.exists("app.R")) "." else "../..", winslash = "/", mustWork = TRUE)
  }
  repo_root <- resolve_repo_root_for_tests()
  source(file.path(repo_root, "R", "helpers_health_formatters.R"), encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_health_runtime_checks.R"), encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_health_checks.R"), encoding = "UTF-8", local = globalenv())
}

.bootstrap_health_runtime_tests()

test_that("runtime sağlık kontrol yardımcıları ayrı dosyadan public adlarla yüklenir", {
  expected <- c(
    "health_check_runtime_info",
    "health_check_worker_info",
    "health_check_package_sanity",
    "health_check_windows_info",
    "health_check_sso_mode",
    "health_check_git_version",
    "health_check_bilge_yolac"
  )

  expect_true(
    all(vapply(expected, exists, logical(1), mode = "function")),
    info = "Runtime sağlık kontrol fonksiyonları public adlarıyla yüklenmelidir."
  )
})

test_that("runtime kontrolleri zorunlu alanları döndürür", {
  fake_perf <- list(get_active_session_count = function() 3L)
  res <- health_check_runtime_info(fake_perf)
  required <- c("id", "label", "status", "severity", "value", "detail", "duration_ms", "checked_at", "remediation")
  expect_true(all(required %in% names(res)))
  expect_true("runtime.sessions" %in% res$id)
  expect_identical(res$value[match("runtime.sessions", res$id)], "3")
})

test_that("paket kontrolü eksik paket için critical döner", {
  res <- health_check_package_sanity(c("base", "paket_yok_olmamali_123"))
  expect_identical(res$status[1], "critical")
  expect_match(res$detail[1], "paket_yok_olmamali_123")
})

test_that("LLM models URL türetme dış internete bağımlı değildir", {
  expect_identical(health_derive_models_url("http://127.0.0.1:8000/v1/chat/completions"), "http://127.0.0.1:8000/v1/models")
  expect_identical(health_derive_models_url("http://localhost:8080"), "http://localhost:8080/v1/models")
})

test_that("SSO modu kontrolü lokal ve SSO durumlarını güvenli raporlar", {
  withr::local_envvar(c(SSO_ENABLED = "TRUE"))
  res_true <- health_check_sso_mode()
  expect_identical(res_true$status[1], "ok")
  expect_match(res_true$value[1], "SSO")

  withr::local_envvar(c(SSO_ENABLED = "FALSE"))
  res_false <- health_check_sso_mode()
  expect_identical(res_false$status[1], "ok")
  expect_match(res_false$value[1], "non-SSO")
})

test_that("Bilge Yolaç kontrolü yapılandırılmamışsa hata fırlatmaz", {
  withr::local_envvar(c(CLAUDE_CODE_CLI_PATH = "", BILGE_YOLAC_CLI_PATH = "", CLAUDE_CODE_DEFAULT_WORKDIR = "", BILGE_YOLAC_DEFAULT_WORKDIR = ""))
  res <- health_check_bilge_yolac()
  expect_true(res$status[1] %in% c("not_configured", "ok", "warning", "unknown"))
})