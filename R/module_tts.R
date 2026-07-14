# R/module_tts.R
# Dosya Yolu: R/module_tts.R
# Açıklama: OpenAI/VoxCPM2 uyumlu Metinden Sese (TTS) dönüştürme modülü.
#           Düşük gecikme süresi için optimize edilmiştir (Namespace kullanımı,
#           worker'larda kütüphane yüklemesi yapılmaz). VoxCPM2 referans-ses
#           profili, üretilen-ses önbelleği ve sınırlı eşzamanlılık kuyruğu
#           mantığı ayrı yardımcı dosyalarındadır; bu modül yalnızca ince
#           entegrasyon çağrıları yapar.

#' TTS İşleme Sunucu Modülü
#'
#' OpenAI/VoxCPM2 uyumlu bir `/audio/speech` uç noktası kullanarak metni sese
#' dönüştürmek için asenkron bir yardımcı sağlar. Sohbet arayüzüne enjekte
#' edilebilen base64 kodlu ses URL'leri döndürür.
#'
#' @param id Modül ad alanı kimliği
#' @param settings_data (opsiyonel) Merkezi ayarlar reaktif değerleri; verilirse
#'   seçili persona profili konuşma özelliği açıldığında tembel ön yüklenir.
#' @return Modül sunucu mantığı listesi (synthesize_speech, tts_available,
#'   prepare_tts_text, preload_profile)
ttsProcessingServer <- function(id, settings_data = NULL) {
  moduleServer(id, function(input, output, session) {

    #' TTS hizmetinin kullanılabilir olup olmadığını kontrol et (uç nokta yapılandırılmış mı?)
    tts_available <- function() {
      endpoint <- tts_config$base_url %||% ""
      nzchar(endpoint)
    }

    #' TTS'e göndermeden önce metni hazırla (yalın geçiş).
    #' Kullanıcıdan veya modelden gelen metni ek sanitizasyon yapmadan iletir.
    prepare_tts_text <- function(text) {
      if (!is.character(text) || length(text) == 0) return("")
      as.character(text[1])
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
    #' Öncelik: kişisel anahtar > TTS servis anahtarı > izinli kurum anahtarı > eski LLM anahtarı
    resolve_tts_api_key <- function() {
      tts_service_key <- tts_config$api_key %||% ""
      legacy_llm_key <- tryCatch(Sys.getenv("LOCAL_LLM_API_KEY", ""), error = function(e) "")

      mb_api_key_get_feature_key_value(
        session = session,
        service_key = tts_service_key,
        fallback_key = legacy_llm_key,
        require_auth = TRUE,
        clear_on_mismatch = TRUE,
        prefer_service_key_after_personal = TRUE
      )
    }

    #' Seçili persona ses profilini tembel yükle (yalnızca doğrula + base64;
    #' ağ isteği veya konuşma üretimi YAPMAZ). VoxCPM2 profilleri kapalıysa
    #' güvenli no-op. Aynı profil sürümü için base64 yalnızca bir kez üretilir.
    preload_profile <- function(char_id = NULL) {
      if (!isTRUE(mergen_tts_voice_profiles_enabled(tts_config))) return(invisible(FALSE))
      pid <- mergen_tts_profile_for_character(char_id)
      # Ana Söyleşi'nin açılış-kritik yolunu bloklamamak için düşük öncelikle ertele.
      later::later(function() {
        tryCatch({
          res <- mergen_tts_load_profile_cached(pid, tts_config)
          if (isTRUE(res$ok)) {
            cat(sprintf("[TTS] Ses profili yüklendi: %s (sürüm %s)\n", pid, res$version %||% "?"))
          } else {
            cat(sprintf("[TTS] Ses profili yüklenemedi: %s - %s\n", pid, res$error %||% "bilinmeyen"))
          }
        }, error = function(e) {
          cat(sprintf("[TTS] Ses profili ön yükleme hatası (%s): %s\n", pid, conditionMessage(e)))
        })
      }, delay = 0.1)
      invisible(TRUE)
    }

    resolve_profile_id_for_speech <- function(profile_id = NULL) {
      explicit_profile <- tolower(trimws(as.character(profile_id %||% "")[1]))
      if (nzchar(explicit_profile)) return(explicit_profile)
      if (!isTRUE(mergen_tts_voice_profiles_enabled(tts_config))) return(NULL)

      char_id <- tryCatch({
        if (!is.null(settings_data) && !is.null(settings_data$selected_character)) {
          shiny::isolate(settings_data$selected_character)
        } else {
          NULL
        }
      }, error = function(e) NULL)

      if (!exists("mergen_tts_profile_for_character", mode = "function", inherits = TRUE)) return(NULL)
      resolved <- tryCatch(mergen_tts_profile_for_character(char_id), error = function(e) NULL)
      resolved <- tolower(trimws(as.character(resolved %||% "")[1]))
      if (nzchar(resolved)) resolved else NULL
    }

    #' Asenkron olarak ses sentezle
    #' @param text Seslendirilecek metin
    #' @param voice Kullanılacak jenerik yedek ses (opsiyonel)
    #' @param profile_id VoxCPM2 persona ses profili kimliği (opsiyonel)
    #' @param should_cancel Kuyruk başlamadan iptali kontrol eden fonksiyon (opsiyonel)
    #' @return promise nesnesi: list(success, audio_src, voice, duration, error)
    synthesize_speech <- function(text, voice = NULL, profile_id = NULL, should_cancel = NULL) {
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

      profile_to_use <- resolve_profile_id_for_speech(profile_id)

      # --- KONUŞMA PLANI (profil çözümleme + önbellek; ana süreçte, worker öncesi) ---
      plan <- tryCatch(
        mergen_tts_prepare_speech_plan(speech_text, config = tts_config, profile_id = profile_to_use, voice = voice),
        error = function(e) NULL
      )
      if (is.null(plan)) {
        # Yardımcılar yoksa jenerik güvenli plana düş (eski davranış).
        plan <- list(
          body = list(
            model = tts_config$model %||% "tts-1-hd",
            input = speech_text,
            voice = voice %||% tts_config$default_voice %||% "default",
            response_format = "mp3"
          ),
          mime_type = "audio/mpeg", voice = voice %||% tts_config$default_voice %||% "default",
          cached_audio_src = NULL, cache_write_path = "", profile_active = FALSE
        )
      }

      voice_to_use <- plan$voice %||% "default"

      # --- ÜRETİLEN-SES ÖNBELLEĞİ İSABETİ: ağ turu olmadan birebir aynı ses ---
      if (!is.null(plan$cached_audio_src) && nzchar(plan$cached_audio_src)) {
        cat(sprintf("[TTS] Önbellek isabeti (profil=%s), ağ isteği atlanıyor.\n", profile_to_use %||% "-"))
        return(promises::promise_resolve(list(
          success = TRUE, audio_src = plan$cached_audio_src, voice = voice_to_use,
          duration = 0, error = NULL, cache_hit = TRUE
        )))
      }

      # --- ANA SÜREÇ DEĞİŞKENLERİ (Future içine aktarılmadan önce yakalanır) ---
      speech_url       <- build_speech_url()
      api_key          <- resolve_tts_api_key()
      model_to_use     <- plan$body$model %||% (tts_config$model %||% "tts-1-hd")
      body_data        <- plan$body
      mime_default     <- plan$mime_type %||% "audio/mpeg"
      cache_write_path <- plan$cache_write_path %||% ""
      timeout_val      <- as.numeric(tts_config$timeout_seconds %||% 90)
      if (is.na(timeout_val) || timeout_val <= 0) timeout_val <- 90
      verify_ssl_val   <- tts_config$verify_ssl
      should_verify    <- if (is.null(verify_ssl_val)) FALSE else isTRUE(verify_ssl_val)

      # Gövde (ref_audio base64) ASLA loglanmaz.
      cat(sprintf("[TTS] İstek: URL=%s | Model=%s | Ses=%s | Profil=%s | API Key uzunluk=%d | Metin=%d karakter\n",
                  speech_url, model_to_use, voice_to_use,
                  if (isTRUE(plan$profile_active)) (profile_to_use %||% "-") else "jenerik",
                  nchar(api_key), nchar(speech_text)))

      debug_log_file <- normalizePath(file.path("logs", "tts_debug.txt"), mustWork = FALSE)
      if (!file.exists(dirname(debug_log_file))) dir.create(dirname(debug_log_file), recursive = TRUE)

      queue <- tryCatch(mergen_tts_default_queue(tts_config), error = function(e) NULL)

      # --- ASENKRON ÇALIŞTIRICI (WORKER) FABRİKASI ---
      worker_factory <- function() {
        tracked_future_promise(
          task_fn = function() {
            start_time <- Sys.time()

            worker_log <- function(msg) {
              try({
                cat(sprintf("[%s] [Worker-%s] %s\n",
                            format(Sys.time(), "%H:%M:%S"), Sys.getpid(), msg),
                    file = debug_log_file, append = TRUE)
              }, silent = TRUE)
            }

            worker_log(sprintf("BAŞLATMA: URL=%s | Model=%s | Ses=%s", speech_url, model_to_use, voice_to_use))

            # ÖNEMLİ: Burada library() çağrısı yapılmaz; açık ad alanları kullanılır.
            headers <- c(
              `Content-Type` = "application/json",
              `Authorization` = paste("Bearer", api_key)
            )

            req_config <- if (isTRUE(should_verify)) {
              list()
            } else {
              httr::config(ssl_verifypeer = 0L, ssl_verifyhost = 0L)
            }

            worker_log("POST İsteği Gönderiliyor...")

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

            if (is.list(resp) && !is.null(resp$error_obj)) {
              err_msg <- conditionMessage(resp$error_obj)
              return(list(success = FALSE, audio_src = NULL, voice = voice_to_use, duration = 0, error = err_msg))
            }

            status <- httr::status_code(resp)
            worker_log(sprintf("YANIT Durumu: %d", status))

            if (status >= 200 && status < 300) {
              content_type <- httr::headers(resp)[["content-type"]] %||% ""
              mime_type <- mime_default
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

              # Standart İkili (Binary) Yanıt (OpenAI/VoxCPM2 için en yaygın durum)
              if (is.null(audio_src)) {
                audio_raw <- httr::content(resp, as = "raw")
                worker_log(sprintf("İKİLİ İÇERİK: %d bayt alındı", length(audio_raw)))

                if (length(audio_raw) > 0) {
                  # Üretilen sesi önbelleğe atomik yaz (ham baytlar burada mevcut).
                  if (nzchar(cache_write_path)) {
                    try({
                      cdir <- dirname(cache_write_path)
                      if (!dir.exists(cdir)) dir.create(cdir, recursive = TRUE, showWarnings = FALSE)
                      tmp <- paste0(cache_write_path, ".tmp-", Sys.getpid(), "-", as.integer(stats::runif(1, 1, 1e9)))
                      con2 <- file(tmp, open = "wb"); writeBin(audio_raw, con2); close(con2)
                      if (!isTRUE(suppressWarnings(file.rename(tmp, cache_write_path)))) {
                        file.copy(tmp, cache_write_path, overwrite = TRUE); unlink(tmp, force = TRUE)
                      }
                    }, silent = TRUE)
                  }
                  audio_b64 <- base64enc::base64encode(audio_raw)
                  audio_src <- paste0("data:", mime_type, ";base64,", audio_b64)
                }
              }

              if (!nzchar(audio_src)) {
                worker_log("BAŞARISIZ: Ses içeriği boş.")
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
              safe_err_msg <- if (exists("mergen_tts_redact_error_text", mode = "function", inherits = TRUE)) {
                mergen_tts_redact_error_text(err_msg)
              } else {
                "TTS isteği başarısız oldu."
              }
              worker_log(sprintf("API HATASI: %s", substr(safe_err_msg, 1, 100)))
              list(success = FALSE, audio_src = NULL, voice = voice_to_use,
                   duration = 0, error = paste("TTS hata:", safe_err_msg))
            }
          },
          task_type = "tts",
          session_token = session$token,
          meta = list(voice = voice_to_use, model = model_to_use)
        )
      }

      on_worker_error <- function(e) {
        cat(sprintf("[TTS] Worker hatası: %s\n", conditionMessage(e)))
        try({
          cat(sprintf("[%s] [Worker-HATA] %s\n", format(Sys.time(), "%H:%M:%S"), conditionMessage(e)),
              file = normalizePath(file.path("logs", "tts_debug.txt"), mustWork = FALSE), append = TRUE)
        }, silent = TRUE)
        list(success = FALSE, audio_src = NULL, voice = voice_to_use,
             duration = 0, error = conditionMessage(e))
      }

      # Sınırlı eşzamanlılık kuyruğuyla gönder (iptal-farkındalı); kuyruk yoksa
      # doğrudan çalıştır (geriye dönük güvenli davranış).
      if (is.environment(queue) && is.function(queue$submit)) {
        queue$submit(worker_factory, should_cancel = should_cancel) %...!% on_worker_error
      } else {
        worker_factory() %...!% on_worker_error
      }
    }

    # TTS/AI Uzman açıksa seçili profili tembel ön yükleme politikasını bağla.
    if (!is.null(settings_data) &&
        exists("mergen_tts_bind_profile_preload", mode = "function", inherits = TRUE)) {
      tryCatch(
        mergen_tts_bind_profile_preload(
          session = session,
          settings_data = settings_data,
          tts_processor = list(preload_profile = preload_profile)
        ),
        error = function(e) cat(sprintf("[TTS] Profil ön yükleme bağlanamadı: %s\n", conditionMessage(e)))
      )
    }

    list(
      synthesize_speech = synthesize_speech,
      tts_available = tts_available,
      prepare_tts_text = prepare_tts_text,
      preload_profile = preload_profile
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
      src = audio_src,
      `data-mergen-audio-owner` = "tts_manual"
    )
  )
}
