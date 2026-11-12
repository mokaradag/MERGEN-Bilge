# R/server_observers_chat_input.R
# Dosya Yolu: R/server_observers_chat_input.R
# Açıklama: Ana sohbet giriş alanı observer'ları.
# Mesaj gönderme, durdurma butonu, dosya yükleme, sesli giriş ve STT entegrasyonu burada işlenir.

#' Sohbet Giriş Gözlemcilerini Başlat
#' @description Ana sohbet giriş alanı observer'larını kurar
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param values Ana reaktif değerler
#' @param settings_data Ayarlar modülünden dönen reaktif ayarlar
#' @param stop_generation Durdurma sinyali reaktif değeri
#' @param active_request_id Aktif istek ID reaktif değeri
#' @param reset_chat_state Sohbet durumunu sıfırlama fonksiyonu
#' @param send_message Mesaj gönderme fonksiyonu
#' @param current_user_id Mevcut kullanıcı ID'si veya bunu döndüren provider fonksiyonu
#' @param file_manager_data Dosya yöneticisi modül verisi
#' @param session_files Oturum dosyaları reaktif değeri
#' @param file_to_add Dosya ekleme reaktif değeri
#' @param stt_data STT modül verisi
chatInputObserversInit <- function(input, session, values, settings_data,
                                    stop_generation, active_request_id,
                                    reset_chat_state, send_message,
                                    current_user_id, file_manager_data,
                                    session_files, file_to_add, stt_data) {

  # current_user_id parametresi artık sabit değer veya provider fonksiyonu olabilir.
  # Bu yardımcı her iki durumu da güvenli şekilde çözümler.
  resolve_chat_input_user_id <- function() {
    uid <- resolve_effective_user_id(
      session = session,
      current_user_id = current_user_id
    )
    if (is.na(uid)) uid <- 0L
    uid
  }

  observeEvent(input$send_stop_btn, {
    session$sendCustomMessage("stopTTSPlayback", list(reason = "stop_button"))

    if (isTRUE(values$is_sending) || isTRUE(values$typing)) {
      cat("[STOP_BUTTON] Kullanıcı durdurma istedi\n")

      # Faz 6 (§5.10): İPTAL İŞÇİYE ULAŞMALIDIR. Geri çağrıyı atmak (aşağıdaki
      # active_request_id değişimi) işçiyi ÇALIŞMAYA DEVAM ETTİRİR; DB
      # bağlantısını ve işçi yuvasını tutar. Jeton artık OTURUM + istek kimliği
      # ile adlandırılır; başka bir oturumun aynı request_1 sayacına dokunamaz.
      #
      # Jeton YALNIZCA gerçekten bir PK isteği sahipse yazılır. Bu gözlemci her
      # gönderen/yazan istek için çalışır; normal sohbet/görsel isteklerinde
      # jetonun sahibi olan bir dağıtıcı YOKTUR ve hiçbir tamamlanma yolu onu
      # temizlemez — art arda durdurmalar süreç ömrü boyunca birer dosya
      # sızdırırdı.
      if (exists("mergen_pk_signal_cancel", mode = "function", inherits = TRUE) &&
          exists("mergen_pk_request_has_cancel_token", mode = "function", inherits = TRUE)) {
        aktif_kimlik <- isolate(active_request_id())
        # ARAMA HATASI TÜM DURDURMA AKIŞINI KİLİTLEMEZ. Yüklem sarmalanmamıştı;
        # hata yükseltirse gözlemci `stop_generation(TRUE)` ve istek kimliği
        # döndürmesine ULAŞMADAN düşüyor ve Durdur düğmesi o tıklamada ölü
        # görünüyordu — PK olmayan istekler dâhil.
        sahip_mi <- tryCatch(
          isTRUE(mergen_pk_request_has_cancel_token(session, aktif_kimlik)),
          error = function(e) FALSE
        )
        if (isTRUE(sahip_mi)) {
          try(mergen_pk_signal_cancel(aktif_kimlik, session = session), silent = TRUE)
        }
      }

      stop_generation(TRUE)
      active_request_id(paste0("cancelled_", as.numeric(Sys.time())))
    }
  }, ignoreInit = TRUE)

  # İstemcinin iyimser (bekleyen) balonu yalnızca sunumdur; kabul/ret kararı
  # burada verilir. Sonuç, işleyicinin HER çıkış yolunda (erken ret, hata,
  # normal dönüş) tam bir kez bildirilir. Kabul ölçütü bu çağrının kullanıcı
  # mesajını gerçekten eklemesidir: mesaj eklendikten sonraki bir hata "ret"
  # sayılmaz (aksi halde istemci metni geri yükler ve yeniden gönderim mesajı
  # çoğaltır). Kabulde eklenen mesajın kimliği döner; istemci bekleyen balonu
  # metinle değil bu kimlikle eşler.
  # Aynı istemci kimliğiyle yeniden teslim edilen istem ikinci kez işlenmez;
  # ilk sonucu yeniden bildirilir. Oturum kapsamlı ve sınırlıdır (son 32 kimlik).
  islenen_istemler <- list()
  istemi_isle <- function(istem) {
    istem_kimligi <- as.character(istem$client_id %||% "")[1]
    if (is.na(istem_kimligi) || !grepl("^[A-Za-z0-9_-]{1,64}$", istem_kimligi)) istem_kimligi <- ""
    if (nzchar(istem_kimligi) && istem_kimligi %in% names(islenen_istemler)) {
      try(session$sendCustomMessage("mergenIstemSonucu", islenen_istemler[[istem_kimligi]]), silent = TRUE)
      return(invisible(NULL))
    }
    kimlik <- function(m) as.character(m$id %||% "")[1]
    onceki <- isolate(values$messages)
    onceki_kimlikler <- vapply(onceki, kimlik, character(1))
    on.exit(if (nzchar(istem_kimligi)) {
      simdiki <- isolate(values$messages)
      # Kimlik tabanlı tespit; kimliksiz mesajlarda (eski/sahte yollar) konuma düşülür.
      eklenen <- Filter(function(m) identical(m$type, "user") && nzchar(kimlik(m)) &&
                          !(kimlik(m) %in% onceki_kimlikler), simdiki)
      if (!length(eklenen) && length(simdiki) > length(onceki)) {
        eklenen <- Filter(function(m) identical(m$type, "user") && !nzchar(kimlik(m)),
                          simdiki[seq.int(length(onceki) + 1L, length(simdiki))])
      }
      sonuc <- list(client_id = istem_kimligi, durum = if (length(eklenen)) "kabul" else "ret")
      if (length(eklenen)) sonuc$mesaj_id <- as.character(eklenen[[length(eklenen)]]$id %||% "")[1]
      islenen_istemler[[istem_kimligi]] <<- sonuc
      if (length(islenen_istemler) > 32L) islenen_istemler <<- utils::tail(islenen_istemler, 32L)
      try(session$sendCustomMessage("mergenIstemSonucu", sonuc), silent = TRUE)
    }, add = TRUE)

    if (!check_rate_limit(resolve_chat_input_user_id())) {
      showToast(session, "Çok fazla istek gönderdiniz. Lütfen biraz bekleyin.", "warning")
      return(invisible(NULL))
    }

    global_check <- check_global_rate_limit()
    if (!global_check$allowed) {
      showToast(session, global_check$message, "warning")
      return(invisible(NULL))
    }

    # Sınır kırpılmamış ham metne uygulanır: boşlukla şişirilmiş girdi sınırı
    # aşamaz; send_message aynı doğrulanmış tek değeri alır.
    ham_metin <- as.character(istem$text %||% "")[1]
    if (is.na(ham_metin)) ham_metin <- ""
    if (nchar(ham_metin) > 20000) {
      showToast(session, "Mesaj çok uzun. Lütfen 20.000 karakterle sınırlayın.", "warning")
      return(invisible(NULL))
    }

    # Kullanıcı gerçek bir prompt gönderdiğinde araç bağlamlı arka plan
    # animasyonu temizlenir. Animasyonlar yalnızca hızlı eylem tanıtım
    # mesajı görünürken (henüz prompt gönderilmemişken) gösterilmelidir.
    # Bu sunucu otoriter sinyaldir; tool_backgrounds.js bunu alır almaz
    # snippet/heptagon katmanlarını gizler.
    tryCatch(
      session$sendCustomMessage("setToolBackgroundFamily", list(
        clear = TRUE,
        reason = "user_prompt"
      )),
      error = function(e) invisible(NULL)
    )

    send_message(ham_metin)
    invisible(NULL)
  }

  observeEvent(input$send_prompt_from_js, {
    req(input$send_prompt_from_js)
    istemi_isle(input$send_prompt_from_js)
  })

  observeEvent(stop_generation(), {
    if (isTRUE(stop_generation()) && (isTRUE(values$is_sending) || isTRUE(values$typing))) {
      reset_chat_state()
      showToast(session, "Yanıt oluşturma durduruldu.", "warning")
    }
  }, ignoreInit = TRUE)

  observeEvent(input$file_upload, {
    req(input$file_upload)
    # Yalnızca Shiny'nin bu oturuma verdiği yükleme kaynakları alınır.
    yuklemeler <- file_ingestion_session_uploads(input$file_upload, session)
    req(nrow(yuklemeler) > 0L)
    handle_file_upload_batch(
      uploads_df             = yuklemeler,
      current_user_id        = resolve_chat_input_user_id(),
      session                = session,
      settings_data          = settings_data,
      file_manager_data      = file_manager_data,
      session_files_reactive = session_files,
      file_to_add_reactive   = file_to_add
    )
  }, ignoreInit = TRUE)

  observeEvent(input$voice_btn, {
    stt_data$start_session()
  }, ignoreInit = TRUE)

  observeEvent(stt_data$final_text(), {
    txt <- stt_data$final_text()
    if (nzchar(txt)) {
      send_message(txt)
    }
  })

  invisible(NULL)
}
