# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_run_dispatch.R
# Açıklama: Bilge Yolaç çalıştırma hazırlığının ana Shiny süreci tarafı.
#           Pahalı dosya sistemi işleri arka plan worker'ına gönderilir; bu
#           dosya yalnızca durum (aşama) güncellemesi, stale-callback koruması,
#           model çözümü ve Claude Code sürecinin başlatılmasını üstlenir.
#
#           Hazırlık tamamlanmadan durum "Çalışıyor" gösterilmez; böylece
#           kullanıcı gerçek aşamayı görür ve tek bir kullanıcının büyük
#           klasörü diğer oturumları bloke etmez.
# ==============================================================================

# Aşama etiketleri: hazırlık ile model çalıştırma durumunu ayırır.
claude_code_run_stages <- list(
  hazirlaniyor = list(metin = "Hazırlanıyor", ikon = "hourglass-half", renk = "#64B5F6"),
  taraniyor = list(metin = "Dosyalar taranıyor", ikon = "search", renk = "#64B5F6"),
  girdi = list(metin = "Gerekli dosyalar hazırlanıyor", ikon = "copy", renk = "#64B5F6"),
  dokuman = list(metin = "Dokümanlar hazırlanıyor", ikon = "file-lines", renk = "#64B5F6"),
  model = list(metin = "Model başlatılıyor", ikon = "play", renk = "#64B5F6"),
  calisiyor = list(metin = "Çalışıyor", ikon = "spinner", renk = "#64B5F6"),
  cikti = list(metin = "Çıktılar işleniyor", ikon = "gears", renk = "#64B5F6"),
  aktarim = list(metin = "Çıktılar aktarılıyor", ikon = "file-export", renk = "#64B5F6"),
  tamamlandi = list(metin = "Tamamlandı", ikon = "check-circle", renk = "#81C784"),
  durduruldu = list(metin = "Durduruldu", ikon = "stop-circle", renk = "#FFB74D"),
  hata = list(metin = "Hata", ikon = "exclamation-triangle", renk = "#E57373"),
  zaman_asimi = list(metin = "Zaman Aşımı", ikon = "clock", renk = "#FFB74D")
)

#' Çalıştırma aşaması durum çubuğunu güncelle
#'
#' @param session Shiny oturumu
#' @param ns Ad alanı fonksiyonu
#' @param stage claude_code_run_stages anahtarı
#' @param duration Süre metni
cc_send_run_stage <- function(session, ns, stage, duration = "") {
  bilgi <- claude_code_run_stages[[stage]]

  if (is.null(bilgi)) {
    bilgi <- claude_code_run_stages$hazirlaniyor
  }

  session$sendCustomMessage(
    type = "cc-update-status",
    message = list(
      statusId = ns("status_text"),
      durationId = ns("duration_text"),
      status = bilgi$metin,
      statusIcon = bilgi$ikon,
      statusColor = bilgi$renk,
      duration = duration
    )
  )

  invisible(TRUE)
}

#' Hazırlık aşamasında biten çalıştırmayı güvenle sonlandır
#'
#' Yalnızca hata veren geri çağrı hâlâ aktif çalışmaya aitse durum temizlenir;
#' böylece geç gelen stale callback yeni bir çalışmayı bozamaz.
cc_fail_run_preparation <- function(ctx, message, stage = "hata") {
  if (!cc_is_active_run(ctx$rv, ctx$run_request_id)) {
    return(invisible(FALSE))
  }

  cc_send_run_blocked_message(
    session = ctx$session,
    ns = ctx$ns,
    message = message
  )

  bilgi <- claude_code_run_stages[[stage]] %||% claude_code_run_stages$hata

  cc_finalize_if_active(
    rv = ctx$rv,
    request_id = ctx$run_request_id,
    finalize_streaming = ctx$finalize_streaming,
    durum_metin = bilgi$metin,
    durum_ikon = bilgi$ikon,
    durum_renk = bilgi$renk,
    sure = NULL
  )

  invisible(TRUE)
}

#' Etkin future planı gerçekten eşzamansız mı?
#'
#' Üretimde PSOCK küme kurulamazsa `global.R` `future::sequential` planına
#' düşer. O planda `tracked_future_promise()` gövdeyi GÖNDERİM ANINDA ana
#' Shiny olay döngüsünde çalıştırır; büyük bir tarama/UNC kopyası veya doküman
#' çıkarımı tüm oturumları bloke eder ve bağımsız deadline hiç tetiklenemez.
#'
#' @return Plan gerçekten eşzamansızsa TRUE
cc_future_plan_is_async <- function() {
  if (!requireNamespace("future", quietly = TRUE)) return(FALSE)

  plan_siniflari <- tryCatch(
    class(future::plan("list")[[1]]),
    error = function(e) character(0)
  )

  if (!length(plan_siniflari)) return(FALSE)

  !any(c("sequential", "uniprocess", "transparent") %in% plan_siniflari)
}

#' Hazırlık işini arka plan worker'ına gönder
#'
#' @param ctx Çalıştırma bağlamı (session, ns, rv ve düz veriler)
#' @return invisible(TRUE)
cc_dispatch_run_preparation <- function(ctx) {
  # Eşzamansız olmayan planda hazırlık ana olay döngüsünde çalışır; bu
  # durumda çalışmayı başlatmak yerine açıkça reddederiz.
  if (!isTRUE(cc_future_plan_is_async())) {
    cc_log_warn(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "[RUNTIME_PREPARE] Eşzamansız worker planı yok; çalıştırma reddedildi."
    ))

    cc_fail_run_preparation(
      ctx,
      paste0(
        "Arka plan çalışma havuzu kullanılamıyor. Bilge Yolaç çalıştırması ",
        "diğer oturumları bloke etmemek için başlatılmadı. Lütfen sistem ",
        "yöneticisiyle iletişime geçin veya uygulamayı yeniden başlatın."
      )
    )

    return(invisible(FALSE))
  }

  cc_send_run_stage(ctx$session, ctx$ns, "taraniyor")

  mevcut_runtime <- NULL
  if (!is.null(ctx$rv$active_runtime_source) &&
      !is.null(ctx$rv$active_runtime_workdir) &&
      identical(
        as.character(ctx$rv$active_runtime_source),
        as.character(ctx$workdir)
      )) {
    mevcut_runtime <- ctx$rv$active_runtime_workdir
  }

  # Sahiplik ANA süreçte, worker gönderilmeden önce devralınır. Böylece aynı
  # runtime üzerinde çalışan eski/durdurulmuş bir hazırlık worker'ı bir
  # sonraki kontrolünde çekilir ve yeni çalışmanın dosyalarını ezemez.
  if (!is.null(mevcut_runtime) && nzchar(as.character(mevcut_runtime)[1])) {
    tryCatch(
      cc_claim_runtime_ownership(mevcut_runtime, ctx$run_request_id),
      error = function(e) ""
    )
  }

  istek <- cc_build_run_prepare_request(
    prompt = ctx$prompt,
    workdir = ctx$workdir,
    user_id = ctx$user_id,
    request_id = ctx$run_request_id,
    existing_runtime_workdir = mevcut_runtime,
    explicit_files = ctx$explicit_files %||% character(0)
  )

  hazirlik_baslangic <- Sys.time()
  zaman_asimi_sn <- cc_runtime_limit("prepare_timeout_sec", 180)
  zaman_asimi_durumu <- new.env(parent = emptyenv())
  zaman_asimi_durumu$pending <- TRUE

  # Başarı callback'inde geçen süreyi ölçmek zaman aşımı değildir: bloke bir
  # worker o callback'e hiç ulaşmaz. Ana later döngüsündeki bağımsız deadline
  # aktif isteği zamanında sonlandırır; geç dönen future stale guard'a takılır.
  zaman_asimi_durumu$cancel <- later::later(function() {
    if (isTRUE(zaman_asimi_durumu$pending) &&
        cc_is_active_run(ctx$rv, ctx$run_request_id)) {
      zaman_asimi_durumu$pending <- FALSE
      cc_fail_run_preparation(
        ctx,
        paste0(
          "Çalışma alanı hazırlığı zaman aşımına uğradı (",
          round(zaman_asimi_sn), " saniye). Lütfen daha küçük bir klasör seçin."
        ),
        stage = "zaman_asimi"
      )
    }
  }, delay = zaman_asimi_sn)

  # Hazırlık bittiği anda bekleyen deadline iptal edilir; aksi halde her
  # çalıştırma tam süre boyunca session/prompt/API anahtarı bağlamını
  # canlı tutan bir closure biriktirir.
  cc_cancel_prepare_deadline <- function() {
    zaman_asimi_durumu$pending <- FALSE
    iptal <- zaman_asimi_durumu$cancel
    if (is.function(iptal)) {
      tryCatch(iptal(), error = function(e) NULL)
    }
    zaman_asimi_durumu$cancel <- NULL
    invisible(NULL)
  }

  tracked_future_promise(
    task_fn = function() {
      cc_prepare_run_workspace(istek)
    },
    task_type = "claude_code_run_prepare",
    session_token = ctx$session$token,
    dependency_mode = "explicit",
    globals = c(
      list(istek = istek),
      cc_run_prepare_worker_globals()
    ),
    packages = c("tools", "utils")
  ) |>
    promises::then(function(prep) {
      cc_cancel_prepare_deadline()
      if (!cc_is_active_run(ctx$rv, ctx$run_request_id)) {
        cc_release_runtime_lease(prep$runtime_lease %||% "")
        return(NULL)
      }

      gecen <- as.numeric(difftime(Sys.time(), hazirlik_baslangic, units = "secs"))

      cc_log_info(sprintf(
        paste0(
          "%s [RUNTIME_PREPARE] request=%s | async=TRUE | toplam_ms=%.0f | ",
          "runtime_ms=%.0f | dokuman_ms=%.0f | snapshot_ms=%.0f | ",
          "girdi_dosya=%d | girdi_bayt=%.0f | secim=%s | aynalandi=%s | yeniden=%s"
        ),
        CLAUDE_CODE_LOG_PREFIX,
        ctx$run_request_id,
        prep$metrics$total_ms %||% 0,
        prep$metrics$runtime_ms %||% 0,
        prep$metrics$document_ms %||% 0,
        prep$metrics$snapshot_ms %||% 0,
        prep$metrics$input_files %||% 0L,
        prep$metrics$input_bytes %||% 0,
        prep$metrics$selection_mode %||% "",
        isTRUE(prep$mirrored),
        isTRUE(prep$reused)
      ))

      if (isTRUE(prep$blocked)) {
        cc_release_runtime_lease(prep$runtime_lease %||% "")
        cc_fail_run_preparation(ctx, prep$message %||% CLAUDE_CODE_LIMIT_MESSAGE)
        return(NULL)
      }

      cc_start_streaming_run(ctx, prep)
      NULL
    }) |>
    promises::catch(function(e) {
      cc_cancel_prepare_deadline()
      if (!cc_is_active_run(ctx$rv, ctx$run_request_id)) {
        return(NULL)
      }

      hata_metni <- conditionMessage(e)

      cc_log_warn(paste(
        CLAUDE_CODE_LOG_PREFIX,
        "[RUNTIME_PREPARE] Hazırlık başarısız:",
        gsub("[{}]", "", hata_metni)
      ))

      if (exists("cc_persist_run_result", mode = "function", inherits = TRUE)) {
        tryCatch(
          cc_persist_run_result(
            rv = ctx$rv,
            env = list(
              prompt = ctx$prompt,
              tum_satirlar = character(0),
              calisma_dizini = ctx$workdir,
              kaynak_calisma_dizini = ctx$workdir
            ),
            status = "failed",
            final_output = paste0("Çalışma alanı hazırlığı başarısız: ", hata_metni)
          ),
          error = function(e2) NULL
        )
      }

      cc_fail_run_preparation(
        ctx,
        paste0("Çalışma alanı hazırlanamadı: ", hata_metni)
      )

      NULL
    })

  invisible(TRUE)
}

#' Hazırlık tamamlandıktan sonra Claude Code sürecini başlat
#'
#' @param ctx Çalıştırma bağlamı
#' @param prep cc_prepare_run_workspace() sonucu
#' @return invisible(TRUE/FALSE)
cc_start_streaming_run <- function(ctx, prep) {
  session <- ctx$session
  ns <- ctx$ns
  rv <- ctx$rv
  lease_handed_off <- FALSE
  on.exit({
    if (!isTRUE(lease_handed_off)) {
      cc_release_runtime_lease(prep$runtime_lease %||% "")
    }
  }, add = TRUE)

  if (isTRUE(prep$snapshot_truncated)) {
    cc_release_runtime_lease(prep$runtime_lease %||% "")
    mesaj <- paste0(
      "Çıktı alanının başlangıç taraması güvenli sınırlar içinde tamamlanamadı; ",
      "eksik dosya aktarımını önlemek için çalışma başlatılmadı."
    )
    cc_log_warn(paste(CLAUDE_CODE_LOG_PREFIX, "[OUTPUT_SNAPSHOT]", mesaj))
    cc_fail_run_preparation(ctx, mesaj)
    return(invisible(FALSE))
  }

  dokuman_baglami <- prep$document_context %||% list()
  kaynak_calisma_dizini <- prep$source_workdir %||% ctx$workdir
  calisma_dizini <- prep$effective_workdir %||% prep$runtime_workdir %||% ctx$workdir
  mirror_kullanildi <- isTRUE(prep$mirrored)

  if (isTRUE(mirror_kullanildi)) {
    rv$active_runtime_workdir <- prep$runtime_workdir
    rv$active_runtime_source <- ctx$workdir
  }

  if (nzchar(prep$limit_notice %||% "")) {
    showNotification(prep$limit_notice, type = "warning", duration = 8)
  }

  # Aşama bildirimi gerçekleşen işi yansıtır: girdi aktarımı yalnızca gerçekten
  # dosya kopyalandığında raporlanır.
  if (length(prep$selection$files %||% character(0)) > 0L) {
    cc_send_run_stage(session, ns, "girdi")

    cc_log_info(sprintf(
      "%s [BOUNDED_SCAN] request=%s | taranan_dosya=%s | taranan_dizin=%s | kesildi=%s (%s)",
      CLAUDE_CODE_LOG_PREFIX,
      ctx$run_request_id,
      as.character(prep$metrics$scan$file_count %||% ""),
      as.character(prep$metrics$scan$dir_count %||% ""),
      isTRUE(prep$metrics$scan$truncated),
      as.character(prep$metrics$scan$truncated_reason %||% "")
    ))
  }

  if (isTRUE(dokuman_baglami$text_sidecars_ready)) {
    cc_send_run_stage(session, ns, "dokuman")

    # Doküman destek dizini yalnızca düz metin çıkarımları içerir; kaynak
    # klasöre geri aktarım yapılmaz.
    mirror_kullanildi <- FALSE

    showNotification(
      paste0(
        length(dokuman_baglami$prepared_files %||% list()),
        " doküman için yerel metin çıkarımı hazırlandı."
      ),
      type = "message",
      duration = 5
    )

    cc_log_info(sprintf(
      "%s [DOCUMENT_PREPARE] hazir=%d | sure_ms=%.0f | destek=%s",
      CLAUDE_CODE_LOG_PREFIX,
      length(dokuman_baglami$prepared_files %||% list()),
      prep$metrics$document_ms %||% 0,
      dokuman_baglami$support_dir %||% ""
    ))
  }

  model_cozumu <- if (isTRUE(dokuman_baglami$has_binary_docs)) {
    list(
      allow_run = TRUE,
      model = ctx$model,
      fallback_used = FALSE,
      reason = "",
      selected_model = ctx$model
    )
  } else {
    resolve_claude_code_execution_model(
      selected_model = ctx$model,
      prompt = ctx$prompt,
      workdir = kaynak_calisma_dizini %||% calisma_dizini,
      document_context = dokuman_baglami
    )
  }

  if (!isTRUE(model_cozumu$allow_run)) {
    cc_release_runtime_lease(prep$runtime_lease %||% "")
    cc_fail_run_preparation(ctx, model_cozumu$reason)
    return(invisible(FALSE))
  }

  efektif_model <- model_cozumu$model %||% ctx$model

  if (!is.null(rv$current_runtime_model) &&
      !identical(rv$current_runtime_model, efektif_model)) {
    rv$cli_session_id <- NULL
    rv$conversation_context <- list()
    rv$active_runtime_workdir <- NULL
    rv$active_runtime_source <- NULL

    cc_log_info(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Çalıştırılan model değişti, CLI oturumu sıfırlandı. Yeni model:",
      efektif_model
    ))
  }

  rv$current_runtime_model <- efektif_model

  if (isTRUE(model_cozumu$fallback_used)) {
    showNotification(
      paste0(
        "Doküman uyumluluğu için geçici olarak düşünmeyen modele geçildi: ",
        efektif_model
      ),
      type = "warning",
      duration = 6
    )
  }

  if (exists("cc_persist_session_begin", mode = "function", inherits = TRUE)) {
    cc_persist_session_begin(
      rv = rv,
      user_id = ctx$user_id,
      prompt = ctx$prompt,
      workdir = ctx$workdir,
      source_workdir = kaynak_calisma_dizini,
      runtime_workdir = calisma_dizini,
      model = efektif_model,
      runtime_model = efektif_model,
      character_id = ctx$character_id
    )
  }

  # İkili doküman görevleri CLI yerine yerel özetleme yoluna gider.
  if (isTRUE(dokuman_baglami$has_binary_docs)) {
    cc_handle_document_summary_run(
      session = session,
      ns = ns,
      rv = rv,
      run_request_id = ctx$run_request_id,
      dokuman_baglami = dokuman_baglami,
      model = efektif_model,
      zaman_asimi = ctx$timeout,
      kaynak_calisma_dizini = kaynak_calisma_dizini,
      calisma_dizini = calisma_dizini,
      effective_user_id = ctx$user_id,
      kullanici_prompt = ctx$prompt,
      karakter = ctx$character,
      karakter_id = ctx$character_id,
      karakter_renk = ctx$accent,
      runtime_lease = prep$runtime_lease %||% "",
      finalize_streaming = ctx$finalize_streaming,
      observe_dir_contents = ctx$observe_dir_contents
    )
    lease_handed_off <- TRUE

    return(invisible(TRUE))
  }

  oturum_id <- rv$cli_session_id

  stream_env <- new.env(parent = emptyenv())
  stream_env$baslangic <- Sys.time()
  stream_env$zaman_asimi <- ctx$timeout
  stream_env$karakter_renk <- ctx$accent
  stream_env$karakter_adi <- ctx$character$display_name
  stream_env$karakter_id <- ctx$character_id
  stream_env$zaman_damgasi <- format(Sys.time(), "%H:%M:%S")
  stream_env$prompt <- ctx$prompt
  stream_env$calisma_dizini <- calisma_dizini
  stream_env$kaynak_calisma_dizini <- kaynak_calisma_dizini
  stream_env$mirror_kullanildi <- mirror_kullanildi
  stream_env$runtime_layout <- prep$layout
  stream_env$runtime_lease <- prep$runtime_lease %||% ""
  stream_env$user_id <- ctx$user_id
  stream_env$session_token <- session$token %||% format(Sys.time(), "%Y%m%d%H%M%S")
  stream_env$request_id <- ctx$run_request_id
  stream_env$tum_satirlar <- character(0)
  stream_env$durduruldu <- FALSE
  stream_env$oturum_id <- NULL
  stream_env$workdir_snapshot <- prep$snapshot %||% list()
  stream_env$cikti_islendi <- FALSE

  rv$stream_env <- stream_env
  rv$poll_state <- stream_env

  cli_args <- cc_policy_build_cli_args(
    prompt = prep$run_prompt %||% ctx$prompt,
    output_format = "stream-json",
    model = efektif_model,
    session_id = oturum_id,
    include_partial_messages = TRUE,
    verbose = TRUE,
    user_id = ctx$user_id,
    settings_data = ctx$settings_data,
    workdir = kaynak_calisma_dizini %||% calisma_dizini
  )

  cc_send_run_stage(session, ns, "model")

  tryCatch({
    cc_log_info(paste(CLAUDE_CODE_LOG_PREFIX, "[PROCESS_START] Canlı akış başlatılıyor"))

    komut <- build_processx_command(ctx$cli_path, cli_args, workdir = calisma_dizini)

    komut$env <- cc_apply_runtime_api_key_env(
      env = komut$env,
      api_key = ctx$api_key
    )

    proc <- processx::process$new(
      command = komut$command,
      args = komut$args,
      env = komut$env,
      wd = komut$wd %||% calisma_dizini,
      stdout = "|",
      stderr = "|",
      cleanup = TRUE,
      cleanup_tree = TRUE,
      windows_verbatim_args = isTRUE(komut$windows_verbatim_args)
    )

    rv$active_process <- proc
    lease_handed_off <- TRUE
    cc_send_run_stage(session, ns, "calisiyor")

  }, error = function(e) {
    hata_metni <- conditionMessage(e)
    log_error(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Akış başlatma hatası:",
      gsub("[{}]", "", hata_metni)
    ))

    if (exists("cc_persist_run_result", mode = "function", inherits = TRUE)) {
      cc_persist_run_result(
        rv = rv,
        env = stream_env,
        status = "failed",
        final_output = paste0("Akış başlatma hatası: ", hata_metni),
        exit_code = NA_integer_,
        duration = as.numeric(difftime(Sys.time(), stream_env$baslangic, units = "secs")),
        tool_uses = list(),
        downloads = list(),
        cli_session_id = oturum_id
      )
    }

    cc_fail_run_preparation(
      ctx,
      paste0("Beklenmeyen hata: ", hata_metni)
    )
  })

  invisible(TRUE)
}
