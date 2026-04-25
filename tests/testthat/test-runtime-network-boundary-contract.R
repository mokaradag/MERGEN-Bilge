# ==============================================================================
# Dosya Yolu: tests/testthat/test-runtime-network-boundary-contract.R
# Açıklama: Air-gapped VM üretimi için runtime kodunda kontrolsüz public internet
#           çağrısı ve CDN bağımlılığı oluşmasını engeller.
# ==============================================================================

.read_repo_text_network_contract <- function(path) {
  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(path, open = "rb")
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

.repo_relative_network_contract <- function(repo_root, path) {
  sub(
    paste0("^", gsub("([\\^$.|?*+(){}\\[\\]\\\\])", "\\\\\\1", repo_root), "/?"),
    "",
    normalizePath(path, winslash = "/", mustWork = FALSE),
    perl = TRUE
  )
}

.strip_js_css_comments_network_contract <- function(text) {
  # JS/CSS lisans ve dokümantasyon yorumlarındaki URL'ler runtime bağımlılığı
  # değildir. Önce block comment, sonra satır yorumlarını temizliyoruz.
  text <- gsub("/\\*.*?\\*/", "", text, perl = TRUE)

  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  lines <- gsub("^\\s*//.*$", "", lines, perl = TRUE)

  paste(lines, collapse = "\n")
}

.runtime_text_without_comments_network_contract <- function(path) {
  ext <- tolower(tools::file_ext(path))

  if (identical(ext, "r")) {
    exprs <- tryCatch(
      parse(file = path, encoding = "UTF-8", keep.source = FALSE),
      error = function(e) expression()
    )

    return(paste(
      vapply(
        exprs,
        function(expr) paste(deparse(expr, width.cutoff = 500L), collapse = "\n"),
        character(1)
      ),
      collapse = "\n"
    ))
  }

  text <- .read_repo_text_network_contract(path)

  if (ext %in% c("js", "css")) {
    text <- .strip_js_css_comments_network_contract(text)
  }

  text
}

.url_allowed_for_airgapped_contract <- function(url) {
  url_norm <- tolower(enc2utf8(as.character(url)[1]))

  allowed_prefixes <- c(
    "http://localhost",
    "http://127.0.0.1",
    "https://localhost",
    "https://127.0.0.1",
    "http://test.local"
  )

  if (any(startsWith(url_norm, allowed_prefixes))) {
    return(TRUE)
  }

  # Dokümantasyon / örnek alan adları: gerçek runtime bağımlılığı değildir.
  if (grepl("^https?://([^/]+\\.)?example\\.(com|org|net)(/|$)", url_norm, perl = TRUE)) {
    return(TRUE)
  }

  # SVG namespace URL'si internet çağrısı değildir; data-uri içindeki XML
  # standardı kimliğidir.
  if (startsWith(url_norm, "http://www.w3.org/2000/svg")) {
    return(TRUE)
  }

  # Kurum içi/intranet uçları. Korykos personel resmi servisi özellikle
  # üretimde kurum içinden kullanılır; public internet bağımlılığı değildir.
  internal_host_regex <- paste(
    c(
      "^https?://[^/]*\\.local(/|$)",
      "^https?://[^/]*\\.lan(/|$)",
      "^https?://[^/]*\\.intra(/|$)",
      "^https?://[^/]*\\.internal(/|$)",
      "^https?://korykos\\.",
      "^https?://mergen\\.",
      "^https?://wiki\\.sirket\\.com"
    ),
    collapse = "|"
  )

  if (grepl(internal_host_regex, url_norm, perl = TRUE)) {
    return(TRUE)
  }

  # Kuruma özel ek izin gerekiyorsa test ortamında regex verilebilir.
  # Örnek:
  # Sys.setenv(MERGEN_ALLOWED_INTERNAL_URL_REGEX = "^https?://[^/]*\\.firma\\.com\\.tr")
  extra_allowed_regex <- Sys.getenv("MERGEN_ALLOWED_INTERNAL_URL_REGEX", "")
  if (nzchar(extra_allowed_regex) &&
      grepl(extra_allowed_regex, url_norm, perl = TRUE, ignore.case = TRUE)) {
    return(TRUE)
  }

  FALSE
}

test_that("runtime dosyaları açık public URL bağımlılığı eklemiyor", {
  repo_root <- resolve_repo_root_for_tests()

  runtime_files <- c(
    file.path(repo_root, "app.R"),
    file.path(repo_root, "global.R"),
    file.path(repo_root, "ui.R"),
    file.path(repo_root, "server.R"),
    file.path(repo_root, "welcome_screen.R"),
    list.files(file.path(repo_root, "R"), pattern = "\\.R$", recursive = TRUE, full.names = TRUE),
    list.files(file.path(repo_root, "www", "js"), pattern = "\\.js$", recursive = TRUE, full.names = TRUE),
    list.files(file.path(repo_root, "www", "css"), pattern = "\\.css$", recursive = TRUE, full.names = TRUE)
  )

  runtime_files <- unique(normalizePath(
    runtime_files[file.exists(runtime_files)],
    winslash = "/",
    mustWork = FALSE
  ))

  violations <- character(0)

  for (f in runtime_files) {
    txt <- .runtime_text_without_comments_network_contract(f)

    urls <- regmatches(
      txt,
      gregexpr("https?://[^[:space:]'\"<>]+", txt, perl = TRUE, useBytes = TRUE)
    )[[1]]

    urls <- unique(urls[nzchar(urls)])

    if (length(urls) == 0) {
      next
    }

    disallowed <- urls[!vapply(
      urls,
      .url_allowed_for_airgapped_contract,
      logical(1)
    )]

    if (length(disallowed) > 0) {
      violations <- c(
        violations,
        sprintf(
          "%s -> %s",
          .repo_relative_network_contract(repo_root, f),
          paste(disallowed, collapse = ", ")
        )
      )
    }
  }

  expect_equal(
    violations,
    character(0),
    info = paste(
      "Air-gapped üretim sözleşmesi ihlali: runtime içinde izin verilmeyen public URL bulundu.",
      paste(violations, collapse = "\n"),
      sep = "\n"
    )
  )
})

test_that("runtime dosyaları CDN domainlerini kullanmıyor", {
  repo_root <- resolve_repo_root_for_tests()

  runtime_files <- c(
    file.path(repo_root, "app.R"),
    file.path(repo_root, "global.R"),
    file.path(repo_root, "ui.R"),
    file.path(repo_root, "server.R"),
    file.path(repo_root, "welcome_screen.R"),
    list.files(file.path(repo_root, "R"), pattern = "\\.R$", recursive = TRUE, full.names = TRUE),
    list.files(file.path(repo_root, "www", "js"), pattern = "\\.js$", recursive = TRUE, full.names = TRUE),
    list.files(file.path(repo_root, "www", "css"), pattern = "\\.css$", recursive = TRUE, full.names = TRUE)
  )

  runtime_files <- unique(normalizePath(
    runtime_files[file.exists(runtime_files)],
    winslash = "/",
    mustWork = FALSE
  ))

  banned_domains <- c(
    "cdn.jsdelivr.net",
    "cdnjs.cloudflare.com",
    "unpkg.com",
    "fonts.googleapis.com",
    "fonts.gstatic.com",
    "maxcdn.bootstrapcdn.com",
    "stackpath.bootstrapcdn.com",
    "code.jquery.com",
    "raw.githubusercontent.com"
  )

  violations <- character(0)

  for (f in runtime_files) {
    txt <- tolower(.runtime_text_without_comments_network_contract(f))

    matched <- banned_domains[vapply(
      banned_domains,
      function(domain) grepl(domain, txt, fixed = TRUE, useBytes = TRUE),
      logical(1)
    )]

    if (length(matched) > 0) {
      violations <- c(
        violations,
        sprintf(
          "%s -> %s",
          .repo_relative_network_contract(repo_root, f),
          paste(matched, collapse = ", ")
        )
      )
    }
  }

  expect_equal(
    violations,
    character(0),
    info = paste(
      "Runtime dosyalarında CDN/public asset bağımlılığı bulundu:",
      paste(violations, collapse = "\n"),
      sep = "\n"
    )
  )
})