# ==============================================================================
# Dosya Yolu: R/helpers_file_manager_upload_runtime.R
# Açıklama: Dosya Yönetimi toplu yükleme gönderimi ve tamamlanma bağlayıcısı.
#           Doğrulama, hash + kopyalama ve bütünlük denetimi burada senkron
#           ÇALIŞMAZ; ortak alım hattına (R/helpers_file_ingestion_*.R)
#           devredilir. Burada ucuz plan/bildirim ve ana süreç commit'i kalır.
# ==============================================================================

# Toplu yükleme için oturum kapsamlı denetleyici ve commit bağlamını üretir.
# Modül yalnızca bu fabrikayı çağırır; yükleme durumu burada toplanır.
fm_create_upload_runtime <- function(session,
                                     process_uploaded_file,
                                     message_data,
                                     message_trigger,
                                     files_added_to_context,
                                     fm_debug, rollback_uploaded_file = NULL, get_user_upload_dir = NULL) {
  list(
    controller = file_ingestion_create_controller(session = session, debug_fn = fm_debug),
    commit_ctx = list(
      session = session,
      process_uploaded_file = process_uploaded_file,
      message_data = message_data,
      message_trigger = message_trigger,
      files_added_to_context = files_added_to_context,
      fm_debug = fm_debug,
      # Çözümleyici olmadan yetim kopya temizliği kökü bulamaz.
      get_user_upload_dir = get_user_upload_dir,
      rollback_uploaded_file = rollback_uploaded_file
    )
  )
}

# Plan aşamasındaki ucuz redleri ve yinelenen adları kullanıcıya bildirir.
fm_report_upload_plan_issues <- function(session, plan) {
  if (length(plan$duplicate_names) > 0L) {
    showToast(session, paste(
      "Dosya(lar) zaten mevcut:", paste(plan$duplicate_names, collapse = ", ")
    ), "warning")
  }

  for (red in plan$rejected %||% list()) {
    showToast(session, sprintf(
      "Dosya reddedildi: %s - %s", red$name, red$error %||% "bilinmeyen doğrulama hatası"
    ), "error")
  }

  invisible(TRUE)
}

# Worker tamamlandıktan sonra ANA SÜREÇTE çalışır: tablo satırları, bağlam
# senkronizasyonu ve kullanıcı bildirimleri burada üretilir.
# Promise geri çağrısı reaktif BAĞLAM içinde değildir; modül state'i okuyan tüm
# iş shiny::isolate() içine alınır (yazmalar yine dinleyicileri tetikler).
fm_commit_bulk_upload_results <- function(results, ctx, batch_id = NULL) {
  if (!is.null(batch_id)) try(removeNotification(batch_id), silent = TRUE)

  shiny::isolate({
    saved_infos <- list()

    for (sonuc in results %||% list()) {
      if (!isTRUE(sonuc$ok)) {
        ctx$fm_debug("upload_reject", sprintf("%s -> %s", sonuc$name, sonuc$code %||% "unknown"))
        showToast(ctx$session, sprintf(
          "Dosya kaydedilemedi: %s - %s", sonuc$name, sonuc$error %||% "bilinmeyen hata"
        ), "error")
        next
      }

      # Tek dosyanın commit hatası partinin kalanını düşürmez.
      saved <- try(ctx$process_uploaded_file(
        list(name = sonuc$name, datapath = sonuc$dest, size = sonuc$size, type = sonuc$type),
        generate_message = FALSE
      ), silent = TRUE)

      # ATOMİK DEĞİL: yan etkiler geri alınmazsa yetim kopya + görünmez kayıt
      # kalır. `process_uploaded_file()` okunamayan yol / desteklenmeyen uzantıda
      # HATA FIRLATMADAN NULL döner; `try()` bunu yakalamıyor ve kopya kalıyordu.
      if (inherits(saved, "try-error")) {
        hata_metni <- conditionMessage(attr(saved, "condition"))
        fm_report_upload_rollback(sonuc, ctx, "upload_commit_error", hata_metni)
        showToast(ctx$session, sprintf("Dosya tabloya eklenemedi: %s - %s", sonuc$name, hata_metni), "error")
        saved <- NULL
      } else if (is.null(saved)) {
        fm_report_upload_rollback(sonuc, ctx, "upload_commit_null")
      }

      if (!is.null(saved)) saved_infos[[length(saved_infos) + 1L]] <- saved
    }

    if (length(saved_infos) > 0L) {
      ctx$message_data(list(
        content = sprintf("%d dosya yüklendi.", length(saved_infos)),
        html    = sprintf("\U0001F4CE <b>%d dosya</b> yüklendi ve sohbete eklendi.", length(saved_infos)),
        type    = "system"
      ))
      ctx$message_trigger(ctx$message_trigger() + 1)
      showToast(ctx$session, paste(length(saved_infos), "dosya başarıyla yüklendi!"), "success")
      ctx$files_added_to_context(saved_infos)
    }

    invisible(saved_infos)
  })
}

# Toplu yüklemeyi planlar ve arka plan alım hattına gönderir. Olay döngüsünde
# yalnızca ucuz üstveri işi yapılır; dönüş anında gerçekleşir.
fm_dispatch_bulk_upload_batch <- function(files_df,
                                          existing_names,
                                          session,
                                          uid,
                                          is_auth_ready,
                                          controller,
                                          commit_ctx,
                                          fm_debug) {
  batch_id <- file_ingestion_new_batch_id("fm")

  plan <- file_ingestion_plan_batch(
    uploads = files_df,
    existing_names = existing_names,
    user_id = uid,
    allowed_ext = fm_normal_allowed_extensions(),
    max_size_mb = fm_upload_limit_mb(),
    batch_id = batch_id
  )

  fm_report_upload_plan_issues(session, plan)

  if (!length(plan$tasks)) {
    return(invisible(list(status = "empty", batch_id = batch_id)))
  }

  if (isTRUE(SSO_ENABLED) && !is_auth_ready()) {
    fm_debug("upload_skip", "auth henüz tamamlanmadığı için toplu yükleme ertelendi")
    showToast(session, "Kimlik doğrulama tamamlanmadan dosya yüklenemez.", "warning")
    return(invisible(list(status = "auth_blocked", batch_id = batch_id)))
  }

  if (!file_ingestion_valid_user_id(uid)) {
    fm_debug("persist_abort", "geçersiz user_id nedeniyle toplu yükleme iptal edildi")
    showToast(session, "Dosyalar kalıcı klasöre kaydedilemedi: kullanıcı kimliği çözümlenemedi.", "error")
    return(invisible(list(status = "invalid_user", batch_id = batch_id)))
  }

  showNotification(
    sprintf("%d dosya arka planda işleniyor\U2026", length(plan$tasks)),
    duration = NULL,
    type = "message",
    id = batch_id
  )

  outcome <- file_ingestion_submit_batch(
    controller = controller,
    tasks = plan$tasks,
    user_id = uid,
    on_complete = function(results, ctx) fm_commit_bulk_upload_results(results, commit_ctx, ctx$batch_id),
    on_failure = function(message, tasks) {
      try(removeNotification(batch_id), silent = TRUE)
      fm_debug("upload_error", message)
      showToast(session, "Dosyalar işlenemedi. Lütfen tekrar deneyin.", "error")
    },
    batch_id = batch_id
  )

  if (identical(outcome$status, "rejected")) {
    try(removeNotification(batch_id), silent = TRUE)
    showToast(session, "Yükleme kuyruğu dolu. Lütfen biraz sonra tekrar deneyin.", "warning")
  }

  fm_debug("upload_dispatch", sprintf(
    "batch=%s dosya=%d durum=%s", batch_id, length(plan$tasks), outcome$status
  ))

  invisible(outcome)
}
