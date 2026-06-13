# ==============================================================================
# Dosya Yolu: tests/testthat/test-mcp-execute-parsed-tool-behavior.R
# Açıklama: helpers_mcp_tools$execute_parsed_tool yönlendirici davranışını
#           doğrular. Bu fonksiyon ayrıştırılmış araç çağrısını (tc) doğru MCP
#           yardımcısına yönlendirir, argüman alias'larını normalize eder ve
#           bilinmeyen/boş araç adlarını güvenle reddeder. Yaprak araç
#           fonksiyonları kaydedici (recorder) ile değiştirilir; gerçek dosya/
#           DB/LLM yoktur. MCP zinciri test-mcp-tools-parse-behavior.R ile aynı
#           sırayla globalenv'e yüklenir; yaprak araçlar test başına geri yüklenir
#           (batch kirliliği yok). Çevrimdışı ve deterministik.
# ==============================================================================

# Türkçe yorum: MCP zinciri globalenv'i ZORUNLU kılar (helpers_mcp_bootstrap.R
# helpers_mcp_tools'u globalenv'de arar). Bu yüzden zincir test-mcp-*-parse ile
# aynı şekilde globalenv'e yüklenir; tekil yükleme guard'ı vardır.
.mcp_execute_source_once <- function() {
  if (exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)) {
    hmt <- get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)
    if (is.environment(hmt) && is.function(hmt$execute_parsed_tool)) {
      return(invisible(hmt))
    }
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

# Türkçe yorum: Yaprak araçları recorder'larla değiştirir; orijinalleri çağıran
# test_that frame'inin sonunda geri yükler (withr::defer envir=parent.frame()),
# böylece batch'te diğer MCP testleri etkilenmez.
.install_tool_recorders <- function(env_frame = parent.frame()) {
  hmt <- .mcp_execute_source_once()
  leaf <- c(
    "analyze_uploaded_file", "get_column_statistics", "get_distinct_values",
    "sql_query_uploaded_file", "analyze_and_visualize", "prepare_chart_data"
  )
  originals <- stats::setNames(lapply(leaf, function(nm) {
    if (exists(nm, envir = hmt, inherits = FALSE)) get(nm, envir = hmt, inherits = FALSE) else NULL
  }), leaf)
  withr::defer({
    for (nm in leaf) {
      if (is.null(originals[[nm]])) {
        if (exists(nm, envir = hmt, inherits = FALSE)) rm(list = nm, envir = hmt)
      } else {
        assign(nm, originals[[nm]], envir = hmt)
      }
    }
  }, envir = env_frame)

  hmt$analyze_uploaded_file <- function(file_name, session = NULL) {
    list(tool = "analyze_uploaded_file", file_name = file_name)
  }
  hmt$get_column_statistics <- function(file_name, column, session = NULL) {
    list(tool = "get_column_statistics", file_name = file_name, column = column)
  }
  hmt$get_distinct_values <- function(file_name, column, limit = 50, session = NULL) {
    list(tool = "get_distinct_values", file_name = file_name, column = column, limit = limit)
  }
  hmt$sql_query_uploaded_file <- function(file_name, sql, session = NULL) {
    list(tool = "sql_query_uploaded_file", file_name = file_name, sql = sql)
  }
  hmt$analyze_and_visualize <- function(file_name, analysis_type = "summary", ...) {
    list(tool = "analyze_and_visualize", file_name = file_name, analysis_type = analysis_type)
  }
  hmt$prepare_chart_data <- function(file_name, chart_type = NULL, x = NULL, y = NULL, ...) {
    list(tool = "prepare_chart_data", file_name = file_name, chart_type = chart_type, x = x, y = y)
  }
  hmt
}

test_that("execute_parsed_tool boş/eksik araç adında hata döndürür", {
  hmt <- .install_tool_recorders()
  expect_identical(hmt$execute_parsed_tool(list(name = ""))$error, "Araç adı boş")
  expect_identical(hmt$execute_parsed_tool(list())$error, "Araç adı boş")
  expect_identical(hmt$execute_parsed_tool(list(arguments = list(x = 1)))$error, "Araç adı boş")
})

test_that("execute_parsed_tool bilinmeyen aracı reddeder", {
  hmt <- .install_tool_recorders()
  res <- hmt$execute_parsed_tool(list(name = "drop_database", arguments = list()))
  expect_true(grepl("Bilinmeyen araç: drop_database", res$error, fixed = TRUE))
})

test_that("execute_parsed_tool analyze_uploaded_file'a yönlendirir", {
  hmt <- .install_tool_recorders()
  res <- hmt$execute_parsed_tool(list(name = "analyze_uploaded_file", arguments = list(file_name = "rapor.xlsx")))
  expect_identical(res$tool, "analyze_uploaded_file")
  expect_identical(res$file_name, "rapor.xlsx")
})

test_that("execute_parsed_tool get_column_statistics'e kolon argümanıyla yönlendirir", {
  hmt <- .install_tool_recorders()
  res <- hmt$execute_parsed_tool(list(
    function_name = "get_column_statistics",
    parameters = list(file_name = "d.xlsx", column = "tutar")
  ))
  expect_identical(res$tool, "get_column_statistics")
  expect_identical(res$column, "tutar")
  # Türkçe yorum: get_column_stats alias'ı da aynı yardımcıya gitmeli
  res2 <- hmt$execute_parsed_tool(list(name = "get_column_stats", arguments = list(file_name = "d.xlsx", column = "ad")))
  expect_identical(res2$tool, "get_column_statistics")
  expect_identical(res2$column, "ad")
})

test_that("execute_parsed_tool get_distinct_values'ta limit varsayılanı 50'dir", {
  hmt <- .install_tool_recorders()
  res <- hmt$execute_parsed_tool(list(name = "get_distinct_values", arguments = list(file_name = "d.xlsx", column = "il")))
  expect_identical(res$tool, "get_distinct_values")
  expect_equal(res$limit, 50)
  res2 <- hmt$execute_parsed_tool(list(name = "get_distinct_values", arguments = list(file_name = "d.xlsx", column = "il", limit = 7)))
  expect_equal(res2$limit, 7)
})

test_that("execute_parsed_tool sql_query_uploaded_file'a sql ile yönlendirir", {
  hmt <- .install_tool_recorders()
  res <- hmt$execute_parsed_tool(list(
    name = "sql_query_uploaded_file",
    arguments = list(file_name = "d.xlsx", sql = "SELECT * FROM dosya")
  ))
  expect_identical(res$tool, "sql_query_uploaded_file")
  expect_true(grepl("SELECT", res$sql, fixed = TRUE))
})

test_that("execute_parsed_tool analyze_and_visualize'da analysis_type varsayılanı summary'dir", {
  hmt <- .install_tool_recorders()
  res <- hmt$execute_parsed_tool(list(name = "analyze_and_visualize", arguments = list(file_name = "d.xlsx")))
  expect_identical(res$tool, "analyze_and_visualize")
  expect_identical(res$analysis_type, "summary")
})

test_that("execute_parsed_tool prepare_chart_data'da x/y alias'larını çözer", {
  hmt <- .install_tool_recorders()
  # Türkçe yorum: x yoksa xlabel, sonra x_col denenmeli (alias zinciri)
  res <- hmt$execute_parsed_tool(list(
    name = "prepare_chart_data",
    arguments = list(file_name = "d.xlsx", chart_type = "bar", xlabel = "ay", y_col = "ciro")
  ))
  expect_identical(res$tool, "prepare_chart_data")
  expect_identical(res$chart_type, "bar")
  expect_identical(res$x, "ay")
  expect_identical(res$y, "ciro")
})

test_that("execute_parsed_tool araç adında büyük/küçük harfe duyarsızdır", {
  hmt <- .install_tool_recorders()
  res <- hmt$execute_parsed_tool(list(name = "ANALYZE_UPLOADED_FILE", arguments = list(file_name = "x.xlsx")))
  expect_identical(res$tool, "analyze_uploaded_file")
})
