# ==============================================================================
# Dosya Yolu: R/helpers_file_manager_context_policy.R
# Açıklama: Dosya Yönetimi model-bağlam seçim temizleme politikaları.
# ==============================================================================

.fm_context_chr <- function(value, default = "") {
  if (is.null(value) || length(value) == 0L || is.na(value[1])) {
    return(default)
  }

  value_chr <- trimws(as.character(value[1]))
  if (!nzchar(value_chr)) {
    return(default)
  }

  value_chr
}

fm_plan_mcp_context_cleanup <- function(file_contents,
                                        files_in_context,
                                        excel_extensions = c("xls", "xlsx")) {
  if (is.null(file_contents) || !is.list(file_contents)) {
    file_contents <- list()
  }

  if (is.null(files_in_context) || !is.list(files_in_context)) {
    files_in_context <- list()
  }

  selected_ids <- names(files_in_context)
  selected_ids <- selected_ids[nzchar(selected_ids)]

  excel_extensions <- tolower(.fm_context_chr(excel_extensions, default = ""))
  excel_extensions <- unique(excel_extensions[nzchar(excel_extensions)])
  if (!length(excel_extensions)) {
    excel_extensions <- c("xls", "xlsx")
  }

  stale_ids <- character(0)
  non_excel_ids <- character(0)
  excel_ids <- character(0)
  detached_names <- character(0)

  for (fid in selected_ids) {
    entry <- file_contents[[fid]]

    if (is.null(entry) || is.null(entry$name)) {
      stale_ids <- c(stale_ids, fid)
      next
    }

    file_name <- .fm_context_chr(entry$name)
    if (!nzchar(file_name)) {
      stale_ids <- c(stale_ids, fid)
      next
    }

    file_ext <- tolower(tools::file_ext(file_name))
    if (!file_ext %in% excel_extensions) {
      non_excel_ids <- c(non_excel_ids, fid)
      detached_names <- c(detached_names, file_name)
      next
    }

    excel_ids <- c(excel_ids, fid)
  }

  excess_ids <- character(0)
  if (length(excel_ids) > 1L) {
    excess_ids <- excel_ids[-1]
    excel_ids <- excel_ids[1]

    for (fid in excess_ids) {
      entry <- file_contents[[fid]]
      file_name <- .fm_context_chr(entry$name)
      if (nzchar(file_name)) {
        detached_names <- c(detached_names, file_name)
      }
    }
  }

  remove_ids <- unique(c(stale_ids, non_excel_ids, excess_ids))

  list(
    keep_ids = unique(excel_ids),
    remove_ids = remove_ids,
    stale_ids = unique(stale_ids),
    non_excel_ids = unique(non_excel_ids),
    excess_ids = unique(excess_ids),
    detached_names = unique(detached_names[nzchar(detached_names)]),
    removed_any = length(remove_ids) > 0L,
    excess_removed = length(excess_ids) > 0L
  )
}