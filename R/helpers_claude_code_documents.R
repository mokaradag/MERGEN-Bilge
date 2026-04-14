# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_documents.R
# Açıklama: Bilge Yolaç için PDF/XLS/XLSX dokümanlarını çevrimdışı olarak
#           metne dönüştürür, rehber dosyası üretir ve çalışma prompt'una
#           güvenli doküman kullanım yönergeleri ekler.
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
    "BU GÖREV İÇİN GLOB, READ, GREP VEYA BAŞKA BİR ARAÇ KULLANMA.",
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
                                              unsupported_files = character(0),
                                              inline_payload = "") {
  satirlar <- c(
    "SİSTEM ÇALIŞMA NOTU:",
    "Bu görev ikili ofis dokümanları içeriyor.",
    "PDF/XLS/XLSX dosyalarını doğrudan ikili içerik olarak Read etme.",
    "Yalnızca düz metin çıkarımlarıyla çalış.",
    "Bu görev için Glob, Read, Grep veya başka bir araç çağırma.",
    "Gerekli içerik rehber dosyasında ve aşağıdaki hazır metin bloklarında zaten var."
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
    "Yanıtını yalnız hazır metin çıkarımlarına dayanarak ver."
  )

  if (nzchar(inline_payload)) {
    satirlar <- c(
      satirlar,
      "",
      "HAZIR METIN CIKARIMLARI:",
      inline_payload
    )
  }

  satirlar <- c(
    satirlar,
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
    document_task_detected = FALSE,
    has_binary_docs = FALSE,
    text_sidecars_ready = FALSE,
    prepared_files = list(),
    unsupported_files = character(0),
    extraction_errors = character(0),
    manifest_path = "",
    reader_template_path = "",
    support_dir = "",
    effective_workdir = runtime_workdir,
    inline_payload = ""
  )

  binary_exts <- get_claude_code_binary_doc_extensions()

  # Önce yerel aynalanmış çalışma dizinini kontrol et
  runtime_dokuman_var <- isTRUE(
    workdir_has_binary_documents(runtime_workdir, binary_exts)
  )

  # Kaynak dizin sadece yedek amaçlı kontrol edilir
  source_dokuman_var <- isTRUE(
    workdir_has_binary_documents(source_workdir, binary_exts)
  )

  dokuman_gorevi <- isTRUE(prompt_mentions_binary_document_type(prompt)) ||
    (
      isTRUE(prompt_requests_document_operation(prompt)) &&
        isTRUE(runtime_dokuman_var || source_dokuman_var)
    )

  if (!isTRUE(dokuman_gorevi)) {
    return(sonuc)
  }

  # Kullanıcı mevcut ikili dokümanı OKUMAK değil YENİ bir ikili doküman
  # ÜRETMEK istiyorsa doküman modunu (metne düşürme yolunu) devre dışı bırak.
  # Aksi halde Claude Code'a "binary üretimi yasaktır" yönergesi enjekte
  # ediliyor ve .docx/.xlsx üretimi engelleniyor.
  if (exists("prompt_requests_binary_document_creation", mode = "function")) {
    olusturma_niyeti <- tryCatch(
      isTRUE(prompt_requests_binary_document_creation(prompt)),
      error = function(e) FALSE
    )

    okuma_niyeti_belirgin <- tryCatch(
      isTRUE(prompt_requests_existing_document_reading(prompt)),
      error = function(e) FALSE
    )

    if (isTRUE(olusturma_niyeti) && !isTRUE(okuma_niyeti_belirgin)) {
      return(sonuc)
    }
  }

  sonuc$document_task_detected <- TRUE

  # Dokümanları mümkünse runtime_workdir içinden al
  dokuman_kaynak_dizini <- if (isTRUE(runtime_dokuman_var)) {
    runtime_workdir
  } else {
    source_workdir %||% runtime_workdir
  }

  dokumanlar <- list_claude_code_binary_documents(
    dokuman_kaynak_dizini,
    extensions = binary_exts
  )

  if (!length(dokumanlar)) {
    return(sonuc)
  }

  sonuc$has_binary_docs <- TRUE

  destek_dizini <- get_claude_code_document_support_dir(user_id = user_id)
  reader_template_path <- get_office_document_reader_template_path()

  hazir_dosyalar <- list()
  unsupported_files <- character(0)
  extraction_errors <- character(0)
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

    cikarma_sonucu <- tryCatch(
      list(
        text = extract_supported_document_text_for_claude(dosya_yolu),
        error = ""
      ),
      error = function(e) {
        list(
          text = "",
          error = conditionMessage(e)
        )
      }
    )

    metin <- enc2utf8(cikarma_sonucu$text %||% "")

    if (nzchar(cikarma_sonucu$error %||% "")) {
      extraction_errors <- c(
        extraction_errors,
        paste0(basename(dosya_yolu), ": ", cikarma_sonucu$error)
      )
    }

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

  sonuc$prepared_files <- hazir_dosyalar
  sonuc$unsupported_files <- unique(unsupported_files)
  sonuc$extraction_errors <- unique(extraction_errors)
  sonuc$reader_template_path <- reader_template_path
  sonuc$support_dir <- destek_dizini
  sonuc$effective_workdir <- destek_dizini

  if (!length(hazir_dosyalar)) {
    log_error(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Doküman görevi algılandı ancak metin çıkarımı hazırlanamadı.",
      paste(sonuc$extraction_errors %||% character(0), collapse = " | ")
    ))
    return(sonuc)
  }

  manifest_path <- write_claude_code_document_manifest(
    hedef_yol = file.path(destek_dizini, "BILGE_YOLAC_DOKUMAN_REHBERI.md"),
    hazir_dosyalar = hazir_dosyalar,
    orijinal_prompt = prompt,
    reader_template_path = reader_template_path
  )

  inline_payload <- build_claude_code_document_inline_payload(
    hazir_dosyalar = hazir_dosyalar
  )

  sonuc$text_sidecars_ready <- TRUE
  sonuc$manifest_path <- manifest_path
  sonuc$inline_payload <- inline_payload
  sonuc$prompt <- build_claude_code_document_prompt(
    orijinal_prompt = prompt,
    manifest_path = manifest_path,
    reader_template_path = reader_template_path,
    unsupported_files = sonuc$unsupported_files,
    inline_payload = inline_payload
  )

  sonuc
}

#' Kullanıcı prompt'undan doküman özetleme detay seviyesini çıkarır
#'
#' @param prompt Kullanıcı prompt'u
#' @return "kisa", "orta" veya "detayli"
resolve_claude_code_document_detail_level <- function(prompt) {
  metin <- tolower(enc2utf8(paste(as.character(prompt %||% ""), collapse = " ")))

  if (!nzchar(metin)) {
    return("orta")
  }

  detay_deseni <- paste(
    c(
      "detay",
      "ayrıntı",
      "ayrinti",
      "çok detay",
      "cok detay",
      "derinlemesine",
      "kapsamlı",
      "kapsamli",
      "ayrıntılı",
      "ayrintili",
      "tam",
      "tamamını",
      "tamamini",
      "satır satır",
      "madde madde",
      "tek tek",
      "geniş",
      "genis"
    ),
    collapse = "|"
  )

  kisa_deseni <- paste(
    c(
      "kısa",
      "kisa",
      "özet geç",
      "ozet gec",
      "kısaca",
      "kisaca",
      "kısa özet",
      "kisa ozet"
    ),
    collapse = "|"
  )

  if (grepl(detay_deseni, metin, perl = TRUE)) {
    return("detayli")
  }

  if (grepl(kisa_deseni, metin, perl = TRUE)) {
    return("kisa")
  }

  "orta"
}

write_claude_code_document_summary_file <- function(summary_text,
                                                    output_dir,
                                                    file_name = "dosya_aciklamalari.txt") {
  output_dir <- as.character(output_dir %||% "")[1]
  summary_text <- enc2utf8(paste(as.character(summary_text %||% ""), collapse = "\n"))

  if (!nzchar(output_dir) || !dir.exists(output_dir) || !nzchar(summary_text)) {
    return("")
  }

  hedef_yol <- file.path(output_dir, file_name)

  writeLines(summary_text, hedef_yol, useBytes = TRUE)

  normalizePath(hedef_yol, winslash = "/", mustWork = FALSE)
}

#' Bilge Yolaç doküman özetleme mesajlarını oluşturur
#'
#' @param document_context prepare_claude_code_document_context çıktısı
#' @return LLM mesaj listesi
build_claude_code_document_summary_messages <- function(document_context) {
  kullanici_icerigi <- enc2utf8(
    paste(as.character(document_context$prompt %||% ""), collapse = "\n")
  )

  detay_seviyesi <- resolve_claude_code_document_detail_level(
    document_context$prompt %||% ""
  )

  detay_yonergesi <- switch(
    detay_seviyesi,
    "kisa" = c(
      "Kısa ve yoğun bir özet ver.",
      "Gereksiz ayrıntılara girme.",
      "Dosya bazlı özetleri kısa tut."
    ),
    "detayli" = c(
      "Kullanıcı ayrıntılı anlatım istiyor.",
      "Özeti kısa tutma; kapsamlı ve açıklayıcı yaz.",
      "Her önemli bölüm veya konu başlığını tek tek açıkla.",
      "Dosya bazlı özetleri kısa değil, ayrıntılı ver.",
      "Önemli kavramları, kararları, bulguları ve ilişkileri aç.",
      "Metindeki sayısal/verisel noktaları mümkün olduğunca koru.",
      "Gerekirse başlıklar ve alt başlıklarla yapılandır."
    ),
    c(
      "Dengeli ayrıntı düzeyi kullan.",
      "Ne çok kısa ne gereksiz uzun yaz."
    )
  )

  sistem_icerigi <- paste(
    c(
      "Sen MERGEN Bilge içindeki Bilge Yolaç doküman özetleme yardımcısısın.",
      "Sana yalnızca yerel olarak çıkarılmış düz metin doküman içerikleri verilir.",
      "Yanıtını yalnızca bu metinlere dayandır.",
      "Binary dosya, tool_result, document bloğu veya harici araç kullanımı üretme.",
      "Metinlerde olmayan bir bilgiyi varmış gibi söyleme.",
      "Yanıtını Türkçe ver.",
	  "Özet metni uygulama tarafından ayrıca .txt dosyasına kaydedilecektir.",
	  "Kullanıcıdan metni kopyalayıp dosyaya yapıştırmasını isteme.",
	  "'şu isimle kaydedin' gibi manuel kayıt yönergeleri verme.",
      detay_yonergesi,
      "Birden çok dosya varsa şu sırayı kullan:",
      "1. Genel özet",
      "2. Dosya bazlı özetler",
      "3. Önemli bulgular",
      "4. Dikkat çeken sayısal/verisel noktalar",
      "5. Gerekirse kritik ayrıntılar ve yorumlanması gereken kısımlar"
    ),
    collapse = "\n"
  )

  list(
    list(role = "system", content = sistem_icerigi),
    list(role = "user", content = kullanici_icerigi)
  )
}

#' Bilge Yolaç dokümanlarını doğrudan yerel LLM ile özetler
#'
#' @param document_context prepare_claude_code_document_context çıktısı
#' @param model_id Kullanılacak model kimliği
#' @param api_key Kullanıcı API anahtarı (varsa)
#' @param request_timeout_sec Zaman aşımı süresi
#' @return run_claude_code benzeri sonuç listesi
summarize_claude_code_documents_with_local_llm <- function(document_context,
                                                           model_id,
                                                           api_key = "",
                                                           request_timeout_sec = 600L,
                                                           output_dir = "",
                                                           user_id = 0L,
                                                           session_token = "") {
  baslangic <- Sys.time()

  if (!is.list(document_context) || !isTRUE(document_context$text_sidecars_ready)) {
    return(list(
      success = FALSE,
      output = "",
      error = "Hazır doküman metin çıkarımı bulunamadı.",
      duration = 0,
      tool_uses = list(),
      session_id = NULL
    ))
  }

  mesajlar <- build_claude_code_document_summary_messages(document_context)

  detay_seviyesi <- resolve_claude_code_document_detail_level(
    document_context$prompt %||% ""
  )

  max_output_tokens_val <- switch(
    detay_seviyesi,
    "kisa" = 4000L,
    "detayli" = 12000L,
    7000L
  )

  ayarlar <- list(
    model_selection = as.character(model_id %||% "")[1],
    api_key = as.character(api_key %||% "")[1],
    request_timeout_sec = as.numeric(request_timeout_sec %||% 600),
    max_output_tokens = max_output_tokens_val
  )

  tryCatch({
    sonuc <- call_local_llm(
      chat_history = mesajlar,
      current_settings = ayarlar
    )

    cikti <- as.character(sonuc$content %||% "")[1]
    sure <- round(
      as.numeric(sonuc$duration %||% difftime(Sys.time(), baslangic, units = "secs")),
      1
    )

    if (!nzchar(cikti)) {
      stop("Yerel LLM doküman özeti boş döndü.")
    }

    ozet_dosya_yolu <- write_claude_code_document_summary_file(
      summary_text = cikti,
      output_dir = output_dir,
      file_name = "dosya_aciklamalari.txt"
    )

    arac_kullanimlari <- list()
    generated_downloads <- list()
    generated_downloads_html <- ""

    if (nzchar(ozet_dosya_yolu)) {
      arac_kullanimlari <- list(
        list(
          name = "file_write",
          input = list(
            path = ozet_dosya_yolu,
            content = cikti
          ),
          result = "Doküman özeti dosyası oluşturuldu."
        )
      )

      if (exists("collect_claude_code_generated_downloads", mode = "function") &&
          exists("format_claude_code_generated_downloads_html", mode = "function")) {
        generated_downloads <- tryCatch(
          collect_claude_code_generated_downloads(
            tool_uses = arac_kullanimlari,
            runtime_workdir = output_dir,
            source_workdir = output_dir,
            user_id = user_id,
            session_token = session_token
          ),
          error = function(e) list()
        )

        generated_downloads_html <- tryCatch(
          format_claude_code_generated_downloads_html(generated_downloads),
          error = function(e) ""
        )
      }
    }

    list(
      success = TRUE,
      output = cikti,
      error = "",
      duration = sure,
      tool_uses = arac_kullanimlari,
      session_id = NULL,
      generated_summary_path = ozet_dosya_yolu,
      generated_downloads = generated_downloads,
      generated_downloads_html = generated_downloads_html
    )
  }, error = function(e) {
    sure <- round(as.numeric(difftime(Sys.time(), baslangic, units = "secs")), 1)

    list(
      success = FALSE,
      output = "",
      error = paste0("Doküman özeti oluşturulamadı: ", conditionMessage(e)),
      duration = sure,
      tool_uses = list(),
      session_id = NULL
    )
  })
}