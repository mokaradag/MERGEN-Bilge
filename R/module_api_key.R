# ==============================================================================
# Dosya Yolu: R/module_api_key.R
# Açıklama:   API anahtarı modalını, kalıcılığını ve doğrulamasını yöneten
#             güvenli Shiny sunucu modülü.
# ==============================================================================

apiKeyServer <- function(id, serviceDesk, api_config) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Her yeni oturumda anahtar önce boşaltılır; yalnızca doğrulanmış
    # uygulama kullanıcısına ait anahtar tekrar yüklenir.
    mb_api_key_clear_session_key(session)

    # --- İç işlem: modalı aç ---
    openModal <- function(title = "API Anahtarı Eksik") {
      showModal(modalDialog(
        title = title,
        easyClose = FALSE, footer = NULL, size = "l",
        div(
          id = "api_key_modal",
          class = "setting-item",

          # Parola giriş alanı için tam genişliği zorunlu uygula.
          tags$style(HTML(sprintf("
            #api_key_modal #%s { 
              width: 400px !important;
              min-width: 400px !important;
              max-width: 400px !important;
              box-sizing: border-box;
            }
            #api_key_modal .shiny-input-container { width: auto !important; }

            #api_key_modal #secure_tooltip {
              display: inline-block;
              color: #93c5fd;
              text-decoration: underline dotted;
              text-underline-offset: 2px;
              cursor: help;
              transition: color .15s ease, text-shadow .15s ease;
            }
            #api_key_modal #secure_tooltip:hover,
            #api_key_modal #secure_tooltip:focus {
              color: #bfdbfe;
              text-shadow: 0 0 6px rgba(147, 197, 253, .35);
              outline: none;
            }
          ", ns("api_key_plain_input")))),

          # \U0001F512 bilgi + ipucu
          tags$p(HTML(
            'API anahtarınız sistemde <span id="secure_tooltip" tabindex="0" data-toggle="tooltip" data-placement="top" data-container="body" data-html="true" title="&lt;i class=&quot;fa fa-lock&quot; aria-hidden=&quot;true&quot;&gt;&lt;/i&gt; AES-256-GCM ile şifreleme yapılır">güvenle</span> saklanır.'
          )),

          div(
            style = "margin-top: 6px;",
            passwordInput(
              ns("api_key_plain_input"),
              label = "API Anahtarı"
            )
          ),

          div(
            style = "display:flex; gap:10px; justify-content:space-between; align-items:center; margin-top:12px; flex-wrap:wrap;",
            # Sol yardımcılar
            div(
              style = "display:flex; gap:10px; flex-wrap:wrap;",
              tags$a(
                href   = serviceDesk$api_key_request_url,
                target = "_blank",
                class  = "btn-modern btn-secondary",
                role   = "button",
                tagList(icon("external-link-alt"), "API Anahtarı Talep Et")
              ),
              actionButton(
                ns("api_key_clear_btn"),
                label = tagList(icon("eraser"), "Temizle"),
                class = "btn-modern btn-secondary"
              )
            ),
            # Sağ birincil işlemler
            div(
              style = "display:flex; gap:10px;",
              actionButton(
                ns("api_key_save_btn"),
                label = tagList(icon("save"), "Kaydet"),
                class = "btn-modern btn-primary"
              ),
              tags$button(
                type = "button",
                class = "btn-modern btn-secondary",
                `data-dismiss` = "modal",
                tagList(icon("times"), "Kapat")
              )
            )
          )
        )
      ))

      # Modal DOM'a eklendikten sonra Bootstrap ipucunu başlat.
      shinyjs::runjs(
        "setTimeout(function(){
            var el = document.getElementById('secure_tooltip');
            if (el && typeof $(el).tooltip === 'function') {
              $(el).tooltip({ html: true, container: 'body', placement: 'top', trigger: 'hover focus' });
            }
          }, 50);"
      )
    }

    # --- Kaydetme işleyicisi ---
    observeEvent(input$api_key_save_btn, {
      req(input$api_key_plain_input)
      key_plain <- trimws(input$api_key_plain_input)
      if (!nzchar(key_plain)) {
        showToast(session, "Anahtar boş olamaz.", "warning"); return()
      }

      owner <- mb_api_key_resolve_owner(session, require_auth = TRUE)
      if (is.null(owner)) {
        showToast(session, "Kimlik doğrulama tamamlanmadan API anahtarı kaydedilemez.", "warning")
        return()
      }

      target <- determine_api_key_validation_target(NULL, api_config)
      if (!isTRUE(target$allow_user_key) || !nzchar(target$endpoint)) {
        showToast(session, "Bu ortamda kullanıcı tarafından yönetilen bir API anahtarı bulunmuyor.", "error")
        return()
      }

      vres <- try(
        validate_api_key(
          key_plain,
          model_id = target$model_id,
          endpoint = target$endpoint,
          timeout_seconds = 6
        ),
        silent = TRUE
      )

      if (inherits(vres, "try-error") || !is.list(vres)) {
        err_msg <- tryCatch(conditionMessage(attr(vres, "condition")), error = function(e) "Bilinmeyen hata")
        showToast(session, paste("Anahtar doğrulaması başarısız:", err_msg), "error")
        return()
      }

      if (identical(vres$valid, FALSE)) {
        showToast(session, paste("API anahtarı geçersiz:", vres$message %||% ""), "error")
        return()
      }

      if (!isTRUE(vres$valid)) {
        showToast(session, paste("Anahtar doğrulanamadı (kaydedilmedi):", vres$message %||% "Doğrulama başarısız."), "error")
        return()
      }

      # Kalıcı olarak sakla (şifreli) ve oturuma aç.
      tryCatch({
        save_user_api_key(owner$username, key_plain)
        mb_api_key_set_session_key(session, key_plain, owner = owner)
        removeModal()
        success_msg <- vres$message %||% "API anahtarı kaydedildi."
		if (isTRUE(target$fallback_used)) {
          success_msg <- paste(success_msg, "Not: Doğrulama birincil uç noktada yapıldı.")
        }
        if (!nzchar(success_msg)) {
          success_msg <- "API anahtarı kaydedildi."
        } else if (!grepl("API anahtarı", success_msg, fixed = TRUE)) {
          success_msg <- paste("API anahtarı kaydedildi \U2014", success_msg)
        }
        showToast(session, success_msg, "success")
      }, error = function(e) {
        showToast(session, paste("API anahtarı kaydedilemedi:", conditionMessage(e)), "error")
      })
    }, ignoreInit = TRUE)

    # --- Temizleme işleyicisi ---
    observeEvent(input$api_key_clear_btn, {
      try(updateTextInput(session, "api_key_plain_input", value = ""), silent = TRUE)
      shinyjs::runjs(sprintf("$('#%s').val('');", ns("api_key_plain_input")))
    }, ignoreInit = TRUE)

    # --- Başlangıçta: anahtarı yükle veya kullanıcıdan iste ---
    # SSO kimliği hazır olmadan kişisel anahtar aranmaz. Böylece paylaşımlı
    # Shiny OS hesabına ait dosya yanlışlıkla yüklenmez.
    api_key_load_observer <- NULL
    api_key_load_observer <- shiny::observe({
      shiny::invalidateLater(200, session)

      owner <- mb_api_key_resolve_owner(session, require_auth = TRUE)
      if (is.null(owner)) {
        return(invisible(NULL))
      }

      loaded_key <- try(load_user_api_key(owner$username), silent = TRUE)
      if (!inherits(loaded_key, "try-error") && nzchar(loaded_key %||% "")) {
        mb_api_key_set_session_key(session, loaded_key, owner = owner)
      } else if (nzchar(mb_api_key_get_default_key())) {
        showToast(
          session,
          "Kişisel API anahtarınız bulunamadı; varsayılan kurum API anahtarı kullanılacak.",
          "info"
        )
      } else {
        shinyjs::delay(400, openModal("API Anahtarı Eksik"))
      }

      if (!is.null(api_key_load_observer)) {
        api_key_load_observer$destroy()
      }

      invisible(NULL)
    })

    # Küçük bir modül API'si döndür.
    list(
      open = function(title = "API Anahtarı") openModal(title)
    )
  })
}