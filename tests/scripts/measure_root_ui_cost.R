#!/usr/bin/env Rscript
# Diagnostics-only benchmark for root UI construction/serialization cost.
# This script does not start the Shiny app and does not define pass/fail criteria.

Sys.setenv(MERGEN_RUN_APP = "false")

source("app.R", encoding = "UTF-8")

measure_elapsed <- function(label, expr, n = 20L) {
  invisible(gc())
  elapsed <- system.time({
    for (i in seq_len(n)) {
      force(expr)
    }
  })[["elapsed"]]

  cat(sprintf("%s mean_ms=%.2f n=%d\n", label, elapsed / n * 1000, n))
}

measure_elapsed("ui.serialize", as.character(ui), n = 10L)
measure_elapsed("asset.tags.construct", ui_asset_tags(), n = 50L)
measure_elapsed("welcome.construct", createWelcomeScreen(list()), n = 100L)

welcome_for_serialize <- createWelcomeScreen(list())
measure_elapsed("welcome.serialize", as.character(welcome_for_serialize), n = 100L)

asset_tags <- ui_asset_tags()

cat(sprintf(
  "sizes ui_bytes=%d welcome_bytes=%d assets_bytes=%d css_count=%d js_count=%d\n",
  nchar(as.character(ui), type = "bytes"),
  nchar(as.character(welcome_for_serialize), type = "bytes"),
  nchar(as.character(asset_tags), type = "bytes"),
  length(ui_asset_all_css()),
  length(ui_asset_all_js())
))
