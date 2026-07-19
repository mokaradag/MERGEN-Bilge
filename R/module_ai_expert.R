# R/module_ai_expert.R
# Dosya Yolu: R/module_ai_expert.R
# Açıklama: AI Uzman (AI Expert) Shiny modülü.
#            Altyazı (subtitle) görüntüleyicisi UI bileşenini ve
#            sunucu tarafındaki durum yönetimini içerir.
#            Altyazı gösterimi TTS sesi hazır olana kadar bekler (senkronizasyon).

#' AI Uzman Altyazı UI Bileşeni
#'
#' Sayfa altında sabit konumlu altyazı şeridi oluşturur.
#' Bu şerit, AI konuşması sırasında metin görüntüler.
#'
#' @param id Modül ad alanı kimliği
#' @return Altyazı şeridi UI tanımı
aiExpertSubtitleUI <- function(id) {
  ns <- NS(id)

  # Sabit konumlu altyazı şeridi (tüm sayfalarda görünür)
  tags$div(
    id = ns("subtitle_strip"),
    class = "ai-expert-subtitle-strip ai-expert-hidden",

    # Sol: Karakter avatarı
    tags$div(
      class = "ai-expert-avatar-wrapper",
		tags$img(
		  id = ns("subtitle_avatar"),
		  class = "ai-expert-subtitle-avatar",
		  # Boş src tarayıcıda mevcut sayfa URL'sine istek atar ve gizli konsol hatası üretir.
		  src = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="
		)
    ),

    # Orta: Altyazı metin alanı
    tags$div(
      class = "ai-expert-subtitle-text-wrapper",
      tags$span(
        id = ns("subtitle_text"),
        class = "ai-expert-subtitle-text",
        ""
      )
    ),

    # Sağ: Durdurma butonu
    tags$div(
      class = "ai-expert-stop-wrapper",
      tags$button(
        id = ns("stop_ai_talk"),
        class = "ai-expert-stop-btn action-button",
        title = "AI konuşmasını durdur",
        tags$i(class = "fa-solid fa-xmark")
      )
    )
  )
}

#' AI Uzman Sunucu Modülü
#'
#' AI Uzman konuşma durumunu, zamanlamasını ve yarış durumu
#' önleme mantığını yönetir.
#'
#' @param id Modül ad alanı kimliği
#' @param settings_data Merkezi ayarlar reaktif değerleri
#' @param tts_processor TTS işleme modülü (sesli çıktı için)
#' @param tts_visualizer TTS görselleştiricisi (animasyon tetiklemek için)
#' @return AI Uzman kontrol fonksiyonlarını içeren liste
aiExpertServer <- function(id, settings_data, tts_processor, tts_visualizer) {
  moduleServer(id, function(input, output, session) {

    ns <- session$ns

    # --- Reaktif durum değişkenleri ---
    is_speaking     <- reactiveVal(FALSE)    # AI şimdi konuşuyor mu
    is_cooldown     <- reactiveVal(FALSE)    # Bekleme süresi aktif mi
    last_speak_time <- reactiveVal(NULL)     # Son konuşma zamanı
    current_page    <- reactiveVal("chat")   # Aktif sayfa
    user_is_active  <- reactiveVal(FALSE)    # Kullanıcı mesaj gönderiyor mu
    tts_vocalizing  <- reactiveVal(FALSE)    # TTS yanıt seslendirmesi aktif mi
    prewarmed_tts   <- reactiveVal(NULL)     # Ön ısıtılmış ilk TTS parçası
    prewarming_tts  <- reactiveVal(NULL)     # Hazırlanmakta olan ilk TTS parçası

    PREWARM_TTL_SECS <- 90                   # Ön ısıtma önbelleği ömrü (sn)

    # Bekleme süreleri (saniye) - daha hızlı ve akıcı deneyim için kısa tutuldu
    COOLDOWN_AFTER_GREETING  <- 10  # Karşılama sonrası bekleme
    COOLDOWN_AFTER_PAGE      <- 8   # Sayfa rehberliği sonrası bekleme
    COOLDOWN_AFTER_IDLE      <- 12  # Boşta konuşma sonrası bekleme
    COOLDOWN_AFTER_STOP      <- 5   # Manuel durdurma sonrası bekleme

    # Aktif bekleme süresi (dinamik olarak değişir)
    active_cooldown_seconds <- reactiveVal(15)

    # Doğal konuşma bitişi kancası (tek slot; sahibi handlers katmanıdır)
    speech_ended_cb <- new.env(parent = emptyenv())
    speech_ended_cb$fn <- NULL
    manual_stop_tokens <- new.env(parent = emptyenv())

    # Yasaklı sayfalar (bu sayfalarda otomatik AI konuşması yapılmaz).
    # Tek yetkili politika kaynağı: R/config_speech_assets.R.
    MUTED_PAGES <- mergen_speech_idle_muted_pages()

    # --- Yardımcı: AI Uzman konuşması mümkün mü? ---
    # Promise/later geri çağrılarından da çağrılır; okumalar isolate içindedir.
    can_speak <- function() isolate({
        # 1. Özellik açık mı?
        if (!isTRUE(settings_data$enable_ai_expert)) return(FALSE)

        # 2. Bütünleşik mod mu?
        if (!identical(settings_data$experience_mode, "kesif")) return(FALSE)

        # 3. Yasaklı sayfa mı?
        page <- current_page()
        if (page %in% MUTED_PAGES) return(FALSE)

        # 4. Zaten konuşuyor mu?
        if (isTRUE(is_speaking())) return(FALSE)

        # 5. TTS yanıt seslendirmesi aktif mi? (yarış durumu önleme)
        if (isTRUE(tts_vocalizing())) return(FALSE)

        # 6. Bekleme süresinde mi?
        if (isTRUE(is_cooldown())) return(FALSE)

        # 7. Son konuşmadan yeterli süre geçti mi?
        lst <- last_speak_time(); cooldown_secs <- active_cooldown_seconds()
        if (!is.null(lst)) {
          elapsed <- as.numeric(difftime(Sys.time(), lst, units = "secs"))
          if (elapsed < cooldown_secs) return(FALSE)
        }

        # 8. Kullanıcı aktif mi? (yazıyorsa veya istek gönderdiyse konuşma)
        if (isTRUE(user_is_active())) return(FALSE)

        TRUE
    })

    # --- Bekleme süresini başlat (senaryo bazlı) ---
    start_cooldown <- function(cooldown_secs) {
      active_cooldown_seconds(cooldown_secs)
      is_cooldown(TRUE)
      shinyjs::delay(cooldown_secs * 1000, {
        is_cooldown(FALSE)
      })
    }

    # --- AI Uzman TTS metnini kısa parçalara böl ---
    # split_text_for_ai_expert_tts() saf bir metin yardımcısıdır ve
    # R/helpers_ai_expert_chunking.R içinde tutulur. Burada yeniden tanım
    # yapılmaz; modül yalnızca paylaşılan helper'ı çağırır.
	
    get_prewarmed_tts <- function(text, char_id, voice_sel) {
      cache <- isolate(prewarmed_tts())
      if (is.null(cache)) return(NULL)

      age_secs <- tryCatch(
        as.numeric(difftime(Sys.time(), cache$created_at, units = "secs")),
        error = function(e) Inf
      )

      if (!is.finite(age_secs) || age_secs > PREWARM_TTL_SECS) {
        prewarmed_tts(NULL)
        return(NULL)
      }

      if (!identical(cache$text, text)) return(NULL)
      if (!identical(cache$char_id, char_id)) return(NULL)
      if (!identical(cache$voice_sel, voice_sel)) return(NULL)

      cache
    }

    get_inflight_prewarm_tts <- function(text, char_id, voice_sel) {
      inflight <- isolate(prewarming_tts())
      if (is.null(inflight)) return(NULL)

      if (!identical(inflight$text, text)) return(NULL)
      if (!identical(inflight$char_id, char_id)) return(NULL)
      if (!identical(inflight$voice_sel, voice_sel)) return(NULL)

      inflight
    }

    prewarm_speaking <- function(text, selected_char_id = NULL) {
      text <- trimws(as.character(text %||% ""))
      if (!nzchar(text)) return(invisible(FALSE))

      # Telaffuz/yazım düzeltmesi: start_speaking ile aynı metnin önbelleğe
      # alındığından emin olmak için burada da uygulanır. Aksi halde cache
      # anahtarı farklı olur ve prewarm'in TTS önbelleği bulunmaz.
      if (exists("sanitize_ai_expert_pronunciation", mode = "function", inherits = TRUE)) {
        text <- tryCatch(sanitize_ai_expert_pronunciation(text), error = function(e) text)
      }

      tts_available <- FALSE
      tryCatch({
        tts_available <- isTRUE(tts_processor$tts_available())
      }, error = function(e) {})

      if (!tts_available) return(invisible(FALSE))

      char_id <- normalize_character_id(selected_char_id %||% isolate(settings_data$selected_character))

      # Kilitli referans modunda ses kimliği persona kimliğinin kendisidir;
      # sentez katmanı referansı fail-closed çözer.
      voice_sel <- char_id

      cached <- get_prewarmed_tts(text, char_id, voice_sel)
      if (!is.null(cached)) return(invisible(TRUE))

      inflight <- get_inflight_prewarm_tts(text, char_id, voice_sel)
      if (!is.null(inflight)) return(invisible(TRUE))

      chunks <- split_text_for_ai_expert_tts(text, max_chunk_chars = 220, min_chunk_chars = 70)
      if (length(chunks) == 0) chunks <- list(text)

      cat(sprintf(
        "[AI_EXPERT] İlk TTS parçası ön ısıtılıyor... (karakter: %s)\n",
        char_id
      ))

      tts_promise <- tts_processor$synthesize_speech(chunks[[1]], persona_id = char_id)

      prewarming_tts(list(
        text = text,
        char_id = char_id,
        voice_sel = voice_sel,
        first_chunk_text = chunks[[1]],
        chunks = chunks,
        promise = tts_promise,
        created_at = Sys.time()
      ))

      tts_promise %...>%
        (function(res) {
          prewarming_tts(NULL)

          if (isTRUE(res$success) && nzchar(res$audio_src)) {
            prewarmed_tts(list(
              text = text,
              char_id = char_id,
              voice_sel = voice_sel,
              first_chunk_text = chunks[[1]],
              chunks = chunks,
              audio_src = res$audio_src,
              duration = res$duration,
              created_at = Sys.time()
            ))

            cat(sprintf(
              "[AI_EXPERT] Ön ısıtılmış ilk TTS parçası hazır (Süre: %.2fs).\n",
              res$duration
            ))
          }
        }) %...!%
        (function(e) {
          prewarming_tts(NULL)
          cat(sprintf("[AI_EXPERT] Ön ısıtma TTS hatası: %s\n", conditionMessage(e)))
        })

      invisible(TRUE)
    }
	
    # --- Konuşmayı başlat ---
    # ÖNEMLİ: Altyazı ve ses senkronizasyonu
    # TTS hazır olana kadar altyazı başlatılmaz, böylece senkronize olurlar.
    # `kind` konuşma türüdür (welcome/page_guidance/idle) ve tek yetkili
    # öncelik matrisinden geçer; `static_plan` verilirse sentez atlanır ve
    # önceden üretilmiş WAV dizisi tek konuşma olarak oynatılır.
	start_speaking <- function(text, cooldown_secs = COOLDOWN_AFTER_PAGE,
	                           kind = "idle", static_plan = NULL) {
	  if (is.null(text) || !nzchar(text)) return(invisible(FALSE))

	  if (isTRUE(isolate(is_speaking()))) {
	    gate <- mergen_speech_priority_decision(mergen_speech_active_kind(session), kind)
	    if (!isTRUE(gate$allow)) return(invisible(FALSE))
	    stop_speaking(0)
	  }

	  decision <- mergen_speech_begin(session, kind)
	  if (!isTRUE(decision$allow)) return(invisible(FALSE))
	  chunk_dispatch <- mergen_speech_chunk_dispatcher(session, decision$token, is_speaking)
	  # Telaffuz/yazım düzeltmesini güvenlik ağı olarak burada da uygula.
	  # call_ai_expert_llm zaten bu düzeltmeyi yapar; ancak doğrudan
	  # start_speaking çağıran yollar olursa "Bilge Yola" -> "Bilge Yolaç"
	  # düzeltmesi yine de yapılır.
	  if (exists("sanitize_ai_expert_pronunciation", mode = "function", inherits = TRUE)) {
	    text <- tryCatch(sanitize_ai_expert_pronunciation(text), error = function(e) text)
	  }

	  is_speaking(TRUE)
	  last_speak_time(Sys.time())

	  # Persona bilgilerini al (eski kimlikler normalleştirilir)
	  char_id <- normalize_character_id(isolate(settings_data$selected_character))
	  char_info <- get_character_record(char_id)

	  avatar_src <- if (!is.null(char_info)) char_info$avatar else "characters/avatar/emre/avatar.png"
	  accent_color <- if (!is.null(char_info)) char_info$accent else "#7C4DFF"

	  # Yazı tipi boyutunu ayarlardan al
	  font_size <- isolate(settings_data$font_size) %||% "medium"

	  # --- Statik plan: önceden üretilmiş WAV dizisi (önek + karşılama /
	  # sayfa rehberliği). Sentez yok; altyazı metni ortak senaryo metnidir.
	  # Görselleştirici/müzik kısma istemcide GERÇEK oynatma anında başlar.
	  if (!is.null(static_plan) && length(static_plan$items %||% list()) > 0) {
	    items <- static_plan$items
	    tts_visualizer$trigger(duration = 0)

	    session$sendCustomMessage("aiExpertStartWithAudio", list(
	      text          = items[[1]]$text,
	      totalChunks   = length(items),
	      avatarSrc     = avatar_src,
	      accentColor   = accent_color,
	      nsPrefix      = ns(""),
	      audioSrc      = items[[1]]$audio_src,
	      audioDuration = (items[[1]]$duration_ms %||% 0) / 1000,
	      fontSize      = font_size,
	      speechToken   = decision$token
	    ))

	    if (length(items) > 1) {
	      for (item_idx in seq.int(2L, length(items))) {
	        session$sendCustomMessage("aiExpertQueueAudioChunk", list(
	          index         = item_idx - 1L,
	          text          = items[[item_idx]]$text,
	          audioSrc      = items[[item_idx]]$audio_src,
	          audioDuration = (items[[item_idx]]$duration_ms %||% 0) / 1000,
	          nsPrefix      = ns(""),
	          speechToken   = decision$token
	        ))
	      }
	    }

	    active_cooldown_seconds(cooldown_secs)
	    return(invisible(TRUE))
	  }

	  # TTS ile seslendirme kontrolü
	  tts_available <- FALSE
	  tryCatch({
		tts_available <- isTRUE(tts_processor$tts_available())
	  }, error = function(e) {})

      if (tts_available) {
        # Kilitli referans modunda ses kimliği persona kimliğinin kendisidir;
        # sentez katmanı onaylı referansı fail-closed çözer.
        voice_sel <- char_id

        # İlk sesi daha hızlı başlatmak için metni kısa parçalara böl
        chunks <- split_text_for_ai_expert_tts(text, max_chunk_chars = 220, min_chunk_chars = 70)
        if (length(chunks) == 0) chunks <- list(text)

        cat(sprintf(
          "[AI_EXPERT] TTS %d parçaya bölündü (toplam: %d karakter)...\n",
          length(chunks), nchar(text)
        ))

        # Kalan parçalar: sınırlı eşzamanlılık + sıralı teslim + boşalınca
        # gerçek teslim sayısını bildirme (istemci eksik parçada asılı kalmaz).
        # Hat kurulumu R/helpers_ai_expert_chunk_pipeline.R içindedir.
        pipeline_policy <- ai_expert_chunk_pipeline_policy()

        queue_remaining_chunks <- function(all_chunks, start_index = 2L) {
          if (start_index > length(all_chunks)) {
            baslangic_kapisi$tampon_hazir()
            return(invisible(NULL))
          }
          if (!chunk_dispatch$claim_synthesis()) {
            # Kalan parça sentezi zaten başka bir çağrı tarafından üstlenildi
            # (ör. ön ısıtılan ilk parça başarısız olup synthesize_first_chunk_now()
            # yeniden dener). O hattın kendi on_buffer_settled geri çağrısı
            # tamponu zamanında açacaktır; burada erken açmak henüz
            # sonuçlanmamış tamponla oynatmayı başlatıp 1. parça sonrası
            # sessizliği geri getirir (Codex PR #636 P2 incelemesi).
            return(invisible(NULL))
          }
          ai_expert_kalan_parcalari_kuyrukla(
            all_chunks = all_chunks, baslangic = start_index,
            tts_processor = tts_processor, char_id = char_id,
            chunk_dispatch = chunk_dispatch, session = session,
            ns_prefix = ns(""), speech_token = decision$token,
            kapi = baslangic_kapisi, policy = pipeline_policy
          )
          invisible(NULL)
        }

        # YARIŞ DURUMU KORUMASI: İlk parça istemciye gönderildi mi?
        first_chunk_dispatched <- FALSE

        dispatch_audio_start <- function(first_chunk_text, all_chunks, audio_src, audio_duration) {
          if (!chunk_dispatch$is_current()) return(invisible(NULL))
          if (isTRUE(first_chunk_dispatched)) return(invisible(NULL))

          tts_visualizer$trigger(duration = 0)

          session$sendCustomMessage("aiExpertStartWithAudio", list(
            text          = first_chunk_text,
            totalChunks   = length(all_chunks),
            avatarSrc     = avatar_src,
            accentColor   = accent_color,
            nsPrefix      = ns(""),
            audioSrc      = audio_src,
            audioDuration = audio_duration,
            fontSize      = font_size,
            speechToken   = decision$token
          ))

          first_chunk_dispatched <<- TRUE
          chunk_dispatch$start()

          invisible(NULL)
        }

        dispatch_subtitle_fallback <- function() {
          if (!chunk_dispatch$is_current()) return(invisible(NULL))
          if (isTRUE(first_chunk_dispatched)) return(invisible(NULL))

          cat("[AI_EXPERT] İlk TTS parçası başarısız, sadece altyazı gösteriliyor.\n")

          session$sendCustomMessage("aiExpertStartSubtitle", list(
            text        = text,
            avatarSrc   = avatar_src,
            accentColor = accent_color,
            nsPrefix    = ns(""),
            fontSize    = font_size,
            speechToken = decision$token
          ))

          session$sendCustomMessage("aiExpertNoAudioFallback", list(
            textLength  = nchar(text),
            nsPrefix    = ns(""),
            speechToken = decision$token
          ))

          invisible(NULL)
        }

        # Başlangıç tamponu kapısı: çok parçalı yanıtta oynatma, 2. parça
        # sonuçlanana (veya süre sınırına) kadar başlamaz; tek parçada anında.
        baslangic_kapisi <- ai_expert_baslangic_kapisi(
          dispatch_fn = dispatch_audio_start,
          deadline_secs = pipeline_policy$baslangic_tampon_suresi_sn
        )

        synthesize_first_chunk_now <- function() {
          first_chunk_promise <- tts_processor$synthesize_speech(chunks[[1]], persona_id = char_id)
          queue_remaining_chunks(chunks, 2L)

          first_chunk_promise %...>%
            (function(first_res) {
              if (!chunk_dispatch$is_current()) return()

              if (isTRUE(first_res$success) && nzchar(first_res$audio_src)) {
                cat(sprintf(
                  "[AI_EXPERT] İlk TTS parçası hazır (Süre: %.2fs). Konuşma hemen başlatılıyor.\n",
                  first_res$duration
                ))

                baslangic_kapisi$ilk_hazir(list(
                  text = chunks[[1]], chunks = chunks,
                  audio_src = first_res$audio_src,
                  duration = first_res$duration
                ))
              } else {
                dispatch_subtitle_fallback()
              }
            }) %...!%
            (function(e) {
              cat(sprintf("[AI_EXPERT] TTS hatası: %s\n", conditionMessage(e)))
              if (!chunk_dispatch$is_current()) return()

              if (isTRUE(first_chunk_dispatched)) {
                cat("[AI_EXPERT] İlk parça zaten gönderilmiş; tam metin geri dönüşü atlandı.\n")
                return()
              }

              dispatch_subtitle_fallback()
            })
        }

        # Önceden hazırlanmış ilk TTS parçası varsa onu kullan
        prewarmed <- get_prewarmed_tts(text, char_id, voice_sel)
        inflight_prewarm <- get_inflight_prewarm_tts(text, char_id, voice_sel)

        if (!is.null(prewarmed) && nzchar(prewarmed$audio_src %||% "")) {
          resolved_chunks <- prewarmed$chunks %||% chunks

          cat(sprintf(
            "[AI_EXPERT] Ön ısıtılmış ilk TTS parçası kullanılıyor (Süre: %.2fs).\n",
            prewarmed$duration
          ))

          queue_remaining_chunks(resolved_chunks, 2L)

          baslangic_kapisi$ilk_hazir(list(
            text = prewarmed$first_chunk_text %||% resolved_chunks[[1]],
            chunks = resolved_chunks,
            audio_src = prewarmed$audio_src,
            duration = prewarmed$duration
          ))

          prewarmed_tts(NULL)

        } else if (!is.null(inflight_prewarm) && !is.null(inflight_prewarm$promise)) {
          cat("[AI_EXPERT] Ön ısıtılan ilk TTS parçası hâlâ hazırlanıyor, hazır olur olmaz kullanılacak.\n")
          queue_remaining_chunks(inflight_prewarm$chunks %||% chunks, 2L)

          inflight_prewarm$promise %...>%
            (function(res) {
              if (!chunk_dispatch$is_current() || isTRUE(first_chunk_dispatched)) return()

              ready <- get_prewarmed_tts(text, char_id, voice_sel)

              if (is.null(ready) && isTRUE(res$success) && nzchar(res$audio_src)) {
                ready <- list(
                  first_chunk_text = inflight_prewarm$first_chunk_text %||% chunks[[1]],
                  chunks = inflight_prewarm$chunks %||% chunks,
                  audio_src = res$audio_src,
                  duration = res$duration
                )
              }

              if (!is.null(ready) && nzchar(ready$audio_src %||% "")) {
                resolved_chunks <- ready$chunks %||% chunks

                cat(sprintf(
                  "[AI_EXPERT] Ön ısıtılan ilk TTS parçası yetişti (Süre: %.2fs).\n",
                  ready$duration
                ))

                baslangic_kapisi$ilk_hazir(list(
                  text = ready$first_chunk_text %||% resolved_chunks[[1]],
                  chunks = resolved_chunks,
                  audio_src = ready$audio_src,
                  duration = ready$duration
                ))

                prewarmed_tts(NULL)
              } else {
                synthesize_first_chunk_now()
              }
            }) %...!%
            (function(e) {
              cat(sprintf(
                "[AI_EXPERT] Ön ısıtılan ilk TTS parçası beklenirken hata oluştu: %s\n",
                conditionMessage(e)
              ))

              if (!chunk_dispatch$is_current() || isTRUE(first_chunk_dispatched)) return()
              synthesize_first_chunk_now()
            })

        } else {
          synthesize_first_chunk_now()
        }
      } else {
		# TTS yoksa sadece altyazı göster, süre tahminle
		# Görselleştiriciyi sessiz bile aktive et (animasyon göster)
		tts_visualizer$trigger(duration = 0)

		session$sendCustomMessage("aiExpertStartSubtitle", list(
		  text        = text,
		  avatarSrc   = avatar_src,
		  accentColor = accent_color,
		  nsPrefix    = ns(""),
		  fontSize    = font_size,
		  speechToken = decision$token
		))

		session$sendCustomMessage("aiExpertNoAudioFallback", list(
		  textLength  = nchar(text),
		  nsPrefix    = ns(""),
		  speechToken = decision$token
		))
	  }

	  # Senaryo bazlı bekleme süresini kaydet (konuşma bittikten sonra uygulanacak)
	  active_cooldown_seconds(cooldown_secs)

	  invisible(TRUE)
	}

    # --- Konuşmayı durdur ---
    stop_speaking <- function(cooldown_secs = NULL, manual = FALSE) {
      active_token <- as.integer(mergen_speech_active_token(session))
      if (isTRUE(manual) && !is.na(active_token) && active_token > 0L) {
        manual_stop_tokens[[as.character(active_token)]] <- TRUE
      }
      is_speaking(FALSE)
      mergen_speech_end(session)
      if (isTRUE(manual)) {
        ai_expert_konusma_bitti_bildir(speech_ended_cb, manual_stop = TRUE)
      }
      session$sendCustomMessage("aiExpertStopSubtitle", list(
        nsPrefix = ns("")
      ))

      # TTS görselleştiricisini durdur
      tryCatch({
        tts_visualizer$stop()
      }, error = function(e) {})

      # Bekleme süresini başlat (0 geçilirse bekleme olmaz)
      cd <- cooldown_secs %||% COOLDOWN_AFTER_STOP
      if (cd > 0) {
        start_cooldown(cd)
      }

      invisible(NULL)
    }

    # --- Durdurma butonu observer ---
    observeEvent(input$stop_ai_talk, {
      cat("[AI_EXPERT] Durdurma butonu tıklandı.\n")
      stop_speaking(COOLDOWN_AFTER_STOP, manual = TRUE)
    }, ignoreInit = TRUE)

    # --- İstemciden "konuşma bitti" sinyali ---
    # start_speaking() bir konuşmayı KESERKEN aynı R turunda stop_speaking(0)
    # çağırıp hemen yeni token kurabilir; eski konuşmanın bayat durdurma
    # yankısı sunucuya YENİ konuşma başladıktan SONRA ulaşabilir. Token
    # eşleşmezse yankı yoksayılır (token yoksa eski davranış korunur).
    observeEvent(input$ai_expert_speech_ended, {
      payload <- input$ai_expert_speech_ended
      raw_token <- if (is.list(payload)) payload$speechToken else NULL
      # Her zaman TEK skaler (NULL/uzunluk-0/uzunluk>1 -> NA_integer_).
      echoed_token <- if (is.null(raw_token)) NA_integer_ else suppressWarnings(as.integer(raw_token))[1]

      if (!is.na(echoed_token) &&
          !identical(echoed_token, as.integer(mergen_speech_active_token(session)))) {
        return(invisible(NULL))
      }

      manual_stop_echo <- !is.na(echoed_token) &&
        isTRUE(manual_stop_tokens[[as.character(echoed_token)]])
      if (isTRUE(manual_stop_echo)) {
        rm(list = as.character(echoed_token), envir = manual_stop_tokens)
        return(invisible(NULL))
      }

      if (isTRUE(is_speaking())) {
        is_speaking(FALSE)
        mergen_speech_end(session, token = if (is.na(echoed_token)) NULL else echoed_token)
        # Bekleme süresini başlat (aktif senaryo bekleme süresiyle)
        cd <- isolate(active_cooldown_seconds()) %||% COOLDOWN_AFTER_PAGE
        start_cooldown(cd)
        # Doğal bitiş kancası: kuyruğa alınmış sayfa rehberliği gibi bekleyen
        # işler konuşma bittiği anda deterministik olarak devam edebilsin.
        # Manuel durdurma yankıları doğal bitiş değildir; bekleyen rehberliği
        # başlatmadan düşürürüz.
        if (!isTRUE(manual_stop_echo)) {
          ai_expert_konusma_bitti_bildir(speech_ended_cb, manual_stop = FALSE)
        }
      }
    }, ignoreInit = TRUE)

    # --- TTS Görselleştiricisi görünürlüğü ---
    # enable_ai_expert veya enable_tts_audio açıkken görselleştiriciyi göster
    observe({
      ai_expert_on <- isTRUE(settings_data$enable_ai_expert) &&
                       identical(settings_data$experience_mode, "kesif")
      tts_on <- isTRUE(settings_data$enable_tts_audio)
      should_show <- ai_expert_on || tts_on

      # İstemciye görselleştiricinin görünürlüğünü bildir
      session$sendCustomMessage("aiExpertVisualizerVisibility", list(
        visible = should_show
      ))
    })

    # --- Dış erişim için fonksiyonlar ---
    return(list(
      start_speaking     = start_speaking,
      prewarm_speaking   = prewarm_speaking,
      stop_speaking      = stop_speaking,
      is_speaking        = is_speaking,
      can_speak          = can_speak,
      set_page           = function(page) {
        current_page(page)
        # JS tarafına sayfa bilgisini gönder (altyazı konumu ayarı için)
        session$sendCustomMessage("aiExpertSetPage", list(page = page))
      },
      set_user_active   = function(active) user_is_active(active),
      set_tts_vocalizing = function(active) tts_vocalizing(active),
      set_speech_ended_callback = function(cb) speech_ended_cb$fn <- cb,
      # Bekleme süreleri dış erişim için
      COOLDOWN_GREETING = COOLDOWN_AFTER_GREETING,
      COOLDOWN_PAGE     = COOLDOWN_AFTER_PAGE,
      COOLDOWN_IDLE     = COOLDOWN_AFTER_IDLE,
      COOLDOWN_STOP     = COOLDOWN_AFTER_STOP
    ))
  })
}
