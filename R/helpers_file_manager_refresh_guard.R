# ==============================================================================
# Dosya Yolu: R/helpers_file_manager_refresh_guard.R
# Açıklama: Dosya Yönetimi kalıcı dosya yenileme akışı için istek nesli koruması.
# ==============================================================================

fm_create_refresh_request_guard <- function(start_at = 0L) {
  request_seq <- suppressWarnings(as.integer(start_at[1]))
  if (is.na(request_seq) || request_seq < 0L) {
    request_seq <- 0L
  }

  list(
    next_id = function() {
      request_seq <<- as.integer(request_seq + 1L)
      request_seq
    },
    is_latest = function(request_id) {
      if (is.null(request_id) || length(request_id) == 0L || is.na(request_id[1])) {
        return(FALSE)
      }

      candidate <- suppressWarnings(as.integer(request_id[1]))
      if (is.na(candidate)) {
        return(FALSE)
      }

      identical(candidate, request_seq)
    },
    current = function() {
      request_seq
    }
  )
}