# ==============================================================================
# Dosya Yolu: tests/testthat/test-chat-message-formatting-refactor-contract.R
# Açıklama: DB mesaj biçimlendirme fonksiyonlarının helpers_database.R içinden
#           ayrıldığını ve yeni helpers_chat_message_formatting.R dosyasının
#           üretim/test source sırasına doğru eklendiğini doğrular.
# ==============================================================================

.read_repo_text_chat_format_contract <- function(path) {
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

.byte_pos_chat_format_contract <- function(pattern, text) {
  pos <- regexpr(pattern, text, fixed = TRUE, useBytes = TRUE)[1]
  if (is.na(pos) || pos < 0L) NA_integer_ else as.integer(pos)
}

test_that("chat mesaj biçimlendirme helper dosyası repoda var", {
  repo_root <- resolve_repo_root_for_tests()

  expect_true(file.exists(file.path(
    repo_root,
    "R",
    "helpers_chat_message_formatting.R"
  )))
})

test_that("global.R chat mesaj biçimlendirme dosyasını helpers_database.R öncesinde source eder", {
  global_text <- .read_repo_text_chat_format_contract("global.R")

  expected_order <- c(
    'safe_source("R/helpers_db_connection.R"',
    'safe_source("R/helpers_db_validation.R"',
    'safe_source("R/helpers_chat_message_formatting.R"',
    'safe_source("R/helpers_database.R"'
  )

  positions <- vapply(
    expected_order,
    .byte_pos_chat_format_contract,
    integer(1),
    text = global_text
  )

  expect_false(
    any(is.na(positions)),
    info = paste(
      "global.R içinde eksik source kayıtları:",
      paste(expected_order[is.na(positions)], collapse = ", ")
    )
  )

  expect_true(
    all(diff(positions) > 0L),
    info = paste(
      "global.R source sırası bozulmuş:",
      paste(expected_order, collapse = " -> ")
    )
  )
})

test_that("test bootstrap chat mesaj biçimlendirme dosyasını helpers_database.R öncesinde yükler", {
  bootstrap_text <- .read_repo_text_chat_format_contract("tests/testthat/helper_bootstrap.R")

  expected_order <- c(
    '"helpers_db_connection.R"',
    '"helpers_db_validation.R"',
    '"helpers_chat_message_formatting.R"',
    '"helpers_database.R"'
  )

  positions <- vapply(
    expected_order,
    .byte_pos_chat_format_contract,
    integer(1),
    text = bootstrap_text
  )

  expect_false(
    any(is.na(positions)),
    info = paste(
      "helper_bootstrap.R içinde eksik source kayıtları:",
      paste(expected_order[is.na(positions)], collapse = ", ")
    )
  )

  expect_true(
    all(diff(positions) > 0L),
    info = "helper_bootstrap.R source sırası üretim sırası ile uyumlu değil."
  )
})

test_that("helpers_chat_message_formatting.R beklenen formatter fonksiyonlarını içerir", {
  txt <- .read_repo_text_chat_format_contract("R/helpers_chat_message_formatting.R")

  expected <- c(
    "db_message_get_image_base64 <- function",
    "db_message_resolve_image_path <- function",
    "db_message_render_image_html <- function",
    "db_message_process_text_content <- function",
    "db_message_format_row <- function",
    "format_chat_messages <- function"
  )

  found <- vapply(
    expected,
    function(pattern) grepl(pattern, txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_true(
    all(found),
    info = paste(
      "helpers_chat_message_formatting.R içinde eksik formatter fonksiyonları:",
      paste(expected[!found], collapse = ", ")
    )
  )
})

test_that("helpers_database.R format_chat_messages tanımını geri almıyor", {
  txt <- .read_repo_text_chat_format_contract("R/helpers_database.R")

  forbidden <- c(
    "format_chat_messages <- function",
    "db_message_get_image_base64 <- function",
    "db_message_resolve_image_path <- function",
    "db_message_render_image_html <- function",
    "db_message_process_text_content <- function",
    "db_message_format_row <- function"
  )

  matched <- forbidden[vapply(
    forbidden,
    function(pattern) grepl(pattern, txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    matched,
    character(0),
    info = paste(
      "helpers_database.R içine formatter fonksiyonları geri dönmüş:",
      paste(matched, collapse = ", ")
    )
  )
})

test_that("format_chat_messages boş veri için güvenli liste döndürür", {
  empty_df <- data.frame(
    MessageID = integer(0),
    MessageContent = character(0),
    MessageType = character(0),
    MessageTimestamp = as.POSIXct(character(0)),
    stringsAsFactors = FALSE
  )

  expect_equal(format_chat_messages(empty_df), list())
})

test_that("format_chat_messages normal metin mesajını temel alanlarla biçimlendirir", {
  msg_df <- data.frame(
    MessageID = 1L,
    MessageContent = "Merhaba **dünya**",
    MessageType = "user",
    MessageTimestamp = as.POSIXct("2026-04-25 12:00:00", tz = "UTC"),
    stringsAsFactors = FALSE
  )

  out <- format_chat_messages(msg_df)

  expect_type(out, "list")
  expect_length(out, 1L)

  expect_equal(out[[1]]$id, "1")
  expect_equal(out[[1]]$db_id, 1L)
  expect_equal(out[[1]]$content, "Merhaba **dünya**")
  expect_equal(out[[1]]$type, "user")
  expect_true(nzchar(out[[1]]$html_content))
  expect_true("has_code" %in% names(out[[1]]))
  expect_equal(out[[1]]$timestamp, "25.04.2026 - 12:00")
})

test_that("format_chat_messages ReasoningContent alanını mesaj nesnesine taşır", {
  msg_df <- data.frame(
    MessageID = 2L,
    MessageContent = "Yanıt",
    MessageType = "ai",
    MessageTimestamp = as.POSIXct("2026-04-25 13:00:00", tz = "UTC"),
    ReasoningContent = "Kısa reasoning özeti",
    stringsAsFactors = FALSE
  )

  out <- format_chat_messages(msg_df)

  expect_equal(out[[1]]$reasoning_content, "Kısa reasoning özeti")
  expect_equal(out[[1]]$reasoning_trace, "Kısa reasoning özeti")
})

test_that("format_chat_messages assistant ChartLab mesajlarını Shiny grafik output placeholder olarak biçimlendirir", {
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_chartlab_spec.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_chartlab.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  chart_spec <- list(
    type = "bar",
    data = data.frame(
      Kategori = c("A", "B"),
      Deger = c(10, 20),
      stringsAsFactors = FALSE
    ),
    mapping = list(x = "Kategori", y = "Deger"),
    params = list()
  )

  chart_json <- jsonlite::toJSON(
    chart_spec,
    auto_unbox = TRUE,
    dataframe = "rows",
    null = "null"
  )

  msg_df <- data.frame(
    MessageID = 3L,
    MessageContent = paste0("Grafik:\n\n```chartlab\n", chart_json, "\n```"),
    MessageType = "assistant",
    MessageTimestamp = as.POSIXct("2026-04-25 14:00:00", tz = "UTC"),
    stringsAsFactors = FALSE
  )

  out <- format_chat_messages(msg_df)

  expect_type(out, "list")
  expect_length(out, 1L)
  expect_equal(out[[1]]$type, "assistant")
  expect_false(out[[1]]$has_code)

  expect_true(
    grepl('id="chart_3_1"', out[[1]]$html_content, fixed = TRUE),
    info = "Geri yüklenen ChartLab mesajı aynı output id ile Shiny placeholder üretmelidir."
  )

  expect_true(
    grepl("shiny", out[[1]]$html_content, ignore.case = TRUE),
    info = "Geri yüklenen ChartLab mesajı statik data attribute yerine Shiny output placeholder kullanmalıdır."
  )

  expect_false(
    grepl("data-chartlab-spec", out[[1]]$html_content, fixed = TRUE),
    info = "Saved chat ChartLab render yolu ayrı JS renderer'a bağımlı kalmamalıdır."
  )
})