# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-manager-state-runtime-contract.R
# Açıklama: Dosya Yönetimi state/refresh runtime extraction sözleşmesini doğrular.
# ==============================================================================

.read_repo_text_file_manager_state_runtime <- function(path) {
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

  txt <- gsub("\\r\\n?|\\r", "\\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.load_file_manager_state_runtime_helpers <- function() {
  repo_root <- resolve_repo_root_for_tests()
  helper_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root, "R", "helpers_file_manager_state_runtime.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  helper_env
}

test_that("file manager state runtime helper factoryleri source edilebilir", {
  env <- .load_file_manager_state_runtime_helpers()

  expect_true(exists("fm_create_file_action_helpers", envir = env, mode = "function", inherits = FALSE))
  expect_true(exists("fm_create_refresh_from_user_folder", envir = env, mode = "function", inherits = FALSE))
})

test_that("file manager refresh ve state mutasyonları modülden helper dosyasına taşınır", {
  module_txt <- .read_repo_text_file_manager_state_runtime("R/module_file_manager.R")
  helper_txt <- .read_repo_text_file_manager_state_runtime("R/helpers_file_manager_state_runtime.R")

  expect_true(grepl("fm_create_file_action_helpers\\(", module_txt, perl = TRUE))
  expect_true(grepl("fm_create_refresh_from_user_folder\\(", module_txt, perl = TRUE))

  expect_true(grepl("fm_create_file_action_helpers <- function", helper_txt, fixed = TRUE))
  expect_true(grepl("fm_create_refresh_from_user_folder <- function", helper_txt, fixed = TRUE))
  expect_true(grepl("sync_file_to_context <- function", helper_txt, fixed = TRUE))
  expect_true(grepl("remove_file_by_name <- function", helper_txt, fixed = TRUE))
  expect_true(grepl("process_uploaded_file <- function", helper_txt, fixed = TRUE))

  expect_false(grepl("sync_file_to_context <- function", module_txt, fixed = TRUE))
  expect_false(grepl("remove_file_by_name <- function", module_txt, fixed = TRUE))
  expect_false(grepl("process_uploaded_file <- function", module_txt, fixed = TRUE))
  expect_false(grepl("refresh_from_user_folder <- function", module_txt, fixed = TRUE))
})

test_that("file manager refresh helper stale request guard sözleşmesini korur", {
  helper_txt <- .read_repo_text_file_manager_state_runtime("R/helpers_file_manager_state_runtime.R")

  expect_true(grepl("request_id <- refresh_guard\\$next_id\\(\\)", helper_txt, perl = TRUE))
  expect_true(grepl("!refresh_guard\\$is_latest\\(request_id\\)", helper_txt, perl = TRUE))
  expect_true(grepl("refresh_error_stale", helper_txt, fixed = TRUE))
  expect_true(grepl("session\\$userData\\$current_session_files <- previous_state\\$session_registry", helper_txt, perl = TRUE))
})

test_that("file manager upload observer SSO hazır olmadan kalıcı dosya state'i mutasyona uğratmaz", {
  helper_txt <- .read_repo_text_file_manager_state_runtime("R/helpers_file_manager_upload_runtime.R")
  module_txt <- .read_repo_text_file_manager_state_runtime("R/module_file_manager.R")

  expect_true(grepl("fm_process_bulk_upload_batch\\(", module_txt, perl = TRUE))
  expect_true(grepl("if \\(isTRUE\\(SSO_ENABLED\\) && !is_auth_ready\\(\\)\\)", helper_txt, perl = TRUE))
  expect_true(grepl("Kimlik doğrulama tamamlanmadan dosya yüklenemez", helper_txt, fixed = TRUE))
  expect_true(grepl("upload_skip", helper_txt, fixed = TRUE))
})
.load_file_manager_upload_runtime_helpers <- function() {
  repo_root <- resolve_repo_root_for_tests()
  helper_env <- new.env(parent = globalenv())

  source(file.path(repo_root, "R", "utils_common.R"), encoding = "UTF-8", local = helper_env)
  source(file.path(repo_root, "R", "helpers_file_manager_upload_runtime.R"), encoding = "UTF-8", local = helper_env)

  helper_env
}

test_that("file manager toplu yükleme runtime doğrulama ve kopya davranışını korur", {
  env <- .load_file_manager_upload_runtime_helpers()
  env$SSO_ENABLED <- FALSE
  env$withProgress <- function(message, value, expr) force(expr)
  env$incProgress <- function(...) invisible(NULL)
  env$path_exists_relaxed <- function(path) TRUE
  env$fm_upload_limit_mb <- function(...) 25L

  toast_log <- list()
  debug_log <- character()
  index_log <- list()
  processed <- list()

  env$showToast <- function(session, message, type = "default") {
    toast_log[[length(toast_log) + 1L]] <<- list(message = message, type = type)
    invisible(NULL)
  }
  old_validate <- if (exists("validate_uploaded_file", envir = globalenv(), inherits = FALSE)) {
    get("validate_uploaded_file", envir = globalenv(), inherits = FALSE)
  } else {
    NULL
  }
  assign("validate_uploaded_file", function(path, filename, max_size_mb, allowed_ext) {
    list(ok = !grepl("\\.exe$", filename), code = "bad_ext", error = "uzantı yasak")
  }, envir = globalenv())
  withr::defer({
    if (is.null(old_validate)) {
      rm("validate_uploaded_file", envir = globalenv())
    } else {
      assign("validate_uploaded_file", old_validate, envir = globalenv())
    }
  })
  env$fm_normal_allowed_extensions <- function() c("txt", "pdf")
  env$copy_to_mcp_base <- function(file_info, uid) paste0(file_info$datapath, "_persisted")

  files_df <- data.frame(
    name = c("mevcut.txt", "Türkçe.txt", "zararlı.exe"),
    datapath = c("/tmp/mevcut.txt", "/tmp/turkce.txt", "/tmp/zararli.exe"),
    size = c(1, 2, 3),
    type = c("text/plain", "text/plain", "application/octet-stream"),
    stringsAsFactors = FALSE
  )

  result <- env$fm_process_bulk_upload_batch(
    files_df = files_df,
    existing_names = "mevcut.txt",
    session = list(),
    uid = "42",
    is_auth_ready = function() TRUE,
    is_under_mcp_base = function(path) FALSE,
    ensure_persisted_upload_index = function(abs_path, display_name, uid) {
      index_log[[length(index_log) + 1L]] <<- list(path = abs_path, name = display_name, uid = uid)
    },
    process_uploaded_file = function(file_info, generate_message = FALSE) {
      processed[[length(processed) + 1L]] <<- list(file_info = file_info, generate_message = generate_message)
      list(id = paste0("id_", length(processed)), name = as.character(file_info$name[1]))
    },
    fm_debug = function(tag, message) debug_log <<- c(debug_log, paste(tag, message, sep = ":"))
  )

  expect_equal(result$duplicate_names, "mevcut.txt")
  expect_equal(length(result$saved_infos), 1L)
  expect_equal(result$saved_infos[[1]]$name, "Türkçe.txt")
  expect_equal(processed[[1]]$file_info$datapath[1], "/tmp/turkce.txt_persisted")
  expect_false(isTRUE(processed[[1]]$generate_message))
  expect_equal(index_log[[1]]$name, "Türkçe.txt")
  expect_true(any(vapply(toast_log, function(x) grepl("zararlı.exe", x$message, fixed = TRUE), logical(1))))
  expect_true(any(grepl("upload_validation_reject", debug_log, fixed = TRUE)))
})
