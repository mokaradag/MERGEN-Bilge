# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-document-extractors-refactor-contract.R
# Açıklama: Bilge Yolaç doküman extractor yardımcılarının ayrı dosyaya
#           taşındığını, kaynak sırasının doğru olduğunu ve temel davranışların
#           korunduğunu doğrular.
# ==============================================================================

.read_repo_text_claude_doc_refactor <- function(rel_path) {
  abs_path <- file.path(repo_root_for_tests, rel_path)

  if (!file.exists(abs_path)) {
    stop(sprintf("Dosya bulunamadı: %s", rel_path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(abs_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(abs_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

test_that("helpers_claude_code_document_extractors.R exists and exposes extractor helpers", {
  helper_path <- file.path(
    repo_root_for_tests,
    "R",
    "helpers_claude_code_document_extractors.R"
  )

  expect_true(
    file.exists(helper_path),
    info = "R/helpers_claude_code_document_extractors.R dosyası eklenmelidir."
  )

  extract_env <- new.env(parent = globalenv())

  extract_env$`%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }

  extract_env$get_claude_code_model_capabilities <- function() {
    list(binary_doc_extensions = c("pdf", "xlsx"))
  }

  extract_env$resolve_app_root <- function() {
    repo_root_for_tests
  }

  extract_env$safe_read_excel_table <- function(...) {
    data.frame()
  }

  source(helper_path, encoding = "UTF-8", local = extract_env)

  expected_functions <- c(
    "get_claude_code_binary_doc_extensions",
    "get_claude_code_text_extractable_extensions",
    "sanitize_claude_doc_cache_name",
    "truncate_claude_doc_text",
    "list_claude_code_binary_documents",
    "get_claude_code_document_support_dir",
    "extract_pdf_text_for_claude",
    "extract_excel_text_for_claude",
    "extract_docx_text_for_claude",
    "extract_supported_document_text_for_claude",
    "get_office_document_reader_template_path"
  )

  for (fn in expected_functions) {
    expect_true(
      exists(fn, envir = extract_env, mode = "function", inherits = FALSE),
      info = sprintf("Eksik extractor helper: %s", fn)
    )
  }
})

test_that("extractor helpers preserve extension, cache-name and truncation behavior", {
  extract_env <- new.env(parent = globalenv())

  extract_env$`%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }

  extract_env$get_claude_code_model_capabilities <- function() {
    list(binary_doc_extensions = c("pdf", "xlsx"))
  }

  extract_env$resolve_app_root <- function() {
    repo_root_for_tests
  }

  extract_env$safe_read_excel_table <- function(...) {
    data.frame()
  }

  source(
    file.path(repo_root_for_tests, "R", "helpers_claude_code_document_extractors.R"),
    encoding = "UTF-8",
    local = extract_env
  )

  exts <- extract_env$get_claude_code_binary_doc_extensions()
  expect_true("pdf" %in% exts)
  expect_true("xlsx" %in% exts)
  expect_true("docx" %in% exts)
  expect_true("doc" %in% exts)

  text_exts <- extract_env$get_claude_code_text_extractable_extensions()
  expect_equal(text_exts, c("pdf", "xlsx", "xls", "docx"))

  expect_equal(
    extract_env$sanitize_claude_doc_cache_name("Deneme Türkçe Dosya.xlsx"),
    "Deneme_T_rk_e_Dosya.xlsx"
  )

  long_text <- paste(rep("a", 20), collapse = "")
  truncated <- extract_env$truncate_claude_doc_text(long_text, max_karakter = 5L)

  expect_true(startsWith(truncated, "aaaaa"))
  expect_match(truncated, "[METIN KISALTILDI]", fixed = TRUE)

  expect_equal(
    extract_env$truncate_claude_doc_text("", max_karakter = 5L),
    ""
  )
})

test_that("runtime manifest sources document extractors before document context helpers", {
  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_claude_code_document_extractors.R",
      "R/helpers_claude_code_documents.R"
    ),
    label = "Extractor helper, helpers_claude_code_documents.R dosyasından önce yüklenmelidir:"
  )
})

test_that("helpers_claude_code_documents.R no longer owns extractor helper definitions", {
  documents_txt <- .read_repo_text_claude_doc_refactor(
    "R/helpers_claude_code_documents.R"
  )

  forbidden_inline_defs <- c(
    "get_claude_code_binary_doc_extensions <- function",
    "get_claude_code_text_extractable_extensions <- function",
    "sanitize_claude_doc_cache_name <- function",
    "truncate_claude_doc_text <- function",
    "list_claude_code_binary_documents <- function",
    "get_claude_code_document_support_dir <- function",
    "extract_pdf_text_for_claude <- function",
    "extract_excel_text_for_claude <- function",
    "extract_docx_text_for_claude <- function",
    "extract_supported_document_text_for_claude <- function",
    "get_office_document_reader_template_path <- function"
  )

  for (pattern in forbidden_inline_defs) {
    expect_false(
      grepl(pattern, documents_txt, fixed = TRUE),
      info = sprintf(
        "Bu extractor helper artık R/helpers_claude_code_document_extractors.R içinde olmalıdır: %s",
        pattern
      )
    )
  }

  expect_true(
    grepl("helpers_claude_code_document_extractors.R", documents_txt, fixed = TRUE),
    info = "Document context dosyası doğrudan source edildiğinde extractor fallback'ini korumalıdır."
  )
})