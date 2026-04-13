# ==============================================================================
# Dosya Yolu: bilge_yolac_plugins/office/templates/document_readers.R
# Açıklama: PDF, Excel ve DOCX dosyalarını metne dönüştüren çevrimdışı
#           yardımcılar. Bilge Yolaç içinde mevcut ofis dokümanlarını okumak
#           ve özetleme öncesi metin çıkarmak için kullanılır.
# ==============================================================================

office_metin_kisalt <- function(metin, max_karakter = 120000L) {
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

office_pdf_metin_cikar <- function(dosya_yolu,
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

  office_metin_kisalt(
    paste(parcalar, collapse = "\n"),
    max_karakter = max_karakter
  )
}

office_excel_metin_cikar <- function(dosya_yolu,
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

  office_metin_kisalt(
    paste(parcalar, collapse = "\n"),
    max_karakter = max_karakter
  )
}

office_docx_metin_cikar <- function(dosya_yolu,
                                    max_paragraf = 500L,
                                    max_karakter = 120000L) {
  gecici_dizin <- file.path(
    tempdir(),
    paste0(
      "office_docx_",
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

  office_metin_kisalt(
    paste(c("=== DOCX METNI ===", metinler), collapse = "\n\n"),
    max_karakter = max_karakter
  )
}

office_dokuman_metin_cikar <- function(dosya_yolu, ...) {
  uzanti <- tolower(tools::file_ext(dosya_yolu))

  if (identical(uzanti, "pdf")) {
    return(office_pdf_metin_cikar(dosya_yolu, ...))
  }

  if (uzanti %in% c("xlsx", "xls")) {
    return(office_excel_metin_cikar(dosya_yolu, ...))
  }

  if (identical(uzanti, "docx")) {
    return(office_docx_metin_cikar(dosya_yolu, ...))
  }

  if (identical(uzanti, "doc")) {
    stop("Eski .doc biçimi bu çevrimdışı şablonda desteklenmiyor. Lütfen .docx biçimine dönüştürün.")
  }

  stop(paste("Desteklenmeyen doküman uzantısı:", uzanti))
}

office_dizin_dokumanlarini_listele <- function(dizin,
                                               uzantilar = c("pdf", "xlsx", "xls", "docx")) {
  if (!dir.exists(dizin)) {
    return(character(0))
  }

  dosyalar <- list.files(
    dizin,
    full.names = TRUE,
    recursive = FALSE,
    all.files = FALSE,
    include.dirs = FALSE
  )

  if (!length(dosyalar)) {
    return(character(0))
  }

  extler <- tolower(tools::file_ext(dosyalar))

  dosyalar[nzchar(extler) & extler %in% tolower(uzantilar)]
}