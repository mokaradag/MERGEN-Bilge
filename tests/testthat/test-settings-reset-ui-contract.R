# ==============================================================================
# Dosya Yolu: tests/testthat/test-settings-reset-ui-contract.R
# Aciklama: Yapilandirma reset akisinin gorunur UI girdilerini
#           varsayilanlara geri senkronize ettigini statik sozlesmeyle korur.
#           App, tarayici, DB veya LLM baslatmaz.
# ==============================================================================

testthat::local_edition(3)

.find_repo_root_settings_reset_contract <- function() {
  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        file.exists(file.path(candidate, "R", "module_settings.R"))) {
      return(candidate)
    }
  }

  stop("Repo koku bulunamadi.", call. = FALSE)
}

.read_settings_module_reset_contract <- function() {
  path <- file.path(.find_repo_root_settings_reset_contract(), "R", "module_settings.R")
  rawToChar(readBin(path, what = "raw", n = file.info(path)$size))
}

test_that("settings reset syncs visible inputs to defaults", {
  text <- .read_settings_module_reset_contract()

  expected_inputs <- c(
    "model_selection",
    "font_size",
    "ai_expert_talk_length",
    "ai_expert_talk_frequency",
    "ai_expert_talk_style",
    "image_size",
    "summary_detail_level",
    "summary_focus_mode",
    "analysis_detail_level",
    "claude_code_timeout",
    "music_volume",
    "enable_timestamps",
    "enable_typing_indicator",
    "enable_animations",
    "enable_widescreen",
    "enable_streaming",
    "enable_tool_backgrounds",
    "enable_followups",
    "show_intro_animation",
    "enable_tts_audio",
    "enable_background_music",
    "enable_ai_expert",
    "enable_rdata_tools",
    "enable_mcp_tools",
    "enable_summarization_tools",
    "enable_coding_tools",
    "enable_process_tools",
    "enable_app_expert_tools",
    "enable_image_tools",
    "image_quality_hd",
    "analysis_deep_thinking"
  )

  missing_inputs <- expected_inputs[!vapply(
    expected_inputs,
    function(input_id) grepl(sprintf('"%s"', input_id), text, fixed = TRUE),
    logical(1)
  )]

  testthat::expect_equal(
    missing_inputs,
    character(0),
    info = paste(
      "Settings reset must update visible configuration inputs. Missing:",
      paste(missing_inputs, collapse = ", ")
    )
  )
})

test_that("custom switch resets clear DOM checked state and Shiny input value", {
  text <- .read_settings_module_reset_contract()

  for (input_id in c("image_quality_hd", "analysis_deep_thinking")) {
    testthat::expect_true(
      grepl(input_id, text, fixed = TRUE) &&
        grepl("prop('checked', false).trigger('change')", text, fixed = TRUE),
      info = paste(input_id, "custom switch reset must keep DOM checked=false and change trigger.")
    )
  }
})
