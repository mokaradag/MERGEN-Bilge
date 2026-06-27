# ==============================================================================
# Dosya Yolu: tests/testthat/test-app-http-routes-contract.R
# Açıklama: Uygulama-içi sağlık/hazırlık uç noktaları ve kök sayfa yönlendiricisi
#           (R/helpers_app_http_routes.R) davranış/sözleşme testleri.
#
# Doğrulananlar:
#   - uiPattern yalnızca "/", "/healthz", "/readyz" eşler; statik kaynak yolları
#     etkilenmez.
#   - GET /healthz küçük statik 200 JSON döndürür (DB/oturum işi yok).
#   - GET /readyz sır-güvenli hazırlık JSON'u döndürür (runtime/backpressure/
#     db_pool blokları; DB I/O yok).
#   - Diğer yollar index_ui'ye delege edilir (fonksiyon ise req ile, statik ise
#     olduğu gibi).
#   - Sağlık uç noktası KAPALI iken index_ui DEĞİŞMEDEN döner (bayt-bayt aynı).
#
# Bu testler app.R'yi BAŞLATMAZ; saf yardımcı dosya tek başına source edilir.
# ==============================================================================

testthat::local_edition(3)

.routes_env <- function() {
  env <- new.env(parent = globalenv())
  source("../../R/helpers_runtime_metrics.R", local = env)
  source("../../R/helpers_request_backpressure.R", local = env)
  source("../../R/helpers_app_http_routes.R", local = env)
  env
}

test_that("uiPattern yalniz kok + saglik yollarini esler; statik kaynaklar haric", {
  env <- .routes_env()
  withr::with_envvar(c(MERGEN_HEALTH_ENDPOINT = ""), {
    pat <- sprintf("^%s$", env$mergen_app_route_pattern())  # shinyApp sarmasini taklit
    expect_true(grepl(pat, "/"))
    expect_true(grepl(pat, "/healthz"))
    expect_true(grepl(pat, "/readyz"))
    expect_false(grepl(pat, "/foo"))
    expect_false(grepl(pat, "/css/app.css"))
    expect_false(grepl(pat, "/session/abc"))
  })
})

test_that("saglik uc noktasi KAPALI iken pattern '/' ve index_ui degismeden doner", {
  env <- .routes_env()
  withr::with_envvar(c(MERGEN_HEALTH_ENDPOINT = "false"), {
    expect_identical(env$mergen_app_route_pattern(), "/")
    idx <- list(marker = "INDEX")
    expect_identical(env$mergen_build_app_ui(idx), idx)
  })
})

test_that("GET /healthz kucuk statik 200 JSON doner (no-store)", {
  skip_if_not_installed("shiny")
  env <- .routes_env()
  withr::with_envvar(c(MERGEN_HEALTH_ENDPOINT = ""), {
    router <- env$mergen_build_app_ui(function(req) shiny::httpResponse(200L, content = "INDEX"))
    resp <- router(list(PATH_INFO = "/healthz"))
    expect_s3_class(resp, "httpResponse")
    expect_identical(resp$status, 200L)
    expect_match(resp$content_type, "application/json", fixed = TRUE)
    expect_match(resp$content, "\"status\":\"ok\"", fixed = TRUE)
    expect_identical(resp$headers[["Cache-Control"]], "no-store")

    # Sondaki "/" normalize edilir.
    expect_s3_class(router(list(PATH_INFO = "/healthz/")), "httpResponse")
  })
})

test_that("GET /readyz sir-guvenli hazirlik JSON'u doner (runtime/backpressure)", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("jsonlite")
  env <- .routes_env()
  withr::with_envvar(c(MERGEN_HEALTH_ENDPOINT = ""), {
    router <- env$mergen_build_app_ui(function(req) shiny::httpResponse(200L, content = "INDEX"))
    resp <- router(list(PATH_INFO = "/readyz"))
    expect_s3_class(resp, "httpResponse")
    expect_identical(resp$status, 200L)
    parsed <- jsonlite::fromJSON(resp$content)
    expect_identical(parsed$status, "ok")
    expect_true(!is.null(parsed$runtime))
    expect_true(!is.null(parsed$backpressure))
    # Sir-benzeri anahtar/DSN/secret kelimeleri sizmamali.
    expect_false(grepl("(?i)(password|secret|dsn=|bearer|api[_-]?key=)", resp$content, perl = TRUE))
  })
})

test_that("diger yollar index_ui'ye delege edilir (fonksiyon ve statik)", {
  skip_if_not_installed("shiny")
  env <- .routes_env()
  withr::with_envvar(c(MERGEN_HEALTH_ENDPOINT = ""), {
    calls <- 0L
    router_fn <- env$mergen_build_app_ui(function(req) { calls <<- calls + 1L; shiny::httpResponse(200L, content = "IDX") })
    d <- router_fn(list(PATH_INFO = "/"))
    expect_match(d$content, "IDX", fixed = TRUE)
    expect_identical(calls, 1L)
    router_fn(list(PATH_INFO = ""))      # bos -> "/"
    expect_identical(calls, 2L)

    router_static <- env$mergen_build_app_ui(list(tag = "STATIC"))
    expect_identical(router_static(list(PATH_INFO = "/")), list(tag = "STATIC"))
  })
})

test_that("saglik isabetleri calisma-zamani metriklerine yansir", {
  skip_if_not_installed("shiny")
  env <- .routes_env()
  withr::with_envvar(c(MERGEN_HEALTH_ENDPOINT = ""), {
    env$mergen_runtime_metrics_reset()
    router <- env$mergen_build_app_ui(function(req) shiny::httpResponse(200L, content = "INDEX"))
    router(list(PATH_INFO = "/healthz"))
    router(list(PATH_INFO = "/readyz"))
    expect_gte(env$mergen_runtime_metric_get("health_liveness_hit"), 1)
    expect_gte(env$mergen_runtime_metric_get("health_readiness_hit"), 1)
  })
})
