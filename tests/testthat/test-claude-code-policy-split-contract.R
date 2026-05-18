# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-policy-split-contract.R
# Açıklama: Bilge Yolaç güvenlik ilkesi (security_policy) ve yol/kök ilkesi
#           (path_policy) ile indirme staging (downloads) ve indirme sunum
#           (downloads_html) arasındaki dosya bölünme sözleşmelerini kilitler.
#           Amaç: maintainability ratchet 25+ fonksiyon eşiğini aşmadan UNC
#           güvenlik ve tıklanabilir indirme kartı eklemelerini sürdürebilmek.
# ==============================================================================

.read_repo_text_cc_policy_split_contract <- function(path) {
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

test_that("path policy helper'ları ayrı dosyada tutulur", {
  repo_root <- resolve_repo_root_for_tests()

  expect_true(file.exists(file.path(
    repo_root,
    "R",
    "helpers_claude_code_path_policy.R"
  )))

  path_policy_text <- .read_repo_text_cc_policy_split_contract(
    "R/helpers_claude_code_path_policy.R"
  )
  security_policy_text <- .read_repo_text_cc_policy_split_contract(
    "R/helpers_claude_code_security_policy.R"
  )

  moved_functions <- c(
    "cc_policy_split_roots",
    "cc_policy_normalize_path",
    "cc_policy_normalize_roots",
    "cc_policy_default_user_workspace",
    "cc_policy_allowed_workdir_roots",
    "cc_policy_allowed_output_roots",
    "cc_policy_path_inside_roots",
    "cc_policy_validate_workdir",
    "cc_policy_filter_generated_file_paths"
  )

  for (fn in moved_functions) {
    pattern <- paste0(fn, "\\s*<-\\s*function\\s*\\(")

    expect_true(
      grepl(pattern, path_policy_text, perl = TRUE),
      info = sprintf(
        "%s R/helpers_claude_code_path_policy.R içinde tanımlı olmalıdır.",
        fn
      )
    )

    expect_false(
      grepl(pattern, security_policy_text, perl = TRUE),
      info = sprintf(
        "%s R/helpers_claude_code_security_policy.R içine geri taşınmamalıdır.",
        fn
      )
    )
  }

  # security_policy.R'de kalması gereken (çalıştırma izin/CLI arg) helper'ları
  remaining_functions <- c(
    "cc_policy_truthy",
    "cc_policy_cli_list",
    "cc_policy_permission_mode",
    "cc_policy_permission_args",
    "cc_policy_user_prompt",
    "cc_policy_append_prompt_argument",
    "cc_policy_dangerous_permissions_allowed",
    "cc_policy_build_cli_args"
  )

  for (fn in remaining_functions) {
    pattern <- paste0(fn, "\\s*<-\\s*function\\s*\\(")

    expect_true(
      grepl(pattern, security_policy_text, perl = TRUE),
      info = sprintf(
        "%s R/helpers_claude_code_security_policy.R içinde tanımlı kalmalıdır.",
        fn
      )
    )
  }
})

test_that("path policy ve security policy source sırası korunur", {
  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_claude_code_runtime_workdir.R",
      "R/helpers_claude_code_security_policy.R",
      "R/helpers_claude_code_path_policy.R",
      "R/helpers_claude_code_prompt_security_policy.R"
    ),
    label = "path policy split source sırası bozulmuş:"
  )
})

test_that("downloads HTML sunum katmanı ayrı dosyada tutulur", {
  repo_root <- resolve_repo_root_for_tests()

  expect_true(file.exists(file.path(
    repo_root,
    "R",
    "helpers_claude_code_downloads_html.R"
  )))

  html_text <- .read_repo_text_cc_policy_split_contract(
    "R/helpers_claude_code_downloads_html.R"
  )
  downloads_text <- .read_repo_text_cc_policy_split_contract(
    "R/helpers_claude_code_downloads.R"
  )

  moved_functions <- c(
    "build_claude_code_display_path",
    "format_claude_code_generated_downloads_html"
  )

  for (fn in moved_functions) {
    pattern <- paste0(fn, "\\s*<-\\s*function\\s*\\(")

    expect_true(
      grepl(pattern, html_text, perl = TRUE),
      info = sprintf(
        "%s R/helpers_claude_code_downloads_html.R içinde tanımlı olmalıdır.",
        fn
      )
    )

    expect_false(
      grepl(pattern, downloads_text, perl = TRUE),
      info = sprintf(
        "%s R/helpers_claude_code_downloads.R içine geri taşınmamalıdır.",
        fn
      )
    )
  }

  # downloads.R'de kalması gereken staging/path/collect helper'ları
  remaining_functions <- c(
    "get_claude_code_download_root",
    "sanitize_claude_code_download_segment",
    "format_claude_code_download_size",
    "resolve_claude_code_generated_path",
    "list_claude_code_generated_file_paths",
    "stage_claude_code_downloads",
    "collect_claude_code_generated_downloads",
    "cc_stage_tool_use_write_paths_as_downloads",
    "cc_collect_streaming_run_downloads"
  )

  for (fn in remaining_functions) {
    pattern <- paste0(fn, "\\s*<-\\s*function\\s*\\(")

    expect_true(
      grepl(pattern, downloads_text, perl = TRUE),
      info = sprintf(
        "%s R/helpers_claude_code_downloads.R içinde tanımlı kalmalıdır.",
        fn
      )
    )
  }
})

test_that("downloads ve downloads_html source sırası korunur", {
  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_claude_code_downloads.R",
      "R/helpers_claude_code_downloads_html.R",
      "R/helpers_claude_code_existing_file_link.R"
    ),
    label = "downloads split source sırası bozulmuş:"
  )
})

test_that("format_claude_code_existing_file_link_html duplicate olarak downloads/html dosyalarında değil", {
  downloads_text <- .read_repo_text_cc_policy_split_contract(
    "R/helpers_claude_code_downloads.R"
  )
  html_text <- .read_repo_text_cc_policy_split_contract(
    "R/helpers_claude_code_downloads_html.R"
  )

  pattern <- "format_claude_code_existing_file_link_html\\s*<-\\s*function\\s*\\("

  expect_false(
    grepl(pattern, downloads_text, perl = TRUE),
    info = paste(
      "format_claude_code_existing_file_link_html ana downloads dosyasına geri",
      "taşınmamalıdır; tanım R/helpers_claude_code_existing_file_link.R'dedir."
    )
  )

  expect_false(
    grepl(pattern, html_text, perl = TRUE),
    info = paste(
      "format_claude_code_existing_file_link_html downloads_html dosyasında",
      "tekrar tanımlanmamalıdır; tanım R/helpers_claude_code_existing_file_link.R'dedir."
    )
  )
})
