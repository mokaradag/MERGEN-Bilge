# ==============================================================================
# R/utils_common.R
# Dosya Yolu: R/utils_common.R
# Açıklama: Uygulama genelinde kullanılan temel yardımcı fonksiyonlar.
# NULL birleştirme operatörü, güvenli kontroller ve metin temizleyicileri içerir.
# global.R tarafından config_packages.R'den hemen sonra source() ile çağrılır.
# ==============================================================================

# --- NULL BİRLEŞTİRME OPERATÖRÜ ---
# Eğer sol taraf NULL ise sağ tarafı döndürür
`%||%` <- function(a, b) {
  if (is.null(a)) b else a
}

# --- GÜVENLİ NZCHAR KONTROLÜ ---
# Tek satırda NULL, NA ve boş karakter kontrolü yapar
safe_nzchar <- function(x) {
  is.character(x) && length(x) > 0 && !is.na(x[1]) && nzchar(x[1])
}

# --- ZAMAN DAMGASI BİÇİMLENDİRİCİ ---
# Türkiye formatında (GG.AA.YYYY - SS:DD) zaman damgası üretir
format_timestamp <- function() {
  format(Sys.time(), "%d.%m.%Y - %H:%M")
}

# --- YAPISAL KAYNAKLARDAN KAYNAKÇA HTML OLUŞTURUCU ---
# API yanıtındaki yapısal sources listesini tıklanabilir Kaynakça metnine dönüştürür.
# Hem call_llm_worker hem call_local_llm tarafından kullanılır.
build_kaynakca_from_sources <- function(sources_list) {
  if (is.null(sources_list) || length(sources_list) == 0) return("")

  cat("\n========== SOURCES PROCESSING ==========\n")

  extracted_sources <- list()
  seen_filenames <- character(0)

  for (i in seq_along(sources_list)) {
    src <- sources_list[[i]]

    if (is.list(src) && !is.null(src[["metadata"]])) {
      metadata_array <- src[["metadata"]]
      for (j in seq_along(metadata_array)) {
        doc <- metadata_array[[j]]
        filename <- doc[["name"]] %||% doc[["source"]]

        if (!is.null(filename) && is.character(filename)) {
          filename <- as.character(filename)[1]
          if (filename %in% seen_filenames) {
            cat("[DOCUMENT ", j, "] DUPLICATE - skipping: <", filename, ">\n", sep = "")
            next
          }

          cat("[DOCUMENT ", j, "] Extracted: <", filename, ">\n", sep = "")
          seen_filenames <- c(seen_filenames, filename)

          # Süreç numarasını ve dosya adını ayır
          process_match <- regexpr("^[a-z]+_[0-9]+_[0-9]+_", filename, ignore.case = TRUE)
          process_num <- ""
          actual_filename <- filename

          if (process_match > 0) {
            match_length <- attr(process_match, "match.length")
            process_part <- substr(filename, 1, match_length - 1)
            actual_filename <- substr(filename, match_length + 1, nchar(filename))
            process_num <- toupper(process_part)
            process_num <- gsub("_", " ", process_num)
            process_num <- gsub("-", " ", process_num)
          }

          # Dosya adını biçimlendir
          file_ext <- tools::file_ext(actual_filename)
          file_base <- tools::file_path_sans_ext(actual_filename)
          file_base <- gsub("_", " ", file_base)
          file_base <- gsub("-", " ", file_base)
          file_base <- tools::toTitleCase(file_base)
          formatted_filename <- paste0(file_base, ".", file_ext)

          extracted_sources[[length(extracted_sources) + 1]] <- list(
            process = process_num,
            filename = formatted_filename,
            original_filename = filename
          )
        }
      }
    }
  }

  cat("[SUMMARY] Total unique sources:", length(extracted_sources), "\n")
  if (length(extracted_sources) == 0) {
    cat("========================================\n\n")
    return("")
  }

  # Tıklanabilir Kaynakça HTML'i oluştur
  sources_text <- "\n\nKaynakça:\n"

  for (i in seq_along(extracted_sources)) {
    src_info <- extracted_sources[[i]]
    source_id <- paste0("source_", i, "_", gsub("[^a-z0-9]", "", tolower(src_info$filename)))
    original_filename <- src_info$original_filename
    file_ext <- tolower(tools::file_ext(original_filename))

    # Dosya türüne göre ikon seç
    icon_html <- if (file_ext %in% c("doc", "docx")) {
      "<i class='fa-regular fa-file-word' style='margin-right:6px;color:#2b579a'></i>"
    } else if (identical(file_ext, "pdf")) {
      "<i class='fa-regular fa-file-pdf' style='margin-right:6px;color:#c00'></i>"
    } else if (file_ext %in% c("xls", "xlsx")) {
      "<i class='fa-regular fa-file-excel' style='margin-right:6px;color:#1d6f42'></i>"
    } else {
      "<i class='fa-regular fa-file' style='margin-right:6px;'></i>"
    }

    label_prefix <- if (nchar(src_info$process) > 0) paste0(src_info$process, ": ") else ""
    parts_raw <- strsplit(original_filename, "&&", fixed = TRUE)[[1]]

    if (length(parts_raw) > 1) {
      parts <- trimws(parts_raw)
      left_parts <- if (length(parts) > 1) parts[seq_len(length(parts) - 1)] else character(0)
      right_part <- parts[length(parts)]

      left_html <- if (length(left_parts)) {
        paste(
          vapply(left_parts, function(p) {
            paste0("<span class='source-chunk'>", htmltools::htmlEscape(p), "</span>")
          }, character(1)),
          collapse = " - "
        )
      } else ""

      clickable_html <- paste0(
        "<span class='source-link' data-source-id='", source_id,
        "' data-filename='", htmltools::htmlEscape(original_filename, attribute = TRUE),
        "' style='color:#007bff; cursor:pointer; text-decoration:underline;'>",
        htmltools::htmlEscape(trimws(right_part)),
        "</span>"
      )

      line <- paste0(
        i, ") ", label_prefix, icon_html,
        if (nzchar(left_html)) paste0(left_html, " - ") else "",
        clickable_html, "\n"
      )
    } else {
      clickable_html <- paste0(
        "<span class='source-link' data-source-id='", source_id,
        "' data-filename='", htmltools::htmlEscape(original_filename, attribute = TRUE),
        "' style='color:#007bff; cursor:pointer; text-decoration:underline;'>",
        htmltools::htmlEscape(src_info$filename),
        "</span>"
      )
      line <- paste0(i, ") ", label_prefix, icon_html, clickable_html, "\n")
    }

    sources_text <- paste0(sources_text, line)
  }

  cat("[SUCCESS] Kaynakça built with", length(extracted_sources), "unique sources\n")
  cat("========================================\n\n")
  sources_text
}

# --- PLANLAYICI / AJAN META-METİN TEMİZLEYİCİ ---
# LLM yanıtlarından araç çağrısı kalıntılarını ve planlama cümlelerini temizler
strip_planner_text <- function(x) {
  # NULL veya character(0) güvenli kontrolü
  if (is.null(x)) return(x)
  if (!is.character(x) || length(x) == 0) return("")
  s <- x[1]
  if (!nzchar(s)) return(s)

  # JSON araç çağrısı kalıntılarını kaldır
  s <- gsub("\\{\\s*\"(tool|name)\"\\s*:\\s*\"[^\"]+\"[^{}]*\"arguments\"\\s*:\\s*\\{[^{}]*\\}\\s*\\}", "", s, perl = TRUE)
  s <- gsub("\\{\\s*\"action\"\\s*:\\s*\"[^\"]+\"[^{}]*\"parameters\"\\s*:\\s*\\{[^{}]*\\}\\s*\\}", "", s, perl = TRUE)
  s <- gsub("\\s*<tool_call>.*?</tool_call>\\s*", "", s, perl = TRUE)

  # Qwen/RAG modellerin metin olarak yazdığı <function=...> biçimli araç çağrılarını kaldır
  s <- gsub("<function=\\w+>.*?</function>", "", s, perl = TRUE)
  # Tamamlanmamış (kapanış etiketi eksik) <function=...> bloklarını da kaldır
  s <- gsub("<function=\\w+>(?:(?!</function>).)*$", "", s, perl = TRUE)
  # Kalan kapanmamış </too, </tool vb. parçaları kaldır
  s <- gsub("</?(too|tool|function|parameter)\\w*>?\\s*$", "", s, perl = TRUE)

  # Planlayıcı meta-cümlelerini kaldır (İngilizce kalıplar)
  s <- gsub("(?im)^(we need to .*|let'?s try.*|probably .*|i'?ll try.*|we will call.*|we will invoke.*|now produce the tool call\\.?|we need to produce a tool call\\.?)\\s*$", "", s, perl = TRUE)

  # Çoklu boş satırları tek satıra düşür
  s <- gsub("\n{3,}", "\n\n", s, perl = TRUE)
  trimws(s)
}

# ==============================================================================
# YEREL BELGE DEPOSUNDAN KAYNAK EŞLEŞTİRME
# API kaynak (sources/citations) döndürmediğinde, kullanıcı sorusu ve AI yanıtı
# üzerinden anahtar kelime çıkararak local_model_paths altındaki belgeleri tarar
# ve eşleşen dosyalardan tıklanabilir Kaynakça HTML'i üretir.
# ==============================================================================

# --- TÜRKÇE KARAKTER NORMALİZASYONU ---
# Dosya adlarındaki ASCII Türkçe ile sorgu metnindeki Unicode Türkçe arasında
# eşleşme sağlamak için her iki tarafı da ASCII'ye dönüştürür.
.normalize_turkish <- function(text) {
  text <- tolower(text)
  text <- gsub("\u00e7", "c", text)   # ç -> c
  text <- gsub("\u011f", "g", text)   # ğ -> g
  text <- gsub("\u0131", "i", text)   # ı -> i
  text <- gsub("\u00f6", "o", text)   # ö -> o
  text <- gsub("\u015f", "s", text)   # ş -> s
  text <- gsub("\u00fc", "u", text)   # ü -> u
  text <- gsub("\u00e2", "a", text)   # â -> a
  text <- gsub("\u00ee", "i", text)   # î -> i
  text <- gsub("\u00fb", "u", text)   # û -> u
  text
}

# --- SOHBET GEÇMİŞİNDEN SON KULLANICI SORUSUNU ÇIKAR ---
.extract_last_user_query <- function(chat_history) {
  if (!is.list(chat_history) || length(chat_history) == 0) return("")
  for (i in rev(seq_along(chat_history))) {
    msg <- chat_history[[i]]
    role <- msg$type %||% msg$role %||% ""
    if (identical(role, "user") && is.character(msg$content) && length(msg$content) > 0 && nzchar(msg$content[1])) {
      return(msg$content[1])
    }
  }
  ""
}

# --- ANAHTAR KELİME ÇIKARICI ---
# Kullanıcı sorusu ve (opsiyonel) AI yanıtından arama anahtar kelimeleri üretir.
# Türkçe durak kelimelerini filtreler ve ASCII normalleştirme uygular.
extract_search_keywords <- function(user_query, ai_text = NULL) {
  # Sorgu metni zorunlu
  if (is.null(user_query) || !nzchar(user_query)) return(character(0))

  # AI yanıtından sadece ilk 500 karakteri kullan (gürültüyü azalt)
  ai_snippet <- if (!is.null(ai_text) && is.character(ai_text) && nzchar(ai_text[1])) {
    substr(ai_text[1], 1, 500)
  } else {
    ""
  }

  combined <- paste(user_query, ai_snippet)
  combined <- .normalize_turkish(combined)

  # Harf ve rakam dışı karakterlerden böl
  tokens <- unlist(strsplit(combined, "[^a-z0-9]+"))
  tokens <- tokens[nzchar(tokens)]

  # Türkçe ve İngilizce durak kelimeleri
  stop_words <- c(
    "ve", "ile", "bir", "bu", "su", "ne", "nedir", "nelerdir",
    "nasil", "hangi", "gibi", "kadar", "icin", "olan", "olarak",
    "da", "de", "mi", "mu", "den", "dan", "ten", "tan",
    "dir", "ler", "lar", "daki", "deki", "nin", "nun",
    "the", "is", "are", "what", "how", "which", "and", "or",
    "var", "yok", "degil", "hem", "ise", "veya", "ya", "ki",
    "hakkinda", "aciklayiniz", "acikla", "anlat", "anlatir",
    "merhaba", "selam", "bana", "benim", "bizim", "onun",
    "lutfen", "tesekkur", "ederim", "sonra", "once"
  )

  tokens <- tokens[!tokens %in% stop_words]
  tokens <- tokens[nchar(tokens) >= 3]  # 3 karakterden kısa kelimeleri filtrele
  unique(tokens)
}

# --- YEREL DOSYA LİSTESİNDEN TIKLANABIIR KAYNAKÇA HTML'İ ---
# Dosya indeksinden seçilen dosyalar için tıklanabilir Kaynakça oluşturur.
# Mevcut source-link CSS sınıfını kullanarak JS tıklama işleyicisiyle uyumlu çalışır.
build_kaynakca_from_local_files <- function(matched_files, index_map) {
  if (length(matched_files) == 0) return("")

  sources_text <- "\n\nKaynakça:\n"

  for (i in seq_along(matched_files)) {
    bn <- matched_files[i]
    full_paths <- index_map[[bn]]
    original_filename <- if (length(full_paths) > 0) basename(full_paths[1]) else bn

    # Süreç ön-ekini ayır (ör. proc_001_002_)
    process_match <- regexpr("^[a-z]+_[0-9]+_[0-9]+_", original_filename, ignore.case = TRUE)
    process_num <- ""
    actual_filename <- original_filename

    if (process_match > 0) {
      match_length <- attr(process_match, "match.length")
      process_part <- substr(original_filename, 1, match_length - 1)
      actual_filename <- substr(original_filename, match_length + 1, nchar(original_filename))
      process_num <- toupper(process_part)
      process_num <- gsub("_", " ", process_num)
      process_num <- gsub("-", " ", process_num)
    }

    # Dosya adını okunabilir biçime getir
    file_ext <- tolower(tools::file_ext(actual_filename))
    file_base <- tools::file_path_sans_ext(actual_filename)
    file_base <- gsub("_", " ", file_base)
    file_base <- gsub("-", " ", file_base)
    file_base <- tools::toTitleCase(file_base)
    formatted_filename <- paste0(file_base, ".", file_ext)

    # Dosya türüne göre ikon belirle
    icon_html <- if (file_ext %in% c("doc", "docx")) {
      "<i class='fa-regular fa-file-word' style='margin-right:6px;color:#2b579a'></i>"
    } else if (identical(file_ext, "pdf")) {
      "<i class='fa-regular fa-file-pdf' style='margin-right:6px;color:#c00'></i>"
    } else if (file_ext %in% c("xls", "xlsx")) {
      "<i class='fa-regular fa-file-excel' style='margin-right:6px;color:#1d6f42'></i>"
    } else {
      "<i class='fa-regular fa-file' style='margin-right:6px;'></i>"
    }

    source_id <- paste0("source_", i, "_", gsub("[^a-z0-9]", "", tolower(formatted_filename)))
    label_prefix <- if (nchar(process_num) > 0) paste0(process_num, ": ") else ""

    clickable_html <- paste0(
      "<span class='source-link' data-source-id='", source_id,
      "' data-filename='", htmltools::htmlEscape(original_filename, attribute = TRUE),
      "' style='color:#007bff; cursor:pointer; text-decoration:underline;'>",
      htmltools::htmlEscape(formatted_filename),
      "</span>"
    )

    line <- paste0(i, ") ", label_prefix, icon_html, clickable_html, "\n")
    sources_text <- paste0(sources_text, line)
  }

  sources_text
}

# --- ANA KAYNAK EŞLEŞTİRME FONKSİYONU ---
# API kaynak döndürmediğinde çağrılır. Kullanıcı sorusu + AI yanıtından
# anahtar kelimeler çıkararak local_model_paths altındaki belge deposunu tarar.
# En çok eşleşen dosyalardan tıklanabilir Kaynakça HTML'i döndürür.
match_local_documents_for_kaynakca <- function(chat_history, ai_content, model_id, max_results = 5) {
  # model_id'ye karşılık gelen belge yolunu bul
  doc_path <- tryCatch(
    api_config$local_model_paths[[as.character(model_id)[1]]],
    error = function(e) NULL
  )
  if (is.null(doc_path) || !nzchar(doc_path)) {
    cat("[KAYNAKÇA-LOCAL] Model için belge yolu bulunamadı:", model_id, "\n")
    return("")
  }

  cat("[KAYNAKÇA-LOCAL] Belge deposu:", doc_path, "\n")

  # Belge indeksini al (önbellek TTL ile yönetilir)
  idx <- tryCatch(.build_basename_index(doc_path), error = function(e) {
    cat("[KAYNAKÇA-LOCAL] İndeks oluşturma hatası:", e$message, "\n")
    list(map = list())
  })
  if (is.null(idx$map) || length(idx$map) == 0) {
    cat("[KAYNAKÇA-LOCAL] İndeks boş veya oluşturulamadı\n")
    return("")
  }

  cat("[KAYNAKÇA-LOCAL] İndekste", length(idx$map), "benzersiz dosya adı var\n")

  # Son kullanıcı sorusunu çıkar
  user_query <- .extract_last_user_query(chat_history)
  if (!nzchar(user_query)) {
    cat("[KAYNAKÇA-LOCAL] Kullanıcı sorusu bulunamadı\n")
    return("")
  }

  # Anahtar kelimeleri çıkar
  keywords <- extract_search_keywords(user_query, ai_content)
  if (length(keywords) == 0) {
    cat("[KAYNAKÇA-LOCAL] Anahtar kelime çıkarılamadı\n")
    return("")
  }
  cat("[KAYNAKÇA-LOCAL] Anahtar kelimeler:", paste(keywords, collapse = ", "), "\n")

  # Her dosya adını anahtar kelimelerle puanla
  all_basenames <- names(idx$map)
  scores <- vapply(all_basenames, function(bn) {
    # Dosya adını normalize et (alt çizgi, tire → boşluk, Türkçe → ASCII)
    normalized <- .normalize_turkish(bn)
    normalized <- gsub("[_\\-\\.]", " ", normalized)
    # Her anahtar kelimenin dosya adında geçip geçmediğini say
    sum(vapply(keywords, function(kw) {
      if (grepl(kw, normalized, fixed = TRUE)) 1L else 0L
    }, integer(1)))
  }, integer(1))

  # Sıfır puanlıları filtrele
  nonzero_mask <- scores > 0
  if (!any(nonzero_mask)) {
    cat("[KAYNAKÇA-LOCAL] Hiçbir dosya eşleşmedi\n")
    return("")
  }

  # Puana göre azalan sırada sırala ve ilk max_results kadarını al
  filtered_basenames <- all_basenames[nonzero_mask]
  filtered_scores <- scores[nonzero_mask]
  top_order <- order(filtered_scores, decreasing = TRUE)
  top_basenames <- head(filtered_basenames[top_order], max_results)
  top_scores <- head(filtered_scores[top_order], max_results)

  cat("[KAYNAKÇA-LOCAL] Eşleşen dosyalar:\n")
  for (j in seq_along(top_basenames)) {
    cat("  ", j, ") ", top_basenames[j], " (puan: ", top_scores[j], ")\n", sep = "")
  }

  # Tıklanabilir Kaynakça HTML'i oluştur
  kaynakca_html <- build_kaynakca_from_local_files(top_basenames, idx$map)
  cat("[KAYNAKÇA-LOCAL] Kaynakça oluşturuldu:", length(top_basenames), "dosya\n")
  kaynakca_html
}