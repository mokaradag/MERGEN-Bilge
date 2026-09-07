# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_run_prepare_task.R
# Açıklama: Bilge Yolaç çalıştırma hazırlığının arka plan (worker) tarafı.
#           Sınırlı kaynak taraması, gerekli girdi dosyalarının seçimi ve
#           kopyalanması, doküman metin çıkarımı ve çalıştırma öncesi çıktı
#           anlık görüntüsü burada yürütülür.
#
#           KRİTİK: Bu dosyadaki fonksiyonlar Shiny session, reaktif değer,
#           süreç tanıtıcısı veya DB bağlantısı ALMAZ. Yalnızca serileştirilebilir
#           düz veri alır ve düz veri döndürür; böylece ana Shiny süreci büyük
#           klasör hazırlığı sırasında diğer oturumlara yanıt vermeye devam eder.
# ==============================================================================

.cc_prepare_worker_cache <- new.env(parent = emptyenv())

#' Hazırlık worker'ına aktarılacak global paketi (bir kez) oluştur
#'
#' Bağımlılık taraması her gönderimde değil, süreç başına bir kez yapılır;
#' böylece gönderim anında ana olay döngüsü bloke olmaz.
#'
#' @param refresh Önbelleği yenile
#' @param envir Aranacak ortam
#' @return Worker'a aktarılacak isimlendirilmiş global listesi
cc_run_prepare_worker_globals <- function(refresh = FALSE,
                                          envir = globalenv()) {
  if (!isTRUE(refresh) && !is.null(.cc_prepare_worker_cache$globals)) {
    return(.cc_prepare_worker_cache$globals)
  }

  wanted <- c(
    "cc_prepare_run_workspace",
    "cc_prepare_run_prompt_note",
    "cc_runtime_owner_file",
    "cc_claim_runtime_ownership",
    "cc_runtime_ownership_is",
    "cc_acquire_reused_runtime_lease",
    ".cc_runtime_workdir_reusable",
    "prepare_claude_runtime_workdir",
    "prepare_claude_code_document_context",
    "cc_snapshot_run_output_area",
    "cc_cleanup_stale_runtime_dirs",
    "cc_reclaim_orphaned_runtime_dirs",
    "cc_with_runtime_cleanup_lock",
    "cc_runtime_cleanup_lock_dir",
    "CC_RUNTIME_LOCK_DIR_NAME",
    ".cc_codex_acquire_dir_lock",
    ".cc_codex_reap_dir_lock",
    ".cc_codex_lock_owner_token",
    ".cc_codex_touch_dir_lock",
    ".cc_codex_dir_lock_age",
    ".CC_CODEX_REAPER_STALE_SEC",
    "cc_cleanup_stale_document_support_dirs",
    "claude_code_runtime_limits",
    "claude_code_config",
    "CLAUDE_CODE_LOG_PREFIX",
    "CLAUDE_CODE_LIMIT_MESSAGE"
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

  .cc_prepare_worker_cache$globals <- bundle
  bundle
}

#' Hazırlık isteğini düz veri olarak oluştur
#'
#' @return Worker'a güvenle serileştirilebilir liste
cc_build_run_prepare_request <- function(prompt,
                                         workdir,
                                         user_id,
                                         request_id,
                                         existing_runtime_workdir = NULL,
                                         explicit_files = character(0),
                                         limits = NULL) {
  list(
    prompt = as.character(prompt %||% "")[1],
    workdir = as.character(workdir %||% "")[1],
    user_id = suppressWarnings(as.integer(user_id %||% 0L)),
    request_id = as.character(request_id %||% "")[1],
    existing_runtime_workdir = as.character(existing_runtime_workdir %||% "")[1],
    explicit_files = as.character(explicit_files %||% character(0)),
    limits = limits %||% tryCatch(
      get("claude_code_runtime_limits", inherits = TRUE),
      error = function(e) list()
    )
  )
}

#' İzole runtime düzeni kullanıldığında modele çalışma alanı notunu ekle
#'
#' @param prompt Kullanıcı metni
#' @param layout Runtime düzeni
#' @param selection Girdi seçim sonucu
#' @param limited Klasör sınırları aşıldı mı
#' @return Zenginleştirilmiş prompt
cc_prepare_run_prompt_note <- function(prompt,
                                       layout,
                                       selection = NULL,
                                       limited = FALSE) {
  if (!is.list(layout) || !nzchar(layout$input %||% "")) {
    return(prompt)
  }

  satirlar <- c(
    "SİSTEM ÇALIŞMA NOTU:",
    "Bu çalışma izole bir yerel çalışma alanında yürütülüyor.",
    paste0("Görev için gereken girdi dosyaları şu klasöre kopyalandı: ", layout$input),
    paste0("Ürettiğin dosyaları şu klasöre yaz: ", layout$output),
    "Kaynak klasörün tamamı kopyalanmadı; yalnızca gerekli dosyalar aktarıldı."
  )

  if (isTRUE(limited)) {
    satirlar <- c(
      satirlar,
      "Kaynak klasör güvenli çalışma sınırlarını aştığı için sınırlı bir alt küme aktarıldı."
    )
  }

  if (is.list(selection) && length(selection$relatives %||% character(0))) {
    satirlar <- c(
      satirlar,
      "Aktarılan dosyalar:",
      paste0("- ", selection$relatives)
    )
  }

  paste(
    c(satirlar, "", "KULLANICININ ASIL İSTEĞİ:", enc2utf8(prompt %||% "")),
    collapse = "\n"
  )
}

# --- Yeniden kullanılan runtime sahipliği --------------------------------------
# Aynı runtime klasörü takip eden sorularda yeniden kullanılır (CLI --resume).
# Eski bir hazırlık worker'ı iptal edilse bile arka planda kopyalamaya devam
# edebilir. Sahiplik işareti ANA süreçte, gönderim anında yazılır; worker
# yazmadan önce ve dönmeden önce hâlâ sahip olduğunu doğrular. Böylece stale
# worker yeni çalışmanın girdilerini/snapshot'ını ezemez.

cc_runtime_owner_file <- function(runtime_workdir) {
  yol <- as.character(runtime_workdir %||% "")[1]
  if (is.na(yol) || !nzchar(yol)) return("")
  file.path(yol, "metadata", "runtime-owner")
}

#' Yeniden kullanılan runtime'ın sahipliğini bu isteğe devret
#'
#' @param runtime_workdir Yeniden kullanılacak runtime kökü
#' @param request_id Aktif çalıştırma kimliği
#' @return Sahiplik dosyası yolu veya ""
cc_claim_runtime_ownership <- function(runtime_workdir, request_id) {
  yol <- cc_runtime_owner_file(runtime_workdir)
  if (!nzchar(yol)) return("")

  dir.create(dirname(yol), recursive = TRUE, showWarnings = FALSE)

  ok <- tryCatch({
    writeLines(as.character(request_id %||% "")[1], yol, useBytes = TRUE)
    TRUE
  }, error = function(e) FALSE)

  if (!isTRUE(ok)) "" else yol
}

#' Runtime sahipliği hâlâ bu isteğe mi ait?
#'
#' @param runtime_workdir Runtime kökü
#' @param request_id Aktif çalıştırma kimliği
#' @return Sahiplik işareti yoksa veya eşleşiyorsa TRUE
cc_runtime_ownership_is <- function(runtime_workdir, request_id) {
  yol <- cc_runtime_owner_file(runtime_workdir)
  if (!nzchar(yol) || !isTRUE(file.exists(yol))) return(TRUE)

  sahip <- tryCatch(
    as.character(readLines(yol, warn = FALSE))[1],
    error = function(e) NA_character_
  )

  if (is.na(sahip) || !nzchar(sahip)) return(TRUE)

  identical(sahip, as.character(request_id %||% "")[1])
}

# Yeniden kullanılan runtime, tarama/kopyalama başlamadan önce başka bir
# oturumun stale temizliğine karşı korunmalıdır.
cc_acquire_reused_runtime_lease <- function(existing_runtime_workdir,
                                            user_id,
                                            request_id) {
  if (!isTRUE(.cc_runtime_workdir_reusable(existing_runtime_workdir, user_id))) {
    return("")
  }

  metadata_dir <- file.path(existing_runtime_workdir, "metadata")
  lease <- file.path(
    metadata_dir,
    paste0("active-run-", gsub("[^A-Za-z0-9_.-]", "_", request_id), ".lease")
  )

  # Lease EDİNİMİ temizlikle AYNI kilit altında yapılır: aksi hâlde temizlik
  # "lease yok" görüp aday dizini silerken biz lease'i oluşturuyor ve AKTİF
  # çalışma alanı altımızdan kaldırılıyordu (TOCTOU).
  olustu <- cc_with_runtime_cleanup_lock(existing_runtime_workdir, fallback = FALSE, {
    dir.create(metadata_dir, recursive = TRUE, showWarnings = FALSE)
    isTRUE(file.create(lease))
  })

  if (!isTRUE(olustu)) {
    stop("Yeniden kullanılan runtime için aktif çalışma lease'i oluşturulamadı.",
         call. = FALSE)
  }

  lease
}

#' Bilge Yolaç çalıştırma hazırlığını arka planda yürüt
#'
#' @param request cc_build_run_prepare_request() çıktısı
#' @return Düz veri hazırlık sonucu
cc_prepare_run_workspace <- function(request) {
  baslangic <- Sys.time()
  runtime_lease <- cc_acquire_reused_runtime_lease(
    existing_runtime_workdir = request$existing_runtime_workdir %||% "",
    user_id = request$user_id,
    request_id = request$request_id
  )
  lease_handed_off <- FALSE
  on.exit({
    if (!isTRUE(lease_handed_off) && nzchar(runtime_lease)) {
      unlink(runtime_lease, force = TRUE)
    }
  }, add = TRUE)

  gecen_ms <- function(from) {
    round(as.numeric(difftime(Sys.time(), from, units = "secs")) * 1000, 1)
  }

  yeniden_kullanilan <- as.character(request$existing_runtime_workdir %||% "")[1]

  # Sahipliği kaybettiysek (yeni bir çalışma aynı runtime'ı devraldı) hiçbir
  # dosya yazmadan çekiliriz; aksi halde yeni çalışmanın girdileri bozulur.
  sahiplik_dogrula <- function(asama) {
    if (!nzchar(yeniden_kullanilan)) return(invisible(TRUE))
    if (isTRUE(cc_runtime_ownership_is(yeniden_kullanilan, request$request_id))) {
      return(invisible(TRUE))
    }
    stop(
      paste0(
        "Yeniden kullanılan çalışma alanı başka bir çalıştırmaya devredildi (",
        asama, "); bu hazırlık iptal edildi."
      ),
      call. = FALSE
    )
  }

  sahiplik_dogrula("baslangic")

  limits <- request$limits %||% list()

  runtime_baslangic <- Sys.time()

  runtime <- prepare_claude_runtime_workdir(
    workdir = request$workdir,
    user_id = request$user_id,
    runtime_token = request$request_id,
    existing_runtime_workdir = if (nzchar(request$existing_runtime_workdir %||% "")) {
      request$existing_runtime_workdir
    } else {
      NULL
    },
    prompt = request$prompt,
    explicit_files = request$explicit_files,
    limits = limits,
    ownership_guard = function() sahiplik_dogrula("girdi_kopyalama")
  )

  runtime_ms <- gecen_ms(runtime_baslangic)

  sahiplik_dogrula("girdi_kopyalama")

  mirrored <- isTRUE(runtime$mirrored)
  layout <- runtime$layout
  source_workdir <- runtime$source_workdir %||% request$workdir
  runtime_workdir <- runtime$runtime_workdir %||% request$workdir

  preflight <- runtime$preflight %||% list(limited = FALSE, message = "")

  # Doküman algılama: izole düzende dokümanlar input klasörüne kopyalanır.
  dokuman_kaynagi <- if (isTRUE(mirrored) && is.list(layout)) layout$input else runtime_workdir

  dokuman_baslangic <- Sys.time()

  dokuman_baglami <- tryCatch(
    prepare_claude_code_document_context(
      prompt = request$prompt,
      runtime_workdir = dokuman_kaynagi,
      source_workdir = source_workdir,
      user_id = request$user_id,
      request_id = request$request_id,
      explicit_files = request$explicit_files,
      support_base_dir = if (is.list(layout)) layout$document_support else NULL,
      limits = limits
    ),
    error = function(e) {
      list(
        prompt = request$prompt,
        document_task_detected = FALSE,
        has_binary_docs = FALSE,
        text_sidecars_ready = FALSE,
        prepared_files = list(),
        unsupported_files = character(0),
        extraction_errors = paste("Doküman hazırlığı başarısız:", conditionMessage(e)),
        manifest_path = "",
        reader_template_path = "",
        support_dir = "",
        effective_workdir = dokuman_kaynagi,
        inline_payload = ""
      )
    }
  )

  dokuman_ms <- gecen_ms(dokuman_baslangic)

  # Çalıştırma promptu: doküman bağlamı varsa onun promptu, aksi halde izole
  # çalışma alanı notu eklenmiş kullanıcı promptu kullanılır.
  calistirma_promptu <- dokuman_baglami$prompt %||% request$prompt

  if (isTRUE(mirrored) && !isTRUE(dokuman_baglami$text_sidecars_ready)) {
    calistirma_promptu <- cc_prepare_run_prompt_note(
      prompt = calistirma_promptu,
      layout = layout,
      selection = runtime$selection,
      limited = isTRUE(preflight$limited)
    )
  }

  etkin_workdir <- if (isTRUE(dokuman_baglami$text_sidecars_ready)) {
    dokuman_baglami$effective_workdir %||% dokuman_baglami$support_dir %||% runtime_workdir
  } else {
    runtime_workdir
  }

  snapshot_baslangic <- Sys.time()

  snapshot <- cc_snapshot_run_output_area(
    runtime_workdir = etkin_workdir,
    mirrored = mirrored,
    limits = limits
  )

  snapshot_ms <- gecen_ms(snapshot_baslangic)

  sahiplik_dogrula("snapshot")

  snapshot_scan <- attr(snapshot, "scan", exact = TRUE)

  # A per-runtime lease is visible to every Shiny session/worker. Stale
  # cleanup must never remove a runtime while another session owns it.
  if (!isTRUE(mirrored) || !isTRUE(runtime$reused)) {
    if (nzchar(runtime_lease)) unlink(runtime_lease, force = TRUE)
    runtime_lease <- ""
  }
  if (isTRUE(mirrored) && !nzchar(runtime_lease) &&
      is.list(layout) && nzchar(layout$metadata %||% "")) {
    aday_lease <- file.path(
      layout$metadata,
      paste0("active-run-", gsub("[^A-Za-z0-9_.-]", "_", request$request_id), ".lease")
    )
    # Lease edinimi temizlikle AYNI kilit altında serileştirilir.
    lease_olustu <- cc_with_runtime_cleanup_lock(layout$root %||% runtime_workdir,
                                                 fallback = FALSE, {
      dir.create(layout$metadata, recursive = TRUE, showWarnings = FALSE)
      isTRUE(file.create(aday_lease))
    })
    runtime_lease <- if (isTRUE(lease_olustu)) aday_lease else ""
  }

  # Eskimiş runtime/doküman destek klasörlerini yaşa göre temizle; aktif
  # çalışmanın klasörleri korunur.
  tryCatch(
    cc_cleanup_stale_runtime_dirs(
      user_id = request$user_id,
      keep_paths = c(runtime_workdir, if (is.list(layout)) layout$root else NULL)
    ),
    error = function(e) NULL
  )

  # AYRI KURTARMA ADIMI: rutin temizlik lease taşıyan çalışma alanını asla
  # silmez; çöken bir süreçten kalan lease'i yalnızca bu işlem, tüm tutucuların
  # bıraktığını doğruladıktan sonra geri kazanır.
  tryCatch(
    cc_reclaim_orphaned_runtime_dirs(
      user_id = request$user_id,
      keep_paths = c(runtime_workdir, if (is.list(layout)) layout$root else NULL)
    ),
    error = function(e) NULL
  )

  tryCatch(
    cc_cleanup_stale_document_support_dirs(
      user_id = request$user_id,
      keep_paths = c(dokuman_baglami$support_dir %||% "")
    ),
    error = function(e) NULL
  )

  result <- list(
    ok = TRUE,
    blocked = FALSE,
    message = "",
    limit_notice = if (isTRUE(preflight$limited)) preflight$message %||% "" else "",
    runtime_workdir = runtime_workdir,
    source_workdir = source_workdir,
    effective_workdir = etkin_workdir,
    mirrored = mirrored,
    reused = isTRUE(runtime$reused),
    layout = layout,
    selection = runtime$selection,
    preflight = preflight,
    document_context = dokuman_baglami,
    run_prompt = calistirma_promptu,
    snapshot = snapshot,
    snapshot_truncated = isTRUE(snapshot_scan$truncated),
    runtime_lease = runtime_lease,
    metrics = list(
      total_ms = gecen_ms(baslangic),
      runtime_ms = runtime_ms,
      document_ms = dokuman_ms,
      snapshot_ms = snapshot_ms,
      scan = runtime$scan_metrics,
      input_files = length(runtime$selection$files %||% character(0)),
      input_bytes = runtime$selection$total_bytes %||% 0,
      selection_mode = runtime$selection$selection_mode %||% "",
      snapshot_files = length(snapshot)
    )
  )
  lease_handed_off <- TRUE
  result
}
