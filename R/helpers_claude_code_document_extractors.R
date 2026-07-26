# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_document_extractors.R
# Açıklama: Bilge Yolaç doküman işleme hattı için ikili doküman algılama,
#           destek dizini hazırlama ve PDF/XLS/XLSX/DOCX metin çıkarımı
#           yardımcıları. Bu dosya Shiny observer, Claude CLI süreç yönetimi
#           veya streaming davranışı başlatmaz.
# ==============================================================================

get_claude_code_binary_doc_extensions <- function() {
  varsayilan_extler <- c("pdf", "xlsx", "xls", "docx", "doc")

  exts <- tryCatch(
    get_claude_code_model_capabilities()$binary_doc_extensions,
    error = function(e) varsayilan_extler
  )

  exts <- unique(c(
    tolower(as.character(exts %||% character(0))),
    varsayilan_extler
  ))

  exts <- exts[nzchar(exts)]
  unique(exts)
}

get_claude_code_text_extractable_extensions <- function() {
  c("pdf", "xlsx", "xls", "docx")
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

list_claude_code_binary_documents <- function(workdir,
                                              extensions = NULL,
                                              max_files = 200L) {
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

  max_files <- suppressWarnings(as.integer(max_files[1]))
  if (!is.na(max_files) && max_files > 0L && length(ogeler) > max_files) {
    ogeler <- ogeler[seq_len(max_files)]
  }

  uzantilar <- tolower(tools::file_ext(ogeler))

  unique(ogeler[nzchar(uzantilar) & uzantilar %in% tolower(extensions)])
}

# Eşzamanlı çalıştırmaların birbirinin çıkarımlarını silmemesi için doküman
# destek klasörü çalışma (request) başına izole edilir. Ortak kullanıcı
# klasörü ASLA her istekte silinmez; eskiyen klasörler yaşa göre temizlenir.
get_claude_code_document_support_dir <- function(user_id = NULL,
                                                 request_id = NULL,
                                                 base_dir = NULL) {
  kok <- as.character(base_dir %||% "")[1]

  if (!nzchar(kok)) {
    kok <- file.path(
      tempdir(),
      "claude_code_runtime",
      paste0("user_", as.character(user_id %||% "default")),
      "document_support"
    )
  }

  token <- as.character(request_id %||% "")[1]
  if (is.na(token) || !nzchar(token)) {
    token <- paste0(
      format(Sys.time(), "%Y%m%d%H%M%OS3"),
      "_",
      sprintf("%04d", sample.int(10000L, 1L) - 1L)
    )
  }

  token <- sanitize_claude_doc_cache_name(token)

  hedef <- file.path(kok, token)

  if (!dir.exists(hedef)) {
    dir.create(hedef, recursive = TRUE, showWarnings = FALSE)
  }

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

extract_docx_text_for_claude <- function(dosya_yolu,
                                         max_paragraf = 500L,
                                         max_karakter = 120000L) {
  gecici_dizin <- file.path(
    tempdir(),
    paste0(
      "claude_docx_",
      format(Sys.time(), "%Y%m%d%H%M%S"),
      "_",
      sprintf("%06d", sample.int(999999L, 1))
    )
  )

  dir.create(gecici_dizin, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(gecici_dizin, recursive = TRUE, force = TRUE), add = TRUE)

  tryCatch(
    utils::unzip(dosya_yolu, files = "word/document.xml", exdir = gecici_dizin),
    error = function(e) {
      stop(paste("DOCX açılamadı:", conditionMessage(e)))
    }
  )

  xml_yolu <- file.path(gecici_dizin, "word", "document.xml")

  if (!file.exists(xml_yolu)) {
    stop("DOCX içindeki word/document.xml bulunamadı.")
  }

  doc <- xml2::read_xml(xml_yolu)
  ns <- xml2::xml_ns(doc)

  paragraflar <- xml2::xml_find_all(doc, ".//w:p", ns = ns)

  metinler <- vapply(
    paragraflar,
    function(paragraf) {
      dugumler <- xml2::xml_find_all(paragraf, ".//w:t", ns = ns)

      if (!length(dugumler)) {
        return("")
      }

      paste(xml2::xml_text(dugumler), collapse = "")
    },
    character(1),
    USE.NAMES = FALSE
  )

  metinler <- trimws(enc2utf8(metinler))
  metinler <- metinler[nzchar(metinler)]

  if (!length(metinler)) {
    return("")
  }

  if (length(metinler) > max_paragraf) {
    metinler <- metinler[seq_len(max_paragraf)]
  }

  truncate_claude_doc_text(
    paste(c("=== DOCX METNI ===", metinler), collapse = "\n\n"),
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

  if (identical(uzanti, "docx")) {
    return(extract_docx_text_for_claude(dosya_yolu))
  }

  if (identical(uzanti, "doc")) {
    stop("Eski .doc biçimi çevrimdışı yerel çıkarımda henüz desteklenmiyor. Lütfen .docx biçimine dönüştürün.")
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