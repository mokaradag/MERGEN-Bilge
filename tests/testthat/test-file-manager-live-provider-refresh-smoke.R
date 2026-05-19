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

.fm_live_process_restored_file <- function(values) {
  force(values)

  function(finfo) {
    file_id <- paste0("restored_", length(values$file_contents) + 1L)

    row <- fm_build_file_table_row(
      file_id = file_id,
      file_name = finfo$name,
      file_path = finfo$datapath,
      file_size = finfo$size %||% 0,
      file_type = finfo$type %||% "application/octet-stream",
      in_context = FALSE,
      attached = FALSE,
      ns = function(id) id
    )

    values$files <- rbind(values$files, row)
    values$file_contents[[file_id]] <- list(
      id = file_id,
      name = enc2utf8(finfo$name),
      datapath = finfo$datapath,
      persisted_path = finfo$datapath
    )

    values$file_contents[[file_id]]
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
    module_values = values,
    module_user_id_chr = function() current_uid,
    is_auth_ready = function() auth_ready,
    fm_debug = function(...) invisible(NULL),
    set_parent_files_context = function(x) {
      session$userData$parent_files_context <- x
      invisible(NULL)
    },
    process_uploaded_file_callback = .fm_live_process_restored_file(values),
    refresh_guard = refresh_guard
  )

  refresh_from_user_folder("initial-before-auth")

  expect_identical(listed_user_ids, character(0))
  expect_equal(nrow(values$files), 0L)

  auth_ready <- TRUE
  current_uid <- "4242"

  refresh_from_user_folder("auth-ready")

  expect_identical(listed_user_ids, "4242")
  expect_equal(nrow(values$files), 1L)
  expect_identical(enc2utf8(values$files$Dosya_Adi[[1]]), original_name)
  expect_false(grepl("^\\d{8}[-_]\\d{6}", values$files$Dosya_Adi[[1]]))
  expect_true(original_name %in% names(session$userData$parent_files_context))
})