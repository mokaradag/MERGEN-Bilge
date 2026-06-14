# ==============================================================================
# Dosya Yolu: tests/testthat/test-mcp-prepare-chart-data-behavior.R
# Açıklama: helpers_mcp_chart_tools.R içindeki grafik veri hazırlama aracının
#           (kaynak-zamanı .mcp_prepare_chart_data_fn olarak tanımlanıp
#           helpers_mcp_tools$prepare_chart_data'ya atanan ve sonra rm edilen
#           fonksiyon) DETERMİNİSTİK erken-dönüş dallarını doğrular: dosya
#           çözülemezse (resolve_file_argument$ok = FALSE) ve dosya okunamazsa
#           (safe_read_table_generic hata fırlatır) yapılandırılmış
#           list(error=, ok=FALSE) döner. Derin grafik üretim mantığı
#           test-mcp-chart-tools-refactor-contract.R + grafik testleriyle korunur;
#           burada güvenli erken-çıkış + argüman normalizasyonu hedeflenir.
#
#           Runtime'da fonksiyon yalnızca helpers_mcp_tools$prepare_chart_data
#           üzerinden erişilebilir (top-level .mcp_prepare_chart_data_fn kaynak
#           sonunda rm edilir). MCP zinciri globalenv'e yüklenir; yaprak araçlar
#           test başına override edilip geri yüklenir (batch kirliliği yok).
#           Gerçek dosya/DB/LLM yoktur; çevrimdışı ve deterministik.
# ==============================================================================

# Türkçe yorum: MCP zincirini globalenv'e tekil yükler ve .mcp_prepare_chart_data_fn'i
# döndürür. Zincir zaten yüklüyse tekrar yüklenmez.
.chartDataChain <- function() {
  if (exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE) &&
      exists(".mcp_prepare_chart_data_fn", envir = globalenv(), inherits = FALSE)) {
    return(invisible(get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)))
  }
  rr <- resolve_repo_root_for_tests()
  files <- c(
    "R/helpers_mcp_context.R",
    "R/helpers_mcp_bootstrap.R",
    "R/helpers_mcp_table_readers.R",
    "R/helpers_mcp_file_resolver.R",
    "R/helpers_mcp_schema_helpers.R",
    "R/helpers_mcp_basic_tools.R",
    "R/helpers_mcp_chart_tools.R",
    "R/helpers_mcp_analyze_visualize.R",
    "R/helpers_mcp_tools.R"
  )
  for (f in files) source(file.path(rr, f), encoding = "UTF-8", local = globalenv())
  invisible(get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE))
}

# Türkçe yorum: helpers_mcp_tools yaprak fonksiyonlarını override eder; orijinalleri
# çağıran test_that frame'i sonunda geri yükler (batch'te diğer MCP testleri etkilenmez).
.overrideChartLeaves <- function(hmt, overrides, env_frame = parent.frame()) {
  nms <- names(overrides)
  originals <- stats::setNames(lapply(nms, function(nm) {
    if (exists(nm, envir = hmt, inherits = FALSE)) get(nm, envir = hmt, inherits = FALSE) else NULL
  }), nms)
  withr::defer({
    for (nm in nms) {
      if (is.null(originals[[nm]])) {
        if (exists(nm, envir = hmt, inherits = FALSE)) rm(list = nm, envir = hmt)
      } else {
        assign(nm, originals[[nm]], envir = hmt)
      }
    }
  }, envir = env_frame)
  for (nm in nms) assign(nm, overrides[[nm]], envir = hmt)
}

.chartDataFn <- function(hmt) hmt$prepare_chart_data

test_that("prepare_chart_data dosya çözülemezse ok=FALSE + hata döner", {
  hmt <- .chartDataChain()
  .overrideChartLeaves(hmt, list(
    auto_file_name = function(file_name, session) file_name,
    normalize_chart_type = function(chart_type) chart_type,
    resolve_file_argument = function(file_name, session) list(ok = FALSE, error = "dosya bulunamadı")
  ))
  fn <- .chartDataFn(hmt)
  res <- fn(file_name = "x.xlsx", chart_type = "bar", session = NULL)
  expect_false(isTRUE(res$ok))
  expect_identical(res$error, "dosya bulunamadı")
})

test_that("prepare_chart_data dosya okunamazsa ok=FALSE + 'Dosya okunamadı' döner", {
  hmt <- .chartDataChain()
  .overrideChartLeaves(hmt, list(
    auto_file_name = function(file_name, session) file_name,
    normalize_chart_type = function(chart_type) chart_type,
    resolve_file_argument = function(file_name, session) list(ok = TRUE, path = "/tmp/olmayan.xlsx"),
    safe_read_table_generic = function(path) stop("okuma patladı")
  ))
  fn <- .chartDataFn(hmt)
  res <- fn(file_name = "x.xlsx", chart_type = "bar", session = NULL)
  expect_false(isTRUE(res$ok))
  expect_true(grepl("Dosya okunamadı", res$error, fixed = TRUE))
})

test_that("prepare_chart_data auto_file_name ve normalize_chart_type'ı uygular", {
  hmt <- .chartDataChain()
  yakalanan <- new.env(parent = emptyenv())
  .overrideChartLeaves(hmt, list(
    auto_file_name = function(file_name, session) { yakalanan$file_name <- file_name; "cozumlenmis.xlsx" },
    normalize_chart_type = function(chart_type) { yakalanan$chart_type <- chart_type; "bar" },
    # Türkçe yorum: çözümlemeyi erken-çıkışla sonlandır (derin mantığa girmeden)
    resolve_file_argument = function(file_name, session) {
      yakalanan$resolved_name <- file_name
      list(ok = FALSE, error = "erken çıkış")
    }
  ))
  fn <- .chartDataFn(hmt)
  res <- fn(file_name = "GİRDİ.xlsx", chart_type = "BAR", session = NULL)
  expect_false(isTRUE(res$ok))
  # Türkçe yorum: auto_file_name/normalize_chart_type girdileri normalize edip
  # resolve_file_argument'a çözümlenmiş dosya adı geçirilmeli
  expect_identical(yakalanan$file_name, "GİRDİ.xlsx")
  expect_identical(yakalanan$chart_type, "BAR")
  expect_identical(yakalanan$resolved_name, "cozumlenmis.xlsx")
})
