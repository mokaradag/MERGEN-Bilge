# ==============================================================================
# Dosya Yolu: tests/testthat/test-config-api-validate-api-key-behavior.R
# Açıklama: R/config_api.R::validate_api_key() davranışsal testleri. Kişisel API
#           anahtarı "Doğrula" akışının uç-nokta doğrulama dallarını (boş anahtar,
#           /v1/models türetme, model-listesi GET 200/401/403/429/500, sağlık uç
#           noktası, sohbet ping POST 200/401/429/hata, endpoint tanımsız) httr
#           mock'larıyla kilitler. derive_models_url() iç closure'u, mock'lanan
#           GET'e geçen URL yakalanarak DOLAYLI sınanır. Çalışma zamanı R kodu
#           DEĞİŞMEZ; gerçek ağ/LLM/anahtar GEREKMEZ; sahte anahtar kullanılır.
# ==============================================================================

# config_api.R üst seviyede validate_api_key tanımlar ama ağır source-time yan
# etkileri vardır; kanıtlanmış bootstrap deseni (bkz.
# test-llm-reasoning-request-overrides.R) ile placeholder env + bağımlılıklar
# hazırlanıp config_api.R globalenv'e source edilir (tekrar yüklemeyi önlemek
# için guard'lı).
.bootstrap_validate_api_key <- function() {
  if (exists("validate_api_key", mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  helper_candidates <- c(
    "tests/testthat/helper_bootstrap.R",
    "testthat/helper_bootstrap.R",
    "helper_bootstrap.R"
  )
  helper_path <- helper_candidates[file.exists(helper_candidates)][1]
  if (!is.na(helper_path) && nzchar(helper_path)) {
    source(helper_path, encoding = "UTF-8", local = globalenv())
  }

  if (!exists("resolve_repo_root_for_tests", mode = "function", inherits = TRUE)) {
    resolve_repo_root_for_tests <<- function() {
      for (cand in c(".", "..", "../..")) {
        if (file.exists(file.path(cand, "app.R")) && dir.exists(file.path(cand, "R"))) {
          return(normalizePath(cand, winslash = "/", mustWork = TRUE))
        }
      }
      stop("Repo kökü bulunamadı.", call. = FALSE)
    }
  }

  repo_root <- resolve_repo_root_for_tests()

  test_logs_dir <- file.path(tempdir(), "mergen-validate-api-key-logs")
  dir.create(test_logs_dir, recursive = TRUE, showWarnings = FALSE)
  if (requireNamespace("logger", quietly = TRUE)) {
    logger::log_appender(
      logger::appender_file(file.path(
        test_logs_dir, sprintf("mergen_%s.log", format(Sys.Date(), "%Y%m%d"))
      )),
      index = 1
    )
  }

  for (fn in c("log_info", "log_warn", "log_debug")) {
    if (!exists(fn, mode = "function", inherits = TRUE)) {
      assign(fn, function(...) invisible(NULL), envir = globalenv())
    }
  }
  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(x, y) if (is.null(x)) y else x
  }

  # config_api.R .Renviron/indeks hazırlığına bakabildiği için güvenli
  # placeholder ortam değişkenleri açıkça verilir.
  Sys.setenv(
    MERGEN_RUN_APP = "false",
    MERGEN_DISABLE_FUTURES = "true",
    MERGEN_LOG_DIR = test_logs_dir,
    LOCAL_LLM_ENDPOINT = Sys.getenv("LOCAL_LLM_ENDPOINT", "http://test.local/v1"),
    DB_DSN = Sys.getenv("DB_DSN", "test-dsn"),
    AI_KEYS_MASTER = Sys.getenv("AI_KEYS_MASTER", "test-master-key-0123456789")
  )

  if (!exists(".build_basename_index", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "utils_file_index.R"),
           encoding = "UTF-8", local = globalenv())
  }

  # Derin Düşünme yetenek kaydı saf helper'dadır; config_api.R'den ÖNCE.
  source(file.path(repo_root, "R", "helpers_deep_thinking_model_capabilities.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "config_api.R"),
         encoding = "UTF-8", local = globalenv())
  # resolve_local_llm_endpoint validate_api_key tarafından çağrılır.
  source(file.path(repo_root, "R", "helpers_api_model_config.R"),
         encoding = "UTF-8", local = globalenv())

  invisible(TRUE)
}

.bootstrap_validate_api_key()

# Sahte httr yanıtı; status_code mock'u attr(., "sc")'yi okur.
.vak_resp <- function(sc) structure(list(), class = "response", sc = sc)

# Test başına GET/POST kayıt + yanıt yönlendirme kurulumu. get_fn/post_fn URL
# alıp ya .vak_resp(...) döndürür ya da stop() ile try-error simüle eder.
.vak_with_http <- function(get_fn, post_fn, code, env = parent.frame()) {
  rec <- new.env()
  rec$get_urls <- character(0)
  rec$post_urls <- character(0)

  testthat::local_mocked_bindings(
    GET = function(url, ...) {
      rec$get_urls <- c(rec$get_urls, url)
      get_fn(url)
    },
    POST = function(url, ...) {
      rec$post_urls <- c(rec$post_urls, url)
      post_fn(url)
    },
    status_code = function(resp) attr(resp, "sc") %||% 0L,
    .package = "httr",
    .env = env
  )

  rec
}

# Varsayılan: GET çağrılırsa hata (çağrılmamalı senaryoları için), POST no-op.
.vak_get_stop <- function(url) stop("GET cagrilmamaliydi")
.vak_post_stop <- function(url) stop("POST cagrilmamaliydi")

FAKE_KEY <- "gecersiz-test-anahtari"  # Gerçek anahtar değil; sk- gibi önek yok.

testthat::test_that("boş anahtar HTTP çağrısı yapmadan geçersiz döner", {
  withr::local_envvar(LLM_HEALTH_ENDPOINT = "")
  rec <- .vak_with_http(.vak_get_stop, .vak_post_stop, env = environment())

  res <- validate_api_key("", model_id = "m", endpoint = "http://h/v1")

  testthat::expect_false(res$valid)
  testthat::expect_match(res$message, "boş", ignore.case = TRUE)
  testthat::expect_length(rec$get_urls, 0L)
  testthat::expect_length(rec$post_urls, 0L)
})

testthat::test_that("model listesi 200 -> anahtar geçerli", {
  withr::local_envvar(LLM_HEALTH_ENDPOINT = "")
  rec <- .vak_with_http(function(url) .vak_resp(200), .vak_post_stop, env = environment())

  res <- validate_api_key(FAKE_KEY, model_id = "m", endpoint = "http://h/v1/chat/completions")

  testthat::expect_true(res$valid)
  testthat::expect_match(res$message, "model listesi", ignore.case = TRUE)
  testthat::expect_length(rec$post_urls, 0L)  # 200'de PONG'a düşmez
})

testthat::test_that("model listesi 401/403 -> anahtar reddedilir", {
  withr::local_envvar(LLM_HEALTH_ENDPOINT = "")
  for (sc in c(401, 403)) {
    rec <- .vak_with_http(function(url) .vak_resp(sc), .vak_post_stop, env = environment())
    res <- validate_api_key(FAKE_KEY, model_id = "m", endpoint = "http://h/v1")
    testthat::expect_false(res$valid)
    testthat::expect_match(res$message, "401/403", fixed = TRUE)
    testthat::expect_length(rec$post_urls, 0L)
  }
})

testthat::test_that("derive_models_url: /v1/ içeren endpoint .../v1/models'e indirgenir", {
  withr::local_envvar(LLM_HEALTH_ENDPOINT = "")
  rec <- .vak_with_http(function(url) .vak_resp(200), .vak_post_stop, env = environment())

  validate_api_key(FAKE_KEY, model_id = "m", endpoint = "http://host:8000/v1/chat/completions")

  testthat::expect_identical(rec$get_urls[1], "http://host:8000/v1/models")
})

testthat::test_that("derive_models_url: /v1/ içermeyen endpoint'e /v1/models eklenir", {
  withr::local_envvar(LLM_HEALTH_ENDPOINT = "")
  rec <- .vak_with_http(function(url) .vak_resp(200), .vak_post_stop, env = environment())

  validate_api_key(FAKE_KEY, model_id = "m", endpoint = "http://host:8000")

  testthat::expect_identical(rec$get_urls[1], "http://host:8000/v1/models")
})

testthat::test_that("derive_models_url: sorgu ve sondaki eğik çizgiler temizlenir", {
  withr::local_envvar(LLM_HEALTH_ENDPOINT = "")
  rec <- .vak_with_http(function(url) .vak_resp(200), .vak_post_stop, env = environment())

  validate_api_key(FAKE_KEY, model_id = "m",
                   endpoint = "http://host/v1/chat/completions/?token=abc")

  testthat::expect_identical(rec$get_urls[1], "http://host/v1/models")
})

testthat::test_that("model listesi 429 sonrası sohbet ping POST 200 -> geçerli", {
  withr::local_envvar(LLM_HEALTH_ENDPOINT = "")
  rec <- .vak_with_http(
    function(url) .vak_resp(429),
    function(url) .vak_resp(200),
    env = environment()
  )

  res <- validate_api_key(FAKE_KEY, model_id = "m", endpoint = "http://h/v1")

  testthat::expect_true(res$valid)
  testthat::expect_match(res$message, "sohbet ping", ignore.case = TRUE)
  testthat::expect_length(rec$post_urls, 1L)
})

testthat::test_that("model listesi GET hatası (try-error) sonrası POST 401 -> reddedilir", {
  withr::local_envvar(LLM_HEALTH_ENDPOINT = "")
  rec <- .vak_with_http(
    function(url) stop("baglanti yok"),
    function(url) .vak_resp(401),
    env = environment()
  )

  res <- validate_api_key(FAKE_KEY, model_id = "m", endpoint = "http://h/v1")

  testthat::expect_false(res$valid)
  testthat::expect_match(res$message, "401/403", fixed = TRUE)
  testthat::expect_length(rec$post_urls, 1L)
})

testthat::test_that("model listesi 500 sonrası POST 429 -> geçerli kabul (hız limiti)", {
  withr::local_envvar(LLM_HEALTH_ENDPOINT = "")
  rec <- .vak_with_http(
    function(url) .vak_resp(500),
    function(url) .vak_resp(429),
    env = environment()
  )

  res <- validate_api_key(FAKE_KEY, model_id = "m", endpoint = "http://h/v1")

  testthat::expect_true(res$valid)
  testthat::expect_match(res$message, "hız limiti", ignore.case = TRUE)
})

testthat::test_that("POST ping hatası (try-error) -> sunucuya ulaşılamadı (NA)", {
  withr::local_envvar(LLM_HEALTH_ENDPOINT = "")
  rec <- .vak_with_http(
    function(url) .vak_resp(500),
    function(url) stop("post baglanti yok"),
    env = environment()
  )

  res <- validate_api_key(FAKE_KEY, model_id = "m", endpoint = "http://h/v1")

  testthat::expect_true(is.na(res$valid))
  testthat::expect_match(res$message, "ulaşılamadı", ignore.case = TRUE)
})

testthat::test_that("POST ping beklenmedik kod -> NA, kod mesajda görünür", {
  withr::local_envvar(LLM_HEALTH_ENDPOINT = "")
  rec <- .vak_with_http(
    function(url) .vak_resp(500),
    function(url) .vak_resp(418),
    env = environment()
  )

  res <- validate_api_key(FAKE_KEY, model_id = "m", endpoint = "http://h/v1")

  testthat::expect_true(is.na(res$valid))
  testthat::expect_match(res$message, "418", fixed = TRUE)
})

testthat::test_that("sağlık uç noktası 200 -> geçerli (model listesi 429 iken)", {
  withr::local_envvar(LLM_HEALTH_ENDPOINT = "http://h/health")
  rec <- .vak_with_http(
    function(url) if (grepl("health", url, fixed = TRUE)) .vak_resp(200) else .vak_resp(429),
    .vak_post_stop,
    env = environment()
  )

  res <- validate_api_key(FAKE_KEY, model_id = "m", endpoint = "http://h/v1")

  testthat::expect_true(res$valid)
  testthat::expect_match(res$message, "Sağlık", ignore.case = TRUE)
  testthat::expect_length(rec$post_urls, 0L)
})

testthat::test_that("sağlık uç noktası 401 -> reddedilir (model listesi 429 iken)", {
  withr::local_envvar(LLM_HEALTH_ENDPOINT = "http://h/health")
  rec <- .vak_with_http(
    function(url) if (grepl("health", url, fixed = TRUE)) .vak_resp(401) else .vak_resp(429),
    .vak_post_stop,
    env = environment()
  )

  res <- validate_api_key(FAKE_KEY, model_id = "m", endpoint = "http://h/v1")

  testthat::expect_false(res$valid)
  testthat::expect_match(res$message, "401/403", fixed = TRUE)
})

testthat::test_that("endpoint tanımsız (resolve boş döner) -> doğrulama yapılamadı (NA)", {
  withr::local_envvar(LLM_HEALTH_ENDPOINT = "")

  # endpoint boş verilince resolve_local_llm_endpoint çağrılır; boş döndürmesi
  # için geçici olarak override edip geri yükle.
  orig_resolve <- get("resolve_local_llm_endpoint", envir = globalenv())
  assign("resolve_local_llm_endpoint", function(...) "", envir = globalenv())
  withr::defer(assign("resolve_local_llm_endpoint", orig_resolve, envir = globalenv()))

  rec <- .vak_with_http(.vak_get_stop, .vak_post_stop, env = environment())

  res <- validate_api_key(FAKE_KEY, model_id = "m", endpoint = "")

  testthat::expect_true(is.na(res$valid))
  testthat::expect_match(res$message, "endpoint", ignore.case = TRUE)
  testthat::expect_length(rec$get_urls, 0L)
  testthat::expect_length(rec$post_urls, 0L)
})
