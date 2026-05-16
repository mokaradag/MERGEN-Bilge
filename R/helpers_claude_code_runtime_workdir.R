# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_runtime_workdir.R
# Açıklama: Bilge Yolaç için kullanıcı çalışma alanı ve Windows/UNC/Unicode
#           çalışma dizini aynalama yardımcıları.
#
#           Bu dosya, Claude Code CLI'ın Windows VM üzerinde problemli UNC veya
#           ASCII dışı çalışma dizinlerinde kararsız çalışmasını önlemek için
#           kullanıcı dizinini geçici yerel bir runtime dizinine aynalar.
#           Runtime dizini çalışma başına benzersizdir; böylece aynı kullanıcının
#           eşzamanlı veya hızlı ardışık çalıştırmaları birbirinin active_dir
#           klasörünü silmez.
# ==============================================================================
# Kullanıcı için izole bir çalışma alanı oluşturur veya mevcut olanı döndürür
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
# Windows cmd.exe / Claude Code CLI için problem çıkarabilecek yol mu?
is_problematic_windows_workdir <- function(path) {
  if (.Platform$OS.type != "windows") return(FALSE)
  if (is.null(path) || !nzchar(path)) return(FALSE)

  aday <- gsub("\\\\", "/", as.character(path[1]), fixed = TRUE)

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

# Dizin içeriğini yerel çalışma alanına aynala
mirror_directory_to_local_workspace <- function(source_dir, target_dir) {
  if (!dir.exists(target_dir)) {
    dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)
  }

  ogeler <- tryCatch(
    list.files(
      source_dir,
      full.names = TRUE,
      recursive = FALSE,
      all.files = FALSE,
      include.dirs = TRUE
    ),
    error = function(e) character(0)
  )

  # UNC / ağ paylaşımı kaynaklı dizinlerde base R list.files bazen boş
  # döner; fs::dir_ls aynı paylaşımı genellikle başarıyla listeler.
  # Aksi halde mirror sessizce boş runtime klasörü üretir ve CLI dizini
  # "completely empty" olarak görür.
  if (!length(ogeler)) {
    dirs_fs <- tryCatch(
      as.character(fs::dir_ls(source_dir, recurse = FALSE, type = "directory")),
      error = function(e) character(0)
    )

    files_fs <- tryCatch(
      as.character(fs::dir_ls(source_dir, recurse = FALSE, type = "file")),
      error = function(e) character(0)
    )

    ogeler <- unique(c(dirs_fs, files_fs))
  }

  if (!length(ogeler)) {
    return(invisible(TRUE))
  }

  kopya_ok <- tryCatch(
    file.copy(
      from = ogeler,
      to = target_dir,
      overwrite = TRUE,
      recursive = TRUE,
      copy.mode = TRUE,
      copy.date = TRUE
    ),
    error = function(e) rep(FALSE, length(ogeler))
  )

  if (any(!kopya_ok)) {
    for (i in seq_along(ogeler)) {
      if (isTRUE(kopya_ok[i])) next

      kaynak <- ogeler[i]
      hedef <- file.path(target_dir, basename(kaynak))

      tryCatch({
        if (dir.exists(kaynak)) {
          if (dir.exists(hedef)) unlink(hedef, recursive = TRUE, force = TRUE)
          fs::dir_copy(kaynak, hedef, overwrite = TRUE)
        } else {
          fs::file_copy(kaynak, hedef, overwrite = TRUE)
        }
      }, error = function(e) {
        log_warn(paste(
          CLAUDE_CODE_LOG_PREFIX,
          "Yerel aynalama sırasında öge kopyalanamadı:",
          basename(kaynak),
          "-",
          conditionMessage(e)
        ))
      })
    }
  }

  invisible(TRUE)
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

  yol_slash <- gsub("\\\\", "/", yol, fixed = TRUE)

  # Yalnızca runtime alanı altında olan klasörler yeniden kullanılabilir.
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

# Problemli ağ/Unicode dizinlerini yerel ASCII çalışma klasörüne taşır.
# existing_runtime_workdir verilirse ve aynı kullanıcı kovası altında geçerli
# bir klasörse yeniden kullanılır; bu sayede Claude CLI --resume oturumu
# takip eden sorularda kaybolmaz.
prepare_claude_runtime_workdir <- function(workdir,
                                           user_id = NULL,
                                           runtime_token = NULL,
                                           existing_runtime_workdir = NULL) {
  if (is.null(workdir) || !nzchar(workdir)) {
    return(list(
      runtime_workdir = workdir,
      source_workdir = workdir,
      mirrored = FALSE
    ))
  }

  original_workdir <- as.character(workdir %||% "")[1]

  source_dir <- resolve_claude_runtime_source_dir(original_workdir)

  if (!nzchar(source_dir)) {
    # Problemli ağ yolu algılandıysa CLI'a doğrudan göndermeyelim;
    # ama gerçek dizin çözülemediği için kullanıcıya açık bir log bırakalım.
    if (isTRUE(is_problematic_windows_workdir(original_workdir))) {
      log_warn(paste(
        CLAUDE_CODE_LOG_PREFIX,
        "Problemli çalışma dizini algılandı ancak yerel aynalama için çözülemedi:",
        original_workdir
      ))
    }

    return(list(
      runtime_workdir = workdir,
      source_workdir = workdir,
      mirrored = FALSE
    ))
  }

  problemli_mi <- isTRUE(is_problematic_windows_workdir(original_workdir)) ||
    isTRUE(is_problematic_windows_workdir(source_dir))

  if (!isTRUE(problemli_mi)) {
    return(list(
      runtime_workdir = source_dir,
      source_workdir = source_dir,
      mirrored = FALSE
    ))
  }

  # Takip eden sorularda mevcut runtime klasörünü yeniden kullan: Claude CLI
  # oturum metadatası bu klasöre bağlı olduğundan yeni runtime klasörü her
  # seferinde "No conversation found with session ID" hatasına yol açar.
  if (isTRUE(.cc_runtime_workdir_reusable(existing_runtime_workdir, user_id))) {
    reuse_yol <- normalizePath(
      existing_runtime_workdir,
      winslash = "/",
      mustWork = FALSE
    )

    # Kaynak dizinin yeni dosyaları runtime klasörüne yansısın diye yeniden
    # aynala; mevcut runtime içeriği korunur, eksik veya değişen dosyalar
    # üzerine yazılır.
    tryCatch(
      mirror_directory_to_local_workspace(source_dir, reuse_yol),
      error = function(e) {
        log_warn(paste(
          CLAUDE_CODE_LOG_PREFIX,
          "Mevcut runtime workdir yeniden aynalanamadı:",
          conditionMessage(e)
        ))
      }
    )

    log_info(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Mevcut runtime workdir yeniden kullanıldı:",
      source_dir,
      "->",
      reuse_yol
    ))

    return(list(
      runtime_workdir = reuse_yol,
      source_workdir = source_dir,
      mirrored = TRUE,
      reused = TRUE
    ))
  }

  run_dir <- .cc_runtime_workdir_token(runtime_token)

  local_base <- file.path(
    tempdir(),
    "claude_code_runtime",
    paste0("user_", as.character(user_id %||% "default")),
    run_dir
  )

  dir.create(local_base, recursive = TRUE, showWarnings = FALSE)

  mirror_directory_to_local_workspace(source_dir, local_base)

  local_base <- normalizePath(local_base, winslash = "/", mustWork = FALSE)

  log_info(paste(
    CLAUDE_CODE_LOG_PREFIX,
    "Problemli çalışma dizini yerel alana aynalandı:",
    source_dir,
    "->",
    local_base
  ))

  list(
    runtime_workdir = local_base,
    source_workdir = source_dir,
    mirrored = TRUE,
    reused = FALSE
  )
}

# Yerel çalışma alanındaki değişiklikleri kaynak dizine geri senkronlar
sync_claude_runtime_workdir_back <- function(runtime_workdir, source_workdir) {
  if (is.null(runtime_workdir) || !nzchar(runtime_workdir)) return(invisible(FALSE))
  if (is.null(source_workdir) || !nzchar(source_workdir)) return(invisible(FALSE))
  if (!dir.exists(runtime_workdir)) return(invisible(FALSE))
  if (!dir.exists(source_workdir)) return(invisible(FALSE))

  mirror_directory_to_local_workspace(runtime_workdir, source_workdir)

  log_info(paste(
    CLAUDE_CODE_LOG_PREFIX,
    "Yerel çalışma alanı kaynak dizine geri senkronlandı:",
    runtime_workdir,
    "->",
    source_workdir
  ))

  invisible(TRUE)
}