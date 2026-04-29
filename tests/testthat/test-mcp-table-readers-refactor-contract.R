# ==============================================================================
# Dosya Yolu: tests/testthat/test-mcp-table-readers-refactor-contract.R
# Açıklama: MCP tablo okuyucularının helpers_mcp_tools monolitinden ayrı dosyada
#           kaldığını ve temel okuma/Markdown sözleşmesini koruduğunu doğrular.
# ==============================================================================

.read_repo_text_quiet_mcp_table <- function(path) {
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
  gsub("\\r\\n?|\\r", "\\n", txt, perl = TRUE)
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
    file.path(repo_root_for_tests, "R", "helpers_mcp_table_readers.R")
  )

  for (dosya in gerekli_dosyalar) {
    source(dosya, encoding = "UTF-8", local = globalenv())
  }
})

test_that("MCP tablo okuyucuları ayrı dosyada tutulur", {
  tools_txt <- .read_repo_text_quiet_mcp_table("R/helpers_mcp_tools.R")
  bootstrap_txt <- .read_repo_text_quiet_mcp_table("R/helpers_mcp_bootstrap.R")
  table_txt <- .read_repo_text_quiet_mcp_table("R/helpers_mcp_table_readers.R")
  global_txt <- .read_repo_text_quiet_mcp_table("global.R")

  expected_defs <- c(
    "helpers_mcp_tools$safe_read_excel_table <- function",
    "helpers_mcp_tools$safe_read_table_generic <- function",
    "helpers_mcp_tools$create_md_table <- function"
  )

  tools_has_defs <- vapply(
    expected_defs,
    function(x) grepl(x, tools_txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  table_has_defs <- vapply(
    expected_defs,
    function(x) grepl(x, table_txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_false(
    any(tools_has_defs),
    info = "MCP tablo okuyucu fonksiyon tanımları helpers_mcp_tools.R içine geri taşınmamalıdır."
  )

  expect_true(
    grepl("R/helpers_mcp_bootstrap.R", tools_txt, fixed = TRUE, useBytes = TRUE),
    info = "helpers_mcp_tools.R tekil source/test bağlamları için MCP bootstrap dosyasını güvenli şekilde yüklemelidir."
  )

  expect_true(
    grepl("R/helpers_mcp_table_readers.R", bootstrap_txt, fixed = TRUE, useBytes = TRUE),
    info = "helpers_mcp_bootstrap.R tablo okuyucu dosyasını tekil source/test bağlamları için güvenli şekilde yüklemelidir."
  )
  
  expect_true(
    grepl("mcp_tools_find_support_file", bootstrap_txt, fixed = TRUE, useBytes = TRUE),
    info = "helpers_mcp_bootstrap.R tablo okuyucu dosyasını working-directory bağımsız çözmelidir."
  )

  expect_true(
    grepl('exists(".mcp_table_readers_path"', bootstrap_txt, fixed = TRUE, useBytes = TRUE),
    info = "helpers_mcp_bootstrap.R .mcp_table_readers_path temizliğini değişken varsa yapmalıdır."
  )

  expect_false(
    grepl(
      "environment(get(.mcp_reader_fn",
      table_txt,
      fixed = TRUE,
      useBytes = TRUE
    ),
    info = "Fonksiyon environment ataması doğrudan get(.mcp_reader_fn, ...) sol tarafına yapılmamalıdır; bu R'de get<- hatası üretir."
  )

  expect_true(
    grepl(
      ".mcp_reader_fun <- get(.mcp_reader_fn, envir = helpers_mcp_tools, inherits = FALSE)",
      table_txt,
      fixed = TRUE,
      useBytes = TRUE
    ),
    info = "MCP reader önce geçici fonksiyon nesnesine alınmalıdır."
  )

  expect_true(
    grepl(
      "environment(.mcp_reader_fun) <- helpers_mcp_tools",
      table_txt,
      fixed = TRUE,
      useBytes = TRUE
    ),
    info = "MCP reader environment ataması geçici fonksiyon nesnesi üzerinden yapılmalıdır."
  )

  expect_true(
    grepl(
      "assign(.mcp_reader_fn, .mcp_reader_fun, envir = helpers_mcp_tools)",
      table_txt,
      fixed = TRUE,
      useBytes = TRUE
    ),
    info = "MCP reader environment ataması sonrası fonksiyon helpers_mcp_tools ortamına geri assign edilmelidir."
  )

  expect_true(
    all(table_has_defs),
    info = paste("Eksik MCP tablo okuyucu tanımları:", paste(expected_defs[!table_has_defs], collapse = ", "))
  )

  expect_true(
    grepl('safe_source("R/helpers_mcp_table_readers.R"', global_txt, fixed = TRUE, useBytes = TRUE),
    info = "helpers_mcp_table_readers.R global.R manifestinde açıkça yüklenmelidir."
  )
})

test_that("MCP Excel okuyucu worker ortamında normalize_excel_path yardımcısını bulabilir", {
  expect_true(exists("safe_read_excel_table", envir = helpers_mcp_tools, inherits = FALSE))
  expect_true(is.function(helpers_mcp_tools$safe_read_excel_table))

  reader_env <- environment(helpers_mcp_tools$safe_read_excel_table)

  expect_identical(
    reader_env,
    helpers_mcp_tools,
    info = "safe_read_excel_table MCP/worker bağlamında helpers_mcp_tools ortamında çalışmalıdır."
  )

  expect_true(
    exists("normalize_excel_path", envir = reader_env, inherits = TRUE),
    info = "safe_read_excel_table çalışırken normalize_excel_path görünür olmalıdır."
  )

  expect_true(
    exists("resolve_readable_path", envir = reader_env, inherits = TRUE),
    info = "safe_read_excel_table çalışırken resolve_readable_path görünür olmalıdır."
  )

  expect_true(
    exists("path_exists_relaxed", envir = reader_env, inherits = TRUE),
    info = "safe_read_excel_table çalışırken path_exists_relaxed görünür olmalıdır."
  )
})

test_that("MCP genel tablo okuyucu CSV dosyasını data.table olarak okur", {
  skip_if_not_installed("data.table")

  temp_dir <- withr::local_tempdir()
  csv_path <- file.path(temp_dir, "mcp_table_reader_test.csv")

  writeLines(
    c(
      "CalisanID,Departman,Maas",
      "1,IT,100",
      "2,IK,120"
    ),
    csv_path,
    useBytes = TRUE
  )

  sonuc <- helpers_mcp_tools$safe_read_table_generic(csv_path)

  expect_s3_class(sonuc, "data.table")
  expect_equal(names(sonuc), c("CalisanID", "Departman", "Maas"))
  expect_equal(nrow(sonuc), 2)
})

test_that("MCP Markdown tablo üretici temel tablo sözleşmesini korur", {
  df <- data.frame(
    CalisanID = c(1, 2),
    Departman = c("IT", "IK"),
    Maas = c(100, 120),
    stringsAsFactors = FALSE
  )

  md <- helpers_mcp_tools$create_md_table(df)

  expect_true(grepl("| CalisanID | Departman | Maas |", md, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("| --- | --- | --- |", md, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("| 1 | IT | 100 |", md, fixed = TRUE, useBytes = TRUE))
})