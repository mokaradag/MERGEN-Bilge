# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_workdir_scan.R
# Açıklama: Bilge Yolaç çalışma dizini için niyet tespiti, dosya yolu
#           kanonikleştirme, snapshot/diff üretimi ve yeni/değişen dosyaların
#           kısa süreli kararlılık kontrolü yardımcılarını içerir.
#           Bu dosya yalnızca tarama/karşılaştırma sorumluluğunu taşır;
#           Türkçe metin kodlama normalizasyonu ve indirme staging akışı
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
#' @param workdir Taranacak kök dizin
#' @param recursive Alt dizinleri de tara (varsayılan TRUE)
#' @param max_files Performans için üst sınır
#' @return Yol -> list(mtime, size) biçiminde isimlendirilmiş liste
snapshot_claude_code_workdir_files <- function(workdir,
                                                recursive = TRUE,
                                                max_files = 5000L) {
  if (is.null(workdir) || !nzchar(workdir) || !dir.exists(workdir)) {
    return(list())
  }

  ogeler <- tryCatch(
    list.files(
      workdir,
      full.names = TRUE,
      recursive = recursive,
      all.files = FALSE,
      include.dirs = FALSE,
      no.. = TRUE
    ),
    error = function(e) character(0)
  )

  if (!length(ogeler)) {
    return(list())
  }

  # Yalnızca gerçek dosyaları tut (yanlışlıkla dizin yakalanmışsa çıkar)
  ogeler <- ogeler[!dir.exists(ogeler)]

  if (!length(ogeler)) {
    return(list())
  }

  if (length(ogeler) > max_files) {
    ogeler <- ogeler[seq_len(max_files)]
  }

  bilgi <- tryCatch(file.info(ogeler), error = function(e) NULL)

  if (is.null(bilgi) || nrow(bilgi) == 0L) {
    return(list())
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

  sonuc
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
                                               max_files = 5000L) {
  if (is.null(workdir) || !nzchar(workdir) || !dir.exists(workdir)) {
    return(character(0))
  }

  sonraki <- snapshot_claude_code_workdir_files(
    workdir = workdir,
    recursive = recursive,
    max_files = max_files
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
    "/\\.document_support/"
  )

  for (desen in haric_desenler) {
    yeni_veya_degisen <- yeni_veya_degisen[
      !grepl(desen, yeni_veya_degisen, perl = TRUE)
    ]
  }

  # Kanonik form üzerinden tekrar dedup (emniyet kemeri)
  deduplicate_claude_code_file_paths(yeni_veya_degisen)
}

#' Yeni/değişen dosyaların kısa süreli kararlı hale gelmesini bekle
#'
#' Claude Code CLI döndükten hemen sonra Windows üzerinde dosya mtime/size
#' bilgileri kısa süre oynayabilir veya child process dosyayı yeni kapatmış
#' olabilir. Bu yardımcı, staging/encoding normalizasyonu başlamadan önce
#' dosya imzasını kısa aralıklarla kontrol eder. Maksimum denemeden sonra
#' dosyaları düşürmez; son görülen mevcut dosya listesini döndürerek önceki
#' davranışı korur.
#'
#' @param file_paths Dosya yolları
#' @param settle_ms Denemeler arasındaki bekleme süresi (ms)
#' @param max_attempts Maksimum kontrol sayısı
#' @return Kanonik, mevcut ve dosya olan yollar
wait_for_stable_claude_code_file_paths <- function(file_paths,
                                                    settle_ms = 75L,
                                                    max_attempts = 4L) {
  file_paths <- deduplicate_claude_code_file_paths(file_paths)
  if (!length(file_paths)) return(character(0))

  settle_ms <- suppressWarnings(as.integer(settle_ms[1] %||% 75L))
  if (is.na(settle_ms) || settle_ms < 0L) {
    settle_ms <- 75L
  }

  max_attempts <- suppressWarnings(as.integer(max_attempts[1] %||% 4L))
  if (is.na(max_attempts) || max_attempts < 1L) {
    max_attempts <- 1L
  }

  file_signature <- function(paths) {
    mevcut <- paths[file.exists(paths) & !dir.exists(paths)]
    mevcut <- deduplicate_claude_code_file_paths(mevcut)

    if (!length(mevcut)) {
      return(data.frame(
        path = character(0),
        size = numeric(0),
        mtime = numeric(0),
        stringsAsFactors = FALSE
      ))
    }

    bilgi <- tryCatch(file.info(mevcut), error = function(e) NULL)
    if (is.null(bilgi) || nrow(bilgi) == 0L) {
      return(data.frame(
        path = character(0),
        size = numeric(0),
        mtime = numeric(0),
        stringsAsFactors = FALSE
      ))
    }

    sonuc <- data.frame(
      path = mevcut,
      size = suppressWarnings(as.numeric(bilgi$size)),
      mtime = suppressWarnings(as.numeric(bilgi$mtime)),
      stringsAsFactors = FALSE
    )

    sonuc <- sonuc[order(tolower(sonuc$path)), , drop = FALSE]
    rownames(sonuc) <- NULL
    sonuc
  }

  same_signature <- function(a, b) {
    if (!is.data.frame(a) || !is.data.frame(b)) return(FALSE)
    if (!identical(nrow(a), nrow(b))) return(FALSE)
    if (!identical(a$path, b$path)) return(FALSE)

    same_size <- isTRUE(all.equal(a$size, b$size, check.attributes = FALSE))
    same_mtime <- isTRUE(all.equal(a$mtime, b$mtime, check.attributes = FALSE))

    isTRUE(same_size) && isTRUE(same_mtime)
  }

  previous <- file_signature(file_paths)
  if (nrow(previous) == 0L) {
    return(character(0))
  }

  latest <- previous

  for (attempt in seq_len(max_attempts)) {
    if (settle_ms > 0L) {
      Sys.sleep(settle_ms / 1000)
    }

    current <- file_signature(file_paths)
    if (nrow(current) == 0L) {
      return(character(0))
    }

    latest <- current

    if (isTRUE(same_signature(previous, current))) {
      return(deduplicate_claude_code_file_paths(current$path))
    }

    previous <- current
  }

  deduplicate_claude_code_file_paths(latest$path)
}