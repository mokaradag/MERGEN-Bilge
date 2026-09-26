# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-sse-perf-log-once-behavior.R
# Açıklama: Düşünen modellerde yanıt metni akıl yürütme süresince boş kalır.
#           "[CHAT PERF] SSE işçide ilk ham HTTP parçası alındı" satırı eskiden
#           yanıt metni boş olduğu sürece HER parçada yazılıyor ve üretim
#           konsol logunu (run_mergen_prod_console.log) saniyede onlarca
#           satırla şişiriyordu. Satır akış başına YALNIZCA bir kez yazılmalıdır.
# ==============================================================================

test_that("ilk ham HTTP parçası satırı akıl yürütme akışında yalnızca bir kez yazılır", {
  skip_if_not_installed("curl")
  skip_if_not_installed("jsonlite")

  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  loglar <- character(0)
  env$log_info <- function(msg, ...) {
    loglar <<- c(loglar, as.character(msg)[1])
    invisible(NULL)
  }
  env$get_local_model_capabilities <- function(model) {
    list(stream_reasoning = TRUE, allow_reasoning_fallback = FALSE)
  }
  env$resolve_local_llm_credentials <- function(model) {
    list(endpoint = "http://localhost:1234/v1/chat/completions",
         default_api_key = "", allow_user_key = FALSE)
  }
  env$should_omit_temperature <- function(model) FALSE
  env$apply_model_request_overrides <- function(body, model) body
  env$should_allow_reasoning_fallback <- function(...) FALSE

  source(file.path(kok, "R/helpers_llm_stream_io.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R/helpers_llm_sse_events.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R/helpers_llm_response_postprocess.R"), encoding = "UTF-8", local = env)
  suppressWarnings(source(file.path(kok, "R/helpers_llm_sse.R"), encoding = "UTF-8", local = env))

  olay <- function(delta) {
    paste0("data: ", jsonlite::toJSON(list(choices = list(list(delta = delta))),
                                      auto_unbox = TRUE), "\n\n")
  }
  parcalar <- c(
    vapply(seq_len(8L), function(i) olay(list(reasoning_content = paste0("adim ", i, " "))),
           character(1)),
    olay(list(content = "Yanit")),
    "data: [DONE]\n\n"
  )

  testthat::local_mocked_bindings(
    new_handle = function(...) list(),
    handle_setheaders = function(handle, ...) invisible(NULL),
    handle_setopt = function(handle, ...) invisible(NULL),
    curl_fetch_stream = function(url, fun, handle, ...) {
      for (p in parcalar) fun(charToRaw(p))
      list(status_code = 200L)
    },
    .package = "curl"
  )

  stream_file <- withr::local_tempfile(fileext = ".jsonl")
  sonuc <- env$call_local_llm_sse_worker(list(list(type = "user", content = "Merhaba")),
                                         list(model_selection = "dusunen-model"), stream_file)
  expect_true(isTRUE(sonuc$success), info = as.character(sonuc$error %||% ""))
  expect_identical(sonuc$content, "Yanit")

  ilk_parca <- grepl("ilk ham HTTP", loglar, fixed = TRUE)
  expect_identical(sum(ilk_parca), 1L)
  expect_identical(sum(grepl("ilk delta", loglar, fixed = TRUE)), 1L)
})

test_that("ilk bayt zamanı yarım UTF-8 harfle biten ilk parçada ölçülür", {
  skip_if_not_installed("curl")
  skip_if_not_installed("jsonlite")

  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  loglar <- character(0)
  env$log_info <- function(msg, ...) {
    loglar <<- c(loglar, as.character(msg)[1])
    invisible(NULL)
  }
  env$get_local_model_capabilities <- function(model) {
    list(stream_reasoning = TRUE, allow_reasoning_fallback = FALSE)
  }
  env$resolve_local_llm_credentials <- function(model) {
    list(endpoint = "http://localhost:1234/v1/chat/completions",
         default_api_key = "", allow_user_key = FALSE)
  }
  env$should_omit_temperature <- function(model) FALSE
  env$apply_model_request_overrides <- function(body, model) body
  env$should_allow_reasoning_fallback <- function(...) FALSE

  source(file.path(kok, "R/helpers_llm_stream_io.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R/helpers_llm_sse_events.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R/helpers_llm_response_postprocess.R"), encoding = "UTF-8", local = env)
  suppressWarnings(source(file.path(kok, "R/helpers_llm_sse.R"), encoding = "UTF-8", local = env))

  olay <- function(delta) {
    paste0("data: ", jsonlite::toJSON(list(choices = list(list(delta = delta))),
                                      auto_unbox = TRUE), "\n\n")
  }
  # İlk parça yalnız çok baytlı "ş" harfinin ilk baytıdır; çözücü onu bekletir.
  tam <- charToRaw(enc2utf8(paste0(olay(list(content = "\u015fey")), "data: [DONE]\n\n")))
  bol <- which(tam == as.raw(0xC5))[1]
  ham_parcalar <- list(tam[seq_len(bol)], tam[-seq_len(bol)])
  ilk_sonrasi <- NA

  testthat::local_mocked_bindings(
    new_handle = function(...) list(),
    handle_setheaders = function(handle, ...) invisible(NULL),
    handle_setopt = function(handle, ...) invisible(NULL),
    curl_fetch_stream = function(url, fun, handle, ...) {
      fun(ham_parcalar[[1]])
      ilk_sonrasi <<- sum(grepl("ilk ham HTTP", loglar, fixed = TRUE))
      fun(ham_parcalar[[2]])
      list(status_code = 200L)
    },
    .package = "curl"
  )

  stream_file <- withr::local_tempfile(fileext = ".jsonl")
  sonuc <- env$call_local_llm_sse_worker(list(list(type = "user", content = "Merhaba")),
                                         list(model_selection = "dusunen-model"), stream_file)
  expect_true(isTRUE(sonuc$success), info = as.character(sonuc$error %||% ""))
  expect_identical(sonuc$content, "\u015fey")
  expect_identical(ilk_sonrasi, 1L)
  expect_identical(sum(grepl("ilk ham HTTP", loglar, fixed = TRUE)), 1L)
})
