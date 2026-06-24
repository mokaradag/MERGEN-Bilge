# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-document-summary-refactor-contract.R
# Açıklama: Bilge Yolaç doküman ÖZETLEME orkestrasyonunun ayrı dosyaya
#           (R/helpers_claude_code_document_summary.R) taşındığını, kaynak
#           sırasının doğru olduğunu, documents.R'nin bu fonksiyonları artık
#           tanımlamadığını ama paylaşılan UTF-8 BOM yazıcıyı koruduğunu ve
#           temel davranışların korunduğunu doğrular. Shiny/DB/LLM/ağ gerektirmez.
# ==============================================================================

.read_repo_text_ccdoc_summary <- function(rel_path) {
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

# Atama biçimli fonksiyon ifadelerini sayar (inline `= function(` dahil); bu,
# maintainability raporuyla aynı metriktir.
.count_fn_ccdoc_summary <- function(txt) {
  hits <- gregexpr("(<-|=)\\s*function\\s*\\(", txt, perl = TRUE)[[1]]
  if (length(hits) == 1L && hits[1] == -1L) 0L else length(hits)
}

.source_ccdoc_summary_env <- function() {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  source(
    file.path(repo_root_for_tests, "R", "helpers_claude_code_document_summary.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

test_that("helpers_claude_code_document_summary.R exists and exposes summary helpers", {
  helper_path <- file.path(
    repo_root_for_tests,
    "R",
    "helpers_claude_code_document_summary.R"
  )

  expect_true(
    file.exists(helper_path),
    info = "R/helpers_claude_code_document_summary.R dosyası eklenmelidir."
  )

  env <- .source_ccdoc_summary_env()

  expected_functions <- c(
    "resolve_claude_code_document_detail_level",
    "write_claude_code_document_summary_file",
    "build_claude_code_document_summary_messages",
    "summarize_claude_code_documents_with_local_llm"
  )

  for (fn in expected_functions) {
    expect_true(
      exists(fn, envir = env, mode = "function", inherits = FALSE),
      info = sprintf("Eksik özet helper: %s", fn)
    )
  }
})

test_that("özet helperları detay seviyesi ve mesaj rollerini korur", {
  env <- .source_ccdoc_summary_env()

  expect_identical(env$resolve_claude_code_document_detail_level(""), "orta")
  expect_identical(env$resolve_claude_code_document_detail_level("detaylı açıkla"), "detayli")
  expect_identical(env$resolve_claude_code_document_detail_level("kısaca özet geç"), "kisa")

  mesajlar <- env$build_claude_code_document_summary_messages(
    list(prompt = "detaylı açıkla")
  )

  expect_equal(length(mesajlar), 2L)
  expect_identical(mesajlar[[1]]$role, "system")
  expect_identical(mesajlar[[2]]$role, "user")
  # Detaylı yönerge sistem mesajına işlenmelidir.
  expect_match(mesajlar[[1]]$content, "ayrıntılı", fixed = TRUE)
})

test_that("runtime manifest documents -> summary -> run_lifecycle sırasını korur", {
  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_claude_code_documents.R",
      "R/helpers_claude_code_document_summary.R",
      "R/helpers_claude_code_run_lifecycle.R"
    ),
    label = paste(
      "Doküman özet helper'ı documents.R'den SONRA, run_lifecycle.R'den ÖNCE",
      "yüklenmelidir:"
    )
  )
})

test_that("helpers_claude_code_documents.R artık özet fonksiyonlarını tanımlamaz", {
  documents_txt <- .read_repo_text_ccdoc_summary(
    "R/helpers_claude_code_documents.R"
  )

  forbidden_inline_defs <- c(
    "resolve_claude_code_document_detail_level <- function",
    "write_claude_code_document_summary_file <- function",
    "build_claude_code_document_summary_messages <- function",
    "summarize_claude_code_documents_with_local_llm <- function"
  )

  for (pattern in forbidden_inline_defs) {
    expect_false(
      grepl(pattern, documents_txt, fixed = TRUE),
      info = sprintf(
        "Bu özet helper artık R/helpers_claude_code_document_summary.R içinde olmalıdır: %s",
        pattern
      )
    )
  }

  # Paylaşılan UTF-8 BOM yazıcı documents.R'de KALIR (run_lifecycle de kullanır).
  expect_true(
    grepl("write_claude_code_utf8_bom_text_file <- function", documents_txt, fixed = TRUE),
    info = "Paylaşılan UTF-8 BOM yazıcısı helpers_claude_code_documents.R içinde kalmalıdır."
  )
})

test_that("özet ve doküman dosyaları sıkı bakım bütçesinde kalır", {
  summary_txt <- .read_repo_text_ccdoc_summary(
    "R/helpers_claude_code_document_summary.R"
  )
  documents_txt <- .read_repo_text_ccdoc_summary(
    "R/helpers_claude_code_documents.R"
  )

  summary_lines <- length(strsplit(summary_txt, "\n", fixed = TRUE)[[1]])
  documents_lines <- length(strsplit(documents_txt, "\n", fixed = TRUE)[[1]])

  # Özetleme orkestrasyonu çıkarımı sonrası taban: summary 281/7, documents 407/10.
  expect_true(
    summary_lines < 320L,
    info = sprintf("R/helpers_claude_code_document_summary.R küçük kalmalı. Satır: %d", summary_lines)
  )
  expect_true(
    .count_fn_ccdoc_summary(summary_txt) <= 9L,
    info = sprintf("Özet dosyası fonksiyon bütçesini aştı: %d", .count_fn_ccdoc_summary(summary_txt))
  )

  expect_true(
    documents_lines < 430L,
    info = sprintf(
      "R/helpers_claude_code_documents.R özet çıkarımı sonrası küçülmeli. Satır: %d",
      documents_lines
    )
  )
  expect_true(
    .count_fn_ccdoc_summary(documents_txt) <= 12L,
    info = sprintf("documents.R fonksiyon bütçesini aştı: %d", .count_fn_ccdoc_summary(documents_txt))
  )
})
