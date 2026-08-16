# ==============================================================================
# Dosya Yolu: tests/testthat/test-true-streaming-worker-globals-contract.R
# Açıklama: Gerçek SSE worker-export globals fabrikasının (mergen_true_streaming_
#           worker_globals) yapısal ayrımını ve davranışını doğrular. Fabrika
#           R/helpers_llm_true_streaming_worker.R'de yaşar; handler onu delege
#           eder. Worker-export sözleşmesi (reasoning delta / stop-file / model
#           request override yardımcıları) korunmalıdır. Uygulamayı başlatmaz;
#           tüm global semboller stub'lanır -> deterministik ve çevrimdışı.
# ==============================================================================

.tsw_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", "..")),
    winslash = "/", mustWork = FALSE
  ))
  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "R"))) {
      return(candidate)
    }
  }
  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.tsw_read_text <- function(rel_path) {
  full <- file.path(.tsw_repo_root(), rel_path)
  size <- suppressWarnings(file.info(full)$size[1])
  if (is.na(size) || size <= 0) return("")
  con <- file(full, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]])
  if (is.na(txt)) txt <- ""
  enc2utf8(gsub("\r\n?|\r", "\n", txt, perl = TRUE))
}

# Stub'lı bir ortama fabrikayı yükler (global semboller çağrı anında çözülür).
.tsw_load_factory_env <- function() {
  env <- new.env(parent = baseenv())
  fn_names <- c(
    "call_local_llm_sse_worker", "get_local_model_capabilities", "should_omit_temperature",
    "should_allow_reasoning_fallback", "apply_model_request_overrides", "normalize_llm_text_node",
    "extract_first_nonempty_llm_text", "extract_llm_text_bundle", "extract_llm_delta_bundle",
    "resolve_local_llm_endpoint", "resolve_local_llm_credentials", "extract_llm_content_and_sources",
    "normalize_llm_scalar_content", "strip_planner_text", "decode_utf8_raw_chunk",
    "create_utf8_stream_decoder", "find_last_utf8_boundary", "parse_llm_sse_event",
    "extract_llm_delta_text", "extract_llm_event_sources", "append_stream_delta_line",
    "append_stream_reasoning_line", "log_info", "log_warn",
    "llm_worker_stream_content_looks_like_reasoning"
  )
  for (nm in fn_names) {
    assign(nm, (function() function(...) NULL)(), envir = env)
  }
  assign("api_config", list(probe = TRUE), envir = env)
  assign("%||%", function(a, b) if (is.null(a)) b else a, envir = env)
  sys.source(
    file.path(.tsw_repo_root(), "R", "helpers_llm_true_streaming_worker.R"),
    envir = env
  )
  env
}

# --- Yapısal ayrım -----------------------------------------------------------

test_that("worker-globals fabrikasi kendi dosyasinda yasar, handler delege eder", {
  helper_text <- .tsw_read_text("R/helpers_llm_true_streaming_worker.R")
  handler_text <- .tsw_read_text("R/server_handler_true_streaming.R")

  expect_true(grepl("mergen_true_streaming_worker_globals <- function", helper_text, fixed = TRUE))

  # Handler artık fabrikayı delege etmeli; satır içi globals listesini içermemeli.
  expect_true(grepl("globals = mergen_true_streaming_worker_globals(", handler_text, fixed = TRUE))
  expect_false(grepl("call_local_llm_sse_worker = call_local_llm_sse_worker", handler_text, fixed = TRUE))
})

test_that("manifest fabrikayi true streaming handler'dan ONCE yukler", {
  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_llm_true_streaming_worker.R",
      "R/server_handler_true_streaming.R"
    ),
    label = "Worker-globals fabrikası handler'dan önce yüklenmeli:"
  )
})

# --- Davranış: worker-export sözleşmesi --------------------------------------

test_that("fabrika tum kritik worker-export adlarini ve arg gecisini saglar", {
  env <- .tsw_load_factory_env()

  g <- env$mergen_true_streaming_worker_globals(
    chat_history_for_sse = "CH",
    settings_for_sse = "ST",
    stream_file_for_sse = "SF",
    stop_file_for_sse = "STOP"
  )

  expect_true(is.list(g))
  # 4 isteğe-özel arg + 25 yardımcı + %||% + api_config = 31 isim.
  expect_identical(length(names(g)), 31L)

  # İsteğe-özel 4 nesne birebir geçer (kimlik).
  expect_identical(g$chat_history_for_sse, "CH")
  expect_identical(g$settings_for_sse, "ST")
  expect_identical(g$stream_file_for_sse, "SF")
  expect_identical(g$stop_file_for_sse, "STOP")

  # CLAUDE.md korumalı worker-export adları: reasoning delta / stop-file /
  # request override yardımcıları işçi tarafında görünür kalmalı.
  protected <- c(
    "call_local_llm_sse_worker", "apply_model_request_overrides",
    "append_stream_delta_line", "append_stream_reasoning_line",
    "extract_llm_delta_bundle", "parse_llm_sse_event",
    "llm_worker_stream_content_looks_like_reasoning",
    "%||%", "api_config"
  )
  expect_true(all(protected %in% names(g)))

  expect_true(is.function(g[["%||%"]]))
  expect_false(is.null(g$api_config))
})
