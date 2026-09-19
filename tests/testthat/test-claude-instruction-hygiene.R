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

  expect_true(
    length(lines) <= 200L,
    info = "Kök CLAUDE.md 200 satırı aşmamalı; ayrıntıyı yol-kapsamlı kurala taşıyın."
  )
  expect_true(grepl("version_history.md", text, fixed = TRUE))
  expect_false(grepl("Current Product Version Reference", text, fixed = TRUE))
  expect_false(grepl("Current baseline coverage", text, fixed = TRUE))
})

test_that("canlı Claude yönergeleri ayrıntılı arşivi @ ile import etmez", {
  repo_root <- resolve_repo_root_for_tests()
  rules_dir <- file.path(repo_root, ".claude", "rules")
  live_files <- c(
    file.path(repo_root, "CLAUDE.md"),
    sort(list.files(
      rules_dir,
      pattern = "\\.md$",
      full.names = TRUE,
      recursive = TRUE
    ))
  )

  forbidden_import <- "@[^\\r\\n]*claude-code-full-contract-reference\\.md"

  for (path in live_files) {
    expect_false(
      grepl(forbidden_import, .claude_instruction_text(path), perl = TRUE),
      info = basename(path)
    )
  }
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
    expect_true(length(fences) >= 2L, info = basename(path))

    frontmatter <- lines[seq.int(2L, fences[2] - 1L)]
    paths_index <- which(trimws(frontmatter) == "paths:")
    expect_length(paths_index, 1L, info = basename(path))

    if (length(paths_index) == 1L) {
      after_paths <- if (paths_index < length(frontmatter)) {
        frontmatter[seq.int(paths_index + 1L, length(frontmatter))]
      } else {
        character()
      }
      next_key <- grep("^[[:alnum:]_-]+[[:space:]]*:", after_paths, perl = TRUE)
      if (length(next_key) > 0L) {
        after_paths <- head(after_paths, next_key[1] - 1L)
      }
      path_rows <- grep(
        "^[[:space:]]*-[[:space:]]+",
        after_paths,
        value = TRUE,
        perl = TRUE
      )
      path_values <- trimws(sub(
        "^[[:space:]]*-[[:space:]]+",
        "",
        path_rows,
        perl = TRUE
      ))
      path_values <- gsub("^[\"']|[\"']$", "", path_values, perl = TRUE)

      expect_true(any(nzchar(trimws(path_values))), info = basename(path))
    }
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
  mapped_lines <- lines[mapped]
  mapped_ids <- sub(
    "^\\|\\s*([0-9]+)\\s*\\|\\s*(H[234])\\s*\\|\\s*(.*?)\\s*\\|.*$",
    "\\1|\\2|\\3",
    mapped_lines,
    perl = TRUE
  )

  archive_lines <- .claude_instruction_lines(
    "docs/maintainers/claude-code-full-contract-reference.md"
  )
  source_start <- which(archive_lines == "# CLAUDE.md - MERGEN Bilge Codebase Guide")
  expect_length(source_start, 1L)
  if (length(source_start) != 1L) {
    return(invisible(NULL))
  }

  source_lines <- archive_lines[seq.int(source_start, length(archive_lines))]
  heading_indexes <- grep("^#{2,4}\\s+\\S", source_lines, perl = TRUE)
  heading_lines <- source_lines[heading_indexes]
  heading_levels <- paste0(
    "H",
    nchar(sub("\\s.*$", "", heading_lines, perl = TRUE))
  )
  heading_titles <- trimws(sub("^#{2,4}\\s+", "", heading_lines, perl = TRUE))
  archive_ids <- paste(heading_indexes, heading_levels, heading_titles, sep = "|")

  expect_identical(length(mapped), 314L)
  expect_identical(length(unique(mapped_ids)), length(mapped_ids))
  expect_identical(mapped_ids, archive_ids)
})
