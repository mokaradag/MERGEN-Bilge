# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_documents.R
# Açıklama: Bilge Yolaç için PDF/XLS/XLSX dokümanlarını çevrimdışı olarak
#           metne dönüştürür, rehber dosyası üretir ve çalışma prompt'una
#           güvenli doküman kullanım yönergeleri ekler.
# ==============================================================================

get_claude_code_binary_doc_extensions <- function() {
  exts <- tryCatch(
    get_claude_code_model_capabilities()$binary_doc_extensions,
    error = function(e) c("pdf", "xlsx", "xls")
  )

  exts <- unique(tolower(as.character(exts %||% c("pdf", "xlsx", "xls"))))
  exts[nzchar(exts)]
}

get_claude_code_text_extractable_extensions <- function() {
  c("pdf", "xlsx", "xls")
}

sanitize_claude_doc_cache_name <- function(x) {
  x <- enc2utf8(as.character(x %||% "dokuman"))
  x <- gsub("[^A-Za-z0-9._-]+", "_", x, perl = TRUE)
  x <- gsub("_+", "_", x, perl = TRUE)
  x <- gsub("^_+|_+$", "", x, perl = TRUE)

  if (!nzchar(x)) {
    x <- "dokuman"
  }

  x
}

truncate_claude_doc_text <- function(metin, max_karakter = 120000L) {
  metin <- enc2utf8(paste(as.character(metin %||% ""), collapse = "\n"))

  if (!nzchar(metin)) {
    return("")
  }

  if (nchar(metin, type = "chars", allowNA = FALSE, keepNA = FALSE) <= max_karakter) {
    return(metin)
  }

  paste0(
    substr(metin, 1, max_karakter),
    "\n\n[METIN KISALTILDI]"
  )
}

list_claude_code_binary_documents <- function(workdir, extensions = NULL) {
  if (is.null(workdir) || !nzchar(workdir) || !dir.exists(workdir)) {
    return(character(0))
  }

  if (is.null(extensions) || !length(extensions)) {
    extensions <- get_claude_code_binary_doc_extensions()
  }

  ogeler <- tryCatch(
    list.files(
      workdir,
      full.names = TRUE,
      recursive = FALSE,
      all.files = FALSE,
      include.dirs = FALSE
    ),
    error = function(e) character(0)
  )

  if (!length(ogeler)) {
    return(character(0))
  }

  uzantilar <- tolower(tools::file_ext(ogeler))

  unique(ogeler[nzchar(uzantilar) & uzantilar %in% tolower(extensions)])
}

get_claude_code_document_support_dir <- function(user_id = NULL) {
  hedef <- file.path(
    tempdir(),
    "claude_code_runtime",
    paste0("user_", as.character(user_id %||% "default")),
    "document_support"
  )

  if (dir.exists(hedef)) {
    unlink(hedef, recursive = TRUE, force = TRUE)
  }

  dir.create(hedef, recursive = TRUE, showWarnings = FALSE)

  normalizePath(hedef, winslash = "/", mustWork = FALSE)
}

extract_pdf_text_for_claude <- function(dosya_yolu,
                                        max_sayfa = 25L,
                                        max_karakter = 120000L) {
  sayfa_metinleri <- pdftools::pdf_text(dosya_yolu)

  if (!length(sayfa_metinleri)) {
    return("")
  }

  if (is.finite(max_sayfa) && length(sayfa_metinleri) > max_sayfa) {
    sayfa_metinleri <- sayfa_metinleri[seq_len(max_sayfa)]
  }

  parcalar <- c()

  for (i in seq_along(sayfa_metinleri)) {
    parcalar <- c(
      parcalar,
      paste0("=== PDF SAYFA ", i, " ==="),
      sayfa_metinleri[[i]],
      ""
    )
  }

  truncate_claude_doc_text(
    paste(parcalar, collapse = "\n"),
    max_karakter = max_karakter
  )
}

extract_excel_text_for_claude <- function(dosya_yolu,
                                          max_sayfa = 5L,
                                          max_satir = 60L,
                                          max_sutun = 20L,
                                          max_karakter = 120000L) {
  sayfalar <- readxl::excel_sheets(dosya_yolu)

  if (!length(sayfalar)) {
    return("")
  }

  if (is.finite(max_sayfa) && length(sayfalar) > max_sayfa) {
    sayfalar <- sayfalar[seq_len(max_sayfa)]
  }

  parcalar <- c()

  for (sayfa in sayfalar) {
    veri <- tryCatch(
      readxl::read_excel(
        dosya_yolu,
        sheet = sayfa,
        n_max = max_satir,
        .name_repair = "unique_quiet"
      ),
      error = function(e) NULL
    )

    if (is.null(veri)) {
      veri <- tryCatch(
        safe_read_excel_table(
          dosya_yolu,
          sheet = sayfa,
          n_max = max_satir
        ),
        error = function(e) NULL
      )
    }

    parcalar <- c(
      parcalar,
      paste0("=== EXCEL SAYFA: ", sayfa, " ===")
    )

    if (is.null(veri) || ncol(veri) == 0 || nrow(veri) == 0) {
      parcalar <- c(parcalar, "(Boş veya okunamadı)", "")
      next
    }

    veri <- as.data.frame(veri, stringsAsFactors = FALSE)

    if (ncol(veri) > max_sutun) {
      veri <- veri[, seq_len(max_sutun), drop = FALSE]
    }

    veri[] <- lapply(veri, function(sutun) {
      if (is.list(sutun)) {
        vapply(
          sutun,
          function(x) paste(as.character(x), collapse = ", "),
          character(1)
        )
      } else {
        as.character(sutun)
      }
    })

    tablo_satirlari <- utils::capture.output(
      print(veri, row.names = FALSE, right = FALSE)
    )

    parcalar <- c(parcalar, tablo_satirlari, "")
  }

  truncate_claude_doc_text(
    paste(parcalar, collapse = "\n"),
    max_karakter = max_karakter
  )
}

extract_supported_document_text_for_claude <- function(dosya_yolu) {
  uzanti <- tolower(tools::file_ext(dosya_yolu))

  if (identical(uzanti, "pdf")) {
    return(extract_pdf_text_for_claude(dosya_yolu))
  }

  if (uzanti %in% c("xlsx", "xls")) {
    return(extract_excel_text_for_claude(dosya_yolu))
  }

  stop(paste("Desteklenmeyen doküman uzantısı:", uzanti))
}

get_office_document_reader_template_path <- function() {
  uygulama_koku <- resolve_app_root()

  aday <- file.path(
    uygulama_koku,
    "bilge_yolac_plugins",
    "office",
    "templates",
    "document_readers.R"
  )

  if (!file.exists(aday)) {
    return("")
  }

  normalizePath(aday, winslash = "/", mustWork = FALSE)
}

write_claude_code_document_manifest <- function(hedef_yol,
                                                hazir_dosyalar,
                                                orijinal_prompt = "",
                                                reader_template_path = "") {
  satirlar <- c(
    "# Bilge Yolaç Doküman Rehberi",
    "",
    "Bu dosya Bilge Yolaç tarafından otomatik üretildi.",
    "Amaç, PDF/XLS/XLSX gibi ikili dosyaları doğrudan binary olarak okumadan",
    "metin çıkarımları üzerinden çalışmaktır.",
    "",
    "## Kullanıcının Asıl İsteği",
    enc2utf8(orijinal_prompt %||% ""),
    "",
    "## Hazır Metin Çıkarımları"
  )

  if (!length(hazir_dosyalar)) {
    satirlar <- c(satirlar, "- Hazır metin çıkarımı yok.", "")
  }

  for (oge in hazir_dosyalar) {
    satirlar <- c(
      satirlar,
      paste0("- Orijinal dosya: ", oge$source_path %||% ""),
      paste0("  - Çıkarılmış metin: ", oge$text_path %||% ""),
      paste0("  - Durum: ", oge$status %||% "hazır"),
      ""
    )
  }

  if (nzchar(reader_template_path)) {
    satirlar <- c(
      satirlar,
      "## Yerel Yardımcı Şablon",
      paste0(
        "- Gerekirse şu dosyayı source ederek yeniden çıkarım üret: ",
        reader_template_path
      ),
      "- Binary dokümanları doğrudan Read aracıyla okumak yerine",
      "  bu yardımcıyı veya hazır .txt dosyalarını kullan.",
      ""
    )
  }

  writeLines(enc2utf8(satirlar), hedef_yol, useBytes = TRUE)

  normalizePath(hedef_yol, winslash = "/", mustWork = FALSE)
}

build_claude_code_document_inline_payload <- function(hazir_dosyalar,
                                                      max_toplam_karakter = 90000L) {
  if (!length(hazir_dosyalar)) {
    return("")
  }

  parcalar <- c(
    "AŞAĞIDA DİZİNDEKİ DOSYALARDAN ÖNCEDEN ÇIKARILMIŞ METİNLER VARDIR.",
    "BU GÖREV İÇİN AYRICA ARAÇ KULLANMA.",
    "DOĞRUDAN BU METİNLERİ OKUYUP ÖZETLE.",
    ""
  )

  kalan <- max_toplam_karakter

  for (oge in hazir_dosyalar) {
    metin <- tryCatch(
      paste(readLines(oge$text_path, warn = FALSE), collapse = "\n"),
      error = function(e) ""
    )

    metin <- enc2utf8(metin)

    if (!nzchar(metin)) {
      next
    }

    blok <- paste0(
      "===== DOSYA: ", basename(oge$source_path %||% oge$text_path %||% ""), " =====\n",
      metin
    )

    blok_uzunluk <- nchar(blok, type = "chars", allowNA = FALSE, keepNA = FALSE)

    if (blok_uzunluk > kalan) {
      blok <- substr(blok, 1, max(0, kalan))
      blok <- paste0(blok, "\n\n[METIN KISALTILDI]")
      parcalar <- c(parcalar, blok)
      break
    }

    parcalar <- c(parcalar, blok, "")
    kalan <- kalan - blok_uzunluk

    if (kalan <= 0) {
      break
    }
  }

  paste(parcalar, collapse = "\n\n")
}

build_claude_code_document_prompt <- function(orijinal_prompt,
                                              manifest_path = "",
                                              reader_template_path = "",
                                              unsupported_files = character(0)) {
  satirlar <- c(
    "SİSTEM ÇALIŞMA NOTU:",
    "Bu görev ikili ofis dokümanları içeriyor.",
    "PDF/XLS/XLSX dosyalarını doğrudan ikili içerik olarak Read etme.",
    "Yalnızca düz metin çıkarımlarıyla çalış."
  )

  if (nzchar(manifest_path)) {
    satirlar <- c(
      satirlar,
      paste0("Önce şu rehberi oku: ", manifest_path)
    )
  }

  if (nzchar(reader_template_path)) {
    satirlar <- c(
      satirlar,
      paste0(
        "Yeni metin çıkarımı gerekirse şu yerel yardımcıyı kullan: ",
        reader_template_path
      )
    )
  }

  if (length(unsupported_files)) {
    satirlar <- c(
      satirlar,
      paste0(
        "Hazır metin çıkarımı üretilemeyen dosyalar: ",
        paste(unique(unsupported_files), collapse = ", ")
      )
    )
  }

  satirlar <- c(
    satirlar,
    "Araç sonuçlarında yalnız metin döndür; binary document blokları üretme.",
    "",
    "KULLANICININ ASIL İSTEĞİ:",
    enc2utf8(orijinal_prompt %||% "")
  )

  paste(satirlar, collapse = "\n")
}

prepare_claude_code_document_context <- function(prompt,
                                                 runtime_workdir,
                                                 source_workdir = NULL,
                                                 user_id = NULL) {
  sonuc <- list(
    prompt = prompt,
    has_binary_docs = FALSE,
    text_sidecars_ready = FALSE,
    prepared_files = list(),
    unsupported_files = character(0),
    manifest_path = "",
    reader_template_path = "",
    support_dir = ""
  )

  kontrol_dizini <- source_workdir %||% runtime_workdir

  dokuman_gorevi <- isTRUE(prompt_mentions_binary_document_type(prompt)) ||
    (
      isTRUE(prompt_requests_document_operation(prompt)) &&
        isTRUE(
          workdir_has_binary_documents(
            kontrol_dizini,
            get_claude_code_binary_doc_extensions()
          )
        )
    )

  if (!isTRUE(dokuman_gorevi)) {
    return(sonuc)
  }

  dokumanlar <- list_claude_code_binary_documents(kontrol_dizini)

  if (!length(dokumanlar)) {
    return(sonuc)
  }

  sonuc$has_binary_docs <- TRUE

  destek_dizini <- get_claude_code_document_support_dir(user_id = user_id)
  reader_template_path <- get_office_document_reader_template_path()

  hazir_dosyalar <- list()
  unsupported_files <- character(0)
  desteklenen_uzantilar <- get_claude_code_text_extractable_extensions()

  for (i in seq_along(dokumanlar)) {
    dosya_yolu <- normalizePath(dokumanlar[[i]], winslash = "/", mustWork = FALSE)
    uzanti <- tolower(tools::file_ext(dosya_yolu))

    if (!(uzanti %in% desteklenen_uzantilar)) {
      unsupported_files <- c(unsupported_files, basename(dosya_yolu))
      next
    }

    hedef_txt <- file.path(
      destek_dizini,
      sprintf(
        "%02d_%s.txt",
        i,
        sanitize_claude_doc_cache_name(basename(dosya_yolu))
      )
    )

    metin <- tryCatch(
      extract_supported_document_text_for_claude(dosya_yolu),
      error = function(e) ""
    )

    if (!nzchar(metin)) {
      unsupported_files <- c(unsupported_files, basename(dosya_yolu))
      next
    }

    writeLines(enc2utf8(metin), hedef_txt, useBytes = TRUE)

    hazir_dosyalar[[length(hazir_dosyalar) + 1]] <- list(
      source_path = dosya_yolu,
      text_path = normalizePath(hedef_txt, winslash = "/", mustWork = FALSE),
      status = "hazır"
    )
  }

  manifest_path <- write_claude_code_document_manifest(
    hedef_yol = file.path(destek_dizini, "BILGE_YOLAC_DOKUMAN_REHBERI.md"),
    hazir_dosyalar = hazir_dosyalar,
    orijinal_prompt = prompt,
    reader_template_path = reader_template_path
  )

  sonuc$prepared_files <- hazir_dosyalar
  sonuc$unsupported_files <- unique(unsupported_files)
  sonuc$text_sidecars_ready <- length(hazir_dosyalar) > 0
  sonuc$manifest_path <- manifest_path
  sonuc$reader_template_path <- reader_template_path
  sonuc$support_dir <- destek_dizini
  sonuc$prompt <- build_claude_code_document_prompt(
    orijinal_prompt = prompt,
    manifest_path = manifest_path,
    reader_template_path = reader_template_path,
    unsupported_files = sonuc$unsupported_files
  )

  sonuc
}