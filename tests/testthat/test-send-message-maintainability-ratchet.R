# ==============================================================================
# Dosya Yolu: tests/testthat/test-send-message-maintainability-ratchet.R
# Açıklama: send_message lifecycle extraction kazanımının geri alınmasını engeller.
# ==============================================================================

.find_repo_root_send_message_ratchet <- function() {
  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "scripts"))) {
      return(candidate)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.as_int_env_send_message_ratchet <- function(name, default) {
  raw <- Sys.getenv(name, as.character(default))
  value <- suppressWarnings(as.integer(raw))

  if (is.na(value)) {
    stop(sprintf("%s geçersiz: %s", name, raw), call. = FALSE)
  }

  value
}

test_that("server_send_message.R request lifecycle extraction sonrası 800 satır altı kalır", {
  repo_root <- .find_repo_root_send_message_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  send_row <- report[
    grepl("(^|/)R/server_send_message\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  helper_row <- report[
    grepl("(^|/)R/helpers_send_message_request_lifecycle\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  expect_equal(
    nrow(send_row),
    1L,
    info = "R/server_send_message.R maintainability raporunda tek satır olarak görünmelidir."
  )

  expect_equal(
    nrow(helper_row),
    1L,
    info = "R/helpers_send_message_request_lifecycle.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_send_lines <- .as_int_env_send_message_ratchet("MERGEN_TEST_MAX_SERVER_SEND_MESSAGE_LINES", 799L)
  max_helper_lines <- .as_int_env_send_message_ratchet("MERGEN_TEST_MAX_SEND_MESSAGE_REQUEST_LIFECYCLE_LINES", 260L)
  max_helper_functions <- .as_int_env_send_message_ratchet("MERGEN_TEST_MAX_SEND_MESSAGE_REQUEST_LIFECYCLE_FUNCTIONS", 16L)

  expect_true(
    send_row$lines[1] <= max_send_lines,
    info = sprintf(
      "server_send_message.R request lifecycle extraction sonrası 800 satır altı kalmalıdır: %d > %d.",
      send_row$lines[1],
      max_send_lines
    )
  )

  expect_true(
    helper_row$lines[1] <= max_helper_lines,
    info = sprintf(
      "helpers_send_message_request_lifecycle.R küçük helper dosyası olarak kalmalıdır: %d > %d.",
      helper_row$lines[1],
      max_helper_lines
    )
  )

  expect_true(
    helper_row$functions[1] <= max_helper_functions,
    info = sprintf(
	  "helpers_send_message_request_lifecycle.R fonksiyon ifadesi sayısı kontrollü kalmalıdır: %d > %d."
      helper_row$functions[1],
      max_helper_functions
    )
  )
})