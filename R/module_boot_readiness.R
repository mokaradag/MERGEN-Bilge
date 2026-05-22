# R/module_boot_readiness.R
# Açıklama: Açılış ekranının yalnızca gerçek hazır olma kontrol noktalarından
# ilerlemesini sağlayan küçük koordinatör.

bootReadinessInit <- function(session, required = NULL) {
  required <- required %||% c(
    "auth_ready",
    "saved_chats_preview_ready",
    "file_index_ready",
    "character_media_ready",
    "welcome_shell_ready",
    "welcome_client_ready"
  )

  done <- shiny::reactiveVal(character())

  mark <- function(key, label = key, pct = NULL, detail = NULL) {
    current <- done()
    if (!key %in% current) {
      done(c(current, key))
    }

    session$sendCustomMessage("bootReadinessCheckpoint", list(
      key = key,
      label = label,
      pct = pct,
      detail = detail,
      required_done = intersect(done(), required),
      required_total = length(required),
      ready = all(required %in% done())
    ))

    invisible(TRUE)
  }

  list(
    mark = mark,
    is_ready = function() all(required %in% done()),
    done = done,
    required = required
  )
}