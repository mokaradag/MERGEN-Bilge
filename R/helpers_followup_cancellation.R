# Takip işinin iptal jetonu; ağ aktarımı ortak LLM kapısını kullanır.
mergen_followup_cancellation <- function(session, current, later_fn = later::later) {
  path <- tempfile("followup_stop_", fileext = ".flag")
  finished <- FALSE
  cancelled <- FALSE
  remove_owner <- remove_end <- function() NULL
  # İptal yalnız durdurma işareti diskte oluşunca tamamlanmış sayılır; yazım
  # başarısızsa yoklama sürer ve yeniden dener.
  cancel <- function(...) {
    if (finished || cancelled) return(invisible(NULL))
    if (!isTRUE(file.exists(path)) && !isTRUE(tryCatch(file.create(path), error = function(e) FALSE)))
      return(invisible(NULL))
    cancelled <<- TRUE
    remove_owner()
    remove_end()
    invisible(NULL)
  }
  poll <- function() {
    if (finished || cancelled) return(invisible(NULL))
    if (!isTRUE(tryCatch(current(), error = function(e) FALSE))) {
      cancel()
      if (cancelled) return(invisible(NULL))
    }
    later_fn(poll, delay = 0.1)
    invisible(NULL)
  }
  remove_owner <- mergen_session_on_owner_change(session, cancel)
  if (is.function(session$onSessionEnded)) remove_end <- session$onSessionEnded(cancel)
  later_fn(poll, delay = 0.1)
  list(path = path, cancel = cancel, finish = function() {
    finished <<- TRUE
    remove_owner()
    remove_end()
    unlink(path, force = TRUE)
    invisible(NULL)
  })
}
