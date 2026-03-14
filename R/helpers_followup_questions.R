# R/helpers_followup_questions.R
# Açıklama: Takip soruları oluşturmak için yardımcı fonksiyonlar.
# Bu dosya server.R'den ayrılarak modülerlik sağlanmıştır.
 
# Kullanıcı perspektifine düzeltme yapan fonksiyon
# "istiyor musunuz?" -> "istiyorum, nasıl yapabilirim?" dönüşümü yapar
ensure_user_perspective <- function(texts) {
  if (is.null(texts) || !length(texts)) return(texts)
  out <- texts
 
  out <- gsub(
    "istiyor musunuz\\?$",
    "istiyorum, nasıl yapabilirim?",
    out,
    ignore.case = TRUE
  )
 
  out <- gsub(
    "ister misiniz\\?$",
    "istiyorum, nasıl yapabilirim?",
    out,
    ignore.case = TRUE
  )
 
  out
}
 
# Takip sorularını normalize eden fonksiyon
# Boşlukları temizler, tekrarları kaldırır, soru işareti ekler
normalize_followup_texts <- function(items, limit = 3L) {
  if (is.null(items) || !length(items)) return(NULL)
  texts <- trimws(as.character(items))
  texts <- texts[nzchar(texts)]
  if (!length(texts)) return(NULL)
  texts <- texts[!duplicated(texts)]
  if (!length(texts)) return(NULL)
 
  texts <- texts[nchar(texts) > 3]
  texts <- substr(texts, 1, 220)
 
  texts <- ensure_user_perspective(texts)
 
  needs_q <- !grepl("\\?$", texts, perl = TRUE)
  texts[needs_q] <- paste0(texts[needs_q], "?")
 
  max_items <- max(1L, as.integer(limit %||% 3L))
  head(texts, max_items)
}
 
# Kod bloklarını temizleyen fonksiyon
# ```json ... ``` gibi blokları kaldırır
strip_code_fences <- function(payload) {
  cleaned <- gsub("^```[a-zA-Z0-9_-]*\\s*", "", payload)
  cleaned <- gsub("\\s*```$", "", cleaned)
  cleaned <- gsub("```json", "", cleaned, ignore.case = TRUE)
  cleaned <- gsub("```", "", cleaned)
  trimws(cleaned)
}
 
# JSON formatındaki takip sorularını ayrıştıran fonksiyon
# {\"followups\": [...]} veya {\"questions\": [...]} formatını destekler
parse_followup_payload <- function(payload) {
  if (!is.character(payload) || length(payload) == 0) return(NULL)
  text <- trimws(payload[1] %||% "")
  if (!nzchar(text)) return(NULL)
 
  cleaned <- strip_code_fences(text)
  parsed <- tryCatch(jsonlite::fromJSON(cleaned), error = function(e) NULL)
  if (is.null(parsed)) {
    return(NULL)
  }
 
  if (is.list(parsed) && !is.null(parsed$followups)) {
    as.character(parsed$followups)
  } else if (is.list(parsed) && !is.null(parsed$questions)) {
    as.character(parsed$questions)
  } else if (is.list(parsed) && !is.null(parsed$sorular)) {
    as.character(parsed$sorular)
  } else if (is.character(parsed)) {
    parsed
  } else if (is.vector(parsed) && !is.list(parsed)) {
    as.character(parsed)
  } else {
    NULL
  }
}
 
# Bağlam metnini kısaltan fonksiyon
# LLM'e gönderilecek metni belirli bir limitle keser
truncate_followup_context <- function(text, limit = 2000L) {
  if (!is.character(text) || length(text) == 0) return("")
  val <- text[1] %||% ""
  if (!nzchar(val)) return("")
  if (nchar(val) <= limit) return(val)
  paste0(substr(val, 1, limit), " \U2026")
}
 
# AI kullanarak takip soruları oluşturan fonksiyon
# Kullanıcı ve asistan mesajlarını analiz ederek öneriler üretir
generate_ai_followups <- function(user_text, ai_text, settings_data, session, api_config) {
  combined <- paste(user_text %||% "", ai_text %||% "")
  if (!nzchar(trimws(combined))) {
    return(NULL)
  }
 
  selected_model <- settings_data$model_selection %||% as.character(api_config$local_models[1])
  request_settings <- list(
    model_selection = selected_model,
    temperature = 0.55,
    enable_mcp_tools = FALSE,
    tool_family = "none",
    shiny_session = session
  )
  api_override <- session$userData$ai_api_key %||% NULL
  if (!is.null(api_override) && nzchar(api_override)) {
    request_settings$api_key_override <- api_override
  }
 
  system_prompt <- paste(
    "Sen MERGEN Bilge arayüzünde takip soruları oluşturan yardımcı bir modülsün.",
    "Yalnızca JSON olarak yanıt ver ve formatı bozma.",
    "Şema: {\"followups\": [\"soru1\", \"soru2\", \"soru3\"]}.",
    "Her soru Türkçe olmalı, 6-18 kelime arası olmalı ve '?' ile bitmeli.",
    "SORULARI KULLANICININ AĞZINDAN YAZ: Bunlar, kullanıcının bir sonraki turda asistanla konuşurken soracağı sorular olsun.",
    "Kullanıcıya hitap eden biçimler (\"istiyor musunuz\", \"ister misiniz\", \"ister miydiniz\" vb.) KULLANMA.",
    "Bunun yerine birinci tekil kişi kullan: örn. \"... nasıl yapabilirim?\", \"... bana gösterebilir misin?\", \"... hakkında daha ayrıntılı anlatır mısın?\"",
    "Örnek yanlış: \"Programın çıktısını nasıl değiştirmek istersiniz?\"",
    "Örnek doğru:  \"Programın çıktısını nasıl değiştirebilirim?\"",
    "Ek açıklama, markdown veya düz yazı ekleme."
  )
 
  context_prompt <- paste(
    "Kullanıcının sorusu:", truncate_followup_context(user_text %||% ""),
    "\n\nAsistanın yanıtı:", truncate_followup_context(ai_text %||% ""),
    "\n\nTalimat: Bu yanıtı okuyan KULLANICININ, bir sonraki turda asistan'a sorabileceği 3 kısa takip sorusu öner.",
    "Soruları mutlaka kullanıcının bakış açısından yaz (\"Ben\", \"bana\", \"nasıl ... yapabilirim?\" gibi)."
  )
 
  messages <- list(
    list(type = "system", content = system_prompt),
    list(type = "user", content = context_prompt)
  )
 
  ai_response <- tryCatch({
    call_local_llm(messages, request_settings)
  }, error = function(err) {
    cat("[FOLLOWUPS][AI] generation failed:", conditionMessage(err), "\n")
    NULL
  })
 
  if (is.null(ai_response)) {
    return(NULL)
  }
 
  payload <- ai_response$content %||% ""
  payload <- as.character(payload)[1]
  parsed <- parse_followup_payload(payload)
  normalize_followup_texts(parsed, limit = 3L)
}
 
# Ana takip sorusu oluşturucu fonksiyon
# Önce AI ile dener, başarısız olursa fallback kullanır
build_followup_suggestions <- function(user_text, ai_text, settings_data, session,
                                        api_config, followup_tools, fallback_followup_tool) {
  enabled_flag <- settings_data$enable_followups
  if (is.null(enabled_flag)) {
    enabled_flag <- TRUE
  }
  if (!isTRUE(enabled_flag)) {
    return(NULL)
  }
 
  generator <- followup_tools$generate
  if (!is.function(generator)) {
    generator <- fallback_followup_tool$generate
  }
 
  ai_suggestions <- generate_ai_followups(user_text, ai_text, settings_data, session, api_config)
  if (!is.null(ai_suggestions) && length(ai_suggestions) >= 2) {
    return(ai_suggestions)
  }
 
  safe_generate <- function(fn) {
    if (!is.function(fn)) return(NULL)
    tryCatch(
      fn(user_text %||% "", ai_text %||% "",
         min_questions = 2L, max_questions = 3L),
      error = function(e) NULL
    )
  }
 
  suggestions <- safe_generate(generator)
  if (is.null(suggestions) || !length(suggestions)) {
    suggestions <- safe_generate(fallback_followup_tool$generate)
  }
 
  if (is.null(suggestions) || !length(suggestions)) {
    return(NULL)
  }
 
  suggestions <- unique(trimws(as.character(suggestions)))
  suggestions <- suggestions[nzchar(suggestions)]
  if (!length(suggestions)) {
    return(NULL)
  }
 
  head(suggestions, 3L)
}