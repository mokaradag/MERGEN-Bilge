# ==============================================================================
# Dosya Yolu: tests/testthat/test-chart-engine-highcharter-only-contract.R
# Açıklama: Grafik render yolu artık tek motorludur (highcharter). plotly+ggplot2
#           fallback render yolu kaldırıldı (üretimde grafikler her zaman
#           highcharter ile üretilir). Bu sözleşme:
#             1) plotly/ggplot2 render fallback'inin geri dönmediğini,
#             2) highcharter render yolunun ve highcharter-yoksa zarif hata
#                (renderUI) davranışının korunduğunu doğrular.
#           Statik, bayt-güvenli kaynak taramasıdır; highcharter kurulu olmasa
#           bile çalışır.
# ==============================================================================

testthat::local_edition(3)

.read_repo_text_chart_engine <- function(path) {
  full_path <- file.path(resolve_repo_root_for_tests(), path)
  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }
  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )
  if (is.na(txt)) {
    txt <- ""
  }
  enc2utf8(txt)
}

.chart_engine_render_files <- c(
  "R/helpers_chartlab.R",
  "R/module_chartlab.R"
)

# Render fallback'inin işaretçileri. Bunlar grafik render dosyalarında
# görünmemelidir.
.chart_engine_forbidden <- c(
  "plotly::",
  "renderPlotly",
  "plotlyOutput",
  "ggplotly",
  "ggplot(",
  "geom_",
  "have_pl("
)

test_that("grafik render dosyaları plotly/ggplot2 render fallback'i içermez", {
  for (path in .chart_engine_render_files) {
    txt <- .read_repo_text_chart_engine(path)
    leaked <- .chart_engine_forbidden[vapply(
      .chart_engine_forbidden,
      function(tok) grepl(tok, txt, fixed = TRUE),
      logical(1)
    )]
    expect_equal(
      leaked,
      character(0),
      info = sprintf(
        "%s içinde kaldırılmış plotly/ggplot2 render fallback işaretçileri bulundu: %s",
        path, paste(leaked, collapse = ", ")
      )
    )
  }
})

test_that("grafik render dosyaları highcharter render yolunu korur", {
  for (path in .chart_engine_render_files) {
    txt <- .read_repo_text_chart_engine(path)
    expect_true(
      grepl("highchartOutput", txt, fixed = TRUE),
      info = sprintf("%s highchartOutput container'ını korumalıdır.", path)
    )
    expect_true(
      grepl("renderHighchart", txt, fixed = TRUE),
      info = sprintf("%s renderHighchart render yolunu korumalıdır.", path)
    )
  }
})

test_that("highcharter yoksa zarif hata (renderUI) davranışı korunur", {
  for (path in .chart_engine_render_files) {
    txt <- .read_repo_text_chart_engine(path)
    expect_true(
      grepl("renderUI", txt, fixed = TRUE),
      info = sprintf("%s highcharter yokken renderUI hata yolunu korumalıdır.", path)
    )
    # Hata mesajı artık yalnızca highcharter'a atıf yapar; plotly/ggplot2 önermez.
    expect_false(
      grepl("plotly+ggplot2", txt, fixed = TRUE),
      info = sprintf("%s hata mesajı plotly+ggplot2 önermemelidir.", path)
    )
  }
})

test_that("config_file_store.R kullanılmayan görselleştirme bayraklarını tanımlamaz", {
  txt <- .read_repo_text_chart_engine("R/config_file_store.R")
  expect_false(
    grepl("have_plotly_gg", txt, fixed = TRUE),
    info = "Kullanılmayan have_plotly_gg bayrağı kaldırılmalıdır."
  )
  expect_false(
    grepl("have_highcharter", txt, fixed = TRUE),
    info = "Kullanılmayan have_highcharter bayrağı kaldırılmalıdır."
  )
})

test_that("plotly çalışma zamanı (R + ui.R + server.R) kodundan tamamen kaldırıldı", {
  repo_root <- resolve_repo_root_for_tests()
  runtime_files <- c(
    list.files(file.path(repo_root, "R"), pattern = "\\.R$", full.names = FALSE) |>
      (\(x) file.path("R", x))(),
    "ui.R",
    "server.R"
  )

  # Yalnızca gerçek kod desenleri taranır; yorumlardaki "plotly" kelimesine
  # (kaldırma açıklaması gibi) takılmaz.
  forbidden_code <- c(
    "plotly::", "\"plotly\"", "plotlyOutput", "renderPlotly",
    "plotly_empty", "plotly_html", "deps_pl"
  )

  offenders <- character(0)
  for (path in runtime_files) {
    full <- file.path(repo_root, path)
    if (!file.exists(full)) next
    txt <- .read_repo_text_chart_engine(path)
    hits <- forbidden_code[vapply(
      forbidden_code,
      function(tok) grepl(tok, txt, fixed = TRUE),
      logical(1)
    )]
    if (length(hits)) {
      offenders <- c(offenders, sprintf("%s -> %s", path, paste(hits, collapse = ", ")))
    }
  }

  expect_equal(
    offenders,
    character(0),
    info = paste(
      "Çalışma zamanı kodunda plotly bağımlılık referansları bulundu:",
      paste(offenders, collapse = " | ")
    )
  )
})
