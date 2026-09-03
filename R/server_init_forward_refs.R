# ==============================================================================
# Dosya Yolu: R/server_init_forward_refs.R
# Açıklama: server.R içinde kullanılan ileri referans sarmalayıcılarını üretir.
#           Karşılama ekranı ve mesaj gönderme fonksiyonları için güvenli
#           gecikmeli bağlama sağlar.
# ==============================================================================

serverInitForwardRefs <- function(session) {

  # ---------------------------------------------------------------------------
  # Karşılama ekranı fonksiyonları için ileri referans ortamı
  # ---------------------------------------------------------------------------
  welcome_fns <- new.env(parent = emptyenv())

  render_welcome_screen <- function(...) {
    fn <- welcome_fns$render_welcome_screen
    if (is.function(fn)) {
      fn(...)
    } else {
      invisible(NULL)
    }
  }

  start_new_chat <- function(...) {
    fn <- welcome_fns$start_new_chat
    if (is.function(fn)) {
      fn(...)
    } else {
      invisible(NULL)
    }
  }

  # ---------------------------------------------------------------------------
  # Mesaj gönderme fonksiyonu için ileri referans ortamı
  # ---------------------------------------------------------------------------
  send_message_fns <- new.env(parent = emptyenv())

  send_message <- function(...) {
    fn <- send_message_fns$send_message

    if (!is.function(fn)) {
      showToast(session, "Mesaj gönderme bileşeni henüz hazır değil.", "warning")
      return(invisible(NULL))
    }

    fn(...)
  }

  list(
    welcome_fns = welcome_fns,
    render_welcome_screen = render_welcome_screen,
    start_new_chat = start_new_chat,
    send_message_fns = send_message_fns,
    send_message = send_message
  )
}