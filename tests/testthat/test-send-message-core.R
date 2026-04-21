# ==============================================================================
# Dosya Yolu: tests/testthat/test-send-message-core.R
# Açıklama: send_message çekirdeğindeki araç ailesi seçimi ve akış profili
# üretimi kararlarını doğrulayan birim testlerini içerir.
# ==============================================================================

# SQL analizi aktifken araç ailesi önceliğinin doğru belirlendiğini doğrular.
test_that("mergen_determine_tool_family SQL modunu önceliklendirir", {
  settings_data <- list(
    enable_mcp_tools = TRUE,
    enable_rdata_tools = TRUE,
    enable_summarization_tools = FALSE,
    enable_coding_tools = FALSE,
    enable_process_tools = FALSE,
    enable_app_expert_tools = FALSE,
    enable_image_tools = FALSE
  )

  current_settings <- list()

  result <- mergen_determine_tool_family(
    settings_data = settings_data,
    uploaded_count = 2,
    skip_mcp_once = FALSE,
    current_settings = current_settings
  )

  expect_identical(result$tool_family, "sql_analysis")
  expect_identical(result$current_settings$max_output_tokens, 4096)
})

# MCP modunun yalnızca dosya yüklemesi olduğunda seçildiğini doğrular.
test_that("mergen_determine_tool_family MCP modunu sadece dosya varsa seçer", {
  settings_data <- list(
    enable_mcp_tools = TRUE,
    enable_rdata_tools = FALSE,
    enable_summarization_tools = FALSE,
    enable_coding_tools = FALSE,
    enable_process_tools = FALSE,
    enable_app_expert_tools = FALSE,
    enable_image_tools = FALSE
  )

  result_no_file <- mergen_determine_tool_family(
    settings_data = settings_data,
    uploaded_count = 0,
    skip_mcp_once = FALSE,
    current_settings = list()
  )

  result_with_file <- mergen_determine_tool_family(
    settings_data = settings_data,
    uploaded_count = 1,
    skip_mcp_once = FALSE,
    current_settings = list()
  )

  expect_identical(result_no_file$tool_family, "none")
  expect_identical(result_with_file$tool_family, "mcp_excel")
})

# Quick action skip işaretinde tüm araç kararlarının bypass edildiğini doğrular.
test_that("mergen_determine_tool_family quick action skip durumunda none döndürür", {
  settings_data <- list(
    enable_mcp_tools = TRUE,
    enable_rdata_tools = TRUE,
    enable_summarization_tools = TRUE,
    enable_coding_tools = TRUE,
    enable_process_tools = TRUE,
    enable_app_expert_tools = TRUE,
    enable_image_tools = TRUE
  )

  result <- mergen_determine_tool_family(
    settings_data = settings_data,
    uploaded_count = 5,
    skip_mcp_once = TRUE,
    current_settings = list()
  )

  expect_identical(result$tool_family, "none")
})

# Basit sohbet koşullarında hızlı akış profilinin seçildiğini doğrular.
test_that("mergen_build_stream_profile basit sohbet için plain_fast döndürür", {
  settings_data <- list(enable_tts_audio = FALSE)

  result <- mergen_build_stream_profile(
    tool_family = "none",
    uploaded_count = 0,
    settings_data = settings_data,
    force_non_streaming_sql = FALSE
  )

  expect_identical(result$label, "plain_fast")
  expect_identical(result$use_delta_transport, TRUE)
  expect_identical(result$poll_interval_ms, 15L)
})

# Zorunlu non-streaming bayrağında standard profilin korunduğunu doğrular.
test_that("mergen_build_stream_profile zorunlu non-streaming durumda standard kalır", {
  settings_data <- list(enable_tts_audio = FALSE)

  result <- mergen_build_stream_profile(
    tool_family = "coding",
    uploaded_count = 0,
    settings_data = settings_data,
    force_non_streaming_sql = TRUE
  )

  expect_identical(result$label, "standard")
  expect_identical(result$use_delta_transport, FALSE)
  expect_identical(result$poll_interval_ms, 50L)
})