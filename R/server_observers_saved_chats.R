# R/server_observers_saved_chats.R
# Dosya Yolu: R/server_observers_saved_chats.R
# Açıklama: Kayıtlı söyleşilerin yüklenmesi, silinmesi ve temizlenmesi ile ilgili observer fonksiyonları.
# Bu dosya server.R'den ayrılarak modülerlik sağlanmıştır.

#' "Söyleşi yüklendi" toast'ını mesaj balonları DOM'a GERÇEKTEN eklendikten
#' sonra göster. Balonlar hiç görünmezse (yükleme başarısız/yarım) toast
#' gösterilmez; boş söyleşilerde beklenecek balon olmadığından hemen gösterilir.
mergen_show_chat_loaded_toast <- function(session, title, last_message_id = NULL) {
  metin <- paste("Söyleşi yüklendi:", as.character(title %||% ""))

  if (is.null(last_message_id) || !nzchar(as.character(last_message_id)[1])) {
    showToast(session, metin, "info")
    return(invisible(NULL))
  }

  payload <- jsonlite::toJSON(
    list(
      text = metin,
      lastId = paste0("message_wrapper_", as.character(last_message_id)[1])
    ),
    auto_unbox = TRUE
  )

  shinyjs::runjs(sprintf("
    (function() {
      var info = %s;
      var attempts = 0;
      var timer = setInterval(function() {
        attempts += 1;
        var ready = !!document.getElementById(info.lastId);
        if (ready || attempts >= 50) {
          clearInterval(timer);
          if (ready && typeof window.showToast === 'function') {
            window.showToast(info.text, 'info');
          }
        }
      }, 100);
    })();
  ", payload))

  invisible(NULL)
}

#' Kayıtlı Sohbet Gözlemcilerini Başlat
#' @description Kayıtlı söyleşi işlemleri için observer'ları kurar
#' @param input Shiny input nesnesi
#' @param output Shiny output nesnesi
#' @param session Shiny session nesnesi
#' @param values Ana reaktif değerler
#' @param settings_data Ayarlar modülünden dönen reaktif ayarlar
#' @param saved_chats_data Kayıtlı söyleşiler modül verisi
#' @param current_user_id Mevcut kullanıcı ID'si
#' @param load_chat_in_progress Sohbet yükleme kilit reaktif değeri
savedChatsObserversInit <- function(input, output, session, values, settings_data,
                                    saved_chats_data, current_user_id,
                                    load_chat_in_progress,
                                    user_config_provider = NULL,
                                    user_first_name_fn = NULL) {
  
  # Son silinen sohbet ID'sini takip et (silme sonrası yanlış yüklemeyi engellemek için)
  last_deleted_chat_id <- reactiveVal(NULL)

  # Etkin kullanıcı kimliğini her kullanım anında oturumdan çöz.
  resolve_current_user_id <- function() {
    resolve_effective_user_id(
      session = session,
      current_user_id = current_user_id
    )
  }

  resolve_user_config <- function(default = NULL) {
    cfg <- NULL

    if (is.function(user_config_provider)) {
      cfg <- tryCatch(
        user_config_provider(default = default),
        error = function(e) NULL
      )
    }

    cfg %||% session$userData$user_config %||% default
  }

  resolve_user_first_name <- function(default = "") {
    value <- NULL

    if (is.function(user_first_name_fn)) {
      value <- tryCatch(
        user_first_name_fn(default = default),
        error = function(e) NULL
      )
    }

    value <- value %||% session$userData$user_first_name %||% default
    value <- as.character(value %||% default)

    if (!nzchar(value)) {
      return(default)
    }

    value
  }
  
  # -------------------------------------------------------------------------
  # Ortak Sohbet Yükleme Fonksiyonu
  # -------------------------------------------------------------------------
  do_load_chat <- function(chat_id) {
    # Boş veya NULL chat_id'yi yoksay
    if (is.null(chat_id) || !nzchar(chat_id)) {
      return()
    }
    
    # Son silinen sohbeti yüklemeye çalışıyorsa engelle
    if (identical(chat_id, last_deleted_chat_id())) {
      cat(sprintf("[SAVED_CHATS] Silinen sohbet yüklenmeye çalışıldı, engellendi: %s\n", chat_id))
      last_deleted_chat_id(NULL)  # Bayrağı sıfırla
      return()
    }
    
    # Çift yüklemeyi engelle
    if (load_chat_in_progress()) {
      return()
    }

    load_chat_in_progress(TRUE)

    # KİLİT HER ÇIKIŞ YOLUNDA BIRAKILIR.
    #
    # `load_feedback_from_db()` ya da sonraki bir render adımı hata fırlattığında
    # fonksiyon, gecikmeli sıfırlama planlanmadan ÖNCE terk ediliyordu. Kilit
    # TRUE kalıyor ve kullanıcı oturumu yeniden yükleyene kadar HİÇBİR sohbet
    # açılamıyordu. Başarı yolunda sahiplik gecikmeli geri çağrıya DEVREDİLİR
    # (kısa gecikme çift tıklamayı emmeye devam eder); bu yüzden `basarili`
    # bayrağı yalnızca orada TRUE olur.
    basarili <- FALSE
    on.exit({
      if (!isTRUE(basarili)) try(load_chat_in_progress(FALSE), silent = TRUE)
    }, add = TRUE)

    # ANINDA görsel geri bildirim: özel mesajlar reaktif flush beklemeden
    # websocket'e yazıldığı için bu toast, aşağıdaki DB hidrasyonu ve UI
    # kurulumu sürerken kullanıcıya hemen görünür. Başarı toast'ı ise içerik
    # mesajlarından SONRA gönderilir (dürüst toast sıralaması).
    yukleme_baslangici <- Sys.time()
    showToast(session, "Söyleşi yükleniyor...", "info")

    # Kaydedilmiş bir sohbet açılırken araç bağlamlı arka plan animasyonu
    # temizlenir. Animasyonlar yalnızca hızlı eylem tanıtım mesajı görünürken
    # gösterilmelidir; eski bir sohbeti açmak yeni bir oturum başlangıcı
    # değildir ve önceki araç ailesi sahnesinde takılı kalmamalıdır.
    tryCatch(
      session$sendCustomMessage("setToolBackgroundFamily", list(
        clear = TRUE,
        reason = "load_saved_chat"
      )),
      error = function(e) invisible(NULL)
    )

    chat_to_load <- values$saved_chats[[chat_id]]
    needs_hydrate <- is.null(chat_to_load)
    
    if (!needs_hydrate) {
      msgs <- chat_to_load$messages
      stored_len <- if (is.list(msgs)) length(msgs) else 0L
      expected_len <- as.integer(chat_to_load$message_count %||% stored_len)
      has_user <- stored_len > 0 && any(vapply(msgs, function(m) {
        identical(m$type %||% "", "user")
      }, logical(1)))
      has_ai <- stored_len > 0 && any(vapply(msgs, function(m) {
        (m$type %||% "") %in% c("ai", "assistant")
      }, logical(1)))
      
      needs_hydrate <- is.null(msgs) || !is.list(msgs) || stored_len == 0 ||
        (!is.na(expected_len) && expected_len > stored_len) ||
        (has_user && !has_ai)
    }
    
    if (isTRUE(needs_hydrate)) {
      detail <- tryCatch(
        load_chat_messages_from_db(
          chat_id,
          user_id = resolve_current_user_id()
        ),
        error = function(e) {
          warning(sprintf("Failed to load chat %s messages: %s", chat_id, e$message))
          NULL
        }
      )
      if (!is.null(detail)) {
        chat_to_load <- detail
        saved_copy <- values$saved_chats
        saved_copy[[chat_id]] <- chat_to_load
        values$saved_chats <- saved_copy
      }
    }
    
    # Sohbet bulunamazsa çık
    if (is.null(chat_to_load)) {
      cat(sprintf("[SAVED_CHATS] Sohbet bulunamadı: %s\n", chat_id))
      load_chat_in_progress(FALSE)
      return()
    }
    
    # Welcome ekranını temizle ve aşağı kaydır butonunu gizle
    shinyjs::runjs("
      if(window.WelcomeVideoPlayer && window.WelcomeVideoPlayer.destroy) {
        window.WelcomeVideoPlayer.destroy();
      }
      if(window.WelcomeNeuralNetwork && window.WelcomeNeuralNetwork.destroy) {
        window.WelcomeNeuralNetwork.destroy();
      }
      if(window.WelcomeGreeting && window.WelcomeGreeting.destroy) {
        window.WelcomeGreeting.destroy();
      }
      $('#welcome_fullscreen_container').addClass('hidden').empty();
      $('#chat_content_container').show().empty();
      $('#scroll_to_bottom_container').removeClass('show');
    ")
    
    removeUI(selector = "#welcome_fullscreen_container > *", multiple = TRUE, immediate = TRUE)
    removeUI(selector = "#chat_content_container > *", multiple = TRUE, immediate = TRUE)
    
    values$messages <- chat_to_load$messages %||% list()
    # Geri yüklenen sohbetlerde kullanıcı başlığı/avatarı doğru görünsün diye
    # kimlik bağlamından gelen user_config'i settings içine enjekte et.
    if (is.null(settings_data$user_config)) {
      session_user_config <- resolve_user_config(default = NULL)

      if (!is.null(session_user_config)) {
        settings_data$user_config <- session_user_config
      }
    }
	
    effective_user_id <- resolve_current_user_id()
    all_feedback <- load_feedback_from_db(effective_user_id)
    values$liked_messages <- all_feedback$liked
    values$disliked_messages <- all_feedback$disliked
    # Faz 6 (§5.10): başka bir sohbete geçildiğinde, sonucu ZATEN atılacak bir
    # PK işçisi DB bağlantısını ve işçi yuvasını doğal bitişine kadar tutmaya
    # devam ederdi. Terk edilen istekler burada iptal edilir.
    #
    # YALNIZCA KİMLİK GERÇEKTEN DEĞİŞİYORSA (PR #703 incelemesi): `do_load_chat()`
    # kullanıcı ZATEN AÇIK olan kayıtlı sohbete yeniden tıkladığında da çalışır.
    # O durumda istek hâlâ AYNI sohbete aittir; koşulsuz terk etmek, geçerli ve
    # uçuştaki bir PK analizini yalnızca liste öğesine tekrar tıklandığı için
    # iptal ederdi. A -> B -> A gezinmesindeki bayat-geri-çağrı koruması
    # KORUNUR: orada hedef kimlik gerçekten değişir.
    onceki_chat_id <- tryCatch(shiny::isolate(values$current_chat_id), error = function(e) NULL)
    hedef_degisti <- !identical(as.character(onceki_chat_id %||% "")[1],
                                as.character(chat_id %||% "")[1])

    values$current_chat_id <- chat_id
    values$show_welcome <- FALSE

    if (isTRUE(hedef_degisti) &&
        exists("mergen_pk_abandon_active_requests", mode = "function", inherits = TRUE)) {
      try(mergen_pk_abandon_active_requests(session, release = FALSE), silent = TRUE)
    }

    # D11 devralınan varlık bağlamı SOHBETE aittir. Aynı gerekçeyle yalnızca
    # kimlik GERÇEKTEN değiştiğinde düşürülür; aynı sohbete yeniden tıklamak
    # geçerli bir devam bağlamını silmemelidir.
    if (isTRUE(hedef_degisti) &&
        exists("pk_entity_context_clear", mode = "function", inherits = TRUE)) {
      try(pk_entity_context_clear(session), silent = TRUE)
    }

    # Mesaj içeriğinden aktif aracı tespit et ve etkinleştir
    # Görsel Uzmanı tespiti güvenilir çalışıyor (görsel yanıtlar belirgin işaretçiler içerir).
    # Diğer araçlar için içerik tabanlı tespit yapılır; eşleşme yoksa araç durumu değiştirilmez.
    detected_tool <- NULL
    for (m in values$messages) {
      if (m$type %||% "" %in% c("ai", "assistant")) {
        msg_content <- m$content %||% ""
        msg_html    <- m$html_content %||% ""
        combined_text <- paste(msg_content, msg_html)

        # Görsel araç tespiti (en güvenilir - galeri yaklaşımıyla uyumlu)
        if (grepl("\\[GORSEL|\\[GÖRSEL|generated-image|image_gen_|dall-e|gorsel-sonuc",
                  combined_text, ignore.case = TRUE, perl = TRUE)) {
          detected_tool <- "enable_image_tools"
          break
        }
        # Süreç yönetimi araç tespiti
        if (grepl("source-link|kaynakca-entry", combined_text, perl = TRUE)) {
          detected_tool <- "enable_process_tools"
          break
        }
      }
    }

    if (!is.null(detected_tool)) {
      # Tüm analiz araçlarını devre dışı bırak
      analysis_tools <- c(
        "enable_rdata_tools", "enable_mcp_tools", "enable_summarization_tools",
        "enable_coding_tools", "enable_process_tools", "enable_app_expert_tools",
        "enable_image_tools"
      )
      for (tool in analysis_tools) {
        isolate({ settings_data[[tool]] <- FALSE })
        updateCheckboxInput(session, paste0("settings_yapilandirma_module-", tool), value = FALSE)
      }
      # Tespit edilen aracı etkinleştir
      isolate({ settings_data[[detected_tool]] <- TRUE })
      updateCheckboxInput(session, paste0("settings_yapilandirma_module-", detected_tool), value = TRUE)

      # İstemci tarafını bilgilendir
      session$sendCustomMessage("saveSettings", stats::setNames(
        as.list(vapply(analysis_tools, function(t) identical(t, detected_tool), logical(1))),
        analysis_tools
      ))

      # Görsel modu için ek UI güncellemeleri (galeri yaklaşımıyla aynı)
      if (identical(detected_tool, "enable_image_tools")) {
        session$sendCustomMessage("toggleImageMode", list(active = TRUE))
        image_model <- Sys.getenv("IMAGE_GEN_MODEL", "dall-e-3")
        isolate({ settings_data$model_selection <- image_model })
      }

      cat(sprintf("[SAVED_CHATS] Araç tespit edildi ve etkinleştirildi: %s\n", detected_tool))
    }

    # Süreç Yönetimi / Uygulama Uzmanı (panelsiz Langflow araçları) model kilidi
    # ve akış seçici, araç bayraklarından bağımsız UI/kilit sinyalleridir ve önceki
    # sohbetten devralınabilir. İçerik tabanlı tespit YALNIZCA Görsel çıktıyı ve
    # Süreç atıf işaretçilerini (source-link|kaynakca-entry) tanır; Uygulama Uzmanı
    # güvenilir tespit edilemez, bu yüzden detected_tool == NULL "belirsiz" demektir
    # ve mevcut araç durumu KORUNUR.
    #
    # Kurallar (bayrakları burada ASLA temizlemeyiz; yalnızca UI'yı mevcut/tespit
    # edilen duruma göre tutarlı kılarız):
    #  - Süreç POZİTİF tespit edildiyse: akış seçiciyi göster + sunucu kilidi.
    #  - Süreç DIŞI bir araç POZİTİF tespit edildiyse (yukarıdaki blok tüm bayrakları
    #    temizleyip o aracı etkinleştirdi): panelsiz Langflow UI'sını temizle.
    #  - Belirsizse (hiç tespit yok) ama panelsiz bir Langflow aracı hâlâ aktifse:
    #    bayrağı KORU ve UI'yı ona göre tutarlı kıl. Böylece tespit edilemeyen bir
    #    Uygulama Uzmanı/Süreç sohbeti sessizce yerel LLM'e düşmez (UI ile
    #    yönlendirme uyumsuzluğu da oluşmaz).
    #  - Belirsiz ve aktif panelsiz Langflow aracı yoksa: UI'yı temizle.
    langflow_flags <- if (exists("mergen_langflow_setting_flags", mode = "function")) {
      mergen_langflow_setting_flags()
    } else {
      c("enable_process_tools", "enable_app_expert_tools")
    }
    lf_active_flags <- Filter(function(f) isTRUE(isolate(settings_data[[f]])), langflow_flags)

    ui_lf_flag <- if (identical(detected_tool, "enable_process_tools")) {
      "enable_process_tools"
    } else if (!is.null(detected_tool)) {
      NULL
    } else if (length(lf_active_flags) > 0) {
      lf_active_flags[[1]]
    } else {
      NULL
    }

    if (is.null(ui_lf_flag)) {
      session$sendCustomMessage("toggleProcessMode", list(active = FALSE))
      session$sendCustomMessage("setToolModelLock", list(active = FALSE))
    } else {
      lf_label <- "Bu araç"
      if (exists("get_tool_mode_config", mode = "function")) {
        lf_cfg <- get_tool_mode_config(ui_lf_flag, by = "setting_flag")
        lf_label <- lf_cfg$title %||% "Bu araç"
      }
      session$sendCustomMessage("setToolModelLock", list(active = TRUE, label = lf_label))
      # Akış seçici yalnızca Süreç Yönetimi için görünür; Uygulama Uzmanı akış
      # seçici kullanmaz. GLOBAL process_flow_selection kasıtlı olarak seçiciye
      # ZORLANMAZ: kayıtlı sohbetin kendi akışı akış başına kalıcı saklanmadığından
      # global son-kullanılan tercihi farklı bir sohbete uygulamak yanlış akışa
      # taşırdı (session_id akış kimliğini içerir). DOM seçici yükleme sırasında
      # zaten kalıcı seçime hizalanmıştır.
      session$sendCustomMessage("toggleProcessMode", list(
        active = identical(ui_lf_flag, "enable_process_tools")
      ))
    }

    # Persona verisini al (eski kimlikler normalleştirilerek çözülür)
    character_data <- get_character_record(isolate(settings_data$selected_character))

    # Mesajları UI'ya ekle
    for (i in seq_along(values$messages)) {
      msg <- values$messages[[i]]
      is_last_user_msg <- (msg$type == "user" && i == length(values$messages))
      
      ui_to_insert <- render_message_bubble_ui(
        msg, settings_data,
        is_last_user_message = is_last_user_msg,
        character_data = character_data,
        liked_ids = values$liked_messages,
        disliked_ids = values$disliked_messages
      )
      
      insertUI(selector = "#chat_content_container", where = "beforeEnd", ui = ui_to_insert)
      
      # Kod bloklarını initialize et (local ile closure sorununu önle)
      wrapper_id <- paste0("message_wrapper_", msg$id)
      if (isTRUE(msg$has_code)) {
        local({
          wid <- wrapper_id
          shinyjs::runjs(sprintf("
            setTimeout(function() {
              if (typeof window.initializeCodeMirrorInElement === 'function') {
                window.initializeCodeMirrorInElement('%s');
              }
            }, 200);
          ", wid))
        })
      }
    }

    # Tüm mesajlar eklendikten sonra grafikleri toplu olarak render et
    # 1) İstemci tarafında Highcharts ile statik grafikleri çiz (yeniden deneme mekanizmalı)
    shinyjs::runjs("
      setTimeout(function() {
        if (typeof window.renderSavedCharts === 'function') {
          window.renderSavedCharts('chat_content_container');
        }
      }, 600);
    ")
    # 2) Plotly/Highcharter çıktı bağlamalarını yeniden kur (sunucu taraflı grafikler)
    chat_rebind_all_charts(session, output, values$messages)

    # UÇUŞTAKİ PK İSTEĞİNİN İLERLEME PANELİ GERİ KONUR.
    #
    # Yukarıdaki yeniden yükleme yolu `#chat_content_container` içeriğini
    # KOŞULSUZ boşaltır; uçuştaki isteğin düşünme/yazıyor sarmalayıcısı da o
    # kapsayıcıda yaşar. Kullanıcı ZATEN AÇIK sohbete yeniden tıkladığında istek
    # (haklı olarak) terk edilmediği için `values$is_sending` / `values$typing`
    # TRUE kalıyor, yeni mesaj "önceki isteği bekleyin" ile reddediliyor ama
    # ekranda hiçbir ilerleme göstergesi kalmıyordu. Sarmalayıcı mesaj balonları
    # basıldıktan SONRA yeniden eklenir.
    # HER İKİ BAYRAK DA ETKİN İSTEK SAYILIR. Yeniden yükleme yolu
    # `#chat_content_container` içeriğini `values$is_sending` VEYA
    # `values$typing` için temizler, ama bu kapı yalnızca ilkine bakıyordu;
    # `R/server_observers_chat_input.R` ile `send_message()` ise ikisini de
    # etkin istek sayar. Ertelenmiş bir PK gönderimi `is_sending` bayrağını
    # sıfırlayıp `typing` bayrağını TRUE bırakırsa, kullanıcı açık söyleşiye
    # yeniden tıkladığında hiçbir ilerleme göstergesi kalmıyor ama girdi
    # BLOKLU kalıyordu.
    if (!isTRUE(hedef_degisti) &&
        (isTRUE(shiny::isolate(values$is_sending)) ||
         isTRUE(shiny::isolate(values$typing))) &&
        exists("mergen_show_send_message_thinking_wrapper", mode = "function",
               inherits = TRUE)) {
      ucustaki_id <- tryCatch(shiny::isolate(values$backpressure_request_id),
                              error = function(e) NULL)
      try(mergen_show_send_message_thinking_wrapper(
        session,
        list(show_thinking_wrapper = TRUE,
             panel_model_id = shiny::isolate(settings_data$model_selection),
             classic_indicator_requested = FALSE,
             panel_simulated = TRUE),
        request_id = ucustaki_id
      ), silent = TRUE)
    }

    # Uzun söyleşi geçmişlerinde içerik/kartlar geç render olabildiği için
    # birkaç kez dip kaydırma denemesi yap.
    shinyjs::runjs("
      (function() {
        var attempts = 0;
        var maxAttempts = 6;
        var timer = setInterval(function() {
          attempts += 1;
          if (typeof window.scrollToBottom === 'function') {
            window.scrollToBottom(false);
          }
          if (attempts >= maxAttempts) {
            clearInterval(timer);
          }
        }, 180);
      })();
    ")
    
    updateTabItems(session, "tabs", "chat")
    # Sekme geçişinden hemen sonra bir kez daha dip kaydır.
    shinyjs::delay(120, {
      shinyjs::runjs("if (typeof window.scrollToBottom === 'function') window.scrollToBottom(false);")
    })
    # Başarı toast'ı, son mesaj balonu DOM'da GERÇEKTEN görünene dek bekletilir;
    # içerik ekranda belirmeden "yüklendi" denmez.
    son_mesaj_id <- if (length(values$messages) > 0) {
      values$messages[[length(values$messages)]]$id
    } else {
      NULL
    }
    mergen_show_chat_loaded_toast(session, chat_to_load$title, son_mesaj_id)
    cat(sprintf(
      "[CHAT PERF] Kayıtlı söyleşi yüklendi - chat_id=%s, mesaj=%d, %.0f ms\n",
      chat_id, length(values$messages),
      as.numeric(difftime(Sys.time(), yukleme_baslangici, units = "secs")) * 1000
    ))
    
    # Kilidi kısa bir gecikmeyle serbest bırak. SAHİPLİK BURADA DEVREDİLİR:
    # `on.exit()` güvenlik ağı artık devreye girmez.
    # SAHİPLİK YALNIZCA GERİ ÇAĞRI GERÇEKTEN KURULDUKTAN SONRA DEVREDİLİR: `shinyjs::delay()` (ör. websocket kapanırken) düşerse bayrak ZATEN `TRUE` olduğu için `on.exit()` güvenlik ağı kilidi bırakmıyor, `load_chat_in_progress` `TRUE` kalıyor ve sonraki HER söyleşi seçimi erken dönüyordu.
    shinyjs::delay(500, {
      load_chat_in_progress(FALSE)
    })
    basarili <- TRUE
  }
  
  # -------------------------------------------------------------------------
  # Sohbet Yükleme Observer'ları
  # -------------------------------------------------------------------------
  
  # Karşılama ekranından doğrudan gelen sohbet yükleme isteği
  # (eventReactive zincirini atlayarak ilk tıklama sorununu önler)
  observeEvent(input$welcome_load_chat_id, {
    do_load_chat(input$welcome_load_chat_id)
  }, ignoreInit = TRUE)
  
  # Kayıtlı Söyleşiler sayfasından gelen sohbet yükleme isteği (mevcut modül zinciri)
  observeEvent(saved_chats_data$load_chat_id(), {
    do_load_chat(saved_chats_data$load_chat_id())
  }, ignoreInit = TRUE)
  
  # -------------------------------------------------------------------------
  # Sohbet Silme ve Temizleme
  # -------------------------------------------------------------------------
  
  # Sohbet silme observer'ı
  observeEvent(saved_chats_data$delete_chat_id(), {
    chat_id <- saved_chats_data$delete_chat_id()
    req(chat_id)
    
    # Silinen sohbeti işaretle (yanlış yüklemeyi engellemek için)
    last_deleted_chat_id(chat_id)
    
    cat(sprintf("[SAVED_CHATS] Sohbet siliniyor: %s\n", chat_id))
    
    # Mevcut sohbet mi siliniyor kontrol et
    current_chat_deleted <- identical(as.character(values$current_chat_id), as.character(chat_id))
    
    effective_user_id <- resolve_current_user_id()
    if (is.na(effective_user_id) || effective_user_id <= 0) {
      showToast(session, "Kullanıcı oturumu henüz hazır değil. Lütfen tekrar deneyin.", "warning")
      return()
    }

    delete_chat_from_db(chat_id, effective_user_id)
    
    values$saved_chats <- load_chats_from_db(effective_user_id, include_messages = FALSE)
    saved_chats_data$refresh()
    
    # Eğer mevcut sohbet silindiyse, Ana Söyleşi sayfasını sıfırla
    if (current_chat_deleted) {
      cat("[SAVED_CHATS] Mevcut sohbet silindi, welcome ekranına dönülüyor\n")

      # ETKİN PK İSTEĞİ ÖNCE TERK EDİLİR. Sohbet silindiğinde isteğin sahibi
      # ortadan kalkar; işçi ve gönderme durumu ETKİN kalırsa geç dönen sonuç
      # ARTIK BAŞKA bir sohbete uygulanmaya çalışılır ve gönder düğmesi
      # DURDURMA kipinde kilitli kalırdı.
      if (exists("mergen_pk_abandon_active_requests", mode = "function", inherits = TRUE)) {
        try(mergen_pk_abandon_active_requests(session, release = FALSE), silent = TRUE)
      }

      # Sohbet durumunu sıfırla
      values$messages <- list()
      values$current_chat_id <- NULL
      values$show_welcome <- TRUE
      
      # Eski animasyonları temizle
      shinyjs::runjs("
        if(window.WelcomeVideoPlayer && window.WelcomeVideoPlayer.destroy) {
          window.WelcomeVideoPlayer.destroy();
        }
        if(window.WelcomeNeuralNetwork && window.WelcomeNeuralNetwork.destroy) {
          window.WelcomeNeuralNetwork.destroy();
        }
		if(window.WelcomeGreeting && window.WelcomeGreeting.destroy) {
          window.WelcomeGreeting.destroy();
        }
        if(window.WelcomePersonalGreeting && window.WelcomePersonalGreeting.destroy) {
          window.WelcomePersonalGreeting.destroy();
        }
        
        // Mevcut sohbet içeriğini temizle
        $('#chat_content_container').empty().hide();
        
        // Welcome container'ı hazırla
        $('#welcome_fullscreen_container').empty().removeClass('hidden').show();
      ")
      
      removeUI(selector = "#chat_content_container > *", multiple = TRUE, immediate = TRUE)
      removeUI(selector = "#welcome_fullscreen_container > *", multiple = TRUE, immediate = TRUE)
      
      # Welcome ekranını yeniden render et ve animasyonları başlat
      shinyjs::delay(150, {
        # Welcome ekranı UI'ını ekle
        insertUI(
          selector = "#welcome_fullscreen_container",
          where = "beforeEnd",
          ui = createWelcomeScreen(values$saved_chats),
          immediate = TRUE
        )
        
        # Animasyonları başlat
        shinyjs::delay(100, {
          session$sendCustomMessage("initModernWelcome", list())
          
          # Kişiselleştirilmiş karşılama animasyonunu başlat
          shinyjs::delay(400, {
            session$sendCustomMessage("initPersonalGreeting", list(
              first_name = resolve_user_first_name(default = "")
            ))
          })
        })
      })
    }
  }, ignoreInit = TRUE)
  
  # Tüm sohbetleri temizleme observer'ı
  observeEvent(saved_chats_data$clear_all_chats_trigger(), {
    if (saved_chats_data$clear_all_chats_trigger() > 0) {
      effective_user_id <- resolve_current_user_id()
      if (is.na(effective_user_id) || effective_user_id <= 0) {
        showToast(session, "Kullanıcı oturumu henüz hazır değil. Lütfen tekrar deneyin.", "warning")
        return()
      }

      clear_all_chats_from_db(effective_user_id)
      values$saved_chats <- list()
      saved_chats_data$refresh()
      showToast(session, "Tüm söyleşiler temizlendi.", "warning")
      
      # Mevcut sohbet varsa, Ana Söyleşi sayfasını sıfırla (tek silme ile aynı akış)
      if (!is.null(values$current_chat_id) || length(values$messages) > 0) {
        cat("[SAVED_CHATS] Tüm söyleşiler silindi, welcome ekranına dönülüyor\n")

        # ETKİN PK İSTEĞİ ÖNCE TERK EDİLİR (tek silme ile AYNI sözleşme).
        if (exists("mergen_pk_abandon_active_requests", mode = "function", inherits = TRUE)) {
          try(mergen_pk_abandon_active_requests(session, release = FALSE), silent = TRUE)
        }

        # Sohbet durumunu sıfırla
        values$messages <- list()
        values$current_chat_id <- NULL
        values$show_welcome <- TRUE
        
        # Eski animasyonları temizle
        shinyjs::runjs("
          if(window.WelcomeVideoPlayer && window.WelcomeVideoPlayer.destroy) {
            window.WelcomeVideoPlayer.destroy();
          }
          if(window.WelcomeNeuralNetwork && window.WelcomeNeuralNetwork.destroy) {
            window.WelcomeNeuralNetwork.destroy();
          }
		  if(window.WelcomeGreeting && window.WelcomeGreeting.destroy) {
            window.WelcomeGreeting.destroy();
          }
          if(window.WelcomePersonalGreeting && window.WelcomePersonalGreeting.destroy) {
            window.WelcomePersonalGreeting.destroy();
          }
          
          // Mevcut sohbet içeriğini temizle
          $('#chat_content_container').empty().hide();
          
          // Welcome container'ı hazırla
          $('#welcome_fullscreen_container').empty().removeClass('hidden').show();
        ")
        
        removeUI(selector = "#chat_content_container > *", multiple = TRUE, immediate = TRUE)
        removeUI(selector = "#welcome_fullscreen_container > *", multiple = TRUE, immediate = TRUE)
        
        # Welcome ekranını yeniden render et ve animasyonları başlat (boş liste ile)
        shinyjs::delay(150, {
          insertUI(
            selector = "#welcome_fullscreen_container",
            where = "beforeEnd",
            ui = createWelcomeScreen(list()),  # Boş liste - tüm sohbetler silindi
            immediate = TRUE
          )
          
          # Animasyonları başlat
          shinyjs::delay(100, {
            session$sendCustomMessage("initModernWelcome", list())
            
            # Kişiselleştirilmiş karşılama animasyonunu başlat
            shinyjs::delay(400, {
				session$sendCustomMessage("initPersonalGreeting", list(
				  first_name = resolve_user_first_name(default = "")
				))
            })
          })
        })
      }
    }
  }, ignoreInit = TRUE)
  
  invisible(NULL)
}