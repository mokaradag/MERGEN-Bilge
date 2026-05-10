# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-model-config-refactor-contract.R
# Açıklama: Bilge Yolaç model/settings helper refactor sözleşmesini korur.
# ==============================================================================

.read_repo_text_cc_model_config_contract <- function(path) {
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

.extract_safe_source_paths_cc_model_config <- function(text) {
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

.source_claude_code_model_config_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  test_env <- new.env(parent = globalenv())

  test_env$`%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }

  test_env$log_info <- function(...) invisible(NULL)
  test_env$log_warn <- function(...) invisible(NULL)
  test_env$CLAUDE_CODE_LOG_PREFIX <- "[TEST]"
  test_env$api_config <- list()

  test_env$get_local_model_capabilities <- function(model_id, api_config = NULL) {
    switch(
      model_id,
      "thinking-model" = list(thinking = TRUE, stream_reasoning = TRUE),
      "plain-model" = list(thinking = FALSE),
      list()
    )
  }

  test_env$claude_code_varsayilan_etiket <- "Varsayılan"
  test_env$claude_code_model_tiers <- list(
    list(
      anahtar_deseni = "HAIKU|FAST|HIZLI",
      etiket = "Hızlı",
      ikon = "fa-bolt",
      ikon_unicode = "\\u26A1",
      aciklama = "Hızlı model"
    ),
    list(
      anahtar_deseni = "SONNET|BALANCED|DENGELI",
      etiket = "Dengeli",
      ikon = "fa-scale-balanced",
      ikon_unicode = "\\u2696",
      aciklama = "Dengeli model"
    ),
    list(
      anahtar_deseni = "OPUS|POWER|GUCLU",
      etiket = "Güçlü",
      ikon = "fa-brain",
      ikon_unicode = "\\u1F9E0",
      aciklama = "Güçlü model"
    )
  )

  source(
    file.path(repo_root, "R", "helpers_claude_code_model_config.R"),
    encoding = "UTF-8",
    local = test_env
  )

  test_env
}

test_that("Claude Code model/settings yardımcıları ayrı dosyaya taşınmıştır", {
  repo_root <- resolve_repo_root_for_tests()

  expect_true(file.exists(file.path(repo_root, "R", "helpers_claude_code_model_config.R")))
  expect_true(file.exists(file.path(repo_root, "R", "helpers_claude_code_session_context.R")))
  expect_true(file.exists(file.path(repo_root, "R", "helpers_claude_code_process.R")))
  expect_true(file.exists(file.path(repo_root, "R", "helpers_claude_code.R")))

  model_config_text <- .read_repo_text_cc_model_config_contract(
    "R/helpers_claude_code_model_config.R"
  )
  
  old_text <- .read_repo_text_cc_model_config_contract(
    "R/helpers_claude_code.R"
  )
  
  process_text <- .read_repo_text_cc_model_config_contract(
    "R/helpers_claude_code_process.R"
  )

  moved_functions <- c(
    "resolve_claude_cli_path",
    "read_claude_settings_json",
    "build_model_tier_choices",
    "parse_claude_code_env_list",
    "get_claude_code_model_capabilities",
    "get_claude_code_runtime_model_capabilities",
    "is_claude_code_thinking_model",
    "prompt_mentions_binary_document_type",
    "prompt_requests_document_operation",
    "workdir_has_binary_documents",
    "resolve_claude_code_execution_model"
  )

  for (fn in moved_functions) {
    pattern <- paste0(fn, "\\s*<-\\s*function\\s*\\(")

    expect_true(
      grepl(pattern, model_config_text, perl = TRUE),
      info = sprintf("%s yeni model/config dosyasında tanımlı olmalıdır.", fn)
    )

    expect_false(
      grepl(pattern, old_text, perl = TRUE),
      info = sprintf("%s R/helpers_claude_code.R içine geri taşınmamalıdır.", fn)
    )
  }

  process_functions <- c(
    "resolve_node_path",
    "escape_non_ascii",
    "ensure_utf8",
    "is_windows_unc_path",
    "normalize_cmd_workdir",
    "build_processx_command",
    "parse_claude_code_json_output",
    "get_safe_claude_cli_workdir"
  )

  for (fn in process_functions) {
    pattern <- paste0(fn, "\\s*<-\\s*function\\s*\\(")

    expect_true(
      grepl(pattern, process_text, perl = TRUE),
      info = sprintf("%s yeni process helper dosyasında tanımlı olmalıdır.", fn)
    )

    expect_false(
      grepl(pattern, old_text, perl = TRUE),
      info = sprintf("%s R/helpers_claude_code.R içine geri taşınmamalıdır.", fn)
    )
  }

  session_context_text <- .read_repo_text_cc_model_config_contract(
    "R/helpers_claude_code_session_context.R"
  )
  module_text <- .read_repo_text_cc_model_config_contract(
    "R/module_claude_code.R"
  )

  expect_true(
    grepl(
      "cc_create_active_character_reactive\\s*<-\\s*function\\s*\\(",
      session_context_text,
      perl = TRUE
    ),
    info = "Aktif karakter bağlamı helper dosyasında tanımlı olmalıdır."
  )

  expect_true(
    grepl(
      "cc_create_user_first_name_reactive\\s*<-\\s*function\\s*\\(",
      session_context_text,
      perl = TRUE
    ),
    info = "Kullanıcı adı bağlamı helper dosyasında tanımlı olmalıdır."
  )

  expect_false(
    grepl("get_active_character\\s*<-\\s*reactive\\s*\\(", module_text, perl = TRUE),
    info = "Aktif karakter reactive bloğu module_claude_code.R içine geri taşınmamalıdır."
  )

  expect_false(
    grepl("kullanici_adi\\s*<-\\s*reactive\\s*\\(", module_text, perl = TRUE),
    info = "Kullanıcı adı reactive bloğu module_claude_code.R içine geri taşınmamalıdır."
  )
})

test_that("Claude Code model/config source sırası korunuyor", {
  expect_source_manifest_order_for_tests(
    c(
      "R/config_claude_code.R",
      "R/helpers_claude_code_model_config.R",
      "R/helpers_claude_code_session_context.R",
      "R/helpers_claude_code_process.R",
      "R/helpers_claude_code.R",
      "R/helpers_claude_code_streaming.R"
    ),
    label = "Claude Code model/config source sırası bozulmuş:"
  )
})

test_that("Claude Code model/config dosyaları parse edilebilir kalır", {
  repo_root <- resolve_repo_root_for_tests()

  expect_silent(parse(
    file.path(repo_root, "R", "helpers_claude_code_model_config.R"),
    encoding = "UTF-8"
  ))
  
  expect_silent(parse(
    file.path(repo_root, "R", "helpers_claude_code_session_context.R"),
    encoding = "UTF-8"
  ))
  
  expect_silent(parse(
    file.path(repo_root, "R", "helpers_claude_code_process.R"),
    encoding = "UTF-8"
  ))

  expect_silent(parse(
    file.path(repo_root, "R", "helpers_claude_code.R"),
    encoding = "UTF-8"
  ))
})

test_that("Claude Code model/config helper davranışı korunur", {
  test_env <- .source_claude_code_model_config_for_test()

  expect_equal(
    test_env$parse_claude_code_env_list("a,b; c\n d\r\n"),
    c("a", "b", "c", "d")
  )

  withr::local_envvar(c(
    CLAUDE_CODE_THINKING_MODELS = "env-thinking",
    CLAUDE_CODE_BINARY_DOC_EXTENSIONS = "pdf,xlsx,docx",
    CLAUDE_CODE_AUTO_FALLBACK_NON_THINKING_FOR_BINARY_DOCS = "TRUE"
  ))

  caps <- test_env$get_claude_code_model_capabilities()

  expect_equal(caps$thinking_models, "env-thinking")
  expect_equal(caps$binary_doc_extensions, c("pdf", "xlsx", "docx"))
  expect_true(caps$auto_fallback_non_thinking_for_binary_docs)

  expect_true(test_env$is_claude_code_thinking_model("thinking-model"))
  expect_false(test_env$is_claude_code_thinking_model("plain-model"))
  expect_true(test_env$is_claude_code_thinking_model("env-thinking"))

  expect_true(test_env$prompt_mentions_binary_document_type("Bu PDF dosyasını incele."))
  expect_true(test_env$prompt_mentions_binary_document_type("Excel çalışma kitabını analiz et."))
  expect_false(test_env$prompt_mentions_binary_document_type("Merhaba, nasılsın?"))

  expect_true(test_env$prompt_requests_document_operation("Bu dosyayı özetler misin?"))
  expect_true(test_env$prompt_requests_document_operation("Please summarize this file."))
  expect_false(test_env$prompt_requests_document_operation("Bugün hava güzel."))
})

test_that("Claude Code çalışma dizini ikili doküman tespiti korunur", {
  test_env <- .source_claude_code_model_config_for_test()

  tmp <- withr::local_tempdir()
  writeLines("x", file.path(tmp, "notlar.txt"), useBytes = TRUE)

  expect_false(test_env$workdir_has_binary_documents(tmp, extensions = c("pdf", "xlsx")))

  writeLines("x", file.path(tmp, "rapor.pdf"), useBytes = TRUE)

  expect_true(test_env$workdir_has_binary_documents(tmp, extensions = c("pdf", "xlsx")))
})