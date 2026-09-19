# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-instruction-hygiene.R
# Açıklama: Claude Code yönergelerinin her oturumda gereksiz bağlam tüketmemesi,
#           yol-kapsamlı kuralların koşullu kalması ve dinamik durum bilgisinin
#           kök sözleşmeye yeniden kopyalanmaması için yapısal regresyon testleri.
# ==============================================================================

.claude_instruction_text <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- if (file.exists(path)) path else file.path(repo_root, path)
  size <- suppressWarnings(file.info(full_path)$size[1])

  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)

  text <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )
  if (is.na(text)) text <- ""

  gsub("\r\n?|\r", "\n", text, perl = TRUE)
}

.claude_instruction_lines <- function(path) {
  strsplit(.claude_instruction_text(path), "\n", fixed = TRUE)[[1]]
}

test_that("kök CLAUDE.md kısa ve dinamik envanterlerden arındırılmış kalır", {
  lines <- .claude_instruction_lines("CLAUDE.md")
  text <- paste(lines, collapse = "\n")

  expect_lte(
    length(lines),
    200L,
    info = "Kök CLAUDE.md 200 satırı aşmamalı; ayrıntıyı yol-kapsamlı kurala taşıyın."
  )
  expect_true(grepl("version_history.md", text, fixed = TRUE))
  expect_false(grepl("Current Product Version Reference", text, fixed = TRUE))
  expect_false(grepl("Current baseline coverage", text, fixed = TRUE))
  expect_false(grepl("@docs/maintainers/claude-code-full-contract-reference.md", text, fixed = TRUE))
})

test_that("tüm proje Claude kuralları paths frontmatter ile koşullu kalır", {
  repo_root <- resolve_repo_root_for_tests()
  rules_dir <- file.path(repo_root, ".claude", "rules")
  files <- sort(list.files(
    rules_dir,
    pattern = "\\.md$",
    full.names = TRUE,
    recursive = TRUE
  ))

  expect_gte(length(files), 10L)

  for (path in files) {
    lines <- .claude_instruction_lines(path)
    fences <- which(lines == "---")

    expect_true(length(lines) >= 4L, info = basename(path))
    expect_identical(lines[1], "---", info = basename(path))
    expect_gte(length(fences), 2L, info = basename(path))

    frontmatter <- lines[seq.int(2L, fences[2] - 1L)]
    expect_true(any(trimws(frontmatter) == "paths:"), info = basename(path))
  }
})

test_that("eski ayrıntılı sözleşme canlı bellek dışında arşivlenmiş kalır", {
  archive <- .claude_instruction_text(
    "docs/maintainers/claude-code-full-contract-reference.md"
  )

  expect_gt(nchar(archive, type = "bytes"), 700000L)
  expect_true(grepl("REFERENCE ARCHIVE — NOT CLAUDE CODE MEMORY", archive, fixed = TRUE))
  expect_true(grepl("## Current Product Version Reference", archive, fixed = TRUE))
})

test_that("taşıma haritası eski tüm H2-H4 başlıklarını izlemeye devam eder", {
  lines <- .claude_instruction_lines(
    "docs/maintainers/claude-code-instruction-refactor-map.md"
  )
  mapped <- grep("^\\|\\s*[0-9]+\\s*\\|\\s*H[234]\\s*\\|", lines, perl = TRUE)

  expect_identical(length(mapped), 314L)
})
