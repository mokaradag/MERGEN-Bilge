# ==============================================================================
# Dosya Yolu: tests/testthat/test-health-checks-probes-behavior.R
# Açıklama: R/helpers_health_checks.R sağlık probe fonksiyonlarının davranışsal
#           testleri. app boot, disk boş alan, DB bağlantı/şema, LLM endpoint ve
#           reasoning hazırlık kontrolleri stub'lı bağımlılıklarla doğrulanır.
#           Gerçek DB/ağ yoktur; get_connection/DBI/httr mock'lanır ve public
#           internet adresleri atlama sözleşmesi korunur.
# ==============================================================================

testthat::local_edition(3)

# Her test izole bir ortamda çalışsın diye sağlık dosyalarını taze ortama
# kaynaklayan kurucu. Parent olarak globalenv yerine yalnızca gerekli stub'ları
# taşıyan temiz bir ortam kullanılır; böylece tam suite koşumunda globalenv'e
# sızmış api_config / apply_model_request_overrides bu testlere bulaşamaz.
.fresh_health_env <- function() {
  kok <- resolve_repo_root_for_tests()
  temiz <- new.env(parent = baseenv())
  temiz[["%||%"]] <- function(x, y) if (is.null(x)) y else x
  temiz$log_info <- temiz$log_warn <- temiz$log_error <- temiz$log_debug <- function(...) invisible(NULL)
  env <- new.env(parent = temiz)
  source(file.path(kok, "R", "helpers_health_formatters.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_health_runtime_checks.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_health_checks.R"), encoding = "UTF-8", local = env)
  env
}

# Sağlık sonucu sözleşmesi: tek satırlık data.frame ve zorunlu alanlar.
.health_contract_ok <- function(res) {
  beklenen <- c("id", "label", "status", "severity", "value", "detail",
                "duration_ms", "checked_at", "remediation")
  all(beklenen %in% names(res)) && nrow(res) == 1L
}

# -----------------------------------------------------------------------------
# app boot
# -----------------------------------------------------------------------------

test_that("health_check_app_boot 'ok' durumu ve tam sonuç sözleşmesini döner", {
  env <- .fresh_health_env()
  r <- env$health_check_app_boot()
  expect_identical(r$status[1], "ok")
  expect_true(.health_contract_ok(r))
  expect_identical(r$id[1], "app.boot")
})

# -----------------------------------------------------------------------------
# disk boş alan (Linux df gerçek çalışır)
# -----------------------------------------------------------------------------

test_that("health_check_disk_free geçerli durum ve sözleşmeyle sonuç üretir", {
  env <- .fresh_health_env()
  r <- env$health_check_disk_free(path = tempdir())
  expect_true(r$status[1] %in% c("ok", "warning", "unknown"))
  expect_true(.health_contract_ok(r))
  expect_identical(r$id[1], "storage.disk_free")
})

# -----------------------------------------------------------------------------
# DB bağlantı
# -----------------------------------------------------------------------------

test_that("health_check_db_connection DSN tanımsızsa not_configured döner", {
  env <- .fresh_health_env()
  withr::local_envvar(c(DB_DSN = ""))
  r <- env$health_check_db_connection("primary", "DB_DSN", "DB P")
  expect_identical(r$status[1], "not_configured")
})

test_that("health_check_db_connection DSN var ama yardımcı yoksa unknown döner", {
  env <- .fresh_health_env()
  withr::local_envvar(c(DB_DSN = "fake-dsn"))
  r <- env$health_check_db_connection("primary", "DB_DSN", "DB P")
  expect_identical(r$status[1], "unknown")
})

test_that("health_check_db_connection mock bağlantı + SELECT 1 ile ok döner", {
  env <- .fresh_health_env()
  env$get_connection <- function(target) list(conn = structure(list(), class = "FakeConn"))
  env$release_connection <- function(x) invisible(NULL)
  withr::local_envvar(c(DB_DSN = "fake-dsn"))
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) data.frame(ok = 1L),
    .package = "DBI"
  )
  r <- env$health_check_db_connection("primary", "DB_DSN", "DB P")
  expect_identical(r$status[1], "ok")
})

test_that("health_check_db_connection bağlantı hatasında critical döner ve mesajı taşır", {
  env <- .fresh_health_env()
  env$get_connection <- function(target) stop("baglanti coktu")
  env$release_connection <- function(x) invisible(NULL)
  withr::local_envvar(c(DB_DSN = "fake-dsn"))
  r <- env$health_check_db_connection("primary", "DB_DSN", "DB P")
  expect_identical(r$status[1], "critical")
  expect_true(grepl("baglanti coktu", r$detail[1], fixed = TRUE))
})

# -----------------------------------------------------------------------------
# DB şema
# -----------------------------------------------------------------------------

test_that("health_check_db_schema tüm tablo/sütun varsa ok döner", {
  env <- .fresh_health_env()
  env$get_connection <- function(target) list(conn = structure(list(), class = "FakeConn"))
  env$release_connection <- function(x) invisible(NULL)
  withr::local_envvar(c(DB_DSN = "fake-dsn"))
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) data.frame(n = 1L),
    .package = "DBI"
  )
  r <- env$health_check_db_schema()
  expect_identical(r$status[1], "ok")
})

test_that("health_check_db_schema eksik tablo/sütun varsa warning döner", {
  env <- .fresh_health_env()
  env$get_connection <- function(target) list(conn = structure(list(), class = "FakeConn"))
  env$release_connection <- function(x) invisible(NULL)
  withr::local_envvar(c(DB_DSN = "fake-dsn"))
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) data.frame(n = 0L),
    .package = "DBI"
  )
  r <- env$health_check_db_schema()
  expect_identical(r$status[1], "warning")
  expect_true(grepl("eksik", r$value[1], fixed = TRUE))
})

test_that("health_check_db_schema bağlantı yoksa unknown döner", {
  env <- .fresh_health_env()
  withr::local_envvar(c(DB_DSN = ""))
  r <- env$health_check_db_schema()
  expect_identical(r$status[1], "unknown")
})

# -----------------------------------------------------------------------------
# LLM endpoint (public internet adresi atlama sözleşmesi)
# -----------------------------------------------------------------------------

test_that("health_check_llm_endpoint public internet adresini çağırmadan atlar (warning)", {
  env <- .fresh_health_env()
  # api_config yok; LOCAL_LLM_ENDPOINT public-benzeri bir host.
  withr::local_envvar(c(LOCAL_LLM_ENDPOINT = "http://dis-servis.example.com/v1"))
  r <- env$health_check_llm_endpoint()
  expect_identical(r$status[1], "warning")
  expect_identical(r$value[1], "Atlandı")
})

test_that("health_check_http_endpoint yerel uç noktada mock GET ile ok döner", {
  env <- .fresh_health_env()
  testthat::local_mocked_bindings(
    GET = function(url, ...) structure(list(), class = "response"),
    status_code = function(res) 200L,
    timeout = function(...) NULL,
    .package = "httr"
  )
  r <- env$health_check_http_endpoint("tts.endpoint", "TTS", "http://127.0.0.1:9000/health")
  expect_identical(r$status[1], "ok")
  expect_true(grepl("HTTP 200", r$value[1], fixed = TRUE))
})

test_that("health_check_http_endpoint boş uç nokta zorunlu değilse not_configured döner", {
  env <- .fresh_health_env()
  r <- env$health_check_http_endpoint("tts.endpoint", "TTS", "", configured_required = FALSE)
  expect_identical(r$status[1], "not_configured")
})

# -----------------------------------------------------------------------------
# Reasoning hazırlık
# -----------------------------------------------------------------------------

test_that("health_check_reasoning_readiness override eksiksiz thinking modelde ok döner", {
  env <- .fresh_health_env()
  env$apply_model_request_overrides <- function(body, model) body
  env$api_config <- list(local_model_capabilities = list(
    m1 = list(thinking = TRUE, request_overrides = list(chat_template_kwargs = list(enable_thinking = TRUE)))
  ))
  r <- env$health_check_reasoning_readiness()
  expect_identical(r$status[1], "ok")
})

test_that("health_check_reasoning_readiness override eksik thinking modelde warning döner", {
  env <- .fresh_health_env()
  env$apply_model_request_overrides <- function(body, model) body
  env$api_config <- list(local_model_capabilities = list(
    m2 = list(thinking = TRUE, request_overrides = list())
  ))
  r <- env$health_check_reasoning_readiness()
  expect_identical(r$status[1], "warning")
})

test_that("health_check_reasoning_readiness yardımcı fonksiyon yoksa critical döner", {
  env <- .fresh_health_env()
  # apply_model_request_overrides bilinçli olarak tanımlanmaz; temiz parent
  # sayesinde globalenv'den miras alınmaz, dolayısıyla critical beklenir.
  r <- env$health_check_reasoning_readiness()
  expect_identical(r$status[1], "critical")
})