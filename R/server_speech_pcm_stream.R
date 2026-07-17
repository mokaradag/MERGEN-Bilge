# R/server_speech_pcm_stream.R
# Gerçek akış PCM köprüsü (chunked_pcm modu). Worker, VoxCPM2 yanıt baytlarını
# geldikçe oturuma özel bir akış dosyasına yazar; ana süreç dosyayı büyüdükçe
# okuyup base64 parçalar hâlinde istemcideki Web Audio kuyruğuna gönderir.
# Böylece tam sentez bitmeden duyulabilir ses başlar. Tamamlanma; altyazı veya
# tahmini süreyle değil, akış sonu + istemci kuyruğunun boşalmasıyla belirlenir.

#' Akış kimliği üret (oturum içinde benzersiz, tekdüze artan).
.speech_pcm_next_stream_id <- function(session) {
  state <- mergen_speech_state(session)
  counter <- get0("pcm_counter", envir = state, ifnotfound = 0L)
  counter <- counter + 1L
  assign("pcm_counter", counter, envir = state)
  sprintf("pcm_%s_%d", substr(session$token, 1, 8), counter)
}

#' Aktif PCM akış kayıtlarını tutan oturum deposu.
.speech_pcm_registry <- function(session) {
  state <- mergen_speech_state(session)
  reg <- get0("pcm_registry", envir = state, ifnotfound = NULL)
  if (is.null(reg)) {
    reg <- new.env(parent = emptyenv())
    assign("pcm_registry", reg, envir = state)
  }
  reg
}

#' Aktif akışı iptal olarak işaretle (istemci durdurdu / oturum kapandı).
mergen_speech_pcm_stream_cancel <- function(session, stream_id) {
  reg <- .speech_pcm_registry(session)
  rec <- get0(as.character(stream_id), envir = reg, ifnotfound = NULL)
  if (!is.null(rec)) rec$cancelled <- TRUE
  invisible(!is.null(rec))
}

#' Yanıt seslendirmesini gerçek PCM akışıyla başlat.
#'
#' @param session Shiny oturumu.
#' @param persona_id Kanonik/eski persona kimliği (fail-closed çözülür).
#' @param text Seslendirilecek tam metin.
#' @param message_id İlgili sohbet mesajı kimliği (istemci görünürlüğü için).
#' @return TRUE akış başlatıldıysa; FALSE (çağıran tamponlu hatta düşebilir).
mergen_speech_pcm_stream_start <- function(session, persona_id, text,
                                           message_id = NULL) {
  if (!identical(mergen_voxcpm2_streaming_mode(), "chunked_pcm")) return(FALSE)

  text <- tryCatch(as.character(text)[1], error = function(e) "")
  if (is.na(text) || !nzchar(trimws(text))) return(FALSE)

  reference <- mergen_speech_reference_payload(persona_id)
  if (!isTRUE(reference$ok)) {
    cat(sprintf("[SPEECH] PCM akışı reddedildi (fail-closed): %s\n", reference$reason))
    return(FALSE)
  }

  profile <- reference$profile
  body <- mergen_voxcpm2_request_body(
    profile = profile, text = text, reference = reference,
    response_format = "pcm", stream = TRUE
  )

  cfg <- get0("tts_config", ifnotfound = list())
  endpoint <- mergen_voxcpm2_endpoint_url(cfg$base_url %||% NULL)
  api_key <- .speech_resolve_tts_api_key(session)
  timeout_val <- suppressWarnings(as.numeric(cfg$timeout_seconds %||% 120))
  if (is.na(timeout_val) || timeout_val <= 0) timeout_val <- 120
  verify_ssl <- isTRUE(cfg$verify_ssl %||% TRUE)

  stream_id <- .speech_pcm_next_stream_id(session)
  out_path <- file.path(tempdir(), sprintf("mergen_speech_%s.pcm", stream_id))

  rec <- new.env(parent = emptyenv())
  rec$cancelled <- FALSE
  rec$worker_done <- FALSE
  rec$worker_ok <- FALSE
  rec$sent_bytes <- 0
  rec$seq <- 0L
  reg <- .speech_pcm_registry(session)
  assign(stream_id, rec, envir = reg)

  session$sendCustomMessage("speechPcmStreamStart", list(
    streamId = stream_id,
    messageId = message_id,
    sampleRate = profile$expected_sample_rate,
    channels = profile$expected_channels,
    bitsPerSample = profile$expected_bits_per_sample,
    text = text
  ))

  .speech_perf_log("response_synth_start", sprintf(
    "persona=%s stream=%s chars=%d", reference$persona_id, stream_id, nchar(text)
  ))

  tracked_future_promise(
    task_fn = function() {
      mergen_voxcpm2_stream_to_file(
        body = body, out_path = out_path, endpoint_url = endpoint,
        api_key = api_key, timeout_seconds = timeout_val,
        verify_ssl = verify_ssl
      )
    },
    task_type = "tts",
    session_token = session$token,
    meta = list(purpose = "voxcpm2_pcm_stream")
  ) %...>% (function(res) {
    rec$worker_done <- TRUE
    rec$worker_ok <- isTRUE(res$success)
    if (!rec$worker_ok) {
      cat(sprintf("[SPEECH] PCM akış worker hatası: %s\n",
                  mergen_voxcpm2_redact(res$error %||% "bilinmiyor")))
    }
  }) %...!% (function(e) {
    rec$worker_done <- TRUE
    rec$worker_ok <- FALSE
    cat(sprintf("[SPEECH] PCM akış worker istisnası: %s\n",
                mergen_voxcpm2_redact(conditionMessage(e))))
  })

  finish <- function(status) {
    if (exists(stream_id, envir = reg, inherits = FALSE)) {
      rm(list = stream_id, envir = reg)
    }
    unlink(out_path)
    session$sendCustomMessage("speechPcmStreamEnd", list(
      streamId = stream_id,
      status = status,
      totalChunks = rec$seq
    ))
    if (identical(status, "completed")) {
      .speech_perf_log("response_stream_sent", sprintf("stream=%s", stream_id))
    }
  }

  pump <- function() {
    if (isTRUE(rec$cancelled)) { finish("cancelled"); return(invisible(NULL)) }

    size <- suppressWarnings(file.info(out_path)$size)
    if (is.na(size)) size <- 0

    if (size > rec$sent_bytes) {
      con <- file(out_path, "rb")
      seek(con, where = rec$sent_bytes)
      new_bytes <- readBin(con, "raw", n = size - rec$sent_bytes)
      close(con)

      if (length(new_bytes) > 0) {
        rec$seq <- rec$seq + 1L
        first_playable <- rec$sent_bytes == 0
        rec$sent_bytes <- rec$sent_bytes + length(new_bytes)
        session$sendCustomMessage("speechPcmStreamChunk", list(
          streamId = stream_id,
          seq = rec$seq,
          b64 = base64enc::base64encode(new_bytes)
        ))
        if (first_playable) {
          .speech_perf_log("response_first_audio_chunk", sprintf("stream=%s", stream_id))
        }
      }
    }

    if (isTRUE(rec$worker_done) && rec$sent_bytes >= size) {
      finish(if (isTRUE(rec$worker_ok)) "completed" else "error")
      return(invisible(NULL))
    }

    later::later(pump, delay = 0.12)
    invisible(NULL)
  }

  later::later(pump, delay = 0.12)
  TRUE
}

#' PCM akış durdurma/bitiş girişlerini bağla (oturum başına bir kez).
speechPcmStreamObserversInit <- function(input, session) {
  shiny::observeEvent(input$speech_pcm_stopped, {
    payload <- input$speech_pcm_stopped
    stream_id <- if (is.list(payload)) payload$streamId else payload
    if (!is.null(stream_id) && nzchar(as.character(stream_id))) {
      mergen_speech_pcm_stream_cancel(session, as.character(stream_id))
    }
  }, ignoreInit = TRUE)

  shiny::observeEvent(input$speech_pcm_drained, {
    payload <- input$speech_pcm_drained
    stream_id <- if (is.list(payload)) payload$streamId %||% "" else as.character(payload)
    .speech_perf_log("response_stream_drained", sprintf("stream=%s", stream_id))
  }, ignoreInit = TRUE)

  invisible(NULL)
}
