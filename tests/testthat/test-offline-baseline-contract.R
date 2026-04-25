# ==============================================================================
# Dosya Yolu: tests/testthat/test-offline-baseline-contract.R
# Açıklama: Air-gapped Windows VM üretim ortamı için temel offline sözleşmeleri
#           varsayılan test koşumunda doğrular. Uygulamayı başlatmaz.
# ==============================================================================

.read_repo_text_for_offline_contract <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  if (length(raw_data) >= 3L &&
      identical(as.integer(raw_data[1:3]), c(239L, 187L, 191L))) {
    raw_data <- raw_data[-(1:3)]
  }

  raw_data <- raw_data[raw_data != as.raw(0)]

  txt <- rawToChar(raw_data, multiple = FALSE)
  Encoding(txt) <- "UTF-8"
  txt <- enc2utf8(txt)
  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)

  txt
}

test_that("runtime kodu varsayılan koşumda açık CDN/public asset bağımlılığı içermez", {
  repo_root <- resolve_repo_root_for_tests()

  runtime_files <- c(
    "app.R",
    "global.R",
    "ui.R",
    "server.R",
    "welcome_screen.R",
    list.files(file.path(repo_root, "R"), pattern = "\\.R$", recursive = TRUE, full.names = TRUE),
    list.files(file.path(repo_root, "www", "js"), pattern = "\\.js$", recursive = TRUE, full.names = TRUE),
    list.files(file.path(repo_root, "www", "css"), pattern = "\\.css$", recursive = TRUE, full.names = TRUE)
  )

  runtime_files <- unique(runtime_files)
  runtime_files <- runtime_files[file.exists(runtime_files) | file.exists(file.path(repo_root, runtime_files))]

  banned_patterns <- c(
    "cdn.jsdelivr.net",
    "cdnjs.cloudflare.com",
    "unpkg.com",
    "fonts.googleapis.com",
    "fonts.gstatic.com",
    "maxcdn.bootstrapcdn.com",
    "stackpath.bootstrapcdn.com",
    "raw.githubusercontent.com",
    "code.jquery.com"
  )

  violations <- character(0)

  for (path in runtime_files) {
    full_path <- if (file.exists(path)) path else file.path(repo_root, path)
    rel_path <- gsub("\\\\", "/", sub(
      paste0("^", gsub("\\\\", "/", repo_root), "/?"),
      "",
      gsub("\\\\", "/", full_path)
    ))

    txt <- .read_repo_text_for_offline_contract(rel_path)

    matched <- banned_patterns[vapply(
      banned_patterns,
      function(pattern) grepl(pattern, txt, fixed = TRUE, ignore.case = TRUE, useBytes = TRUE),
      logical(1)
    )]

    if (length(matched) > 0) {
      violations <- c(
        violations,
        sprintf("%s -> %s", rel_path, paste(matched, collapse = ", "))
      )
    }
  }

  expect_equal(
    violations,
    character(0),
    info = paste(
      "Offline üretim sözleşmesi ihlali: runtime dosyalarında dış asset/CDN bağımlılığı bulundu.",
      paste(violations, collapse = "\n"),
      sep = "\n"
    )
  )
})

test_that("testthat ana koşumu strict offline testleri yanlışlıkla zorunlu hale getirmez", {
  runner_text <- .read_repo_text_for_offline_contract("tests/testthat.R")

  expect_false(
    grepl("MERGEN_STRICT_OFFLINE_TESTS", runner_text, fixed = TRUE, useBytes = TRUE),
    info = paste(
      "tests/testthat.R içinde MERGEN_STRICT_OFFLINE_TESTS zorlanmamalı.",
      "Geniş offline tarama opsiyonel kalmalı; temel CDN yasağı ayrı testte zaten çalışıyor."
    )
  )
})