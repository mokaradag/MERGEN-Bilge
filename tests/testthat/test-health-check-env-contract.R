# ==============================================================================
# Dosya Yolu: tests/testthat/test-health-check-env-contract.R
# Açıklama: Sistem Durumu ortam değişkeni sözleşmesi ve gizli değer maskeleme
#            davranışını test eder.
# ==============================================================================

.bootstrap_health_env_tests <- function() {
  helper_candidates <- c("tests/testthat/helper_bootstrap.R", "testthat/helper_bootstrap.R", "helper_bootstrap.R")
  helper_path <- helper_candidates[file.exists(helper_candidates)][1]
  if (!is.na(helper_path) && nzchar(helper_path)) source(helper_path, encoding = "UTF-8", local = globalenv())
  if (!exists("resolve_repo_root_for_tests", mode = "function", inherits = TRUE)) {
    resolve_repo_root_for_tests <<- function() normalizePath(if (file.exists("app.R")) "." else "../..", winslash = "/", mustWork = TRUE)
  }
  repo_root <- resolve_repo_root_for_tests()
  source(file.path(repo_root, "R", "helpers_health_formatters.R"), encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_health_checks.R"), encoding = "UTF-8", local = globalenv())
}

.bootstrap_health_env_tests()

test_that("zorunlu ortam değişkeni yoksa kritik döner", {
  withr::local_envvar(c(LOCAL_LLM_ENDPOINT = ""))
  res <- health_check_env_var("LOCAL_LLM_ENDPOINT", required = TRUE)
  expect_identical(res$status[1], "critical")
})

test_that("opsiyonel ortam değişkeni yoksa tanımlı değil döner", {
  withr::local_envvar(c(LOCAL_TTS_ENDPOINT = ""))
  res <- health_check_env_var("LOCAL_TTS_ENDPOINT", required = FALSE)
  expect_identical(res$status[1], "not_configured")
})

test_that("gizli ortam değişkeni ham değeri sızdırmaz", {
  withr::local_envvar(c(AI_KEYS_MASTER = "abc-secret-123"))
  res <- health_check_env_var("AI_KEYS_MASTER", required = TRUE)
  expect_identical(res$status[1], "ok")
  expect_false(grepl("abc-secret-123", paste(res$value, res$detail), fixed = TRUE))
})

test_that("env contract required ve optional sonuçları üretir", {
  withr::local_envvar(c(LOCAL_LLM_ENDPOINT = "http://127.0.0.1:8000/v1", DB_DSN = "test", AI_KEYS_MASTER = "secret"))
  res <- health_check_env_contract(required = c("LOCAL_LLM_ENDPOINT", "DB_DSN", "AI_KEYS_MASTER"), optional = c("LOCAL_TTS_ENDPOINT"))
  expect_true(all(paste0("env.", c("LOCAL_LLM_ENDPOINT", "DB_DSN", "AI_KEYS_MASTER", "LOCAL_TTS_ENDPOINT")) %in% res$id))
  expect_false(any(grepl("secret", res$value, fixed = TRUE)))
})

# Regresyon: dahili adres sınıflandırması yalnızca ÖNEK eşleştirmesi yapıyordu.
test_that("health_is_public_url dahili IP literallerini doğru sınıflar", {
  withr::local_envvar(c(MERGEN_HEALTH_INTERNAL_ENDPOINTS = ""))

  # Tüm 127/8 loopback aralığı ve IPv4 bağlantı-yerel 169.254/16 dahilidir.
  expect_false(health_is_public_url("http://127.0.0.2:9000/v1/models"))
  expect_false(health_is_public_url("http://169.254.10.5:9000/v1/models"))
  # Genişletilmiş IPv6 loopback biçimi de dahilidir.
  expect_false(health_is_public_url("http://[0:0:0:0:0:0:0:1]:8080/v1/models"))
  expect_false(health_is_public_url("http://[::1]:8080/v1/models"))

  # Geçerli GENEL DNS adları IPv4 öneki taşısa bile dahili sayılmaz.
  expect_true(health_is_public_url("http://10.example.com/v1/models"))
  expect_true(health_is_public_url("http://192.168.example.com/v1/models"))
  expect_true(health_is_public_url("http://172.16.example.com/v1/models"))
  # 172.16-31 dışı IPv4 literali gerçekten geneldir.
  expect_true(health_is_public_url("http://172.32.0.1:9000/v1/models"))
  expect_false(health_is_public_url("http://172.16.0.1:9000/v1/models"))
})

test_that("public internet URL sağlık sayfası için zorunlu değildir", {
  expect_true(health_is_public_url("https://example.com/v1/models"))
  res <- health_check_http_endpoint("public.test", "Public Test", "https://example.com/v1/models", configured_required = FALSE)
  expect_identical(res$status[1], "warning")
  expect_match(res$detail[1], "public endpoint|Genel internet", ignore.case = TRUE)
})
