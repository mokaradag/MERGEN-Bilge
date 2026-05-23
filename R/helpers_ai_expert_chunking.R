# ==============================================================================
# Dosya Yolu: R/helpers_ai_expert_chunking.R
# Açıklama: AI Uzman TTS metnini kısa parçalara bölen saf metin yardımcıları.
#           module_ai_expert.R içinden ayrılarak hem dosya bütçesi hem de
#           izole edilebilir yardımcı katman sağlar. Bu dosya yalnızca yan
#           etkisiz (Shiny/IO bağımsız) yardımcılar barındırır.
# ==============================================================================

# Uzun bir parçayı virgül/iki nokta/üç nokta/boşluk sınırlarından kontrollü
# biçimde alt parçalara böler. Saf yardımcı; kapanışsız.
.ai_expert_split_long_piece <- function(piece, max_chunk_chars = 220L) {
  piece <- trimws(piece)
  if (!nzchar(piece)) return(character(0))
  if (nchar(piece) <= max_chunk_chars) return(piece)

  comma_parts <- unlist(strsplit(piece, "(?<=[,;:])\\s+", perl = TRUE))
  comma_parts <- trimws(comma_parts)
  comma_parts <- comma_parts[nzchar(comma_parts)]

  if (length(comma_parts) <= 1) {
    words <- unlist(strsplit(piece, "\\s+"))
    out <- character(0)
    current <- ""

    for (w in words) {
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

  for (part in comma_parts) {
    candidate <- trimws(paste(current, part))
    if (!nzchar(current) || nchar(candidate) <= max_chunk_chars) {
      current <- candidate
    } else {
      out <- c(out, .ai_expert_split_long_piece(current, max_chunk_chars))
      current <- part
    }
  }

  if (nzchar(current)) out <- c(out, .ai_expert_split_long_piece(current, max_chunk_chars))
  out
}

# AI Uzman konuşma metnini ilk parçanın hızlı sentezlenebileceği şekilde
# kısa parçalara böler. Amaç: konuşmayı bekletmeden başlatmak ve sonraki
# parçaları arka planda sıraya almak.
split_text_for_ai_expert_tts <- function(text, max_chunk_chars = 220, min_chunk_chars = 70) {
  text <- trimws(as.character(text %||% ""))
  if (!nzchar(text)) return(list())

  sentence_candidates <- unlist(strsplit(text, "(?<=[.!?…])\\s+", perl = TRUE))
  sentence_candidates <- trimws(sentence_candidates)
  sentence_candidates <- sentence_candidates[nzchar(sentence_candidates)]

  if (length(sentence_candidates) == 0) {
    sentence_candidates <- text
  }

  chunks <- character(0)
  current <- ""

  for (sentence in sentence_candidates) {
    sentence_parts <- .ai_expert_split_long_piece(sentence, max_chunk_chars)

    for (part in sentence_parts) {
      candidate <- trimws(paste(current, part))
      if (!nzchar(current)) {
        current <- part
      } else if (nchar(candidate) <= max_chunk_chars) {
        current <- candidate
      } else if (nchar(current) < min_chunk_chars) {
        current <- candidate
      } else {
        chunks <- c(chunks, current)
        current <- part
      }
    }
  }

  if (nzchar(current)) chunks <- c(chunks, current)

  chunks <- trimws(chunks)
  chunks <- chunks[nzchar(chunks)]

  as.list(chunks)
}
