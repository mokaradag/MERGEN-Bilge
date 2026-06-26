# ==============================================================================
# Dosya Yolu: tests/testthat/test-source-manifest-contract.R
# Açıklama: global.R kaynak yükleme manifestinin üretim açısından kritik sıra,
#           tekrar ve varlık sözleşmelerini doğrular. Uygulamayı başlatmaz.
# ==============================================================================

.read_repo_text_manifest_contract <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.load_source_manifest_paths_for_contract <- function() {
  repo_root <- resolve_repo_root_for_tests()
  manifest_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root, "R", "config_source_manifest.R"),
    encoding = "UTF-8",
    local = manifest_env
  )

  if (!exists("source_manifest_runtime_paths", envir = manifest_env, inherits = FALSE)) {
    stop("Test manifesti source_manifest_runtime_paths nesnesini bulamadı.", call. = FALSE)
  }

  paths <- get("source_manifest_runtime_paths", envir = manifest_env, inherits = FALSE)

  if (!is.character(paths) || length(paths) == 0L) {
    stop("Test manifesti boş veya geçersiz.", call. = FALSE)
  }

  enc2utf8(paths)
}

test_that("config_source_manifest.R manifestindeki dosyalar repoda gerçekten var", {
  repo_root <- resolve_repo_root_for_tests()
  paths <- .load_source_manifest_paths_for_contract()

  expect_gt(length(paths), 50L)

  missing_paths <- paths[!file.exists(file.path(repo_root, paths))]

  expect_equal(
    missing_paths,
    character(0),
    info = paste(
      "global.R manifestinde olmayan dosyalar var:",
      paste(missing_paths, collapse = ", ")
    )
  )
})

test_that("config_source_manifest.R manifestinde aynı R dosyası yanlışlıkla tekrar tekrar yüklenmiyor", {
  paths <- .load_source_manifest_paths_for_contract()

  duplicate_paths <- unique(paths[duplicated(paths)])

  # welcome_screen.R bilerek hem root boot hem de welcome handler kısmında
  # görülebilir; bu nedenle yalnızca R/ altındaki tekrarlar kritik sayılır.
  duplicate_r_paths <- duplicate_paths[grepl("^R/", duplicate_paths)]

  expect_equal(
    duplicate_r_paths,
    character(0),
    info = paste(
      "global.R içinde tekrar eden R/ safe_source kayıtları:",
      paste(duplicate_r_paths, collapse = ", ")
    )
  )
})

test_that("global.R manifest doğrulamasını küçük bootstrap helper'ı üzerinden runtime source zincirinden önce çalıştırıyor", {
  paths <- .load_source_manifest_paths_for_contract()
  global_text <- .read_repo_text_manifest_contract("global.R")
  bootstrap_text <- .read_repo_text_manifest_contract(file.path("R", "bootstrap_source_manifest.R"))

  global_expected_tokens <- c(
    'safe_source("R/bootstrap_source_manifest.R", encoding = "UTF-8")',
    'paths = "R/config_source_manifest.R"',
    'safe_source("R/config_source_manifest.R", encoding = "UTF-8")',
    "source_manifest_validate_config_objects()",
    "source_manifest_current_paths <- source_manifest_get_runtime_paths",
    "source_manifest_validate(",
    "source_manifest_load(source_manifest_group_1_paths)"
  )

  global_found <- vapply(
    global_expected_tokens,
    function(token) {
      isTRUE(suppressWarnings(grepl(
        token,
        global_text,
        fixed = TRUE,
        useBytes = TRUE
      )))
    },
    logical(1)
  )

  expect_true(
    all(global_found),
    info = paste(
      "global.R manifest bootstrap/doğrulama kayıtları eksik:",
      paste(global_expected_tokens[!global_found], collapse = ", ")
    )
  )

  bootstrap_expected_tokens <- c(
    "source_manifest_stop <- function",
    "source_manifest_validate_config_objects <- function",
    "source_manifest_validate_files <- function",
    "source_manifest_validate_parse <- function",
    "source_manifest_validate_order <- function",
    "source_manifest_get_runtime_paths <- function",
    "source_manifest_load <- function",
    "source_manifest_validate <- function",
    "source_manifest_required_order <- list"
  )

  bootstrap_found <- vapply(
    bootstrap_expected_tokens,
    function(token) {
      isTRUE(suppressWarnings(grepl(
        token,
        bootstrap_text,
        fixed = TRUE,
        useBytes = TRUE
      )))
    },
    logical(1)
  )

  expect_true(
    all(bootstrap_found),
    info = paste(
      "bootstrap_source_manifest.R manifest helper/kayıtları eksik:",
      paste(bootstrap_expected_tokens[!bootstrap_found], collapse = ", ")
    )
  )

  bootstrap_source_pos <- regexpr(
    'safe_source("R/bootstrap_source_manifest.R", encoding = "UTF-8")',
    global_text,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  validation_call_pos <- regexpr(
    "source_manifest_validate(",
    global_text,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  first_manifest_source_pos <- regexpr(
    "source_manifest_load(source_manifest_group_1_paths)",
    global_text,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  after_future_manifest_source_pos <- regexpr(
    "source_manifest_load(source_manifest_after_future_paths)",
    global_text,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  expect_true(bootstrap_source_pos > 0L)
  expect_true(validation_call_pos > 0L)
  expect_true(first_manifest_source_pos > 0L)
  expect_true(after_future_manifest_source_pos > 0L)
  expect_lt(bootstrap_source_pos, validation_call_pos)
  expect_lt(validation_call_pos, first_manifest_source_pos)
  expect_lt(first_manifest_source_pos, after_future_manifest_source_pos)

  critical_rules <- c(
    'c("R/bootstrap_source_manifest.R", "R/config_packages.R")',
    'c("R/config_api.R", "R/helpers_api_model_config.R")',
    'c("R/helpers_send_message_request_lifecycle.R", "R/helpers_send_message_core.R")',
    'c("R/helpers_llm_worker_payload.R", "R/helpers_llm_worker_tool_results.R")',
    'c("R/server_handler_true_streaming.R", "R/server_send_message.R")'
  )

  rules_found <- vapply(
    critical_rules,
    function(rule) {
      isTRUE(suppressWarnings(grepl(
        rule,
        bootstrap_text,
        fixed = TRUE,
        useBytes = TRUE
      )))
    },
    logical(1)
  )

  expect_true(
    all(rules_found),
    info = paste(
      "bootstrap_source_manifest.R manifest doğrulama sıra kuralı eksik:",
      paste(critical_rules[!rules_found], collapse = ", ")
    )
  )
})

test_that("LLM/SSE/worker yükleme sırası korunuyor", {
  paths <- .load_source_manifest_paths_for_contract()

  pos <- function(path) match(path, paths)

  expect_false(is.na(pos("R/helpers_llm_stream_io.R")))
  expect_false(is.na(pos("R/helpers_llm_sse_events.R")))
  expect_false(is.na(pos("R/helpers_llm_worker_payload.R")))
  expect_false(is.na(pos("R/helpers_llm_worker_tool_results.R")))

  expect_lt(pos("R/helpers_llm_response_postprocess.R"), pos("R/helpers_llm_api.R"))
  expect_lt(pos("R/helpers_llm_api.R"), pos("R/helpers_llm_stream_io.R"))
  expect_lt(pos("R/helpers_llm_stream_io.R"), pos("R/helpers_llm_sse_events.R"))
  expect_lt(pos("R/helpers_llm_sse_events.R"), pos("R/helpers_llm_sse.R"))
  expect_lt(pos("R/helpers_llm_sse.R"), pos("R/helpers_llm_worker_payload.R"))
  expect_lt(pos("R/helpers_llm_worker_payload.R"), pos("R/helpers_llm_worker_tool_results.R"))
  expect_lt(pos("R/helpers_llm_worker_tool_results.R"), pos("R/helpers_llm_worker.R"))
  expect_lt(pos("R/server_handler_true_streaming.R"), pos("R/server_send_message.R"))
})

test_that("file store indeks/registry yardımcıları config dosyasından sonra yükleniyor", {
  paths <- .load_source_manifest_paths_for_contract()

  pos <- function(path) match(path, paths)

  expect_false(is.na(pos("R/config_file_store.R")))
  expect_false(is.na(pos("R/config_file_store_index_mutation.R")))
  expect_false(is.na(pos("R/config_file_store_registry.R")))
  expect_false(is.na(pos("R/config_characters.R")))

  expect_lt(pos("R/config_file_store.R"), pos("R/config_file_store_index_mutation.R"))
  expect_lt(pos("R/config_file_store_index_mutation.R"), pos("R/config_file_store_registry.R"))
  expect_lt(pos("R/config_file_store_registry.R"), pos("R/config_characters.R"))
})

test_that("API model/uç nokta yardımcıları config_api sonrasında ve LLM katmanından önce yükleniyor", {
  paths <- .load_source_manifest_paths_for_contract()

  pos <- function(path) match(path, paths)

  expect_false(is.na(pos("R/config_api.R")))
  expect_false(is.na(pos("R/helpers_api_model_config.R")))
  expect_false(is.na(pos("R/helpers_llm_api.R")))
  expect_false(is.na(pos("R/helpers_llm_sse.R")))
  expect_false(is.na(pos("R/helpers_llm_worker.R")))

  expect_lt(pos("R/config_api.R"), pos("R/helpers_api_model_config.R"))
  expect_lt(pos("R/helpers_api_model_config.R"), pos("R/helpers_llm_api.R"))
  expect_lt(pos("R/helpers_api_model_config.R"), pos("R/helpers_llm_sse.R"))
  expect_lt(pos("R/helpers_api_model_config.R"), pos("R/helpers_llm_worker.R"))
})

test_that("kritik yardımcılar modüllerden önce yükleniyor", {
  paths <- .load_source_manifest_paths_for_contract()

  pos <- function(path) match(path, paths)

  expect_false(is.na(pos("R/helpers_mcp_context.R")))
  expect_false(is.na(pos("R/helpers_mcp_bootstrap.R")))
  expect_false(is.na(pos("R/helpers_mcp_table_readers.R")))
  expect_false(is.na(pos("R/helpers_mcp_file_resolver.R")))
  expect_false(is.na(pos("R/helpers_mcp_schema_helpers.R")))
  expect_false(is.na(pos("R/helpers_mcp_basic_tools.R")))
  expect_false(is.na(pos("R/helpers_mcp_chart_tools.R")))
  expect_false(is.na(pos("R/helpers_chartlab_spec.R")))
  expect_lt(pos("R/helpers_database.R"), pos("R/module_chat_history.R"))
  expect_lt(pos("R/helpers_mcp_context.R"), pos("R/helpers_mcp_bootstrap.R"))
  expect_lt(pos("R/helpers_mcp_bootstrap.R"), pos("R/helpers_mcp_table_readers.R"))
  expect_lt(pos("R/helpers_mcp_table_readers.R"), pos("R/helpers_mcp_file_resolver.R"))
  expect_lt(pos("R/helpers_mcp_file_resolver.R"), pos("R/helpers_mcp_schema_helpers.R"))
  expect_lt(pos("R/helpers_mcp_schema_helpers.R"), pos("R/helpers_mcp_basic_tools.R"))
  expect_lt(pos("R/helpers_mcp_basic_tools.R"), pos("R/helpers_mcp_chart_tools.R"))
  expect_lt(pos("R/helpers_mcp_chart_tools.R"), pos("R/helpers_mcp_analyze_visualize.R"))
  expect_lt(pos("R/helpers_mcp_analyze_visualize.R"), pos("R/helpers_mcp_tools.R"))
  expect_lt(pos("R/helpers_mcp_tools.R"), pos("R/helpers_chartlab_spec.R"))
  expect_lt(pos("R/helpers_chartlab_spec.R"), pos("R/helpers_chartlab.R"))
  expect_lt(pos("R/helpers_mcp_file_resolver.R"), pos("R/module_summarization.R"))
  expect_false(is.na(pos("R/helpers_send_message_request_lifecycle.R")))
  expect_false(is.na(pos("R/helpers_send_message_prompting.R")))
  expect_lt(pos("R/helpers_send_message_request_lifecycle.R"), pos("R/helpers_send_message_core.R"))
  expect_lt(pos("R/helpers_send_message_core.R"), pos("R/helpers_send_message_prompting.R"))
  expect_lt(pos("R/helpers_send_message_prompting.R"), pos("R/server_send_message.R"))
  expect_lt(pos("R/helpers_send_message_request_lifecycle.R"), pos("R/server_handler_true_streaming.R"))
  expect_lt(pos("R/helpers_send_message_core.R"), pos("R/server_send_message.R"))
  expect_false(is.na(pos("R/helpers_user_session_identity.R")))
  expect_false(is.na(pos("R/server_init_user_session.R")))
  expect_false(is.na(pos("R/helpers_server_runtime_contracts.R")))
  expect_false(is.na(pos("R/helpers_server_runtime_named_contracts.R")))
  expect_false(is.na(pos("R/server_runtime_context.R")))
  expect_false(is.na(pos("R/server_runtime_function_slot.R")))
  expect_false(is.na(pos("R/server_module_wiring.R")))
  expect_false(is.na(pos("R/server_chat_engine_dependencies.R")))
  expect_false(is.na(pos("R/server_chat_engine_runtime.R")))
  expect_false(is.na(pos("R/server_core_observer_runtime.R")))
  expect_false(is.na(pos("R/utils_session_cleanup.R")))
  expect_false(is.na(pos("R/server_session_cache.R")))
  expect_false(is.na(pos("R/server_init_session_state.R")))
  expect_lt(pos("R/utils_session_cleanup.R"), pos("R/server_session_cache.R"))
  expect_lt(pos("R/utils_session_cleanup.R"), pos("R/server_init_session_state.R"))
  expect_lt(pos("R/module_user_identity.R"), pos("R/helpers_user_session_identity.R"))
  expect_lt(pos("R/helpers_user_session_identity.R"), pos("R/server_init_user_session.R"))
  expect_lt(pos("R/server_init_forward_refs.R"), pos("R/server_init_user_session.R"))
  expect_lt(pos("R/server_init_user_session.R"), pos("R/helpers_server_runtime_contracts.R"))
  expect_lt(pos("R/helpers_server_runtime_contracts.R"), pos("R/helpers_server_runtime_named_contracts.R"))
  expect_lt(pos("R/helpers_server_runtime_named_contracts.R"), pos("R/server_runtime_context.R"))
  expect_lt(pos("R/server_runtime_context.R"), pos("R/server_runtime_function_slot.R"))
  expect_lt(pos("R/server_runtime_function_slot.R"), pos("R/server_module_wiring.R"))
  expect_lt(pos("R/server_module_wiring.R"), pos("R/server_chat_engine_dependencies.R"))
  expect_lt(pos("R/server_chat_engine_dependencies.R"), pos("R/server_chat_engine_runtime.R"))
  expect_lt(pos("R/server_chat_engine_runtime.R"), pos("R/server_init_session_state.R"))
  expect_lt(pos("R/server_chat_engine_runtime.R"), pos("R/server_init_chat_runtime.R"))
  expect_lt(pos("R/server_init_chat_runtime.R"), pos("R/server_core_observer_runtime.R"))
  expect_lt(pos("R/server_core_observer_runtime.R"), pos("R/server_core_interaction_runtime.R"))
  expect_false(is.na(pos("R/helpers_health_runtime_checks.R")))
  expect_lt(pos("R/helpers_health_formatters.R"), pos("R/helpers_health_runtime_checks.R"))
  expect_lt(pos("R/helpers_health_runtime_checks.R"), pos("R/helpers_health_checks.R"))
  expect_lt(pos("R/helpers_health_checks.R"), pos("R/module_health.R"))
})

test_that("Bilge Yolaç user guard ve server setup yardımcıları modülden önce yükleniyor", {
  paths <- .load_source_manifest_paths_for_contract()

  pos <- function(path) match(path, paths)

  expect_false(is.na(pos("R/helpers_claude_code_user_guard.R")))
  expect_false(is.na(pos("R/helpers_claude_code_upload_folder.R")))
  expect_false(is.na(pos("R/helpers_claude_code_dir_ui.R")))
  expect_false(is.na(pos("R/helpers_claude_code_process.R")))
  expect_false(is.na(pos("R/helpers_claude_code_runtime_workdir.R")))
  expect_false(is.na(pos("R/helpers_claude_code_directory_listing.R")))
  expect_false(is.na(pos("R/helpers_claude_code.R")))
  expect_false(is.na(pos("R/helpers_claude_code_downloads.R")))
  expect_false(is.na(pos("R/helpers_claude_code_workdir_scan.R")))
  expect_false(is.na(pos("R/helpers_claude_code_workdir_snapshot.R")))
  expect_false(is.na(pos("R/helpers_claude_code_documents.R")))
  expect_false(is.na(pos("R/helpers_claude_code_run_lifecycle.R")))
  expect_false(is.na(pos("R/helpers_claude_code_server_setup.R")))
  expect_false(is.na(pos("R/module_claude_code_akis.R")))
  expect_false(is.na(pos("R/module_claude_code.R")))

  expect_lt(
    pos("R/helpers_claude_code_user_guard.R"),
    pos("R/helpers_claude_code_server_setup.R")
  )

  expect_lt(
    pos("R/helpers_claude_code_upload_folder.R"),
    pos("R/helpers_claude_code_server_setup.R")
  )

  expect_lt(
    pos("R/helpers_claude_code_process.R"),
    pos("R/helpers_claude_code_runtime_workdir.R")
  )

  expect_lt(
    pos("R/helpers_claude_code_runtime_workdir.R"),
    pos("R/helpers_claude_code_directory_listing.R")
  )

  expect_lt(
    pos("R/helpers_claude_code_directory_listing.R"),
    pos("R/helpers_claude_code.R")
  )

  expect_lt(
    pos("R/helpers_claude_code.R"),
    pos("R/helpers_claude_code_server_setup.R")
  )
  
  expect_lt(
    pos("R/helpers_claude_code_downloads.R"),
    pos("R/helpers_claude_code_workdir_scan.R")
  )

  expect_lt(
    pos("R/helpers_claude_code_workdir_scan.R"),
    pos("R/helpers_claude_code_workdir_snapshot.R")
  )

  expect_lt(
    pos("R/helpers_claude_code_workdir_snapshot.R"),
    pos("R/helpers_claude_code_documents.R")
  )
  
  expect_lt(
    pos("R/helpers_claude_code_documents.R"),
    pos("R/helpers_claude_code_run_lifecycle.R")
  )

  expect_lt(
    pos("R/helpers_claude_code_run_lifecycle.R"),
    pos("R/module_claude_code_akis.R")
  )

  expect_lt(
    pos("R/helpers_claude_code_run_lifecycle.R"),
    pos("R/module_claude_code.R")
  )

  expect_lt(
    pos("R/helpers_claude_code_server_setup.R"),
    pos("R/module_claude_code.R")
  )
})

test_that("admin geri bildirim helper dosyaları modülden önce yükleniyor", {
  paths <- .load_source_manifest_paths_for_contract()

  pos <- function(path) match(path, paths)

  expect_false(is.na(pos("R/helpers_admin_geri_bildirim.R")))
  expect_false(is.na(pos("R/helpers_admin_geri_bildirim_queries.R")))
  expect_false(is.na(pos("R/module_admin_geri_bildirim.R")))

  expect_lt(
    pos("R/helpers_admin_geri_bildirim.R"),
    pos("R/helpers_admin_geri_bildirim_queries.R")
  )

  expect_lt(
    pos("R/helpers_admin_geri_bildirim_queries.R"),
    pos("R/module_admin_geri_bildirim.R")
  )
})

test_that("admin hata analizi helper dosyaları modülden önce yükleniyor", {
  paths <- .load_source_manifest_paths_for_contract()

  pos <- function(path) match(path, paths)

  expect_false(is.na(pos("R/helpers_admin_hata_analizi.R")))
  expect_false(is.na(pos("R/helpers_admin_hata_heatmap_data.R")))
  expect_false(is.na(pos("R/helpers_admin_hata_detail_runtime.R")))
  expect_false(is.na(pos("R/module_admin_hata_analizi.R")))

  expect_lt(
    pos("R/helpers_admin_hata_analizi.R"),
    pos("R/helpers_admin_hata_heatmap_data.R")
  )

  expect_lt(
    pos("R/helpers_admin_hata_heatmap_data.R"),
    pos("R/helpers_admin_hata_detail_runtime.R")
  )

  expect_lt(
    pos("R/helpers_admin_hata_detail_runtime.R"),
    pos("R/module_admin_hata_analizi.R")
  )
})

test_that("file manager policy ve UI yardımcıları dosya yöneticisi sunucu modülünden önce yükleniyor", {
  paths <- .load_source_manifest_paths_for_contract()

  pos <- function(path) match(path, paths)

  expect_false(is.na(pos("R/helpers_files_path.R")))
  expect_false(is.na(pos("R/helpers_file_manager_policy.R")))
  expect_false(is.na(pos("R/helpers_file_manager_context_policy.R")))
  expect_false(is.na(pos("R/helpers_file_manager_table.R")))
  expect_false(is.na(pos("R/helpers_file_manager_refresh_guard.R")))
  expect_false(is.na(pos("R/helpers_file_manager_session_registry.R")))
  expect_false(is.na(pos("R/helpers_file_manager_runtime.R")))
  expect_false(is.na(pos("R/helpers_file_manager_storage.R")))
  expect_false(is.na(pos("R/helpers_file_manager_delete_runtime.R")))
  expect_false(is.na(pos("R/helpers_file_manager_state_runtime.R")))
  expect_false(is.na(pos("R/helpers_file_manager_attach_client.R")))
  expect_false(is.na(pos("R/module_file_manager_ui.R")))

  expect_lt(pos("R/helpers_files_path.R"), pos("R/helpers_files.R"))
  expect_lt(pos("R/helpers_files.R"), pos("R/helpers_file_manager_policy.R"))
  expect_lt(pos("R/helpers_file_manager_policy.R"), pos("R/helpers_file_manager_context_policy.R"))
  expect_lt(pos("R/helpers_file_manager_context_policy.R"), pos("R/helpers_file_manager_table.R"))
  expect_lt(pos("R/helpers_file_manager_table.R"), pos("R/helpers_file_manager_refresh_guard.R"))
  expect_lt(pos("R/helpers_file_manager_refresh_guard.R"), pos("R/helpers_file_manager_session_registry.R"))
  expect_lt(pos("R/helpers_file_manager_session_registry.R"), pos("R/helpers_file_manager_runtime.R"))
  expect_lt(pos("R/helpers_file_manager_runtime.R"), pos("R/helpers_file_manager_storage.R"))
  expect_lt(pos("R/helpers_file_manager_storage.R"), pos("R/helpers_file_manager_delete_runtime.R"))
  expect_lt(pos("R/helpers_file_manager_delete_runtime.R"), pos("R/helpers_file_manager_state_runtime.R"))
  expect_lt(pos("R/helpers_file_manager_state_runtime.R"), pos("R/helpers_file_manager_attach_client.R"))
  expect_lt(pos("R/helpers_file_manager_attach_client.R"), pos("R/module_file_manager.R"))
  expect_lt(pos("R/helpers_file_manager_state_runtime.R"), pos("R/module_file_manager_ui.R"))
  expect_lt(pos("R/module_file_manager_ui.R"), pos("R/module_file_manager.R"))
})