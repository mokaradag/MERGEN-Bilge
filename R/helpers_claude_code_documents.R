# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_documents.R
# Açıklama: Bilge Yolaç için PDF/XLS/XLSX dokümanlarını çevrimdışı olarak
#           metne dönüştürür, rehber dosyası üretir ve çalışma prompt'una
#           güvenli doküman kullanım yönergeleri ekler.
# ==============================================================================

# Extractor helpers are kept in a separate file so this document-context helper
# remains focused on manifest/prompt/summary orchestration.
if (!exists("extract_supported_document_text_for_claude", mode = "function", inherits = TRUE) ||
    !exists("get_office_document_reader_template_path", mode = "function", inherits = TRUE)) {

  # Çalışma dizininden bağımsız aday yolları dene. Üretimde global.R bu dosyayı
  # extractor'dan SONRA yüklediği için bu dal normalde hiç çalışmaz; ancak izole
  # test/debug source bağlamında getwd() repo kökü olmayabilir. Bu yüzden repo
  # kökü, tests/testthat ve MERGEN_REPO_ROOT adayları sırayla denenir.
  claude_doc_extractors_candidates <- c(
    file.path("R", "helpers_claude_code_document_extractors.R"),
    file.path("..", "..", "R", "helpers_claude_code_document_extractors.R"),
    if (nzchar(Sys.getenv("MERGEN_REPO_ROOT"))) {
      file.path(Sys.getenv("MERGEN_REPO_ROOT"), "R", "helpers_claude_code_document_extractors.R")
    } else {
      NULL
    }
  )

  claude_doc_extractors_path <- NULL
  for (claude_doc_cand in claude_doc_extractors_candidates) {
    if (!is.null(claude_doc_cand) && nzchar(claude_doc_cand) &&
        isTRUE(tryCatch(file.exists(claude_doc_cand), error = function(e) FALSE))) {
      claude_doc_extractors_path <- claude_doc_cand
      break
    }
  }

  if (is.null(claude_doc_extractors_path)) {
    stop(
      "R/helpers_claude_code_document_extractors.R bulunamadı; helpers_claude_code_documents.R yüklenemiyor.",
      call. = FALSE
    )
  }

  source(claude_doc_extractors_path, encoding = "UTF-8", local = globalenv())
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
                                                 user_id = NULL,
                                                 request_id = NULL,
                                                 explicit_files = character(0),
                                                 support_base_dir = NULL,
                                                 limits = NULL) {
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
    workdir_has_binary_documents(runtime_workdir, binary_exts, limits = limits)
  )

  # Kaynak dizin sadece yedek amaçlı kontrol edilir
  source_dokuman_var <- isTRUE(
    workdir_has_binary_documents(source_workdir, binary_exts, limits = limits)
  )

  # Doküman özet/okuma yolu (yerel metne çıkarma + non-streaming özet) yalnızca
  # kullanıcı AÇIKÇA mevcut bir dokümanın okunmasını/özetlenmesini istediğinde
  # devreye girer. "Bu dosyada ne var?" gibi içerik soruları artık doğrudan
  # canlı akış üzerinden Claude Code CLI'ya iletilir.
  # Üretim niyeti (örn. "Word dökümanı oluştur") açıkça okumadan ayrılır.
  okuma_niyeti_belirgin <- tryCatch(
    isTRUE(prompt_requests_existing_document_reading(prompt)),
    error = function(e) FALSE
  )

  olusturma_niyeti <- tryCatch(
    isTRUE(prompt_requests_binary_document_creation(prompt)),
    error = function(e) FALSE
  )

  dokuman_gorevi <- isTRUE(okuma_niyeti_belirgin) &&
    !isTRUE(olusturma_niyeti) &&
    isTRUE(runtime_dokuman_var || source_dokuman_var)

  if (!isTRUE(dokuman_gorevi)) {
    return(sonuc)
  }

  sonuc$document_task_detected <- TRUE

  # Dokümanları mümkünse runtime_workdir içinden al
  dokuman_kaynak_dizini <- if (isTRUE(runtime_dokuman_var)) {
    runtime_workdir
  } else {
    source_workdir %||% runtime_workdir
  }

  dokuman_adaylari <- list_claude_code_binary_documents(
    dokuman_kaynak_dizini, extensions = binary_exts, limits = limits
  )

  if (!length(dokuman_adaylari)) {
    return(sonuc)
  }

  dokuman_secimi <- cc_select_documents_for_request(
    prompt = prompt,
    documents = dokuman_adaylari,
    explicit_files = explicit_files,
    limits = limits
  )

  dokumanlar <- dokuman_secimi$files

  if (!length(dokumanlar)) {
    return(sonuc)
  }

  sonuc$has_binary_docs <- TRUE
  sonuc$document_selection <- dokuman_secimi

  destek_dizini <- get_claude_code_document_support_dir(
    user_id = user_id,
    request_id = request_id,
    base_dir = support_base_dir
  )
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

write_claude_code_utf8_bom_text_file <- function(text, file_path) {
  text <- enc2utf8(paste(as.character(text %||% ""), collapse = "\n"))
  file_path <- as.character(file_path %||% "")[1]

  if (!nzchar(file_path)) {
    return(FALSE)
  }

  con <- file(file_path, open = "wb")
  on.exit(close(con), add = TRUE)

  # UTF-8 BOM: makes Windows/Notepad/Office reliably detect Turkish text.
  writeBin(as.raw(c(0xEF, 0xBB, 0xBF)), con)
  writeBin(charToRaw(text), con)

  TRUE
}
