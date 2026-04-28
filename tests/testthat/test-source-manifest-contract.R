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

  expect_lt(pos("R/helpers_llm_response_postprocess.R"), pos("R/helpers_llm_api.R"))
  expect_lt(pos("R/helpers_llm_api.R"), pos("R/helpers_llm_sse.R"))
  expect_lt(pos("R/helpers_llm_sse.R"), pos("R/helpers_llm_worker.R"))
  expect_lt(pos("R/server_handler_true_streaming.R"), pos("R/server_send_message.R"))
})

test_that("kritik yardımcılar modüllerden önce yükleniyor", {
  global_text <- .read_repo_text_manifest_contract("global.R")
  paths <- .extract_safe_source_paths(global_text)

  pos <- function(path) match(path, paths)

  expect_false(is.na(pos("R/helpers_mcp_context.R")))
  expect_false(is.na(pos("R/helpers_mcp_table_readers.R")))
  expect_lt(pos("R/helpers_database.R"), pos("R/module_chat_history.R"))
  expect_lt(pos("R/helpers_mcp_context.R"), pos("R/helpers_mcp_tools.R"))
  expect_lt(pos("R/helpers_mcp_tools.R"), pos("R/helpers_mcp_table_readers.R"))
  expect_lt(pos("R/helpers_mcp_table_readers.R"), pos("R/module_summarization.R"))
  expect_lt(pos("R/helpers_send_message_core.R"), pos("R/server_send_message.R"))
  expect_lt(pos("R/helpers_health_checks.R"), pos("R/module_health.R"))
})

test_that("file manager policy ve UI yardımcıları dosya yöneticisi sunucu modülünden önce yükleniyor", {
  global_text <- .read_repo_text_manifest_contract("global.R")
  paths <- .extract_safe_source_paths(global_text)

  pos <- function(path) match(path, paths)

  expect_false(is.na(pos("R/helpers_file_manager_policy.R")))
  expect_false(is.na(pos("R/module_file_manager_ui.R")))

  expect_lt(pos("R/helpers_files.R"), pos("R/helpers_file_manager_policy.R"))
  expect_lt(pos("R/helpers_file_manager_policy.R"), pos("R/module_file_manager_ui.R"))
  expect_lt(pos("R/module_file_manager_ui.R"), pos("R/module_file_manager.R"))
})