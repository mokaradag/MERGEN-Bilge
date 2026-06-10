# ==============================================================================
# Dosya Yolu: R/helpers_streaming_poll_lifecycle.R
# Açıklama: True streaming yoklama (poll) döngüsü için saf karar yardımcıları.
#           Akış JSONL satırlarının delta / akıl yürütme / debug olarak
#           sınıflandırılması, yoklama aralığı ve ertelenen kalıcılaştırma
#           gecikmesi kararları ile worker dönüşündeki akıl yürütme (reasoning)
#           geri kazanım planı burada yaşar.
#           Shiny, DB, dosya veya LLM çağrısı içermez.
# ==============================================================================

# Yoklama aralığını stream profilinden güvenle çözer. Eksik, geçersiz veya
# minimumun altındaki değerler varsayılana döner; minimum ve üzeri değerler
# olduğu gibi korunur (hızlı profiller 15 ms kullanır).
mergen_stream_poll_interval_ms <- function(stream_profile = list(),
                                           default_ms = 50L,
                                           min_ms = 15L) {
  candidate <- tryCatch(
    suppressWarnings(as.integer(stream_profile$poll_interval_ms %||% default_ms))[1],
    error = function(e) NA_integer_
  )

  if (length(candidate) == 0L || is.na(candidate) || candidate < as.integer(min_ms)) {
    return(as.integer(default_ms))
  }

  candidate
}

# Ertelenen sohbet kalıcılaştırma gecikmesini profil etiketinden çözer. Hızlı
# profiller, ilk delta sonrası UI'ı bloklamamak için kısa bir gecikme kullanır;
# diğer profiller gecikmesiz kalıcılaştırır.
mergen_stream_persist_delay <- function(stream_profile_label = "",
                                        fast_labels = c("plain_fast", "coding_fast"),
                                        fast_delay = 0.30,
                                        default_delay = 0) {
  label <- tryCatch(
    as.character(stream_profile_label %||% "")[1],
    error = function(e) ""
  )

  if (length(label) == 0L || is.na(label)) {
    label <- ""
  }

  if (label %in% fast_labels) fast_delay else default_delay
}

# Akış dosyasından okunan yeni JSONL satırlarını sınıflandırır. Her satır tek
# bir JSON yüküdür; bozuk/yarım satırlar sessizce atlanır (worker satırı
# yazarken poll yakalamış olabilir). Dönen birleşik metinler, orijinal satır
# sırası korunarak üretilir; boş çözülen parçalar sayılmaz.
#
# decode_fn verilmezse önce ortak `decode_stream_delta_payload()` (base64 +
# düz metin) aranır; izole test/debug bağlamları için yalnızca `payload$text`
# okuyan asgari bir fallback kullanılır.
mergen_stream_classify_poll_lines <- function(new_lines, decode_fn = NULL) {
  if (!is.function(decode_fn)) {
    if (exists("decode_stream_delta_payload", mode = "function")) {
      decode_fn <- get("decode_stream_delta_payload", mode = "function")
    } else {
      decode_fn <- function(payload) {
        value <- tryCatch(
          as.character(payload$text %||% "")[1],
          error = function(e) ""
        )
        if (length(value) == 0L || is.na(value)) "" else enc2utf8(value)
      }
    }
  }

  lines <- tryCatch(
    as.character(new_lines %||% character(0)),
    error = function(e) character(0)
  )

  delta_batch <- character(0)
  reasoning_batch <- character(0)
  debug_lines <- character(0)

  for (satir in lines) {
    payload <- tryCatch(
      jsonlite::fromJSON(satir, simplifyVector = TRUE),
      error = function(e) NULL
    )

    if (is.null(payload)) {
      next
    }

    payload_type <- as.character(payload$type %||% "")[1]

    if (identical(payload_type, "stream_debug")) {
      debug_text <- decode_fn(payload)
      if (nzchar(debug_text)) {
        debug_lines <- c(debug_lines, debug_text)
      }

    } else if (identical(payload_type, "delta")) {
      delta_text <- decode_fn(payload)
      if (nzchar(delta_text)) {
        delta_batch <- c(delta_batch, delta_text)
      }

    } else if (identical(payload_type, "reasoning_delta")) {
      reasoning_text <- decode_fn(payload)
      if (nzchar(reasoning_text)) {
        reasoning_batch <- c(reasoning_batch, reasoning_text)
      }
    }
  }

  list(
    delta_count = length(delta_batch),
    reasoning_count = length(reasoning_batch),
    delta_text = paste0(delta_batch, collapse = ""),
    reasoning_text = paste0(reasoning_batch, collapse = ""),
    debug_lines = debug_lines
  )
}

# Worker dönüşünde gelen reasoning metnini, yoklama sırasında birikmiş canlı
# reasoning ile karşılaştırıp geri kazanım kararını üretir:
#   - "none": gönderilecek bir şey yok (worker boş, metinler birebir aynı veya
#     canlı metin worker metninin öneki değil).
#   - "replace_full": canlı panel hiç reasoning almadıysa tam metin gönderilir.
#   - "append_suffix": canlı metin worker metninin gerçek öneki ise yalnızca
#     eksik kuyruk gönderilir.
# Bu karar, reasoning'in yalnızca final chunk'ta geldiği veya <think>
# ayrıştırmasının worker tarafında tamamlandığı uçlarda DB'de
# ReasoningContent'in NULL kalmasını engelleyen yolun saf çekirdeğidir.
mergen_stream_reasoning_recovery_plan <- function(accumulated_reasoning,
                                                  result_reasoning,
                                                  stream_started = FALSE,
                                                  normalize_fn = NULL) {
  if (!is.function(normalize_fn)) {
    normalize_fn <- function(x) {
      if (is.null(x)) return("")
      value <- as.character(x)[1]
      if (is.na(value)) "" else value
    }
  }

  worker_reasoning <- tryCatch(
    enc2utf8(normalize_fn(result_reasoning %||% "")),
    error = function(e) ""
  )

  if (length(worker_reasoning) == 0L || is.na(worker_reasoning)) {
    worker_reasoning <- ""
  }

  live_reasoning <- tryCatch(
    enc2utf8(as.character(accumulated_reasoning %||% "")[1]),
    error = function(e) ""
  )

  if (length(live_reasoning) == 0L || is.na(live_reasoning)) {
    live_reasoning <- ""
  }

  none_plan <- list(
    action = "none",
    delta = "",
    accumulated = live_reasoning,
    started_payload = FALSE,
    mark_stream_started = FALSE
  )

  if (!nzchar(worker_reasoning)) {
    return(none_plan)
  }

  if (!nzchar(live_reasoning)) {
    return(list(
      action = "replace_full",
      delta = worker_reasoning,
      accumulated = worker_reasoning,
      started_payload = !isTRUE(stream_started),
      mark_stream_started = TRUE
    ))
  }

  if (!identical(live_reasoning, worker_reasoning) &&
      startsWith(worker_reasoning, live_reasoning)) {
    missing_tail <- substr(
      worker_reasoning,
      nchar(live_reasoning) + 1L,
      nchar(worker_reasoning)
    )

    if (nzchar(missing_tail)) {
      return(list(
        action = "append_suffix",
        delta = missing_tail,
        accumulated = worker_reasoning,
        started_payload = FALSE,
        mark_stream_started = FALSE
      ))
    }
  }

  none_plan
}
