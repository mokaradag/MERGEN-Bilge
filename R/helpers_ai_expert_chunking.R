# ==============================================================================
# Dosya Yolu: R/helpers_ai_expert_chunking.R
# Açıklama: AI Uzman TTS metnini kısa parçalara bölen saf metin yardımcıları.
#           module_ai_expert.R içinden ayrılarak hem dosya bütçesi hem de
#           izole edilebilir yardımcı katman sağlar. Bu dosya yalnızca yan
#           etkisiz (Shiny/IO bağımsız) yardımcılar barındırır.
# ==============================================================================

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
}

# VoxCPM2 uzun metinlerin sonunu semantik olarak eksik üretebildiği için bu
# değerler yalnızca UX tercihi değil, ses bütünlüğü politikasıdır. İlk parça daha
# küçük tutulur (daha kısa açılış gecikmesi); hiçbir tercih sert üst sınırı aşamaz.
MERGEN_AI_EXPERT_TTS_MAX_CHUNK_CHARS   <- 180L
MERGEN_AI_EXPERT_TTS_FIRST_CHUNK_CHARS <- 100L
MERGEN_AI_EXPERT_TTS_MIN_CHUNK_CHARS   <- 60L

# Uzun bir parçayı noktalama/boşluk sınırlarından kontrollü biçimde böler.
# Tek bir sözcük üst sınırı aşıyorsa Unicode karakter konumlarında deterministik
# olarak bölünür; böylece max_chunk_chars her durumda gerçek bir üst sınırdır.
.ai_expert_split_long_piece <- function(piece, max_chunk_chars = MERGEN_AI_EXPERT_TTS_MAX_CHUNK_CHARS) {
  max_chunk_chars <- suppressWarnings(as.integer(max_chunk_chars)[1])
  if (is.na(max_chunk_chars) || max_chunk_chars < 1L) max_chunk_chars <- 1L
  piece <- trimws(gsub("[[:space:]]+", " ", as.character(piece %||% "")))
  if (!nzchar(piece)) return(character(0))
  if (nchar(piece) <= max_chunk_chars) return(piece)

  boundary_parts <- unlist(strsplit(piece, "(?<=[.!?…,:;])\\s+", perl = TRUE))
  boundary_parts <- trimws(boundary_parts)
  boundary_parts <- boundary_parts[nzchar(boundary_parts)]

  if (length(boundary_parts) <= 1L) {
    words <- unlist(strsplit(piece, "\\s+"))
    out <- character(0)
    current <- ""

    for (w in words) {
      if (nchar(w) > max_chunk_chars) {
        if (nzchar(current)) {
          out <- c(out, current)
          current <- ""
        }
        starts <- seq.int(1L, nchar(w), by = max_chunk_chars)
        token_parts <- substring(w, starts, pmin(starts + max_chunk_chars - 1L, nchar(w)))
        if (length(token_parts) > 1L) out <- c(out, token_parts[-length(token_parts)])
        current <- token_parts[[length(token_parts)]]
        next
      }
      candidate <- trimws(paste(current, w))
      if (!nzchar(current) || nchar(candidate) <= max_chunk_chars) {
        current <- candidate
      } else {
        out <- c(out, current)
        current <- w
      }
    }

    if (nzchar(current)) out <- c(out, current)
    return(out)
  }

  out <- character(0)
  current <- ""

  for (part in boundary_parts) {
    candidate <- trimws(paste(current, part))
    if (!nzchar(current) && nchar(part) > max_chunk_chars) {
      split_part <- .ai_expert_split_long_piece(part, max_chunk_chars)
      if (length(split_part) > 1L) out <- c(out, split_part[-length(split_part)])
      current <- split_part[[length(split_part)]]
    } else if (!nzchar(current) || nchar(candidate) <= max_chunk_chars) {
      current <- candidate
    } else {
      out <- c(out, current)
      if (nchar(part) > max_chunk_chars) {
        split_part <- .ai_expert_split_long_piece(part, max_chunk_chars)
        if (length(split_part) > 1L) out <- c(out, split_part[-length(split_part)])
        current <- split_part[[length(split_part)]]
      } else {
        current <- part
      }
    }
  }

  if (nzchar(current)) out <- c(out, current)
  out
}

# Cümle sınırlarını önceleyen, verilen tek sert üst sınıra göre açgözlü bölümleme.
.ai_expert_partition_text <- function(text, max_chunk_chars) {
  sentence_candidates <- unlist(strsplit(text, "(?<=[.!?…])\\s+", perl = TRUE))
  sentence_candidates <- trimws(sentence_candidates)
  sentence_candidates <- sentence_candidates[nzchar(sentence_candidates)]
  if (length(sentence_candidates) == 0L) sentence_candidates <- text

  chunks <- character(0)
  current <- ""
  for (sentence in sentence_candidates) {
    for (part in .ai_expert_split_long_piece(sentence, max_chunk_chars)) {
      candidate <- trimws(paste(current, part))
      if (!nzchar(current) || nchar(candidate) <= max_chunk_chars) {
        current <- candidate
      } else {
        chunks <- c(chunks, current)
        current <- part
      }
    }
  }
  if (nzchar(current)) chunks <- c(chunks, current)
  chunks
}

# AI Uzman konuşma metnini ilk parçanın hızlı sentezlenebileceği şekilde
# kısa parçalara böler. Amaç: konuşmayı bekletmeden başlatmak ve sonraki
# parçaları arka planda sıraya almak.
split_text_for_ai_expert_tts <- function(
    text,
    max_chunk_chars = MERGEN_AI_EXPERT_TTS_MAX_CHUNK_CHARS,
    min_chunk_chars = MERGEN_AI_EXPERT_TTS_MIN_CHUNK_CHARS,
    first_chunk_chars = MERGEN_AI_EXPERT_TTS_FIRST_CHUNK_CHARS) {
  max_chunk_chars <- suppressWarnings(as.integer(max_chunk_chars)[1])
  if (is.na(max_chunk_chars) || max_chunk_chars < 1L) max_chunk_chars <- 1L
  min_chunk_chars <- suppressWarnings(as.integer(min_chunk_chars)[1])
  if (is.na(min_chunk_chars) || min_chunk_chars < 1L) min_chunk_chars <- 1L
  min_chunk_chars <- min(min_chunk_chars, max_chunk_chars)
  first_chunk_chars <- suppressWarnings(as.integer(first_chunk_chars)[1])
  if (is.na(first_chunk_chars) || first_chunk_chars < 1L) first_chunk_chars <- max_chunk_chars
  first_chunk_chars <- min(first_chunk_chars, max_chunk_chars)

  text <- trimws(gsub("[[:space:]]+", " ", as.character(text %||% "")))
  if (!nzchar(text)) return(list())

  # min_chunk_chars yalnızca doğal birleştirme tercihidir: açgözlü bölümleyici
  # kısa parçayı ancak aday sert sınıra sığıyorsa birleştirir. Asla üst sınırı
  # aşan eski "kısa current" istisnasına dönüşmez.
  first_candidates <- .ai_expert_partition_text(text, first_chunk_chars)
  first <- first_candidates[[1L]]
  rest <- trimws(substr(text, nchar(first) + 1L, nchar(text)))
  chunks <- c(first, if (nzchar(rest)) .ai_expert_partition_text(rest, max_chunk_chars) else character(0))
  chunks <- chunks[nzchar(trimws(chunks))]

  if (any(nchar(chunks) > max_chunk_chars)) {
    stop("AI Uzman TTS parça üst sınırı ihlal edildi.", call. = FALSE)
  }

  as.list(chunks)
}
