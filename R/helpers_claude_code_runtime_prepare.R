# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_runtime_prepare.R
# Açıklama: Bilge Yolaç izole runtime çalışma alanı düzeni (input/output/
#           metadata/document_support), büyük klasör preflight kararı, gerekli
#           girdi dosyalarının seçimi ve kopyalanması ile yalnızca değişen
#           çıktıların geri aktarım planı.
#
#           Bu dosya Shiny, reaktif değer, DB veya süreç yönetimi içermez;
#           arka plan worker sürecinde çalıştırılabilir.
# ==============================================================================

CLAUDE_CODE_LIMIT_MESSAGE <- paste(
  "Seçilen klasör güvenli çalışma sınırlarını aşıyor.",
  "Bilge Yolaç klasörün tamamını kopyalamadı.",
  "Lütfen daha küçük bir alt klasör veya gerekli dosyaları seçin."
)

# Hazırlık kodu hem ana Shiny sürecinde hem de arka plan worker'ında çalışır.
# Worker'da logger appender yapılandırılmamış olabileceğinden log çağrıları
# asla hazırlığı düşürmemelidir.
cc_log_info <- function(message) {
  tryCatch({
    if (exists("log_info", mode = "function", inherits = TRUE)) {
      log_info(message)
    }
  }, error = function(e) NULL)

  invisible(NULL)
}

cc_log_warn <- function(message) {
  tryCatch({
    if (exists("log_warn", mode = "function", inherits = TRUE)) {
      log_warn(message)
    }
  }, error = function(e) NULL)

  invisible(NULL)
}

cc_runtime_base_dir <- function() {
  file.path(tempdir(), "claude_code_runtime")
}

cc_runtime_user_dir <- function(user_id = NULL) {
  file.path(
    cc_runtime_base_dir(),
    paste0("user_", as.character(user_id %||% "default"))
  )
}

#' İzole runtime çalışma alanı düzenini hesapla
#'
#' @param user_id Kullanıcı kimliği
#' @param run_token Çalışma başına benzersiz klasör adı
#' @return root/input/output/metadata/document_support yollarını içeren liste
cc_runtime_dir_layout <- function(user_id = NULL, run_token = "run") {
  kok <- file.path(cc_runtime_user_dir(user_id), as.character(run_token)[1])

  list(
    root = kok,
    input = file.path(kok, "input"),
    output = file.path(kok, "output"),
    metadata = file.path(kok, "metadata"),
    document_support = file.path(kok, "document_support")
  )
}

#' Runtime çalışma alanı klasörlerini oluştur
#'
#' @param layout cc_runtime_dir_layout() çıktısı
#' @return Normalize edilmiş düzen listesi
cc_runtime_ensure_layout <- function(layout) {
  gerekli <- c("root", "input", "output", "metadata", "document_support")
  if (!is.list(layout) || !all(gerekli %in% names(layout))) {
    stop("Runtime dizini eksik veya geçersiz.")
  }

  baglanti_mi <- function(yol) {
    hedef <- tryCatch(Sys.readlink(yol), error = function(e) NA_character_)
    length(hedef) == 1L && !is.na(hedef) && nzchar(hedef)
  }

  kok <- as.character(layout$root)[1]
  if (isTRUE(baglanti_mi(kok))) {
    stop("Runtime kök dizini bağlantı olamaz.")
  }

  if (!dir.exists(kok) && !dir.create(kok, recursive = TRUE, showWarnings = FALSE)) {
    stop("Runtime kök dizini oluşturulamadı.")
  }
  if (isTRUE(baglanti_mi(kok))) {
    stop("Runtime kök dizini bağlantı olamaz.")
  }

  gercek_kok <- normalizePath(kok, winslash = "/", mustWork = TRUE)
  kok_anahtar <- if (.Platform$OS.type == "windows") tolower(gercek_kok) else gercek_kok

  # Yeniden kullanılan bir runtime'da model önceki bölgelerden birini
  # symlink/junction ile değiştirmiş olabilir. Bu durumda dış hedefe yazmak
  # yerine hazırlığı kapalı biçimde reddet.
  for (ad in setdiff(gerekli, "root")) {
    yol <- as.character(layout[[ad]])[1]
    beklenen <- file.path(kok, ad)
    yol_adresi <- normalizePath(yol, winslash = "/", mustWork = FALSE)
    beklenen_adres <- normalizePath(beklenen, winslash = "/", mustWork = FALSE)
    if (.Platform$OS.type == "windows") {
      yol_adresi <- tolower(yol_adresi)
      beklenen_adres <- tolower(beklenen_adres)
    }
    if (!identical(yol_adresi, beklenen_adres)) {
      stop(sprintf("Runtime bölgesi beklenen konumda değil: %s", ad))
    }
    if (isTRUE(baglanti_mi(yol))) {
      stop(sprintf("Runtime bölgesi bağlantı olamaz: %s", ad))
    }
    if (!dir.exists(yol) && !dir.create(yol, recursive = TRUE, showWarnings = FALSE)) {
      stop(sprintf("Runtime bölgesi oluşturulamadı: %s", ad))
    }
    if (isTRUE(baglanti_mi(yol))) {
      stop(sprintf("Runtime bölgesi bağlantı olamaz: %s", ad))
    }

    gercek <- normalizePath(yol, winslash = "/", mustWork = TRUE)
    anahtar <- if (.Platform$OS.type == "windows") tolower(gercek) else gercek
    if (!startsWith(anahtar, paste0(kok_anahtar, "/"))) {
      stop(sprintf("Runtime bölgesi kök dışında: %s", ad))
    }
  }

  lapply(layout, function(yol) {
    tryCatch(
      normalizePath(yol, winslash = "/", mustWork = FALSE),
      error = function(e) yol
    )
  })
}

# ------------------------------------------------------------------------------
# PREFLIGHT: BÜYÜK KLASÖR POLİTİKASI
# ------------------------------------------------------------------------------

#' Preflight tarama sonucunu güvenli çalışma sınırlarına göre değerlendir
#'
#' @param scan cc_scan_directory_bounded() çıktısı
#' @param limits Sınır listesi
#' @return list(ok, blocked, limited, reason, message, metrics)
cc_evaluate_workdir_preflight <- function(scan, limits = NULL) {
  if (!is.list(scan) || !isTRUE(scan$ok)) {
    hata <- if (is.list(scan)) {
      paste(as.character(scan$errors %||% character(0)), collapse = " | ")
    } else {
      ""
    }
    mesaj <- "Kaynak klasör güvenli biçimde taranamadı; çalışma başlatılmadı."
    if (nzchar(hata)) mesaj <- paste(mesaj, hata)

    return(list(
      ok = FALSE,
      blocked = TRUE,
      limited = TRUE,
      reason = "scan_unavailable",
      message = mesaj,
      metrics = list(
        file_count = scan$file_count %||% 0L,
        dir_count = scan$dir_count %||% 0L,
        total_bytes = scan$total_bytes %||% 0,
        truncated = isTRUE(scan$truncated),
        truncated_reason = scan$truncated_reason %||% "",
        errors = scan$errors %||% character(0)
      )
    ))
  }

  max_files <- cc_runtime_limit("preflight_max_files", 1500, limits)
  max_dirs <- cc_runtime_limit("preflight_max_dirs", 400, limits)
  max_bytes <- cc_runtime_limit("preflight_max_total_bytes", 256 * 1024^2, limits)

  asim <- character(0)
  if (scan$file_count > max_files) asim <- c(asim, "max_files")
  if (scan$dir_count > max_dirs) asim <- c(asim, "max_directories")
  if (scan$total_bytes > max_bytes) asim <- c(asim, "max_total_bytes")
  if (isTRUE(scan$truncated)) asim <- c(asim, scan$truncated_reason)

  asim <- unique(asim[nzchar(asim)])

  metrics <- list(
    file_count = scan$file_count,
    dir_count = scan$dir_count,
    total_bytes = scan$total_bytes,
    elapsed_ms = scan$elapsed_ms,
    truncated = isTRUE(scan$truncated),
    truncated_reason = scan$truncated_reason
  )

  if (!length(asim)) {
    return(list(
      ok = TRUE,
      blocked = FALSE,
      limited = FALSE,
      reason = "",
      message = "",
      metrics = metrics
    ))
  }

  # Sınır aşıldığında bile görev güvenli bir alt kümeyle sürdürülebilir;
  # bu yüzden çalıştırma engellenmez, yalnızca sınırlı mod bildirilir.
  list(
    ok = TRUE,
    blocked = FALSE,
    limited = TRUE,
    reason = paste(asim, collapse = ","),
    message = CLAUDE_CODE_LIMIT_MESSAGE,
    metrics = metrics
  )
}

# Kaynak dizini sınırlı biçimde tarar (preflight + girdi seçimi için ortak yol)
cc_scan_source_workdir <- function(source_dir, limits = NULL) {
  cc_scan_directory_bounded(
    root = source_dir,
    max_files = cc_runtime_limit("scan_max_files", 2000, limits),
    max_dirs = cc_runtime_limit("scan_max_dirs", 500, limits),
    max_depth = cc_runtime_limit("scan_max_depth", 6, limits),
    max_total_bytes = cc_runtime_limit("scan_max_total_bytes", 512 * 1024^2, limits),
    max_elapsed_ms = cc_runtime_limit("scan_timeout_ms", 4000, limits),
    # Preflight metadata accounting must include oversized files. The
    # per-file copy limit is applied later, when the bounded subset is chosen.
    max_file_bytes = Inf
  )
}

# ------------------------------------------------------------------------------
# GEREKLİ GİRDİ DOSYALARININ SEÇİMİ
# ------------------------------------------------------------------------------

#' Prompt metninde geçen dosya adlarını çıkar
#'
#' @param prompt Kullanıcı metni
#' @return Küçük harfe çevrilmiş aday dosya adları
cc_extract_prompt_file_mentions <- function(prompt) {
  metin <- enc2utf8(paste(as.character(prompt %||% ""), collapse = " "))
  if (!nzchar(metin)) return(character(0))

  eslesmeler <- tryCatch(
    regmatches(
      metin,
      gregexpr("[^\\s\"'`<>|:*?]+\\.[A-Za-z0-9]{1,8}\\b", metin, perl = TRUE)
    )[[1]],
    error = function(e) character(0)
  )

  if (!length(eslesmeler)) return(character(0))

  eslesmeler <- gsub("[\\\\/]+", "/", eslesmeler, perl = TRUE)
  eslesmeler <- sub("[.,;:)\\]]+$", "", eslesmeler, perl = TRUE)
  eslesmeler <- eslesmeler[nzchar(eslesmeler)]

  unique(tolower(eslesmeler))
}

.cc_prepare_mention_matches <- function(files, relatives, mentions) {
  if (!length(files) || !length(mentions)) return(logical(length(files)))

  rel_key <- tolower(relatives)
  base_key <- tolower(basename(files))

  vapply(seq_along(files), function(i) {
    any(vapply(mentions, function(m) {
      identical(m, base_key[i]) ||
        identical(m, rel_key[i]) ||
        endsWith(rel_key[i], paste0("/", m))
    }, logical(1)))
  }, logical(1))
}

#' Adı geçen dosyaları doğrudan diskte çöz (kesilmiş tarama yedeği)
#'
#' Sınırlı tarama, adı geçen dosya numaralandırılmadan önce kesilebilir. Bu
#' durumda otomatik alt kümeye düşmek yerine, güvenli göreli yol adaylarını
#' kökün altında doğrudan doğrularız. Mutlak yol, sürücü harfi ve `..`
#' geçişleri asla kabul edilmez; sonuç her zaman kökün içinde kalır.
#'
#' @param mentions Küçük harfli aday dosya adları/göreli yollar
#' @param root Kaynak kök dizin
#' @param max_files Doğrulanacak maksimum dosya sayısı
#' @return Kök altında var olan mutlak dosya yolları
cc_resolve_mentioned_files_on_disk <- function(mentions,
                                               root,
                                               max_files = 40L) {
  mentions <- unique(as.character(mentions %||% character(0)))
  mentions <- mentions[nzchar(mentions)]

  kok <- .cc_scan_norm(as.character(root %||% "")[1])
  if (!length(mentions) || !nzchar(kok) ||
      !isTRUE(tryCatch(dir.exists(kok), error = function(e) FALSE))) {
    return(character(0))
  }

  kok_key <- .cc_scan_key(kok)
  max_files <- max(0L, suppressWarnings(as.integer(max_files)))
  if (!is.finite(max_files) || max_files == 0L) return(character(0))

  bulunanlar <- character(0)

  for (aday in mentions) {
    if (length(bulunanlar) >= max_files) break

    rel <- gsub("\\", "/", aday, fixed = TRUE)
    rel <- sub("^\\./+", "", rel, perl = TRUE)

    # Mutlak yol / sürücü harfi / UNC / üst dizin geçişi kabul edilmez.
    if (grepl("^(?:[A-Za-z]:|/|//)", rel, perl = TRUE)) next
    if (grepl("(^|/)\\.\\.(/|$)", rel, perl = TRUE)) next
    if (!nzchar(rel)) next

    hedef <- .cc_scan_norm(file.path(kok, rel))
    hedef_key <- .cc_scan_key(hedef)

    if (!startsWith(hedef_key, paste0(kok_key, "/"))) next
    if (!isTRUE(file.exists(hedef)) || isTRUE(dir.exists(hedef))) next

    bulunanlar <- c(bulunanlar, hedef)
  }

  unique(bulunanlar)
}

#' Çalıştırma için gerçekten gerekli girdi dosyalarını seç
#'
#' Öncelik sırası: açıkça seçilen dosyalar, prompt içinde adı geçen dosyalar,
#' ardından sınırlı otomatik alt küme. Hiçbir durumda klasörün tamamı
#' "gerekli girdi" sayılmaz.
#'
#' @param prompt Kullanıcı metni
#' @param files Taranan dosya yolları
#' @param file_sizes Dosya boyutları
#' @param root Kaynak kök dizin
#' @param explicit_files UI tarafından açıkça seçilen dosyalar
#' @param limits Sınır listesi
#' @return list(files, relatives, total_bytes, selection_mode, skipped, truncated)
cc_select_input_files <- function(prompt,
                                  files,
                                  file_sizes = NULL,
                                  root = "",
                                  explicit_files = character(0),
                                  limits = NULL) {
  files <- as.character(files %||% character(0))
  bos <- list(
    files = character(0),
    relatives = character(0),
    total_bytes = 0,
    selection_mode = "none",
    skipped = character(0),
    truncated = FALSE
  )

  if (!length(files)) return(bos)

  boyutlar <- suppressWarnings(as.numeric(file_sizes %||% rep(NA_real_, length(files))))
  if (length(boyutlar) != length(files)) {
    boyutlar <- rep(NA_real_, length(files))
  }
  boyutlar[!is.finite(boyutlar)] <- 0

  relatives <- cc_scan_relative_paths(files, root)

  max_files <- cc_runtime_limit("max_input_files", 40, limits)
  max_file_bytes <- cc_runtime_limit("max_input_file_bytes", 25 * 1024^2, limits)
  max_total_bytes <- cc_runtime_limit("max_input_total_bytes", 100 * 1024^2, limits)
  auto_max <- cc_runtime_limit("auto_select_max_files", 25, limits)

  explicit_files <- as.character(explicit_files %||% character(0))
  explicit_key <- tolower(c(basename(explicit_files), gsub("\\", "/", explicit_files, fixed = TRUE)))
  explicit_key <- unique(explicit_key[nzchar(explicit_key)])

  secim_modu <- "auto"
  secilen_idx <- integer(0)

  if (length(explicit_key)) {
    secilen_idx <- which(.cc_prepare_mention_matches(files, relatives, explicit_key))
    if (length(secilen_idx)) secim_modu <- "explicit"
  }

  mentions <- cc_extract_prompt_file_mentions(prompt)

  if (!length(secilen_idx) && length(mentions)) {
    secilen_idx <- which(.cc_prepare_mention_matches(files, relatives, mentions))
    if (length(secilen_idx)) secim_modu <- "prompt"
  }

  # Tarama sınıra takıldıysa istenen dosya hiç numaralandırılmamış olabilir.
  # Bu durumda rastgele bir otomatik alt kümeye düşmeden önce, güvenli
  # göreli yol adaylarını doğrudan diskte çözeriz.
  istenen_anahtarlar <- unique(c(explicit_key, mentions))
  eksik_anahtarlar <- character(0)

  if (length(istenen_anahtarlar)) {
    eslesti <- vapply(
      istenen_anahtarlar,
      function(m) any(.cc_prepare_mention_matches(files, relatives, m)),
      logical(1),
      USE.NAMES = FALSE
    )
    eksik_anahtarlar <- istenen_anahtarlar[!eslesti]
  }

  if (length(eksik_anahtarlar) && nzchar(as.character(root %||% "")[1])) {
    diskten <- cc_resolve_mentioned_files_on_disk(
      mentions = eksik_anahtarlar,
      root = root,
      max_files = max_files
    )
    diskten <- setdiff(diskten, files)

    if (length(diskten)) {
      disk_boyut <- suppressWarnings(as.numeric(file.info(diskten)$size))
      disk_boyut[!is.finite(disk_boyut)] <- 0

      yeni_idx <- length(files) + seq_along(diskten)
      files <- c(files, diskten)
      boyutlar <- c(boyutlar, disk_boyut)
      relatives <- c(relatives, cc_scan_relative_paths(diskten, root))

      secilen_idx <- unique(c(secilen_idx, yeni_idx))
      if (!identical(secim_modu, "explicit")) secim_modu <- "prompt"
    }
  }

  if (!length(secilen_idx)) {
    # Prompt hiçbir dosyaya işaret etmiyorsa klasörün tamamı gerekli girdi
    # sayılmaz; yalnızca sınırlı ve deterministik bir alt küme kopyalanır.
    sira <- order(boyutlar, tolower(relatives))
    secilen_idx <- sira[seq_len(min(length(sira), max(0L, as.integer(auto_max))))]
    secim_modu <- "auto"
  }

  secilen_idx <- unique(secilen_idx)
  secilen_idx <- secilen_idx[order(tolower(relatives[secilen_idx]))]

  sonuc_dosyalar <- character(0)
  sonuc_rel <- character(0)
  atlananlar <- character(0)
  toplam <- 0
  kesildi <- FALSE

  for (i in secilen_idx) {
    if (length(sonuc_dosyalar) >= max_files) {
      kesildi <- TRUE
      break
    }

    if (boyutlar[i] > max_file_bytes) {
      atlananlar <- c(atlananlar, relatives[i])
      next
    }

    if (toplam + boyutlar[i] > max_total_bytes) {
      kesildi <- TRUE
      break
    }

    sonuc_dosyalar <- c(sonuc_dosyalar, files[i])
    sonuc_rel <- c(sonuc_rel, relatives[i])
    toplam <- toplam + boyutlar[i]
  }

  list(
    files = sonuc_dosyalar,
    relatives = sonuc_rel,
    total_bytes = toplam,
    selection_mode = secim_modu,
    skipped = unique(atlananlar),
    truncated = kesildi
  )
}

#' Seçilen girdi dosyalarını runtime input klasörüne kopyala
#'
#' Göreli klasör yapısı korunur; klasörün tamamı için özyinelemeli
#' file.copy() kullanılmaz.
#'
#' @param files Kaynak dosya yolları
#' @param relatives Köke göre göreli yollar
#' @param input_dir Hedef input klasörü
#' @return list(copied, failed, total_bytes, results)
cc_copy_files_to_runtime_input <- function(files, relatives, input_dir) {
  files <- as.character(files %||% character(0))
  relatives <- as.character(relatives %||% character(0))

  if (!length(files) || !nzchar(as.character(input_dir %||% "")[1])) {
    return(list(copied = character(0), failed = character(0), total_bytes = 0, results = list()))
  }

  if (length(relatives) != length(files)) {
    relatives <- basename(files)
  }

  kopyalananlar <- character(0)
  basarisizlar <- character(0)
  sonuclar <- list()
  toplam <- 0

  for (i in seq_along(files)) {
    hedef <- file.path(input_dir, relatives[i])
    hedef_dizin <- dirname(hedef)

    if (!dir.exists(hedef_dizin)) {
      dir.create(hedef_dizin, recursive = TRUE, showWarnings = FALSE)
    }

    ok <- tryCatch(
      file.copy(
        from = files[i],
        to = hedef,
        overwrite = TRUE,
        copy.mode = TRUE,
        copy.date = TRUE
      ),
      error = function(e) FALSE
    )

    if (!isTRUE(ok) || !isTRUE(file.exists(hedef))) {
      basarisizlar <- c(basarisizlar, relatives[i])
      sonuclar[[length(sonuclar) + 1L]] <- list(
        source_path = files[i],
        dest_path = hedef,
        success = FALSE,
        size = NA_real_,
        error = "Dosya kopyalanamadı"
      )
      next
    }

    boyut <- suppressWarnings(as.numeric(file.info(hedef)$size[1]))
    if (!is.finite(boyut)) boyut <- 0
    toplam <- toplam + boyut

    kopyalananlar <- c(kopyalananlar, hedef)
    sonuclar[[length(sonuclar) + 1L]] <- list(
      source_path = files[i],
      dest_path = hedef,
      success = TRUE,
      size = boyut,
      error = ""
    )
  }

  list(
    copied = kopyalananlar,
    failed = basarisizlar,
    total_bytes = toplam,
    results = sonuclar
  )
}

#' Bu çalıştırma için işlenecek dokümanları sınırlı biçimde seç
#'
#' Büyük bir klasördeki her doküman işlenmez. Öncelik sırası: açıkça seçilen
#' dosyalar, prompt içinde adı geçen dosyalar, ardından sınırlı alt küme.
#'
#' @param prompt Kullanıcı metni
#' @param documents Aday doküman yolları
#' @param explicit_files Açıkça seçilen dosyalar
#' @param limits Sınır listesi
#' @return list(files, selection_mode, skipped, truncated)
cc_select_documents_for_request <- function(prompt,
                                            documents,
                                            explicit_files = character(0),
                                            limits = NULL) {
  documents <- unique(as.character(documents %||% character(0)))

  if (!length(documents)) {
    return(list(
      files = character(0),
      selection_mode = "none",
      skipped = character(0),
      truncated = FALSE
    ))
  }

  max_docs <- cc_runtime_limit("max_documents", 10, limits)
  max_doc_bytes <- cc_runtime_limit("max_document_bytes", 25 * 1024^2, limits)
  max_total_bytes <- cc_runtime_limit("max_documents_total_bytes", 80 * 1024^2, limits)

  adlar <- tolower(basename(documents))

  anahtarlar <- unique(tolower(c(
    basename(as.character(explicit_files %||% character(0))),
    cc_extract_prompt_file_mentions(prompt)
  )))
  anahtarlar <- anahtarlar[nzchar(anahtarlar)]

  secilen_idx <- integer(0)
  secim_modu <- "auto"

  if (length(anahtarlar)) {
    secilen_idx <- which(adlar %in% anahtarlar)
    if (length(secilen_idx)) secim_modu <- "prompt"
  }

  if (!length(secilen_idx)) {
    secilen_idx <- order(adlar)
  }

  boyutlar <- suppressWarnings(as.numeric(file.info(documents)$size))
  boyutlar[!is.finite(boyutlar)] <- 0

  secilenler <- character(0)
  atlananlar <- character(0)
  toplam <- 0
  kesildi <- FALSE

  for (i in secilen_idx) {
    if (length(secilenler) >= max_docs) {
      kesildi <- TRUE
      break
    }

    if (boyutlar[i] > max_doc_bytes) {
      atlananlar <- c(atlananlar, basename(documents[i]))
      next
    }

    if (toplam + boyutlar[i] > max_total_bytes) {
      kesildi <- TRUE
      break
    }

    secilenler <- c(secilenler, documents[i])
    toplam <- toplam + boyutlar[i]
  }

  list(
    files = secilenler,
    selection_mode = secim_modu,
    skipped = unique(atlananlar),
    truncated = kesildi
  )
}
