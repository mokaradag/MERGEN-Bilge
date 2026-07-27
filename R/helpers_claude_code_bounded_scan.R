# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_bounded_scan.R
# Açıklama: Bilge Yolaç için gerçekten sınırlı (bounded) dizin tarayıcısı.
#           Tüm ağacı list.files(recursive = TRUE) ile numaralandırıp sonradan
#           kırpmak yerine, artımlı gezinir ve sınıra ulaşıldığı anda durur.
#           Bu dosya saf tarama sorumluluğu taşır: Shiny, reaktif değer, DB,
#           ağ veya süreç yönetimi içermez ve worker sürecinde çalışabilir.
# ==============================================================================

# Varsayılan olarak atlanan dizin adları (basename eşleşmesi).
cc_scan_default_excluded_dirs <- function() {
  c(
    ".git", ".svn", ".hg",
    "node_modules", ".Rproj.user", "packrat",
    "build", "dist", "target", "bin", "obj", "coverage",
    ".cache", "cache", "__pycache__", ".pytest_cache", ".mypy_cache",
    ".venv", "venv", ".tox",
    ".idea", ".vscode", ".gradle", ".terraform",
    "tmp", "temp", ".tmp",
    "claude_code_runtime", "claude_code_workspaces",
    "bilge_yolac_downloads", "document_support", ".document_support"
  )
}

# Kök dizine göre göreli yol eşleşmesiyle atlanan dizinler.
cc_scan_default_excluded_rel_paths <- function() {
  c("renv/library", "renv/staging", "renv/sandbox", "renv/cellar", "renv/python")
}

# Bilge Yolaç runtime düzeninde çıktı taramasına dahil edilmeyen alt klasörler.
cc_scan_runtime_excluded_dirs <- function() {
  c("metadata", "document_support")
}

.cc_scan_int <- function(value, default) {
  out <- suppressWarnings(as.numeric(value[1]))
  if (length(out) != 1L || is.na(out) || out < 0) {
    out <- suppressWarnings(as.numeric(default))
  }
  if (length(out) != 1L || is.na(out)) {
    return(Inf)
  }
  out
}

.cc_scan_norm <- function(path) {
  out <- tryCatch(
    normalizePath(path, winslash = "/", mustWork = FALSE),
    error = function(e) as.character(path)[1]
  )
  out <- gsub("\\", "/", as.character(out)[1], fixed = TRUE)
  sub("(?<=.)/+$", "", out, perl = TRUE)
}

.cc_scan_key <- function(path) {
  if (.Platform$OS.type == "windows") tolower(path) else path
}

# Dizin bağlantısı (symlink/junction) mı? Takip edilmeyen bağlantılar hem
# döngüye hem de izinli kökün dışına kaçmaya yol açabilir.
.cc_scan_is_link <- function(path) {
  hedef <- tryCatch(Sys.readlink(path), error = function(e) NA_character_)
  if (length(hedef) != 1L || is.na(hedef)) return(FALSE)
  nzchar(hedef)
}

# Bir dizinin girdilerini işletim sistemi sürecinden artımlı olarak tüketir.
# `list.files()` tek çağrıda bütün dizini belleğe aldığı için yüz binlerce
# girdili düz dizinlerde sınırlar uygulanamadan önce bloke olabiliyordu.
.cc_scan_list_entries <- function(path, max_entries, deadline_ms) {
  limit <- max(0L, as.integer(max_entries))
  if (limit == 0L) return(list(entries = character(0), truncated = TRUE, reason = "max_entries"))

  if (!requireNamespace("processx", quietly = TRUE)) {
    stop("Sınırlı dizin taraması için processx paketi gereklidir.")
  }

  if (.Platform$OS.type == "windows") {
    escaped <- gsub("'", "''", normalizePath(path, winslash = "\\", mustWork = FALSE), fixed = TRUE)
    command <- "powershell.exe"
    args <- c(
      "-NoProfile", "-NonInteractive", "-Command",
      paste0("Get-ChildItem -LiteralPath '", escaped,
             "' -Force:$false | ForEach-Object { $_.FullName }")
    )
  } else {
    command <- "find"
    args <- c(path, "-mindepth", "1", "-maxdepth", "1", "-print")
  }

  proc <- processx::process$new(command, args, stdout = "|", stderr = "|", cleanup = TRUE)
  on.exit(if (proc$is_alive()) proc$kill(), add = TRUE)

  entries <- character(0)
  truncated <- FALSE
  reason <- ""

  repeat {
    if (as.numeric(difftime(Sys.time(), deadline_ms$started, units = "secs")) * 1000 >
        deadline_ms$limit) {
      truncated <- TRUE
      reason <- "timeout"
      break
    }

    available <- proc$poll_io(50)
    if (identical(available[["output"]], "ready")) {
      chunk <- proc$read_output_lines(n = min(128L, limit + 1L - length(entries)))
      entries <- c(entries, chunk)
      if (length(entries) > limit) {
        entries <- entries[seq_len(limit)]
        truncated <- TRUE
        reason <- "max_entries"
        break
      }
    }

    if (!proc$is_alive()) {
      chunk <- proc$read_all_output_lines()
      entries <- c(entries, chunk)
      if (length(entries) > limit) {
        entries <- entries[seq_len(limit)]
        truncated <- TRUE
        reason <- "max_entries"
      }
      break
    }
  }

  list(entries = entries, truncated = truncated, reason = reason)
}

.cc_scan_result <- function(root,
                            files = character(0),
                            file_sizes = numeric(0),
                            directories = character(0),
                            total_bytes = 0,
                            elapsed_ms = 0,
                            truncated = FALSE,
                            truncated_reason = "",
                            errors = character(0),
                            skipped = character(0),
                            ok = TRUE) {
  list(
    ok = isTRUE(ok),
    root = root,
    files = files,
    file_sizes = file_sizes,
    directories = directories,
    file_count = length(files),
    dir_count = length(directories),
    total_bytes = total_bytes,
    elapsed_ms = elapsed_ms,
    truncated = isTRUE(truncated),
    truncated_reason = truncated_reason,
    errors = errors,
    skipped = skipped
  )
}

#' Bir dizini gerçekten sınırlı biçimde tara
#'
#' Artımlı gezinir; herhangi bir sınıra ulaşıldığında kalan ağacı hiç
#' numaralandırmadan durur ve `truncated_reason` alanını doldurur.
#'
#' @param root Taranacak kök dizin
#' @param max_files Maksimum dosya sayısı
#' @param max_dirs Maksimum dizin sayısı
#' @param max_depth Maksimum derinlik (kök = 0)
#' @param max_total_bytes Maksimum toplam bayt
#' @param max_elapsed_ms Maksimum tarama süresi (ms)
#' @param max_file_bytes Tek dosya için üst sınır (aşan dosya atlanır)
#' @param max_entries İşlenecek maksimum öge sayısı
#' @param exclude_dirs Atlanacak dizin adları
#' @param exclude_rel_paths Köke göre atlanacak göreli dizin yolları
#' @param follow_symlinks Dizin bağlantıları takip edilsin mi
#' @param allowed_root Çözülen yolların içinde kalması gereken kök
#' @return Yapılandırılmış tarama sonucu listesi
cc_scan_directory_bounded <- function(root,
                                      max_files = 2000L,
                                      max_dirs = 500L,
                                      max_depth = 6L,
                                      max_total_bytes = 200 * 1024^2,
                                      max_elapsed_ms = 4000L,
                                      max_file_bytes = 25 * 1024^2,
                                      max_entries = 20000L,
                                      exclude_dirs = cc_scan_default_excluded_dirs(),
                                      exclude_rel_paths = cc_scan_default_excluded_rel_paths(),
                                      follow_symlinks = FALSE,
                                      allowed_root = NULL) {
  baslangic <- Sys.time()

  ham_kok <- as.character(root %||% "")[1]
  if (is.na(ham_kok) || !nzchar(ham_kok)) {
    return(.cc_scan_result(root = "", ok = FALSE, truncated_reason = "invalid_root"))
  }

  kok <- .cc_scan_norm(ham_kok)

  if (!isTRUE(tryCatch(dir.exists(kok), error = function(e) FALSE))) {
    return(.cc_scan_result(root = kok, ok = FALSE, truncated_reason = "missing_root"))
  }

  max_files <- .cc_scan_int(max_files, 2000L)
  max_dirs <- .cc_scan_int(max_dirs, 500L)
  max_depth <- .cc_scan_int(max_depth, 6L)
  max_total_bytes <- .cc_scan_int(max_total_bytes, 200 * 1024^2)
  max_elapsed_ms <- .cc_scan_int(max_elapsed_ms, 4000L)
  max_file_bytes <- .cc_scan_int(max_file_bytes, 25 * 1024^2)
  max_entries <- .cc_scan_int(max_entries, 20000L)

  haric_adlar <- tolower(as.character(exclude_dirs %||% character(0)))
  haric_rel <- tolower(gsub("\\", "/", as.character(exclude_rel_paths %||% character(0)), fixed = TRUE))

  izin_kok <- if (is.null(allowed_root) || !nzchar(as.character(allowed_root)[1])) {
    kok
  } else {
    .cc_scan_norm(allowed_root)
  }
  izin_kok_key <- .cc_scan_key(izin_kok)

  dosyalar <- character(0)
  boyutlar <- numeric(0)
  dizinler <- character(0)
  hatalar <- character(0)
  atlananlar <- character(0)

  toplam_bayt <- 0
  islenen_oge <- 0
  kesildi <- FALSE
  kesme_nedeni <- ""

  gorulen <- new.env(parent = emptyenv())
  assign(.cc_scan_key(kok), TRUE, envir = gorulen)

  kuyruk <- list(list(path = kok, depth = 0L, rel = ""))

  gecen_ms <- function() {
    as.numeric(difftime(Sys.time(), baslangic, units = "secs")) * 1000
  }

  kes <- function(neden) {
    kesildi <<- TRUE
    if (!nzchar(kesme_nedeni)) kesme_nedeni <<- neden
    invisible(NULL)
  }

  while (length(kuyruk) > 0L && !isTRUE(kesildi)) {
    if (gecen_ms() > max_elapsed_ms) {
      kes("timeout")
      break
    }

    mevcut <- kuyruk[[1L]]
    kuyruk <- kuyruk[-1L]

    kalan_oge <- max_entries - islenen_oge
    listeleme <- tryCatch(
      .cc_scan_list_entries(
        mevcut$path,
        max_entries = kalan_oge,
        deadline_ms = list(started = baslangic, limit = max_elapsed_ms)
      ),
      error = function(e) {
        hatalar <<- c(hatalar, paste0(mevcut$rel, ": ", conditionMessage(e)))
        list(entries = character(0), truncated = FALSE, reason = "")
      }
    )

    ogeler <- listeleme$entries
    if (isTRUE(listeleme$truncated)) kes(listeleme$reason)

    if (!length(ogeler)) next

    bilgi <- tryCatch(
      file.info(ogeler, extra_cols = FALSE),
      error = function(e) {
        hatalar <<- c(hatalar, paste0(mevcut$rel, ": ", conditionMessage(e)))
        NULL
      }
    )

    if (is.null(bilgi) || nrow(bilgi) == 0L) next

    for (i in seq_along(ogeler)) {
      islenen_oge <- islenen_oge + 1L
      if (islenen_oge > max_entries) {
        kes("max_entries")
        break
      }

      if (islenen_oge %% 64L == 0L && gecen_ms() > max_elapsed_ms) {
        kes("timeout")
        break
      }

      oge <- .cc_scan_norm(ogeler[i])
      oge_ad <- basename(oge)
      oge_rel <- if (nzchar(mevcut$rel)) paste0(mevcut$rel, "/", oge_ad) else oge_ad

      dizin_mi <- isTRUE(bilgi$isdir[i])

      if (dizin_mi) {
        if (tolower(oge_ad) %in% haric_adlar || tolower(oge_rel) %in% haric_rel) {
          atlananlar <- c(atlananlar, oge_rel)
          next
        }

        if (!isTRUE(follow_symlinks) && isTRUE(.cc_scan_is_link(oge))) {
          atlananlar <- c(atlananlar, oge_rel)
          next
        }

        if (mevcut$depth + 1L > max_depth) {
          kes("max_depth")
          next
        }

        # Bağlantı/junction döngülerine ve izinli kök dışına kaçışa karşı
        # gerçek yol üzerinden tekrar ziyaret kontrolü yapılır.
        gercek <- tryCatch(
          normalizePath(oge, winslash = "/", mustWork = TRUE),
          error = function(e) oge
        )
        gercek <- .cc_scan_norm(gercek)
        gercek_key <- .cc_scan_key(gercek)

        if (!identical(gercek_key, izin_kok_key) &&
            !startsWith(gercek_key, paste0(izin_kok_key, "/"))) {
          atlananlar <- c(atlananlar, oge_rel)
          next
        }

        if (exists(gercek_key, envir = gorulen, inherits = FALSE)) {
          atlananlar <- c(atlananlar, oge_rel)
          next
        }
        assign(gercek_key, TRUE, envir = gorulen)

        if (length(dizinler) + 1L > max_dirs) {
          kes("max_directories")
          next
        }

        dizinler <- c(dizinler, oge)
        kuyruk[[length(kuyruk) + 1L]] <- list(
          path = oge,
          depth = mevcut$depth + 1L,
          rel = oge_rel
        )
        next
      }

      if (!isTRUE(follow_symlinks) && isTRUE(.cc_scan_is_link(oge))) {
        atlananlar <- c(atlananlar, oge_rel)
        next
      }

      boyut <- suppressWarnings(as.numeric(bilgi$size[i]))
      if (!is.finite(boyut)) boyut <- 0

      if (boyut > max_file_bytes) {
        atlananlar <- c(atlananlar, oge_rel)
        next
      }

      if (length(dosyalar) + 1L > max_files) {
        kes("max_files")
        break
      }

      if (toplam_bayt + boyut > max_total_bytes) {
        kes("max_total_bytes")
        break
      }

      dosyalar <- c(dosyalar, oge)
      boyutlar <- c(boyutlar, boyut)
      toplam_bayt <- toplam_bayt + boyut
    }
  }

  .cc_scan_result(
    root = kok,
    files = dosyalar,
    file_sizes = boyutlar,
    directories = dizinler,
    total_bytes = toplam_bayt,
    elapsed_ms = round(gecen_ms(), 1),
    truncated = kesildi,
    truncated_reason = kesme_nedeni,
    errors = unique(hatalar),
    skipped = unique(atlananlar),
    ok = TRUE
  )
}

#' Tarama sonucundaki yolları köke göre göreli forma çevir
#'
#' @param paths Mutlak yollar
#' @param root Kök dizin
#' @return Göreli yollar (kök dışındakiler basename olarak döner)
cc_scan_relative_paths <- function(paths, root) {
  paths <- as.character(paths %||% character(0))
  if (!length(paths)) return(character(0))

  kok <- .cc_scan_norm(root %||% "")
  if (!nzchar(kok)) return(basename(paths))

  kok_key <- .cc_scan_key(kok)
  onek <- paste0(kok_key, "/")

  vapply(paths, function(p) {
    p_norm <- .cc_scan_norm(p)
    p_key <- .cc_scan_key(p_norm)

    if (startsWith(p_key, onek)) {
      substring(p_norm, nchar(kok) + 2L)
    } else {
      basename(p_norm)
    }
  }, character(1), USE.NAMES = FALSE)
}
