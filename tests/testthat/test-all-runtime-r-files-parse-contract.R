# ==============================================================================
# Dosya Yolu: tests/testthat/test-all-runtime-r-files-parse-contract.R
# Açıklama: Üretim çalışma zamanında kullanılan tüm R dosyalarının UTF-8 olarak
# parse edilebilir kaldığını doğrular. Uygulamayı başlatmaz, DB/LLM çağırmaz.
# ==============================================================================

.read_runtime_r_file_for_parse_contract <- function(path) {
  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  if (length(raw_data) >= 3L &&
      identical(as.integer(raw_data[1:3]), c(239L, 187L, 191L))) {
    raw_data <- raw_data[-(1:3)]
  }

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.collect_runtime_r_files_for_parse_contract <- function(repo_root) {
  candidates <- c(
    file.path(repo_root, "app.R"),
    file.path(repo_root, "global.R"),
    file.path(repo_root, "ui.R"),
    file.path(repo_root, "server.R"),
    file.path(repo_root, "welcome_screen.R"),
    list.files(
      file.path(repo_root, "R"),
      pattern = "\\.R$",
      recursive = TRUE,
      full.names = TRUE
    )
  )

  candidates <- unique(candidates[file.exists(candidates)])

  normalizePath(candidates, winslash = "/", mustWork = TRUE)
}

test_that("tüm runtime R dosyaları UTF-8 olarak parse edilebilir", {
  repo_root <- resolve_repo_root_for_tests()
  runtime_files <- .collect_runtime_r_files_for_parse_contract(repo_root)

  expect_gt(length(runtime_files), 50L)

  parse_errors <- character(0)

  for (path in runtime_files) {
    rel_path <- sub(
      paste0("^", gsub("([\\^$.|?*+(){}\\[\\]\\\\])", "\\\\\\1", normalizePath(repo_root, winslash = "/", mustWork = TRUE)), "/?"),
      "",
      normalizePath(path, winslash = "/", mustWork = TRUE),
      perl = TRUE
    )

    txt <- .read_runtime_r_file_for_parse_contract(path)

    err <- tryCatch(
      {
        parse(text = txt, keep.source = FALSE)
        NULL
      },
      error = function(e) e
    )

    if (!is.null(err)) {
      parse_errors <- c(
        parse_errors,
        sprintf("%s -> %s", rel_path, conditionMessage(err))
      )
    }
  }

  expect_equal(
    parse_errors,
    character(0),
    info = paste(
      "Parse edilemeyen runtime R dosyaları bulundu:",
      paste(parse_errors, collapse = "\n"),
      sep = "\n"
    )
  )
})