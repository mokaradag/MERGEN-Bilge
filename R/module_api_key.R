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

    # İstemci tercihini (yalnızca bastırma bayrağı; ANAHTAR DEĞİL) erken oku.
    # Kullanıcı "bu ekranı bir daha gösterme" dediyse veya Yapılandırma'dan
    # kapattıysa, mergen_settings.api_key_onboarding_suppressed=true olur ve
    # onboarding modalı yeni oturumda tekrar gösterilmez.
    session$sendCustomMessage("mergenApiKeyChoiceReportPref", list(
      inputId     = ns("api_key_onboarding_suppressed"),
      settingsKey = "api_key_onboarding_suppressed"
    ))

    # --- İç işlem: premium API anahtarı seçim modalını aç ---
    # Modal içeriği R/module_api_key_choice_modal.R içinde üretilir. Burada
    # yalnızca varsayılan kurum anahtarının kullanılabilir olup olmadığına
    # göre iki yollu / tek yollu görünüm seçilir. Hiçbir anahtar değeri
    # bu fonksiyonda okunmaz, saklanmaz veya gösterilmez.
    openModal <- function(title = NULL) {
      default_available <- nzchar(mb_api_key_get_default_key())
      show_api_key_choice_modal(
        session,
        default_available = default_available,
        service_desk = serviceDesk
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
        # Bu oturumda onboarding kararı verildi; modal tekrar açılmasın.
        session$userData$api_key_onboarding_done <- TRUE
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

    # --- "Varsayılan kurum anahtarı ile devam et" işleyicisi ---
    # Varsayılan kurum anahtarı tamamen sunucu tarafında (MERGEN_DEFAULT_API_KEY)
    # yönetilir. Burada hiçbir anahtar saklanmaz, yazılmaz, loglanmaz veya
    # istemciye gönderilmez. Yalnızca modal kapatılır; uygulama mevcut etkin
    # anahtar yardımcıları üzerinden varsayılan anahtar akışıyla devam eder.
    observeEvent(input$api_key_use_default_btn, {
      if (!nzchar(mb_api_key_get_default_key())) {
        showToast(session, "Varsayılan kurum API anahtarı bu ortamda kullanılamıyor.", "warning")
        return()
      }
      session$userData$api_key_onboarding_done <- TRUE
      removeModal()
      showToast(session, "Varsayılan kurum API anahtarıyla devam ediyorsunuz.", "info")
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
        # Kişisel anahtar mevcut: modal gösterilmez, normal akış devam eder.
        mb_api_key_set_session_key(session, loaded_key, owner = owner)
      } else {
        default_available <- nzchar(mb_api_key_get_default_key())

        # İstemciden gelen bastırma bayrağı (anahtar değil): kullanıcı "bir
        # daha gösterme" dediyse veya Yapılandırma'dan kapattıysa TRUE olur.
        suppressed <- tryCatch(
          isTRUE(shiny::isolate(input$api_key_onboarding_suppressed)),
          error = function(e) FALSE
        )

        if (isTRUE(session$userData$api_key_onboarding_done)) {
          # Bu oturumda zaten bir seçim yapıldı; tekrar sorma.
        } else if (isTRUE(suppressed) && default_available) {
          # Kullanıcı bu ekranı bir daha görmek istemiyor VE varsayılan kurum
          # anahtarı mevcut; modalı göstermeden varsayılan akışla devam et.
          # Not: varsayılan anahtar yoksa bastırma yok sayılır, aksi halde
          # kullanıcı anahtarsız kalır.
          session$userData$api_key_onboarding_done <- TRUE
        } else {
          # Kişisel anahtar yok: premium seçim modalını göster. Varsayılan
          # kurum anahtarı varsa iki yol, yoksa yalnızca kişisel yol sunulur.
          shinyjs::delay(400, openModal())
        }
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