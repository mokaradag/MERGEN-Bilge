# ==============================================================================
# Dosya Yolu: R/helpers_llm_sse_events.R
# Açıklama: SSE olay/delta ayrıştırma yardımcıları. helpers_llm_sse.R içinden
#           ayrılarak hem dosya bütçesi hem de salt-okunur olay çıkarma yolu
#           için izole edilebilir bir katman sağlar. Bu dosya yalnızca düşük
#           yan etkili (HTTP/IO/lojik durum tutmayan) yardımcılar barındırır.
# ==============================================================================

# ------------------------------------------------------------------------------
# RAW PARÇAYI UTF-8 OLARAK ÇÖZ
# ------------------------------------------------------------------------------
# NOT: SSE parçaları çoklu baytlı UTF-8 karakterlerinin ortasında bölünebilir.
# Bu durumda enc2utf8 sonrası yapılacak gsub/strsplit/nchar gibi işlemler
# "input string 1 is invalid UTF-8" hatasını fırlatır. Bu fonksiyon durumsuz
# bir güvenli çözücüdür ve geçersiz baytları siler. Durumlu (yarım baytları
# bir sonraki parçaya taşıyan) sürüm için R/helpers_llm_stream_io.R içindeki
# create_utf8_stream_decoder() yardımcısı kullanılır.

decode_utf8_raw_chunk <- function(raw_chunk) {
  if (length(raw_chunk) == 0L) return("")
  txt <- tryCatch(rawToChar(raw_chunk), error = function(e) "")
  if (!nzchar(txt)) return("")
  Encoding(txt) <- "UTF-8"
  sanitized <- tryCatch(
    iconv(txt, from = "UTF-8", to = "UTF-8", sub = ""),
    error = function(e) ""
  )
  if (is.na(sanitized)) "" else sanitized
}

# ------------------------------------------------------------------------------
# SSE OLAY METNİNİ AYRIŞTIR
# ------------------------------------------------------------------------------

parse_llm_sse_event <- function(event_text) {
  temiz_metin <- gsub("\r", "", event_text, fixed = TRUE)
  satirlar <- strsplit(temiz_metin, "\n", fixed = TRUE)[[1]]

  data_satirlari <- character(0)

  for (satir in satirlar) {
    if (grepl("^data\\s*:", satir)) {
      data_satirlari <- c(data_satirlari, sub("^data\\s*:\\s*", "", satir))
    }
  }

  if (length(data_satirlari) == 0) {
    aday <- trimws(temiz_metin)
    if (!nzchar(aday)) {
      return(NULL)
    }
    data_payload <- aday
  } else {
    data_payload <- paste(data_satirlari, collapse = "\n")
  }

  if (!nzchar(trimws(data_payload))) {
    return(NULL)
  }

  if (identical(trimws(data_payload), "[DONE]")) {
    return(list(done = TRUE, data = NULL))
  }

  parsed <- tryCatch(
    jsonlite::fromJSON(data_payload, simplifyVector = FALSE),
    error = function(e) NULL
  )

  if (is.null(parsed)) {
    return(NULL)
  }

  list(done = FALSE, data = parsed)
}

# ------------------------------------------------------------------------------
# SSE OLAYINDAN METİN PARÇASI ÇIKAR
# ------------------------------------------------------------------------------

# İç içe listede güvenli yol erişimi. Atomic/NULL/list dışı düğümlerde NULL
# döndürür; böylece extract_llm_delta_bundle() OpenAI uyumlu farklı uç yapılarında
# (atomic delta/message vb.) çökmez.
.llm_sse_safe_get <- function(x, path) {
  current <- x

  for (key in path) {
    if (is.null(current) || !is.list(current)) {
      return(NULL)
    }

    if (is.numeric(key)) {
      idx <- as.integer(key)[1]
      if (is.na(idx) || idx < 1L || length(current) < idx) {
        return(NULL)
      }
      current <- current[[idx]]
    } else {
      key <- as.character(key)[1]
      if (is.na(key) || !nzchar(key)) {
        return(NULL)
      }
      if (is.null(names(current)) || !(key %in% names(current))) {
        return(NULL)
      }
      current <- current[[key]]
    }
  }

  current
}

# Multimodal content düğümünü (list/character) güvenli biçimde content/reasoning
# ayrımı ile ayrıştırır. Bazı uçlar düz string yerine block dizisi yollayabilir.
.llm_sse_split_content_node <- function(node) {
  if (is.null(node)) {
    return(list(content = "", reasoning = ""))
  }

  if (!is.list(node)) {
    return(list(
      content = enc2utf8(normalize_llm_text_node(node)),
      reasoning = ""
    ))
  }

  content_parts <- character(0)
  reasoning_parts <- character(0)

  for (part in node) {
    if (is.null(part)) {
      next
    }

    if (!is.list(part)) {
      txt <- enc2utf8(normalize_llm_text_node(part))
      if (nzchar(txt)) {
        content_parts <- c(content_parts, txt)
      }
      next
    }

    part_type <- tolower(as.character(
      .llm_sse_safe_get(part, list("type")) %||%
        .llm_sse_safe_get(part, list("kind")) %||%
        .llm_sse_safe_get(part, list("role")) %||%
        ""
    )[1])

    part_text <- extract_first_nonempty_llm_text(
      .llm_sse_safe_get(part, list("text")),
      .llm_sse_safe_get(part, list("content")),
      .llm_sse_safe_get(part, list("value")),
      .llm_sse_safe_get(part, list("reasoning_content")),
      .llm_sse_safe_get(part, list("reasoning")),
      .llm_sse_safe_get(part, list("thinking")),
      .llm_sse_safe_get(part, list("thought"))
    )

    if (!nzchar(part_text)) {
      next
    }

    if (grepl("reason|thinking|thought", part_type, ignore.case = TRUE, perl = TRUE)) {
      reasoning_parts <- c(reasoning_parts, part_text)
    } else {
      content_parts <- c(content_parts, part_text)
    }
  }

  list(
    content = enc2utf8(paste0(content_parts, collapse = "")),
    reasoning = enc2utf8(paste0(reasoning_parts, collapse = ""))
  )
}

extract_llm_delta_bundle <- function(event_obj) {
  # OpenAI uyumlu uçlar her zaman aynı JSON şeklini döndürmüyor:
  # - choices[[1]]$delta$content
  # - choices[[1]]$delta$reasoning_content
  # - delta$content
  # - content
  # Bazı uçlarda ara düğümler atomic vector olabiliyor. Bu nedenle hiçbir yerde
  # doğrudan iç içe $ erişimi kullanmıyoruz; tüm yollar .llm_sse_safe_get()
  # üzerinden geçer.

  safe_get <- .llm_sse_safe_get
  split_content_node <- .llm_sse_split_content_node

  if (!is.list(event_obj)) {
    return(list(content = "", reasoning = ""))
  }

  content_node <- extract_first_nonempty_llm_text(
    safe_get(event_obj, list("choices", 1L, "delta", "content")),
    safe_get(event_obj, list("choices", 1L, "delta", "text")),
    safe_get(event_obj, list("choices", 1L, "message", "content")),
    safe_get(event_obj, list("choices", 1L, "text")),
    safe_get(event_obj, list("delta", "content")),
    safe_get(event_obj, list("delta", "text")),
    safe_get(event_obj, list("content")),
    safe_get(event_obj, list("text"))
  )

  reasoning_text <- extract_first_nonempty_llm_text(
    safe_get(event_obj, list("choices", 1L, "delta", "reasoning_content")),
    safe_get(event_obj, list("choices", 1L, "delta", "reasoning")),
    safe_get(event_obj, list("choices", 1L, "delta", "reasoning_text")),
    safe_get(event_obj, list("choices", 1L, "delta", "thinking")),
    safe_get(event_obj, list("choices", 1L, "delta", "thought")),
    safe_get(event_obj, list("choices", 1L, "delta", "reasoning", "content")),
    safe_get(event_obj, list("choices", 1L, "delta", "reasoning", "text")),
    safe_get(event_obj, list("choices", 1L, "delta", "reasoning", "summary")),
    safe_get(event_obj, list("choices", 1L, "message", "reasoning_content")),
    safe_get(event_obj, list("choices", 1L, "message", "reasoning")),
    safe_get(event_obj, list("choices", 1L, "message", "reasoning_text")),
    safe_get(event_obj, list("choices", 1L, "message", "thinking")),
    safe_get(event_obj, list("choices", 1L, "message", "thought")),
    safe_get(event_obj, list("choices", 1L, "message", "reasoning", "content")),
    safe_get(event_obj, list("choices", 1L, "message", "reasoning", "text")),
    safe_get(event_obj, list("choices", 1L, "message", "reasoning", "summary")),
    safe_get(event_obj, list("delta", "reasoning_content")),
    safe_get(event_obj, list("delta", "reasoning")),
    safe_get(event_obj, list("delta", "reasoning_text")),
    safe_get(event_obj, list("delta", "thinking")),
    safe_get(event_obj, list("delta", "thought")),
    safe_get(event_obj, list("reasoning_content")),
    safe_get(event_obj, list("reasoning")),
    safe_get(event_obj, list("reasoning_text")),
    safe_get(event_obj, list("thinking")),
    safe_get(event_obj, list("thought"))
  )

  # Bazı uçlar content'i multimodal/list parçaları olarak döndürebilir.
  # Eğer düz content boşsa list node'u ayrıştırmayı dene.
  if (!nzchar(content_node)) {
    split_a <- split_content_node(safe_get(event_obj, list("choices", 1L, "delta", "content")))
    split_b <- split_content_node(safe_get(event_obj, list("choices", 1L, "message", "content")))
    split_c <- split_content_node(safe_get(event_obj, list("delta", "content")))
    split_d <- split_content_node(safe_get(event_obj, list("content")))

    content_node <- extract_first_nonempty_llm_text(
      split_a$content,
      split_b$content,
      split_c$content,
      split_d$content
    )

    reasoning_text <- paste0(
      reasoning_text,
      extract_first_nonempty_llm_text(
        split_a$reasoning,
        split_b$reasoning,
        split_c$reasoning,
        split_d$reasoning
      )
    )
  }

  list(
    content = enc2utf8(content_node %||% ""),
    reasoning = enc2utf8(reasoning_text %||% "")
  )
}

extract_llm_delta_text <- function(event_obj) {
  extract_llm_delta_bundle(event_obj)$content
}

# ------------------------------------------------------------------------------
# SSE OLAYINDAN KAYNAK BİLGİSİ ÇIKAR
# ------------------------------------------------------------------------------

extract_llm_event_sources <- function(event_obj) {
  ayristirilmis <- extract_llm_content_and_sources(event_obj)
  ayristirilmis$sources
}
