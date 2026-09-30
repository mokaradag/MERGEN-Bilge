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
  # DNS'e hiç gidilmez: genel ad doğrudan "genel_dns" nedeniyle atlanır.
  env$health_resolve_host_ips <- function(host) stop("DNS çağrılmamalıydı")
  expect_identical(env$health_endpoint_scope("http://dis-servis.example.com/v1")$neden, "genel_dns")
  r <- env$health_check_http_endpoint("dis.test", "Dış Servis", "http://dis-servis.example.com/v1")
  expect_identical(r$status[1], "warning")
  expect_identical(r$value[1], "Atlandı")
})

# .Renviron.example sözleşmesi: LOCAL_*_ENDPOINT / IMAGE_GEN_ENDPOINT /
# LANGFLOW_BASE_URL / SSO_KEYCLOAK_URL. Kurumsal DNS adındaki (ör. *.com.tr)
# yapılandırılmış uç noktalar eskiden "Genel internet adresi" diye atlanıyordu;
# yalnız özel adreslere çözülürse denenir (DNS testte sahtelenir).
test_that("yapılandırılmış LOCAL_LLM_ENDPOINT kurumsal DNS adıyla gerçekten denenir", {
  skip_if_not_installed("httr")
  env <- .fresh_health_env()
  env$health_resolve_host_ips <- function(host) "10.20.30.40"
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

  # Yapılandırılmış ama GENEL adrese çözülen uç noktaya istek gönderilmez.
  env2 <- .fresh_health_env()
  env2$health_resolve_host_ips <- function(host) c("10.0.0.5", "8.8.8.8")
  r2 <- env2$health_check_llm_endpoint()
  expect_identical(cagrilan, "https://llm.kurum.com.tr/v1/models")
  expect_true(grepl("Genel internet", r2$detail[1], fixed = TRUE))
})

test_that("yapılandırılmış olmak tek başına on-prem sayılmaz; DNS kanıtı önbelleklenir", {
  env <- .fresh_health_env()
  sorgu <- 0L
  env$health_resolve_host_ips <- function(host) {
    sorgu <<- sorgu + 1L
    switch(host, "ozel.kurum.com.tr" = "172.16.4.2", "genel.example.com" = "93.184.216.34",
           "sinkhole.example.com" = "0.0.0.0", character(0))
  }
  withr::local_envvar(c(
    LOCAL_TTS_ENDPOINT = "https://ozel.kurum.com.tr/v1",
    LOCAL_STT_ENDPOINT = "https://genel.example.com/v1",
    IMAGE_GEN_ENDPOINT = "https://yok.example.com/v1",
    LANGFLOW_BASE_URL = "https://sinkhole.example.com",
    SSO_KEYCLOAK_URL = "https://8.8.4.4/realms/x",
    MERGEN_HEALTH_INTERNAL_ENDPOINTS = ""
  ))
  expect_false(env$health_is_public_url("https://ozel.kurum.com.tr/v1"))
  expect_true(env$health_is_public_url("https://genel.example.com/v1"))
  expect_true(env$health_is_public_url("https://yok.example.com/v1"))
  expect_true(env$health_is_public_url("https://sinkhole.example.com/"))
  expect_true(env$health_is_public_url("https://8.8.4.4/realms/x"))
  # Yapılandırılmamış host için DNS sorgusu yapılmaz; genel çıkan sonuç önbellekten gelir.
  once <- sorgu
  expect_true(env$health_is_public_url("https://baska.example.com/v1"))
  expect_true(env$health_is_public_url("https://genel.example.com/v1"))
  expect_identical(sorgu, once)
  # Özel karar yalnız bir yenileme aralığı tutulur; süre dolunca yeniden çözülür.
  expect_false(env$health_is_public_url("https://ozel.kurum.com.tr/health"))
  expect_identical(sorgu, once)
  expect_identical(env$health_host_private_ips("ozel.kurum.com.tr", kisa_ttl = 0), "172.16.4.2")
  expect_identical(sorgu, once + 1L)
  # Operatörün açık ilanı DNS'ten bağımsız geçerlidir.
  withr::local_envvar(c(MERGEN_HEALTH_INTERNAL_ENDPOINTS = "genel.example.com"))
  expect_false(env$health_is_public_url("https://genel.example.com/v1"))
})

test_that("TTS/STT/görsel/SSO uç noktalarının hostları özel adrese çözülünce on-prem sayılır", {
  env <- .fresh_health_env()
  env$health_resolve_host_ips <- function(host) c("10.1.1.1", "fd00::5")
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
  env$health_resolve_host_ips <- function(host) "192.168.10.7"
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
  # Tek etiketli intranet adı yalnız özel adrese çözülürse denenir; IPv6 bölge
  # kimliği davranışı değişmez.
  env$health_resolve_host_ips <- function(host) if (identical(host, "intranet-servis")) "10.0.0.8" else "8.8.8.8"
  expect_false(env$health_is_public_url("http://intranet-servis:8080/v1"))
  expect_true(env$health_is_public_url("http://servis-genel:8080/v1"))
  expect_false(env$health_is_public_url("http://[fe80::1%25eth0]:8080/v1"))
})

test_that("sayısal IPv4 yazımları libcurl gibi çözülür; genel adres intranet sayılmaz", {
  env <- .fresh_health_env()
  withr::local_envvar(c(MERGEN_HEALTH_INTERNAL_ENDPOINTS = ""))
  expect_identical(env$health_ipv4_canonical("134744072"), "8.8.8.8")
  expect_identical(env$health_ipv4_canonical("0x8080808"), "8.8.8.8")
  expect_identical(env$health_ipv4_canonical("010.010.010.010"), "8.8.8.8")
  expect_identical(env$health_ipv4_canonical("127.1"), "127.0.0.1")
  expect_null(env$health_ipv4_canonical("intranet"))
  expect_true(is.na(env$health_ipv4_canonical("08.1.1.1")))
  expect_true(env$health_is_public_url("http://134744072/"))
  expect_true(env$health_is_public_url("http://0x8080808:8080/v1"))
  expect_true(env$health_is_public_url("http://010.010.010.010/"))
  expect_true(env$health_is_public_url("http://300.1.1.1/"))
  expect_false(env$health_is_public_url("http://127.1:9000/"))
  expect_false(env$health_is_public_url("http://012.0.0.1/"))
})

test_that("IPv6 joker adresinin tüm yazımları yerel döngüden denenir", {
  env <- .fresh_health_env()
  expect_identical(env$health_probe_url("http://[0:0:0:0:0:0:0:0]:9000/x"), "http://[::1]:9000/x")
  expect_identical(env$health_probe_url("http://[0::0]:9000/x"), "http://[::1]:9000/x")
  expect_identical(env$health_probe_url("http://0:8000/"), "http://127.0.0.1:8000/")
  expect_identical(env$health_probe_url("http://[::1]:9000/x"), "http://[::1]:9000/x")
  expect_identical(env$health_probe_url("http://[fd00::]:9000/x"), "http://[fd00::]:9000/x")
  # Yüzde kodlu joker adres de (libcurl çözer) yerel döngüden denenir.
  expect_identical(env$health_probe_url("http://%30.0.0.0:9000/health"), "http://127.0.0.1:9000/health")
  # Rakamsız onaltılık literal (`0x`) sayı değildir; 0.0.0.0'a eşlenmez.
  expect_null(env$health_ipv4_canonical("0x"))
  expect_false(env$health_host_unspecified("0x"))
  expect_identical(env$health_probe_url("http://0x:8000/"), "http://0x:8000/")
})

test_that("onaltılık IPv4-eşlemeli IPv6 gömülü IPv4 kuralıyla sınıflandırılır", {
  env <- .fresh_health_env()
  withr::local_envvar(c(MERGEN_HEALTH_INTERNAL_ENDPOINTS = ""))
  expect_true(env$health_ip_literal_internal("::ffff:7f00:1"))
  expect_true(env$health_ip_literal_internal("0:0:0:0:0:ffff:a00:1"))
  expect_false(env$health_ip_literal_internal("::ffff:808:808"))
  expect_false(env$health_is_public_url("http://[::ffff:7f00:1]:9000/"))
  expect_true(env$health_is_public_url("http://[::ffff:808:808]/"))
})

test_that("model eşlemesindeki doğrudan URL on-prem host kümesine girer", {
  env <- .fresh_health_env()
  env$health_resolve_host_ips <- function(host) if (identical(host, "model2.kurum.com.tr")) "10.9.9.9" else "8.8.8.8"
  withr::local_envvar(c(MERGEN_HEALTH_INTERNAL_ENDPOINTS = ""))
  env$api_config <- list(local_model_endpoint_map = c(model2 = "https://model2.kurum.com.tr/v1",
                                                      model1 = "primary"))
  expect_false(env$health_is_public_url("https://model2.kurum.com.tr/v1/models"))
  expect_true(env$health_is_public_url("https://primary.example.com/v1"))
})

test_that("sağlık denemesi HTTP yönlendirmesini izlemez", {
  skip_if_not_installed("httr")
  env <- .fresh_health_env()
  yakalanan <- list()
  testthat::local_mocked_bindings(
    GET = function(url, ...) {
      yakalanan <<- list(...)
      structure(list(), class = "response")
    },
    status_code = function(res) 302L,
    .package = "httr"
  )
  r <- env$health_check_http_endpoint("tts.endpoint", "TTS", "http://127.0.0.1:9000/health")
  ayar <- Filter(function(x) inherits(x, "request"), yakalanan)
  expect_true(any(vapply(ayar, function(x) identical(x$options$followlocation, 0L), logical(1))))
  expect_identical(r$status[1], "ok")
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
  # Dahili son ek testi artık düşmez; özel adrese çözülen ad denenir.
  env$health_resolve_host_ips <- function(host) "10.3.3.3"
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
  # Bozuk ULA/bağlantı-yerel literal dahili sayılmaz (kapalı-başarısız).
  for (bozuk in c("fd00:zzzz::1", "fe80:garbage", "fc00::1::2", "fd00:1:2:3:4:5:6:7:8")) {
    expect_false(isTRUE(env$health_ip_literal_internal(bozuk)), info = bozuk)
  }
  expect_true(isTRUE(env$health_ip_literal_internal("fe80::1%eth0")))
  expect_true(isTRUE(env$health_ip_literal_internal("FEBF::1")))
  expect_false(isTRUE(env$health_ip_literal_internal("fec0::1")))
})

test_that("dahili görünümlü ad ve son ek genel adrese çözülürse denenmez; çözülmezse neden söylenir", {
  env <- .fresh_health_env()
  withr::local_envvar(c(MERGEN_HEALTH_INTERNAL_ENDPOINTS = ""))
  env$health_resolve_host_ips <- function(host) switch(host, "servis.corp" = "93.184.216.34",
                                                       "ic-servis" = "8.8.8.8", character(0))
  expect_true(env$health_is_public_url("https://servis.corp/v1"))
  expect_true(env$health_is_public_url("http://ic-servis/v1"))
  expect_identical(env$health_endpoint_scope("http://yok.internal/v1")$neden, "cozulmedi")
  # Operatör ilanı çözümlemeden bağımsız geçerlidir.
  withr::local_envvar(c(MERGEN_HEALTH_INTERNAL_ENDPOINTS = "servis.corp"))
  expect_false(env$health_is_public_url("https://servis.corp/v1"))
})

test_that("başarısız DNS çözümü genel sonuç sayılmaz; kısa süre önbelleklenir ve olay döngüsünü tekrar bloklamaz", {
  env <- .fresh_health_env()
  cevap <- character(0)
  sorgu <- 0L
  env$health_resolve_host_ips <- function(host) { sorgu <<- sorgu + 1L; cevap }
  withr::local_envvar(c(LOCAL_TTS_ENDPOINT = "https://ses.kurum.com.tr/v1", MERGEN_HEALTH_INTERNAL_ENDPOINTS = ""))
  expect_identical(env$health_endpoint_scope("https://ses.kurum.com.tr/v1")$neden, "cozulmedi")
  expect_identical(env$health_endpoint_scope("https://ses.kurum.com.tr/v1")$neden, "cozulmedi")
  expect_identical(sorgu, 1L)
  # Kısa süre dolunca yeniden çözülür; genel hükme dönüşmemiştir.
  cevap <- "10.1.2.3"
  expect_identical(env$health_host_private_ips("ses.kurum.com.tr", kisa_ttl = 0), "10.1.2.3")
  # Özel hüküm de kısa süre tutulur (her yenilemede yeniden sorgu yok).
  expect_false(env$health_is_public_url("https://ses.kurum.com.tr/v1"))
  expect_identical(sorgu, 2L)
})

test_that("DNS ile onaylanan uç nokta denetlenen özel adrese sabitlenir", {
  env <- .fresh_health_env()
  withr::local_envvar(c(LOCAL_STT_ENDPOINT = "https://yazi.kurum.com.tr:8443/v1", MERGEN_HEALTH_INTERNAL_ENDPOINTS = ""))
  env$health_resolve_host_ips <- function(host) c("10.4.4.4", "fd00::7")
  kapsam <- env$health_endpoint_scope("https://yazi.kurum.com.tr:8443/v1/health")
  expect_false(kapsam$public)
  # Tüm denetlenen adresler tek girdide: ikinci girdi öncekini ezerdi.
  expect_identical(kapsam$pin, "yazi.kurum.com.tr:8443:10.4.4.4,[fd00::7]")
  expect_identical(env$health_endpoint_scope("http://127.0.0.1:9000/")$pin, character(0))
  ayarlar <- NULL
  testthat::local_mocked_bindings(
    GET = function(url, ...) { ayarlar <<- list(...); structure(list(), class = "response") },
    status_code = function(res) 200L,
    .package = "httr"
  )
  r <- env$health_check_http_endpoint("stt.endpoint", "STT", "https://yazi.kurum.com.tr:8443/v1/health")
  expect_identical(r$status[1], "ok")
  cfg <- Filter(function(x) inherits(x, "request"), ayarlar)
  expect_true(any(vapply(cfg, function(x) identical(x$options$resolve, kapsam$pin), logical(1))))
})

test_that("HTTP(S) dışı şema denenmez", {
  env <- .fresh_health_env()
  testthat::local_mocked_bindings(GET = function(url, ...) stop("çağrılmamalıydı"), .package = "httr")
  r <- env$health_check_http_endpoint("x", "X", "ftp://dosya.example.com/pub")
  expect_identical(r$value[1], "Atlandı")
  expect_true(grepl("HTTP(S)", r$detail[1], fixed = TRUE))
})

test_that("IDNA nokta eşdeğerleri noktaya çevrilir; genel ad intranet sayılmaz", {
  env <- .fresh_health_env()
  withr::local_envvar(c(MERGEN_HEALTH_INTERNAL_ENDPOINTS = ""))
  env$health_resolve_host_ips <- function(host) "8.8.8.8"
  expect_identical(env$health_url_host("http://public\u3002example\uff0ecom/"), "public.example.com")
  expect_true(env$health_is_public_url("http://public\uff61example\u3002com/v1"))
})

test_that("bozuk IPv6 joker yazımı yerel döngüye çevrilmez", {
  env <- .fresh_health_env()
  expect_true(env$health_host_unspecified("::"))
  expect_true(env$health_host_unspecified("0:0:0:0:0:0:0:0"))
  expect_true(env$health_host_unspecified("0::0"))
  for (bozuk in c("0:::0", ":::", "0::0::0", ":0::", "0:0:0:0:0:0:0:0:0", "00000::")) {
    expect_false(env$health_host_unspecified(bozuk), info = bozuk)
  }
  expect_identical(env$health_probe_url("http://[0:::0]:8000/x"), "http://[0:::0]:8000/x")
})

test_that("sabitlenen istek host'u resolve anahtarıyla birebir eşleşir (kök noktası, büyük harf, yol korunur)", {
  env <- .fresh_health_env()
  withr::local_envvar(c(LOCAL_STT_ENDPOINT = "https://Model.Corp.:8443/v1", MERGEN_HEALTH_INTERNAL_ENDPOINTS = ""))
  env$health_resolve_host_ips <- function(host) "10.9.9.9"
  kapsam <- env$health_endpoint_scope("https://Model.Corp.:8443/V1/Saglik?x=Y")
  expect_identical(kapsam$pin, "model.corp:8443:10.9.9.9")
  expect_identical(kapsam$hedef, "https://model.corp:8443/V1/Saglik?x=Y")
  istenen <- NULL
  testthat::local_mocked_bindings(
    GET = function(url, ...) { istenen <<- url; structure(list(), class = "response") },
    status_code = function(res) 200L,
    .package = "httr"
  )
  env$health_check_http_endpoint("stt.endpoint", "STT", "https://Model.Corp.:8443/V1/Saglik?x=Y")
  expect_identical(istenen, kapsam$hedef)
  expect_null(env$health_endpoint_scope("http://127.0.0.1:9000/")$hedef)
})

test_that("bozuk IPv6 loopback literali dahili sayılmaz", {
  env <- .fresh_health_env()
  for (gecerli in c("::1", "0:0:0:0:0:0:0:1", "::0001", "0::1")) {
    expect_true(isTRUE(env$health_ip_literal_internal(gecerli)), info = gecerli)
  }
  for (bozuk in c("0:0:0:0:0:0:1", "1::", "0:1::", ":::1", "0:0:0:0:0:0:0:0:1")) {
    expect_false(isTRUE(env$health_ip_literal_internal(bozuk)), info = bozuk)
  }
  expect_true(env$health_is_public_url("http://[0:0:0:0:0:0:1]:8080/v1"))
})

test_that("sağlık denetimleri dosyası tek başına yüklendiğinde kapsam yardımcısını da yükler", {
  kok <- resolve_repo_root_for_tests()
  temiz <- new.env(parent = baseenv())
  temiz[["%||%"]] <- function(x, y) if (is.null(x)) y else x
  env <- new.env(parent = temiz)
  withr::with_dir(tempdir(), source(file.path(kok, "R", "helpers_health_checks.R"), encoding = "UTF-8", local = env))
  expect_true(exists("health_endpoint_scope", envir = env, inherits = FALSE))
  expect_true(exists("health_probe_url", envir = env, inherits = FALSE))
})


test_that("DNS çözümlemesi beklemez, süre aşımında ayrı süreç durdurulur", {
  skip_if_not_installed("callr")
  skip_if_not_installed("later")
  env <- .fresh_health_env()
  alive <- TRUE
  starts <- 0L
  timeout <- NULL
  worker <- list(is_alive = function() alive, kill = function() alive <<- FALSE,
                 get_result = function() stop("timeout"))
  testthat::local_mocked_bindings(r_bg = function(...) { starts <<- starts + 1L; worker }, .package = "callr")
  testthat::local_mocked_bindings(later = function(func, delay, ...) {
    expect_lte(delay, 3)
    timeout <<- func
  }, .package = "later")
  expect_true(attr(env$health_resolve_host_ips("servis.corp"), "pending"))
  expect_length(env$health_host_private_ips("servis.corp"), 0L)
  expect_identical(starts, 1L)
  expect_null(env$.HEALTH_DNS_CACHE[["servis.corp"]])
  timeout()
  expect_false(alive)
  expect_length(env$health_host_private_ips("servis.corp"), 0L)
  expect_false(is.null(env$.HEALTH_DNS_CACHE[["servis.corp"]]))
})
