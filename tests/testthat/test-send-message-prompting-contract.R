# ==============================================================================
# Dosya Yolu: tests/testthat/test-send-message-prompting-contract.R
# Açıklama: send_message prompt/style ve dosya bağlamı helper sözleşmelerini doğrular.
# ==============================================================================

repo_root_send_message_prompting <- resolve_repo_root_for_tests()

source(file.path(repo_root_send_message_prompting, "R/utils_common.R"), encoding = "UTF-8", local = globalenv())
source(file.path(repo_root_send_message_prompting, "R/utils_session_cleanup.R"), encoding = "UTF-8", local = globalenv())
source(file.path(repo_root_send_message_prompting, "R/helpers_send_message_prompting.R"), encoding = "UTF-8", local = globalenv())

.with_send_message_prompting_stubs <- function(code) {
  old_chars_exists <- exists("get_characters_data", envir = globalenv(), inherits = FALSE)
  old_summary_exists <- exists("build_summarization_system_prompt", envir = globalenv(), inherits = FALSE)

  old_chars <- if (old_chars_exists) get("get_characters_data", envir = globalenv()) else NULL
  old_summary <- if (old_summary_exists) get("build_summarization_system_prompt", envir = globalenv()) else NULL

  on.exit({
    if (old_chars_exists) {
      assign("get_characters_data", old_chars, envir = globalenv())
    } else if (exists("get_characters_data", envir = globalenv(), inherits = FALSE)) {
      rm("get_characters_data", envir = globalenv())
    }

    if (old_summary_exists) {
      assign("build_summarization_system_prompt", old_summary, envir = globalenv())
    } else if (exists("build_summarization_system_prompt", envir = globalenv(), inherits = FALSE)) {
      rm("build_summarization_system_prompt", envir = globalenv())
    }
  }, add = TRUE)

  assign(
    "get_characters_data",
    function() {
      list(
        styles = list(
          list(
            id = "emre",
            system_prompt_en = "BASE_PROMPT",
            parameters = list(temperature = 0.7)
          )
        )
      )
    },
    envir = globalenv()
  )

  assign(
    "build_summarization_system_prompt",
    function(file_count, total_chars) {
      paste0("SUMMARY_PROMPT file_count=", file_count, " total_chars=", total_chars)
    },
    envir = globalenv()
  )

  force(code)
}

test_that("send message style helper karakter, sıcaklık ve kaynakça sözleşmesini korur", {
  .with_send_message_prompting_stubs({
    plan <- mergen_prepare_send_message_prompting(
      tool_family = "none",
      uploaded_count = 2L,
      settings_data = list(
        selected_character = "emre",
        enable_coding_tools = FALSE,
        enable_image_tools = FALSE
      ),
      messages_to_process = list(
        list(type = "user", content = "Merhaba dünya")
      )
    )

    expect_identical(plan$selected_char_id, "emre")
    expect_identical(plan$temperature_value, 0.7)
    expect_identical(plan$messages_to_process[[1]]$type, "system")
    expect_match(plan$messages_to_process[[1]]$content, "BASE_PROMPT", fixed = TRUE)
    expect_match(plan$messages_to_process[[1]]$content, "Kaynakça:", fixed = TRUE)
    expect_match(plan$messages_to_process[[1]]$content, "Do NOT use inline \\[Source:", perl = TRUE)
  })
})

test_that("send message style helper SQL system promptunu çoğaltmadan birleştirir", {
  .with_send_message_prompting_stubs({
    plan <- mergen_prepare_send_message_prompting(
      tool_family = "sql_analysis",
      uploaded_count = 0L,
      settings_data = list(
        selected_character = "emre",
        enable_coding_tools = FALSE,
        enable_image_tools = FALSE
      ),
      messages_to_process = list(
        list(role = "system", content = "SQL_CONTEXT"),
        list(type = "user", content = "Proje durumunu özetle")
      )
    )

    expect_length(plan$messages_to_process, 2L)
    expect_identical(plan$messages_to_process[[1]]$role, "system")
    expect_identical(plan$messages_to_process[[1]]$type, "system")
    expect_match(plan$messages_to_process[[1]]$content, "BASE_PROMPT", fixed = TRUE)
    expect_match(plan$messages_to_process[[1]]$content, "SQL_CONTEXT", fixed = TRUE)
  })
})

test_that("MCP Excel dosya bağlamı araç kullanma ve kaynakça talimatını korur", {
  recent_messages <- list(
    list(type = "user", content = "Önceki soru"),
    list(type = "user", content = "Tabloyu özetle")
  )

  context_plan <- mergen_build_uploaded_files_context_messages(
    tool_family = "mcp_excel",
    uploaded_count = 2L,
    uploaded_names = c("rapor.xlsx", "özet.xlsx"),
    recent_messages = recent_messages,
    system_msg = list(type = "system", content = "SYS"),
    session = NULL,
    messages_to_process = recent_messages
  )

  final_prompt <- context_plan$messages_to_process[[3]]$content

  expect_length(context_plan$messages_to_process, 3L)
  expect_match(final_prompt, "DOSYA BİLGİSİ", fixed = TRUE)
  expect_match(final_prompt, "analyze_uploaded_file", fixed = TRUE)
  expect_match(final_prompt, "rapor.xlsx", fixed = TRUE)
  expect_match(final_prompt, "Kaynakça:", fixed = TRUE)
  expect_match(final_prompt, "Soru: Tabloyu özetle", fixed = TRUE)
})

test_that("MCP kapalı dosya bağlamı oturum özetlerini ve Türkçe kaynakçayı korur", {
  session <- list(userData = new.env(parent = emptyenv()))
  session$userData$file_summaries <- list(
    "özet.pdf" = "Türkçe özet metni"
  )
  session$userData$current_session_files <- list()

  recent_messages <- list(
    list(type = "user", content = "Dosyayı açıkla")
  )

  context_plan <- mergen_build_uploaded_files_context_messages(
    tool_family = "none",
    uploaded_count = 1L,
    uploaded_names = c("özet.pdf"),
    recent_messages = recent_messages,
    system_msg = list(type = "system", content = "SYS"),
    session = session,
    messages_to_process = recent_messages
  )

  final_prompt <- context_plan$messages_to_process[[2]]$content

  expect_length(context_plan$messages_to_process, 2L)
  expect_match(final_prompt, "Araç KULLANILMAYACAKTIR", fixed = TRUE)
  expect_match(final_prompt, "Türkçe özet metni", fixed = TRUE)
  expect_match(final_prompt, "Kaynakça:\n1) özet.pdf", fixed = TRUE)
})