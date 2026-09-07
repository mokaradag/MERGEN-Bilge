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
    "cc_output_sync_skipped_results",
    "cc_runtime_zone_of_path",
    "cc_filter_download_candidates",
    "cc_with_path_visibility_budget",
    "cc_path_visibility_budget_remaining",
    ".cc_path_visibility_budget",
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
    active_guard = env$output_sync_guard %||% "",
    # İndirme kökü worker'a AÇIKÇA taşınır: mergen.claude_code_download_root
    # seçeneği yalnızca ana süreçte tanımlıdır ve worker'da getwd() tabanlı
    # yanlış bir klasöre düşülüyordu.
    download_root = tryCatch(
      if (exists("get_claude_code_download_root", mode = "function", inherits = TRUE)) {
        get_claude_code_download_root()
      } else {
        ""
      },
      error = function(e) ""
    ),
    limits = tryCatch(
      get("claude_code_runtime_limits", inherits = TRUE),
      error = function(e) list()
    )
  )
}

#' İndirme adaylarını onaylı runtime bölgelerine ve boyut sınırlarına göre süz
#'
#' Metadata (lease/manifest) ve doküman destek dosyaları kullanıcı indirmesi
#' değildir; onaylı çıktı alanı dışında kalan hiçbir aday staging'e girmez.
#' Boyut sınırları da kopyalama BAŞLAMADAN uygulanır; aksi halde tek bir dev
#' dosya worker'ı ve sunucu geçici diskini doldurabilir.
#'
#' @param paths Aday dosya yolları
#' @param layout Runtime düzeni (NULL ise bölge süzgeci uygulanmaz)
#' @param limits Sınır listesi
#' @return list(paths, rejected_zone, rejected_size)
cc_filter_download_candidates <- function(paths, layout = NULL, limits = NULL) {
  yollar <- unique(as.character(paths %||% character(0)))
  yollar <- yollar[nzchar(yollar)]

  bos <- list(paths = character(0), rejected_zone = character(0),
              rejected_size = character(0))
  if (!length(yollar)) return(bos)

  max_file_bytes <- cc_runtime_limit("max_output_file_bytes", 100 * 1024^2, limits)
  max_total_bytes <- cc_runtime_limit("max_output_total_bytes", 400 * 1024^2, limits)

  kabul <- character(0)
  bolge_red <- character(0)
  boyut_red <- character(0)
  toplam <- 0

  for (yol in yollar) {
    if (is.list(layout) && nzchar(as.character(layout$root %||% "")[1])) {
      bolge <- cc_runtime_zone_of_path(yol, layout)

      # Runtime düzeni içindeyken yalnızca onaylı bölgeler indirilebilir.
      # Düzenin tamamen dışındaki yollar (kaynak klasör) eski davranışta
      # olduğu gibi politika süzgecine bırakılır.
      if (nzchar(bolge) && !bolge %in% c("output", "input", "root")) {
        bolge_red <- c(bolge_red, yol)
        next
      }
    }

    boyut <- suppressWarnings(as.numeric(file.info(yol)$size[1]))
    if (!is.finite(boyut)) boyut <- 0

    if (boyut > max_file_bytes || toplam + boyut > max_total_bytes) {
      boyut_red <- c(boyut_red, yol)
      next
    }

    kabul <- c(kabul, yol)
    toplam <- toplam + boyut
  }

  list(
    paths = kabul,
    rejected_zone = unique(bolge_red),
    rejected_size = unique(boyut_red)
  )
}

#' Çalıştırma sonrası çıktı işlemesini arka planda BİR KEZ yürüt
#'
#' @param request cc_build_run_output_request() çıktısı
#' @return list(downloads, changed_files, sync_results, metrics)
cc_process_run_outputs <- function(request) {
  baslangic <- Sys.time()

  # Worker'da seçenek tanımsızdır; ana süreçten taşınan kök geri kurulur.
  # Worker'lar görevler arasında yeniden kullanılır: seçenek görev sonunda geri
  # alınmazsa, kökü boş gelen sonraki bir istek önceki çalıştırmanın kökünü
  # devralırdı.
  indirme_koku <- as.character(request$download_root %||% "")[1]
  if (!is.na(indirme_koku) && nzchar(indirme_koku)) {
    onceki_kok <- getOption("mergen.claude_code_download_root", NULL)
    options(mergen.claude_code_download_root = indirme_koku)
    on.exit(options(mergen.claude_code_download_root = onceki_kok), add = TRUE)
  }

  gecen_ms <- function(from) {
    round(as.numeric(difftime(Sys.time(), from, units = "secs")) * 1000, 1)
  }

  # Runtime output/build, output/dist ve output/bin gerçek çıktılardır. İzole
  # çalışma alanında kaynak-ağaç basename hariçlerini uygulamayız; yalnızca
  # dahili metadata/doküman alanları KÖK düzeyinde (exclude_rel_paths) tarama
  # dışında kalır. Basename eşleşmesi (exclude_dirs) "output/metadata" gibi
  # gerçek üretilmiş iç içe dizinleri de yanlışlıkla dışarıda bırakırdı.
  haric_dir <- character(0)
  haric_rel <- character(0)

  if (isTRUE(request$mirrored)) {
    haric_rel <- cc_scan_runtime_excluded_dirs()
  } else {
    haric_dir <- cc_scan_default_excluded_dirs()
  }

  # DEADLINE/İPTAL SİNYALİ: ana süreç zaman aşımında `active_guard` dosyasını
  # siler. Worker pahalı aşamalar ARASINDA bunu denetlemezse çalıştırma
  # kullanıcıya bitmiş görünürken worker havuzda meşgul kalmaya devam ediyordu.
  .iptal_edildi <- function() {
    g <- as.character(request$active_guard %||% "")[1]
    nzchar(g) && !isTRUE(file.exists(g))
  }
  if (.iptal_edildi()) {
    stop("Çıktı işleme iptal edildi (zaman aşımı veya yeni çalıştırma).", call. = FALSE)
  }

  diff_baslangic <- Sys.time()

  degisenler <- character(0)
  diff_kesildi <- FALSE
  diff_kesme_nedeni <- ""

  if (nzchar(request$runtime_workdir %||% "") && dir.exists(request$runtime_workdir)) {
    # Diff başarısızlığını boş değişiklik listesine dönüştürmeyin. Çağıran
    # promise catch'i bu hatayı kullanıcıya bildirir ve başarılı Claude çıkışını
    # yanlışlıkla "Tamamlandı" olarak sonlandırmaz.
    degisenler <- diff_claude_code_workdir_snapshot(
      before_snapshot = request$before_snapshot,
      workdir = request$runtime_workdir,
      exclude_dirs = haric_dir,
      exclude_rel_paths = haric_rel,
      limits = request$limits
    )

    # Çalıştırma SONRASI tarama da sınıra takılabilir. Bu durumda değişen
    # dosya listesi eksiktir; sessizce "Tamamlandı" göstermek üretilen
    # dosyaların kaybolmasını gizler.
    diff_tarama <- attr(degisenler, "scan", exact = TRUE)
    diff_kesildi <- isTRUE(diff_tarama$truncated)
    diff_kesme_nedeni <- as.character(diff_tarama$truncated_reason %||% "")[1]
    degisenler <- as.character(degisenler)
  }

  diff_ms <- gecen_ms(diff_baslangic)

  # Tarama kesildiyse `degisenler` EKSİKTİR; bu haliyle staging/sync
  # yapmak eksik bir alt kümeyi güvenilir gibi kaynak dizine aktarır. Çağıran
  # taraf zaten `output_scan_truncated` ile başarısız işaretleyecek.
  if (isTRUE(diff_kesildi)) {
    return(list(
      downloads = list(), changed_files = degisenler, sync_results = list(),
      output_scan_truncated = TRUE, output_scan_truncated_reason = diff_kesme_nedeni,
      metrics = list(
        total_ms = gecen_ms(baslangic), diff_ms = diff_ms, staging_ms = 0, sync_ms = 0,
        changed_count = length(degisenler), download_count = 0L, synced_count = 0L
      )
    ))
  }

  if (.iptal_edildi()) {
    stop("Çıktı işleme iptal edildi (zaman aşımı veya yeni çalıştırma).", call. = FALSE)
  }

  staging_baslangic <- Sys.time()

  indirmeler <- tryCatch(
    cc_with_path_visibility_budget(
      cc_collect_streaming_run_downloads(
        before_snapshot = request$before_snapshot,
        tool_uses = request$tool_uses,
        runtime_workdir = request$runtime_workdir,
        source_workdir = request$source_workdir,
        user_id = request$user_id,
        session_token = request$session_token,
        changed_files = degisenler,
        exclude_dirs = haric_dir,
        limits = request$limits,
        layout = request$layout,
        # İptal/deadline UZUN staging döngüsünün İÇİNDE de denetlenir; aksi
        # hâlde süre dolduktan sonra worker kopyalamaya devam ediyordu.
        cancel_fn = .iptal_edildi
      )
    ),
    error = function(e) list()
  )

  staging_ms <- gecen_ms(staging_baslangic)

  if (.iptal_edildi()) {
    stop("Çıktı işleme iptal edildi (zaman aşımı veya yeni çalıştırma).", call. = FALSE)
  }

  sync_baslangic <- Sys.time()
  sync_sonuclari <- list()

  if (isTRUE(request$mirrored)) {
    # Sistemik bir dosya sistemi/yol hatasını boş sonuca dönüştürmeyin;
    # aksi halde hiçbir dosya aktarılmadığı halde çalıştırma "Tamamlandı"
    # olarak sonlandırılabilir. Hatanın bu future'ı reddetmesine izin
    # verilir; çağıran promise catch'i bunu açık bir hata olarak raporlar.
    sync_sonuclari <- sync_claude_runtime_workdir_back(
      runtime_workdir = request$runtime_workdir,
      source_workdir = request$source_workdir,
      changed_files = degisenler,
      layout = request$layout,
      limits = request$limits,
      active_guard = request$active_guard
    )
  }

  sync_ms <- gecen_ms(sync_baslangic)

  list(
    downloads = indirmeler,
    changed_files = degisenler,
    sync_results = sync_sonuclari,
    output_scan_truncated = isTRUE(diff_kesildi),
    output_scan_truncated_reason = diff_kesme_nedeni,
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

    # Kapanmış oturumda websocket gönderimi HATA verir ve `then()` reddedilip
    # `catch()` dalına düşüyor; BAŞARIYLA tamamlanmış çalıştırma `failed` olarak
    # kalıcılaşıyordu. Gönderim korunur; kalıcılaştırma her durumda çalışır.
    try(session$sendCustomMessage(
      type = "cc-stream-end",
      message = list(
        target = ns("output_area"),
        duration = sure,
        finalContent = son_icerik,
        finalToolUsesHtml = son_arac_kullanim_html,
        accentColor = env$karakter_renk,
        characterName = env$karakter_adi
      )
    ), silent = TRUE)

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

    # Kapanmış oturumda `finalize_streaming()` kendi `sendCustomMessage()`
    # çağrılarından hata fırlatıyor; hata `cc_finish_streaming_run()` dışına
    # yayılınca `rv$output_history` güncellemesi ve dosya yöneticisi yenilemesi
    # HİÇ çalışmıyordu (promise `catch()` de `rv$active_request_id` temizlendiği
    # için ikinci bir başarısızlık raporlamıyor).
    try(cc_finalize_if_active(
      rv = rv,
      request_id = env$request_id,
      finalize_streaming = ctx$finalize_streaming,
      durum_metin = "Tamamlandı",
      durum_ikon = "check-circle",
      durum_renk = "#81C784",
      sure = sure
    ), silent = TRUE)
  } else {
    hata_mesaji <- ctx$hata_mesaji %||% ""

    log_warn(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Akış hata kodu:",
      cikis_kodu,
      "- Mesaj:",
      gsub("[{}]", "", substr(hata_mesaji, 1, 200))
    ))

    # Kapalı oturumda UI gönderimi hata verir; kalıcılaştırma ve sonlandırma
    # her durumda çalışmalıdır (bkz. cc_report_output_processing_failure).
    try({
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
    }, silent = TRUE)

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

    # Aynı kapalı-oturum koruması hata dalında da geçerlidir.
    try(cc_finalize_if_active(
      rv = rv,
      request_id = env$request_id,
      finalize_streaming = ctx$finalize_streaming,
      durum_metin = "Hata",
      durum_ikon = "exclamation-triangle",
      durum_renk = "#E57373",
      sure = sure
    ), silent = TRUE)
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
