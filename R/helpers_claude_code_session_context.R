# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_session_context.R
# Açıklama: Bilge Yolaç oturum bağlamı yardımcıları.
#           Aktif karakter ve kullanıcı görünen adını module_claude_code.R
#           dışına alarak sunucu modülünü sadeleştirir.
# ==============================================================================

cc_create_active_character_reactive <- function(settings_data = NULL) {
  reactive({
    karakter_id <- "mergen"

    if (!is.null(settings_data) && !is.null(settings_data$selected_character)) {
      secili <- settings_data$selected_character
      if (!is.null(secili) && nzchar(secili)) {
        karakter_id <- secili
      }
    }

    karakterler <- get_characters_data()
    secili <- NULL

    for (s in karakterler$styles) {
      if (s$id == karakter_id) {
        secili <- s
        break
      }
    }

    if (is.null(secili)) {
      secili <- karakterler$styles[[1]]
    }

    secili
  })
}

cc_create_user_first_name_reactive <- function(session, user_first_name = NULL) {
  reactive({
    if (!is.null(user_first_name)) {
      ad <- if (is.function(user_first_name)) {
        tryCatch(user_first_name(), error = function(e) NULL)
      } else if (is.reactive(user_first_name)) {
        user_first_name()
      } else {
        user_first_name
      }

      ad <- as.character(ad %||% "")[1]
      if (nzchar(ad)) {
        return(ad)
      }
    }

    ad <- session$userData$user_first_name
    if (!is.null(ad) && nzchar(ad)) {
      return(ad)
    }

    uc <- session$userData$user_config
    if (!is.null(uc) && !is.null(uc$first_name) && nzchar(uc$first_name)) {
      return(uc$first_name)
    }

    if (!is.null(uc) && !is.null(uc$name) && nzchar(uc$name)) {
      return(uc$name)
    }

    "Siz"
  })
}