# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_output_sync.R
# Açıklama: Bilge Yolaç izole runtime alanındaki çıktı bölgesinin belirlenmesi,
#           YALNIZCA bu çalıştırmada üretilen/değişen dosyaların kaynak dizine
#           geri aktarım planı ve eskiyen runtime/doküman destek klasörlerinin
#           yaşa göre temizliği.
#
#           Runtime klasörünün tamamı ASLA kaynak dizine geri kopyalanmaz.
#           Bu dosya Shiny/reaktif/DB bağımlılığı içermez ve arka plan
#           worker'ında çalıştırılabilir.
# ==============================================================================

#' Bir yolun runtime düzeninde hangi bölgeye ait olduğunu belirle
#'
#' @param path Kontrol edilecek yol
#' @param layout Runtime düzeni
#' @return "output", "input", "metadata", "document_support", "root" veya ""
cc_runtime_zone_of_path <- function(path, layout) {
  yol <- .cc_scan_norm(as.character(path %||% "")[1])
  if (!nzchar(yol) || !is.list(layout)) return("")

  yol_key <- .cc_scan_key(yol)

  icinde <- function(kok) {
    if (is.null(kok) || !nzchar(kok)) return(FALSE)
    kok_key <- .cc_scan_key(.cc_scan_norm(kok))
    identical(yol_key, kok_key) || startsWith(yol_key, paste0(kok_key, "/"))
  }

  for (bolge in c("output", "input", "metadata", "document_support")) {
    if (icinde(layout[[bolge]])) return(bolge)
  }

  if (icinde(layout$root)) return("root")

  ""
}

#' Yalnızca üretilen/değişen çıktı dosyaları için geri aktarım planı üret
#'
#' Runtime klasörünün tamamı kaynak dizine kopyalanmaz. Yalnızca onaylı
#' çıktı bölgesinde bulunan, bu çalıştırmada oluşmuş veya değişmiş ve
#' boyut sınırlarını aşmayan dosyalar planlanır.
#'
#' @param changed_files Snapshot diff sonucundaki yollar
#' @param layout Runtime düzeni
#' @param source_workdir Hedef kaynak dizin
#' @param limits Sınır listesi
#' @return list(items, skipped, total_bytes)
cc_plan_output_sync <- function(changed_files,
                                layout,
                                source_workdir,
                                limits = NULL) {
  changed_files <- unique(as.character(changed_files %||% character(0)))
  bos <- list(items = list(), skipped = character(0), total_bytes = 0)

  if (!length(changed_files) || !is.list(layout)) return(bos)

  hedef_kok <- .cc_scan_norm(as.character(source_workdir %||% "")[1])
  if (!nzchar(hedef_kok) || !dir.exists(hedef_kok)) return(bos)

  max_file_bytes <- cc_runtime_limit("max_output_file_bytes", 100 * 1024^2, limits)
  max_total_bytes <- cc_runtime_limit("max_output_total_bytes", 400 * 1024^2, limits)

  root_norm <- .cc_scan_norm(layout$root %||% "")
  hedef_kok_key <- .cc_scan_key(hedef_kok)

  ogeler <- list()
  atlananlar <- character(0)
  toplam <- 0

  for (yol in changed_files) {
    kaynak <- .cc_scan_norm(yol)

    if (!isTRUE(file.exists(kaynak)) || isTRUE(dir.exists(kaynak))) {
      atlananlar <- c(atlananlar, kaynak)
      next
    }

    bolge <- cc_runtime_zone_of_path(kaynak, layout)

    # Kopyalanmış girdilerdeki doğrulanmış Edit değişiklikleri de özgün göreli
    # yollarına geri taşınır. Metadata ve doküman desteği hiçbir zaman taşınmaz.
    if (!bolge %in% c("output", "input", "root")) {
      atlananlar <- c(atlananlar, kaynak)
      next
    }

    boyut <- suppressWarnings(as.numeric(file.info(kaynak)$size[1]))
    if (!is.finite(boyut)) boyut <- 0

    if (boyut > max_file_bytes || toplam + boyut > max_total_bytes) {
      atlananlar <- c(atlananlar, kaynak)
      next
    }

    zone_root <- if (identical(bolge, "output")) {
      layout$output
    } else if (identical(bolge, "input")) {
      layout$input
    } else {
      root_norm
    }
    rel <- cc_scan_relative_paths(kaynak, zone_root)
    rel <- as.character(rel)[1]

    if (!nzchar(rel) || grepl("(^|/)\\.\\.(/|$)", rel, perl = TRUE) ||
        grepl("^(?:[A-Za-z]:|/)", rel, perl = TRUE)) {
      atlananlar <- c(atlananlar, kaynak)
      next
    }

    hedef <- .cc_scan_norm(file.path(hedef_kok, rel))
    hedef_key <- .cc_scan_key(hedef)

    if (!startsWith(hedef_key, paste0(hedef_kok_key, "/"))) {
      atlananlar <- c(atlananlar, kaynak)
      next
    }

    ogeler[[length(ogeler) + 1L]] <- list(
      source_path = kaynak,
      dest_path = hedef,
      relative_path = rel,
      size = boyut
    )

    toplam <- toplam + boyut
  }

  list(
    items = ogeler, skipped = unique(atlananlar), total_bytes = toplam,
    source_workdir = hedef_kok
  )
}

#' Geri aktarım planını uygula
#'
#' @param plan cc_plan_output_sync() çıktısı
#' @return Dosya başına yapılandırılmış sonuç listesi
cc_apply_output_sync_plan <- function(plan, active_guard = NULL) {
  if (!is.list(plan) || !length(plan$items %||% list())) {
    return(list())
  }

  sonuclar <- list()

  for (oge in plan$items) {
    if (!is.null(active_guard) && nzchar(active_guard) && !file.exists(active_guard)) {
      break
    }
    hedef_dizin <- dirname(oge$dest_path)

    # Existing symlink/junction parents must be resolved before directory
    # creation or copying; a lexical destination prefix check is not enough.
    approved_root <- .cc_scan_norm(plan$source_workdir %||% hedef_dizin)
    ancestor <- hedef_dizin
    while (!dir.exists(ancestor) && !identical(dirname(ancestor), ancestor)) {
      ancestor <- dirname(ancestor)
    }
    resolved_ancestor <- tryCatch(
      .cc_scan_norm(normalizePath(ancestor, winslash = "/", mustWork = TRUE)),
      error = function(e) ""
    )
    approved_key <- .cc_scan_key(approved_root)
    ancestor_key <- .cc_scan_key(resolved_ancestor)
    parent_safe <- nzchar(approved_root) && nzchar(resolved_ancestor) && (
      identical(ancestor_key, approved_key) ||
        startsWith(ancestor_key, paste0(approved_key, "/"))
    )
    if (!isTRUE(parent_safe)) {
      sonuclar[[length(sonuclar) + 1L]] <- list(
        source_path = oge$source_path, dest_path = oge$dest_path,
        success = FALSE, size = oge$size,
        error = "Hedef üst dizini onaylı kaynak kökün dışında"
      )
      next
    }

    if (!dir.exists(hedef_dizin)) {
      dir.create(hedef_dizin, recursive = TRUE, showWarnings = FALSE)
    }

    hata <- ""

    ok <- tryCatch(
      if (!is.null(active_guard) && nzchar(active_guard) && !file.exists(active_guard)) {
        FALSE
      } else
      file.copy(
        from = oge$source_path,
        to = oge$dest_path,
        overwrite = TRUE,
        copy.mode = TRUE,
        copy.date = TRUE
      ),
      error = function(e) {
        hata <<- conditionMessage(e)
        FALSE
      }
    )

    if (!isTRUE(ok) && !nzchar(hata)) {
      hata <- "Dosya kaynak dizine kopyalanamadı"
    }

    sonuclar[[length(sonuclar) + 1L]] <- list(
      source_path = oge$source_path,
      dest_path = oge$dest_path,
      success = isTRUE(ok),
      size = oge$size,
      error = hata
    )
  }

  sonuclar
}

#' Eski runtime/doküman destek klasörlerini yaşa göre temizle
#'
#' Aktif çalışmaları etkilememesi için yalnızca belirtilen süreden eski
#' klasörler ve asla `keep_paths` içindeki yollar silinmez.
#'
#' @param user_id Kullanıcı kimliği
#' @param max_age_sec Saklama süresi (saniye)
#' @param keep_paths Korunacak yollar
#' @return Silinen klasör sayısı
cc_cleanup_stale_runtime_dirs <- function(user_id = NULL,
                                          max_age_sec = NULL,
                                          keep_paths = character(0)) {
  kullanici_dizin <- cc_runtime_user_dir(user_id)
  if (!dir.exists(kullanici_dizin)) return(invisible(0L))

  max_age_sec <- suppressWarnings(as.numeric(max_age_sec[1]))
  if (!is.finite(max_age_sec)) {
    max_age_sec <- cc_runtime_limit("runtime_retention_sec", 21600)
  }
  if (!is.finite(max_age_sec)) return(invisible(0L))

  adaylar <- tryCatch(
    list.dirs(kullanici_dizin, full.names = TRUE, recursive = FALSE),
    error = function(e) character(0)
  )

  if (!length(adaylar)) return(invisible(0L))

  koru <- .cc_scan_key(vapply(
    as.character(keep_paths %||% character(0)),
    .cc_scan_norm,
    character(1),
    USE.NAMES = FALSE
  ))

  simdi <- Sys.time()
  silinen <- 0L

  for (aday in adaylar) {
    aday_norm <- .cc_scan_norm(aday)
    if (.cc_scan_key(aday_norm) %in% koru) next

    leases <- tryCatch(
      list.files(
        file.path(aday, "metadata"), pattern = "^active-run-.*\\.lease$", recursive = FALSE,
        full.names = TRUE, include.dirs = FALSE
      ),
      error = function(e) character(0)
    )
    if (length(leases)) next

    mtime <- tryCatch(file.info(aday)$mtime[1], error = function(e) NA)
    if (is.na(mtime)) next

    yas <- as.numeric(difftime(simdi, mtime, units = "secs"))
    if (!is.finite(yas) || yas < max_age_sec) next

    ok <- tryCatch({
      unlink(aday, recursive = TRUE, force = TRUE)
      TRUE
    }, error = function(e) FALSE)

    if (isTRUE(ok)) silinen <- silinen + 1L
  }

  invisible(silinen)
}

#' Eski doküman destek klasörlerini yaşa göre temizle
#'
#' Aktif çalıştırmaları etkilememesi için yalnızca `max_age_sec` süresinden
#' eski ve `keep_paths` dışındaki klasörler silinir.
#'
#' @param user_id Kullanıcı kimliği
#' @param max_age_sec Saklama süresi (saniye)
#' @param keep_paths Korunacak klasör yolları
#' @return Silinen klasör sayısı
cc_cleanup_stale_document_support_dirs <- function(user_id = NULL,
                                                   max_age_sec = 21600,
                                                   keep_paths = character(0)) {
  kok <- file.path(
    tempdir(),
    "claude_code_runtime",
    paste0("user_", as.character(user_id %||% "default")),
    "document_support"
  )

  if (!dir.exists(kok)) return(invisible(0L))

  max_age_sec <- suppressWarnings(as.numeric(max_age_sec[1]))
  if (!is.finite(max_age_sec) || max_age_sec < 0) return(invisible(0L))

  adaylar <- tryCatch(
    list.dirs(kok, full.names = TRUE, recursive = FALSE),
    error = function(e) character(0)
  )

  if (!length(adaylar)) return(invisible(0L))

  koru <- tolower(gsub("\\", "/", as.character(keep_paths %||% character(0)), fixed = TRUE))
  simdi <- Sys.time()
  silinen <- 0L

  for (aday in adaylar) {
    aday_key <- tolower(gsub("\\", "/", aday, fixed = TRUE))
    if (aday_key %in% koru) next

    mtime <- tryCatch(file.info(aday)$mtime[1], error = function(e) NA)
    if (is.na(mtime)) next

    yas <- as.numeric(difftime(simdi, mtime, units = "secs"))
    if (!is.finite(yas) || yas < max_age_sec) next

    ok <- tryCatch({
      unlink(aday, recursive = TRUE, force = TRUE)
      TRUE
    }, error = function(e) FALSE)

    if (isTRUE(ok)) silinen <- silinen + 1L
  }

  invisible(silinen)
}

#' Bilge Yolaç runtime çıktı bölgesinin anlık görüntüsünü al
#'
#' Kaynak klasörün tamamı değil, yalnızca yazılabilir onaylı çıktı alanı
#' (runtime kökü + output) taranır; input/metadata/document_support hariç
#' tutulur.
#'
#' @param runtime_workdir Claude Code çalışma dizini
#' @param mirrored Izole runtime düzeni kullanılıyor mu
#' @param limits Sınır listesi
#' @return snapshot_claude_code_workdir_files() çıktısı
cc_snapshot_run_output_area <- function(runtime_workdir,
                                        mirrored = FALSE,
                                        limits = NULL) {
  # İzole runtime'da build/dist/bin gibi adlar onaylı output alanının normal
  # parçalarıdır; basename tabanlı kaynak-ağaç hariçleri burada uygulanmaz.
  # Input da başlangıç snapshot'ına girer ki Edit değişiklikleri bulunabilsin.
  haric <- if (isTRUE(mirrored)) {
    setdiff(cc_scan_runtime_excluded_dirs(), "input")
  } else {
    cc_scan_default_excluded_dirs()
  }

  snapshot_claude_code_workdir_files(
    workdir = runtime_workdir,
    recursive = TRUE,
    exclude_dirs = haric,
    limits = limits
  )
}
