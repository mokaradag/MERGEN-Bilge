# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-sse-events-behavior.R
# Açıklama: SSE olay/delta ayrıştırma yardımcılarının davranışsal testleri.
#           decode_utf8_raw_chunk (ham bayt -> UTF-8 metin) ve
#           extract_llm_delta_text (çeşitli delta şekillerinden içerik) doğrulanır.
#           Saf, yan etkisiz ayrıştırma katmanıdır; DB/LLM/ağ/tarayıcı gerekmez.
# ==============================================================================

.llm_sse_events_source_once <- function() {
  if (exists("decode_utf8_raw_chunk", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("extract_llm_delta_text", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("extract_first_nonempty_llm_text", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  # extract_llm_delta_bundle extract_first_nonempty_llm_text'e (postprocess)
  # bağımlıdır.
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_llm_response_postprocess.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_llm_sse_events.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

testthat::test_that("decode_utf8_raw_chunk ham baytları güvenli UTF-8 metne çevirir", {
  .llm_sse_events_source_once()

  testthat::expect_identical(decode_utf8_raw_chunk(raw(0)), "")
  testthat::expect_identical(decode_utf8_raw_chunk(charToRaw("merhaba")), "merhaba")
  testthat::expect_identical(decode_utf8_raw_chunk(charToRaw("test 123")), "test 123")
})

testthat::test_that("extract_llm_delta_text çeşitli delta şekillerinden içerik çıkarır", {
  .llm_sse_events_source_once()

  # choices[[1]]$delta$content
  testthat::expect_identical(
    extract_llm_delta_text(list(choices = list(list(delta = list(content = "abc"))))),
    "abc"
  )
  # Üst düzey delta$content
  testthat::expect_identical(
    extract_llm_delta_text(list(delta = list(content = "xyz"))),
    "xyz"
  )
  # Üst düzey content
  testthat::expect_identical(
    extract_llm_delta_text(list(content = "duz")),
    "duz"
  )
  # Liste olmayan girdi -> boş.
  testthat::expect_identical(extract_llm_delta_text("metin degil liste"), "")
})
