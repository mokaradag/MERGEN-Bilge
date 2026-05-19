# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-manager-live-provider-refresh-smoke.R
# Açıklama: Dosya Yöneticisi canlı kullanıcı kimliği, SSO placeholder ve
#           kalıcı dosya görünen ad yenileme davranışını gerçek helper seam'leri
#           üzerinden doğrular. Uygulamayı, DB'yi veya tarayıcıyı başlatmaz.
# ==============================================================================

.find_fm_live_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", "..")),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("File Manager live-provider smoke repo kökünü bulamadı.", call. = FALSE)
}

repo_root_fm_live <- .find_fm_live_repo_root()

if (!exists("resolve_repo_root_for_tests", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(repo_root_fm_live, "tests", "testthat", "helper_bootstrap.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

repo_root_fm_live <- resolve_repo_root_for_tests()

.fm_live_source_once <- function(path, required_function = NULL) {
  if (!is.null(required_function) &&
      exists(required_function, envir = globalenv(), inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(repo_root_fm_live, path),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

.fm_live_source_once("R/utils_common.R", "%||%")
.fm_live_source_once("R/helpers_file_manager_policy.R", "fm_file_ext_icon_html")
.fm_live_source_once("R/helpers_file_manager_table.R", "fm_empty_files_df")
.fm_live_source_once("R/helpers_file_manager_refresh_guard.R", "fm_create_refresh_request_guard")
.fm_live_source_once("R/helpers_file_manager_storage.R", "fm_create_server_storage_helpers")
.fm_live_source_once("R/helpers_file_manager_state_runtime.R", "fm_create_refresh_from_user_folder")

.fm_live_fake_session <- function(session_user_id = 0L) {
  session <- new.env(parent = emptyenv())
  session$userData <- new.env(parent = emptyenv())
  session$userData$user_id <- session_user_id
  session$ns <- function(id) id
  session
}

.fm_live_fake_values <- function() {
  values <- new.env(parent = emptyenv())
  values$files <- fm_empty_files_df()
  values$file_contents <- list()
  values$files_in_context <- list()
  values
}

.fm_live_process_restored_file <- function(values, session = NULL) {
  force(values)
  force(session)

  function(finfo) {
    file_id <- paste0("restored_", length(values$file_contents) + 1L)

    file_info <- list(
      name = enc2utf8(finfo$name),
      datapath = finfo$datapath,
      size = finfo$size %||% 0,
      type = finfo$type %||% "application/octet-stream"
    )

    row <- fm_build_file_table_row(
      file_name = file_info$name,
      file_size = file_info$size,
      file_info = file_info,
      file_id = file_id,
      ns = function(id) id
    )

    values$files <- rbind(values$files, row)

    restored <- list(
      id = file_id,
      name = file_info$name,
      datapath = file_info$datapath,
      persisted_path = file_info$datapath,
      size = file_info$size,
      type = file_info$type
    )

    values$file_contents[[file_id]] <- restored

    if (!is.null(session) && !is.null(session$userData)) {
      session$userData$current_session_files <- session$userData$current_session_files %||% list()
      session$userData$current_session_files[[restored$name]] <- restored
    }

    restored
  }
}

test_that("File Manager storage helpers read live current_user_id provider", {
  current_uid <- "101"

  storage <- fm_create_server_storage_helpers(
    module_user_id_chr = function() current_uid,
    fm_debug = function(...) invisible(NULL)
  )

  first_dir <- storage$get_user_upload_dir()
  expect_true(grepl("user_101", first_dir, fixed = TRUE))

  current_uid <- "202"

  second_dir <- storage$get_user_upload_dir()
  expect_true(grepl("user_202", second_dir, fixed = TRUE))
  expect_false(identical(first_dir, second_dir))
})

test_that("File Manager refresh skips SSO placeholder and restores Turkish display name with live user id", {
  session <- .fm_live_fake_session(session_user_id = 0L)
  values <- .fm_live_fake_values()
  session$userData$current_session_files <- list()

  current_uid <- "0"
  auth_ready <- FALSE
  listed_user_ids <- character()

  original_name <- enc2utf8("Türkçe_çalışma_özeti_İstanbul.pdf")
  probe_file <- tempfile("fm_live_turkish_", fileext = ".pdf")
  writeBin(charToRaw(enc2utf8("PDF smoke içeriği: ğüşİÖÇ")), probe_file)
  on.exit(unlink(probe_file, force = TRUE), add = TRUE)

  refresh_guard <- fm_create_refresh_request_guard()

	old_sso_exists <- exists("SSO_ENABLED", envir = globalenv(), inherits = FALSE)
	old_sso_value <- if (old_sso_exists) get("SSO_ENABLED", envir = globalenv()) else NULL

	old_list_exists <- exists("mergen_list_user_files", envir = globalenv(), inherits = FALSE)
	old_list_value <- if (old_list_exists) get("mergen_list_user_files", envir = globalenv()) else NULL

	on.exit({
	  if (old_sso_exists) {
		assign("SSO_ENABLED", old_sso_value, envir = globalenv())
	  } else if (exists("SSO_ENABLED", envir = globalenv(), inherits = FALSE)) {
		rm("SSO_ENABLED", envir = globalenv())
	  }

	  if (old_list_exists) {
		assign("mergen_list_user_files", old_list_value, envir = globalenv())
	  } else if (exists("mergen_list_user_files", envir = globalenv(), inherits = FALSE)) {
		rm("mergen_list_user_files", envir = globalenv())
	  }
	}, add = TRUE)

	assign("SSO_ENABLED", TRUE, envir = globalenv())

	assign(
	  "mergen_list_user_files",
	  function(user_id, prune_missing = TRUE) {
		listed_user_ids <<- c(listed_user_ids, as.character(user_id))

		data.frame(
		  name = original_name,
		  path = probe_file,
		  size = file.info(probe_file)$size,
		  type = "application/pdf",
		  stringsAsFactors = FALSE
		)
	  },
	  envir = globalenv()
	)

	refresh_from_user_folder <- fm_create_refresh_from_user_folder(
	  session = session,
	  ns = function(id) id,
	  module_values_provider = function() values,
	  module_user_id_chr = function() current_uid,
	  is_auth_ready = function() auth_ready,
	  ensure_session_registry = function() {
		session$userData$current_session_files <- session$userData$current_session_files %||% list()
		invisible(TRUE)
	  },
	  attach_in_parent = function(file_obj) {
		session$userData$parent_files_context <- session$userData$parent_files_context %||% list()
		session$userData$parent_files_context[[file_obj$name]] <- file_obj
		invisible(TRUE)
	  },
	  process_uploaded_file_callback = .fm_live_process_restored_file(values, session),
	  refresh_guard = refresh_guard,
	  fm_debug = function(...) invisible(NULL)
	)

  refresh_from_user_folder("initial-before-auth")

  expect_identical(listed_user_ids, character(0))
  expect_equal(nrow(values$files), 0L)

  auth_ready <- TRUE
  current_uid <- "4242"

  refresh_from_user_folder("auth-ready")

  expect_identical(listed_user_ids, "4242")
  expect_equal(nrow(values$files), 1L)

  if (nrow(values$files) > 0L) {
    expect_identical(enc2utf8(values$files$Dosya_Adi[[1]]), original_name)
  }
  expect_false(grepl("^\\d{8}[-_]\\d{6}", values$files$Dosya_Adi[[1]]))
  expect_true(original_name %in% names(session$userData$current_session_files))
  expect_identical(
    enc2utf8(session$userData$current_session_files[[original_name]]$name),
    original_name
  )
})