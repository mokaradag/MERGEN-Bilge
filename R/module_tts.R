# R/module_tts.R
# Dosya Yolu: R/module_tts.R
# Açıklama: OpenAI uyumlu Metinden Sese (TTS) dönüştürme modülü.
#           Düşük gecikme süresi için optimize edilmiştir (Namespace kullanımı, 
#           worker'larda kütüphane yüklemesi yapılmaz).

#' TTS İşleme Sunucu Modülü
#'
#' OpenAI uyumlu bir `/audio/speech` uç noktası kullanarak metni sese dönüştürmek
#' için asenkron bir yardımcı sağlar. Sohbet arayüzüne enjekte edilebilen 
#' base64 kodlu ses URL'leri döndürür.
#'
#' @param id Modül ad alanı kimliği
#' @return Modül sunucu mantığı (synthesize_speech, tts_available, prepare_tts_text fonksiyonlarını içeren liste)
ttsProcessingServer <- function(id) {
  moduleServer(id, function(input, output, session) {

    #' TTS hizmetinin kullanılabilir olup olmadığını kontrol et (uç nokta yapılandırılmış mı?)
    tts_available <- function() {
      endpoint <- tts_config$base_url %||% ""
      nzchar(endpoint)
    }

    #' TTS'e göndermeden önce metni normalleştir (temizle)
    #' Kod bloklarını, bağlantıları, emojileri ve özel karakterleri ayıklar.
    #' Sayısal değerleri Türkçe okunuşlarına dönüştürür.
    prepare_tts_text <- function(text) {
      if (!is.character(text) || length(text) == 0) return("")

      cleaned <- as.character(text[1])
      # Kod bloklarını kaldır (çok satırlı)
      cleaned <- gsub("```[\\s\\S]*?```", " ", cleaned, perl = TRUE)
      # Satır içi kod tırnaklarını kaldır
      cleaned <- gsub("`([^`]*)`", "\\1", cleaned)
      # Markdown bağlantılarından sadece metni al: [metin](url) -> metin (URL'lerden önce)
      cleaned <- gsub("\\[([^\\]]*?)\\]\\([^)]*\\)", "\\1", cleaned, perl = TRUE)
      # Köşeli parantez referanslarını kaldır [DOC] veya [1]
      cleaned <- gsub("\u3010[^\u3011]+\u3011", " ", cleaned)
      cleaned <- gsub("\\[[^\\]]*\\]", " ", cleaned, perl = TRUE)
      # Çıplak URL'leri kaldır (http/https/www ile başlayanlar)
      cleaned <- gsub("https?://[^\\s)]+", " ", cleaned, perl = TRUE)
      cleaned <- gsub("www\\.[^\\s)]+", " ", cleaned, perl = TRUE)
      # E-posta adreslerini kaldır
      cleaned <- gsub("[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}", " ", cleaned, perl = TRUE)
      # Emoji ve özel Unicode karakterleri kaldır
      cleaned <- gsub("[\U0001F600-\U0001F64F]", "", cleaned, perl = TRUE)
      cleaned <- gsub("[\U0001F300-\U0001F5FF]", "", cleaned, perl = TRUE)
      cleaned <- gsub("[\U0001F680-\U0001F6FF]", "", cleaned, perl = TRUE)
      cleaned <- gsub("[\U0001F1E0-\U0001F1FF]", "", cleaned, perl = TRUE)
      cleaned <- gsub("[\U00002702-\U000027B0]", "", cleaned, perl = TRUE)
      cleaned <- gsub("[\U0000FE00-\U0000FE0F]", "", cleaned, perl = TRUE)
      cleaned <- gsub("[\U0001F900-\U0001F9FF]", "", cleaned, perl = TRUE)
      cleaned <- gsub("[\U0001FA00-\U0001FA6F]", "", cleaned, perl = TRUE)
      cleaned <- gsub("[\U0001FA70-\U0001FAFF]", "", cleaned, perl = TRUE)
      cleaned <- gsub("[\U00002600-\U000026FF]", "", cleaned, perl = TRUE)
      cleaned <- gsub("[\U0000200D\U0000FE0F\U000020E3]", "", cleaned, perl = TRUE)
      cleaned <- gsub("[\U00002B50\U00002B55\U0000231A\U0000231B\U00002328\U000023CF\U000023E9-\U000023F3\U000023F8-\U000023FA]", "", cleaned, perl = TRUE)
      # Dosya yollarını kaldır (Windows ve Unix)
      cleaned <- gsub("[A-Z]:\\\\[^\\s]+", " ", cleaned, perl = TRUE)
      cleaned <- gsub("/[a-zA-Z0-9_./\\-]+\\.[a-zA-Z]{2,4}", " ", cleaned, perl = TRUE)
      # Markdown biçimlendirme karakterlerini kaldır (her birini ayrı ayrı, ilk/son karakteri yutmamak için)
      cleaned <- gsub("\\*{1,3}", " ", cleaned)   # Kalın/italik yıldızlar
      cleaned <- gsub("_{1,3}", " ", cleaned)     # Kalın/italik alt çizgiler
      cleaned <- gsub("^#{1,6}\\s+", "", cleaned, perl = TRUE)  # Satır başı başlık işaretleri
      cleaned <- gsub("\\n#{1,6}\\s+", "\n", cleaned, perl = TRUE)  # Ara satır başlıkları
      cleaned <- gsub("^>\\s*", "", cleaned, perl = TRUE)  # Alıntı işaretleri (satır başı)
      cleaned <- gsub("\\n>\\s*", "\n", cleaned, perl = TRUE)  # Alıntı işaretleri (ara satır)
      cleaned <- gsub("^\\s*[-]\\s+", "", cleaned, perl = TRUE)  # Liste işaretleri (tire, satır başı)
      cleaned <- gsub("\\n\\s*[-]\\s+", "\n", cleaned, perl = TRUE)  # Liste işaretleri (tire, ara satır)
      # Tırnak karakterlerini sadeleştir (akışı bozup ilk harfi yutabilen durumları azaltır)
      cleaned <- gsub("[“”«»]", "\"", cleaned, perl = TRUE)
      # Noktalama/tırnak sonrası boşluk ekle (karakterin yutulmasını önler)
      cleaned <- gsub("([.!?,:;\"'])([[:alpha:]\\p{L}])", "\\1 \\2", cleaned, perl = TRUE)
      # Açılış tırnağından sonra boşluk bırak: \"Bey\" -> \" Bey\"
      cleaned <- gsub("([\"'])([[:alpha:]\\p{L}])", "\\1 \\2", cleaned, perl = TRUE)
      # Sayıları Türkçe okunuşlarına dönüştür
      cleaned <- convert_numbers_to_turkish(cleaned)
      # Satır sonlarını ve fazla boşlukları normalleştir
      cleaned <- gsub("\n+", ". ", cleaned)
      cleaned <- gsub("[[:space:]]+", " ", cleaned)
      trimws(cleaned)
    }

    #' Sayısal değerleri Türkçe metin okunuşlarına dönüştür
    #' @param text Dönüştürülecek metin
    #' @return Sayıları Türkçe kelimelerle değiştirilmiş metin
    convert_numbers_to_turkish <- function(text) {
      if (!is.character(text) || !nzchar(text)) return(text)

      # Ondalıklı sayıları işle (örn: 3.14 -> "üç nokta on dört")
      text <- gsub("(\\d+)[.,](\\d+)", "\\1 nokta \\2", text, perl = TRUE)

      # Yüzde ifadelerini işle (örn: %50 -> "yüzde elli")
      text <- gsub("%(\\d+)", "y\u00FCzde \\1", text, perl = TRUE)

      # Tekil rakamlar tablosu
      birler <- c("0" = "s\u0131f\u0131r", "1" = "bir", "2" = "iki", "3" = "\u00FC\u00E7",
                  "4" = "d\u00F6rt", "5" = "be\u015F", "6" = "alt\u0131",
                  "7" = "yedi", "8" = "sekiz", "9" = "dokuz")
      onlar <- c("10" = "on", "20" = "yirmi", "30" = "otuz", "40" = "k\u0131rk",
                 "50" = "elli", "60" = "altm\u0131\u015F", "70" = "yetmi\u015F",
                 "80" = "seksen", "90" = "doksan")

      # Tek sayıyı Türkçe kelimeye çeviren iç fonksiyon
      number_to_word <- function(n) {
        n <- as.integer(n)
        if (is.na(n)) return(as.character(n))
        if (n < 0) return(paste("eksi", number_to_word(abs(n))))
        if (n == 0) return("s\u0131f\u0131r")

        result <- ""

        # Milyonlar
        if (n >= 1000000) {
          milyon <- n %/% 1000000
          if (milyon == 1) {
            result <- paste0(result, "bir milyon ")
          } else {
            result <- paste0(result, number_to_word(milyon), " milyon ")
          }
          n <- n %% 1000000
        }

        # Binler
        if (n >= 1000) {
          bin <- n %/% 1000
          if (bin == 1) {
            result <- paste0(result, "bin ")
          } else {
            result <- paste0(result, number_to_word(bin), " bin ")
          }
          n <- n %% 1000
        }

        # Yüzler
        if (n >= 100) {
          yuz <- n %/% 100
          if (yuz == 1) {
            result <- paste0(result, "y\u00FCz ")
          } else {
            result <- paste0(result, birler[as.character(yuz)], " y\u00FCz ")
          }
          n <- n %% 100
        }

        # Onlar
        if (n >= 10) {
          on_val <- (n %/% 10) * 10
          result <- paste0(result, onlar[as.character(on_val)], " ")
          n <- n %% 10
        }

        # Birler
        if (n > 0) {
          result <- paste0(result, birler[as.character(n)])
        }

        trimws(result)
      }

      # Metindeki bağımsız sayıları kelimeye dönüştür (en fazla 7 basamak)
      matches <- gregexpr("\\b\\d{1,7}\\b", text, perl = TRUE)

      # Sayıları sondan başa doğru değiştir (konum kaymasını önlemek için)
      if (length(matches[[1]]) > 0 && matches[[1]][1] != -1) {
        positions <- matches[[1]]
        lengths <- attr(matches[[1]], "match.length")
        for (i in rev(seq_along(positions))) {
          num_str <- substr(text, positions[i], positions[i] + lengths[i] - 1)
          word <- number_to_word(as.integer(num_str))
          text <- paste0(
            substr(text, 1, positions[i] - 1),
            word,
            substr(text, positions[i] + lengths[i], nchar(text))
          )
        }
      }

      text
    }

    #' Nihai ses uç noktası (speech endpoint) URL'sini oluştur
    build_speech_url <- function() {
      base <- tts_config$base_url %||% ""
      if (!nzchar(base)) return("")
      base <- sub("/+$", "", base)
      if (grepl("/audio/speech$", base, ignore.case = TRUE)) {
        return(base)
      }
      paste0(base, "/audio/speech")
    }

    #' TTS uç noktası için API anahtarını belirle
    #' Öncelik: oturum anahtarı > TTS anahtarı > birincil LLM anahtarı
    resolve_tts_api_key <- function() {
      # 1. Oturuma özel anahtarı dene (kullanıcının LLM API anahtarı)
      user_key <- tryCatch({
        sess_key <- session$userData$ai_api_key %||% NULL
        if (is.null(sess_key) || !nzchar(sess_key)) return(NULL)
        as.character(sess_key)[1]
      }, error = function(e) NULL)

      if (!is.null(user_key) && nzchar(user_key)) {
        return(user_key)
      }

      # 2. TTS'e özel yapılandırma anahtarını dene
      default_key <- tts_config$api_key %||% ""
      if (is.null(default_key) || is.na(default_key)) default_key <- ""
      if (nzchar(default_key)) return(default_key)

      # 3. Birincil LLM API anahtarını dene (TTS anahtarı boşsa yedek)
      llm_key <- tryCatch(Sys.getenv("LOCAL_LLM_API_KEY", ""), error = function(e) "")
      if (!is.null(llm_key) && nzchar(llm_key)) return(llm_key)

      ""
    }

    #' Asenkron olarak ses sentezle
    #' @param text Seslendirilecek metin
    #' @param voice Kullanılacak ses (opsiyonel)
    #' @return promise nesnesi: list(success, audio_src, voice, duration, error)
    synthesize_speech <- function(text, voice = NULL) {
      if (!tts_available()) {
        cat("[TTS] Seslendirme kullanılamıyor: uç nokta yapılandırılmamış\n")
        return(promises::promise_resolve(list(
          success = FALSE, audio_src = NULL, voice = voice, duration = 0, error = "TTS uç noktası yapılandırılmamış."
        )))
      }

      speech_text <- prepare_tts_text(text)
      if (!nzchar(speech_text)) {
        cat("[TTS] Temizleme sonrası metin boş, seslendirme atlanıyor\n")
        return(promises::promise_resolve(list(
          success = FALSE, audio_src = NULL, voice = voice, duration = 0, error = "Seslendirilecek metin boş."
        )))
      }
      # Bazı TTS motorlarında ilk fonemin kırpılmasını azaltmak için
      # metnin başına kısa bir duraklama işareti ekle.
      speech_text <- paste0(". ", speech_text)

      # --- ANA SÜREÇ DEĞİŞKENLERİ (Future içine aktarılmadan önce yakalanır) ---
      speech_url   <- build_speech_url()
      voice_to_use <- voice %||% tts_config$default_voice %||% "tr-male-1"
      api_key      <- resolve_tts_api_key()
      model_to_use <- tts_config$model %||% "tts-1-hd"
      timeout_val  <- as.numeric(tts_config$timeout_seconds %||% 30)
      if (is.na(timeout_val) || timeout_val <= 0) timeout_val <- 30

      cat(sprintf("[TTS] İstek hazırlanıyor: URL=%s | Model=%s | Ses=%s | API Key uzunluk=%d | Metin=%d karakter\n",
                  speech_url, model_to_use, voice_to_use, nchar(api_key), nchar(speech_text)))
      
      verify_ssl_val <- tts_config$verify_ssl
      should_verify  <- if (is.null(verify_ssl_val)) FALSE else isTRUE(verify_ssl_val)
      
      # Log dosyası yolu (mutlak yol)
      debug_log_file <- normalizePath(file.path("logs", "tts_debug.txt"), mustWork = FALSE)
      if (!file.exists(dirname(debug_log_file))) dir.create(dirname(debug_log_file), recursive = TRUE)

      # --- ASENKRON ÇALIŞTIRICI (WORKER) BAŞLANGICI ---
      future_promise({
        start_time <- Sys.time()
        
        # -- Worker Tarafı Log Yardımcısı --
        worker_log <- function(msg) {
          try({
            cat(sprintf("[%s] [Worker-%s] %s\n", 
                        format(Sys.time(), "%H:%M:%S"), 
                        Sys.getpid(), 
                        msg), 
                file = debug_log_file, append = TRUE)
          }, silent = TRUE)
        }

        worker_log(sprintf("BAŞLATMA: URL=%s | Model=%s | Ses=%s", speech_url, model_to_use, voice_to_use))

        # ÖNEMLİ: Burada library() çağrısı yapılmaz. Gecikmeyi azaltmak için 
        # açık ad alanları (httr::, base64enc::) kullanılır.

        # Üstbilgi (Header) Kurulumu
        headers <- c(
          `Content-Type` = "application/json",
          `Authorization` = paste("Bearer", api_key)
        )

        # Gövde (Body) Kurulumu
        body_data <- list(
          model = model_to_use,
          voice = voice_to_use,
          input = speech_text,
          response_format = "wav"
        )
        
        # Yapılandırma Kurulumu (Gerekiyorsa SSL doğrulaması atlanır)
        req_config <- if (isTRUE(should_verify)) {
           list() 
        } else {
           httr::config(ssl_verifypeer = 0L, ssl_verifyhost = 0L)
        }
        
        worker_log("POST İsteği Gönderiliyor...")
        
        # İstek Yürütme
        resp <- tryCatch({
          httr::POST(
            url = speech_url,
            httr::add_headers(.headers = headers),
            body = body_data,
            encode = "json",
            httr::timeout(timeout_val),
            req_config 
          )
        }, error = function(e) {
           worker_log(sprintf("POST İşleminde Kritik Hata: %s", conditionMessage(e)))
           return(list(error_obj = e))
        })
        
        # Bağlantı Hatalarını Yönet
        if (is.list(resp) && !is.null(resp$error_obj)) {
           err_msg <- conditionMessage(resp$error_obj)
           return(list(success = FALSE, audio_src = NULL, voice = voice_to_use, duration = 0, error = err_msg))
        }

        status <- httr::status_code(resp)
        worker_log(sprintf("YANIT Durumu: %d", status))

        if (status >= 200 && status < 300) {
          content_type <- httr::headers(resp)[["content-type"]] %||% ""
          mime_type <- "audio/wav"
          if (nzchar(content_type)) {
            mime_type <- strsplit(content_type, ";", fixed = TRUE)[[1]][1]
          }

          audio_src <- NULL
          
          # JSON sarmalayıcı kontrolü (bazı proxy'lerde nadir de olsa görülebilir)
          if (grepl("json", content_type, ignore.case = TRUE)) {
            parsed <- tryCatch(httr::content(resp, as = "parsed", encoding = "UTF-8"),
                               error = function(e) NULL)
            b64 <- NULL
            if (is.list(parsed)) {
              if (!is.null(parsed$audio)) b64 <- parsed$audio
              else if (!is.null(parsed$data)) b64 <- parsed$data
              else if (!is.null(parsed$content)) b64 <- parsed$content
            }
            if (!is.null(b64) && nzchar(as.character(b64)[1])) {
              b64_str <- as.character(b64)[1]
              if (startsWith(b64_str, "data:")) {
                audio_src <- b64_str
              } else {
                audio_src <- paste0("data:", mime_type, ";base64,", b64_str)
              }
            }
          }

          # Standart İkili (Binary) Yanıt (OpenAI API için en yaygın durum)
          if (is.null(audio_src)) {
            audio_raw <- httr::content(resp, as = "raw")
            worker_log(sprintf("İKİLİ İÇERİK: %d bayt alındı", length(audio_raw)))
            
            if (length(audio_raw) > 0) {
                # base64enc paketini doğrudan kullan
                audio_b64 <- base64enc::base64encode(audio_raw)
                audio_src <- paste0("data:", mime_type, ";base64,", audio_b64)
            }
          }

          if (!nzchar(audio_src)) {
            worker_log("BAŞARISIZ: Ses içeriği boş.");
            return(list(success = FALSE, audio_src = NULL, voice = voice_to_use,
                        duration = 0, error = "Ses yanıtı boş döndü."))
          }
          
          duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
          worker_log(sprintf("BAŞARILI: Ses %.2fs içinde hazırlandı", duration))

          list(success = TRUE, audio_src = audio_src, voice = voice_to_use,
               duration = duration, error = NULL)
        } else {
          err_msg <- tryCatch(httr::content(resp, as = "text", encoding = "UTF-8"),
                              error = function(e) "TTS isteği başarısız oldu.")
          worker_log(sprintf("API HATASI: %s", substr(err_msg, 1, 100)))
          list(success = FALSE, audio_src = NULL, voice = voice_to_use,
               duration = 0, error = paste("TTS hata:", err_msg))
        }
      }) %...!% (function(e) {
        # İşlenmemiş istisnaları (exception) logla
        cat(sprintf("[TTS] Worker hatası: %s\n", conditionMessage(e)))
        try({
           cat(sprintf("[%s] [Worker-HATA] %s\n", format(Sys.time(), "%H:%M:%S"), conditionMessage(e)),
               file = normalizePath(file.path("logs", "tts_debug.txt"), mustWork = FALSE), append = TRUE)
        }, silent = TRUE)

        list(success = FALSE, audio_src = NULL, voice = voice_to_use,
             duration = 0, error = conditionMessage(e))
      })
    }

    list(
      synthesize_speech = synthesize_speech,
      tts_available = tts_available,
      prepare_tts_text = prepare_tts_text
    )
  })
}

#' Sohbet mesajı için yeniden kullanılabilir ses oynatıcı UI parçası oluştur
#'
#' @param message_id Mesajın kimliği
#' @param audio_src Base64 kodlu ses kaynağı
#' @param voice Ses adı (etiket için)
#' @return HTML div elemanı
build_tts_audio_ui <- function(message_id, audio_src, voice = NULL) {
  if (is.null(audio_src) || !nzchar(audio_src)) return(NULL)

  label <- if (!is.null(voice) && nzchar(voice)) {
    paste("Ses:", voice)
  } else {
    "Sesli Yanıt"
  }

  div(
    id = paste0("tts_audio_", message_id),
    class = "tts-audio-wrapper",
    div(
      class = "tts-audio-header",
      tags$i(class = "fas fa-volume-up"),
      span(label)
    ),
  tags$audio(
      controls = "controls",
      preload = "auto",
      src = audio_src
    )
  )
}
