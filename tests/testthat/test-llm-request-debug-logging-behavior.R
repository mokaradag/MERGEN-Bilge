# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-request-debug-logging-behavior.R
# Açıklama: mergen_log_llm_request_debug() ve mergen_log_chat_perf_summary()
#           davranışsal testleri. Kritik yol dostu loglama: varsayılan olarak
#           yalnızca hafif sayım/boyut özeti yazılır; tam döküm yalnızca açık
#           tanılama bayrağıyla üretilir. Sır/istem gövdesi varsayılan loglanmaz.
# ==============================================================================

.llmdbg_source_once <- function() {
  if (exists("mergen_log_llm_request_debug", mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_performance_instrumentation.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# log_info/dbg_dump yakalayıcılarını kurar ve eski hallerini geri yükler.
.llmdbg_with_captures <- function(expr) {
  logs <- character()
  dumps <- list()

  old_log <- if (exists("log_info", envir = .GlobalEnv, inherits = FALSE)) get("log_info", envir = .GlobalEnv) else NULL
  old_dump <- if (exists("dbg_dump", envir = .GlobalEnv, inherits = FALSE)) get("dbg_dump", envir = .GlobalEnv) else NULL

  assign("log_info", function(msg, ...) logs[[length(logs) + 1L]] <<- as.character(msg)[1], envir = .GlobalEnv)
  assign("dbg_dump", function(label, payload) dumps[[length(dumps) + 1L]] <<- list(label = label, payload = payload), envir = .GlobalEnv)

  on.exit({
    if (is.null(old_log)) rm("log_info", envir = .GlobalEnv) else assign("log_info", old_log, envir = .GlobalEnv)
    if (is.null(old_dump)) rm("dbg_dump", envir = .GlobalEnv) else assign("dbg_dump", old_dump, envir = .GlobalEnv)
  }, add = TRUE)

  force(expr)
  list(logs = logs, dumps = dumps)
}

testthat::test_that("varsayılan: yalnızca hafif özet yazılır, tam döküm yapılmaz", {
  .llmdbg_source_once()
  old_env <- Sys.getenv("MERGEN_LLM_REQUEST_DEBUG", unset = NA_character_)
  old_dbg <- Sys.getenv("MERGEN_DEBUG", unset = NA_character_)
  on.exit({
    if (is.na(old_env)) Sys.unsetenv("MERGEN_LLM_REQUEST_DEBUG") else Sys.setenv(MERGEN_LLM_REQUEST_DEBUG = old_env)
    if (is.na(old_dbg)) Sys.unsetenv("MERGEN_DEBUG") else Sys.setenv(MERGEN_DEBUG = old_dbg)
  }, add = TRUE)
  Sys.unsetenv("MERGEN_LLM_REQUEST_DEBUG")
  Sys.setenv(MERGEN_DEBUG = "FALSE")

  msgs <- list(
    list(content = "merhaba"),          # 7 karakter
    list(content = "dunya selam")       # 11 karakter
  )

  res <- .llmdbg_with_captures(
    mergen_log_llm_request_debug(
      "LLM_REQUEST_TRUE_STREAMING", "model-x", msgs,
      list(max_output_tokens = 4096L, api_key_override = "fake-secret-xyz")
    )
  )

  # Hafif özet satırı yazıldı.
  testthat::expect_true(any(grepl("LLM istek ozeti", res$logs, fixed = TRUE)))
  testthat::expect_true(any(grepl("mesaj=2", res$logs, fixed = TRUE)))
  testthat::expect_true(any(grepl("toplam_karakter=18", res$logs, fixed = TRUE)))
  testthat::expect_true(any(grepl("model=model-x", res$logs, fixed = TRUE)))

  # Tam döküm YAPILMADI.
  testthat::expect_length(res$dumps, 0L)

  # Sır ve istem gövdesi özet satırında geçmez.
  testthat::expect_false(any(grepl("fake-secret-xyz", res$logs, fixed = TRUE)))
  testthat::expect_false(any(grepl("merhaba", res$logs, fixed = TRUE)))
})

testthat::test_that("MERGEN_LLM_REQUEST_DEBUG açıkken tam döküm yapılır ve oturum çıkarılır", {
  .llmdbg_source_once()
  old_env <- Sys.getenv("MERGEN_LLM_REQUEST_DEBUG", unset = NA_character_)
  on.exit({
    if (is.na(old_env)) Sys.unsetenv("MERGEN_LLM_REQUEST_DEBUG") else Sys.setenv(MERGEN_LLM_REQUEST_DEBUG = old_env)
  }, add = TRUE)
  Sys.setenv(MERGEN_LLM_REQUEST_DEBUG = "true")

  settings <- list(max_output_tokens = 2048L, shiny_session = list(token = "abc"))

  res <- .llmdbg_with_captures(
    mergen_log_llm_request_debug("LLM_REQUEST_TRUE_STREAMING", "model-x", list(list(content = "x")), settings)
  )

  # Tam döküm yapıldı.
  testthat::expect_length(res$dumps, 1L)
  testthat::expect_identical(res$dumps[[1]]$label, "LLM_REQUEST_TRUE_STREAMING")
  # Shiny oturumu döküm yükünde çıkarıldı.
  testthat::expect_null(res$dumps[[1]]$payload$settings$shiny_session)
})

testthat::test_that("mergen_log_chat_perf_summary tek satır özet üretir ve NA'ları yazar", {
  .llmdbg_source_once()

  res <- .llmdbg_with_captures(
    mergen_log_chat_perf_summary(
      "req_1", "model-x", "plain_fast",
      first_reasoning_ms = 120, first_answer_ms = 350,
      first_ui_ms = NA_real_, total_ms = 1800
    )
  )

  testthat::expect_length(res$logs, 1L)
  line <- res$logs[[1]]
  testthat::expect_true(grepl("[CHAT PERF SUMMARY]", line, fixed = TRUE))
  testthat::expect_true(grepl("req=req_1", line, fixed = TRUE))
  testthat::expect_true(grepl("path=plain_fast", line, fixed = TRUE))
  testthat::expect_true(grepl("first_reasoning_ms=120", line, fixed = TRUE))
  testthat::expect_true(grepl("first_answer_ms=350", line, fixed = TRUE))
  testthat::expect_true(grepl("first_ui_ms=NA", line, fixed = TRUE))
  testthat::expect_true(grepl("total_ms=1800", line, fixed = TRUE))
})

testthat::test_that("mergen_llm_request_debug_enabled bayrak çözümlemesi doğru", {
  .llmdbg_source_once()
  old_env <- Sys.getenv("MERGEN_LLM_REQUEST_DEBUG", unset = NA_character_)
  old_dbg <- Sys.getenv("MERGEN_DEBUG", unset = NA_character_)
  on.exit({
    if (is.na(old_env)) Sys.unsetenv("MERGEN_LLM_REQUEST_DEBUG") else Sys.setenv(MERGEN_LLM_REQUEST_DEBUG = old_env)
    if (is.na(old_dbg)) Sys.unsetenv("MERGEN_DEBUG") else Sys.setenv(MERGEN_DEBUG = old_dbg)
  }, add = TRUE)

  Sys.unsetenv("MERGEN_LLM_REQUEST_DEBUG")
  Sys.setenv(MERGEN_DEBUG = "FALSE")
  testthat::expect_false(mergen_llm_request_debug_enabled())

  Sys.setenv(MERGEN_LLM_REQUEST_DEBUG = "1")
  testthat::expect_true(mergen_llm_request_debug_enabled())

  Sys.setenv(MERGEN_LLM_REQUEST_DEBUG = "off")
  testthat::expect_false(mergen_llm_request_debug_enabled())

  # MERGEN_LLM_REQUEST_DEBUG boşsa genel MERGEN_DEBUG'a düşer.
  Sys.unsetenv("MERGEN_LLM_REQUEST_DEBUG")
  Sys.setenv(MERGEN_DEBUG = "TRUE")
  testthat::expect_true(mergen_llm_request_debug_enabled())
})
