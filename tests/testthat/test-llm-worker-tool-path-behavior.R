# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-worker-tool-path-behavior.R
# Açıklama: call_llm_worker (R/helpers_llm_worker.R) MCP ARAÇ yolunu (enable_tools
#           = TRUE, tool_family = "mcp_excel") davranışsal olarak sınar. Araçsız
#           yol + hata normalizasyonu test-llm-worker-call-behavior.R'de kapsanmıştı;
#           bu test araç-yürütme ve ikinci-geçiş ORKESTRASYON sözleşmesini kilitler:
#             * araçlardan biri hata döndürürse "Araç hatası:" ile ERKEN döner
#               (ikinci geçişe gitmeden),
#             * strict_data_only=TRUE iken yalnızca biçimlenmiş GERÇEK VERİ metni
#               döner (ikinci LLM geçişi atlanır),
#             * yapısal/metinsel araç çağrısı yoksa mcp_excel fallback devreye girer
#               ve yanıt "Kaynakça:" ile döner,
#             * ikinci geçiş ok=FALSE -> helper'ın hazır response'u aynen döner,
#             * ikinci geçiş ok=TRUE + içerik -> ai2 döner,
#             * ikinci geçiş ok=TRUE + boş ai2 -> format_answer_from_tool_results
#               yedeği döner.
#           Gerçek ağ/LLM/MCP/DB GEREKMEZ; httr namespace local_mocked_bindings ile
#           taklit edilir, helpers_mcp_tools ve ikinci-geçiş/biçimleme yardımcıları
#           deterministik stub'lanır.
# ==============================================================================

testthat::local_edition(3)

testthat::skip_if_not_installed("httr")
testthat::skip_if_not_installed("jsonlite")

.clwt_env <- new.env(parent = globalenv())
.clwt_env$`%||%` <- function(a, b) if (is.null(a)) b else a
.clwt_env$mergen_debug_cat <- function(...) invisible(NULL)
.clwt_env$log_info <- function(...) invisible(NULL)
.clwt_env$should_omit_temperature <- function(model) FALSE
.clwt_env$apply_model_request_overrides <- function(body, model) body
# Saf payload yardımcıları.
.clwt_env$llm_worker_chat_history_to_messages <- function(ch) ch
.clwt_env$llm_worker_merge_system_messages_to_front <- function(payload) payload
.clwt_env$llm_worker_has_chart_intent <- function(ch) FALSE
.clwt_env$llm_worker_detect_chart_type_from_text <- function(...) NULL
.clwt_env$llm_worker_add_fallback_chart <- function(x) x
.clwt_env$llm_worker_build_chart_summary <- function(...) ""
.clwt_env$llm_worker_build_auto_insight <- function(...) ""
.clwt_env$strip_planner_text <- function(x) x
.clwt_env$extract_llm_content_and_sources <- function(response_content, model_id = NULL) {
  list(content = "model metni", reasoning = "")
}
# MCP araç ortamı stub'ı (varsayılanlar; testlerde execute_parsed_tool/
# parse_tool_calls_from_text override edilir).
.clwt_env$helpers_mcp_tools <- list(
  get_openai_tools = function(session_obj = NULL) {
    list(tools = list(list(
      type = "function",
      `function` = list(
        name = "sql_query_uploaded_file",
        parameters = list(required = list("query"))
      )
    )))
  },
  get_mcp_tools_prompt = function(file_schema = NULL) "ARAÇ YÖNERGESİ",
  extract_mcp_file_schema = function(file_name, session_obj) NULL,
  parse_tool_calls_from_text = function(text) list(),
  execute_parsed_tool = function(tc, session = NULL) list(text = "ok")
)
# Araç sonucu biçimleyici ve ikinci-geçiş/yedek yardımcıları (testlerde override).
.clwt_env$llm_worker_format_tool_results_for_prompt <- function(tool_calls, tool_results_raw, chart_summary_fn) {
  list(tool_results = list(), results_text = "GERÇEK VERİ TABLOSU")
}
.clwt_env$llm_worker_run_mcp_second_pass <- function(...) list(ok = TRUE, ai2 = "ikinci", reasoning2 = "")
.clwt_env$format_answer_from_tool_results <- function(tool_results_raw) "tablo yedeği"
.clwt_env$mcp_excel_tool_fallback <- function(session_obj) list(text = "fallback", citation = "")

source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_llm_worker.R"),
  encoding = "UTF-8",
  local = .clwt_env
)

.clwt_settings <- function() {
  list(model_selection = "model-x", tool_family = "mcp_excel", enable_mcp_tools = TRUE)
}
.clwt_history <- function() list(list(role = "user", content = "Excel verisini analiz et"))
.clwt_response <- structure(list(), class = "clwt_fake_response")

# Yapısal tool_calls içeren API yanıtı (mcp_excel ilk geçiş).
.clwt_structured_resp <- function() {
  list(choices = list(list(message = list(
    content = "",
    tool_calls = list(list(`function` = list(
      name = "sql_query_uploaded_file",
      arguments = "{\"query\":\"SELECT 1\"}"
    )))
  ))))
}
# tool_calls içermeyen API yanıtı (fallback yolu).
.clwt_plain_resp <- function() {
  list(choices = list(list(message = list(content = "düz model yanıtı"))))
}

test_that("araç hata döndürürse 'Araç hatası:' ile erken döner (ikinci geçişe gitmez)", {
  .clwt_env$.resp <- .clwt_structured_resp()
  .clwt_env$helpers_mcp_tools$execute_parsed_tool <- function(tc, session = NULL) {
    list(error = "Sorgu çalıştırılamadı")
  }
  # İkinci geçiş çağrılırsa hata fırlatsın: erken dönüşün kanıtı.
  .clwt_env$llm_worker_run_mcp_second_pass <- function(...) stop("araç hatasında ikinci geçiş çağrılmamalı")

  testthat::local_mocked_bindings(
    POST = function(url, ...) .clwt_response,
    status_code = function(resp) 200L,
    content = function(x, as = NULL, ...) if (identical(as, "parsed")) .clwt_env$.resp else "",
    .package = "httr"
  )

  out <- .clwt_env$call_llm_worker(.clwt_history(), .clwt_settings(), "http://local/api", enable_tools = TRUE)

  expect_match(out$content, "Araç hatası", fixed = TRUE)
  expect_match(out$content, "Sorgu çalıştırılamadı", fixed = TRUE)
})

test_that("strict_data_only=TRUE iken yalnızca GERÇEK VERİ metni döner (ikinci geçiş atlanır)", {
  withr::local_options(mergen.ai.strict_data_only = TRUE)
  .clwt_env$.resp <- .clwt_structured_resp()
  .clwt_env$helpers_mcp_tools$execute_parsed_tool <- function(tc, session = NULL) list(text = "satır verisi")
  .clwt_env$llm_worker_format_tool_results_for_prompt <- function(tool_calls, tool_results_raw, chart_summary_fn) {
    list(tool_results = list(), results_text = "GERÇEK VERİ TABLOSU")
  }
  .clwt_env$llm_worker_run_mcp_second_pass <- function(...) stop("strict modda ikinci geçiş çağrılmamalı")

  testthat::local_mocked_bindings(
    POST = function(url, ...) .clwt_response,
    status_code = function(resp) 200L,
    content = function(x, as = NULL, ...) if (identical(as, "parsed")) .clwt_env$.resp else "",
    .package = "httr"
  )

  out <- .clwt_env$call_llm_worker(.clwt_history(), .clwt_settings(), "http://local/api", enable_tools = TRUE)

  expect_identical(out$content, "GERÇEK VERİ TABLOSU")
})

test_that("araç çağrısı yoksa mcp_excel fallback devreye girer ve Kaynakça ile döner", {
  .clwt_env$.resp <- .clwt_plain_resp()
  .clwt_env$extract_llm_content_and_sources <- function(response_content, model_id = NULL) {
    list(content = "düz model yanıtı", reasoning = "")
  }
  .clwt_env$helpers_mcp_tools$parse_tool_calls_from_text <- function(text) list()
  .clwt_env$mcp_excel_tool_fallback <- function(session_obj) {
    list(text = "Fallback yanıt metni", citation = "satislar.xlsx")
  }

  testthat::local_mocked_bindings(
    POST = function(url, ...) .clwt_response,
    status_code = function(resp) 200L,
    content = function(x, as = NULL, ...) if (identical(as, "parsed")) .clwt_env$.resp else "",
    .package = "httr"
  )

  out <- .clwt_env$call_llm_worker(.clwt_history(), .clwt_settings(), "http://local/api", enable_tools = TRUE)

  expect_match(out$content, "Fallback yanıt metni", fixed = TRUE)
  expect_match(out$content, "Kaynakça:", fixed = TRUE)
  expect_match(out$content, "satislar.xlsx", fixed = TRUE)
})

test_that("ikinci geçiş ok=FALSE ise helper'ın hazır response'u aynen döner", {
  withr::local_options(mergen.ai.strict_data_only = FALSE)
  .clwt_env$.resp <- .clwt_structured_resp()
  .clwt_env$helpers_mcp_tools$execute_parsed_tool <- function(tc, session = NULL) list(text = "veri")
  .clwt_env$llm_worker_format_tool_results_for_prompt <- function(tool_calls, tool_results_raw, chart_summary_fn) {
    list(tool_results = list(), results_text = "VERİ METNİ")
  }
  .clwt_env$llm_worker_run_mcp_second_pass <- function(...) {
    list(ok = FALSE, response = list(content = "erken dönüş yanıtı", duration = 0, chart_store = list()))
  }

  testthat::local_mocked_bindings(
    POST = function(url, ...) .clwt_response,
    status_code = function(resp) 200L,
    content = function(x, as = NULL, ...) if (identical(as, "parsed")) .clwt_env$.resp else "",
    .package = "httr"
  )

  out <- .clwt_env$call_llm_worker(.clwt_history(), .clwt_settings(), "http://local/api", enable_tools = TRUE)

  expect_identical(out$content, "erken dönüş yanıtı")
})

test_that("ikinci geçiş ok=TRUE + içerik -> ai2 döner", {
  withr::local_options(mergen.ai.strict_data_only = FALSE)
  .clwt_env$.resp <- .clwt_structured_resp()
  .clwt_env$helpers_mcp_tools$execute_parsed_tool <- function(tc, session = NULL) list(text = "veri")
  .clwt_env$llm_worker_format_tool_results_for_prompt <- function(tool_calls, tool_results_raw, chart_summary_fn) {
    list(tool_results = list(), results_text = "VERİ METNİ")
  }
  .clwt_env$llm_worker_run_mcp_second_pass <- function(...) {
    list(ok = TRUE, ai2 = "İkinci geçiş final yanıtı", reasoning2 = "düşünce")
  }

  testthat::local_mocked_bindings(
    POST = function(url, ...) .clwt_response,
    status_code = function(resp) 200L,
    content = function(x, as = NULL, ...) if (identical(as, "parsed")) .clwt_env$.resp else "",
    .package = "httr"
  )

  out <- .clwt_env$call_llm_worker(.clwt_history(), .clwt_settings(), "http://local/api", enable_tools = TRUE)

  expect_match(out$content, "İkinci geçiş final yanıtı", fixed = TRUE)
  expect_identical(out$reasoning_content, "düşünce")
})

test_that("ikinci geçiş ok=TRUE + boş ai2 -> format_answer_from_tool_results yedeği döner", {
  withr::local_options(mergen.ai.strict_data_only = FALSE)
  .clwt_env$.resp <- .clwt_structured_resp()
  .clwt_env$helpers_mcp_tools$execute_parsed_tool <- function(tc, session = NULL) list(text = "veri")
  .clwt_env$llm_worker_format_tool_results_for_prompt <- function(tool_calls, tool_results_raw, chart_summary_fn) {
    list(tool_results = list(), results_text = "VERİ METNİ")
  }
  .clwt_env$llm_worker_run_mcp_second_pass <- function(...) list(ok = TRUE, ai2 = "", reasoning2 = "")
  .clwt_env$format_answer_from_tool_results <- function(tool_results_raw) "Tablodan üretilen yedek yanıt"

  testthat::local_mocked_bindings(
    POST = function(url, ...) .clwt_response,
    status_code = function(resp) 200L,
    content = function(x, as = NULL, ...) if (identical(as, "parsed")) .clwt_env$.resp else "",
    .package = "httr"
  )

  out <- .clwt_env$call_llm_worker(.clwt_history(), .clwt_settings(), "http://local/api", enable_tools = TRUE)

  expect_match(out$content, "Tablodan üretilen yedek yanıt", fixed = TRUE)
})
