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
    # Her seçim modalı kendi jetonunu taşır; "bir daha gösterme" kutusunun
    # bekleyen değeri yalnız bu modal ve bu kullanıcı etiketiyle geçerlidir.
    # Modal sahibi: sahip değişince modal ve yazılmış anahtar kaldırılır, eski
    # modaldan gelen kaydetme/seçim yeni kullanıcı adına işlenmez.
    modal_jetonu <- ""
    modal_sayaci <- 0L
    modal_sahibi <- NULL
    # Tarayıcı tercih yazımının onayı yalnız bu yazımın jetonu ve sahibinin
    # etiketiyle kabul edilir; A'nın geç onayı B'ye bildirilmez.
    bekleyen_yazim <- NULL
    yazim_jetonu <- function(tur, etiket) {
      modal_sayaci <<- modal_sayaci + 1L
      bekleyen_yazim <<- list(jeton = sprintf("y%d-%.0f", modal_sayaci, as.numeric(Sys.time()) * 1000),
                              etiket = etiket %||% "", tur = tur)
      bekleyen_yazim$jeton
    }
    # Kullanıcı modalda açık seçim yaptıysa geç gelen tercih kararı değiştirmez.
    acik_secim <- FALSE

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
      sahip <- mb_api_key_resolve_owner(session, require_auth = TRUE)
      modal_sayaci <<- modal_sayaci + 1L
      modal_jetonu <<- sprintf("%d-%.0f", modal_sayaci, as.numeric(Sys.time()) * 1000)
      modal_sahibi <<- if (is.null(sahip)) "" else as.character(sahip$username %||% "")[1]
      show_api_key_choice_modal(
        session,
        default_available = default_available,
        service_desk = serviceDesk,
        nonce = modal_jetonu,
        user_tag = if (is.null(sahip)) "" else api_key_pref_user_tag(sahip$username) %||% ""
      )
    }

    # Sahip değişince/kimlik düşünce önceki sahibin modalı ve yazdığı anahtar
    # kaldırılır; oturumdaki kişisel anahtar bırakılır.
    sahip_birak <- function() {
      mb_api_key_clear_session_key(session)
      if (is.character(modal_sahibi) && !is.na(modal_sahibi)) {
        removeModal()
        try(updateTextInput(session, "api_key_plain_input", value = ""), silent = TRUE)
        shinyjs::runjs(sprintf("$('#%s').val('');", ns("api_key_plain_input")))
      }
      modal_jetonu <<- ""
      modal_sahibi <<- if (is.null(modal_sahibi)) NULL else NA_character_
      bekleyen_yazim <<- NULL
      invisible(NULL)
    }

    # Modal başka (önceki) sahip için açıldıysa işlem kabul edilmez.
    modal_sahibine_ait <- function(owner) {
      is.null(modal_sahibi) || identical(modal_sahibi, as.character(owner$username %||% "")[1])
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
      if (!modal_sahibine_ait(owner)) {
        showToast(session, "Oturum kimliği değişti; anahtar kaydedilmedi. Lütfen seçim ekranını yeniden açın.", "warning")
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
        # Açık kişisel anahtar seçimi, tarayıcıda hatırlanan kurum seçimini
        # kaldırır; tarayıcı yazımı doğrulamazsa kullanıcı uyarılır.
        if (exists("forget_api_key_choice_default", mode = "function")) {
          jeton <- yazim_jetonu("personal", api_key_pref_user_tag(owner$username))
          if (!isTRUE(forget_api_key_choice_default(
            session, owner$username, result_input = ns("api_key_choice_remembered"), nonce = jeton
          ))) {
            showToast(session, "Kurum anahtarı tercihi bu tarayıcıdan kaldırılamadı; sonraki girişte kurum anahtarı kullanılabilir.", "warning")
          }
        }
        # Bu oturumda onboarding kararı verildi; modal tekrar açılmasın.
        acik_secim <<- TRUE
        onboarding_tamam(owner$username)
        removeModal()
        modal_sahibi <<- NULL
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
      if (is.null(sahip) || !nzchar(as.character(sahip$username %||% "")[1]) || !modal_sahibine_ait(sahip)) {
        showToast(session, "Kimlik doğrulaması geçerli değil; seçim kaydedilmedi. Lütfen yeniden giriş yapın.", "warning")
        return()
      }
      # Kurum anahtarı seçilince oturumdaki kişisel anahtar bırakılır (kayıtlı
      # anahtar silinmez); aksi halde kişisel anahtar öncelikli kalırdı.
      mb_api_key_clear_session_key(session)
      acik_secim <<- TRUE
      onboarding_tamam(sahip$username)
      removeModal()
      modal_sahibi <<- NULL
      showToast(session, "Varsayılan kurum API anahtarıyla devam ediyorsunuz.", "info")
      # Seçim ekranı yalnız kullanıcı "Bu ekranı bir daha gösterme"yi
      # işaretlediyse o kullanıcı için hatırlanır (Ayarlar > Yapılandırma'dan
      # geri açılır). "Hatırlanacak" onayı tarayıcı kaydı doğruladıktan sonra verilir.
      # Kutunun değeri yalnız bu modal jetonu ve bu kullanıcının etiketiyle
      # geçerlidir; önceki modalın/kullanıcının işareti devralınmaz.
      # İşaret kaldırılmışsa (önceden hatırlanan bastırma dahil) tercih silinir;
      # sonraki girişte seçim ekranı yeniden gösterilir.
      etiket <- api_key_pref_user_tag(sahip$username)
      bekleyen <- input$api_key_dontshow
      bu_modal <- is.list(bekleyen) && nzchar(modal_jetonu) &&
        identical(as.character(bekleyen$nonce %||% "")[1], modal_jetonu) &&
        identical(as.character(bekleyen$tag %||% "")[1], etiket %||% NA_character_)
      if (!bu_modal) {
        return()
      }
      if (!isTRUE(bekleyen$checked)) {
        if (exists("clear_api_key_choice_pref", mode = "function")) {
          clear_api_key_choice_pref(session, sahip$username, result_input = ns("api_key_choice_remembered"),
                                    nonce = yazim_jetonu("clear", etiket))
        }
        return()
      }
      hatirlatildi <- exists("remember_api_key_choice_default", mode = "function") &&
        isTRUE(remember_api_key_choice_default(
          session, sahip$username, result_input = ns("api_key_choice_remembered"),
          nonce = yazim_jetonu("default", etiket)
        ))
      if (!hatirlatildi) {
        showToast(session, "Seçiminiz bu tarayıcıda hatırlanamadı; seçim ekranı sonraki girişte yeniden gösterilebilir.", "warning")
      }
    }, ignoreInit = TRUE)

    # Tarayıcı yazım onayı yalnız bekleyen yazımın jetonu ve geçerli sahibin
    # etiketiyle eşleşirse bildirilir.
    observeEvent(input$api_key_choice_remembered, {
      onay <- input$api_key_choice_remembered
      sahip <- mb_api_key_resolve_owner(session, require_auth = TRUE)
      yazim <- bekleyen_yazim
      if (!is.list(onay) || is.null(yazim) || is.null(sahip) ||
          !identical(as.character(onay$nonce %||% "")[1], yazim$jeton) ||
          !identical(as.character(onay$tag %||% "")[1], yazim$etiket) ||
          !identical(yazim$etiket, api_key_pref_user_tag(sahip$username) %||% NA_character_)) {
        return()
      }
      bekleyen_yazim <<- NULL
      tamam <- isTRUE(onay$ok)
      if (identical(yazim$tur, "default")) {
        if (tamam) {
          showToast(session, "Seçiminiz hatırlanacak; Ayarlar > Yapılandırma'dan değiştirebilirsiniz.", "info")
        } else {
          showToast(session, "Seçiminiz bu tarayıcıda kaydedilemedi; seçim ekranı sonraki girişte yeniden gösterilebilir.", "warning")
        }
      } else if (!tamam && identical(yazim$tur, "personal")) {
        showToast(session, "Kurum anahtarı tercihi bu tarayıcıdan kaldırılamadı; sonraki girişte kurum anahtarı kullanılabilir.", "warning")
      } else if (!tamam) {
        showToast(session, "Tercihiniz bu tarayıcıda kaydedilemedi; seçim ekranı sonraki girişte gösterilmeyebilir.", "warning")
      }
    }, ignoreInit = TRUE)

    # --- Başlangıçta: anahtarı yükle veya kullanıcıdan iste ---
    # SSO kimliği hazır olmadan kişisel anahtar aranmaz. Böylece paylaşımlı
    # Shiny OS hesabına ait dosya yanlışlıkla yüklenmez.
    #
    # Bastırma bayrağı (api_key_onboarding_suppressed) istemciden asenkron
    # gelir. Karar bayrak gelince ya da 6 sn tolerans dolunca verilir; tolerans
    # dolduktan sonra gelen eşleşen bayrak, kullanıcı açık seçim yapmadıysa
    # kararı uzlaştırır. Pencere, kimlik yokken ya da sahip değişince sıfırlanır.
    # Gözlemci kimliği yoklamaz: oturum kimlik sinyaline ve bayrağa bağımlıdır;
    # zamanlayıcı yalnız karar penceresi açıkken çalışır.
    kimlik_sinyali <- if (exists("mergen_session_identity_signal", mode = "function")) {
      mergen_session_identity_signal(session)
    }
    api_key_decision_start <- NULL
    karar_sahibi <- NULL
    pencere_sahibi <- NULL
    kisisel_anahtar <- NULL
    zaman_asimi_karari <- FALSE
    shiny::observe({
      if (is.function(kimlik_sinyali)) kimlik_sinyali() else shiny::invalidateLater(5000, session)
      raw_flag <- input$api_key_onboarding_suppressed
      owner <- mb_api_key_resolve_owner(session, require_auth = TRUE)

      # Kimlik yokken karar ve tolerans penceresi bırakılır: aynı kullanıcı geri
      # gelince kişisel anahtar yeniden yüklenir, tercih yeniden beklenir.
      if (is.null(owner)) {
        if (!is.null(pencere_sahibi)) sahip_birak()
        karar_sahibi <<- NULL
        pencere_sahibi <<- NULL
        kisisel_anahtar <<- NULL
        return(invisible(NULL))
      }

      etiket <- api_key_pref_user_tag(owner$username) %||% ""
      default_available <- nzchar(mb_api_key_get_default_key())
      # İstemciden gelen bastırma bayrağı (anahtar değil) yalnız bu kullanıcının
      # etiketini taşıyorsa geçerlidir; önceki kullanıcının yanıtı devralınmaz.
      flag_arrived <- is.list(raw_flag) &&
        identical(as.character(raw_flag$tag %||% "")[1], etiket) &&
        is.logical(raw_flag$suppressed) && length(raw_flag$suppressed) == 1L &&
        !is.na(raw_flag$suppressed)
      suppressed <- flag_arrived && isTRUE(raw_flag$suppressed)
      kurum_hatirlandi <- suppressed && default_available &&
        identical(as.character(raw_flag$source %||% "")[1], "default")

      if (identical(karar_sahibi, owner$username)) {
        # Tolerans sonrası geç gelen tercih, açık seçim yoksa uygulanır.
        if (zaman_asimi_karari && flag_arrived && !acik_secim) {
          zaman_asimi_karari <<- FALSE
          if (kurum_hatirlandi && !is.null(kisisel_anahtar)) mb_api_key_clear_session_key(session)
          if (suppressed && default_available && is.null(kisisel_anahtar) &&
              identical(modal_sahibi, owner$username)) {
            removeModal()
            modal_sahibi <<- NULL
          }
        }
        return(invisible(NULL))
      }

      # Yeni sahip için pencere baştan açılır: önceki sahibin oturum anahtarı ve
      # modalı kaldırılır, kişisel anahtar ADAY olarak yüklenir. Kurum seçimi
      # hatırlanmış olabileceğinden aday, tercih bilinene dek yayımlanmaz.
      if (!identical(pencere_sahibi, owner$username)) {
        if (is.null(pencere_sahibi)) mb_api_key_clear_session_key(session) else sahip_birak()
        karar_sahibi <<- NULL
        pencere_sahibi <<- owner$username
        api_key_decision_start <<- Sys.time()
        tercih_istek_zamani <<- NULL
        zaman_asimi_karari <<- FALSE
        acik_secim <<- FALSE
        loaded_key <- try(load_user_api_key(owner$username), silent = TRUE)
        kisisel_anahtar <<- if (!inherits(loaded_key, "try-error") && nzchar(loaded_key %||% "")) loaded_key
      }

      elapsed <- as.numeric(difftime(Sys.time(), api_key_decision_start, units = "secs"))

      # Tercih kullanıcı etiketiyle istenir; ilk istek kaybolmuşsa yanıt gelene
      # kadar saniyede bir yeniden istenir.
      if (!flag_arrived && (is.null(tercih_istek_zamani) ||
          as.numeric(difftime(Sys.time(), tercih_istek_zamani, units = "secs")) >= 1)) {
        tercih_iste(etiket)
        tercih_istek_zamani <<- Sys.time()
      }
      karar_ver <- function(zaman_asimi) {
        karar_sahibi <<- owner$username
        zaman_asimi_karari <<- zaman_asimi
      }

      # Kişisel anahtar varken modal gösterilmez. Kurum anahtarı yoksa belirsizlik
      # yoktur, anahtar hemen yayımlanır; varsa tercih (ya da tolerans) beklenir
      # ve kurum seçimi hatırlanmışsa kişisel anahtar oturuma hiç açılmaz.
      if (!is.null(kisisel_anahtar)) {
        if (default_available && !flag_arrived && elapsed < 6) {
          shiny::invalidateLater(150, session)
          return(invisible(NULL))
        }
        if (!kurum_hatirlandi) mb_api_key_set_session_key(session, kisisel_anahtar, owner = owner)
        karar_ver(!flag_arrived)
        return(invisible(NULL))
      }

      if (isTRUE(session$userData$api_key_onboarding_done) &&
          identical(session$userData$api_key_onboarding_owner, owner$username)) {
        # Bu oturumda bu kullanıcı için zaten bir seçim yapıldı; tekrar sorma.
        karar_ver(FALSE)
        return(invisible(NULL))
      }

      # Bastırma yalnızca varsayılan kurum anahtarı varken geçerlidir; aksi
      # halde kullanıcı anahtarsız kalır, bu yüzden yine de modalı gösteririz.
      if (suppressed && default_available) {
        onboarding_tamam(owner$username)
        karar_ver(FALSE)
        return(invisible(NULL))
      }

      # Bayrak geldiyse (ve bastırma yoksa) ya da tolerans dolduysa karar ver.
      # Gecikmeli açılış yalnız hâlâ aynı sahip için yapılır.
      if (flag_arrived || elapsed >= 6) {
        onboarding_tamam(owner$username)
        karar_ver(!flag_arrived)
        acilis_sahibi <- owner$username
        shinyjs::delay(300, {
          simdiki <- mb_api_key_resolve_owner(session, require_auth = TRUE)
          if (!is.null(simdiki) && identical(simdiki$username, acilis_sahibi) &&
              identical(karar_sahibi, acilis_sahibi)) {
            openModal()
          }
        })
        return(invisible(NULL))
      }

      # Aksi halde bayrağın gelmesini bekle (tolerans penceresi).
      shiny::invalidateLater(150, session)
      invisible(NULL)
    })

    # Küçük bir modül API'si döndür.
    list(
      open = function(title = "API Anahtarı") openModal(title)
    )
  })
}