# R/server_llm_response_handlers.R
# Dosya Yolu: R/server_llm_response_handlers.R
# Açıklama: LLM yanıt işleyicileri - non-streaming mod için AI yanıt işleme fonksiyonları.
# Bu dosya server.R'den ayrılarak modülerlik sağlanmıştır.
 
#' LLM Yanıt İşleyicilerini Başlat
#' @description Non-streaming LLM yanıt işleme fonksiyonlarını kurar
#' @param session Shiny session nesnesi
#' @param values Ana reaktif değerler
#' @param settings_data Ayarlar modülünden dönen reaktif ayarlar
#' @param ai_processor AI işleme modülü
#' @param perf_tracker Performans izleme modülü
#' @param active_request_id Aktif istek kimliği reactiveVal
#' @param stop_generation Durdurma sinyali reactiveVal
#' @param reset_chat_state_fn Sohbet durumunu sıfırlama fonksiyonu
#' @param add_message_fn Mesaj ekleme fonksiyonu
#' @param trigger_tts_fn TTS tetikleme fonksiyonu
#' @param followup_tools Takip soruları araçları
#' @param fallback_followup_tool Yedek takip soruları aracı
#' @param api_config API yapılandırması
#' @return LLM yanıt işleyici fonksiyonlarını içeren liste
llmResponseHandlersInit <- function(
  session,
  values,
  settings_data,
  ai_processor,
  perf_tracker,
  active_request_id,
  stop_generation,
  reset_chat_state_fn,
  add_message_fn,
  trigger_tts_fn,
  followup_tools,
  fallback_followup_tool,
  api_config
) {
 
  # Non-streaming LLM yanıt işleyicisi
  # Bu fonksiyon AI'dan gelen yanıtları işler ve kullanıcıya gösterir
  generate_non_streaming_stoppable <- function(
    chat_history,
    current_settings,
    user_prompt_msg,
    chat_id_val,
    model_selected,
    last_user_text = NULL,
    current_user_id = NULL
  ) {
 
    # Benzersiz istek kimliği oluştur
    req_id <- paste0("req_", format(Sys.time(), "%Y%m%d%H%M%OS3"), "_", sample(1000:9999, 1))
    active_request_id(req_id)
 
    # Debug için ayarları kaydet (session hariç)
    safe_settings <- current_settings
    safe_settings$shiny_session <- NULL
    dbg_dump("LLM_REQUEST_NONSTREAM", list(
      model = model_selected,
      messages = chat_history,
      settings = safe_settings
    ))
 
    # AI işlemcisini çağır
    p <- ai_processor$call_llm_non_streaming(chat_history, current_settings, model_selected)
 
    # Promise zincirini oluştur ve sonucu işle
    p2 <- promises::then(
      p,
      onFulfilled = function(result) {
        # İstek durdurulduysa veya farklı bir istek aktifse çık
        if (isTRUE(stop_generation()) || !identical(active_request_id(), req_id)) {
          perf_tracker$track_error()
          shiny::removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
          values$typing <- FALSE
          reset_chat_state_fn()
          return(invisible(NULL))
        }
 
        # Debug için yanıtı kaydet
        dbg_dump("LLM_RESPONSE_NONSTREAM", list(
          success = result$success,
          duration = result$duration %||% NA_real_,
          content_preview = substr(result$content %||% "", 1, 800),
          error = result$error %||% NULL
        ))
 
        if (result$success) {
          # Debug: Yanıtın tipi ve uzunluğu
          cat("[AI_RESP] success=TRUE; class=", paste(class(result$content), collapse=","),
              " length=", if (is.null(result$content)) NA_integer_ else length(result$content),
              ' preview="', substr(as.character(result$content)[1], 1, 120), '"\n', sep="")
 
          # Performans takibi
          perf_tracker$track_request(result$duration)
 
          # Yazma animasyonunu kaldır
          shiny::removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
          values$typing <- FALSE
 
          # Grafik verilerini oturuma kaydet
          if (is.list(result$chart_store) && length(result$chart_store) > 0) {
            if (is.null(session$userData$chart_store) || !is.list(session$userData$chart_store)) {
              session$userData$chart_store <- list()
            }
            session$userData$chart_store <- utils::modifyList(
              session$userData$chart_store,
              result$chart_store
            )
          }
 
          # ChartLab yedek mekanizması: Model metin döndürdüyse zorla en az 1 grafik ekle
          # Yalnızca MCP Excel modunda ve kullanıcı grafik istediğinde çalıştır
          if (identical(current_settings$tool_family, "mcp_excel")) {
            # Yanıtta zaten chartlab bloğu var mı kontrol et
            has_chart_block <- is.character(result$content) && length(result$content) > 0 &&
                               grepl("```chartlab", result$content, fixed = TRUE)
 
            # Kullanıcı isteğinde grafik niyeti var mı kontrol et
            wants_chart <- is.character(user_prompt_msg$content) && length(user_prompt_msg$content) > 0 &&
                           grepl("(?i)\\b(grafik|grafikleri|grafiğini|görselleştir|gorsellestir|görselleştirme|gorsellestirme|plot|chart|chartlab|figure|graph|viz|visualize|visualise|çiz|çizelge|histogram|bar|çubuk|line|çizgi|trend|dağılım|scatter|pie|pasta|donut|pareto|area|spline|boxplot)\\b",
                                 user_prompt_msg$content[1], perl = TRUE)
 
            if (!has_chart_block && wants_chart) {
              # İlk dosya yolunu seç
              fp <- NULL
              if (is.list(current_settings$file_paths) && length(current_settings$file_paths) > 0) {
                fp <- as.character(current_settings$file_paths[[1]])
              }
 
              # prepare_chart_data ile otomatik grafik üret ve yanıta ekle
              if (!is.null(fp) && nzchar(fp) && path_exists_relaxed(fp) &&
                      exists("helpers_mcp_tools", inherits = TRUE) &&
                      is.function(helpers_mcp_tools$prepare_chart_data)) {
 
                  detected_type <- if (exists("detect_chart_type_from_text", mode = "function")) {
                    detect_chart_type_from_text(user_prompt_msg$content[1])
                  } else {
                    "auto"
                  }
 
                  fb <- try(helpers_mcp_tools$prepare_chart_data(
                    file_name  = fp,
                    chart_type = detected_type,
                    limit      = 4000,
                    session    = session
                  ), silent = TRUE)
 
                  if (!inherits(fb, "try-error") && is.list(fb) && isTRUE(fb$ok) && !is.null(fb$chart)) {
                    # Referans kimliği oluştur ve store'a kaydet
                    ref_id <- paste0("cl_", format(Sys.time(), "%Y%m%d%H%M%OS3"), "_",
                                     sprintf("%04d", sample(0:9999, 1)))
                    if (is.null(session$userData$chart_store) || !is.list(session$userData$chart_store)) {
                      session$userData$chart_store <- list()
                    }
                    session$userData$chart_store[[ref_id]] <- fb$chart
 
                    # Veriyle birlikte inline chartlab bloğunu göm
                    inline <- fb$chart
                    inline$ref <- ref_id
                    block <- paste0(
                      "\n\n```chartlab\n",
                      jsonlite::toJSON(inline, auto_unbox = TRUE, null = "null", digits = 12),
                      "\n```"
                    )
                    result$content <- paste0(
                      if (is.character(result$content)) result$content[1] else "",
                      block
                    )
                  }
              }
            }
          }
 
          # Takip soruları oluştur (helpers_followup_questions.R)
          followup_questions <- build_followup_suggestions(
            last_user_text,
            result$content,
            settings_data,
            session,
            api_config,
            followup_tools,
            fallback_followup_tool
          )
 
          # AI mesajını ekle
          tryCatch({
            ai_msg <- add_message_fn(result$content, "ai", followups = followup_questions)
          }, error = function(e) {
            cat("[AI_RESP][ADD_MESSAGE_ERROR] ", conditionMessage(e), "\n", sep="")
            cat("[AI_RESP][ADD_MESSAGE_ERROR] dput(content)= "); dput(result$content); cat("\n")
            showToast(session, "Render hatası: içerik boş/uygunsuz. Günlüğe yazıldı.", "error")
            # Sohbet akışını bozmamak için placeholder mesaj ekle
            ai_msg <- add_message_fn("⚠️ Model boş bir yanıt döndürdü (loglandı).", "ai")
          })
 
          # TTS'i tetikle (eğer mesaj eklendiyse ve durdurulmadıysa)
          if (!is.null(ai_msg) && !isTRUE(stop_generation())) {
            trigger_tts_fn(ai_msg$id, result$content)
          }
 
          # Kullanım logunu kaydet
          tryCatch({
            log_ai_usage(
              chat_id_val,
              user_prompt_msg$db_id,
              current_user_id,
              model_selected,
              result$duration,
              TRUE
            )
          }, error = function(e) {
            print(paste("Logging error:", e$message))
          })

          # NOT: reset_chat_state_fn() burada kaldırıldı, finally bloğunda çağrılacak

        } else {
          # Hata durumunu takip et
          perf_tracker$track_error()
 
          # Yazma animasyonunu kaldır
          shiny::removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
          values$typing <- FALSE
 
          # Başarısızlık logunu kaydet
          tryCatch({
            log_ai_usage(
              chat_id_val,
              user_prompt_msg$db_id,
              current_user_id,
              model_selected,
              result$duration,
              FALSE
            )
          }, error = function(e) {
            print(paste("Logging error:", e$message))
          })
 
          # Hata mesajını göster
          showToast(session, result$error, "error")
          reset_chat_state_fn()
        }
      },
      onRejected = function(err) {
        # Promise reddedildiğinde hata işleme
        perf_tracker$track_error()
        shiny::removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
        values$typing <- FALSE

        # Kullanıcı dostu mesaj göster
        msg <- as.character(conditionMessage(err))
        msg <- sub("^[A-Z_]+:\\s*", "", msg)
        if (!nzchar(msg)) msg <- "Beklenmeyen bir hata oluştu."
        showToast(session, msg, "error")

        # NOT: reset_chat_state_fn() burada kaldırıldı, finally bloğunda çağrılacak
        invisible(NULL)
      }
    )
 
    # Promise tamamlandığında her zaman temizlik yap
    promises::finally(p2, onFinally = function() {
      reset_chat_state_fn()
    })
 
    return(p2)
  }
 
  # Fonksiyonları döndür
  list(
    generate_non_streaming_stoppable = generate_non_streaming_stoppable
  )
}