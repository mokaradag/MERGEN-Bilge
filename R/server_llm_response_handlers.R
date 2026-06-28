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
    current_user_id = NULL,
    request_id = NULL
  ) {

    # send_message tarafından oluşturulan request_id'yi koru.
    # Düşünce Akışı paneli bu request_id ile başlatıldığı için,
    # non-streaming/MCP tarafı yeni bir request_id üretmemeli.
    req_id <- as.character(request_id %||% "")[1]

    if (is.na(req_id) || !nzchar(req_id)) {
      req_id <- paste0("req_", format(Sys.time(), "%Y%m%d%H%M%OS3"), "_", sample(1000:9999, 1))
    }

    active_request_id(req_id)
	
    mcp_reasoning_stream_file <- NULL
    mcp_reasoning_stream_observer <- NULL
    mcp_reasoning_lines_read <- 0L

    drain_mcp_reasoning_stream <- function() {
      if (is.null(mcp_reasoning_stream_file) ||
          !nzchar(mcp_reasoning_stream_file) ||
          !file.exists(mcp_reasoning_stream_file)) {
        return(invisible(NULL))
      }

      satirlar <- tryCatch(
        suppressWarnings(readLines(mcp_reasoning_stream_file, warn = FALSE, encoding = "UTF-8")),
        error = function(e) {
          tryCatch(
            suppressWarnings(readLines(mcp_reasoning_stream_file, warn = FALSE)),
            error = function(e2) character(0)
          )
        }
      )

      if (length(satirlar) <= mcp_reasoning_lines_read) {
        return(invisible(NULL))
      }

      yeni_satirlar <- satirlar[seq.int(mcp_reasoning_lines_read + 1L, length(satirlar))]
      mcp_reasoning_lines_read <<- length(satirlar)

      reasoning_batch <- character(0)

      for (satir in yeni_satirlar) {
        payload <- tryCatch(
          jsonlite::fromJSON(satir, simplifyVector = TRUE),
          error = function(e) NULL
        )

        if (is.null(payload)) next

        payload_type <- as.character(payload$type %||% "")

        if (identical(payload_type, "stream_debug")) {
          debug_text <- decode_stream_delta_payload(payload)
          if (nzchar(debug_text)) log_info(debug_text)
          next
        }

        if (identical(payload_type, "reasoning_delta")) {
          reasoning_text <- decode_stream_delta_payload(payload)
          if (nzchar(reasoning_text)) {
            reasoning_batch <- c(reasoning_batch, reasoning_text)
          }
        }
      }

      if (length(reasoning_batch) > 0) {
        session$sendCustomMessage("streamingReasoningDelta", list(
          delta = paste0(reasoning_batch, collapse = ""),
          started = TRUE,
          requestId = req_id
        ))
      }

      invisible(NULL)
    }

    if (isTRUE(current_settings$enable_mcp_reasoning_stream)) {
      mcp_reasoning_stream_file <- tempfile(
        pattern = paste0("mcp_reasoning_", req_id, "_"),
        fileext = ".jsonl"
      )

      file.create(mcp_reasoning_stream_file)

      current_settings$mcp_reasoning_stream_file <- mcp_reasoning_stream_file
      current_settings$mcp_reasoning_request_id <- req_id

      mcp_reasoning_stream_observer <- shiny::observe({
        shiny::invalidateLater(80, session)
        drain_mcp_reasoning_stream()
      })
    }
 
    # Kritik yol dostu: varsayılan yalnızca hafif sayım/boyut özeti; tam istem/ayar
    # dökümü yalnızca açık tanılama bayrağıyla (MERGEN_LLM_REQUEST_DEBUG/MERGEN_DEBUG).
    mergen_log_llm_request_debug("LLM_REQUEST_NONSTREAM", model_selected, chat_history, current_settings)
 
    # AI işlemcisini çağır
    p <- ai_processor$call_llm_non_streaming(chat_history, current_settings, model_selected)
 
    # Promise zincirini oluştur ve sonucu işle
    p2 <- promises::then(
      p,
      onFulfilled = function(result) {
        # Bayatlık kontrolü: bu istek artık güncel değilse (durduruldu ya da
        # daha yeni bir istek başladı) paylaşılan UI/typing durumunu EZME.
        # Daha yeni isteğin yazma sarmalayıcısını ve gönderme durumunu bayat
        # geri çağrı bozmamalıdır; nihai temizlik finally bloğunda yapılır.
        if (!mergen_is_current_request(active_request_id, req_id, stop_generation)) {
          perf_tracker$track_error()
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
 
          # Takip (followup) önerileri AI yanıtının render'ından SONRA, bloklamayan
          # bir later() döngüsünde üretilir (aşağıya bakınız). build_followup_suggestions()
          # AI üreticisinde senkron bir LLM çağrısı (call_local_llm) yapabilir; bu
          # çağrı eskiden add_message_fn'den ÖNCE çalıştığı için akıcı-olmayan/TTS/MCP
          # yanıtlarında TÜM cevabın görünmesini geciktiriyordu.

          # Worker tarafında toplanan akıl yürütme (reasoning) metnini çıkar;
          # MB_Messages.ReasoningContent sütununa düşen veri bu alandır.
          reasoning_for_db <- tryCatch({
            raw_reason <- result$reasoning_content
            if (is.null(raw_reason)) {
              NULL
            } else {
              txt <- as.character(raw_reason)[1]
              if (is.na(txt) || !nzchar(txt)) NULL else txt
            }
          }, error = function(e) NULL)

          # MCP canlı Düşünce Akışı aktifken reasoning_content'i ilk render'a verme.
          # Aksi halde aynı mesaj içinde hem canlı panel hem de arşiv <details>
          # bloğu oluşur ve Düşünce Akışı iki kez görünür.
          reasoning_for_render <- if (isTRUE(current_settings$enable_mcp_reasoning_stream)) {
            NULL
          } else {
            reasoning_for_db
          }

          ai_msg <- NULL

          # AI mesajını ekle
          tryCatch({
            ai_msg <- add_message_fn(
              result$content,
              "ai",
              followups = NULL,
              reasoning_content = reasoning_for_render
            )
          }, error = function(e) {
            cat("[AI_RESP][ADD_MESSAGE_ERROR] ", conditionMessage(e), "\n", sep="")
            cat("[AI_RESP][ADD_MESSAGE_ERROR] dput(content)= "); dput(result$content); cat("\n")
            showToast(session, "Render hatası: içerik boş/uygunsuz. Günlüğe yazıldı.", "error")
            # Sohbet akışını bozmamak için placeholder mesaj ekle
            ai_msg <- add_message_fn("\U000026A0\U0000FE0F Model boş bir yanıt döndürdü (loglandı).", "ai")
          })

          if (isTRUE(current_settings$enable_mcp_reasoning_stream) &&
              !is.null(ai_msg) &&
              !is.null(ai_msg$id)) {
            try(drain_mcp_reasoning_stream(), silent = TRUE)

            session$sendCustomMessage("premiumReasoningStreamStart", list(
              id = ai_msg$id,
              requestId = req_id
            ))

            # Görselde ikinci arşiv bloğunu üretmeden DB'de reasoning'i koru.
            # Böylece mevcut cevapta tek canlı panel kalır; geçmişten açıldığında
            # reasoning DB'den arşiv olarak render edilebilir.
            if (!is.null(reasoning_for_db) &&
                !is.null(ai_msg$db_id) &&
                exists("update_message_reasoning_content", mode = "function", inherits = TRUE)) {
              try(update_message_reasoning_content(ai_msg$db_id, reasoning_for_db), silent = TRUE)
            }
          }
 
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

          # Takip önerilerini yanıt render'ından SONRA, bloklamayan bir later()
          # döngüsünde üret ve push et. Böylece AI cevabı (ve TTS) hemen görünür;
          # senkron takip LLM çağrısı artık kritik yolun DIŞINDADIR. Sözleşme:
          # tarayıcı followup_container'ı talep üzerine oluşturur
          # (updateFollowupSuggestions), bu yüzden mesaj önerilerden önce eklenebilir.
          if (!is.null(ai_msg) && !is.null(ai_msg$id)) {
            followup_target_id <- ai_msg$id
            followup_ai_text <- result$content
            later::later(function() {
              followup_perf_start <- mergen_perf_now()
              followup_questions <- tryCatch(
                build_followup_suggestions(
                  last_user_text, followup_ai_text, settings_data, session,
                  api_config, followup_tools, fallback_followup_tool
                ),
                error = function(e) NULL
              )
              mergen_perf_log("nonstream.followups", start = followup_perf_start,
                              fields = list(count = length(followup_questions %||% character(0))))
              if (!is.null(followup_questions) && length(followup_questions) > 0) {
                try(
                  push_followup_update(session, followup_target_id, followup_questions, pending = FALSE),
                  silent = TRUE
                )
              }
            }, delay = 0)
          }

          # NOT: reset_chat_state_fn() burada kaldırıldı, finally bloğunda çağrılacak

        } else {
          # Hata durumunu takip et
          perf_tracker$track_error()

          # 401/403/AUTH hatasında gönderim anahtarı önbelleği geçersiz kılınır.
          mb_api_key_invalidate_send_cache_on_auth_error(session, result$error %||% "")

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

        # Bayatlık kontrolü: yeni bir istek aktifse ya da istek durdurulduysa
        # bu bayat hata, yeni isteğin UI/typing durumunu EZMEMELİ ve kullanıcıya
        # bayat hata toast'ı gösterilmemeli. Temizlik finally'de istek-kapsamlı
        # olarak yapılır.
        if (!mergen_is_current_request(active_request_id, req_id, stop_generation)) {
          return(invisible(NULL))
        }

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
      try(drain_mcp_reasoning_stream(), silent = TRUE)

      if (!is.null(mcp_reasoning_stream_observer)) {
        try(mcp_reasoning_stream_observer$destroy(), silent = TRUE)
        mcp_reasoning_stream_observer <- NULL
      }

      if (!is.null(mcp_reasoning_stream_file) && nzchar(mcp_reasoning_stream_file)) {
        try(unlink(mcp_reasoning_stream_file, force = TRUE), silent = TRUE)
      }

      # Sohbet durumunu yalnızca daha YENİ bir istek aktif DEĞİLSE sıfırla.
      # Aksi halde bayat finally, yeni isteğin gönderme/typing durumunu ve
      # yazma sarmalayıcısını bozar (stale-request yarışı koruması). İptal
      # (cancelled_) ve normal tamamlanma durumlarında sıfırlamaya izin verilir.
      current_active_id <- tryCatch(active_request_id(), error = function(e) NULL)
      current_active_id <- if (is.null(current_active_id)) "" else as.character(current_active_id)[1]
      newer_request_active <- nzchar(current_active_id) &&
        !identical(current_active_id, as.character(req_id)[1]) &&
        !startsWith(current_active_id, "cancelled_")
      if (!isTRUE(newer_request_active)) {
        reset_chat_state_fn()
      }
    })
 
    return(p2)
  }
 
  # Fonksiyonları döndür
  list(
    generate_non_streaming_stoppable = generate_non_streaming_stoppable
  )
}
