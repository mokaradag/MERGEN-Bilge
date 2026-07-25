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

  expect_true(grepl("fm_dispatch_bulk_upload_batch\\(", module_txt, perl = TRUE))
  expect_true(grepl("if \\(isTRUE\\(SSO_ENABLED\\) && !is_auth_ready\\(\\)\\)", helper_txt, perl = TRUE))
  expect_true(grepl("Kimlik doğrulama tamamlanmadan dosya yüklenemez", helper_txt, fixed = TRUE))
  expect_true(grepl("upload_skip", helper_txt, fixed = TRUE))
})

test_that("file manager toplu yükleme observer'ı senkron kopyalama/indeksleme yapmaz", {
  helper_txt <- .read_repo_text_file_manager_state_runtime("R/helpers_file_manager_upload_runtime.R")
  module_txt <- .read_repo_text_file_manager_state_runtime("R/module_file_manager.R")

  # Olay döngüsünü bloklayan senkron döngü/kopyalama/indeks yazımı geri gelmemeli.
  expect_false(grepl("withProgress", helper_txt, fixed = TRUE))
  expect_false(grepl("copy_to_mcp_base", helper_txt, fixed = TRUE))
  expect_false(grepl("ensure_persisted_upload_index", helper_txt, fixed = TRUE))

  # Gönderim sınırlı eşzamanlılıklı alım hattına devredilir.
  expect_true(grepl("file_ingestion_plan_batch\\(", helper_txt, perl = TRUE))
  expect_true(grepl("file_ingestion_submit_batch\\(", helper_txt, perl = TRUE))

  # Uçuştaki parti "Tümünü Temizle" sonrasında tabloyu geri getirmemeli.
  expect_true(grepl("file_ingestion_cancel_controller\\(", module_txt, perl = TRUE))
})
.load_file_manager_upload_runtime_helpers <- function() {
  repo_root <- resolve_repo_root_for_tests()
  helper_env <- new.env(parent = globalenv())

  source(file.path(repo_root, "R", "utils_common.R"), encoding = "UTF-8", local = helper_env)
  source(file.path(repo_root, "R", "helpers_file_ingestion_task.R"), encoding = "UTF-8", local = helper_env)
  source(file.path(repo_root, "R", "helpers_file_manager_upload_runtime.R"), encoding = "UTF-8", local = helper_env)

  helper_env$SSO_ENABLED <- FALSE
  helper_env$fm_upload_limit_mb <- function(...) 25L
  helper_env$fm_normal_allowed_extensions <- function() c("txt", "pdf")
  helper_env$showNotification <- function(...) invisible(NULL)
  helper_env$removeNotification <- function(...) invisible(NULL)

  helper_env
}

.uploadDispatchFixture <- function(env) {
  rec <- new.env(parent = emptyenv())
  rec$toasts <- list()
  rec$debug <- character()
  rec$submitted <- list()

  env$showToast <- function(session, message, type = "default") {
    rec$toasts[[length(rec$toasts) + 1L]] <- list(message = message, type = type)
    invisible(NULL)
  }
  env$file_ingestion_submit_batch <- function(controller, tasks, user_id, on_complete = NULL,
                                              on_failure = NULL, batch_id = NULL) {
    rec$submitted[[length(rec$submitted) + 1L]] <- list(
      tasks = tasks, user_id = user_id, on_complete = on_complete, batch_id = batch_id
    )
    list(status = "started", batch_id = batch_id, queued = 0L)
  }

  rec$fm_debug <- function(tag, message) {
    rec$debug <- c(rec$debug, paste(tag, message, sep = ":"))
    invisible(NULL)
  }

  rec
}

.uploadFilesDf <- function() {
  data.frame(
    name = c("mevcut.txt", "Türkçe.txt", "zararlı.exe"),
    datapath = c("/tmp/mevcut.txt", "/tmp/turkce.txt", "/tmp/zararli.exe"),
    size = c(1, 2, 3),
    type = c("text/plain", "text/plain", "application/octet-stream"),
    stringsAsFactors = FALSE
  )
}

test_that("toplu yükleme gönderimi yinelenen/desteklenmeyen dosyaları eler ve kalanı hatta verir", {
  env <- .load_file_manager_upload_runtime_helpers()
  rec <- .uploadDispatchFixture(env)

  outcome <- env$fm_dispatch_bulk_upload_batch(
    files_df = .uploadFilesDf(),
    existing_names = "mevcut.txt",
    session = list(),
    uid = "42",
    is_auth_ready = function() TRUE,
    controller = new.env(parent = emptyenv()),
    commit_ctx = list(),
    fm_debug = rec$fm_debug
  )

  expect_identical(outcome$status, "started")
  expect_equal(length(rec$submitted), 1L)

  # Yalnızca geçerli ve yinelenmeyen dosya worker'a gider.
  gorevler <- rec$submitted[[1]]$tasks
  expect_equal(length(gorevler), 1L)
  expect_identical(gorevler[[1]]$name, "Türkçe.txt")
  expect_identical(gorevler[[1]]$user_id, "42")

  mesajlar <- vapply(rec$toasts, function(x) x$message, character(1))
  expect_true(any(grepl("mevcut.txt", mesajlar, fixed = TRUE)))
  expect_true(any(grepl("zararlı.exe", mesajlar, fixed = TRUE)))
})

test_that("SSO hazır değilken toplu yükleme hatta gönderilmez", {
  env <- .load_file_manager_upload_runtime_helpers()
  env$SSO_ENABLED <- TRUE
  rec <- .uploadDispatchFixture(env)

  outcome <- env$fm_dispatch_bulk_upload_batch(
    files_df = .uploadFilesDf(),
    existing_names = character(),
    session = list(),
    uid = "42",
    is_auth_ready = function() FALSE,
    controller = new.env(parent = emptyenv()),
    commit_ctx = list(),
    fm_debug = rec$fm_debug
  )

  expect_identical(outcome$status, "auth_blocked")
  expect_equal(length(rec$submitted), 0L)
  expect_true(any(grepl("upload_skip", rec$debug, fixed = TRUE)))
})

test_that("geçersiz kullanıcı kimliğiyle toplu yükleme hatta gönderilmez", {
  env <- .load_file_manager_upload_runtime_helpers()
  rec <- .uploadDispatchFixture(env)

  outcome <- env$fm_dispatch_bulk_upload_batch(
    files_df = .uploadFilesDf(),
    existing_names = character(),
    session = list(),
    uid = "0",
    is_auth_ready = function() TRUE,
    controller = new.env(parent = emptyenv()),
    commit_ctx = list(),
    fm_debug = rec$fm_debug
  )

  expect_identical(outcome$status, "invalid_user")
  expect_equal(length(rec$submitted), 0L)
})

test_that("commit yalnızca başarılı sonuçlar için tablo satırı üretir", {
  env <- .load_file_manager_upload_runtime_helpers()
  rec <- .uploadDispatchFixture(env)

  islenen <- list()
  eklenen <- NULL
  sayac <- 0L

  ctx <- list(
    session = list(),
    fm_debug = rec$fm_debug,
    process_uploaded_file = function(file_info, generate_message = FALSE) {
      islenen[[length(islenen) + 1L]] <<- list(info = file_info, generate_message = generate_message)
      list(id = paste0("id_", length(islenen)), name = file_info$name)
    },
    message_data = function(x) invisible(NULL),
    message_trigger = function(x) {
      if (missing(x)) return(sayac)
      sayac <<- x
      invisible(NULL)
    },
    files_added_to_context = function(x) {
      eklenen <<- x
      invisible(NULL)
    }
  )

  sonuclar <- list(
    list(ok = TRUE, name = "Türkçe.txt", dest = "/kalici/user_42/Türkçe.txt", size = 120, type = "text/plain"),
    list(ok = FALSE, name = "bozuk.txt", code = "copy_failed", error = "disk dolu")
  )

  saved <- env$fm_commit_bulk_upload_results(sonuclar, ctx, batch_id = "b1")

  expect_equal(length(saved), 1L)
  expect_identical(islenen[[1]]$info$datapath, "/kalici/user_42/Türkçe.txt")
  expect_false(isTRUE(islenen[[1]]$generate_message))
  expect_equal(length(eklenen), 1L)

  hata_mesajlari <- vapply(rec$toasts, function(x) x$message, character(1))
  expect_true(any(grepl("bozuk.txt", hata_mesajlari, fixed = TRUE)))
})
