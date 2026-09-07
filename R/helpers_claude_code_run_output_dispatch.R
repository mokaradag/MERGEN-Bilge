# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_run_output_dispatch.R
# Açıklama: Bilge Yolaç çıktı işleme AŞAMASININ ana süreç tarafı: aktarım
#           hatalarının/kesilmiş taramanın kullanıcıya raporlanması ve çıktı
#           worker'ının bağımsız deadline ile gönderilmesi.
#
#           R/helpers_claude_code_run_completion.R (istek üretimi, aday
#           süzgeci ve worker gövdesi cc_process_run_outputs) dosyasından
#           SONRA yüklenir; bakım-yapılabilirlik cırcırı (800 satır / 25
#           fonksiyon) nedeniyle bilinçli olarak ayrılmıştır. Bu fonksiyonları
#           tekrar completion dosyasına taşımayın.
# ==============================================================================

cc_output_sync_failures <- function(outputs) {
  Filter(
    function(x) is.list(x) && !isTRUE(x$success),
    outputs$sync_results %||% list()
  )
}

cc_report_output_sync_failure <- function(ctx, outputs) {
  basarisiz <- cc_output_sync_failures(outputs)
  if (!length(basarisiz)) return(FALSE)

  yollar <- vapply(basarisiz, function(x) basename(x$dest_path %||% x$source_path %||% "dosya"), character(1))
  mesaj <- paste0(
    "Çalıştırma tamamlandı ancak ", length(basarisiz),
    " çıktı kaynak klasöre aktarılamadı: ", paste(unique(yollar), collapse = ", ")
  )
  # Kapanmış oturumda `sendCustomMessage()` HATA VERİR; kalıcılaştırma ve
  # sonlandırma her durumda çalışmalıdır. Aksi hâlde `promises::catch()` bu
  # yolu genel `cc_report_output_processing_failure()` dalına düşürüyor ve
  # "Aktarım Hatası" durumu hiç kalıcılaşmıyordu.
  try({
    ctx$session$sendCustomMessage("cc-stream-end", list(target = ctx$ns("output_area")))
    ctx$session$sendCustomMessage("cc-add-message", list(
      target = ctx$ns("output_area"), type = "error",
      content = htmltools::htmlEscape(mesaj), timestamp = format(Sys.time(), "%H:%M:%S")
    ))
  }, silent = TRUE)
  ctx$rv$last_result <- list(success = FALSE, output = "", error = mesaj)
  if (exists("cc_persist_run_result", mode = "function", inherits = TRUE)) {
    cc_persist_run_result(ctx$rv, ctx$env, status = "failed", final_output = mesaj)
  }
  cc_finalize_if_active(
    ctx$rv, ctx$env$request_id, ctx$finalize_streaming,
    durum_metin = "Aktarım Hatası", durum_ikon = "exclamation-triangle", durum_renk = "#E57373"
  )
  TRUE
}

cc_report_output_scan_truncation <- function(ctx, outputs) {
  if (!isTRUE(outputs$output_scan_truncated)) return(FALSE)

  neden <- as.character(outputs$output_scan_truncated_reason %||% "")[1]
  mesaj <- paste0(
    "Çalıştırma sonrası çıktı taraması güvenli sınırlar içinde tamamlanamadı",
    if (nzchar(neden)) paste0(" (", neden, ")") else "",
    "; üretilen dosyaların bir bölümü eksik kalabileceği için çalışma ",
    "tamamlandı olarak işaretlenmedi."
  )

  cc_log_warn(paste(CLAUDE_CODE_LOG_PREFIX, "[OUTPUT_DIFF]", mesaj))

  # Kapanmış oturumda gönderim hata verir; "Çıktı Taraması Eksik" durumunun
  # kalıcılaşması ve sonlandırma GÖNDERİMDEN BAĞIMSIZ olmalıdır.
  try({
    ctx$session$sendCustomMessage("cc-stream-end", list(target = ctx$ns("output_area")))
    ctx$session$sendCustomMessage("cc-add-message", list(
      target = ctx$ns("output_area"), type = "error",
      content = htmltools::htmlEscape(mesaj), timestamp = format(Sys.time(), "%H:%M:%S")
    ))
  }, silent = TRUE)
  ctx$rv$last_result <- list(success = FALSE, output = "", error = mesaj)
  if (exists("cc_persist_run_result", mode = "function", inherits = TRUE)) {
    cc_persist_run_result(ctx$rv, ctx$env, status = "failed", final_output = mesaj)
  }
  cc_finalize_if_active(
    ctx$rv, ctx$env$request_id, ctx$finalize_streaming,
    durum_metin = "Çıktı Taraması Eksik", durum_ikon = "exclamation-triangle",
    durum_renk = "#E57373"
  )
  TRUE
}

cc_report_output_processing_failure <- function(ctx, error) {
  mesaj <- paste0(
    "Claude işlemi tamamlandı ancak çıktı dosyaları güvenli biçimde işlenemedi: ",
    gsub("[{}]", "", conditionMessage(error))
  )
  # Kapanmış oturumda websocket gönderimi hata verir; KALICILAŞTIRMA ve
  # sonlandırma her durumda çalışmalıdır. Aksi hâlde koruma dosyası silinmiş
  # bir çalıştırma, geç çözülen worker promise'i tarafından sessizce
  # "Tamamlandı" olarak kapatılıyordu.
  try({
    ctx$session$sendCustomMessage("cc-stream-end", list(target = ctx$ns("output_area")))
    ctx$session$sendCustomMessage("cc-add-message", list(
      target = ctx$ns("output_area"), type = "error",
      content = htmltools::htmlEscape(mesaj), timestamp = format(Sys.time(), "%H:%M:%S")
    ))
  }, silent = TRUE)
  ctx$rv$last_result <- list(success = FALSE, output = "", error = mesaj)
  if (exists("cc_persist_run_result", mode = "function", inherits = TRUE)) {
    cc_persist_run_result(ctx$rv, ctx$env, status = "failed", final_output = mesaj)
  }
  try(cc_finalize_if_active(
    ctx$rv, ctx$env$request_id, ctx$finalize_streaming,
    durum_metin = "Çıktı İşleme Hatası", durum_ikon = "exclamation-triangle",
    durum_renk = "#E57373"
  ), silent = TRUE)
  invisible(TRUE)
}

#' Çıktı işlemesini arka plana gönder ve sonucunda çalıştırmayı sonlandır
#'
#' @param ctx Sonlandırma bağlamı (session, ns, rv, env, ayristirma, ...)
#' @return invisible(TRUE)
cc_dispatch_run_output_processing <- function(ctx) {
  guard <- file.path(
    ctx$env$runtime_layout$metadata %||% tempdir(),
    paste0("output-sync-", gsub("[^A-Za-z0-9_.-]", "_", ctx$env$request_id %||% "run"), ".active")
  )
  dir.create(dirname(guard), recursive = TRUE, showWarnings = FALSE)

  # file.create() sonucu kontrol edilmezse (ör. izin değişikliği veya geçici
  # disk dolması), var olmayan bir guard ile worker gönderilir;
  # cc_apply_output_sync_plan() eksik guard'ı iptal gibi yorumlayıp hiçbir
  # başarısız sonuç eklemeden çıkar ve çalıştırma yanlışlıkla "Tamamlandı"
  # görünür. Guard oluşturulamazsa worker hiç gönderilmeden açık bir hata
  # olarak sonlandırılır.
  guard_olusturuldu <- isTRUE(tryCatch(file.create(guard), error = function(e) FALSE)) &&
    isTRUE(tryCatch(file.exists(guard), error = function(e) FALSE))

  if (!isTRUE(guard_olusturuldu)) {
    # Lease bırakılmazsa cc_cleanup_stale_runtime_dirs() taze lease gördüğü için
    # runtime dizinini varsayılan orphan eşiğine (86400 sn) kadar gereksiz
    # tutuyordu.
    if (exists("cc_release_runtime_lease", mode = "function", inherits = TRUE)) {
      try(cc_release_runtime_lease(ctx$env$runtime_lease %||% ""), silent = TRUE)
    }
    cc_log_warn(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "[OUTPUT_SYNC] Aktarım koruma dosyası oluşturulamadı; çıktı işleme başlatılmadı."
    ))
    cc_report_output_processing_failure(
      ctx,
      simpleError(
        "Çıktı aktarım koruma dosyası oluşturulamadı; çalıştırma güvenli biçimde tamamlanamadı."
      )
    )
    return(invisible(TRUE))
  }

  ctx$env$output_sync_guard <- guard
  istek <- cc_build_run_output_request(ctx$env, ctx$ayristirma$tool_uses %||% list())

  # Aşama gönderimi HATA GÜVENLİ: kapanan oturumda `sendCustomMessage()` hata
  # verebiliyor; bu durumda guard/lease dosyaları temizlenmiyor, başarısızlık
  # raporlanmıyor ve worker hiç başlatılmadan akış sonlanıyordu.
  asama_hatasi <- tryCatch({
    # `cc_send_run_stage()` gönderim hatasında FALSE döner (istisna fırlatmaz);
    # sinyal yok sayılırsa guard/lease temizliği çalışmıyordu.
    if (!isTRUE(cc_send_run_stage(ctx$session, ctx$ns, "cikti"))) {
      simpleError("Çıktı aşaması bildirilemedi (oturum kapalı olabilir).")
    } else {
      NULL
    }
  }, error = function(e) e)

  if (inherits(asama_hatasi, "condition")) {
    unlink(guard, force = TRUE)
    unlink(ctx$env$runtime_lease %||% "", force = TRUE)
    cc_report_output_processing_failure(ctx, asama_hatasi)
    return(invisible(TRUE))
  }

  # Hazırlık aşamasındaki bağımsız deadline deseninin aynısı: takılan bir
  # worker çalıştırmayı "Çıktılar işleniyor" durumunda sonsuza bırakmamalı.
  cikti_zaman_asimi_sn <- cc_runtime_limit("output_process_timeout_sec", 180, istek$limits)
  cikti_zaman_asimi_durumu <- new.env(parent = emptyenv())
  cikti_zaman_asimi_durumu$pending <- TRUE
  # `expired`: deadline dolduktan SONRA geç çözülen bir promise, `changed_files`
  # boşken hata bulamıyor ve `cc_is_active_run()` hâlâ TRUE döndüğü için daha
  # önce `failed` olarak kalıcılaştırılmış çalıştırmayı `completed` yazabiliyordu.
  cikti_zaman_asimi_durumu$expired <- FALSE
  cikti_zaman_asimi_durumu$cancel <- later::later(function() {
    if (!isTRUE(cikti_zaman_asimi_durumu$pending)) return(invisible(NULL))
    cikti_zaman_asimi_durumu$pending <- FALSE
    cikti_zaman_asimi_durumu$expired <- TRUE

    # Bu çalıştırmanın KENDİ koruma dosyaları her durumda bırakılır.
    unlink(istek$active_guard, force = TRUE)
    unlink(ctx$env$runtime_lease %||% "", force = TRUE)

    # Daha yeni bir çalıştırma devraldıysa raporlama yapılmaz.
    if (!cc_is_active_run(ctx$rv, ctx$env$request_id)) return(invisible(NULL))

    # Guard silindiği için worker artık hiçbir çıktıyı aktaramaz; kayıt KAPALI
    # oturumda da başarısız olarak kalıcılaşmalıdır. Raporlayıcı websocket
    # gönderimlerini kendi içinde güvenli hâle getirir.
    cc_report_output_processing_failure(ctx, simpleError(sprintf(
      "Çıktı işleme zaman aşımına uğradı (%.0f saniye).", cikti_zaman_asimi_sn
    )))
  }, delay = cikti_zaman_asimi_sn)

  # `later` görevi yalnızca pending bayrağıyla etkisizleştirilirse closure
  # (ctx/istek/oturum) tüm süre boyunca canlı kalır; gerçek iptal edici çağrılır.
  cikti_deadline_iptal <- function() {
    cikti_zaman_asimi_durumu$pending <- FALSE
    iptal <- cikti_zaman_asimi_durumu$cancel
    if (is.function(iptal)) tryCatch(iptal(), error = function(e) NULL)
    cikti_zaman_asimi_durumu$cancel <- NULL
    invisible(NULL)
  }

  # tracked_future_promise() gönderim anında SENKRON hata verebilir (worker
  # planı yok, serileştirme hatası). Yakalanmazsa çalıştırma 180 saniye boyunca
  # "Çıktılar işleniyor" durumunda asılı kalırdı.
  gonderim <- tryCatch(
  tracked_future_promise(
    task_fn = function() {
      cc_process_run_outputs(istek)
    },
    task_type = "claude_code_run_outputs",
    session_token = ctx$session$token,
    dependency_mode = "explicit",
    globals = c(
      list(istek = istek),
      cc_run_output_worker_globals()
    ),
    packages = c("tools", "utils")
  ) |>
    promises::then(function(outputs) {
      cikti_deadline_iptal()
      if (isTRUE(cikti_zaman_asimi_durumu$expired) ||
          !cc_is_active_run(ctx$rv, ctx$env$request_id)) {
        unlink(istek$active_guard, force = TRUE)
        unlink(ctx$env$runtime_lease %||% "", force = TRUE)
        return(NULL)
      }

      cc_log_info(sprintf(
        paste0(
          "%s [OUTPUT_DIFF] request=%s | async=TRUE | degisen=%d | diff_ms=%.0f | ",
          "[DOWNLOAD_STAGE] indirme=%d | staging_ms=%.0f | ",
          "[OUTPUT_SYNC] aktarilan=%d | sync_ms=%.0f"
        ),
        CLAUDE_CODE_LOG_PREFIX,
        ctx$env$request_id %||% "",
        outputs$metrics$changed_count %||% 0L,
        outputs$metrics$diff_ms %||% 0,
        outputs$metrics$download_count %||% 0L,
        outputs$metrics$staging_ms %||% 0,
        outputs$metrics$synced_count %||% 0L,
        outputs$metrics$sync_ms %||% 0
      ))

      # Kaynak dizine gerçekten dosya aktarıldıysa bunu aşama olarak bildir.
      if (length(outputs$sync_results %||% list()) > 0L) {
        cc_send_run_stage(ctx$session, ctx$ns, "aktarim")
      }

      if (cc_report_output_scan_truncation(ctx, outputs)) {
        unlink(istek$active_guard, force = TRUE)
        unlink(ctx$env$runtime_lease %||% "", force = TRUE)
        return(NULL)
      }

      if (cc_report_output_sync_failure(ctx, outputs)) {
        unlink(istek$active_guard, force = TRUE)
        unlink(ctx$env$runtime_lease %||% "", force = TRUE)
        return(NULL)
      }

      cc_finish_streaming_run(ctx, outputs)
      unlink(istek$active_guard, force = TRUE)
      unlink(ctx$env$runtime_lease %||% "", force = TRUE)
      NULL
    }) |>
    promises::catch(function(e) {
      cikti_deadline_iptal()
      unlink(istek$active_guard, force = TRUE)
      unlink(ctx$env$runtime_lease %||% "", force = TRUE)
      if (isTRUE(cikti_zaman_asimi_durumu$expired) ||
          !cc_is_active_run(ctx$rv, ctx$env$request_id)) {
        return(NULL)
      }

      cc_log_warn(paste(
        CLAUDE_CODE_LOG_PREFIX,
        "[OUTPUT_DIFF] Çıktı işleme başarısız:",
        gsub("[{}]", "", conditionMessage(e))
      ))

      cc_report_output_processing_failure(ctx, e)
      NULL
    }),
    error = function(e) e
  )

  if (inherits(gonderim, "condition")) {
    cikti_deadline_iptal()
    unlink(istek$active_guard, force = TRUE)
    unlink(ctx$env$runtime_lease %||% "", force = TRUE)
    cc_log_warn(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "[OUTPUT_DIFF] Çıktı işleme gönderilemedi:",
      gsub("[{}]", "", conditionMessage(gonderim))
    ))
    if (cc_is_active_run(ctx$rv, ctx$env$request_id)) {
      cc_report_output_processing_failure(ctx, gonderim)
    }
  }

  invisible(TRUE)
}