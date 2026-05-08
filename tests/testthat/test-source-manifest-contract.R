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

.extract_safe_source_paths <- function(text) {
  m <- gregexpr(
    'safe_source\\("([^"]+)"\\s*,\\s*encoding\\s*=\\s*"UTF-8"',
    text,
    perl = TRUE,
    useBytes = TRUE
  )

  hits <- regmatches(text, m)[[1]]
  if (length(hits) == 0 || identical(hits, character(0))) {
    return(character(0))
  }

  sub(
    '.*safe_source\\("([^"]+)".*',
    "\\1",
    hits,
    perl = TRUE,
    useBytes = TRUE
  )
}

test_that("global.R safe_source manifestindeki dosyalar repoda gerçekten var", {
  repo_root <- resolve_repo_root_for_tests()
  global_text <- .read_repo_text_manifest_contract("global.R")
  paths <- .extract_safe_source_paths(global_text)

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

test_that("global.R manifestinde aynı R dosyası yanlışlıkla tekrar tekrar yüklenmiyor", {
  global_text <- .read_repo_text_manifest_contract("global.R")
  paths <- .extract_safe_source_paths(global_text)

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

test_that("LLM/SSE/worker yükleme sırası korunuyor", {
  global_text <- .read_repo_text_manifest_contract("global.R")
  paths <- .extract_safe_source_paths(global_text)

  pos <- function(path) match(path, paths)

  expect_false(is.na(pos("R/helpers_llm_stream_io.R")))
  expect_false(is.na(pos("R/helpers_llm_worker_payload.R")))
  expect_false(is.na(pos("R/helpers_llm_worker_tool_results.R")))

  expect_lt(pos("R/helpers_llm_response_postprocess.R"), pos("R/helpers_llm_api.R"))
  expect_lt(pos("R/helpers_llm_api.R"), pos("R/helpers_llm_stream_io.R"))
  expect_lt(pos("R/helpers_llm_stream_io.R"), pos("R/helpers_llm_sse.R"))
  expect_lt(pos("R/helpers_llm_sse.R"), pos("R/helpers_llm_worker_payload.R"))
  expect_lt(pos("R/helpers_llm_worker_payload.R"), pos("R/helpers_llm_worker_tool_results.R"))
  expect_lt(pos("R/helpers_llm_worker_tool_results.R"), pos("R/helpers_llm_worker.R"))
  expect_lt(pos("R/server_handler_true_streaming.R"), pos("R/server_send_message.R"))
})

test_that("file store indeks/registry yardımcıları config dosyasından sonra yükleniyor", {
  global_text <- .read_repo_text_manifest_contract("global.R")
  paths <- .extract_safe_source_paths(global_text)

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
  global_text <- .read_repo_text_manifest_contract("global.R")
  paths <- .extract_safe_source_paths(global_text)

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
  global_text <- .read_repo_text_manifest_contract("global.R")
  paths <- .extract_safe_source_paths(global_text)

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
  expect_lt(pos("R/helpers_mcp_bootstrap.R"), pos("R/helpers_mcp_tools.R"))
  expect_lt(pos("R/helpers_mcp_tools.R"), pos("R/helpers_mcp_table_readers.R"))
  expect_lt(pos("R/helpers_mcp_table_readers.R"), pos("R/helpers_mcp_file_resolver.R"))
  expect_lt(pos("R/helpers_mcp_file_resolver.R"), pos("R/helpers_mcp_schema_helpers.R"))
  expect_lt(pos("R/helpers_mcp_schema_helpers.R"), pos("R/helpers_mcp_basic_tools.R"))
  expect_lt(pos("R/helpers_mcp_basic_tools.R"), pos("R/helpers_mcp_chart_tools.R"))
  expect_lt(pos("R/helpers_mcp_chart_tools.R"), pos("R/helpers_chartlab_spec.R"))
  expect_lt(pos("R/helpers_chartlab_spec.R"), pos("R/helpers_chartlab.R"))
  expect_lt(pos("R/helpers_mcp_file_resolver.R"), pos("R/module_summarization.R"))
  expect_false(is.na(pos("R/helpers_send_message_request_lifecycle.R")))
  expect_lt(pos("R/helpers_send_message_request_lifecycle.R"), pos("R/helpers_send_message_core.R"))
  expect_lt(pos("R/helpers_send_message_request_lifecycle.R"), pos("R/server_handler_true_streaming.R"))
  expect_lt(pos("R/helpers_send_message_core.R"), pos("R/server_send_message.R"))
  expect_false(is.na(pos("R/helpers_user_session_identity.R")))
  expect_false(is.na(pos("R/server_init_user_session.R")))
  expect_false(is.na(pos("R/helpers_server_runtime_contracts.R")))
  expect_false(is.na(pos("R/server_runtime_context.R")))
  expect_false(is.na(pos("R/server_runtime_function_slot.R")))
  expect_false(is.na(pos("R/server_module_wiring.R")))
  expect_false(is.na(pos("R/utils_session_cleanup.R")))
  expect_false(is.na(pos("R/server_session_cache.R")))
  expect_false(is.na(pos("R/server_init_session_state.R")))
  expect_lt(pos("R/utils_session_cleanup.R"), pos("R/server_session_cache.R"))
  expect_lt(pos("R/utils_session_cleanup.R"), pos("R/server_init_session_state.R"))
  expect_lt(pos("R/module_user_identity.R"), pos("R/helpers_user_session_identity.R"))
  expect_lt(pos("R/helpers_user_session_identity.R"), pos("R/server_init_user_session.R"))
  expect_lt(pos("R/server_init_forward_refs.R"), pos("R/server_init_user_session.R"))
  expect_lt(pos("R/server_init_user_session.R"), pos("R/helpers_server_runtime_contracts.R"))
  expect_lt(pos("R/helpers_server_runtime_contracts.R"), pos("R/server_runtime_context.R"))
  expect_lt(pos("R/server_runtime_context.R"), pos("R/server_runtime_function_slot.R"))
  expect_lt(pos("R/server_runtime_function_slot.R"), pos("R/server_module_wiring.R"))
  expect_lt(pos("R/server_module_wiring.R"), pos("R/server_init_session_state.R"))
  expect_lt(pos("R/server_module_wiring.R"), pos("R/server_init_chat_runtime.R"))
  expect_false(is.na(pos("R/helpers_health_runtime_checks.R")))
  expect_lt(pos("R/helpers_health_formatters.R"), pos("R/helpers_health_runtime_checks.R"))
  expect_lt(pos("R/helpers_health_runtime_checks.R"), pos("R/helpers_health_checks.R"))
  expect_lt(pos("R/helpers_health_checks.R"), pos("R/module_health.R"))
})

test_that("Bilge Yolaç user guard ve server setup yardımcıları modülden önce yükleniyor", {
  global_text <- .read_repo_text_manifest_contract("global.R")
  paths <- .extract_safe_source_paths(global_text)

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
  global_text <- .read_repo_text_manifest_contract("global.R")
  paths <- .extract_safe_source_paths(global_text)

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

test_that("admin hata analizi helper dosyası modülden önce yükleniyor", {
  global_text <- .read_repo_text_manifest_contract("global.R")
  paths <- .extract_safe_source_paths(global_text)

  pos <- function(path) match(path, paths)

  expect_false(is.na(pos("R/helpers_admin_hata_analizi.R")))
  expect_false(is.na(pos("R/module_admin_hata_analizi.R")))

  expect_lt(
    pos("R/helpers_admin_hata_analizi.R"),
    pos("R/module_admin_hata_analizi.R")
  )
})

test_that("file manager policy ve UI yardımcıları dosya yöneticisi sunucu modülünden önce yükleniyor", {
  global_text <- .read_repo_text_manifest_contract("global.R")
  paths <- .extract_safe_source_paths(global_text)

  pos <- function(path) match(path, paths)

  expect_false(is.na(pos("R/helpers_files_path.R")))
  expect_false(is.na(pos("R/helpers_file_manager_policy.R")))
  expect_false(is.na(pos("R/helpers_file_manager_context_policy.R")))
  expect_false(is.na(pos("R/helpers_file_manager_table.R")))
  expect_false(is.na(pos("R/helpers_file_manager_refresh_guard.R")))
  expect_false(is.na(pos("R/helpers_file_manager_session_registry.R")))
  expect_false(is.na(pos("R/helpers_file_manager_runtime.R")))
  expect_false(is.na(pos("R/helpers_file_manager_storage.R")))
  expect_false(is.na(pos("R/helpers_file_manager_state_runtime.R")))
  expect_false(is.na(pos("R/module_file_manager_ui.R")))

  expect_lt(pos("R/helpers_files_path.R"), pos("R/helpers_files.R"))
  expect_lt(pos("R/helpers_files.R"), pos("R/helpers_file_manager_policy.R"))
  expect_lt(pos("R/helpers_file_manager_policy.R"), pos("R/helpers_file_manager_context_policy.R"))
  expect_lt(pos("R/helpers_file_manager_context_policy.R"), pos("R/helpers_file_manager_table.R"))
  expect_lt(pos("R/helpers_file_manager_table.R"), pos("R/helpers_file_manager_refresh_guard.R"))
  expect_lt(pos("R/helpers_file_manager_refresh_guard.R"), pos("R/helpers_file_manager_session_registry.R"))
  expect_lt(pos("R/helpers_file_manager_session_registry.R"), pos("R/helpers_file_manager_runtime.R"))
  expect_lt(pos("R/helpers_file_manager_runtime.R"), pos("R/helpers_file_manager_storage.R"))
  expect_lt(pos("R/helpers_file_manager_storage.R"), pos("R/helpers_file_manager_state_runtime.R"))
  expect_lt(pos("R/helpers_file_manager_state_runtime.R"), pos("R/module_file_manager_ui.R"))
  expect_lt(pos("R/module_file_manager_ui.R"), pos("R/module_file_manager.R"))
})