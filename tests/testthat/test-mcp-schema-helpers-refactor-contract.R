# ==============================================================================
# Dosya Yolu: tests/testthat/test-mcp-schema-helpers-refactor-contract.R
# Açıklama: MCP şema/kolon/argüman yardımcılarının helpers_mcp_tools monolitinden
#           ayrı dosyada kaldığını ve worker ortam sözleşmesini koruduğunu doğrular.
# ==============================================================================

.read_repo_text_quiet_mcp_schema <- function(path) {
  repo_root <- if (exists("resolve_repo_root_for_tests", mode = "function")) {
    resolve_repo_root_for_tests()
  } else {
    normalizePath(".", winslash = "/", mustWork = TRUE)
  }

  full_path <- file.path(repo_root, path)
  size <- suppressWarnings(file.info(full_path)$size[1])

  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  if (length(raw_data) >= 3L &&
      identical(as.integer(raw_data[1:3]), c(239L, 187L, 191L))) {
    raw_data <- raw_data[-(1:3)]
  }

  raw_data <- raw_data[raw_data != as.raw(0)]
  txt <- rawToChar(raw_data, multiple = FALSE)
  Encoding(txt) <- "UTF-8"
  txt <- enc2utf8(txt)
  gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
}

local({
  gerekli_dosyalar <- c(
    file.path(repo_root_for_tests, "R", "utils_common.R"),
    file.path(repo_root_for_tests, "R", "utils_path_helpers.R"),
    file.path(repo_root_for_tests, "R", "helpers_files.R"),
    file.path(repo_root_for_tests, "R", "utils_excel_reader.R"),
    file.path(repo_root_for_tests, "R", "helpers_mcp_context.R"),
    file.path(repo_root_for_tests, "R", "helpers_mcp_bootstrap.R"),
    file.path(repo_root_for_tests, "R", "helpers_mcp_tools.R"),
    file.path(repo_root_for_tests, "R", "helpers_mcp_table_readers.R"),
    file.path(repo_root_for_tests, "R", "helpers_mcp_file_resolver.R"),
    file.path(repo_root_for_tests, "R", "helpers_mcp_schema_helpers.R")
  )

  for (dosya in gerekli_dosyalar) {
    source(dosya, encoding = "UTF-8", local = globalenv())
  }
})

test_that("MCP şema ve argüman yardımcıları ayrı dosyada tutulur", {
  tools_txt <- .read_repo_text_quiet_mcp_schema("R/helpers_mcp_tools.R")
  bootstrap_txt <- .read_repo_text_quiet_mcp_schema("R/helpers_mcp_bootstrap.R")
  schema_txt <- .read_repo_text_quiet_mcp_schema("R/helpers_mcp_schema_helpers.R")

  expected_defs <- c(
    "helpers_mcp_tools$extract_mcp_file_schema <- function",
    "helpers_mcp_tools$find_matching_column <- function",
    "helpers_mcp_tools$find_columns_by_context <- function",
    "helpers_mcp_tools$normalize_args <- function",
    "helpers_mcp_tools$normalize_chart_type <- function",
    "helpers_mcp_tools$prettify_column_name <- function",
    "helpers_mcp_tools$prettify_result_colnames <- function"
  )

  tools_has_defs <- vapply(
    expected_defs,
    function(x) grepl(x, tools_txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  schema_has_defs <- vapply(
    expected_defs,
    function(x) grepl(x, schema_txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_false(
    any(tools_has_defs),
    info = "MCP şema/kolon/argüman helper tanımları helpers_mcp_tools.R içine geri taşınmamalıdır."
  )

  expect_true(
    all(schema_has_defs),
    info = paste("Eksik MCP şema helper tanımları:", paste(expected_defs[!schema_has_defs], collapse = ", "))
  )

  expect_true(
    grepl("R/helpers_mcp_bootstrap.R", tools_txt, fixed = TRUE, useBytes = TRUE),
    info = "helpers_mcp_tools.R tekil source/test bağlamları için MCP bootstrap dosyasını güvenli şekilde yüklemelidir."
  )

  expect_true(
    grepl("R/helpers_mcp_schema_helpers.R", bootstrap_txt, fixed = TRUE, useBytes = TRUE),
    info = "helpers_mcp_bootstrap.R şema helper dosyasını tekil source/test bağlamları için güvenli şekilde yüklemelidir."
  )

  expect_true(
    grepl('exists(".mcp_schema_helpers_path"', bootstrap_txt, fixed = TRUE, useBytes = TRUE),
    info = "helpers_mcp_bootstrap.R .mcp_schema_helpers_path temizliğini değişken varsa yapmalıdır."
  )

  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_mcp_context.R",
      "R/helpers_mcp_bootstrap.R",
      "R/helpers_mcp_tools.R",
      "R/helpers_mcp_table_readers.R",
      "R/helpers_mcp_file_resolver.R",
      "R/helpers_mcp_schema_helpers.R"
    ),
    label = "MCP source sırası context -> bootstrap -> tools -> table_readers -> file_resolver -> schema_helpers olmalıdır:"
  )
})

test_that("MCP şema helper fonksiyonları helpers_mcp_tools ortamında çalışır", {
  expected_functions <- c(
    "extract_mcp_file_schema",
    "find_matching_column",
    "find_columns_by_context",
    "normalize_args",
    "normalize_chart_type",
    "prettify_column_name",
    "prettify_result_colnames"
  )

  for (fn in expected_functions) {
    expect_true(
      exists(fn, envir = helpers_mcp_tools, inherits = FALSE),
      info = paste("Eksik helpers_mcp_tools fonksiyonu:", fn)
    )

    fun <- get(fn, envir = helpers_mcp_tools, inherits = FALSE)

    expect_true(
      is.function(fun),
      info = paste("helpers_mcp_tools içindeki değer fonksiyon olmalıdır:", fn)
    )

    expect_identical(
      environment(fun),
      helpers_mcp_tools,
      info = paste("MCP helper worker/tool bağlamında helpers_mcp_tools ortamında çalışmalıdır:", fn)
    )
  }
})

test_that("MCP argüman ve kolon yardımcılarının temel davranışı korunur", {
  args <- helpers_mcp_tools$normalize_args(list(
    filename = "ornek.xlsx",
    col = "Maas",
    query = "SELECT * FROM data"
  ))

  expect_identical(args$file_name, "ornek.xlsx")
  expect_identical(args$column, "Maas")
  expect_identical(args$sql, "SELECT * FROM data")

  expect_identical(
    helpers_mcp_tools$normalize_chart_type("çizgi grafiği"),
    "line"
  )

  expect_identical(
    helpers_mcp_tools$normalize_chart_type("halka"),
    "donut"
  )

  expect_identical(
    helpers_mcp_tools$normalize_chart_type("boxplot"),
    "hist"
  )

  cols <- c("EmployeeName", "Maas_TL", "Departman")
  expect_identical(
    helpers_mcp_tools$find_matching_column("maaş", cols),
    "Maas_TL"
  )
  
  expect_identical(
    helpers_mcp_tools$find_matching_column("maas", cols),
    "Maas_TL"
  )

  df <- data.frame(
    Maas_TL = c(100, 120),
    Departman = c("IT", "IK"),
    stringsAsFactors = FALSE
  )

  matches <- helpers_mcp_tools$find_columns_by_context(df, c("maaş", "maas", "departman"))

  expect_identical(matches[["maaş"]], "Maas_TL")
  expect_identical(matches[["maas"]], "Maas_TL")
  expect_identical(matches[["departman"]], "Departman")
})