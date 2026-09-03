# R/module_chat_history_background.R
# Açıklama: Söyleşi geçmişini görünür ilk bölümden sonra küçük partilerle ısıtır.

historyBackgroundWarm <- function(session, chat_ids, chats, ensure_history_cache,
                                  batch_size = 120L, delay_sec = 0.35,
                                  on_complete = NULL) {
  if (!length(chat_ids)) return(invisible(NULL))

  batches <- split(chat_ids, ceiling(seq_along(chat_ids) / batch_size))
  remaining <- length(batches)

  for (i in seq_along(batches)) {
    local({
      batch <- batches[[i]]
      wait <- i * delay_sec

      later::later(function() {
        if (!session$isClosed()) {
          shiny::withReactiveDomain(session, {
            shiny::isolate({
              ensure_history_cache(batch, chats)
              remaining <<- remaining - 1L

              if (remaining <= 0L && is.function(on_complete)) {
                on_complete()
              }
            })
          })
        }
      }, delay = wait)
    })
  }

  invisible(TRUE)
}