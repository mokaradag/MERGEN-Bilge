# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-instruction-hygiene.R
# Açıklama: Claude Code yönergelerinin her oturumda gereksiz bağlam tüketmemesi,
#           yol-kapsamlı kuralların koşullu kalması ve dinamik durum bilgisinin
#           kök sözleşmeye yeniden kopyalanmaması için yapısal regresyon testleri.
# ==============================================================================

.claude_instruction_text <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)
  paste(readLines(full_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

test_that("kök CLAUDE.md kısa ve dinamik envanterlerden arındırılmış kalır", {
  repo_root <- resolve_repo_root_for_tests()
  path <- file.path(repo_root, "CLAUDE.md")
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
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
  files <- sort(list.files(rules_dir, pattern = "\\.md$", full.names = TRUE))

  expect_gte(length(files), 10L)

  for (path in files) {
    lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
    expect_true(length(lines) >= 4L, info = basename(path))
    expect_identical(lines[1], "---", info = basename(path))
    expect_true(any(trimws(lines) == "paths:"), info = basename(path))

    second_fence <- which(lines[-1] == "---")
    expect_true(length(second_fence) >= 1L, info = basename(path))
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
