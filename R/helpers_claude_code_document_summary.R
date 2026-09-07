# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_document_summary.R
# Açıklama: Bilge Yolaç doküman ÖZETLEME orkestrasyonu. Kullanıcı prompt'undan
#           özet detay seviyesini çözer, özetleme LLM mesajlarını kurar, yerel
#           LLM ile özeti üretir ve dosya_aciklamalari.txt çıktısını yazar.
#           helpers_claude_code_documents.R'den ayrıldı (doküman BAĞLAM hazırlığı
#           orada kalır). UTF-8 BOM yazıcı paylaşılan yardımcı olduğu için
#           documents.R'de kalır ve bu dosyadan ÖNCE yüklenir.
# ==============================================================================

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
      # "tam" sözcük sınırı olmadan "tamir", "tamam", "tamamlandı" gibi
      # sözcüklerin içinde de eşleşiyordu ve detay seviyesi yanlış çözülüyordu.
      "\\btam\\b",
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

  if (!isTRUE(write_claude_code_utf8_bom_text_file(summary_text, hedef_yol))) {
    return("")
  }

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
