# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-document-extractors-maintainability-contract.R
# Açıklama: helpers_claude_code_documents.R dosyasının extractor refactor sonrası
#           800 satır ve 25 fonksiyon eşiklerinin altına düştüğünü doğrular.
# ==============================================================================

.read_repo_text_claude_doc_metric <- function(rel_path) {
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

.count_functions_claude_doc_metric <- function(txt) {
  hits <- gregexpr(
    "(<-|=)\\s*function\\s*\\(",
    txt,
    perl = TRUE
  )[[1]]

  if (identical(hits[1], -1L)) {
    return(0L)
  }

  length(hits)
}

.file_metrics_claude_doc <- function(rel_path) {
  txt <- .read_repo_text_claude_doc_metric(rel_path)
  lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]

  data.frame(
    path = rel_path,
    lines = length(lines),
    functions = .count_functions_claude_doc_metric(txt),
    stringsAsFactors = FALSE
  )
}

test_that("helpers_claude_code_documents.R crosses below maintainability thresholds", {
  metrics <- .file_metrics_claude_doc("R/helpers_claude_code_documents.R")

  expect_true(
    metrics$lines < 800L,
    info = paste(
      "R/helpers_claude_code_documents.R 800+ satır eşiğinin altına düşmeli.",
      "Bu, maintainability_score için gerçek +3 puan etkisi yaratır.",
      sprintf("Mevcut satır: %d", metrics$lines)
    )
  )

  expect_true(
    metrics$functions < 25L,
    info = paste(
      "R/helpers_claude_code_documents.R 25+ fonksiyon eşiğinin altına düşmeli.",
      "Bu, maintainability_score için gerçek +2 puan etkisi yaratır.",
      sprintf("Mevcut fonksiyon ifadesi: %d", metrics$functions)
    )
  )
})

test_that("helpers_claude_code_document_extractors.R remains bounded and side-effect-light", {
  metrics <- .file_metrics_claude_doc("R/helpers_claude_code_document_extractors.R")
  txt <- .read_repo_text_claude_doc_metric("R/helpers_claude_code_document_extractors.R")

  expect_true(
    metrics$lines < 450L,
    info = sprintf(
      "R/helpers_claude_code_document_extractors.R küçük kalmalıdır. Mevcut satır: %d",
      metrics$lines
    )
  )

  expect_true(
    metrics$functions <= 18L,
    info = sprintf(
      paste(
        "R/helpers_claude_code_document_extractors.R bounded kalmalıdır.",
        "Bu metrik tryCatch/lapply/vapply içindeki anonim function ifadelerini de sayar.",
        "Beklenen üst sınır 18'dir. Mevcut fonksiyon ifadesi: %d"
      ),
      metrics$functions
    )
  )

  expect_false(
    grepl("observeEvent\\s*\\(|renderUI\\s*\\(|shiny::runApp", txt, perl = TRUE),
    info = "Extractor helper dosyası Shiny observer/render/runtime davranışı içermemelidir."
  )

  expect_false(
    grepl("call_claude|processx::|system2\\s*\\(", txt, perl = TRUE),
    info = "Extractor helper dosyası Claude CLI/process yönetimi başlatmamalıdır."
  )

  expect_false(
    grepl("sendCustomMessage|session\\$send", txt, perl = TRUE),
    info = "Extractor helper dosyası frontend/session mesajı göndermemelidir."
  )
})