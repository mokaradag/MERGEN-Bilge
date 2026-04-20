test_that("validate_username güvenli biçimi kabul eder", {
  expect_true(validate_username("mehmet_onur.karadag"))
})

test_that("validate_username güvensiz karakterleri reddeder", {
  expect_error(validate_username("mehmet onur"))
  expect_error(validate_username("mehmet;drop"))
})

test_that("validate_chat_title boş ve aşırı uzun başlığı reddeder", {
  expect_error(validate_chat_title(""))
  expect_error(validate_chat_title(strrep("a", 201)))
})

test_that("validate_message_content boş ve aşırı uzun içeriği reddeder", {
  expect_error(validate_message_content(""))
  expect_error(validate_message_content(strrep("x", 20001)))
})