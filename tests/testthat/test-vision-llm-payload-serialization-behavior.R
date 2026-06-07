# ==============================================================================
# Dosya Yolu: tests/testthat/test-vision-llm-payload-serialization-behavior.R
# Açıklama: Vision çok-kipli (multimodal) kullanıcı içeriğinin GERÇEK LLM istek
#           gövdesine bozulmadan serileştiğini doğrular. Hem non-streaming
#           (call_local_llm -> httr::POST) hem streaming (call_local_llm_sse_worker
#           -> curl postfields) yolu test edilir. Gerçek ağ/LLM yok; httr/curl
#           bağlamaları taklit edilir ve gönderilecek gövde yakalanır.
# ==============================================================================

repo_root_vis_ser <- resolve_repo_root_for_tests()

test_that("call_local_llm çok-kipli içeriği gövdede dizi olarak korur (non-streaming)", {
  skip_if_not_installed("httr")
  skip_if_not_installed("jsonlite")

  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
  env$log_info <- function(...) invisible(NULL)
  env$resolve_local_llm_credentials <- function(model) {
    list(endpoint = "http://localhost:1234/v1/chat/completions",
         default_api_key = "", allow_user_key = FALSE)
  }
  env$should_omit_temperature <- function(model) FALSE
  env$apply_model_request_overrides <- function(body, model) body
  env$extract_llm_content_and_sources <- function(parsed, model_id = NULL) {
    list(content = "test-yanit", sources = list())
  }
  env$append_clickable_sources <- function(content, sources) content
  env$strip_planner_text <- function(content) content
  source(file.path(repo_root_vis_ser, "R/helpers_llm_api.R"), encoding = "UTF-8", local = env)

  captured <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    POST = function(url, body, encode, ...) {
      captured$body <- body
      structure(list(), class = "response")
    },
    status_code = function(resp) 200L,
    content = function(resp, ...) {
      list(choices = list(list(message = list(content = "test-yanit"))))
    },
    add_headers = function(...) list(),
    timeout = function(...) list(),
    .package = "httr"
  )

  multimodal_content <- list(
    list(type = "text", text = "Bu görselde ne var?"),
    list(type = "image_url", image_url = list(url = "data:image/png;base64,AAAB"))
  )
  chat_history <- list(
    list(type = "system", content = "SYS"),
    list(type = "user", content = multimodal_content)
  )

  res <- env$call_local_llm(chat_history, list(model_selection = "vmod"))
  expect_true(is.list(res))

  body <- captured$body
  expect_true(is.list(body$messages))
  user_msg <- body$messages[[2]]
  expect_identical(user_msg$role, "user")
  # Kullanıcı içeriği DİZİ (multimodal) olarak korunmalı, string'e düzleşmemeli
  expect_true(is.list(user_msg$content))
  types <- vapply(user_msg$content, function(p) p$type %||% "", character(1))
  expect_true("text" %in% types)
  expect_true("image_url" %in% types)

  # encode = "json" ile aynı serileşme: image_url yapısı JSON'da görünmeli
  json <- as.character(jsonlite::toJSON(body, auto_unbox = TRUE, null = "null"))
  expect_true(grepl('"type":"image_url"', json, fixed = TRUE))
  expect_true(grepl('"url":"data:image/png;base64,AAAB"', json, fixed = TRUE))
  # Metin parçası korunur ve role tek string kalır
  expect_true(grepl('"type":"text"', json, fixed = TRUE))
  expect_true(grepl('"role":"user"', json, fixed = TRUE))
})

test_that("call_local_llm sade string içeriği string olarak gönderir (metin yolu korunur)", {
  skip_if_not_installed("httr")

  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
  env$log_info <- function(...) invisible(NULL)
  env$resolve_local_llm_credentials <- function(model) {
    list(endpoint = "http://localhost:1234/v1/chat/completions",
         default_api_key = "", allow_user_key = FALSE)
  }
  env$should_omit_temperature <- function(model) FALSE
  env$apply_model_request_overrides <- function(body, model) body
  env$extract_llm_content_and_sources <- function(parsed, model_id = NULL) {
    list(content = "test-yanit", sources = list())
  }
  env$append_clickable_sources <- function(content, sources) content
  env$strip_planner_text <- function(content) content
  source(file.path(repo_root_vis_ser, "R/helpers_llm_api.R"), encoding = "UTF-8", local = env)

  captured <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    POST = function(url, body, encode, ...) {
      captured$body <- body
      structure(list(), class = "response")
    },
    status_code = function(resp) 200L,
    content = function(resp, ...) {
      list(choices = list(list(message = list(content = "test-yanit"))))
    },
    add_headers = function(...) list(),
    timeout = function(...) list(),
    .package = "httr"
  )

  chat_history <- list(
    list(type = "system", content = "SYS"),
    list(type = "user", content = "düz metin sorusu")
  )
  env$call_local_llm(chat_history, list(model_selection = "metin-modeli"))

  user_msg <- captured$body$messages[[2]]
  expect_true(is.character(user_msg$content))
  expect_identical(user_msg$content, "düz metin sorusu")
})

test_that("call_local_llm_sse_worker çok-kipli içeriği postfields'te dizi olarak korur (streaming)", {
  skip_if_not_installed("curl")
  skip_if_not_installed("jsonlite")

  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
  env$log_info <- function(...) invisible(NULL)
  env$get_local_model_capabilities <- function(model) {
    list(stream_reasoning = FALSE, allow_reasoning_fallback = FALSE)
  }
  env$resolve_local_llm_credentials <- function(model) {
    list(endpoint = "http://localhost:1234/v1/chat/completions",
         default_api_key = "", allow_user_key = FALSE)
  }
  env$should_omit_temperature <- function(model) FALSE
  env$apply_model_request_overrides <- function(body, model) body

  # Akış protokolü ve SSE olay yardımcıları (runtime'da yüklü değilse).
  source(file.path(repo_root_vis_ser, "R/helpers_llm_stream_io.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root_vis_ser, "R/helpers_llm_sse_events.R"), encoding = "UTF-8", local = env)
  suppressWarnings(source(file.path(repo_root_vis_ser, "R/helpers_llm_sse.R"), encoding = "UTF-8", local = env))

  captured <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    new_handle = function(...) list(),
    handle_setheaders = function(handle, ...) invisible(NULL),
    handle_setopt = function(handle, ...) {
      args <- list(...)
      if (!is.null(args$postfields)) captured$postfields <- args$postfields
      invisible(NULL)
    },
    curl_fetch_stream = function(url, fun, handle, ...) stop("TEST_ABORT_BEFORE_STREAM"),
    .package = "curl"
  )

  multimodal_content <- list(
    list(type = "text", text = "Bu görselde ne var?"),
    list(type = "image_url", image_url = list(url = "data:image/png;base64,CCCD"))
  )
  chat_history <- list(
    list(type = "system", content = "SYS"),
    list(type = "user", content = multimodal_content)
  )

  stream_file <- tempfile(fileext = ".jsonl")
  on.exit(unlink(stream_file), add = TRUE)

  # curl_fetch_stream içinden fırlatılan hata fonksiyonun kendi tryCatch'i ile
  # yakalanır; gövde zaten handle_setopt aşamasında yakalanmış olur.
  invisible(tryCatch(
    env$call_local_llm_sse_worker(chat_history, list(model_selection = "vmod"), stream_file),
    error = function(e) NULL
  ))

  expect_false(is.null(captured$postfields))
  json <- as.character(captured$postfields)
  expect_true(grepl('"type":"image_url"', json, fixed = TRUE))
  expect_true(grepl('"url":"data:image/png;base64,CCCD"', json, fixed = TRUE))
  expect_true(grepl('"type":"text"', json, fixed = TRUE))
  expect_true(grepl('"role":"user"', json, fixed = TRUE))
})
