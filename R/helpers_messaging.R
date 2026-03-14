# R/helpers_messaging.R

#' Create HTML for a Code Block
#'
#' Generates a complete HTML structure for a syntax-highlighted code block,
#' including a header with the language name, a copy button, and line numbers.
#'
#' @param code The raw code string to be formatted.
#' @param language The programming language key (e.g., "r", "python").
#'                 If "auto", the language will be detected automatically.
#' @return An HTML object created with `htmltools::HTML`.

# --- Safe fallback: detect_code_content ---
# Ensure the function exists and always returns a single TRUE/FALSE
if (!exists("detect_code_content") || !is.function(detect_code_content)) {
  detect_code_content <- function(text) {
    if (is.null(text) || length(text) == 0) return(FALSE)
    # Very light heuristic; always returns length-1 logical
    # (adjust to your needs if you have a real detector elsewhere)
    any(grepl("```|^\\s*def\\s+|^\\s*function\\s*\\(|<-\\s*function\\s*\\(",
              paste(text, collapse = "\n")))
  }
}

create_code_block_html <- function(code, language = "auto") {
  block_id <- paste0("code_", floor(as.numeric(Sys.time()) * 1000), sample(100, 1))
  detected_lang <- if (language == "auto") detect_language(code) else tolower(language)
  
  raw_display_language <- LANG_MAP[[detected_lang]] %||% detected_lang
  display_language <- stringr::str_to_upper(raw_display_language, locale = "en")
  
  # The new structure uses a simple <textarea> that CodeMirror will enhance.
  # The 'data-lang' attribute is used by our JavaScript to set the correct language mode.
  HTML(sprintf(
    '<div class="code-container" id="%s">
       <div class="code-header">
         <span class="code-language">%s</span>
         <div class="code-header-actions">
           <button class="code-collapse-btn" onclick="toggleCodeCollapse(this)" title="Kodu Daralt/Genişlet">
             <i class="fas fa-chevron-up"></i>
           </button>
           <button class="code-copy-btn" onclick="copyCodeFromCM(this)" title="Kodu Kopyala">
             <i class="fas fa-copy"></i>
           </button>
         </div>
       </div>
       <div class="code-collapse-info" onclick="expandCodeFromInfo(this)" style="display:none;">
         <span class="code-collapse-line-count"></span>
         <i class="code-collapse-icon fas fa-chevron-down"></i>
       </div>
       <textarea class="codemirror-textarea" data-lang="%s">%s</textarea>
     </div>',
    block_id,
    display_language,
    detected_lang,
    htmltools::htmlEscape(code) # Sadece ham kodu escape et
  ))
}

#' Robustly Parse AI Response with a Single Code Block
#'
#' A specialized parser for AI responses that are expected to contain one primary
#' code block surrounded by explanatory text.
#'
#' @param content The raw string content from the AI response.
#' @return A list containing the final HTML (`html`) and a boolean (`has_code`).
parse_ai_response_robustly <- function(content) {
  content <- gsub("\\\\n", "\n", content)

  # If the content has actual reference URLs at the bottom, make them clickable
  content <- gsub("\\[1\\]:\\s*(https?://[^\\s]+)", '[1]: <a href="\\1" target="_blank">\\1</a>', content)
  content <- gsub("\\[2\\]:\\s*(https?://[^\\s]+)", '[2]: <a href="\\1" target="_blank">\\1</a>', content)
  content <- gsub("\\[3\\]:\\s*(https?://[^\\s]+)", '[3]: <a href="\\1" target="_blank">\\1</a>', content)
  content <- gsub("\\[4\\]:\\s*(https?://[^\\s]+)", '[4]: <a href="\\1" target="_blank">\\1</a>', content)
  content <- gsub("\\[5\\]:\\s*(https?://[^\\s]+)", '[5]: <a href="\\1" target="_blank">\\1</a>', content)
  content <- gsub("\\[6\\]:\\s*(https?://[^\\s]+)", '[6]: <a href="\\1" target="_blank">\\1</a>', content)

  # NEW: Guard - if no code fences, just return markdown
  fences <- stringr::str_locate_all(content, "```")[[1]]
  if (is.null(fences) || NROW(fences) < 2) {
    html_content <- commonmark::markdown_html(content, hardbreaks = TRUE, extensions = c("strikethrough", "table"))
    return(list(html = html_content, has_code = FALSE))
  }

  first_fence <- fences[1, ]
  last_fence  <- fences[NROW(fences), ]
  
  text_before <- substr(content, 1, first_fence[1] - 1)
  full_code_block <- substr(content, first_fence[1], last_fence[2])
  text_after <- substr(content, last_fence[2] + 1, nchar(content))
  
  lang_match <- stringr::str_match(full_code_block, "```(\\w*\\b)?\\n?")
  language <- if (!is.na(lang_match[1, 2]) && nchar(lang_match[1, 2]) > 0) lang_match[1, 2] else "auto"
  
  code_content <- stringr::str_remove(full_code_block, paste0("```", language, "\\n?"))
  code_content <- stringr::str_remove(code_content, "```$")
  
  html_parts <- list()
  if (nchar(trimws(text_before)) > 0) {
    html_parts <- append(html_parts, commonmark::markdown_html(text_before, hardbreaks = TRUE, extensions = c("strikethrough", "table")))
  }
  html_parts <- append(html_parts, create_code_block_html(trimws(code_content), language))
  if (nchar(trimws(text_after)) > 0) {
    html_parts <- append(html_parts, commonmark::markdown_html(text_after, hardbreaks = TRUE, extensions = c("strikethrough", "table")))
  }
  
  return(list(html = paste(html_parts, collapse = ""), has_code = TRUE))
}

#' Process Message Content into HTML
#'
#' The main message processor.
#'
#' @param content The raw string content of the message.
#' @param type A character string, either "user" or "ai".
#' @return A list containing the final HTML (`html`) and a boolean (`has_code`).
process_message_content <- function(content, type = "user") {
  # --- DEBUG GUARD + LOG ---
  if (!is.character(content) || length(content) == 0) {
    cat("[MSG_RENDER] content is length-0; substituting empty string. type=", type, "\n", sep = "")
    content <- ""
  } else if (length(content) > 1) {
    if (getOption("mergen.debug.verbose", FALSE)) {
      cat("[MSG_RENDER] content has length>", length(content), " taking first element.\n")
    }
    content <- content[1]
  } else {
    # length == 1
    if (getOption("mergen.debug.verbose", FALSE)) {
      cat("[MSG_RENDER] content len=1 ok. preview=\"", substr(as.character(content), 1, 120), "\"\n", sep = "")
    }
  }
  # --------------------------

  content <- gsub("\\\\n", "\n", content)
  content <- trimws(content)
  
  # For user messages with detected code (safe)
  has_user_code <- FALSE
	if (identical(type, "user")) {
	  dc <- try(detect_code_content(content), silent = TRUE)
	  if (!inherits(dc, "try-error") && length(dc) >= 1) {
		has_user_code <- isTRUE(dc[[1]])
	  }
	}
	if (has_user_code) {
	  # Metin ve kod kısımlarını ayırmayı dene (karma mesajlar için)
	  split_result <- tryCatch(split_text_and_code(content), error = function(e) NULL)
	  if (!is.null(split_result)) {
	    html_parts <- list()
	    if (nchar(trimws(split_result$text_before)) > 0) {
	      html_parts <- append(html_parts,
	        commonmark::markdown_html(split_result$text_before, hardbreaks = TRUE))
	    }
	    html_parts <- append(html_parts,
	      as.character(create_code_block_html(split_result$code)))
	    if (nchar(trimws(split_result$text_after)) > 0) {
	      html_parts <- append(html_parts,
	        commonmark::markdown_html(split_result$text_after, hardbreaks = TRUE))
	    }
	    return(list(html = paste(html_parts, collapse = ""), has_code = TRUE))
	  }
	  # Tamamen kod ise mevcut davranışı koru
	  return(list(html = as.character(create_code_block_html(content)), has_code = TRUE))
	}
  
  # Check for code blocks with triple backticks
  if (!grepl("```", content, fixed = TRUE)) {
    # No code blocks, just process as markdown
    html_content <- commonmark::markdown_html(content, hardbreaks = TRUE, extensions = c("strikethrough", "table"))
    return(list(html = html_content, has_code = FALSE))
  }
  
  # Split content by code blocks
  parts <- strsplit(content, "```", fixed = TRUE)[[1]]
  html_parts <- list()
  has_code <- FALSE
  
  for (i in seq_along(parts)) {
    if (i %% 2 == 1) {
      # Text part (odd indices)
      if (nchar(trimws(parts[i])) > 0) {
        html_parts <- append(html_parts, 
          commonmark::markdown_html(parts[i], hardbreaks = TRUE, extensions = c("strikethrough", "table")))
      }
    } else {
      # Code part (even indices)
      has_code <- TRUE
      # Extract language from first line
      lines <- strsplit(parts[i], "\n", fixed = TRUE)[[1]]
      language <- if (length(lines) > 0 && nchar(lines[1]) > 0 && !grepl(" ", lines[1])) {
        lines[1]
      } else {
        "auto"
      }
      
      # Get code content (skip language line if present)
      code_content <- if (language != "auto" && length(lines) > 1) {
        paste(lines[-1], collapse = "\n")
      } else {
        parts[i]
      }
      
      if (nchar(trimws(code_content)) > 0) {
        html_parts <- append(html_parts, create_code_block_html(trimws(code_content), language))
      }
    }
  }
  
  return(list(html = paste(html_parts, collapse = ""), has_code = has_code))
}

build_followup_container <- function(message_id, followups = NULL, pending = FALSE) {
  if (is.null(followups) || length(followups) == 0) {
    return(NULL)
  }

  classes <- c("followup-suggestions-box")
  if (isTRUE(pending)) {
    classes <- c(classes, "pending")
  }

  buttons <- lapply(seq_along(followups), function(idx) {
    question <- followups[[idx]] %||% ""
    if (!nzchar(question)) return(NULL)

    tags$button(
      type = "button",
      class = "followup-option",
      `data-question` = question,
      span(htmltools::htmlEscape(question)),
      tags$i(class = "fas fa-arrow-up-right-from-square")
    )
  })

  buttons <- Filter(Negate(is.null), buttons)
  if (!length(buttons)) {
    return(NULL)
  }

  div(
    id = paste0("followup_container_", message_id),
    class = paste(classes, collapse = " "),
    `data-has-items` = "true",
    div(
      class = "followup-suggestions-title",
      tags$i(class = "fas fa-lightbulb"),
      span("Önerilen Takip Soruları")
    ),
    div(class = "followup-suggestions-list", buttons)
  )
}

#' Pure UI builder for message bubbles (no access to values$)
#' Pass liked_ids / disliked_ids explicitly.
render_message_bubble_ui <- function(msg, settings, is_last_user_message = FALSE,
                                     character_data = NULL,
                                     liked_ids = character(0), disliked_ids = character(0)) {

  is_streaming <- isTRUE(msg$is_streaming)

  # Oturum-yerel user_config varsa onu kullan, yoksa global'e düş (çoklu kullanıcı güvenliği)
  uc <- settings$user_config %||% user_config

  div(id = paste0("message_wrapper_", msg$id), {

    if (msg$type == "user") {
      div(
        class = "message-bubble animate-fadeIn",
        div(
          class = "user-message",
          div(
            class = "message-header",
            div(
              class = "user-avatar",
              style = "overflow: hidden; width: 40px; height: 40px;",
              tags$img(
                src = paste0("https://url......./", uc$userId, ".jpg"),
                alt = uc$name,
                style = "width: 100%; height: 100%; object-fit: cover;",
                onerror = "this.style.display='none'; this.parentElement.classList.add('gradient-user'); this.parentElement.innerHTML='<i class=\"fas fa-user\"></i>';"
              )
            ),
            div(
              class = "message-info",
              div(class = "message-author", uc$name),
              div(class = paste("message-time", if (isTRUE(settings$enable_timestamps)) "" else "hidden"), msg$timestamp)
            ),
            div(
              class = "message-actions",
              if (is_last_user_message && !is_streaming) {
                tags$button(
                  id = paste0("edit_user_", msg$id),
                  class = "btn btn-default message-action-btn", title = "Düzenle",
                  onclick = sprintf("Shiny.setInputValue('edit_message_request', '%s', {priority: 'event'})", msg$id),
                  icon("pencil-alt")
                )
              },
              tags$button(
                id = paste0("copy_user_", msg$id),
                class = "btn btn-default message-action-btn", title = "Kopyala",
                onclick = sprintf("copyAIMessageContent('%s')", msg$id),
                icon("copy")
              )
            )
          ),
          div(class = "message-content", id = msg$id, HTML(msg$html_content))
        )
      )

    } else if (msg$type %in% c("ai", "assistant")) {
      audio_block <- NULL
      if (!is.null(msg$audio_src) && nzchar(msg$audio_src)) {
        audio_block <- build_tts_audio_ui(msg$id, msg$audio_src, msg$audio_voice %||% NULL)
      }
	  
      div(
        class = "message-bubble animate-fadeIn",
        div(
          class = if(is_streaming) "ai-message streaming-message" else "ai-message",
          div(
            class = "message-header",
            div(
              class = "ai-avatar",
              style = "overflow: hidden; width: 40px; height: 40px;",
              tags$img(
                src = if (!is.null(character_data)) character_data$avatar else "mergen_avatar.png",
                alt = if (!is.null(character_data)) character_data$display_name else "MERGEN Bilge",
                style = "width: 100%; height: 100%; object-fit: cover;",
                onerror = "this.style.display='none'; this.parentElement.classList.add('gradient-ai'); this.parentElement.innerHTML='<i class=\"fas fa-magic\"></i>';"
              )
            ),
            div(
              class = "message-info",
              div(
                class = "message-author",
                if (!is.null(character_data)) {
                  span(character_data$display_name,
                       class = "brand-text-primary",
                       style = paste0("color: ", character_data$accent, " !important;"))
                } else {
                  tagList(span("MERGEN", class = "brand-text-primary"), span("Bilge"))
                }
              ),
              div(class = paste("message-time", if (isTRUE(settings$enable_timestamps)) "" else "hidden"), msg$timestamp)
            ),
            div(
              class = "message-actions",
              tags$button(
                id = paste0("like_", msg$id),
                class = paste(
                  "btn btn-default message-action-btn like-btn",
                  if (is_streaming) "streaming-hidden" else "",
                  if (isTRUE(as.character(msg$db_id) %in% as.character(liked_ids))) "active liked" else ""
                ),
                title = "Beğen",
                onclick = sprintf("Shiny.setInputValue('like_message', '%s', {priority: 'event'})", msg$id),
                icon("thumbs-up")
              ),
              tags$button(
                id = paste0("dislike_", msg$id),
                class = paste(
                  "btn btn-default message-action-btn dislike-btn",
                  if (is_streaming) "streaming-hidden" else "",
                  if (isTRUE(as.character(msg$db_id) %in% as.character(disliked_ids))) "active disliked" else ""
                ),
                title = "Beğenme",
                onclick = sprintf("Shiny.setInputValue('dislike_message', '%s', {priority: 'event'})", msg$id),
                icon("thumbs-down")
              ),
              tags$button(
                id = paste0("copy_ai_", msg$id),
                class = paste("btn btn-default message-action-btn", if(is_streaming) "streaming-hidden" else ""),
                title = "Kopyala",
                onclick = sprintf("copyAIMessageContent('%s')", msg$id),
                icon("copy")
              ),
              tags$button(
                id = paste0("regenerate_", msg$id),
                class = paste("btn btn-default message-action-btn", if(is_streaming) "streaming-hidden" else ""),
                title = "Yeniden Oluştur",
                onclick = sprintf("Shiny.setInputValue('regenerate_message', '%s', {priority: 'event'})", msg$id),
                icon("sync-alt")
              )
            )
          ),
          div(class = "message-content",
              id = msg$id,
              `data-streaming` = if(is_streaming) "true" else "false",
              HTML(msg$html_content)),
          if (!is.null(audio_block)) audio_block,
          build_followup_container(
            msg$id,
            msg$followups %||% NULL,
            pending = isTRUE(msg$is_streaming)
          )
        )
      )

    } else {
      # system
      div(
        class = "message-bubble animate-fadeIn",
        div(
          class = "system-message",
          div(
            style = "display: flex; align-items: center; justify-content: center; gap: 10px;",
            div(class = "message-content", HTML(msg$html_content)),
            tags$button(
              class = "message-action-btn",
              title = "Copy Text",
              icon("copy"),
              onclick = sprintf("copyAIMessageContent('%s')", msg$id)
            )
          ),
          div(class = paste("message-time", if (isTRUE(settings$enable_timestamps)) "" else "hidden"), msg$timestamp)
        )
      )
    }
  })
}