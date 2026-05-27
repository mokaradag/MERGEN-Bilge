# ==============================================================================
# Dosya Yolu: tests/testthat/test-streaming-markdown-safety-contract.R
# Açıklama: Browser-side streaming markdown HTML güvenliği sözleşmesi.
# ==============================================================================

.find_repo_root_streaming_markdown_safety <- function() {
  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        file.exists(file.path(candidate, "R/config_ui_assets.R")) &&
        dir.exists(file.path(candidate, "www", "js"))) {
      return(candidate)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.read_repo_text_streaming_markdown_safety <- function(path) {
  full_path <- file.path(.find_repo_root_streaming_markdown_safety(), path)

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

  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.source_ui_asset_config_streaming_markdown_safety <- function() {
  asset_env <- new.env(parent = globalenv())
  source(
    file.path(.find_repo_root_streaming_markdown_safety(), "R/config_ui_assets.R"),
    encoding = "UTF-8",
    local = asset_env
  )
  asset_env
}

.asset_pos_streaming_markdown_safety <- function(paths, path) {
  pos <- match(path, paths)
  if (is.na(pos)) {
    Inf
  } else {
    pos
  }
}

.function_slice_streaming_markdown_safety <- function(text, function_name, next_function_name = NULL) {
  start_pattern <- paste0("function ", function_name, "\\s*\\(")
  start <- regexpr(start_pattern, text, perl = TRUE)[[1]]

  if (start < 0) {
    return("")
  }

  sliced <- substring(text, start)

  if (!is.null(next_function_name)) {
    end_pattern <- paste0("\\n\\s*function ", next_function_name, "\\s*\\(")
    end <- regexpr(end_pattern, sliced, perl = TRUE)[[1]]

    if (end > 0) {
      sliced <- substring(sliced, 1, end - 1)
    }
  }

  sliced
}

test_that("streaming markdown güvenlik helper'ı manifestte doğru sırada yüklenir", {
  asset_env <- .source_ui_asset_config_streaming_markdown_safety()
  repo_root <- .find_repo_root_streaming_markdown_safety()
  js_paths <- asset_env$ui_asset_all_js()

  expect_true("js/streaming_markdown_safety.js" %in% asset_env$ui_asset_js_groups$critical)
  expect_true("js/markdown-parser.js" %in% asset_env$ui_asset_js_groups$critical)
  expect_true("js/streaming_manager.js" %in% asset_env$ui_asset_js_groups$critical)

  expect_lt(
    .asset_pos_streaming_markdown_safety(js_paths, "js/streaming_markdown_safety.js"),
    .asset_pos_streaming_markdown_safety(js_paths, "js/markdown-parser.js")
  )

  expect_lt(
    .asset_pos_streaming_markdown_safety(js_paths, "js/markdown-parser.js"),
    .asset_pos_streaming_markdown_safety(js_paths, "js/streaming_manager.js")
  )

  expect_lt(
    .asset_pos_streaming_markdown_safety(js_paths, "js/streaming_markdown_safety.js"),
    .asset_pos_streaming_markdown_safety(js_paths, "js/streaming_manager.js")
  )

  expect_true(any(vapply(
    asset_env$ui_asset_js_order_rules,
    function(rule) identical(rule, c("js/streaming_markdown_safety.js", "js/markdown-parser.js")),
    logical(1)
  )))

  expect_true(any(vapply(
    asset_env$ui_asset_js_order_rules,
    function(rule) identical(rule, c("js/markdown-parser.js", "js/streaming_manager.js")),
    logical(1)
  )))

  asset_env$ui_asset_validate(root = repo_root, check_files = FALSE)
})

test_that("raw streaming markdown prose innerHTML öncesinde escape edilir", {
  safety_text <- .read_repo_text_streaming_markdown_safety(
    "www/js/streaming_markdown_safety.js"
  )
  parser_text <- .read_repo_text_streaming_markdown_safety(
    "www/js/markdown-parser.js"
  )
  manager_text <- .read_repo_text_streaming_markdown_safety(
    "www/js/streaming_manager.js"
  )

  expect_true(grepl("window.MergenMarkdownSafety", safety_text, fixed = TRUE))
  expect_true(grepl("escapeHtml", safety_text, fixed = TRUE))
  expect_true(grepl("normalizeLanguage", safety_text, fixed = TRUE))
  expect_true(grepl("^[a-z0-9_-]{1,32}$", safety_text, fixed = TRUE))

  inline_slice <- .function_slice_streaming_markdown_safety(
    parser_text,
    "parseInlineMarkdown",
    "parseMarkdownWithoutCode"
  )

  pos_escape <- regexpr(
    "let html = safety.escapeHtml(text);",
    inline_slice,
    fixed = TRUE
  )[[1]]
  pos_strong <- regexpr(
    "html = html.replace(/\\*\\*",
    inline_slice,
    fixed = TRUE
  )[[1]]
  pos_em <- regexpr(
    "html = html.replace(/\\*(",
    inline_slice,
    fixed = TRUE
  )[[1]]

  expect_gt(pos_escape, 0)
  expect_gt(pos_strong, 0)
  expect_gt(pos_em, 0)
  expect_lt(pos_escape, pos_strong)
  expect_lt(pos_escape, pos_em)

  expect_false(grepl("let html = text;", parser_text, fixed = TRUE))
  expect_false(grepl(": state.accumulatedText;", manager_text, fixed = TRUE))
  expect_true(grepl("contentDiv.textContent = state.accumulatedText || '';", manager_text, fixed = TRUE))
})

test_that("parseMarkdownWithoutCode raw HTML'i doğrudan geçirmez", {
  parser_text <- .read_repo_text_streaming_markdown_safety(
    "www/js/markdown-parser.js"
  )

  markdown_slice <- .function_slice_streaming_markdown_safety(
    parser_text,
    "parseMarkdownWithoutCode",
    "escapeHtml"
  )

  expect_true(grepl("parseInlineMarkdown", markdown_slice, fixed = TRUE))
  expect_false(grepl("let html = text", markdown_slice, fixed = TRUE))
  expect_false(grepl("<script", parser_text, fixed = TRUE))
  expect_false(grepl("<img", parser_text, fixed = TRUE))
  expect_false(grepl("<a ", parser_text, fixed = TRUE))
  expect_false(grepl("href=", parser_text, fixed = TRUE))
  expect_false(grepl("onerror", parser_text, fixed = TRUE))
})

test_that("server-side final markdown HTML ham HTML'i kaçırır", {
  skip_if_not_installed("commonmark")

  repo_root <- .find_repo_root_streaming_markdown_safety()
  helper_path <- file.path(repo_root, "R/helpers_markdown_safety.R")

  expect_true(file.exists(helper_path))

  helper_env <- new.env(parent = globalenv())
  source(helper_path, encoding = "UTF-8", local = helper_env)

  html <- helper_env$render_safe_markdown_html(
    paste(
      "# Başlık <script>alert(1)</script>",
      "**Kalın <img src=x onerror=alert(1)>**",
      "- Madde <a href=\"javascript:alert(1)\">x</a>",
      "[x](javascript:alert(1))",
      sep = "\n"
    )
  )

  expect_false(grepl("<script", html, fixed = TRUE))
  expect_false(grepl("<img", html, fixed = TRUE))
  expect_false(grepl("<a href=\"javascript:", html, fixed = TRUE))

  # onerror= metni kaçırılmış düz metin içinde kalabilir; tehlikeli olan,
  # gerçek bir HTML etiketi üzerinde olay işleyici attribute'u oluşmasıdır.
  expect_false(grepl("<[^>]+\\sonerror\\s*=", html, perl = TRUE, ignore.case = TRUE))

  expect_true(grepl("&lt;script&gt;alert(1)&lt;/script&gt;", html, fixed = TRUE))
  expect_true(grepl("&lt;img src=x onerror=alert(1)&gt;", html, fixed = TRUE))
  expect_true(grepl("&lt;a href=", html, fixed = TRUE))
  expect_true(grepl("data-mergen-unsafe-href=\"removed\"", html, fixed = TRUE))
})

test_that("server-side markdown safety helper kaynak manifestinde doğru sıradadır", {
  manifest_text <- .read_repo_text_streaming_markdown_safety("R/config_source_manifest.R")
  messaging_text <- .read_repo_text_streaming_markdown_safety("R/helpers_messaging.R")
  formatting_text <- .read_repo_text_streaming_markdown_safety("R/helpers_chat_message_formatting.R")

  safety_pos <- regexpr('"R/helpers_markdown_safety.R"', manifest_text, fixed = TRUE)[[1]]
  formatting_pos <- regexpr('"R/helpers_chat_message_formatting.R"', manifest_text, fixed = TRUE)[[1]]
  messaging_pos <- regexpr('"R/helpers_messaging.R"', manifest_text, fixed = TRUE)[[1]]

  expect_gt(safety_pos, 0)
  expect_gt(formatting_pos, 0)
  expect_gt(messaging_pos, 0)
  expect_lt(safety_pos, formatting_pos)
  expect_lt(safety_pos, messaging_pos)

  expect_true(grepl("render_safe_markdown_html", messaging_text, fixed = TRUE))
  expect_true(grepl("render_safe_markdown_html", formatting_text, fixed = TRUE))
  expect_false(grepl("commonmark::markdown_html", messaging_text, fixed = TRUE))
})

test_that("tehlikeli streaming fixture'ları statik ve browser smoke kapsamındadır", {
  smoke_text <- .read_repo_text_streaming_markdown_safety("www/smoke/ux-smoke.html")
  parser_text <- .read_repo_text_streaming_markdown_safety("www/js/markdown-parser.js")

  # Not: ux-smoke.html inline <script> içinde gerçek </script> yazılamaz;
  # aksi durumda HTML parser script'i erken kapatır. Bu nedenle fixture'lar
  # smoke içinde parçalı kurulur ve burada parçalı sözleşme aranır.
  dangerous_fixtures <- c(
    "<scr",
    "ipt>alert(1)</scr",
    "ipt>",
    "<img src=x onerror=alert(1)>",
    "java",
    "script:alert(1)"
  )

  missing_from_smoke <- dangerous_fixtures[
    !vapply(
      dangerous_fixtures,
      function(fixture) grepl(fixture, smoke_text, fixed = TRUE),
      logical(1)
    )
  ]

  expect_equal(
    missing_from_smoke,
    character(0),
    info = paste(
      "Streaming HTML güvenlik smoke fixture'ları eksik:",
      paste(missing_from_smoke, collapse = ", ")
    )
  )

  expect_true(grepl("querySelector(\"script\")", smoke_text, fixed = TRUE))
  expect_true(grepl("querySelector(\"img\")", smoke_text, fixed = TRUE))
  expect_true(grepl("querySelector(\"a\")", smoke_text, fixed = TRUE))
  expect_true(grepl("alertCount === 0", smoke_text, fixed = TRUE))
  expect_true(grepl(".streaming-code pre code", smoke_text, fixed = TRUE))

  expect_true(grepl("'<h' + level + '>'", parser_text, fixed = TRUE))
  expect_true(grepl("'</h' + level + '>'", parser_text, fixed = TRUE))

  allowed_generated_constructs <- c(
    "<strong", "<em", "<code", "<pre", "<br", "<ul", "<li",
    "<div", "<span", "<i"
  )

  missing_allowed_constructs <- allowed_generated_constructs[
    !vapply(
      allowed_generated_constructs,
      function(tag) grepl(tag, parser_text, fixed = TRUE),
      logical(1)
    )
  ]

  expect_equal(missing_allowed_constructs, character(0))
})