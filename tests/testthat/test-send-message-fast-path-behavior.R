# ==============================================================================
# Dosya Yolu: tests/testthat/test-send-message-fast-path-behavior.R
# Açıklama: "Düz hızlı sohbet" yolu kararını (mergen_is_plain_fast_chat) ve
#           worker ayar yükü küçültücüsünü (mergen_sanitize_llm_settings_for_worker)
#           doğrulayan DAVRANIŞSAL testler. Gerçek üretim fonksiyonları çağrılır;
#           Shiny/DB/ağ/LLM GEREKMEZ.
# ==============================================================================

# Çekirdek yardımcılar helper-load-app.R ile global ortama yüklenir; izole
# çalıştırmada eksikse working-directory bağımsız olarak yüklenir.
.fastpath_source_once <- function() {
  if (exists("mergen_is_plain_fast_chat", mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_send_message_core.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# mergen_is_plain_fast_chat
# ------------------------------------------------------------------------------
testthat::test_that("mergen_is_plain_fast_chat normal sohbet/dosya yok/streaming için TRUE", {
  .fastpath_source_once()
  testthat::expect_true(mergen_is_plain_fast_chat(
    tool_family = "none",
    uploaded_count = 0L,
    current_settings = list(enable_streaming = TRUE),
    settings_data = list(enable_tts_audio = FALSE),
    force_non_streaming_sql = FALSE
  ))
})

testthat::test_that("mergen_is_plain_fast_chat dosya yüklendiğinde FALSE", {
  .fastpath_source_once()
  testthat::expect_false(mergen_is_plain_fast_chat(
    tool_family = "none",
    uploaded_count = 2L,
    current_settings = list(enable_streaming = TRUE),
    settings_data = list(enable_tts_audio = FALSE)
  ))
})

testthat::test_that("mergen_is_plain_fast_chat MCP açıkken FALSE", {
  .fastpath_source_once()
  testthat::expect_false(mergen_is_plain_fast_chat(
    tool_family = "none",
    uploaded_count = 0L,
    current_settings = list(enable_streaming = TRUE, enable_mcp_tools = TRUE),
    settings_data = list(enable_tts_audio = FALSE)
  ))
})

testthat::test_that("mergen_is_plain_fast_chat TTS açıkken FALSE", {
  .fastpath_source_once()
  testthat::expect_false(mergen_is_plain_fast_chat(
    tool_family = "none",
    uploaded_count = 0L,
    current_settings = list(enable_streaming = TRUE),
    settings_data = list(enable_tts_audio = TRUE)
  ))
})

testthat::test_that("mergen_is_plain_fast_chat streaming kapalıyken FALSE", {
  .fastpath_source_once()
  testthat::expect_false(mergen_is_plain_fast_chat(
    tool_family = "none",
    uploaded_count = 0L,
    current_settings = list(enable_streaming = FALSE),
    settings_data = list(enable_tts_audio = FALSE)
  ))
})

testthat::test_that("mergen_is_plain_fast_chat araç modlarında (sql/coding/image/...) FALSE", {
  .fastpath_source_once()
  cs <- list(enable_streaming = TRUE)
  sd <- list(enable_tts_audio = FALSE)

  for (fam in c("sql_analysis", "coding", "mcp_excel", "summarization", "image", "process", "app_expert")) {
    testthat::expect_false(
      mergen_is_plain_fast_chat(fam, 0L, cs, sd),
      info = sprintf("tool_family=%s düz hızlı sohbet OLMAMALI", fam)
    )
  }
})

testthat::test_that("mergen_is_plain_fast_chat SQL non-streaming zorlamasında FALSE", {
  .fastpath_source_once()
  testthat::expect_false(mergen_is_plain_fast_chat(
    tool_family = "none",
    uploaded_count = 0L,
    current_settings = list(enable_streaming = TRUE),
    settings_data = list(enable_tts_audio = FALSE),
    force_non_streaming_sql = TRUE
  ))
})

# Yönlendirme sözleşmesi: düz hızlı sohbeti TRUE yapan koşullar, aynı zamanda
# server_send_message.R'deki GERÇEK SSE (handle_true_streaming_mode) dalının
# koşullarını da sağlamalıdır. Bu, normal sohbetin yanlışlıkla non-streaming
# veya TTS-simülasyon yoluna düşmemesini korur.
testthat::test_that("düz hızlı sohbet koşulları gerçek SSE dalını sağlar", {
  .fastpath_source_once()
  cs <- list(enable_streaming = TRUE, enable_mcp_tools = FALSE)
  sd <- list(enable_tts_audio = FALSE)
  force_non_streaming_sql <- FALSE

  testthat::expect_true(mergen_is_plain_fast_chat("none", 0L, cs, sd, force_non_streaming_sql))

  # server_send_message.R'deki gerçek SSE dal koşulu (birebir mantık):
  true_sse_branch <- isTRUE(cs$enable_streaming) &&
    !isTRUE(cs$enable_mcp_tools) &&
    !isTRUE(sd$enable_tts_audio) &&
    !isTRUE(force_non_streaming_sql)
  testthat::expect_true(true_sse_branch)
})

# ------------------------------------------------------------------------------
# mergen_sanitize_llm_settings_for_worker
# ------------------------------------------------------------------------------
testthat::test_that("sanitize_llm_settings_for_worker Shiny oturumunu her zaman çıkarır", {
  .fastpath_source_once()
  settings <- list(
    model_selection = "m1",
    shiny_session = list(token = "abc"),
    temperature = 0.4
  )

  # Düz hızlı olmasa bile oturum çıkarılır.
  out <- mergen_sanitize_llm_settings_for_worker(settings, plain_fast = FALSE)
  testthat::expect_null(out$shiny_session)
  testthat::expect_identical(out$model_selection, "m1")
  testthat::expect_identical(out$temperature, 0.4)
})

testthat::test_that("sanitize_llm_settings_for_worker düz hızlı sohbette ağır alanları atar, gerekli alanları korur", {
  .fastpath_source_once()
  settings <- list(
    model_selection = "m1",
    temperature = 0.7,
    max_output_tokens = 2048L,
    api_key_override = "fake-key",
    api_key_source = "personal",
    request_start_unix = 123456,
    future_submit_unix = 123457,
    allow_non_streaming_fallback = TRUE,
    enable_streaming = TRUE,
    shiny_session = list(token = "abc"),
    current_session_files = list(a = 1),
    mcp_registry_snapshot = list(b = 2),
    mcp_snapshot = list(c = 3),
    file_paths = list(d = 4),
    uploaded_files = c("x.txt"),
    user_config = list(name = "Test")
  )

  out <- mergen_sanitize_llm_settings_for_worker(settings, plain_fast = TRUE)

  # Ağır/gereksiz alanlar atılır.
  testthat::expect_null(out$shiny_session)
  testthat::expect_null(out$current_session_files)
  testthat::expect_null(out$mcp_registry_snapshot)
  testthat::expect_null(out$mcp_snapshot)
  testthat::expect_null(out$file_paths)
  testthat::expect_null(out$uploaded_files)
  testthat::expect_null(out$user_config)

  # Worker'ın ihtiyaç duyduğu alanlar korunur.
  testthat::expect_identical(out$model_selection, "m1")
  testthat::expect_identical(out$temperature, 0.7)
  testthat::expect_identical(out$max_output_tokens, 2048L)
  testthat::expect_identical(out$api_key_override, "fake-key")
  testthat::expect_identical(out$request_start_unix, 123456)
  testthat::expect_identical(out$future_submit_unix, 123457)
  testthat::expect_true(isTRUE(out$allow_non_streaming_fallback))
})

testthat::test_that("sanitize_llm_settings_for_worker düz hızlı DEĞİLKEN ağır alanları korur", {
  .fastpath_source_once()
  settings <- list(
    model_selection = "m1",
    mcp_registry_snapshot = list(b = 2),
    file_paths = list(d = 4)
  )

  out <- mergen_sanitize_llm_settings_for_worker(settings, plain_fast = FALSE)

  # Düz hızlı değilse (örn. MCP/Excel) bu alanlar worker için gereklidir.
  testthat::expect_identical(out$mcp_registry_snapshot, list(b = 2))
  testthat::expect_identical(out$file_paths, list(d = 4))
})

testthat::test_that("sanitize_llm_settings_for_worker liste olmayan girdide güvenli list döner", {
  .fastpath_source_once()
  out <- mergen_sanitize_llm_settings_for_worker(NULL, plain_fast = TRUE)
  testthat::expect_true(is.list(out))
  testthat::expect_null(out$shiny_session)
})
