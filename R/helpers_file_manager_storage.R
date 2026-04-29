# ==============================================================================
# Dosya Yolu: R/helpers_file_manager_storage.R
# Açıklama: Dosya Yönetimi kalıcı yükleme klasörü ve indeks yardımcıları.
# ==============================================================================

fm_create_server_storage_helpers <- function(module_user_id_chr, fm_debug) {
  get_user_upload_dir <- function() {
    base <- getOption(
      "mergen.mcp_base_dir",
      Sys.getenv(
        "MCP_FILES_BASE",
        normalizePath(
          file.path(getwd(), "mergen_uploads"),
          winslash = "/",
          mustWork = FALSE
        )
      )
    )
    file.path(base, sprintf("user_%s", module_user_id_chr()))
  }

  is_under_mcp_base <- function(p) {
    if (is.null(p) || !nzchar(p)) return(FALSE)
    base <- getOption("mergen.mcp_base_dir", Sys.getenv("MCP_FILES_BASE", ""))
    if (!nzchar(base)) return(FALSE)
    np <- tryCatch(normalizePath(p, winslash = "/", mustWork = FALSE), error = function(e) p)
    nb <- tryCatch(normalizePath(base, winslash = "/", mustWork = FALSE), error = function(e) base)
    startsWith(tolower(np), tolower(paste0(nb, "/"))) || identical(tolower(np), tolower(nb))
  }

  list_user_folder_files <- function() {
    udir <- get_user_upload_dir()
    if (!dir.exists(udir)) return(character(0))
    list.files(udir, full.names = TRUE, recursive = FALSE, include.dirs = FALSE)
  }

  ensure_persisted_upload_index <- function(abs_path, display_name, uid) {
    if (is.null(abs_path) || !nzchar(abs_path) || !path_exists_relaxed(abs_path)) {
      return(invisible(FALSE))
    }

    if (is.null(uid) || !nzchar(uid) || identical(uid, "unknown") || identical(uid, "0")) {
      return(invisible(FALSE))
    }

    ok <- tryCatch({
      mergen_register_uploaded_file(
        src_path = abs_path,
        as_name = display_name,
        user_id = uid,
        persist_under_mcp_base = TRUE
      )
      TRUE
    }, error = function(e) {
      fm_debug("index_sync_error", sprintf("%s -> %s", display_name, conditionMessage(e)))
      FALSE
    })

    if (isTRUE(ok)) {
      fm_debug("index_sync", sprintf("%s -> %s", display_name, abs_path))
    }

    invisible(ok)
  }

  list(
    get_user_upload_dir = get_user_upload_dir,
    is_under_mcp_base = is_under_mcp_base,
    list_user_folder_files = list_user_folder_files,
    ensure_persisted_upload_index = ensure_persisted_upload_index
  )
}