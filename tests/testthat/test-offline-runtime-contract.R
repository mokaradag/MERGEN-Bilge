# ==============================================================================
# Dosya Yolu: tests/testthat/test-offline-runtime-contract.R
# Açıklama: Air-gapped üretim VM'i için runtime dosyalarında dış CDN/online
# bağımlılık izlerini arayan opsiyonel sıkı sözleşme testi.
# ==============================================================================

test_that("runtime dosyaları dış CDN/online bağımlılık içermemelidir", {
  strict <- tolower(Sys.getenv("MERGEN_STRICT_OFFLINE_TESTS", "false")) %in%
    c("1", "true", "yes", "on")

  testthat::skip_if_not(
    strict,
    "Sıkı offline runtime testi için MERGEN_STRICT_OFFLINE_TESTS=true ayarlayın."
  )

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
  runtime_files <- runtime_files[file.exists(ifelse(grepl("^/", runtime_files) | grepl("^[A-Za-z]:", runtime_files), runtime_files, file.path(repo_root, runtime_files)))]

  banned_patterns <- c(
    "cdn\\.jsdelivr\\.net",
    "cdnjs\\.cloudflare\\.com",
    "unpkg\\.com",
    "fonts\\.googleapis\\.com",
    "fonts\\.gstatic\\.com",
    "maxcdn\\.bootstrapcdn\\.com",
    "stackpath\\.bootstrapcdn\\.com",
    "raw\\.githubusercontent\\.com"
  )

  allowed_patterns <- c(
    "localhost",
    "127\\.0\\.0\\.1",
    "0\\.0\\.0\\.0",
    "w3\\.org/2000/svg"
  )

  violations <- character(0)

  for (path in runtime_files) {
    full_path <- if (grepl("^/", path) || grepl("^[A-Za-z]:", path)) path else file.path(repo_root, path)
    rel_path <- sub(paste0("^", gsub("\\\\", "/", repo_root), "/?"), "", gsub("\\\\", "/", full_path))

    txt <- paste(
      readLines(full_path, warn = FALSE, encoding = "UTF-8", skipNul = TRUE),
      collapse = "\n"
    )

    has_banned <- vapply(
      banned_patterns,
      function(pat) grepl(pat, txt, ignore.case = TRUE, perl = TRUE),
      logical(1)
    )

    has_allowed_only <- vapply(
      allowed_patterns,
      function(pat) grepl(pat, txt, ignore.case = TRUE, perl = TRUE),
      logical(1)
    )

    if (any(has_banned) && !all(has_allowed_only)) {
      violations <- c(
        violations,
        sprintf("%s -> %s", rel_path, paste(banned_patterns[has_banned], collapse = ", "))
      )
    }
  }

  expect_equal(
    violations,
    character(0),
    info = paste(
      "Runtime dosyalarında offline üretim VM'i için yasak dış bağımlılık bulundu:",
      paste(violations, collapse = "\n"),
      sep = "\n"
    )
  )
})