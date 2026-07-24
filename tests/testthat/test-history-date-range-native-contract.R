# ==============================================================================
# Dosya Yolu: tests/testthat/test-history-date-range-native-contract.R
# Açıklama: Söyleşi Geçmişi tarih aralığının bootstrap-datepicker bağımlılığı
#           üretmeden çalışmasını korur.
# ==============================================================================

.read_history_date_contract_text <- function(...) {
  full_path <- file.path(resolve_repo_root_for_tests(), ...)

  if (!file.exists(full_path)) {
    stop(sprintf("Beklenen dosya bulunamadı: %s", full_path), call. = FALSE)
  }

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

  gsub("\\r\\n?|\\r", "\n", enc2utf8(txt), perl = TRUE)
}

test_that("Söyleşi Geçmişi yerel tarih aralığı bootstrap-datepicker yükletmez", {
  module_text <- .read_history_date_contract_text("R", "module_chat_history.R")
  manifest_text <- .read_history_date_contract_text("R", "config_ui_assets.R")
  js_text <- .read_history_date_contract_text("www", "js", "history_date_range.js")
  css_text <- .read_history_date_contract_text("www", "css", "date_picker.css")

  expect_false(
    grepl("dateRangeInput\\s*\\(", module_text, perl = TRUE),
    info = "Söyleşi Geçmişi dateRangeInput kullanırsa bootstrap-datepicker uyarıları geri gelir."
  )

  expect_false(
    grepl("updateDateRangeInput\\s*\\(", module_text, perl = TRUE),
    info = "Yerel tarih alanları updateDateRangeInput ile güncellenmemelidir."
  )

  expect_true(grepl("history-native-date-range", module_text, fixed = TRUE))
  expect_true(grepl('"js/history_date_range.js"', manifest_text, fixed = TRUE))
  expect_true(grepl("history-date-range-set", js_text, fixed = TRUE))
  expect_true(grepl("Shiny\\.setInputValue", js_text, perl = TRUE))
  expect_true(grepl("formatDisplayDate", js_text, fixed = TRUE))
  expect_true(grepl("match[3] + '/' + match[2] + '/' + match[1]", js_text, fixed = TRUE))
  expect_true(grepl("history-native-date-display-shell", css_text, fixed = TRUE))
})
