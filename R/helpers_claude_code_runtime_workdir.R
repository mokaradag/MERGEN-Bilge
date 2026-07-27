# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_runtime_workdir.R
# Açıklama: Bilge Yolaç için kullanıcı çalışma alanı ve Windows/UNC/Unicode
#           çalışma dizini hazırlığı.
#
#           Claude Code CLI Windows VM üzerinde UNC veya ASCII dışı çalışma
#           dizinlerinde kararsız çalıştığı için bu durumlarda izole bir yerel
#           runtime çalışma alanı hazırlanır. Runtime alanı `input`, `output`,
#           `metadata` ve `document_support` bölmelerinden oluşur; kaynak
#           klasörün TAMAMI asla özyinelemeli olarak kopyalanmaz. Yalnızca
#           göreve gerçekten gereken girdi dosyaları `input` altına aktarılır.
#           Runtime dizini çalışma başına benzersizdir; böylece aynı kullanıcının
#           eşzamanlı veya hızlı ardışık çalıştırmaları birbirini bozmaz.
# ==============================================================================

get_user_workspace <- function(user_id, base_dir = NULL) {
  if (is.null(base_dir) || !nzchar(base_dir)) {
    base_dir <- file.path(tempdir(), "claude_code_workspaces")
  }

  user_dir <- file.path(base_dir, paste0("user_", user_id))

  if (!dir.exists(user_dir)) {
    dir.create(user_dir, recursive = TRUE, showWarnings = FALSE)
    log_info(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Kullanıcı çalışma alanı oluşturuldu:",
      user_dir
    ))
  }

  normalizePath(user_dir, mustWork = FALSE)
}
is_problematic_windows_workdir <- function(path) {
  if (.Platform$OS.type != "windows") return(FALSE)
  if (is.null(path) || !nzchar(path)) return(FALSE)

  aday <- gsub("\\", "/", as.character(path[1]), fixed = TRUE)

  unc_mi <- if (exists("is_windows_unc_path", mode = "function", inherits = TRUE)) {
    is_windows_unc_path(aday)
  } else {
    grepl("^//[^/]+/[^/]+", aday) ||
      (
        grepl("^/[^/]", aday) &&
          !grepl("^/(tmp|temp|var|home|usr|opt|etc|bin|sbin|mnt|media|proc|sys|dev|run)(/|$)",
                 tolower(aday),
                 perl = TRUE)
      )
  }

  ascii_disi_var_mi <- grepl("[^ -~]", enc2utf8(aday), perl = TRUE)

  isTRUE(unc_mi || ascii_disi_var_mi)
}

#' Gerekli girdi dosyalarını yerel runtime input klasörüne aktar
#'
#' Klasörün tamamı özyinelemeli olarak kopyalanmaz; sınırlı tarama sonucundan
#' seçilen dosyalar göreli yapısı korunarak aktarılır.
#'
#' @param source_dir Kaynak dizin
#' @param target_dir Hedef input dizini
#' @param prompt Kullanıcı metni (dosya adı çıkarımı için)
#' @param explicit_files Açıkça seçilmiş dosyalar
#' @param limits Sınır listesi
#' @param scan Hazır tarama sonucu (yeniden taramayı önlemek için)
#' @return list(ok, selection, copy, scan)
mirror_directory_to_local_workspace <- function(source_dir,
                                                target_dir,
                                                prompt = NULL,
                                                explicit_files = character(0),
                                                limits = NULL,
                                                scan = NULL) {
  if (!dir.exists(target_dir)) {
    dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)
  }

  if (is.null(scan) || !is.list(scan)) {
    scan <- cc_scan_source_workdir(source_dir, limits = limits)
  }

  secim <- cc_select_input_files(
    prompt = prompt,
    files = scan$files,
    file_sizes = scan$file_sizes,
    root = scan$root %||% source_dir,
    explicit_files = explicit_files,
    limits = limits
  )

  kopya <- cc_copy_files_to_runtime_input(
    files = secim$files,
    relatives = secim$relatives,
    input_dir = target_dir
  )

  basarisiz <- as.character(kopya$failed %||% character(0))

  list(
    ok = !length(basarisiz),
    selection = secim,
    copy = kopya,
    scan = scan,
    message = if (length(basarisiz)) {
      paste0("Gerekli girdi dosyaları kopyalanamadı: ", paste(basarisiz, collapse = ", "))
    } else {
      ""
    }
  )
}

.cc_runtime_workdir_token <- function(runtime_token = NULL) {
  token <- as.character(runtime_token %||% "")[1]
  if (is.na(token)) {
    token <- ""
  }

  if (!nzchar(token)) {
    token <- paste0(
      format(Sys.time(), "%Y%m%d%H%M%OS6"),
      "_",
      sprintf("%04d", sample.int(10000L, 1L) - 1L)
    )
  }

  token <- gsub("[^A-Za-z0-9_.-]+", "_", token, perl = TRUE)
  token <- gsub("^_+|_+$", "", token, perl = TRUE)

  if (!nzchar(token)) {
    token <- paste0(
      format(Sys.time(), "%Y%m%d%H%M%OS6"),
      "_",
      sprintf("%04d", sample.int(10000L, 1L) - 1L)
    )
  }

  paste0("run_", token)
}

# Var olan runtime workdir aynı kullanıcı kovasında ve aynı kaynak için
# yeniden kullanılabilir mi? Claude CLI oturum kimliği (--resume) runtime
# çalışma dizinine göre saklandığı için takip eden sorularda aynı klasörü
# yeniden kullanmak oturum sürekliliğini korur.
.cc_runtime_workdir_reusable <- function(existing_runtime_workdir, user_id = NULL) {
  yol <- as.character(existing_runtime_workdir %||% "")[1]
  if (is.na(yol) || !nzchar(yol)) return(FALSE)

  yol_slash <- gsub("\\", "/", yol, fixed = TRUE)

  beklenen_kullanici_segmenti <- paste0(
    "/claude_code_runtime/user_",
    as.character(user_id %||% "default"),
    "/"
  )

  if (!grepl(beklenen_kullanici_segmenti, yol_slash, fixed = TRUE)) {
    return(FALSE)
  }

  isTRUE(tryCatch(dir.exists(yol), error = function(e) FALSE))
}

.cc_runtime_prepare_result <- function(workdir,
                                       source_dir = NULL,
                                       mirrored = FALSE,
                                       reused = FALSE,
                                       layout = NULL,
                                       selection = NULL,
                                       preflight = NULL,
                                       scan = NULL) {
  list(
    runtime_workdir = workdir,
    source_workdir = source_dir %||% workdir,
    mirrored = isTRUE(mirrored),
    reused = isTRUE(reused),
    layout = layout,
    selection = selection,
    preflight = preflight,
    scan_metrics = if (is.list(scan)) {
      list(
        file_count = scan$file_count,
        dir_count = scan$dir_count,
        total_bytes = scan$total_bytes,
        elapsed_ms = scan$elapsed_ms,
        truncated = isTRUE(scan$truncated),
        truncated_reason = scan$truncated_reason
      )
    } else {
      NULL
    }
  )
}

# Problemli ağ/Unicode dizinlerini izole yerel runtime alanına hazırlar.
# existing_runtime_workdir verilirse ve aynı kullanıcı kovası altında geçerli
# bir klasörse yeniden kullanılır; bu sayede Claude CLI --resume oturumu
# takip eden sorularda kaybolmaz. Yeniden kullanımda kaynak klasör yeniden
# aynalanmaz; yalnızca gerekli girdi dosyaları tazelenir.
prepare_claude_runtime_workdir <- function(workdir,
                                           user_id = NULL,
                                           runtime_token = NULL,
                                           existing_runtime_workdir = NULL,
                                           prompt = NULL,
                                           explicit_files = character(0),
                                           limits = NULL) {
  if (is.null(workdir) || !nzchar(workdir)) {
    return(.cc_runtime_prepare_result(workdir))
  }

  original_workdir <- as.character(workdir %||% "")[1]

  source_dir <- resolve_claude_runtime_source_dir(original_workdir)

  if (!nzchar(source_dir)) {
    # Problemli ağ yolu algılandıysa CLI'a doğrudan göndermeyelim;
    # ama gerçek dizin çözülemediği için kullanıcıya açık bir log bırakalım.
    if (isTRUE(is_problematic_windows_workdir(original_workdir))) {
      cc_log_warn(paste(
        CLAUDE_CODE_LOG_PREFIX,
        "Problemli çalışma dizini algılandı ancak yerel hazırlık için çözülemedi:",
        original_workdir
      ))
    }

    return(.cc_runtime_prepare_result(workdir))
  }

  problemli_mi <- isTRUE(is_problematic_windows_workdir(original_workdir)) ||
    isTRUE(is_problematic_windows_workdir(source_dir))

  tarama <- cc_scan_source_workdir(source_dir, limits = limits)
  preflight <- cc_evaluate_workdir_preflight(tarama, limits = limits)

  cc_log_info(sprintf(
    "%s [WORKDIR_PREFLIGHT] dosya=%d | dizin=%d | bayt=%.0f | sure_ms=%.0f | kesildi=%s | sinirli=%s",
    CLAUDE_CODE_LOG_PREFIX,
    tarama$file_count, tarama$dir_count, tarama$total_bytes,
    tarama$elapsed_ms, isTRUE(tarama$truncated), isTRUE(preflight$limited)
  ))

  if (!isTRUE(problemli_mi) && !isTRUE(preflight$limited)) {
    return(.cc_runtime_prepare_result(
      workdir = source_dir,
      source_dir = source_dir,
      preflight = preflight,
      scan = tarama
    ))
  }

  reuse_mi <- isTRUE(.cc_runtime_workdir_reusable(existing_runtime_workdir, user_id))

  runtime_kok <- if (isTRUE(reuse_mi)) {
    normalizePath(existing_runtime_workdir, winslash = "/", mustWork = FALSE)
  } else {
    aday <- file.path(
      cc_runtime_user_dir(user_id),
      .cc_runtime_workdir_token(runtime_token)
    )
    dir.create(aday, recursive = TRUE, showWarnings = FALSE)
    normalizePath(aday, winslash = "/", mustWork = FALSE)
  }

  duzen <- cc_runtime_ensure_layout(list(
    root = runtime_kok,
    input = file.path(runtime_kok, "input"),
    output = file.path(runtime_kok, "output"),
    metadata = file.path(runtime_kok, "metadata"),
    document_support = file.path(runtime_kok, "document_support")
  ))

  aktarim <- mirror_directory_to_local_workspace(
    source_dir = source_dir,
    target_dir = duzen$input,
    prompt = prompt,
    explicit_files = explicit_files,
    limits = limits,
    scan = tarama
  )

  cc_log_info(sprintf(
    "%s [INPUT_COPY] mod=%s | kopyalanan=%d | basarisiz=%d | bayt=%.0f | yeniden_kullanim=%s | runtime=%s",
    CLAUDE_CODE_LOG_PREFIX,
    aktarim$selection$selection_mode %||% "",
    length(aktarim$copy$copied %||% character(0)),
    length(aktarim$copy$failed %||% character(0)),
    aktarim$copy$total_bytes %||% 0,
    isTRUE(reuse_mi),
    duzen$root
  ))

  if (!isTRUE(aktarim$ok)) stop(
    aktarim$message %||% "Gerekli girdi dosyaları runtime alanına kopyalanamadı.", call. = FALSE
  )

  .cc_runtime_prepare_result(
    workdir = duzen$root,
    source_dir = source_dir,
    mirrored = TRUE,
    reused = reuse_mi,
    layout = duzen,
    selection = aktarim$selection,
    preflight = preflight,
    scan = tarama
  )
}

# Yalnızca bu çalıştırmada üretilen/değişen çıktı dosyalarını kaynak dizine
# aktarır. Runtime klasörünün tamamı asla geri kopyalanmaz.
sync_claude_runtime_workdir_back <- function(runtime_workdir,
                                             source_workdir,
                                             changed_files = character(0),
                                             layout = NULL,
                                             limits = NULL,
                                             active_guard = NULL) {
  if (is.null(runtime_workdir) || !nzchar(runtime_workdir)) return(invisible(list()))
  if (is.null(source_workdir) || !nzchar(source_workdir)) return(invisible(list()))
  if (!dir.exists(runtime_workdir)) return(invisible(list()))
  if (!dir.exists(source_workdir)) return(invisible(list()))

  if (is.null(layout) || !is.list(layout)) {
    layout <- list(
      root = runtime_workdir,
      input = file.path(runtime_workdir, "input"),
      output = file.path(runtime_workdir, "output"),
      metadata = file.path(runtime_workdir, "metadata"),
      document_support = file.path(runtime_workdir, "document_support")
    )
  }

  plan <- cc_plan_output_sync(
    changed_files = changed_files,
    layout = layout,
    source_workdir = source_workdir,
    limits = limits
  )

  if (!length(plan$items %||% list())) {
    cc_log_info(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "[OUTPUT_SYNC] Aktarılacak yeni/değişen çıktı dosyası yok."
    ))
    return(invisible(list()))
  }

  sonuclar <- cc_apply_output_sync_plan(plan, active_guard = active_guard)

  basarili <- sum(vapply(sonuclar, function(x) isTRUE(x$success), logical(1)))

  cc_log_info(sprintf(
    "%s [OUTPUT_SYNC] aktarilan=%d | basarisiz=%d | atlanan=%d | bayt=%.0f",
    CLAUDE_CODE_LOG_PREFIX,
    basarili,
    length(sonuclar) - basarili,
    length(plan$skipped %||% character(0)),
    plan$total_bytes %||% 0
  ))

  invisible(sonuclar)
}
