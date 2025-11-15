# R/module_followup_questions.R
#
# Provides lightweight, deterministic follow-up suggestions based on
# the latest user prompt and AI response. Designed to avoid additional
# API round-trips while still producing contextual prompts.

.followup_generator_impl <- local({
  turkish_stopwords <- c(
    "ve", "veya", "ile", "ama", "ancak", "fakat", "bir", "bu", "şu", "o",
    "için", "icin", "gibi", "daha", "çok", "az", "hem", "ya", "yada",
    "ya da", "ki", "mı", "mi", "mu", "mü", "nı", "ni", "nu", "nü",
    "de", "da", "ya", "sen", "ben", "biz", "siz", "onlar", "şey"
  )

  clean_text <- function(text) {
    if (is.null(text) || !nzchar(text)) return("")
    txt <- gsub("[\r\n]+", " ", text)
    txt <- gsub("[^[:alnum:]çğıöşüÇĞİÖŞÜ ]", " ", txt)
    trimws(txt)
  }

  extract_keywords <- function(text, limit = 3L) {
    cleaned <- tolower(clean_text(text))
    tokens <- unlist(strsplit(cleaned, "\\s+", perl = TRUE))
    if (!length(tokens)) return(character(0))
    tokens <- tokens[!(tokens %in% turkish_stopwords)]
    tokens <- tokens[nzchar(tokens)]
    unique(head(tokens, limit))
  }

  safe_title_case <- function(tokens) {
    if (!length(tokens)) return(character(0))
    tryCatch({
      suppressWarnings(
        stringi::stri_trans_totitle(
          tokens,
          opts_brkiter = stringi::stri_opts_brkiter(type = "word", locale = "tr_TR")
        )
      )
    }, warning = function(w) {
      stringr::str_to_title(tokens)
    }, error = function(e) {
      tokens
    })
  }

  format_topic <- function(tokens) {
    if (length(tokens) == 0) return(NULL)
	title_tokens <- safe_title_case(tokens)
    trimws(paste(title_tokens, collapse = " "))
  }

  ensure_question <- function(text) {
    if (!nzchar(text)) return("")
    trimmed <- trimws(text)
    if (grepl("\\?$", trimmed)) {
      trimmed
    } else {
      paste0(trimmed, "?")
    }
  }

  build_templates <- function(topic = NULL) {
    base <- if (!is.null(topic) && nzchar(topic)) {
      c(
        sprintf("%s konusunda bir sonraki adımı nasıl planlamalıyım?", topic),
        sprintf("%s ile ilgili potansiyel riskleri nasıl izleyebilirim?", topic),
        sprintf("%s hakkında uygulanmış bir örnek paylaşabilir misin?", topic)
      )
    } else {
      character(0)
    }

    general <- c(
      "Bu cevabı günlük iş akışına nasıl uyarlayabilirim",
      "Ek olarak hangi verileri incelememi önerirsin",
      "Benzer durumlarda takip etmem gereken metrikler neler",
      "Bu çözümü güçlendirmek için önerebileceğin araçlar var mı"
    )

    unique(c(base, general))
  }

  function(user_text = NULL,
           ai_text = NULL,
           min_questions = 2L,
           max_questions = 3L) {
    combined <- paste(user_text %||% "", ai_text %||% "")
    if (!nzchar(trimws(combined))) {
      return(character(0))
    }

    topic_tokens <- extract_keywords(user_text %||% "", limit = 3L)
    if (length(topic_tokens) == 0) {
      topic_tokens <- extract_keywords(ai_text %||% "", limit = 3L)
    }
    topic <- format_topic(topic_tokens)

    templates <- build_templates(topic)
    if (!length(templates)) {
      templates <- build_templates(NULL)
    }

    suggestions <- ensure_question(templates)
    suggestions <- unique(suggestions[nzchar(suggestions)])
    if (!length(suggestions)) {
      return(character(0))
    }

    max_q <- max(2L, as.integer(max_questions))
    min_q <- max(1L, as.integer(min_questions))
    suggestions <- suggestions[seq_len(min(length(suggestions), max_q))]

    if (length(suggestions) < min_q) {
      fallback <- ensure_question(c(
        "Bu sonucu ölçmek için hangi göstergeleri takip etmeliyim",
        "İlgili paydaşları nasıl bilgilendirmeliyim"
      ))
      extra <- setdiff(fallback, suggestions)
      suggestions <- c(suggestions, extra)
      suggestions <- suggestions[seq_len(min(length(suggestions), max_q))]
    }

    suggestions
  }
})

create_followup_suggestions_tool <- function() {
  list(generate = .followup_generator_impl)
}

followupSuggestionsServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    create_followup_suggestions_tool()
  })
}