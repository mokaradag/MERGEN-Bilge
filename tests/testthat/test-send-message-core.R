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

# Kodlama Desteği aracı aktif + dosya yok senaryosunda tool_family 'coding'.
test_that("mergen_determine_tool_family coding aracı seçildiğinde 'coding' döner", {
  settings_data <- list(
    enable_mcp_tools         = FALSE,
    enable_rdata_tools       = FALSE,
    enable_summarization_tools = FALSE,
    enable_coding_tools      = TRUE,
    enable_process_tools     = FALSE,
    enable_app_expert_tools  = FALSE,
    enable_image_tools       = FALSE
  )

  result <- mergen_determine_tool_family(
    settings_data = settings_data,
    uploaded_count = 0,
    skip_mcp_once = FALSE,
    current_settings = list()
  )

  expect_identical(result$tool_family, "coding")
})

# Görsel üretim aracı aktifken image tool family seçilmelidir.
test_that("mergen_determine_tool_family görsel aracı aktifken image tool_family döner", {
  settings_data <- list(
    enable_mcp_tools         = FALSE,
    enable_rdata_tools       = FALSE,
    enable_summarization_tools = FALSE,
    enable_coding_tools      = FALSE,
    enable_process_tools     = FALSE,
    enable_app_expert_tools  = FALSE,
    enable_image_tools       = TRUE
  )

  result <- mergen_determine_tool_family(
    settings_data = settings_data,
    uploaded_count = 0,
    skip_mcp_once = FALSE,
    current_settings = list()
  )

  expect_identical(result$tool_family, "image")
})

# Düşünmeli SQL/Proje analizi akış planı (mergen_sql_analysis_stream_plan).
# Düşünmeli SQL analizi artık akış AÇIKKEN canlı SSE Düşünce Akışı ile çalışır
# ve non-streaming güvenlik ağı açılır; TTS/akış-kapalı/MCP durumlarında eski
# güvenli non-streaming korunur. Bu, force_non_streaming_sql kararını yönetir.
test_that("mergen_sql_analysis_stream_plan düşünmeli SQL analizini canlı SSE'ye yönlendirir", {
  # Akış açık, TTS/MCP kapalı, düşünmeli model -> gerçek SSE + güvenlik ağı.
  p <- mergen_sql_analysis_stream_plan(
    tool_family = "sql_analysis", thinking_model = TRUE,
    enable_streaming = TRUE, enable_mcp_tools = FALSE, enable_tts_audio = FALSE
  )
  expect_true(p$is_sql_thinking)
  expect_true(p$allow_non_streaming_fallback)
  expect_false(p$force_non_streaming)
})

test_that("mergen_sql_analysis_stream_plan TTS/akış-kapalı/MCP durumunda non-streaming kalır", {
  # TTS açık -> non-streaming (TTS yolu reasoning'i gerçek SSE gibi akıtmaz).
  tts <- mergen_sql_analysis_stream_plan(
    "sql_analysis", TRUE, enable_streaming = TRUE,
    enable_mcp_tools = FALSE, enable_tts_audio = TRUE
  )
  expect_true(tts$force_non_streaming)
  expect_false(tts$allow_non_streaming_fallback)

  # Akış kapalı -> non-streaming.
  off <- mergen_sql_analysis_stream_plan(
    "sql_analysis", TRUE, enable_streaming = FALSE,
    enable_mcp_tools = FALSE, enable_tts_audio = FALSE
  )
  expect_true(off$force_non_streaming)

  # MCP açık -> bu düşünmeli SQL akışı için non-streaming.
  mcp <- mergen_sql_analysis_stream_plan(
    "sql_analysis", TRUE, enable_streaming = TRUE,
    enable_mcp_tools = TRUE, enable_tts_audio = FALSE
  )
  expect_true(mcp$force_non_streaming)
  expect_false(mcp$allow_non_streaming_fallback)
})

test_that("mergen_sql_analysis_stream_plan SQL olmayan/düşünmeyen akışları değiştirmez", {
  # Düşünmeyen SQL analizi: zorla non-streaming YOK, güvenlik ağı YOK.
  nonthink <- mergen_sql_analysis_stream_plan(
    "sql_analysis", FALSE, enable_streaming = TRUE,
    enable_mcp_tools = FALSE, enable_tts_audio = FALSE
  )
  expect_false(nonthink$is_sql_thinking)
  expect_false(nonthink$force_non_streaming)
  expect_false(nonthink$allow_non_streaming_fallback)

  # Normal sohbet (none): hiçbir şey zorlanmaz.
  none <- mergen_sql_analysis_stream_plan(
    "none", TRUE, enable_streaming = TRUE,
    enable_mcp_tools = FALSE, enable_tts_audio = FALSE
  )
  expect_false(none$force_non_streaming)
  expect_false(none$allow_non_streaming_fallback)
})