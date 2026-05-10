# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-workdir-scan-contract.R
# Açıklama: Bilge Yolaç çalışma dizini scan/snapshot helper extraction ve
#           dosya staging öncesi kararlılık bekleme sözleşmesini doğrular.
# ==============================================================================

.read_repo_text_cc_workdir_scan_contract <- function(path) {
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

  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.extract_safe_source_paths_cc_workdir_scan <- function(text) {
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

.source_cc_workdir_scan_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  test_env <- new.env(parent = globalenv())

  test_env$`%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }

  source(
    file.path(repo_root, "R", "helpers_claude_code_workdir_scan.R"),
    encoding = "UTF-8",
    local = test_env
  )

  test_env
}

test_that("Bilge Yolaç workdir scan yardımcıları ayrı dosyaya taşınmıştır", {
  repo_root <- resolve_repo_root_for_tests()

  expect_true(file.exists(file.path(
    repo_root,
    "R",
    "helpers_claude_code_workdir_scan.R"
  )))

  scan_text <- .read_repo_text_cc_workdir_scan_contract(
    "R/helpers_claude_code_workdir_scan.R"
  )
  snapshot_text <- .read_repo_text_cc_workdir_scan_contract(
    "R/helpers_claude_code_workdir_snapshot.R"
  )

  moved_functions <- c(
    "prompt_requests_binary_document_creation",
    "prompt_requests_existing_document_reading",
    "canonicalize_claude_code_file_path",
    "deduplicate_claude_code_file_paths",
    "snapshot_claude_code_workdir_files",
    "diff_claude_code_workdir_snapshot",
    "wait_for_stable_claude_code_file_paths"
  )

  for (fn in moved_functions) {
    pattern <- paste0(fn, "\\s*<-\\s*function\\s*\\(")

    expect_true(
      grepl(pattern, scan_text, perl = TRUE),
      info = sprintf(
        "%s R/helpers_claude_code_workdir_scan.R içinde tanımlı olmalıdır.",
        fn
      )
    )

    expect_false(
      grepl(pattern, snapshot_text, perl = TRUE),
      info = sprintf(
        "%s R/helpers_claude_code_workdir_snapshot.R içine geri taşınmamalıdır.",
        fn
      )
    )
  }
})

test_that("Bilge Yolaç workdir scan helper source sırası korunur", {
  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_claude_code_downloads.R",
      "R/helpers_claude_code_workdir_scan.R",
      "R/helpers_claude_code_workdir_snapshot.R",
      "R/helpers_claude_code_documents.R"
    ),
    label = "Bilge Yolaç workdir scan source sırası bozulmuş:"
  )
})

test_that("Bilge Yolaç workdir scan helper dosyası parse ve source edilebilir kalır", {
  repo_root <- resolve_repo_root_for_tests()

  expect_silent(parse(
    file.path(repo_root, "R", "helpers_claude_code_workdir_scan.R"),
    encoding = "UTF-8"
  ))

  expect_silent(.source_cc_workdir_scan_for_test())
})

test_that("workdir snapshot diff yeni ve değişen dosyaları yakalar", {
  test_env <- .source_cc_workdir_scan_for_test()

  workdir <- withr::local_tempdir()
  first_file <- file.path(workdir, "ilk.txt")
  second_file <- file.path(workdir, "ikinci.txt")

  writeLines("merhaba", first_file, useBytes = TRUE)

  before <- test_env$snapshot_claude_code_workdir_files(workdir)

  Sys.sleep(0.02)
  writeLines("merhaba dünya", first_file, useBytes = TRUE)
  writeLines("yeni dosya", second_file, useBytes = TRUE)

  changed <- test_env$diff_claude_code_workdir_snapshot(before, workdir)

  changed_basenames <- basename(changed)

  expect_true("ilk.txt" %in% changed_basenames)
  expect_true("ikinci.txt" %in% changed_basenames)
})

test_that("dosya kararlılık bekleyicisi yalnızca mevcut dosyaları kanonik döndürür", {
  test_env <- .source_cc_workdir_scan_for_test()

  workdir <- withr::local_tempdir()
  existing_file <- file.path(workdir, "çıktı.txt")
  missing_file <- file.path(workdir, "yok.txt")

  writeLines("Türkçe içerik", existing_file, useBytes = TRUE)

  stable <- test_env$wait_for_stable_claude_code_file_paths(
    c(existing_file, missing_file, existing_file),
    settle_ms = 0L,
    max_attempts = 1L
  )

  expect_length(stable, 1L)
  expect_equal(basename(stable), "çıktı.txt")
  expect_true(file.exists(stable))
})

test_that("download collector staging öncesi dosya kararlılık korumasını kullanır", {
  snapshot_text <- .read_repo_text_cc_workdir_scan_contract(
    "R/helpers_claude_code_workdir_snapshot.R"
  )

  expect_true(
    grepl(
      "wait_for_stable_claude_code_file_paths\\s*\\(",
      snapshot_text,
      perl = TRUE
    ),
    info = paste(
      "collect_claude_code_workdir_changes_downloads(),",
      "normalizasyon/staging öncesi wait_for_stable_claude_code_file_paths()",
      "çağırmalıdır."
    )
  )
})