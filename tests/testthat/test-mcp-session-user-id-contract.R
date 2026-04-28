# ==============================================================================
# Dosya Yolu: tests/testthat/test-mcp-session-user-id-contract.R
# Açıklama: MCP dosya çözümleme katmanında kullanıcı kimliği sözleşmesini korur.
#           current_session_files hiçbir koşulda kullanıcı kimliği gibi
#           kullanılmamalıdır.
# ==============================================================================

.read_repo_text_quiet_mcp_user <- function(path) {
  repo_root <- if (exists("resolve_repo_root_for_tests", mode = "function")) {
    resolve_repo_root_for_tests()
  } else {
    normalizePath(".", winslash = "/", mustWork = TRUE)
  }

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
  gsub("\\r\\n?|\\r", "\\n", txt, perl = TRUE)
}

local({
  repo_root <- if (exists("resolve_repo_root_for_tests", mode = "function")) {
    resolve_repo_root_for_tests()
  } else {
    normalizePath(".", winslash = "/", mustWork = TRUE)
  }

  source(
    file.path(repo_root, "R", "helpers_mcp_context.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
})

test_that("MCP kullanıcı kimliği dosya listesi üzerinden çözülmez", {
  txt <- .read_repo_text_quiet_mcp_user("R/helpers_mcp_context.R")

  expect_true(
    grepl(
      "helpers_mcp_tools$get_session_user_id <- function(session = NULL)",
      txt,
      fixed = TRUE,
      useBytes = TRUE
    )
  )

  expect_false(
    grepl(
      "session$userData$current_session_files %||%",
      txt,
      fixed = TRUE,
      useBytes = TRUE
    ),
    info = paste(
      "current_session_files bir dosya kayıt defteridir; kullanıcı kimliği değildir.",
      "Bu ifade SSO başlangıç yarışlarında yanlış user_id üretebilir."
    )
  )
})

test_that("MCP kullanıcı kimliği scalar karakter değere indirgenir", {
  txt <- .read_repo_text_quiet_mcp_user("R/helpers_mcp_context.R")

  beklenenler <- c(
    "helpers_mcp_tools$get_session_user_id <- function(session = NULL)",
    "candidate <- trimws(as.character(candidate[1]))",
    'tolower(candidate) %in% c("0", "unknown", "null", "na", "nan")'
  )

  bulunanlar <- vapply(
    beklenenler,
    function(x) grepl(x, txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_true(
    all(bulunanlar),
    info = paste("Eksik scalar user_id korumaları:", paste(beklenenler[!bulunanlar], collapse = ", "))
  )
})

test_that("MCP kullanıcı kimliği SSO placeholder değerlerini yok sayar", {
  session <- new.env(parent = emptyenv())
  session$userData <- new.env(parent = emptyenv())
  session$userData$current_session_files <- list(
    "dummy.xlsx" = list(name = "dummy.xlsx", path = "dummy.xlsx")
  )

  session$userData$user_id <- 0L
  expect_null(helpers_mcp_tools$get_session_user_id(session))

  session$userData$user_id <- "unknown"
  expect_null(helpers_mcp_tools$get_session_user_id(session))

  session$userData$user_id <- 42L
  expect_equal(helpers_mcp_tools$get_session_user_id(session), "42")
})