# ==============================================================================
# Faz 6: PK async ana-süreç gönderim ve callback yaşam döngüsü.
# ==============================================================================

# NOT: derin gözlemci fabrika-kapsamı sarmalayıcısı ARTIK BURADA DEĞİLDİR.
# `R/helpers_pk_worker_observers.R` içine taşındı; böylece (a) temiz bir PSOCK
# işçisi de aynı kapsamı alır ve (b) sarmalayıcı yeniden source'a karşı
# IDEMPOTENT'tir (burada her yüklemede zincir büyüyordu).

mergen_pk_analysis_execute <- function(ctx) {
  stopped <- try(ctx$stop_generation(), silent = TRUE)
  if (!inherits(stopped, "try-error") && isTRUE(stopped)) return(list(action = "stop"))

  # Bu fonksiyon YALNIZCA PK istekleri için çalışır: jeton sahipliği burada
  # kaydedilir ki Durdur gözlemcisi PK olmayan isteklerde boşuna `.flag`
  # dosyası oluşturmasın (senkron yol da iptal jetonunu kullanır).
  try(mergen_pk_register_cancel_token(ctx$session, ctx$req_id), silent = TRUE)

  # Yapılandırma sözleşmesi sorgu metadata'sına EN YÜKSEK önceliği verir.
  # Yönlendirme kararı `NULL` metadata ile alınırsa, `async = FALSE` işaretli
  # bir üretim sorgusu global bayrak açıkken yine işçiye gönderilirdi.
  aktif_meta <- tryCatch(pk_active_query_meta(), error = function(e) NULL)
  uygun <- pk_async_available(aktif_meta)
  if (!isTRUE(uygun$available)) {
    if (!identical(uygun$reason, "flag_off")) {
      log_info(sprintf("[PK_ASYNC] Async yok (%s); senkron yol.", uygun$reason))
    }
    return(mergen_pk_apply_analysis_result(mergen_pk_run_sync(ctx), ctx$messages_to_process))
  }

  hazirlik <- mergen_pk_prepare_async_request(ctx)
  if (!isTRUE(hazirlik$ok)) {
    if (isTRUE(hazirlik$fallback_sync)) {
      return(mergen_pk_apply_analysis_result(mergen_pk_run_sync(ctx), ctx$messages_to_process))
    }
    return(list(action = "answer", answer = hazirlik$answer, chips = list()))
  }
  mergen_pk_dispatch_async(ctx, hazirlik$request, hazirlik$cancel_token)
}

mergen_pk_dispatch_async <- function(ctx, request, cancel_token) {
  req_id <- as.character(ctx$req_id %||% "")[1]
  mesajlar <- ctx$messages_to_process
  oturum <- ctx$session

  # Kaydedilmemiş sohbetler için `NULL` TEK bir sentinel'e katlanıyordu; bu
  # yüzden "kaydedilmemiş sohbet A" ile "Yeni Sohbet'ten sonraki kaydedilmemiş
  # sohbet B" ayırt EDİLEMİYORDU ve eski işçi sonucu taze sohbete düşebiliyordu.
  # Kaydedilmemiş sohbet artık oturum-yerel bir NESİL sayacıyla etiketlenir.
  kaynak_chat_key <- mergen_pk_chat_identity(oturum, ctx$values)

  request_done <- FALSE
  session_ended <- FALSE

  butce_birak <- function() {
    try(shiny::isolate(
      mergen_send_message_release_values_token(ctx$values, req_id = req_id)
    ), silent = TRUE)
  }

  # onSessionEnded YALNIZCA jetonu işaretlemez. Future zaten tamamlanmışsa
  # jeton geç kalır; bu yüzden ayrıca bir "oturum kapandı" durumu kaydedilir ve
  # sonraki her geri çağrı korumayı GEÇEMEZ. Ayrıca istek kapsamlı backpressure
  # yuvası burada bırakılır: aksi hâlde bir kopma fırtınası, sağlıklı
  # oturumlara dakikalarca "sunucu meşgul" döndürebilirdi.
  kayit <- try({
    oturum$onSessionEnded(function() {
      session_ended <<- TRUE
      if (!isTRUE(request_done)) {
        pk_cancel_token_signal(cancel_token)
        butce_birak()
      }
    })
    TRUE
  }, silent = TRUE)
  if (!identical(kayit, TRUE)) log_info("[PK_ASYNC] onSessionEnded iptal kaydi yapilamadi.")

  # continuation ve message insertion alt çağrıları da reactive okuyabildiği için
  # callback'teki tüm gövde isolate edilir.
  devam_et <- function(uygulama) shiny::isolate({
    if (identical(uygulama$action, "answer")) {
      ctx$cleanup_send_message()
      ctx$add_message_fn(uygulama$answer, "ai")
      if (exists("mergen_pk_emit_chips", mode = "function", inherits = TRUE)) {
        try(mergen_pk_emit_chips(ctx, uygulama$chips), silent = TRUE)
      }
      return(invisible(NULL))
    }
    ctx$continue_fn(uygulama$messages_to_process, uygulama$max_output_tokens)
  })

  koruma_gecti <- function(etiket, result = NULL) {
    if (isTRUE(session_ended)) {
      log_info(sprintf("[PK_ASYNC] Callback yok sayildi (%s, sebep=session_ended).", etiket))
      request_done <<- TRUE
      pk_cancel_token_clear(cancel_token)
      try(mergen_pk_cleanup_worker_artifact(result), silent = TRUE)
      butce_birak()
      return(FALSE)
    }

    aktif <- try(shiny::isolate(ctx$active_request_id()), silent = TRUE)
    if (inherits(aktif, "try-error")) aktif <- NULL
    stopped <- try(shiny::isolate(ctx$stop_generation()), silent = TRUE)
    stopped <- !inherits(stopped, "try-error") && isTRUE(stopped)
    karar <- pk_async_should_apply(aktif, req_id, stopped = stopped)

    simdiki <- mergen_pk_chat_identity(oturum, ctx$values)
    ayni_chat <- identical(simdiki, kaynak_chat_key)
    if (isTRUE(karar$apply) && isTRUE(ayni_chat)) return(TRUE)

    sebep <- if (!isTRUE(karar$apply)) karar$reason else "chat_changed"
    log_info(sprintf("[PK_ASYNC] Callback yok sayildi (%s, sebep=%s).", etiket, sebep))
    request_done <<- TRUE
    pk_cancel_token_clear(cancel_token)
    try(mergen_pk_cleanup_worker_artifact(result), silent = TRUE)
    butce_birak()

    # SOHBET DEĞİŞTİ ama istek kimliği HÂLÂ BU İSTEK: kullanıcı yeni bir istek
    # başlatmadı, yalnızca gezindi. Gönderim durumu (`is_sending`) burada
    # temizlenmezse yeni sohbet eski isteğin durdur/gönder kilidinde takılı
    # kalırdı. Gerçekten BAYAT kimlikler için davranış değişmez (no-op).
    if (isTRUE(karar$apply) && !isTRUE(ayni_chat)) {
      try(shiny::isolate(ctx$cleanup_send_message()), silent = TRUE)
    }
    FALSE
  }

  # Senkron yedeğe düşerken ORİJİNAL bütçe korunur. Bootstrap/gönderim hatası
  # zaten süre harcadı; taze bir son tarih vermek toplam duvar saatini ikiye
  # katlar ve olay döngüsünü tam da kaçınılmak istenen süre kadar bloklardı.
  senkron_yedek <- function(etiket) shiny::isolate({
    kalan <- mergen_pk_residual_budget_sec(request)
    if (is.finite(kalan) && kalan <= 0) {
      log_warn(sprintf("[PK_ASYNC] %s: kalan butce yok; senkron yeniden deneme YAPILMADI.", etiket))
      return(list(action = "answer", answer = pk_async_halt_message("deadline"),
                  messages_to_process = mesajlar, chips = list()))
    }
    eski <- getOption("mergen.pk.async.deadline_at", NULL)
    options(mergen.pk.async.deadline_at = mergen_pk_request_deadline_at(request))
    on.exit(options(mergen.pk.async.deadline_at = eski), add = TRUE)
    mergen_pk_apply_analysis_result(mergen_pk_run_sync(ctx), mesajlar)
  })

  session_token <- try(oturum$token, silent = TRUE)
  if (inherits(session_token, "try-error")) session_token <- NULL
  vaat <- try(
    tracked_future_promise(
      task_fn = function() pk_async_run_analysis(request),
      task_type = if (isTRUE(request$deep_thinking)) "pk_deep_analysis" else "pk_analysis",
      session_token = session_token,
      dependency_mode = "explicit",
      globals = c(pk_async_worker_globals(), list(request = request)),
      packages = c("DBI", "jsonlite")
    ),
    silent = TRUE
  )
  if (inherits(vaat, "try-error")) {
    request_done <- TRUE
    log_warn("[PK_ASYNC] Gonderim basarisiz; senkron yol.")
    pk_cancel_token_clear(cancel_token)
    return(senkron_yedek("dispatch_failed"))
  }

  tamamlandi <- promises::then(
    vaat,
    onFulfilled = function(worker_result) {
      if (!isTRUE(koruma_gecti("fulfilled", worker_result$result))) return(invisible(NULL))
      request_done <<- TRUE
      pk_cancel_token_clear(cancel_token)
      durum <- as.character(worker_result$status %||% "error")[1]

      if (identical(durum, "ok")) {
        # `pk_analiz_process_request()` sıradan terminal yanıtları KARAKTER
        # olarak döndürebilir ("eşleşen sorgu yok", yetki/ön koşul mesajları).
        # Artifact/provenance yeniden yazımı YALNIZCA liste sonuçlar içindir;
        # aksi hâlde atomik vektörde `$` ile "invalid for atomic vectors"
        # hatası alınır ve yanıt tamamen kaybolurdu.
        eski_sonuc <- worker_result$result
        if (!is.list(eski_sonuc)) {
          try(pk_async_apply_session_writes(oturum, worker_result$session_writes), silent = TRUE)
          return(devam_et(mergen_pk_apply_analysis_result(eski_sonuc, mesajlar)))
        }

        sunum <- mergen_pk_serve_worker_artifact(eski_sonuc, oturum)
        if (!isTRUE(sunum$ok)) {
          # Servis edilemeyen bir ek, çalışmayan indirme bağlantısı olarak
          # sunulmaz; artifact temizlenir ve durum AÇIKÇA hata olur.
          try(mergen_pk_cleanup_worker_artifact(eski_sonuc), silent = TRUE)
          shiny::isolate({
            ctx$cleanup_send_message()
            ctx$add_message_fn(mergen_pk_worker_outcome_text("export_failed"), "ai")
          })
          return(invisible(NULL))
        }
        sonuc <- sunum$result

        pending <- worker_result$session_writes$pk_provenance_pending
        eski_blok <- as.character(eski_sonuc$pk_answer_block %||% "")[1]
        yeni_blok <- as.character(sonuc$pk_answer_block %||% "")[1]
        if (is.list(pending) && is.character(pending$footer) && length(pending$footer) == 1L &&
            nzchar(eski_blok) && nzchar(yeni_blok) && !identical(eski_blok, yeni_blok) &&
            grepl(eski_blok, pending$footer, fixed = TRUE)) {
          pending$footer <- sub(eski_blok, yeni_blok, pending$footer, fixed = TRUE)
          worker_result$session_writes$pk_provenance_pending <- pending
        }
        try(pk_async_apply_session_writes(oturum, worker_result$session_writes), silent = TRUE)
        return(devam_et(mergen_pk_apply_analysis_result(sonuc, mesajlar)))
      }

      # KABUL EDİLMEYEN sonuçların oturum yazımları UYGULANMAZ. İşçi bu
      # yazımları son kapıdan ÖNCE topluyor; iptal/son tarih/hata ile atılan
      # bir istek, canlı oturumun seçim durumunu ve köken alt bilgisini
      # EZEMEMELİDİR (sonraki istek oradan tohumlanıyor).
      if (identical(durum, "bootstrap_failed")) {
        log_warn("[PK_ASYNC] Worker bootstrap basarisiz; senkron yeniden deneniyor.")
        return(devam_et(senkron_yedek("bootstrap_failed")))
      }
      shiny::isolate({
        ctx$cleanup_send_message()
        ctx$add_message_fn(mergen_pk_worker_outcome_text(durum, worker_result$error), "ai")
      })
      invisible(NULL)
    },
    onRejected = function(error) {
      if (!isTRUE(koruma_gecti("rejected"))) return(invisible(NULL))
      request_done <<- TRUE
      pk_cancel_token_clear(cancel_token)
      # Buraya yalnızca ALTYAPI hataları düşer (serileştirme/işçi kaybı):
      # boru hattı hataları işçide tipli pakete dönüştürülür. Diğer altyapı
      # yollarıyla (gönderim hatası, bootstrap_failed) SİMETRİK olarak senkron
      # yola dönülür; aksi hâlde yalnızca bayrak açık diye istek sert biçimde
      # başarısız olurdu.
      log_warn("[PK_ASYNC] Isci reddedildi; senkron yol deneniyor.")
      devam_et(senkron_yedek("worker_rejected"))
      invisible(NULL)
    }
  )

  # `then()` içindeki onFulfilled/onRejected KENDİLERİ de hata atabilir
  # (`mergen_pk_apply_analysis_result`, `continue_fn`, nihai LLM hazırlığı).
  # Bu istisna, kardeş onRejected'a DEĞİL, `then()`'in DÖNDÜRDÜĞÜ çocuk
  # promise'e düşer. Yakalanmazsa `is_sending`/backpressure takılı kalır ve
  # yanıt sessizce kaybolur.
  try(promises::catch(tamamlandi, function(hata) {
    log_warn("[PK_ASYNC] Devam kapanisi hata verdi; istek temizleniyor.")
    request_done <<- TRUE
    pk_cancel_token_clear(cancel_token)
    butce_birak()
    try(shiny::isolate({
      ctx$cleanup_send_message()
      ctx$add_message_fn(mergen_pk_worker_outcome_text("error"), "ai")
    }), silent = TRUE)
    invisible(NULL)
  }), silent = TRUE)

  list(action = "deferred")
}

mergen_pk_signal_cancel <- function(request_id, session = NULL) {
  kimlik <- try(as.character(request_id)[1], silent = TRUE)
  if (inherits(kimlik, "try-error") || is.null(kimlik) || !length(kimlik) ||
      is.na(kimlik) || !nzchar(kimlik)) return(invisible(FALSE))
  pk_cancel_token_signal(mergen_pk_cancel_token_for_session(session, kimlik))
}
