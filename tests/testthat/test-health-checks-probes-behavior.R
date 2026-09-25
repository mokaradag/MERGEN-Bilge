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
  source(file.path(kok, "R", "helpers_health_endpoint_scope.R"), encoding = "UTF-8", local = env)
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

test_that("yapılandırılmamış genel internet adresi çağrılmadan atlanır (warning)", {
  skip_if_not_installed("httr")
  env <- .fresh_health_env()
  withr::local_envvar(c(LOCAL_LLM_ENDPOINT = "http://test.local/v1",
                        MERGEN_HEALTH_INTERNAL_ENDPOINTS = ""))
  testthat::local_mocked_bindings(
    GET = function(url, ...) stop("genel adres çağrılmamalıydı"),
    .package = "httr"
  )
  r <- env$health_check_http_endpoint("dis.test", "Dış Servis", "http://dis-servis.example.com/v1")
  expect_identical(r$status[1], "warning")
  expect_identical(r$value[1], "Atlandı")
})

# .Renviron.example sözleşmesi: LOCAL_*_ENDPOINT / IMAGE_GEN_ENDPOINT /
# LANGFLOW_BASE_URL / SSO_KEYCLOAK_URL otomatik on-prem sayılır. Kurumsal DNS
# adındaki (ör. *.com.tr) yapılandırılmış uç noktalar eskiden "Genel internet
# adresi" diye atlanıyor ve Tanılama sekmesinde yanlış uyarı üretiyordu.
test_that("yapılandırılmış LOCAL_LLM_ENDPOINT kurumsal DNS adıyla gerçekten denenir", {
  skip_if_not_installed("httr")
  env <- .fresh_health_env()
  withr::local_envvar(c(LOCAL_LLM_ENDPOINT = "https://llm.kurum.com.tr/v1/chat/completions",
                        MERGEN_HEALTH_INTERNAL_ENDPOINTS = ""))
  cagrilan <- character(0)
  testthat::local_mocked_bindings(
    GET = function(url, ...) {
      cagrilan <<- c(cagrilan, url)
      structure(list(), class = "response")
    },
    status_code = function(res) 200L,
    timeout = function(...) NULL,
    .package = "httr"
  )
  r <- env$health_check_llm_endpoint()
  expect_identical(r$status[1], "ok")
  expect_identical(cagrilan, "https://llm.kurum.com.tr/v1/models")
})

test_that("TTS/STT/görsel/SSO uç noktalarının hostları otomatik on-prem sayılır", {
  env <- .fresh_health_env()
  withr::local_envvar(c(
    LOCAL_TTS_ENDPOINT = "https://ses.kurum.com.tr/v1",
    LOCAL_STT_ENDPOINT = "https://yazi.kurum.gov.tr:8443/v1/audio/transcriptions",
    IMAGE_GEN_ENDPOINT = "https://gorsel.kurum.com.tr/v1/images/generations",
    SSO_KEYCLOAK_URL = "https://sso.kurum.com.tr/realms/x",
    MERGEN_HEALTH_INTERNAL_ENDPOINTS = ""
  ))
  expect_false(env$health_is_public_url("https://ses.kurum.com.tr/v1"))
  expect_false(env$health_is_public_url("https://yazi.kurum.gov.tr:8443/health"))
  expect_false(env$health_is_public_url("https://gorsel.kurum.com.tr/v1/images/generations"))
  expect_false(env$health_is_public_url("https://sso.kurum.com.tr/realms/x"))
  expect_true(env$health_is_public_url("https://api.example.com/v1"))
})

test_that("api_config LLM uç nokta listesi de on-prem host kümesine girer", {
  env <- .fresh_health_env()
  withr::local_envvar(c(MERGEN_HEALTH_INTERNAL_ENDPOINTS = ""))
  env$api_config <- list(local_llm_endpoints = list(buyuk = "https://model2.kurum.com.tr/v1/chat/completions"))
  expect_false(env$health_is_public_url("https://model2.kurum.com.tr/v1/models"))
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

test_that("joker bağlama adresli uç nokta yerel döngü adresinden denenir", {
  env <- .fresh_health_env()
  cagrilan <- character(0)
  testthat::local_mocked_bindings(
    GET = function(url, ...) {
      cagrilan <<- c(cagrilan, url)
      structure(list(), class = "response")
    },
    status_code = function(res) 200L,
    timeout = function(...) NULL,
    .package = "httr"
  )
  r <- env$health_check_http_endpoint("tts.endpoint", "TTS", "http://0.0.0.0:9000/health")
  expect_identical(r$status[1], "ok")
  env$health_check_http_endpoint("stt.endpoint", "STT", "http://[::]:9001/v1")
  expect_identical(cagrilan, c("http://127.0.0.1:9000/health", "http://[::1]:9001/v1"))
  # Joker olmayan adresler ve benzer görünen hostlar değişmez.
  expect_identical(env$health_probe_url("http://0.0.0.01:80/x"), "http://0.0.0.01:80/x")
  expect_identical(env$health_probe_url("https://10.0.0.5:8443/v1"), "https://10.0.0.5:8443/v1")
  expect_identical(env$health_probe_url("http://0.0.0.0"), "http://127.0.0.1")
})

test_that("yüzde kodlu genel host adı intranet sayılmaz", {
  env <- .fresh_health_env()
  withr::local_envvar(c(MERGEN_HEALTH_INTERNAL_ENDPOINTS = ""))
  expect_identical(env$health_url_host("https://public%2eexample%2ecom/"), "public.example.com")
  expect_true(env$health_is_public_url("https://public%2eexample%2ecom/"))
  expect_true(env$health_is_public_url("https://PUBLIC%2EEXAMPLE%2ECOM/v1"))
  # Tek etiketli intranet adı ve IPv6 bölge kimliği davranışı değişmez.
  expect_false(env$health_is_public_url("http://intranet-servis:8080/v1"))
  expect_false(env$health_is_public_url("http://[fe80::1%25eth0]:8080/v1"))
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

# -----------------------------------------------------------------------------
# host sınıflandırma (sondaki DNS kök noktası + IPv4-eşlemeli IPv6)
# -----------------------------------------------------------------------------

test_that("health_url_host sondaki DNS kök noktasını kaldırır", {
  env <- .fresh_health_env()

  expect_identical(env$health_url_host("https://service.local./v1"), "service.local")
  expect_identical(env$health_url_host("https://servis.intranet.:8443/x"), "servis.intranet")
  # Dahili son ek testi artık düşmez; canlı sonda atlanmaz.
  expect_false(env$health_is_public_url("https://service.local./v1"))
  expect_false(env$health_is_public_url("https://servis.intranet.:8443/x"))
  # Genel adres sondaki noktayla da genel kalır.
  expect_true(env$health_is_public_url("https://api.example.com./v1"))
})

test_that("IPv4-eşlemeli IPv6 gömülü IPv4 kuralıyla sınıflandırılır", {
  env <- .fresh_health_env()

  expect_true(isTRUE(env$health_ip_literal_internal("::ffff:127.0.0.1")))
  expect_true(isTRUE(env$health_ip_literal_internal("::ffff:10.0.0.1")))
  expect_true(isTRUE(env$health_ip_literal_internal("0:0:0:0:0:ffff:192.168.1.5")))
  expect_false(isTRUE(env$health_ip_literal_internal("::ffff:8.8.8.8")))

  expect_false(env$health_is_public_url("http://[::ffff:127.0.0.1]:8080/v1"))
  expect_false(env$health_is_public_url("http://[::ffff:10.0.0.1]:8080/v1"))
  expect_true(env$health_is_public_url("http://[::ffff:8.8.8.8]:8080/v1"))

  # Gerçek (eşlemeli olmayan) IPv6 davranışı DEĞİŞMEZ.
  expect_true(isTRUE(env$health_ip_literal_internal("fd00::1")))
  expect_true(is.na(env$health_ip_literal_internal("2001:db8::1")))
})