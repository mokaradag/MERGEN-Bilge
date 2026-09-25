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

    # İstemci tercihini (yalnızca bastırma bayrağı; ANAHTAR DEĞİL) oku.
    # Kullanıcı "bu ekranı bir daha gösterme" dediyse veya Yapılandırma'dan
    # kapattıysa onboarding modalı yeni oturumda tekrar gösterilmez. Bayrak
    # tarayıcıda kullanıcıya özgü etiket altında tutulur; etiket kimlik hazır
    # olunca gönderilir, aynı tarayıcıdaki başka kullanıcı tercihi devralmaz.
    tercih_iste <- function(etiket) {
      session$sendCustomMessage("mergenApiKeyChoiceReportPref", list(
        inputId     = ns("api_key_onboarding_suppressed"),
        settingsKey = "api_key_onboarding_suppressed",
        userTag     = etiket
      ))
    }
    tercih_istek_zamani <- NULL

    # Onboarding kararı KİMLİĞE bağlıdır: aynı Shiny oturumu SSO ile başka
    # kullanıcıya geçerse önceki kullanıcının kararı devralınmaz.
    onboarding_tamam <- function(kullanici) {
      session$userData$api_key_onboarding_done <- TRUE
      session$userData$api_key_onboarding_owner <- as.character(kullanici %||% "")[1]
      invisible(NULL)
    }

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
        onboarding_tamam(owner$username)
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
        # Anahtar işleme sınırında hata metni kullanıcıya gösterilmeden önce
        # redakte edilir; hata bağlamı yanlışlıkla gizli değer taşıyabilir.
        hata_metni <- conditionMessage(e)
        if (exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
          hata_metni <- redact_sensitive_text(hata_metni)
        }
        showToast(session, paste("API anahtarı kaydedilemedi:", hata_metni), "error")
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
      # Modal açıkken kimlik düşmüş ya da değişmiş olabilir: karar kimliksiz
      # verilmez, modal açık kalır (kapalı-başarısız).
      sahip <- mb_api_key_resolve_owner(session, require_auth = TRUE)
      if (is.null(sahip) || !nzchar(as.character(sahip$username %||% "")[1])) {
        showToast(session, "Kimlik doğrulaması geçerli değil; seçim kaydedilmedi. Lütfen yeniden giriş yapın.", "warning")
        return()
      }
      onboarding_tamam(sahip$username)
      removeModal()
      showToast(session, "Varsayılan kurum API anahtarıyla devam ediyorsunuz.", "info")
      # Seçim ekranı yalnız kullanıcı "Bu ekranı bir daha gösterme"yi
      # işaretlediyse o kullanıcı için hatırlanır (Ayarlar > Yapılandırma'dan
      # geri açılır). "Hatırlanacak" onayı tarayıcı kaydı doğruladıktan sonra verilir.
      if (!isTRUE(input$api_key_dontshow)) {
        return()
      }
      hatirlatildi <- exists("remember_api_key_choice_default", mode = "function") &&
        isTRUE(remember_api_key_choice_default(
          session, sahip$username, result_input = ns("api_key_choice_remembered")
        ))
      if (!hatirlatildi) {
        showToast(session, "Seçiminiz bu tarayıcıda hatırlanamadı; seçim ekranı sonraki girişte yeniden gösterilebilir.", "warning")
      }
    }, ignoreInit = TRUE)

    observeEvent(input$api_key_choice_remembered, {
      if (isTRUE(input$api_key_choice_remembered$ok)) {
        showToast(session, "Seçiminiz hatırlanacak; Ayarlar > Yapılandırma'dan değiştirebilirsiniz.", "info")
      } else {
        showToast(session, "Seçiminiz bu tarayıcıda kaydedilemedi; seçim ekranı sonraki girişte yeniden gösterilebilir.", "warning")
      }
    }, ignoreInit = TRUE)

    # --- Başlangıçta: anahtarı yükle veya kullanıcıdan iste ---
    # SSO kimliği hazır olmadan kişisel anahtar aranmaz. Böylece paylaşımlı
    # Shiny OS hesabına ait dosya yanlışlıkla yüklenmez.
    #
    # Bastırma bayrağı (api_key_onboarding_suppressed) istemciden asenkron
    # gelir. Eğer karar bu bayrak gelmeden verilirse, "bir daha gösterme"
    # seçeneği işe yaramaz ve modal her açılışta tekrar görünür. Bu yüzden:
    #   - Kimlik hazır olduktan sonra istemci tercihinin gelmesi için kısa bir
    #     "tolerans" süresi (poll) tanırız.
    #   - Bayrak geldiğinde (TRUE/FALSE) hemen karar veririz.
    #   - Tolerans dolarsa varsayılan davranışa (göster) düşeriz.
    api_key_decision_start <- NULL
    karar_sahibi <- NULL
    shiny::observe({
      owner <- mb_api_key_resolve_owner(session, require_auth = TRUE)
      # Karar verildikten sonra yalnız kimlik değişimi seyrek izlenir; yeni
      # kullanıcı görülünce karar hızla yeniden verilir.
      seyrek <- !is.null(karar_sahibi) &&
        (is.null(owner) || identical(karar_sahibi, owner$username))
      shiny::invalidateLater(if (seyrek) 1000 else 150, session)

      if (is.null(owner)) {
        return(invisible(NULL))
      }

      # Aynı oturum başka kullanıcıya geçtiyse önceki kararın ve bayrağın
      # yerine yeni kullanıcı için akış baştan işler (kişisel anahtar/tercih).
      if (!is.null(karar_sahibi)) {
        if (identical(karar_sahibi, owner$username)) {
          return(invisible(NULL))
        }
        karar_sahibi <<- NULL
        api_key_decision_start <<- NULL
        tercih_istek_zamani <<- NULL
      }
      etiket <- api_key_pref_user_tag(owner$username) %||% ""

      # Kimlik hazır olduğu anı işaretle; tolerans penceresini buradan ölç.
      if (is.null(api_key_decision_start)) {
        api_key_decision_start <<- Sys.time()
      }

      loaded_key <- try(load_user_api_key(owner$username), silent = TRUE)
      if (!inherits(loaded_key, "try-error") && nzchar(loaded_key %||% "")) {
        # Kişisel anahtar mevcut: modal gösterilmez, normal akış devam eder.
        # Etiket yine gönderilir; Yapılandırma anahtarı tercihi yazabilsin.
        mb_api_key_set_session_key(session, loaded_key, owner = owner)
        tercih_iste(etiket)
        karar_sahibi <<- owner$username
        return(invisible(NULL))
      }

      if (isTRUE(session$userData$api_key_onboarding_done) &&
          identical(session$userData$api_key_onboarding_owner, owner$username)) {
        # Bu oturumda bu kullanıcı için zaten bir seçim yapıldı; tekrar sorma.
        karar_sahibi <<- owner$username
        return(invisible(NULL))
      }

      default_available <- nzchar(mb_api_key_get_default_key())

      # İstemciden gelen bastırma bayrağı (anahtar değil) etiketiyle gelir ve
      # yalnız bu kullanıcının etiketi taşıyorsa geçerlidir; önceki
      # kullanıcının yanıtı devralınmaz. Aksi halde "gelmemiş" kabul edilir.
      raw_flag <- shiny::isolate(input$api_key_onboarding_suppressed)
      flag_arrived <- is.list(raw_flag) &&
        identical(as.character(raw_flag$tag %||% "")[1], etiket) &&
        is.logical(raw_flag$suppressed) && length(raw_flag$suppressed) == 1L &&
        !is.na(raw_flag$suppressed)
      suppressed <- flag_arrived && isTRUE(raw_flag$suppressed)

      elapsed <- as.numeric(difftime(Sys.time(), api_key_decision_start, units = "secs"))

      # Tercih kimlik hazır olunca kullanıcı etiketiyle istenir. Zengin
      # başlangıçta tarayıcı meşgulken bayrak geç gelebilir; ilk istek
      # kaybolmuşsa yanıt gelene kadar saniyede bir yeniden istenir.
      if (!flag_arrived && (is.null(tercih_istek_zamani) ||
          as.numeric(difftime(Sys.time(), tercih_istek_zamani, units = "secs")) >= 1)) {
        tercih_iste(etiket)
        tercih_istek_zamani <<- Sys.time()
      }

      # Bastırma yalnızca varsayılan kurum anahtarı varken geçerlidir; aksi
      # halde kullanıcı anahtarsız kalır, bu yüzden yine de modalı gösteririz.
      if (suppressed && default_available) {
        onboarding_tamam(owner$username)
        karar_sahibi <<- owner$username
        return(invisible(NULL))
      }

      # Bayrak geldiyse (ve bastırma yoksa) ya da tolerans dolduysa karar ver.
      if (flag_arrived || elapsed >= 6) {
        onboarding_tamam(owner$username)
        karar_sahibi <<- owner$username
        shinyjs::delay(300, openModal())
        return(invisible(NULL))
      }

      # Aksi halde bayrağın gelmesini bekle (tolerans penceresi).
      invisible(NULL)
    })

    # Küçük bir modül API'si döndür.
    list(
      open = function(title = "API Anahtarı") openModal(title)
    )
  })
}