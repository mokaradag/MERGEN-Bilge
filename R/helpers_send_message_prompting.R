# ==============================================================================
# Dosya Yolu: R/helpers_send_message_prompting.R
# Açıklama: send_message hattındaki prompt, karakter stili ve dosya bağlamı
#           hazırlığını tek yerde toplar.
# ==============================================================================

# Vision (görsel bağlam) yardımcıları normalde manifest ile yüklenir; izole
# test/worker bağlamında yoksa çalışma-dizininden bağımsız olarak yüklenir.
if (!exists("mergen_vision_active", mode = "function", inherits = TRUE)) {
  .mb_vision_candidates <- c(
    file.path("R", "helpers_vision_context.R"),
    file.path("..", "..", "R", "helpers_vision_context.R"),
    if (nzchar(Sys.getenv("MERGEN_REPO_ROOT"))) {
      file.path(Sys.getenv("MERGEN_REPO_ROOT"), "R", "helpers_vision_context.R")
    } else {
      NULL
    }
  )
  for (.mb_vision_cand in .mb_vision_candidates) {
    if (!is.null(.mb_vision_cand) && nzchar(.mb_vision_cand) &&
        isTRUE(tryCatch(file.exists(.mb_vision_cand), error = function(e) FALSE))) {
      source(.mb_vision_cand, encoding = "UTF-8", local = globalenv())
      break
    }
  }
  if (exists(".mb_vision_cand", inherits = FALSE)) rm(.mb_vision_cand)
  if (exists(".mb_vision_candidates", inherits = FALSE)) rm(.mb_vision_candidates)
}

mergen_build_citation_instruction <- function(uploaded_count) {
  if (uploaded_count > 0) {
    paste0(
      "\n\nMANDATORY CITATION RULE: ",
      "Your response MUST end with a 'Kaynakça:' section listing the source filenames. ",
      "This is REQUIRED and NON-NEGOTIABLE. ",
      "Do NOT add any other 'Sources' sections. ",
      "Do NOT use inline [Source: ...] citations. ",
      "Example:\nKaynakça:\n1) document.docx\n2) file.pdf"
    )
  } else {
    paste0(
      "\n\nCRITICAL CITATION REQUIREMENT: ",
      "If you reference any sources, include a 'Kaynakça:' section at the end. ",
      "Do NOT use inline [Source: ...] citations. "
    )
  }
}

mergen_prepare_send_message_prompting <- function(tool_family,
                                                  uploaded_count,
                                                  settings_data,
                                                  messages_to_process) {
  # Opsiyonel performans ölçümü (yalnızca MERGEN_PERF_LOG açıkken aktiftir).
  .perf_start <- if (exists("mergen_perf_now", mode = "function", inherits = TRUE)) mergen_perf_now() else NULL
  if (!is.null(.perf_start)) on.exit(mergen_perf_log("send_message.prompt_plan", .perf_start), add = TRUE)

  selected_char_id <- normalize_character_id(settings_data$selected_character)
  chars_data <- get_characters_data()

  character_data <- if (!is.null(chars_data)) {
    Find(function(x) x$id == selected_char_id, chars_data$styles)
  } else {
    NULL
  }

  base_instruction <- if (!is.null(character_data)) {
    character_data$system_prompt_en
  } else {
    "Be a balanced, pragmatic assistant. Provide clear, actionable responses."
  }

  citation_instruction <- mergen_build_citation_instruction(uploaded_count)

  if (identical(tool_family, "summarization") && uploaded_count > 0) {
    style_instruction <- build_summarization_system_prompt(
      file_count = uploaded_count,
      total_chars = 0
    )
  } else if (isTRUE(settings_data$enable_coding_tools)) {
    style_instruction <- paste0(
      base_instruction,
      "\n\nKODLAMA UZMANI MODU AKTİF:\n",
      "You are an expert software development assistant specializing in code optimization, debugging, and best practices.\n\n",
      "YOUR CAPABILITIES:\n",
      "- Code review and optimization across multiple languages (Python, R, JavaScript, Java, C++, Go, etc.)\n",
      "- Algorithm design and complexity analysis\n",
      "- Debugging and error resolution\n",
      "- Performance optimization and refactoring\n",
      "- Best practices and design patterns\n",
      "- Unit testing and test-driven development\n",
      "- Code documentation and maintainability\n\n",
      "YOUR APPROACH:\n",
      "- Provide clean, efficient, production-ready code\n",
      "- Explain your reasoning and trade-offs\n",
      "- Suggest multiple solutions when applicable\n",
      "- Follow language-specific conventions and style guides\n",
      "- Prioritize readability, maintainability, and performance\n",
      "- Include inline comments for complex logic\n",
      "- Consider edge cases and error handling\n\n",
      "RESPONSE FORMAT:\n",
      "- Use proper markdown code blocks with language specification\n",
      "- Provide clear explanations before and after code\n",
      "- Highlight key improvements or changes\n",
      "- Suggest testing strategies when relevant",
      citation_instruction
    )
  } else if (isTRUE(settings_data$enable_image_tools)) {
    style_instruction <- paste0(
      base_instruction,
      "\n\nGÖRSEL OLUŞTURMA MODU:\n",
      "Kullanıcının isteğine göre görsel oluşturulacak.",
      citation_instruction
    )
  } else {
    style_instruction <- paste0(base_instruction, citation_instruction)
  }

  temperature_value <- if (!is.null(character_data) &&
                           !is.null(character_data$parameters$temperature)) {
    character_data$parameters$temperature
  } else {
    0.4
  }

  system_msg <- list(type = "system", content = style_instruction)

  if (identical(tool_family, "sql_analysis") &&
      length(messages_to_process) > 0 &&
      identical(
        tolower(as.character(messages_to_process[[1]]$role %||% messages_to_process[[1]]$type %||% "")),
        "system"
      )) {

    mevcut_system_icerik <- as.character(messages_to_process[[1]]$content %||% "")
    messages_to_process[[1]]$content <- paste0(style_instruction, "\n\n", mevcut_system_icerik)
    messages_to_process[[1]]$type <- "system"
    messages_to_process[[1]]$role <- "system"

  } else {
    messages_to_process <- c(list(system_msg), messages_to_process)
  }

  list(
    messages_to_process = messages_to_process,
    system_msg = system_msg,
    selected_char_id = selected_char_id,
    temperature_value = temperature_value,
    style_instruction = style_instruction
  )
}

mergen_build_uploaded_files_context_messages <- function(tool_family,
                                                         uploaded_count,
                                                         uploaded_names,
                                                         recent_messages,
                                                         system_msg,
                                                         session,
                                                         messages_to_process,
                                                         model_selected = NULL,
                                                         api_config = NULL) {
  # Opsiyonel performans ölçümü (yalnızca MERGEN_PERF_LOG açıkken aktiftir).
  .perf_start <- if (exists("mergen_perf_now", mode = "function", inherits = TRUE)) mergen_perf_now() else NULL
  if (!is.null(.perf_start)) on.exit(mergen_perf_log("send_message.file_context", .perf_start), add = TRUE)

  if (identical(tool_family, "mcp_excel") && uploaded_count > 0) {
    file_list_text <- paste0(
      "\n\nDOSYA BİLGİSİ:\n",
      "Toplam ", uploaded_count, " dosya yüklü:\n",
      paste(paste0("- ", uploaded_names), collapse = "\n"),
      "\n\nÖNEMLİ: Bu dosyaları analiz etmek için MUTLAKA 'analyze_uploaded_file' veya 'get_column_statistics' veya 'sql_query_uploaded_file' araçlarını kullan. ",
      "Dosya içeriğini TAHMİN ETME, araçları kullan!"
    )

    user_question <- tail(recent_messages, 1)[[1]]$content
    citation_files_list <- paste(paste0(seq_along(uploaded_names), ") ", uploaded_names), collapse = "\n")

    final_context_prompt <- list(
      type = "user",
      content = paste0(
        "Aşağıdaki dosya bağlamını kullanarak soruyu yanıtla.\n\n",
        "[ Toplam Dosya Sayısı: ", uploaded_count, " ]\n",
        file_list_text,
        "\n\n--- BAĞLAM SONU ---\n\n",
        "ZORUNLU TALİMAT: Yanıtının EN SONUNDA aşağıdaki formatı AYNEN kullan:\n\n",
        "Kaynakça:\n",
        citation_files_list,
        "\n\nSoru: ", user_question
      )
    )

    return(list(
      messages_to_process = c(list(system_msg), head(recent_messages, -1), list(final_context_prompt))
    ))
  }

  if (identical(tool_family, "none") && uploaded_count > 0) {
    total_budget <- 120000
    per_file_cap <- max(4000, floor(total_budget / max(1, uploaded_count)))

    summary_store <- session_user_data_get_list(session, "file_summaries")
    current_file_store <- session_user_data_get_list(session, "current_session_files")

    # Vision yalnızca bayrak + model yeteneği birlikte açıkken aktiftir; aksi
    # halde metin yolu birebir korunur ve görseller için açık not eklenir.
    vision_active <- mergen_vision_active(model_selected, api_config)

    blocks <- mergen_vision_prepare_context_blocks(
      uploaded_names = uploaded_names,
      summary_store = summary_store,
      current_file_store = current_file_store,
      per_file_cap = per_file_cap,
      vision_active = vision_active
    )
    file_blocks <- blocks$file_blocks
    image_data_urls <- blocks$image_data_urls

    citation_files_list <- paste(paste0(seq_along(uploaded_names), ") ", uploaded_names), collapse = "\n")
    user_question <- tail(recent_messages, 1)[[1]]$content

    context_text <- paste0(
      "Aşağıdaki dosya özetlerini ve/veya alıntılarını kullanarak isteği yanıtla. Araç KULLANILMAYACAKTIR (MCP kapalı).\n\n",
      paste(file_blocks, collapse = "\n\n"),
      "\n\nSoru: ", user_question,
      "\n\nKaynakça:\n", citation_files_list
    )

    # Vision aktif ve gerçekten kodlanmış görsel varsa kullanıcı içeriği OpenAI
    # uyumlu çok-kipli diziye dönüşür; aksi halde metin (string) olarak kalır.
    final_content <- if (isTRUE(vision_active) && length(image_data_urls) > 0) {
      mergen_build_vision_user_content(context_text, image_data_urls)
    } else {
      context_text
    }

    final_context_prompt <- list(
      type = "user",
      content = final_content
    )

    return(list(
      messages_to_process = c(list(system_msg), head(recent_messages, -1), list(final_context_prompt))
    ))
  }

  if (identical(tool_family, "sql_analysis")) {
    return(list(messages_to_process = messages_to_process))
  }

  list(
    messages_to_process = c(list(system_msg), recent_messages)
  )
}