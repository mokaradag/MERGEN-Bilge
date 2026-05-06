# ==============================================================================
# Dosya Yolu: tests/testthat/test-server-boundary-contract.R
# Açıklama: server.R dosyasının iş mantığı/altyapı detaylarını tekrar içine
# almamasını doğrular. Amaç: server.R yalnızca modül bağlama ve oturum
# orkestrasyonu yapsın; DB, HTTP ve async detayları helper/modül katmanında kalsın.
# ==============================================================================

.read_repo_text_server_boundary_contract <- function(path) {
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

.strip_comments_for_server_boundary_contract <- function(text) {
  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  lines <- gsub("#.*$", "", lines, perl = TRUE)
  paste(lines, collapse = "\n")
}

test_that("server.R kimlik portlarını tek sözleşme üzerinden kullanır", {
  server_text <- .strip_comments_for_server_boundary_contract(
    .read_repo_text_server_boundary_contract("server.R")
  )

  expect_true(
    grepl(
      "identity_ports <- serverRuntimeBuildIdentityPorts(",
      server_text,
      fixed = TRUE,
      useBytes = TRUE
    ),
    info = "server.R kimlik erişimini serverRuntimeBuildIdentityPorts() üzerinden kurmalıdır."
  )

  forbidden_patterns <- c(
    "user_config_rv <- identity$user_config_rv",
    "resolve_current_user_id <- identity$resolve_current_user_id",
    "current_user_id_provider <- identity$current_user_id_provider",
    "current_user_first_name <- identity$get_first_name",
    "current_user_display_name <- identity$get_display_name"
  )

  matched <- forbidden_patterns[vapply(
    forbidden_patterns,
    function(pattern) grepl(pattern, server_text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    matched,
    character(0),
    info = paste(
      "server.R içinde kimlik alanlarını dağıtan yerel alias bulundu:",
      paste(matched, collapse = ", ")
    )
  )
})

test_that("server.R doğrudan veritabanı sorgusu çalıştırmaz", {
  server_text <- .strip_comments_for_server_boundary_contract(
    .read_repo_text_server_boundary_contract("server.R")
  )

  forbidden_patterns <- c(
    "dbGetQuery(",
    "DBI::dbGetQuery(",
    "dbExecute(",
    "DBI::dbExecute(",
    "dbConnect(",
    "DBI::dbConnect("
  )

  matched <- forbidden_patterns[vapply(
    forbidden_patterns,
    function(pattern) grepl(pattern, server_text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    matched,
    character(0),
    info = paste(
      "server.R içinde doğrudan DB erişimi bulundu. DB işleri helper/modül katmanında kalmalı:",
      paste(matched, collapse = ", ")
    )
  )
})

test_that("server.R doğrudan HTTP/LLM çağrısı yapmaz", {
  server_text <- .strip_comments_for_server_boundary_contract(
    .read_repo_text_server_boundary_contract("server.R")
  )

  forbidden_patterns <- c(
    "curl::",
    "httr::",
    "httr2::",
    "POST(",
    "GET(",
    "call_local_llm(",
    "call_local_llm_sse_worker("
  )

  matched <- forbidden_patterns[vapply(
    forbidden_patterns,
    function(pattern) grepl(pattern, server_text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    matched,
    character(0),
    info = paste(
      "server.R içinde doğrudan HTTP/LLM çağrısı bulundu. Bu işler helper katmanında kalmalı:",
      paste(matched, collapse = ", ")
    )
  )
})

test_that("server.R raw future/future_promise başlatmaz", {
  server_text <- .strip_comments_for_server_boundary_contract(
    .read_repo_text_server_boundary_contract("server.R")
  )

  forbidden_regex <- c(
    "(^|[^A-Za-z0-9_.])future\\s*\\(",
    "future::future\\s*\\(",
    "(^|[^A-Za-z0-9_.])future_promise\\s*\\(",
    "promises::future_promise\\s*\\("
  )

  matched <- forbidden_regex[vapply(
    forbidden_regex,
    function(pattern) grepl(pattern, server_text, perl = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    matched,
    character(0),
    info = paste(
      "server.R içinde raw future/future_promise kullanımı bulundu. tracked wrapper kullanılmalı:",
      paste(matched, collapse = ", ")
    )
  )
})