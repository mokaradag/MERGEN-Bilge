# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-run-lifecycle-contract.R
# Açıklama: Bilge Yolaç çalışma yaşam döngüsü ve stale async callback koruması.
# ==============================================================================

.read_repo_text_cc_run_lifecycle_contract <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

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

  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.source_cc_run_lifecycle_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  source(file.path(repo_root, "R", "utils_common.R"), encoding = "UTF-8", local = env)
  source(
    file.path(repo_root, "R", "helpers_claude_code_run_lifecycle.R"),
    encoding = "UTF-8",
    local = env
  )

  env
}

test_that("Claude Code run lifecycle helper aktif ve stale request ayrımı yapar", {
  env <- .source_cc_run_lifecycle_for_test()

  rv <- new.env(parent = emptyenv())
  request_id <- env$cc_next_run_request_id()
  stale_id <- paste0(request_id, "_stale")

  expect_match(request_id, "^ccrun_")

  env$cc_mark_active_run(rv, request_id)

  expect_true(env$cc_is_active_run(rv, request_id))
  expect_false(env$cc_is_active_run(rv, stale_id))

  # Geriye dönük uyumluluk: eski finalize çağrıları request_id vermez.
  expect_true(env$cc_is_active_run(rv, NULL))
})

test_that("cc_finalize_if_active stale finalize çağrısını yoksayar", {
  env <- .source_cc_run_lifecycle_for_test()

  rv <- new.env(parent = emptyenv())
  calls <- 0L

  finalize_fn <- function(durum_metin,
                          durum_ikon,
                          durum_renk,
                          sure = NULL,
                          request_id = NULL) {
    calls <<- calls + 1L
    rv$last_finalize_request_id <- request_id
    invisible(TRUE)
  }

  env$cc_mark_active_run(rv, "newer-request")

  expect_false(env$cc_finalize_if_active(
    rv = rv,
    request_id = "older-request",
    finalize_streaming = finalize_fn,
    durum_metin = "Hata",
    durum_ikon = "exclamation-triangle",
    durum_renk = "#E57373",
    sure = NULL
  ))

  expect_equal(calls, 0L)

  expect_true(env$cc_finalize_if_active(
    rv = rv,
    request_id = "newer-request",
    finalize_streaming = finalize_fn,
    durum_metin = "Tamamlandı",
    durum_ikon = "check-circle",
    durum_renk = "#81C784",
    sure = 1
  ))

  expect_equal(calls, 1L)
  expect_identical(rv$last_finalize_request_id, "newer-request")
})

test_that("module_claude_code.R doküman özetleme akışını lifecycle helper'a delege eder", {
  txt <- .read_repo_text_cc_run_lifecycle_contract("R/module_claude_code.R")

  expect_true(
    grepl("cc_next_run_request_id\\(\\)", txt, perl = TRUE),
    info = "Bilge Yolaç komut çalıştırma akışı request id üretmelidir."
  )

  expect_true(
    grepl("cc_mark_active_run\\(rv, run_request_id\\)", txt, perl = TRUE),
    info = "Bilge Yolaç aktif request kimliğini rv içinde işaretlemelidir."
  )

  expect_true(
    grepl("cc_handle_document_summary_run\\(", txt, perl = TRUE),
    info = "Doküman özetleme promise callback'leri helper'a taşınmış olmalıdır."
  )

  expect_true(
    grepl("stream_env\\$request_id\\s*<-\\s*run_request_id", txt, perl = TRUE),
    info = "Streaming env aktif request kimliğini taşımalıdır."
  )
})

test_that("module_claude_code.R normal streaming finalization request id ile korunur", {
  txt <- .read_repo_text_cc_run_lifecycle_contract("R/module_claude_code.R")

  expect_true(
    grepl(
      'finalize_streaming\\(\\s*"Tamamlandı"\\s*,\\s*"check-circle"\\s*,\\s*"#81C784"\\s*,\\s*sure\\s*,\\s*request_id\\s*=\\s*env\\$request_id',
      txt,
      perl = TRUE
    ),
    info = "Normal başarılı streaming finalization stale poll callback'lere karşı env$request_id ile korunmalıdır."
  )

  expect_true(
    grepl(
      'finalize_streaming\\(\\s*"Hata"\\s*,\\s*"exclamation-triangle"\\s*,\\s*"#E57373"\\s*,\\s*sure\\s*,\\s*request_id\\s*=\\s*env\\$request_id',
      txt,
      perl = TRUE
    ),
    info = "Normal hata streaming finalization stale poll callback'lere karşı env$request_id ile korunmalıdır."
  )

  expect_false(
    grepl(
      'finalize_streaming\\(\\s*"Tamamlandı"\\s*,\\s*"check-circle"\\s*,\\s*"#81C784"\\s*,\\s*sure\\s*\\)',
      txt,
      perl = TRUE
    ),
    info = "Başarılı streaming finalization request_id parametresiz kalmamalıdır."
  )

  expect_false(
    grepl(
      'finalize_streaming\\(\\s*"Hata"\\s*,\\s*"exclamation-triangle"\\s*,\\s*"#E57373"\\s*,\\s*sure\\s*\\)',
      txt,
      perl = TRUE
    ),
    info = "Hata streaming finalization request_id parametresiz kalmamalıdır."
  )
})

test_that("Bilge Yolaç stop observer UI finalization'ı poll observer'a bırakmaz", {
  txt <- .read_repo_text_cc_run_lifecycle_contract("R/module_claude_code.R")

  m <- regexpr(
    "observeEvent\\(input\\$stop_command, \\{[\\s\\S]+?\\n    \\}\\)",
    txt,
    perl = TRUE
  )

  expect_true(
    m[1] > 0,
    info = "input$stop_command observer bloğu bulunmalıdır."
  )

  block <- regmatches(txt, m)[[1]]

  expect_true(
    grepl("finalize_streaming\\(", block, perl = TRUE),
    info = "Stop observer, poll observer'a güvenmeden finalize_streaming() çağırmalıdır."
  )

  expect_true(
    grepl("\"Durduruldu\"", block, fixed = TRUE),
    info = "Stop observer kullanıcıya Durduruldu durumunu göndermelidir."
  )

  expect_true(
    grepl("cc-stream-end", block, fixed = TRUE),
    info = "Stop observer istemcide açık stream mesajını kapatmalıdır."
  )

  expect_false(
    grepl("rv\\$active_process\\s*<-\\s*NULL", block, perl = TRUE),
    info = "Stop observer active_process'i elle NULL yapmamalı; state temizliği finalize_streaming() içinde kalmalıdır."
  )

  expect_true(
    grepl("request_id\\s*=\\s*request_id", block, perl = TRUE),
    info = "Stop observer stale finalize koruması için request_id ile finalize etmelidir."
  )
})