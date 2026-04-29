# ==============================================================================
# Dosya Yolu: tests/testthat/test-mcp-basic-tools-refactor-contract.R
# Açıklama: MCP temel dosya/istatistik/SQL araçlarının helpers_mcp_tools
#           monolitinden ayrı dosyada kaldığını ve worker ortamı sözleşmesini
#           koruduğunu doğrular.
# ==============================================================================

.read_repo_text_quiet_mcp_basic <- function(path) {
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
    file.path(repo_root_for_tests, "R", "helpers_mcp_schema_helpers.R"),
    file.path(repo_root_for_tests, "R", "helpers_mcp_basic_tools.R")
  )

  for (dosya in gerekli_dosyalar) {
    source(dosya, encoding = "UTF-8", local = globalenv())
  }
})

test_that("MCP temel araçları ayrı dosyada tutulur", {
  tools_txt <- .read_repo_text_quiet_mcp_basic("R/helpers_mcp_tools.R")
  basic_txt <- .read_repo_text_quiet_mcp_basic("R/helpers_mcp_basic_tools.R")
  global_txt <- .read_repo_text_quiet_mcp_basic("global.R")

  expected_defs <- c(
    "helpers_mcp_tools$safe_has_duckdb <- function",
    "helpers_mcp_tools$analyze_uploaded_file <- function",
    "helpers_mcp_tools$get_column_statistics <- function",
    "helpers_mcp_tools$sql_query_uploaded_file <- function"
  )

  tools_has_defs <- vapply(
    expected_defs,
    function(x) grepl(x, tools_txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  basic_has_defs <- vapply(
    expected_defs,
    function(x) grepl(x, basic_txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_false(
    any(tools_has_defs),
    info = "MCP temel araç fonksiyon tanımları helpers_mcp_tools.R içine geri taşınmamalıdır."
  )

  expect_true(
    all(basic_has_defs),
    info = paste("Eksik MCP temel araç tanımları:", paste(expected_defs[!basic_has_defs], collapse = ", "))
  )

  expect_true(
    grepl("R/helpers_mcp_basic_tools.R", tools_txt, fixed = TRUE, useBytes = TRUE),
    info = "helpers_mcp_tools.R temel araç dosyasını tekil source/test bağlamları için güvenli şekilde yüklemelidir."
  )

  expect_true(
    grepl('safe_source("R/helpers_mcp_basic_tools.R"', global_txt, fixed = TRUE, useBytes = TRUE),
    info = "helpers_mcp_basic_tools.R global.R manifestinde açıkça yüklenmelidir."
  )
})

test_that("MCP temel araçları helpers_mcp_tools worker ortamında çalışır", {
  expected_fns <- c(
    "safe_has_duckdb",
    "analyze_uploaded_file",
    "get_column_statistics",
    "sql_query_uploaded_file"
  )

  for (fn in expected_fns) {
    expect_true(exists(fn, envir = helpers_mcp_tools, inherits = FALSE))
    expect_true(is.function(get(fn, envir = helpers_mcp_tools, inherits = FALSE)))

    expect_identical(
      environment(get(fn, envir = helpers_mcp_tools, inherits = FALSE)),
      helpers_mcp_tools,
      info = sprintf("%s MCP/worker bağlamında helpers_mcp_tools ortamında çalışmalıdır.", fn)
    )
  }
})

test_that("MCP dosya özeti aracı public davranışını korur", {
  old_resolver <- helpers_mcp_tools$resolve_file_argument
  old_auto_file_name <- helpers_mcp_tools$auto_file_name
  old_reader <- helpers_mcp_tools$safe_read_excel_table
  old_md_table <- helpers_mcp_tools$create_md_table

  withr::defer({
    helpers_mcp_tools$resolve_file_argument <- old_resolver
    helpers_mcp_tools$auto_file_name <- old_auto_file_name
    helpers_mcp_tools$safe_read_excel_table <- old_reader
    helpers_mcp_tools$create_md_table <- old_md_table
  })

  temp_dir <- withr::local_tempdir()
  fake_path <- file.path(temp_dir, "ornek.xlsx")
  writeLines("placeholder", fake_path, useBytes = TRUE)

  helpers_mcp_tools$auto_file_name <- function(file_name, session = NULL) {
    file_name
  }

  helpers_mcp_tools$resolve_file_argument <- function(file_name, session = NULL) {
    list(
      ok = TRUE,
      path = fake_path,
      display = "ornek.xlsx"
    )
  }

  helpers_mcp_tools$safe_read_excel_table <- function(path) {
    data.frame(
      Departman = c("IT", "IK"),
      Maas = c(100, 120),
      stringsAsFactors = FALSE
    )
  }

  helpers_mcp_tools$create_md_table <- function(df) {
    paste(capture.output(print(df, row.names = FALSE)), collapse = "\n")
  }

  sonuc <- helpers_mcp_tools$analyze_uploaded_file("ornek.xlsx")

  expect_true(is.list(sonuc))
  expect_null(sonuc$error)

  # Türkçe karakterli çıktı R/Windows yerel kodlamasında byte-byte
  # karşılaştırılmamalıdır. Bu test refactor sözleşmesini doğrular:
  # araç başarılı sonuç, dosya adı, satır/sütun sayısı ve sayısal özet üretmelidir.
  sonuc_text <- enc2utf8(paste(as.character(sonuc$result %||% ""), collapse = "\n"))

  expect_true(grepl("ornek.xlsx", sonuc_text, fixed = TRUE))
  expect_true(grepl("2", sonuc_text, fixed = TRUE))
  expect_true(grepl("Departman", sonuc_text, fixed = TRUE))
  expect_true(grepl("Maas", sonuc_text, fixed = TRUE))
  expect_true(grepl("100", sonuc_text, fixed = TRUE))
  expect_true(grepl("120", sonuc_text, fixed = TRUE))
})