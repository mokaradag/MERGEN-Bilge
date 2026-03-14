# R/module_api_key.R
# Simple, safe module to handle the API key modal + persistence/validation
apiKeyServer <- function(id, serviceDesk, api_config) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # --- internal: open the modal ---
    openModal <- function(title = "API Anahtarı Eksik") {
      showModal(modalDialog(
        title = title,
        easyClose = FALSE, footer = NULL, size = "l",
        div(
          id = "api_key_modal",
          class = "setting-item",

          # enforce exact width for the password input (namespaced)
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

          # \U0001F512 info + tooltip
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
            # Left helpers
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
            # Right primaries
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

      # Initialize Bootstrap tooltip after modal is in the DOM
      shinyjs::runjs(
        "setTimeout(function(){
            var el = document.getElementById('secure_tooltip');
            if (el && typeof $(el).tooltip === 'function') {
              $(el).tooltip({ html: true, container: 'body', placement: 'top', trigger: 'hover focus' });
            }
          }, 50);"
      )
    }

    # --- Save handler ---
    observeEvent(input$api_key_save_btn, {
      req(input$api_key_plain_input)
      key_plain <- trimws(input$api_key_plain_input)
      if (!nzchar(key_plain)) {
        showToast(session, "Anahtar boş olamaz.", "warning"); return()
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

      # persist (encrypted) + expose to session
      tryCatch({
        # prefer the username set by app, else fallback
        system_username <- session$userData$system_username %||% Sys.info()[["user"]]
        save_user_api_key(system_username, key_plain)
        session$userData$ai_api_key <- key_plain
        removeModal()
        success_msg <- vres$message %||% "API anahtarı kaydedildi."
		if (isTRUE(target$fallback_used)) {
          success_msg <- paste(success_msg, "Not: Doğrulama birincil uç noktada yapıldı.")
        }
        if (!nzchar(success_msg)) {
          success_msg <- "API anahtarı kaydedildi."
        } else if (!grepl("API anahtarı", success_msg, fixed = TRUE)) {
          success_msg <- paste("API anahtarı kaydedildi —", success_msg)
        }
        showToast(session, success_msg, "success")
      }, error = function(e) {
        showToast(session, paste("API anahtarı kaydedilemedi:", conditionMessage(e)), "error")
      })
    }, ignoreInit = TRUE)

    # --- Clear handler ---
    observeEvent(input$api_key_clear_btn, {
      try(updateTextInput(session, "api_key_plain_input", value = ""), silent = TRUE)
      shinyjs::runjs(sprintf("$('#%s').val('');", ns("api_key_plain_input")))
    }, ignoreInit = TRUE)

    # --- On init: load key or ask user ---
    shiny::observeEvent(TRUE, {
      loaded_key <- try(load_user_api_key(session$userData$system_username %||% Sys.info()[["user"]]), silent = TRUE)
      if (!inherits(loaded_key, "try-error") && nzchar(loaded_key %||% "")) {
        session$userData$ai_api_key <- loaded_key
      } else {
        shinyjs::delay(400, openModal("API Anahtarı Eksik"))
      }
    }, once = TRUE)

    # return a small API
    list(
      open = function(title = "API Anahtarı") openModal(title)
    )
  })
}