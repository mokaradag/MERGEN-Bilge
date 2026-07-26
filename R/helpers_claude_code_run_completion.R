# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_run_completion.R
# Açıklama: Bilge Yolaç çalıştırması bittikten sonraki pahalı dosya işleri
#           (çıktı diff'i, kararlılık beklemesi, kodlama normalizasyonu,
#           indirme staging'i ve yalnızca değişen dosyaların kaynak dizine
#           aktarımı) arka plan worker'ında BİR KEZ yürütülür.
#
#           Ana Shiny süreci yalnızca sonucu alır, HTML üretir ve UI'ı
#           sonlandırır. Böylece büyük çıktı klasörleri diğer oturumları
#           bloke etmez ve aynı çalıştırma için toplama iki kez çalışmaz.
# ==============================================================================

.cc_completion_worker_cache <- new.env(parent = emptyenv())

#' Çıktı işleme worker'ına aktarılacak global paketi (bir kez) oluştur
cc_run_output_worker_globals <- function(refresh = FALSE, envir = globalenv()) {
  if (!isTRUE(refresh) && !is.null(.cc_completion_worker_cache$globals)) {
    return(.cc_completion_worker_cache$globals)
  }

  wanted <- c(
    "cc_process_run_outputs",
    "diff_claude_code_workdir_snapshot",
    "collect_claude_code_workdir_changes_downloads",
    "cc_collect_streaming_run_downloads",
    "cc_stage_tool_use_write_paths_as_downloads",
    "sync_claude_runtime_workdir_back",
    "cc_scan_default_excluded_dirs",
    "cc_scan_runtime_excluded_dirs",
    "claude_code_runtime_limits",
    "claude_code_config",
    "CLAUDE_CODE_LOG_PREFIX"
  )

  bundle <- list()
  for (nm in wanted) {
    obj <- get0(nm, envir = envir, inherits = TRUE)
    if (!is.null(obj)) bundle[[nm]] <- obj
  }

  if (exists("worker_monitor_expand_function_globals", mode = "function", inherits = TRUE)) {
    nested <- tryCatch(
      worker_monitor_expand_function_globals(bundle),
      error = function(e) list()
    )

    for (nm in names(nested)) {
      if (!nm %in% names(bundle)) bundle[[nm]] <- nested[[nm]]
    }
  }

  .cc_completion_worker_cache$globals <- bundle
  bundle
}

#' Akış ortamından düz veri çıktı isteği oluştur
#'
#' @param env Akış durumu ortamı
#' @param tool_uses Ayrıştırılmış araç kullanımları
#' @return Serileştirilebilir istek listesi
cc_build_run_output_request <- function(env, tool_uses = list()) {
  list(
    before_snapshot = env$workdir_snapshot %||% list(),
    tool_uses = tool_uses %||% list(),
    runtime_workdir = env$calisma_dizini %||% "",
    source_workdir = env$kaynak_calisma_dizini %||% "",
    user_id = env$user_id %||% 0L,
    session_token = env$session_token %||% "",
    layout = env$runtime_layout,
    mirrored = isTRUE(env$mirror_kullanildi),
    request_id = env$request_id %||% "",
    limits = tryCatch(
      get("claude_code_runtime_limits", inherits = TRUE),
      error = function(e) list()
    )
  )
}

#' Çalıştırma sonrası çıktı işlemesini arka planda BİR KEZ yürüt
#'
#' @param request cc_build_run_output_request() çıktısı
#' @return list(downloads, changed_files, sync_results, metrics)
cc_process_run_outputs <- function(request) {
  baslangic <- Sys.time()

  gecen_ms <- function(from) {
    round(as.numeric(difftime(Sys.time(), from, units = "secs")) * 1000, 1)
  }

  haric <- cc_scan_default_excluded_dirs()
  if (isTRUE(request$mirrored)) {
    haric <- unique(c(haric, cc_scan_runtime_excluded_dirs()))
  }

  diff_baslangic <- Sys.time()

  degisenler <- character(0)
  if (nzchar(request$runtime_workdir %||% "") && dir.exists(request$runtime_workdir)) {
    degisenler <- tryCatch(
      diff_claude_code_workdir_snapshot(
        before_snapshot = request$before_snapshot,
        workdir = request$runtime_workdir,
        exclude_dirs = haric,
        limits = request$limits
      ),
      error = function(e) character(0)
    )
  }

  diff_ms <- gecen_ms(diff_baslangic)

  staging_baslangic <- Sys.time()

  indirmeler <- tryCatch(
    cc_collect_streaming_run_downloads(
      before_snapshot = request$before_snapshot,
      tool_uses = request$tool_uses,
      runtime_workdir = request$runtime_workdir,
      source_workdir = request$source_workdir,
      user_id = request$user_id,
      session_token = request$session_token,
      changed_files = degisenler,
      exclude_dirs = haric,
      limits = request$limits
    ),
    error = function(e) list()
  )

  staging_ms <- gecen_ms(staging_baslangic)

  sync_baslangic <- Sys.time()
  sync_sonuclari <- list()

  if (isTRUE(request$mirrored)) {
    sync_sonuclari <- tryCatch(
      sync_claude_runtime_workdir_back(
        runtime_workdir = request$runtime_workdir,
        source_workdir = request$source_workdir,
        changed_files = degisenler,
        layout = request$layout,
        limits = request$limits
      ),
      error = function(e) list()
    )
  }

  sync_ms <- gecen_ms(sync_baslangic)

  list(
    downloads = indirmeler,
    changed_files = degisenler,
    sync_results = sync_sonuclari,
    metrics = list(
      total_ms = gecen_ms(baslangic),
      diff_ms = diff_ms,
      staging_ms = staging_ms,
      sync_ms = sync_ms,
      changed_count = length(degisenler),
      download_count = length(indirmeler),
      synced_count = sum(vapply(
        sync_sonuclari,
        function(x) isTRUE(x$success),
        logical(1)
      ))
    )
  )
}

#' Çıktı işlemesini arka plana gönder ve sonucunda çalıştırmayı sonlandır
#'
#' @param ctx Sonlandırma bağlamı (session, ns, rv, env, ayristirma, ...)
#' @return invisible(TRUE)
cc_dispatch_run_output_processing <- function(ctx) {
  istek <- cc_build_run_output_request(ctx$env, ctx$ayristirma$tool_uses %||% list())

  cc_send_run_stage(ctx$session, ctx$ns, "cikti")

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
      if (!cc_is_active_run(ctx$rv, ctx$env$request_id)) {
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

      cc_finish_streaming_run(ctx, outputs)
      NULL
    }) |>
    promises::catch(function(e) {
      if (!cc_is_active_run(ctx$rv, ctx$env$request_id)) {
        return(NULL)
      }

      cc_log_warn(paste(
        CLAUDE_CODE_LOG_PREFIX,
        "[OUTPUT_DIFF] Çıktı işleme başarısız:",
        gsub("[{}]", "", conditionMessage(e))
      ))

      cc_finish_streaming_run(
        ctx,
        list(downloads = list(), changed_files = character(0), sync_results = list())
      )
      NULL
    })

  invisible(TRUE)
}

.cc_log_tool_use_debug <- function(env, ayristirma, olusan_dosyalar) {
  tryCatch({
    ham_satir_sayisi <- length(env$tum_satirlar)
    ilk_n <- min(3L, ham_satir_sayisi)

    olay_turleri <- character(0)
    if (ham_satir_sayisi > 0L) {
      for (satir in env$tum_satirlar) {
        if (!nzchar(satir)) next
        nesne <- tryCatch(
          jsonlite::fromJSON(satir, simplifyVector = FALSE),
          error = function(e) NULL
        )
        if (is.null(nesne)) next
        tur <- as.character(nesne$type %||% "")
        if (identical(tur, "stream_event")) {
          tur <- paste0("stream_event:", as.character(nesne$event$type %||% ""))
        }
        olay_turleri <- c(olay_turleri, tur)
      }
    }

    olay_ozeti <- if (length(olay_turleri)) {
      olay_say <- table(olay_turleri)
      paste(sprintf("%s=%d", names(olay_say), as.integer(olay_say)), collapse = ",")
    } else {
      "(olay tespit edilmedi)"
    }

    log_info(sprintf(
      "%s [TOOL_USE_DEBUG] ham_satir=%d | parsed_tool_uses=%d | olay_dagilimi=%s",
      CLAUDE_CODE_LOG_PREFIX,
      ham_satir_sayisi,
      length(ayristirma$tool_uses %||% list()),
      olay_ozeti
    ))

    if (length(ayristirma$tool_uses %||% list()) == 0L &&
        length(olusan_dosyalar %||% list()) > 0L) {
      ornek_ozet <- if (ilk_n > 0L) {
        paste(substr(env$tum_satirlar[seq_len(ilk_n)], 1L, 200L), collapse = " || ")
      } else {
        "(ham satır yok)"
      }

      log_warn(sprintf(
        "%s [TOOL_USE_DEBUG] Parser tool_use yakalamadı ama %d dosya üretildi. İlk %d ham JSONL örneği: %s",
        CLAUDE_CODE_LOG_PREFIX,
        length(olusan_dosyalar),
        ilk_n,
        gsub("[{}]", "", ornek_ozet)
      ))
    }
  }, error = function(e) NULL)

  invisible(TRUE)
}

.cc_missing_tool_warning_html <- function(env, ayristirma, olusan_dosyalar) {
  no_tool_kullanildi <- length(ayristirma$tool_uses %||% list()) == 0L
  no_dosya_uretildi <- length(olusan_dosyalar %||% list()) == 0L

  yazma_niyeti_var <- tryCatch(
    isTRUE(cc_policy_prompt_has_write_intent(env$prompt)),
    error = function(e) FALSE
  )

  if (!isTRUE(yazma_niyeti_var) || !isTRUE(no_tool_kullanildi) || !isTRUE(no_dosya_uretildi)) {
    return("")
  }

  log_warn(paste(
    CLAUDE_CODE_LOG_PREFIX,
    "Kullanıcı dosya oluşturma/değiştirme istedi ancak hiç araç",
    "kullanımı (tool_use) algılanmadı ve çalışma dizininde yeni dosya",
    "üretilmedi. On-prem LLM proxy araç olaylarını üretmiyor olabilir."
  ))

  paste0(
    '<div class="cc-tool-warning" ',
    'style="margin-top:12px; padding:10px 14px; border-left:3px solid #FFB74D; ',
    'background:rgba(255,183,77,0.08); color:#FFB74D; ',
    'border-radius:6px; font-size:13px;">',
    '<i class="fas fa-triangle-exclamation"></i> ',
    'Model bir dosya oluşturma/değiştirme isteğine yanıt verdi ancak ',
    'gerçekte hiçbir araç (Read/Write/Edit vb.) çağrısı yapılmadı ve ',
    'çalışma dizininde yeni bir dosya algılanmadı. Yanıttaki bilgiler ',
    'yalnızca metin tabanlı olabilir; gerçek bir dosya işlemi ',
    'beklediyseniz lütfen isteğinizi netleştirip yeniden deneyin.',
    '</div>'
  )
}

#' Çıktı işlemesi bittikten sonra çalıştırmayı sonlandır
#'
#' @param ctx Sonlandırma bağlamı
#' @param outputs cc_process_run_outputs() sonucu
#' @return invisible(TRUE)
cc_finish_streaming_run <- function(ctx, outputs) {
  session <- ctx$session
  ns <- ctx$ns
  rv <- ctx$rv
  env <- ctx$env
  ayristirma <- ctx$ayristirma
  cikis_kodu <- ctx$cikis_kodu
  sure <- ctx$sure

  olusan_dosyalar <- outputs$downloads %||% list()

  indirme_html <- tryCatch(
    format_claude_code_generated_downloads_html(olusan_dosyalar),
    error = function(e) ""
  )

  .cc_log_tool_use_debug(env, ayristirma, olusan_dosyalar)

  if (identical(cikis_kodu, 0L)) {
    log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Akış tamamlandı - Süre:", sure, "sn"))

    oturum_id <- env$oturum_id %||% ayristirma$session_id
    if (!is.null(oturum_id) && nzchar(oturum_id %||% "")) {
      rv$cli_session_id <- oturum_id
    }

    rv$conversation_context <- c(
      rv$conversation_context,
      list(list(role = "assistant", content = ayristirma$text_output))
    )

    sentetik_arac_eklendi <- cc_synthesize_tool_uses_from_downloads(
      session = session,
      ns = ns,
      env = env,
      ayristirma = ayristirma,
      olusan_dosyalar = olusan_dosyalar
    )

    if (length(sentetik_arac_eklendi)) {
      ayristirma$tool_uses <- c(ayristirma$tool_uses, sentetik_arac_eklendi)
    }

    son_icerik <- paste0(
      format_claude_code_output(ayristirma$text_output),
      indirme_html,
      .cc_missing_tool_warning_html(env, ayristirma, olusan_dosyalar)
    )

    son_arac_kullanim_html <- tryCatch(
      if (length(ayristirma$tool_uses %||% list()) > 0L) {
        format_tool_uses_html_enhanced(ayristirma$tool_uses)
      } else {
        ""
      },
      error = function(e) ""
    )

    session$sendCustomMessage(
      type = "cc-stream-end",
      message = list(
        target = ns("output_area"),
        duration = sure,
        finalContent = son_icerik,
        finalToolUsesHtml = son_arac_kullanim_html,
        accentColor = env$karakter_renk,
        characterName = env$karakter_adi
      )
    )

    rv$last_result <- list(
      success = TRUE,
      output = ayristirma$text_output,
      error = "",
      duration = sure,
      tool_uses = ayristirma$tool_uses,
      session_id = oturum_id,
      generated_downloads = olusan_dosyalar
    )

    if (exists("cc_persist_run_result", mode = "function", inherits = TRUE)) {
      cc_persist_run_result(
        rv = rv,
        env = env,
        status = "completed",
        final_output = ayristirma$text_output %||% "",
        exit_code = cikis_kodu,
        duration = sure,
        tool_uses = ayristirma$tool_uses,
        downloads = olusan_dosyalar,
        cli_session_id = oturum_id
      )
    }

    cc_finalize_if_active(
      rv = rv,
      request_id = env$request_id,
      finalize_streaming = ctx$finalize_streaming,
      durum_metin = "Tamamlandı",
      durum_ikon = "check-circle",
      durum_renk = "#81C784",
      sure = sure
    )
  } else {
    hata_mesaji <- ctx$hata_mesaji %||% ""

    log_warn(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Akış hata kodu:",
      cikis_kodu,
      "- Mesaj:",
      gsub("[{}]", "", substr(hata_mesaji, 1, 200))
    ))

    session$sendCustomMessage(
      type = "cc-stream-end",
      message = list(target = ns("output_area"))
    )

    session$sendCustomMessage(
      type = "cc-add-message",
      message = list(
        target = ns("output_area"),
        type = "error",
        content = htmltools::htmlEscape(hata_mesaji),
        timestamp = format(Sys.time(), "%H:%M:%S"),
        welcomeId = ns("welcome_screen")
      )
    )

    if (nzchar(indirme_html)) {
      session$sendCustomMessage(
        type = "cc-add-message",
        message = list(
          target = ns("output_area"),
          type = "ai",
          content = indirme_html,
          timestamp = format(Sys.time(), "%H:%M:%S"),
          welcomeId = ns("welcome_screen"),
          accentColor = env$karakter_renk,
          characterName = env$karakter_adi
        )
      )
    }

    rv$last_result <- list(
      success = FALSE,
      output = "",
      error = hata_mesaji,
      duration = sure,
      tool_uses = ayristirma$tool_uses,
      session_id = env$oturum_id %||% ayristirma$session_id,
      generated_downloads = olusan_dosyalar
    )

    if (exists("cc_persist_run_result", mode = "function", inherits = TRUE)) {
      cc_persist_run_result(
        rv = rv,
        env = env,
        status = "failed",
        final_output = hata_mesaji %||% "",
        exit_code = cikis_kodu,
        duration = sure,
        tool_uses = ayristirma$tool_uses,
        downloads = olusan_dosyalar,
        cli_session_id = env$oturum_id %||% ayristirma$session_id
      )
    }

    cc_finalize_if_active(
      rv = rv,
      request_id = env$request_id,
      finalize_streaming = ctx$finalize_streaming,
      durum_metin = "Hata",
      durum_ikon = "exclamation-triangle",
      durum_renk = "#E57373",
      sure = sure
    )
  }

  rv$output_history <- c(
    rv$output_history,
    list(list(
      prompt = env$prompt,
      result = rv$last_result,
      timestamp = Sys.time(),
      character = env$karakter_id
    ))
  )

  ctx$observe_dir_contents(
    dizin = env$kaynak_calisma_dizini %||% env$calisma_dizini
  )

  cc_refresh_user_file_manager_after_run(
    session = session,
    user_id = env$user_id
  )

  invisible(TRUE)
}
