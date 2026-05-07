# ==============================================================================
# Dosya Yolu: tests/testthat/test-e2e-file-context-regression.R
# Açıklama: Dosya Yönetimi, model bağlamı, özetleme/MCP kuralları ve refresh
#           yarış durumları için deterministik E2E benzeri regresyon testleri.
# ==============================================================================

.find_file_context_e2e_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("File context E2E test repo kökünü bulamadı. Testi repo kökünden çalıştırın.", call. = FALSE)
}

repo_root_file_context_e2e <- .find_file_context_e2e_repo_root()

if (!exists("resolve_repo_root_for_tests", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(repo_root_file_context_e2e, "tests", "testthat", "helper_bootstrap.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

repo_root_file_context_e2e <- resolve_repo_root_for_tests()

if (!exists("e2e_file_context_new_state", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(
      repo_root_file_context_e2e,
      "tests",
      "testthat",
      "helper_e2e_file_context_harness.R"
    ),
    encoding = "UTF-8",
    local = globalenv()
  )
}

.e2e_file_context_read_text <- function(...) {
  path <- file.path(repo_root_file_context_e2e, ...)
  if (!file.exists(path)) {
    stop(sprintf("Beklenen dosya bulunamadı: %s", path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(path, open = "rb")
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

test_that("supported upload appears in file manager state and attach updates parent context", {
  state <- e2e_file_context_new_state()

  state <- e2e_file_context_upload(
    state,
    e2e_file_context_make_file_info("müşteri_İğdır.docx")
  )

  expect_equal(nrow(state$table), 1L)
  expect_identical(state$table$Dosya_Adi[1], "müşteri_İğdır.docx")
  expect_length(state$file_contents, 1L)
  expect_length(state$messages, 1L)
  expect_identical(state$messages[[1]]$type, "system")

  file_id <- state$last_upload$id

  state <- e2e_file_context_attach(
    state = state,
    file_id = file_id,
    checked = TRUE
  )

  expect_true(isTRUE(state$files_in_context[[file_id]]))
  expect_true("müşteri_İğdır.docx" %in% names(state$parent_context))
  expect_identical(state$parent_context[["müşteri_İğdır.docx"]]$id, file_id)
  expect_null(state$last_error)
})

test_that("summarization mode rejects unsupported uploads but keeps supported context files", {
  state <- e2e_file_context_new_state()

  state <- e2e_file_context_upload(
    state,
    e2e_file_context_make_file_info("bütçe.xlsx"),
    generate_message = TRUE,
    summarization_mode = TRUE
  )

  expect_identical(state$last_error, "unsupported_extension")
  expect_length(state$file_contents, 0L)
  expect_true(any(grepl("unsupported_extension:bütçe.xlsx", state$toasts, fixed = TRUE)))

  state <- e2e_file_context_upload(
    state,
    e2e_file_context_make_file_info("aydınlanma_özeti.pdf"),
    generate_message = TRUE,
    summarization_mode = TRUE
  )

  file_id <- state$last_upload$id

  state <- e2e_file_context_attach(
    state = state,
    file_id = file_id,
    checked = TRUE,
    summarization_mode = TRUE
  )

  expect_null(state$last_error)
  expect_true("aydınlanma_özeti.pdf" %in% names(state$parent_context))
  expect_setequal(
    fm_summarization_allowed_extensions(),
    c("doc", "docx", "pdf", "txt")
  )
})

test_that("MCP mode removes non-Excel and excess selected files, then enforces one Excel", {
  state <- e2e_file_context_new_state()

  state <- e2e_file_context_upload(
    state,
    e2e_file_context_make_file_info("notlar.pdf"),
    generate_message = FALSE
  )
  pdf_id <- state$last_upload$id

  state <- e2e_file_context_upload(
    state,
    e2e_file_context_make_file_info("veri.xlsx"),
    generate_message = FALSE
  )
  xlsx_id <- state$last_upload$id

  state <- e2e_file_context_upload(
    state,
    e2e_file_context_make_file_info("plan.xls"),
    generate_message = FALSE
  )
  xls_id <- state$last_upload$id

  state <- e2e_file_context_attach(state, pdf_id, checked = TRUE)
  state <- e2e_file_context_attach(state, xlsx_id, checked = TRUE)
  state <- e2e_file_context_attach(state, xls_id, checked = TRUE)

  expect_setequal(
    names(state$parent_context),
    c("notlar.pdf", "veri.xlsx", "plan.xls")
  )

  state <- e2e_file_context_enable_mcp(state)

  expect_identical(state$last_cleanup_plan$keep_ids, xlsx_id)
  expect_setequal(state$last_cleanup_plan$remove_ids, c(pdf_id, xls_id))
  expect_setequal(state$ui_unchecked_ids, c(pdf_id, xls_id))
  expect_identical(names(state$parent_context), "veri.xlsx")

  state <- e2e_file_context_attach(
    state = state,
    file_id = pdf_id,
    checked = TRUE,
    mcp_enabled = TRUE
  )

  expect_identical(state$last_error, "mcp_non_excel")
  expect_false("notlar.pdf" %in% names(state$parent_context))

  state <- e2e_file_context_attach(
    state = state,
    file_id = xls_id,
    checked = TRUE,
    mcp_enabled = TRUE
  )

  expect_null(state$last_error)
  expect_identical(names(state$parent_context), "plan.xls")
  expect_identical(names(state$files_in_context), xls_id)
})

test_that("invalid or auth-not-ready refresh does not wipe existing file context", {
  state <- e2e_file_context_new_state()

  state <- e2e_file_context_upload(
    state,
    e2e_file_context_make_file_info("mevcut.txt"),
    generate_message = FALSE
  )

  file_id <- state$last_upload$id
  state <- e2e_file_context_attach(state, file_id, checked = TRUE)

  state <- e2e_file_context_refresh_start(
    state,
    user_id = "0",
    trigger = "initial"
  )

  expect_null(state$last_refresh_id)
  expect_identical(state$refresh_guard$current(), 0L)
  expect_equal(nrow(state$table), 1L)
  expect_true("mevcut.txt" %in% names(state$parent_context))
  expect_true(any(grepl("refresh_skip:invalid_user:initial", state$events, fixed = TRUE)))

  state <- e2e_file_context_refresh_start(
    state,
    user_id = "42",
    trigger = "sso-early",
    sso_enabled = TRUE,
    auth_ready = FALSE
  )

  expect_null(state$last_refresh_id)
  expect_identical(state$refresh_guard$current(), 0L)
  expect_equal(nrow(state$table), 1L)
  expect_true("mevcut.txt" %in% names(state$parent_context))
  expect_true(any(grepl("refresh_skip:auth_not_ready:sso-early", state$events, fixed = TRUE)))
})

test_that("newer refresh wins and stale refresh cannot overwrite file table or context", {
  state <- e2e_file_context_new_state()

  state <- e2e_file_context_upload(
    state,
    e2e_file_context_make_file_info("seçili.pdf"),
    generate_message = FALSE
  )

  old_file_id <- state$last_upload$id
  state <- e2e_file_context_attach(state, old_file_id, checked = TRUE)

  state <- e2e_file_context_refresh_start(
    state,
    user_id = "42",
    trigger = "manual-a"
  )
  old_request_id <- state$last_refresh_id

  state <- e2e_file_context_refresh_start(
    state,
    user_id = "42",
    trigger = "manual-b"
  )
  new_request_id <- state$last_refresh_id

  newer_rows <- data.frame(
    name = c("seçili.pdf", "yeni_rapor.txt"),
    path = c(
      tempfile("secili_", fileext = ".pdf"),
      tempfile("yeni_rapor_", fileext = ".txt")
    ),
    size = c(10, 20),
    type = c("application/pdf", "text/plain"),
    stringsAsFactors = FALSE
  )

  state <- e2e_file_context_refresh_apply(
    state,
    request_id = new_request_id,
    rows = newer_rows
  )

  expect_setequal(
    state$table$Dosya_Adi,
    c("seçili.pdf", "yeni_rapor.txt")
  )
  expect_true("seçili.pdf" %in% names(state$parent_context))
  expect_true(any(grepl(sprintf("refresh_apply:%s:2", new_request_id), state$events, fixed = TRUE)))

  stale_rows <- data.frame(
    name = "eski_sonuç.txt",
    path = tempfile("eski_sonuc_", fileext = ".txt"),
    size = 30,
    type = "text/plain",
    stringsAsFactors = FALSE
  )

  state <- e2e_file_context_refresh_apply(
    state,
    request_id = old_request_id,
    rows = stale_rows
  )

  expect_false("eski_sonuç.txt" %in% state$table$Dosya_Adi)
  expect_setequal(
    state$table$Dosya_Adi,
    c("seçili.pdf", "yeni_rapor.txt")
  )
  expect_true(any(grepl(sprintf("refresh_skip:stale:%s", old_request_id), state$events, fixed = TRUE)))
})

test_that("browser restore ignores stale attachment ids and keeps valid model context", {
  state <- e2e_file_context_new_state()

  state <- e2e_file_context_upload(
    state,
    e2e_file_context_make_file_info("durum_özet.pdf"),
    generate_message = FALSE
  )

  valid_id <- state$last_upload$id

  state <- e2e_file_context_restore_client_state(
    state,
    attached_ids = c(valid_id, "ghost_id")
  )

  expect_identical(state$last_restore_stale_ids, "ghost_id")
  expect_identical(names(state$files_in_context), valid_id)
  expect_identical(names(state$parent_context), "durum_özet.pdf")
  expect_true(any(grepl("client_restore:valid=1:stale=1", state$events, fixed = TRUE)))
})

test_that("file manager browser/server hooks for upload and attach events remain wired", {
  module_txt <- .e2e_file_context_read_text("R", "module_file_manager.R")
  file_js <- .e2e_file_context_read_text("www", "js", "file_handlers.js")

  expect_true(grepl("attach_toggled", module_txt, fixed = TRUE))
  expect_true(grepl("setAttachState", module_txt, fixed = TRUE))
  expect_true(grepl("files_in_context", module_txt, fixed = TRUE))

  expect_true(grepl("file_manager_module-execute_bulk_upload", file_js, fixed = TRUE))
  expect_true(grepl("file_manager_module-file_action", file_js, fixed = TRUE))
  expect_true(grepl("Shiny.setInputValue", file_js, fixed = TRUE))
})