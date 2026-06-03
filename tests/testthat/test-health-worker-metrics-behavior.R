# ==============================================================================
# Dosya Yolu: tests/testthat/test-health-worker-metrics-behavior.R
# Açıklama: R/module_health_worker_metrics.R içindeki render_worker_health_html()
#           saf HTML biçimlendiricisinin DAVRANIŞSAL testleri. Bu dosya daha önce
#           hiçbir test tarafından çağrılmıyordu.
#
#           render_worker_health_html() bir worker_info listesini sprintf ile
#           HTML'e çevirir; iş türü dağılımı varsa <br> ile listeler, yoksa
#           "Aktif asenkron iş yok" gösterir. Saf fonksiyon; yalnızca %||% ve
#           HTML() gerekir. Ağ/DB/LLM/tarayıcı GEREKMEZ.
# ==============================================================================

.source_worker_metrics_for_test <- function() {
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  # HTML() htmltools/shiny'den gelir; izole ortamda erişilebilir olması için
  # htmltools::HTML köprülenir.
  env$HTML <- function(text) htmltools::HTML(text)
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_health_worker_metrics.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

.sample_worker_info <- function(breakdown = NULL) {
  list(
    total_workers = 6L,
    free_workers = 4L,
    active_workers = 2L,
    active_jobs = 2L,
    queued_jobs = 1L,
    usage_pct = 33.3,
    note = "On-prem işçi havuzu özeti",
    task_type_breakdown = breakdown
  )
}

testthat::test_that("render_worker_health_html tüm sayısal alanları HTML'e yazar", {
  testthat::skip_if_not_installed("htmltools")
  env <- .source_worker_metrics_for_test()

  html <- as.character(env$render_worker_health_html(.sample_worker_info()))
  testthat::expect_true(grepl("Toplam İşçi:", html, fixed = TRUE))
  testthat::expect_true(grepl(">6<", html, fixed = TRUE))   # total_workers
  testthat::expect_true(grepl(">4<", html, fixed = TRUE))   # free_workers
  testthat::expect_true(grepl("Aktif İşçi:", html, fixed = TRUE))
  testthat::expect_true(grepl("Kuyruktaki İş:", html, fixed = TRUE))
  # usage_pct %.1f%% biçiminde.
  testthat::expect_true(grepl("33.3%", html, fixed = TRUE))
  testthat::expect_true(grepl("On-prem işçi havuzu özeti", html, fixed = TRUE))
})

testthat::test_that("render_worker_health_html iş türü dağılımını <br> ile listeler", {
  testthat::skip_if_not_installed("htmltools")
  env <- .source_worker_metrics_for_test()

  breakdown <- list(llm_streaming = 3L, image_generation = 1L)
  html <- as.character(env$render_worker_health_html(.sample_worker_info(breakdown)))
  testthat::expect_true(grepl("llm_streaming: 3", html, fixed = TRUE))
  testthat::expect_true(grepl("image_generation: 1", html, fixed = TRUE))
  testthat::expect_true(grepl("İş Türleri:", html, fixed = TRUE))
})

testthat::test_that("render_worker_health_html boş dağılımda 'Aktif asenkron iş yok' gösterir", {
  testthat::skip_if_not_installed("htmltools")
  env <- .source_worker_metrics_for_test()

  # task_type_breakdown NULL -> %||% list() -> boş -> fallback metin.
  html <- as.character(env$render_worker_health_html(.sample_worker_info(NULL)))
  testthat::expect_true(grepl("Aktif asenkron iş yok", html, fixed = TRUE))

  html_bos <- as.character(env$render_worker_health_html(.sample_worker_info(list())))
  testthat::expect_true(grepl("Aktif asenkron iş yok", html_bos, fixed = TRUE))
})

testthat::test_that("render_worker_health_html htmltools HTML işaretli çıktı döndürür", {
  testthat::skip_if_not_installed("htmltools")
  env <- .source_worker_metrics_for_test()
  out <- env$render_worker_health_html(.sample_worker_info())
  testthat::expect_s3_class(out, "html")
})
