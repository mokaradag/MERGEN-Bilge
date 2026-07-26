# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_workdir_scan.R
# Açıklama: Bilge Yolaç çalışma dizini için niyet tespiti, dosya yolu
#           kanonikleştirme ve sınırlı snapshot/diff üretimi yardımcılarını
#           içerir. Bu dosya yalnızca tarama/karşılaştırma sorumluluğunu taşır.
#           Dosya kararlılık beklemesi R/helpers_claude_code_file_stability.R,
#           runtime çıktı bölgesi anlık görüntüsü ve geri aktarım planı
#           R/helpers_claude_code_output_sync.R, Türkçe metin kodlama
#           normalizasyonu ve indirme staging akışı
#           R/helpers_claude_code_workdir_snapshot.R içinde kalır.
# ==============================================================================

# ------------------------------------------------------------------------------
# NİYET TESPİTİ: İKİLİ DOKÜMAN ÜRETME / MEVCUTU OKUMA
# ------------------------------------------------------------------------------

#' Kullanıcının ikili doküman ÜRETME niyeti olup olmadığını tespit et
#'
#' @param prompt Kullanıcı metni
#' @return TRUE/FALSE
prompt_requests_binary_document_creation <- function(prompt) {
  metin <- tolower(enc2utf8(paste(as.character(prompt %||% ""), collapse = " ")))
  if (!nzchar(metin)) return(FALSE)

  # Türkçe + İngilizce üretme/yazma/kaydetme fiilleri
  uretme_deseni <- paste(
    c(
      "olu\\u015ftur",       # oluştur
      "olustur",
      "yarat",
      "\\u00fcret",          # üret
      "uret",
      "haz\\u0131rla",       # hazırla
      "hazirla",
      "yaz\\u0131l",         # yazıl
      "yazil",
      "kaydet",
      "d\\u00f6n\\u00fc\\u015ft\\u00fcr",  # dönüştür
      "donustur",
      "ekspor",
      "export",
      "generate",
      "create",
      "write",
      "produce",
      "save"
    ),
    collapse = "|"
  )

  if (!grepl(uretme_deseni, metin, perl = TRUE)) return(FALSE)

  # Üretim fiilinin yanında ikili doküman uzantısı veya adı geçmeli
  ikili_deseni <- paste(
    c(
      "\\.docx",
      "\\.doc\\b",
      "\\.xlsx",
      "\\.xls\\b",
      "\\.pdf",
      "\\.pptx",
      "\\.ppt\\b",
      "\\bdocx\\b",
      "\\bxlsx\\b",
      "\\bpdf\\b",
      "\\bpptx\\b",
      "\\bword\\b",
      "\\bexcel\\b",
      "\\bpowerpoint\\b"
    ),
    collapse = "|"
  )

  grepl(ikili_deseni, metin, perl = TRUE)
}

#' Kullanıcının MEVCUT ikili dokümanı OKUMA niyetini tespit et
#'
#' @param prompt Kullanıcı metni
#' @return TRUE/FALSE
prompt_requests_existing_document_reading <- function(prompt) {
  metin <- tolower(enc2utf8(paste(as.character(prompt %||% ""), collapse = " ")))
  if (!nzchar(metin)) return(FALSE)

  okuma_deseni <- paste(
    c(
      "\\bokuy",            # oku / okuy...
      "\\boku\\b",
      "incele",
      "\\u00f6zetle",        # özetle
      "ozetle",
      "\\u00f6zet\\u00e7",    # özetç...
      "\\u00e7\\u0131kar",    # çıkar (metni çıkar)
      "cikar",
      "i\\u00e7eri\\u011fi",  # içeriği
      "icerigi",
      "summari",
      "\\bread\\b",
      "\\bextract"
    ),
    collapse = "|"
  )

  grepl(okuma_deseni, metin, perl = TRUE)
}

# ------------------------------------------------------------------------------
# YOL KANONİKLEŞTİRME
# Windows 8.3 kısa dosya adlarını (R_HELP~1.TXT gibi) uzun kanonik forma
# çevirir. Aynı dosyanın hem uzun hem kısa formda indirme listesine
# eklenmesini engeller.
# ------------------------------------------------------------------------------

#' Dosya yolunu kanonik (uzun, mutlak) forma çevir
#'
#' @param path Ham dosya yolu
#' @return Kanonik yol veya orijinal değer
canonicalize_claude_code_file_path <- function(path) {
  path <- as.character(path %||% "")[1]
  if (!nzchar(path)) return("")

  # Dosya diskte mevcutsa mustWork = TRUE ile Windows 8.3 kısa adları uzun
  # forma çözümle. normalizePath(mustWork = TRUE) Windows'ta bu çözümü yapar.
  sonuc <- tryCatch(
    normalizePath(path, winslash = "/", mustWork = TRUE),
    error = function(e) NA_character_
  )

  if (is.na(sonuc) || !nzchar(sonuc)) {
    sonuc <- tryCatch(
      normalizePath(path, winslash = "/", mustWork = FALSE),
      error = function(e) path
    )
  }

  if (is.na(sonuc) || !nzchar(sonuc)) {
    return(path)
  }

  sonuc
}

#' Birden çok dosya yolunu kanonikleştir ve tekrarları kaldır
#'
#' Windows'ta büyük/küçük harf farkı olabileceği için karşılaştırmayı da
#' küçük harfe göre yapar; gerçek yolun kanonik hali korunur.
#'
#' @param paths Dosya yolları
#' @return Tekrarsız kanonik yol vektörü
deduplicate_claude_code_file_paths <- function(paths) {
  paths <- unique(Filter(nzchar, as.character(paths %||% character(0))))
  if (!length(paths)) return(character(0))

  kanonikler <- vapply(
    paths,
    canonicalize_claude_code_file_path,
    character(1),
    USE.NAMES = FALSE
  )

  kanonikler <- kanonikler[nzchar(kanonikler)]
  if (!length(kanonikler)) return(character(0))

  # Windows'ta büyük/küçük harf farkını da yok say
  anahtarlar <- tolower(kanonikler)
  ilk_gorunumler <- !duplicated(anahtarlar)

  kanonikler[ilk_gorunumler]
}

# ------------------------------------------------------------------------------
# ÇALIŞMA DİZİNİ ANLIK GÖRÜNTÜSÜ
# Claude Code çalıştırılmadan önce dizindeki tüm dosyaların (mtime + boyut)
# haritasını çıkarır. Çalıştırma bittiğinde karşılaştırma yapılır ve
# yeni/değişmiş dosyalar tespit edilir.
# ------------------------------------------------------------------------------

#' Çalışma dizinindeki dosyaların anlık görüntüsünü al
#'
#' Tarama sınırlı gezinme ile yapılır: tüm ağaç numaralandırılıp sonradan
#' kırpılmaz, sınıra ulaşıldığı anda durulur. Sonuca `scan` özniteliği ile
#' tarama metrikleri (kesilme nedeni dahil) eklenir.
#'
#' @param workdir Taranacak kök dizin
#' @param recursive Alt dizinleri de tara (varsayılan TRUE)
#' @param max_files Performans için üst sınır
#' @param exclude_dirs Atlanacak dizin adları
#' @param max_depth Maksimum derinlik
#' @param limits Sınır listesi
#' @return Yol -> list(mtime, size) biçiminde isimlendirilmiş liste
snapshot_claude_code_workdir_files <- function(workdir,
                                                recursive = TRUE,
                                                max_files = NULL,
                                                exclude_dirs = cc_scan_default_excluded_dirs(),
                                                max_depth = NULL,
                                                limits = NULL) {
  if (is.null(workdir) || !nzchar(workdir) || !dir.exists(workdir)) {
    return(list())
  }

  max_files <- if (is.null(max_files)) {
    cc_runtime_limit("output_scan_max_files", 1000, limits)
  } else {
    suppressWarnings(as.numeric(max_files[1]))
  }

  max_depth <- if (is.null(max_depth)) {
    cc_runtime_limit("output_scan_max_depth", 8, limits)
  } else {
    suppressWarnings(as.numeric(max_depth[1]))
  }

  if (!isTRUE(recursive)) {
    max_depth <- 0
  }

  tarama <- tryCatch(
    cc_scan_directory_bounded(
      root = workdir,
      max_files = max_files,
      max_dirs = cc_runtime_limit("scan_max_dirs", 500, limits),
      max_depth = max_depth,
      max_total_bytes = Inf,
      max_elapsed_ms = cc_runtime_limit("scan_timeout_ms", 4000, limits),
      max_file_bytes = Inf,
      exclude_dirs = exclude_dirs
    ),
    error = function(e) NULL
  )

  if (is.null(tarama) || !length(tarama$files)) {
    return(structure(list(), scan = tarama))
  }

  ogeler <- tarama$files
  bilgi <- tryCatch(file.info(ogeler), error = function(e) NULL)

  if (is.null(bilgi) || nrow(bilgi) == 0L) {
    return(structure(list(), scan = tarama))
  }

  sonuc <- list()

  for (i in seq_along(ogeler)) {
    # Windows 8.3 kısa adları uzun kanonik forma çevir
    yol_norm <- canonicalize_claude_code_file_path(ogeler[i])

    if (!nzchar(yol_norm)) next

    mtime_val <- suppressWarnings(as.numeric(bilgi$mtime[i]))
    size_val <- suppressWarnings(as.numeric(bilgi$size[i]))

    # Anahtarı küçük harfe çevir (Windows case-insensitive)
    anahtar <- tolower(yol_norm)

    sonuc[[anahtar]] <- list(
      path = yol_norm,
      mtime = if (is.finite(mtime_val)) mtime_val else NA_real_,
      size = if (is.finite(size_val)) size_val else NA_real_
    )
  }

  if (isTRUE(tarama$truncated)) {
    log_warn(sprintf(
      "%s [OUTPUT_DIFF] Çıktı taraması sınıra takıldı (%s); üretilen dosya listesi eksik olabilir.",
      CLAUDE_CODE_LOG_PREFIX,
      tarama$truncated_reason
    ))
  }

  structure(sonuc, scan = tarama)
}

#' İki anlık görüntü arasındaki yeni veya değişmiş dosyaları döndür
#'
#' @param before_snapshot snapshot_claude_code_workdir_files çıktısı
#' @param workdir Tekrar taranacak dizin
#' @param recursive Alt dizinleri de tara
#' @param max_files Üst sınır
#' @return Yeni/değişmiş dosyaların yollarını içeren karakter vektörü
diff_claude_code_workdir_snapshot <- function(before_snapshot,
                                               workdir,
                                               recursive = TRUE,
                                               max_files = NULL,
                                               exclude_dirs = cc_scan_default_excluded_dirs(),
                                               limits = NULL) {
  if (is.null(workdir) || !nzchar(workdir) || !dir.exists(workdir)) {
    return(character(0))
  }

  sonraki <- snapshot_claude_code_workdir_files(
    workdir = workdir,
    recursive = recursive,
    max_files = max_files,
    exclude_dirs = exclude_dirs,
    limits = limits
  )

  if (!length(sonraki)) {
    return(character(0))
  }

  once <- if (is.list(before_snapshot)) before_snapshot else list()

  yeni_veya_degisen <- character(0)

  for (anahtar in names(sonraki)) {
    eski <- once[[anahtar]]
    yeni <- sonraki[[anahtar]]

    # Kanonik yolu liste girdisinden al (eski sürümler sadece key tutuyor olabilir)
    yeni_yol <- yeni$path %||% anahtar
    if (!nzchar(yeni_yol)) next

    if (is.null(eski)) {
      yeni_veya_degisen <- c(yeni_veya_degisen, yeni_yol)
      next
    }

    degisti <- FALSE

    if (!isTRUE(all.equal(eski$mtime, yeni$mtime))) {
      degisti <- TRUE
    }

    if (!isTRUE(all.equal(eski$size, yeni$size))) {
      degisti <- TRUE
    }

    if (isTRUE(degisti)) {
      yeni_veya_degisen <- c(yeni_veya_degisen, yeni_yol)
    }
  }

  # Bilge Yolaç iç yardımcı çıktılarını hariç tut
  # (doküman özet destek dizini, rehber dosyası vb.)
  haric_desenler <- c(
    "/BILGE_YOLAC_DOKUMAN_REHBERI\\.md$",
    "/document_support/",
    "/\\.document_support/",
    "/input/",
    "/metadata/"
  )

  for (desen in haric_desenler) {
    yeni_veya_degisen <- yeni_veya_degisen[
      !grepl(desen, yeni_veya_degisen, perl = TRUE)
    ]
  }

  # Kanonik form üzerinden tekrar dedup (emniyet kemeri)
  deduplicate_claude_code_file_paths(yeni_veya_degisen)
}
