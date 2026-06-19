# ==============================================================================
# Dosya Yolu: tests/testthat/test-index-page-cache-contract.R
# Açıklama: Kök sayfa (GET /) HTML önbellekleme yardımcılarının
#           (R/helpers_index_page_cache.R) davranış/sözleşme testleri.
#
# Doğrulananlar:
#   - Önbellek KAPALI iken `ui` statik etiket nesnesi olarak korunur (mevcut
#     davranış: Shiny her istekte render eder).
#   - Önbellek AÇIK iken `ui` bir function(req) olur; ilk istekte render edilir
#     ve sonraki istekler yeniden serileştirme OLMADAN aynı httpResponse'u alır.
#   - Render başarısız olursa statik UI'ye GÜVENLİ biçimde geri dönülür ve
#     önbellek bozuk yanıtla kirletilmez (sonraki istekte yeniden denenir).
#   - Özellik bayrağı (MERGEN_CACHE_INDEX_HTML) doğru çözülür.
#
# Bu testler app.R'yi BAŞLATMAZ ve gerçek tam UI'yi render etmez; saf yardımcı
# dosya tek başına source edilir ve render fonksiyonu enjekte edilir.
# ==============================================================================

testthat::local_edition(3)

.index_cache_env <- function() {
  env <- new.env(parent = globalenv())
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_index_page_cache.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

test_that("önbellek kapalı iken statik UI nesnesi DEĞİŞMEDEN korunur", {
  env <- .index_cache_env()
  static_ui <- list(marker = "STATIK_UI")

  result <- env$mergen_build_index_ui(
    static_ui,
    enabled = FALSE,
    render_page_fn = function(...) stop("render edilmemeli")
  )

  expect_false(is.function(result))
  expect_identical(result, static_ui)
})

test_that("dinamik UI fonksiyonu önbellek sarmalayıcısına alınmadan korunur", {
  env <- .index_cache_env()
  dynamic_ui <- function(req) list(marker = "DINAMIK_UI", req = req)

  result <- env$mergen_build_index_ui(
    dynamic_ui,
    enabled = TRUE,
    render_page_fn = function(...) stop("dinamik UI renderPage ile render edilmemeli")
  )

  expect_identical(result, dynamic_ui)
  expect_identical(result(list(PATH_INFO = "/"))$marker, "DINAMIK_UI")
})

test_that("önbellek açık iken ui bir function(req) olur ve ilk render önbeklenir", {
  skip_if_not_installed("shiny")
  env <- .index_cache_env()

  static_ui <- list(marker = "STATIK_UI")
  render_count <- 0L
  fake_render <- function(ui, showcase = 0, testMode = FALSE) {
    render_count <<- render_count + 1L
    # Shiny renderPage çağrı sözleşmesini doğrula: showcase=0, testMode=FALSE.
    expect_identical(showcase, 0)
    expect_false(testMode)
    expect_identical(ui, static_ui)
    "<html>MERGEN INDEX</html>"
  }

  handler <- env$mergen_build_index_ui(
    static_ui,
    enabled = TRUE,
    render_page_fn = fake_render
  )

  expect_true(is.function(handler))
  expect_length(formals(handler), 1L)

  # İlk istek: render edilir ve httpResponse döner.
  resp1 <- handler(list(PATH_INFO = "/"))
  expect_s3_class(resp1, "httpResponse")
  expect_identical(resp1$status, 200L)
  expect_identical(resp1$content, "<html>MERGEN INDEX</html>")
  expect_match(resp1$content_type, "text/html", fixed = TRUE)
  expect_identical(render_count, 1L)

  # Sonraki istekler: yeniden render YOK; aynı önbelleğe alınmış yanıt döner.
  resp2 <- handler(list(PATH_INFO = "/"))
  resp3 <- handler(list(PATH_INFO = "/"))
  expect_identical(render_count, 1L)
  expect_identical(resp2, resp1)
  expect_identical(resp3, resp1)
})

test_that("render başarısız olursa statik UI'ye düşülür ve önbellek kirletilmez", {
  skip_if_not_installed("shiny")
  env <- .index_cache_env()

  static_ui <- list(marker = "STATIK_UI")
  calls <- 0L
  flaky_render <- function(ui, showcase = 0, testMode = FALSE) {
    calls <<- calls + 1L
    if (calls == 1L) stop("ilk render basarisiz")
    "<html>SONRADAN OK</html>"
  }

  handler <- env$mergen_build_index_ui(
    static_ui,
    enabled = TRUE,
    render_page_fn = flaky_render
  )

  # İlk istek: render hata verir -> statik UI döner (Shiny her zamanki gibi
  # render eder). Önbellek NULL kalır.
  suppressWarnings(suppressMessages({
    r1 <- handler(list(PATH_INFO = "/"))
  }))
  expect_identical(r1, static_ui)
  expect_false(inherits(r1, "httpResponse"))

  # İkinci istek: yeniden denenir ve bu kez başarılı -> httpResponse önbeklenir.
  r2 <- handler(list(PATH_INFO = "/"))
  expect_s3_class(r2, "httpResponse")
  expect_identical(r2$content, "<html>SONRADAN OK</html>")

  # Üçüncü istek: artık önbellekten gelir (yeniden render yok).
  r3 <- handler(list(PATH_INFO = "/"))
  expect_identical(r3, r2)
  expect_identical(calls, 2L)
})

test_that("render fonksiyonu çözülemezse statik UI'ye güvenli biçimde düşülür", {
  env <- .index_cache_env()
  static_ui <- list(marker = "STATIK_UI")

  # render_page_fn açıkça NULL ve enjekte edilen çözümleyici de fonksiyon
  # döndürmüyor: enabled TRUE olsa bile statik UI korunur.
  result <- env$mergen_build_index_ui(
    static_ui,
    enabled = TRUE,
    render_page_fn = "fonksiyon-degil"
  )
  expect_identical(result, static_ui)
})

test_that("MERGEN_CACHE_INDEX_HTML bayrağı doğru çözülür", {
  env <- .index_cache_env()

  withr::with_envvar(c(MERGEN_CACHE_INDEX_HTML = ""), {
    expect_true(env$mergen_index_html_cache_enabled())  # varsayılan AÇIK
  })
  withr::with_envvar(c(MERGEN_CACHE_INDEX_HTML = "true"), {
    expect_true(env$mergen_index_html_cache_enabled())
  })
  for (off in c("false", "0", "off", "no", "hayir", "kapali")) {
    withr::with_envvar(c(MERGEN_CACHE_INDEX_HTML = off), {
      expect_false(env$mergen_index_html_cache_enabled())
    })
  }
})

test_that("mergen_resolve_render_page_fn Shiny renderPage'i çözer", {
  skip_if_not_installed("shiny")
  env <- .index_cache_env()
  fn <- env$mergen_resolve_render_page_fn()
  expect_true(is.function(fn))
})
