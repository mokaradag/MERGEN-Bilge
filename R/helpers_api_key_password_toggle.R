# ==============================================================================
# Dosya Yolu: R/helpers_api_key_password_toggle.R
# Açıklama:   API anahtarı parola alanları için ortak göster/gizle UI yardımcısı.
#             Yalnızca güvenli UI öznitelikleri üretir; anahtar değerini okumaz,
#             saklamaz, loglamaz veya istemciye yazmaz.
# ==============================================================================

api_key_password_input_with_toggle <- function(ns,
                                               input_id,
                                               label,
                                               width = "100%",
                                               wrapper_class = NULL) {
  if (!is.function(ns)) {
    stop("api_key_password_input_with_toggle: ns fonksiyon olmalıdır.", call. = FALSE)
  }

  input_id <- as.character(input_id %||% "")[1]
  label <- as.character(label %||% "")[1]
  width <- as.character(width %||% "100%")[1]

  if (!nzchar(input_id)) {
    stop("api_key_password_input_with_toggle: input_id boş olamaz.", call. = FALSE)
  }

  class_values <- c("api-key-password-field", as.character(wrapper_class %||% character(0)))
  class_values <- class_values[nzchar(class_values)]

  div(
    class = paste(class_values, collapse = " "),
    `data-api-key-password-field` = "1",
    htmltools::tagQuery(
      passwordInput(
        inputId = ns(input_id),
        label = label,
        width = width
      )
    )$find("input")$addAttrs(
      autocomplete = "new-password",
      `data-api-key-password-input` = "1"
    )$allTags(),
    tags$button(
      type = "button",
      class = "api-key-password-toggle",
      `data-api-key-password-toggle` = "1",
      `aria-label` = "API anahtarını göster",
      `aria-pressed` = "false",
      icon("eye"),
      tags$span(
        class = "api-key-password-toggle-text sr-only",
        "API anahtarını göster"
      )
    )
  )
}