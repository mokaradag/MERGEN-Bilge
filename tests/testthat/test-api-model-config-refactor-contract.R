# ==============================================================================
# Dosya Yolu: tests/testthat/test-api-model-config-refactor-contract.R
# Açıklama: API model/uç nokta yardımcılarının config_api.R dışına ayrıldıktan
#           sonra aynı public fonksiyon sözleşmesini koruduğunu doğrular.
# ==============================================================================

.bootstrap_api_model_config_contract <- function() {
  helper_candidates <- c(
    "tests/testthat/helper_bootstrap.R",
    "testthat/helper_bootstrap.R",
    "helper_bootstrap.R"
  )

  helper_path <- helper_candidates[file.exists(helper_candidates)][1]
  if (!is.na(helper_path) && nzchar(helper_path)) {
    source(helper_path, encoding = "UTF-8", local = globalenv())
  }

  if (!exists("resolve_repo_root_for_tests", mode = "function", inherits = TRUE)) {
    resolve_repo_root_for_tests <<- function() {
      candidates <- c(".", "..", "../..")
      for (cand in candidates) {
        if (file.exists(file.path(cand, "app.R")) && dir.exists(file.path(cand, "R"))) {
          return(normalizePath(cand, winslash = "/", mustWork = TRUE))
        }
      }
      stop("Repo kökü bulunamadı. Test çalışma dizinini kontrol edin.", call. = FALSE)
    }
  }

  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(x, y) if (is.null(x)) y else x
  }

  if (!exists("log_info", mode = "function", inherits = TRUE)) {
    log_info <<- function(...) invisible(NULL)
  }
  if (!exists("log_warn", mode = "function", inherits = TRUE)) {
    log_warn <<- function(...) invisible(NULL)
  }
  if (!exists("log_debug", mode = "function", inherits = TRUE)) {
    log_debug <<- function(...) invisible(NULL)
  }

  Sys.setenv(
    MERGEN_RUN_APP = "false",
    MERGEN_DISABLE_FUTURES = "true",
    LOCAL_LLM_ENDPOINT = Sys.getenv("LOCAL_LLM_ENDPOINT", "http://primary.test/v1/chat/completions"),
    LOCAL_LLM_ENDPOINT_ALT = Sys.getenv("LOCAL_LLM_ENDPOINT_ALT", "http://secondary.test/v1/chat/completions"),
    LOCAL_LLM_ENDPOINT_ALT_API_KEY = Sys.getenv("LOCAL_LLM_ENDPOINT_ALT_API_KEY", "secondary-key"),
    DB_DSN = Sys.getenv("DB_DSN", "test-dsn"),
    AI_KEYS_MASTER = Sys.getenv("AI_KEYS_MASTER", "test-master-key-0123456789")
  )

  if (!exists(".build_basename_index", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "utils_file_index.R"),
           encoding = "UTF-8", local = globalenv())
  }

  source(file.path(repo_root, "R", "config_api.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_api_model_config.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_api_model_tool_runtime.R"),
         encoding = "UTF-8", local = globalenv())

  invisible(TRUE)
}

.bootstrap_api_model_config_contract()

test_that("config_api.R bilinmeyen deep-thinking modellerini endpoint map'e güvenli ekler", {
  repo_root <- resolve_repo_root_for_tests()

  old_env <- Sys.getenv(c(
    "EXCEL_DEEP_LOW_MODEL",
    "EXCEL_DEEP_HIGH_MODEL",
    "CODING_DEEP_LOW_MODEL",
    "CODING_DEEP_HIGH_MODEL"
  ), unset = NA_character_)

	on.exit({
	  for (nm in names(old_env)) {
		if (is.na(old_env[[nm]])) {
		  Sys.unsetenv(nm)
		} else {
		  do.call(Sys.setenv, stats::setNames(list(old_env[[nm]]), nm))
		}
	  }
	}, add = TRUE)

  Sys.setenv(
    EXCEL_DEEP_LOW_MODEL = "unknown-excel-deep-low-model",
    EXCEL_DEEP_HIGH_MODEL = "unknown-excel-deep-high-model",
    CODING_DEEP_LOW_MODEL = "unknown-coding-deep-low-model",
    CODING_DEEP_HIGH_MODEL = "unknown-coding-deep-high-model"
  )

  expect_silent(
    source(file.path(repo_root, "R", "config_api.R"),
           encoding = "UTF-8", local = globalenv())
  )

  expect_identical(
    unname(api_config$local_model_endpoint_map["unknown-excel-deep-low-model"]),
    "primary"
  )

  expect_identical(
    unname(api_config$local_model_endpoint_map["unknown-coding-deep-high-model"]),
    "primary"
  )
})

test_that("API model config helper public fonksiyonları source sonrası mevcuttur", {
  expected_functions <- c(
    "get_local_model_capabilities",
    "merge_named_list_deep",
    "apply_model_request_overrides",
    "is_thinking_model",
    "should_omit_temperature",
    "should_stream_reasoning",
    "should_allow_reasoning_fallback",
    "resolve_local_llm_endpoint",
    "resolve_local_llm_credentials",
    "determine_api_key_validation_target",
    "get_tool_mode_config",
    "resolve_tool_model_for_family",
    "resolve_deep_thinking_model",
    "resolve_runtime_model_for_request",
    "resolve_tool_model_for_flag",
    "build_main_actions_data_from_config"
  )

  missing_functions <- expected_functions[
    !vapply(expected_functions, exists, logical(1), mode = "function", inherits = TRUE)
  ]

  expect_equal(
    missing_functions,
    character(0),
    info = paste(
      "helpers_api_model_config.R public API sözleşmesi eksik:",
      paste(missing_functions, collapse = ", ")
    )
  )
})

test_that("thinking model capability config bildirimi ve request override davranışı korunur", {
  fake_config <- list(
    local_model_capabilities = list(
      "plain-model" = list(
        thinking = FALSE,
        omit_temperature = FALSE,
        stream_reasoning = FALSE,
        allow_reasoning_fallback = FALSE
      ),
      "custom-thinking" = list(
        thinking = TRUE,
        omit_temperature = TRUE,
        stream_reasoning = TRUE,
        allow_reasoning_fallback = TRUE,
        request_overrides = list(
          chat_template_kwargs = list(enable_thinking = TRUE)
        )
      )
    )
  )

  # Config'te açıkça thinking=TRUE olarak bildirilen model
  declared <- get_local_model_capabilities("custom-thinking", config = fake_config)
  expect_true(isTRUE(declared$thinking))
  expect_true(isTRUE(declared$omit_temperature))
  expect_true(isTRUE(declared$stream_reasoning))
  expect_true(isTRUE(declared$allow_reasoning_fallback))

  # Config'te açıkça thinking=FALSE olarak bildirilen model
  plain <- get_local_model_capabilities("plain-model", config = fake_config)
  expect_false(isTRUE(plain$thinking))
  expect_false(isTRUE(plain$omit_temperature))
  expect_false(isTRUE(plain$stream_reasoning))
  expect_false(isTRUE(plain$allow_reasoning_fallback))

  # Config'te bildirilmemiş model -> varsayılan olarak thinking=FALSE
  # Eski regex tabanlı tahmin (qwen3/qwq/deepseek-r1 vs.) artık devrede değil.
  unknown <- get_local_model_capabilities("qwen3-prod-model", config = fake_config)
  expect_false(isTRUE(unknown$thinking))
  expect_false(isTRUE(unknown$omit_temperature))
  expect_false(isTRUE(unknown$stream_reasoning))
  expect_false(isTRUE(unknown$allow_reasoning_fallback))

  body <- list(
    model = "custom-thinking",
    stream = TRUE,
    chat_template_kwargs = list(existing_value = "korunmalı")
  )

  merged <- apply_model_request_overrides(
    body = body,
    model_id = "custom-thinking",
    config = fake_config
  )

  expect_true(isTRUE(merged$chat_template_kwargs$enable_thinking))
  expect_identical(merged$chat_template_kwargs$existing_value, "korunmalı")
  expect_true(isTRUE(should_omit_temperature("custom-thinking", config = fake_config)))
  expect_true(isTRUE(should_stream_reasoning("custom-thinking", config = fake_config)))
})

test_that("model bazlı endpoint ve credential çözümleme davranışı korunur", {
  fake_config <- list(
    local_llm_endpoint = "http://legacy.test/v1/chat/completions",
    local_llm_endpoints = list(
      primary = "http://primary.test/v1/chat/completions",
      secondary = "http://secondary.test/v1/chat/completions"
    ),
    local_llm_endpoint_keys = list(
      primary = "",
      secondary = "secondary-default-key"
    ),
    local_llm_endpoint_user_managed = c(
      primary = TRUE,
      secondary = FALSE
    ),
    local_llm_default_endpoint_key = "primary",
    local_models = c("Birincil" = "model-primary", "İkincil" = "model-secondary"),
    local_model_endpoint_map = c(
      "model-primary" = "primary",
      "model-secondary" = "secondary"
    )
  )

  expect_identical(
    resolve_local_llm_endpoint("model-secondary", config = fake_config),
    "http://secondary.test/v1/chat/completions"
  )

  creds <- resolve_local_llm_credentials("model-secondary", config = fake_config)
  expect_identical(creds$endpoint_key, "secondary")
  expect_identical(creds$default_api_key, "secondary-default-key")
  expect_false(isTRUE(creds$allow_user_key))

  target <- determine_api_key_validation_target("model-secondary", config = fake_config)
  expect_identical(target$model_id, "model-primary")
  expect_identical(target$endpoint_key, "primary")
  expect_true(isTRUE(target$allow_user_key))
  expect_true(isTRUE(target$fallback_used))
})

test_that("tool mode model çözümleme ve ana aksiyon verisi korunur", {
  fake_config <- list(
    local_models = c("Varsayılan" = "fallback-model"),
    tool_mode_config = list(
      summarization = list(
        family = "summarization",
        setting_flag = "enable_summarization_tools",
        quick_action_id = "summarization",
        title = "Özetleme Desteği",
        message = "__SUMMARIZATION_REQUEST__",
        description = "Dosyaları özetleyin.",
        icon_name = "file-alt",
        themeColor = "#6366f1",
        model_id = "summary-model"
      ),
      process = list(
        family = "process",
        setting_flag = "enable_process_tools",
        quick_action_id = "project-process",
        title = "Süreç Yönetimi Sistemi",
        message = "Süreç dokümanları hakkında yardım.",
        description = "Süreç, izleç, rehber ve şablon desteği.",
        icon_name = "briefcase",
        themeColor = "#3b82f6",
        model_id = "process-model"
      )
    )
  )

  expect_identical(
    resolve_tool_model_for_family("summarization", config = fake_config),
    "summary-model"
  )

  expect_identical(
    resolve_tool_model_for_flag("enable_process_tools", config = fake_config),
    "process-model"
  )

  actions <- build_main_actions_data_from_config(fake_config)
  action_ids <- unname(vapply(actions, `[[`, character(1), "id"))

  expect_identical(action_ids, c("summarization", "project-process"))
  expect_identical(actions[[1]]$model_value, "summary-model")
  expect_identical(actions[[2]]$model_value, "process-model")
})

test_that("Excel Analizi Derin Düşünme yüksek seviyesi EXCEL_DEEP_HIGH modelini çözer", {
  fake_config <- list(
    local_models = c("Varsayılan" = "fallback-model"),
    tool_mode_config = list(
      mcp_excel = list(
        family = "mcp_excel",
        model_id = "excel-normal-model"
      ),
      coding = list(
        family = "coding",
        model_id = "coding-normal-model"
      )
    ),
    deep_thinking_models = list(
      mcp_excel = list(
        low = "excel-deep-low-model",
        high = "excel-deep-high-model"
      ),
      coding = list(
        low = "coding-deep-low-model",
        high = "coding-deep-high-model"
      )
    )
  )

  resolved <- resolve_runtime_model_for_request(
    tool_family = "mcp_excel",
    fallback_model = "fallback-model",
    excel_deep_on = TRUE,
    excel_deep_level = "high",
    coding_deep_on = FALSE,
    coding_deep_level = "low",
    config = fake_config
  )

  expect_identical(resolved, "excel-deep-high-model")

  normal_resolved <- resolve_runtime_model_for_request(
    tool_family = "mcp_excel",
    fallback_model = "fallback-model",
    excel_deep_on = FALSE,
    excel_deep_level = "high",
    coding_deep_on = FALSE,
    coding_deep_level = "low",
    config = fake_config
  )

  expect_identical(normal_resolved, "excel-normal-model")
})