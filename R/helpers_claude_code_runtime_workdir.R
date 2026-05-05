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

# Windows cmd.exe için problem çıkarabilecek yol mu?
is_problematic_windows_workdir <- function(path) {
  if (.Platform$OS.type != "windows") return(FALSE)
  if (is.null(path) || !nzchar(path)) return(FALSE)

  aday <- gsub("\\\\", "/", as.character(path[1]), fixed = TRUE)

  unc_mi <- grepl("^//", aday)
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

# Problemli ağ/Unicode dizinlerini yerel ASCII çalışma klasörüne taşır
prepare_claude_runtime_workdir <- function(workdir,
                                           user_id = NULL,
                                           runtime_token = NULL) {
  if (is.null(workdir) || !nzchar(workdir)) {
    return(list(
      runtime_workdir = workdir,
      source_workdir = workdir,
      mirrored = FALSE
    ))
  }

  source_dir <- tryCatch(
    normalize_mcp_path(workdir, must_exist = FALSE),
    error = function(e) as.character(workdir)
  )

  dir_ok <- tryCatch(
    isTRUE(dir.exists(source_dir)) || isTRUE(fs::dir_exists(source_dir)),
    error = function(e) FALSE
  )

  if (!isTRUE(dir_ok)) {
    return(list(
      runtime_workdir = workdir,
      source_workdir = workdir,
      mirrored = FALSE
    ))
  }

  if (!is_problematic_windows_workdir(source_dir)) {
    return(list(
      runtime_workdir = source_dir,
      source_workdir = source_dir,
      mirrored = FALSE
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
    mirrored = TRUE
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