# ==============================================================================
# Dosya Yolu: tests/testthat/test-health-formatters-render-behavior.R
# Açıklama: R/helpers_health_formatters.R içindeki render yardımcılarının
#           davranışsal testleri: health_escape (HTML kaçışı), health_status_pill
#           (durum rozeti) ve health_render_value (durum->rozet / düz metin->kaçış).
#           Mevcut health testleri farklı fonksiyonları kapsar; bunlar kapsam dışıydı.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.hfmt_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_health_formatters.R"),
  encoding = "UTF-8",
  local = .hfmt_env
)

test_that("health_escape HTML özel karakterlerini kaçırır ve NULL'u boş stringe çevirir", {
  expect_equal(.hfmt_env$health_escape("<b>&x"), "&lt;b&gt;&amp;x")
  expect_equal(.hfmt_env$health_escape(NULL), "")
  # Türkçe karakter korunmalı.
  expect_equal(.hfmt_env$health_escape("Türkçe"), "Türkçe")
})

test_that("health_status_pill durum rozetini health-pill sınıfı ve tooltip ile üretir", {
  skip_if_not_installed("shiny")

  html <- paste(as.character(.hfmt_env$health_status_pill("ok")), collapse = "")
  expect_true(grepl("health-pill", html, fixed = TRUE))
  expect_true(grepl("data-health-tooltip", html, fixed = TRUE))
  expect_true(grepl("Durum:", html, fixed = TRUE))
})

test_that("health_render_value durum seviyesini rozet, düz metni kaçışlı string olarak döndürür", {
  skip_if_not_installed("shiny")

  # Durum seviyesi -> rozet (shiny tag).
  rozet <- .hfmt_env$health_render_value("ok")
  expect_true(grepl("health-pill", paste(as.character(rozet), collapse = ""), fixed = TRUE))

  # Düz metin -> HTML kaçışlı karakter dizisi.
  metin <- .hfmt_env$health_render_value("sıradan <b>metin")
  expect_true(is.character(metin))
  expect_equal(metin, "sıradan &lt;b&gt;metin")
})
