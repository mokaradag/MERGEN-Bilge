# ==============================================================================
# Dosya Yolu: tests/testthat/test-db-chat-readers-behavior.R
# Açıklama: R/helpers_db_chat_readers.R içindeki saf kullanıcı-id ve zaman damgası
#           yardımcılarının davranışsal testleri. DB bağlantısı gerektirmez;
#           yalnızca .db_chat_valid_user_id / .db_chat_timestamp_missing /
#           .db_chat_as_numeric_timestamp karar mantığı doğrulanır.
# ==============================================================================

testthat::local_edition(3)

.dbr_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_db_chat_readers.R"),
  encoding = "UTF-8",
  local = .dbr_env
)

# -----------------------------------------------------------------------------
# .db_chat_valid_user_id
# -----------------------------------------------------------------------------

test_that(".db_chat_valid_user_id yalnızca pozitif tamsayıya çözülen id'leri kabul eder", {
  expect_true(.dbr_env$.db_chat_valid_user_id(5))
  expect_true(.dbr_env$.db_chat_valid_user_id(3L))
  expect_true(.dbr_env$.db_chat_valid_user_id("7"))    # sayısal string

  expect_false(.dbr_env$.db_chat_valid_user_id(0))
  expect_false(.dbr_env$.db_chat_valid_user_id(-1))
  expect_false(.dbr_env$.db_chat_valid_user_id("abc")) # NA'ya çözülür
  expect_false(.dbr_env$.db_chat_valid_user_id(NA))
  expect_false(.dbr_env$.db_chat_valid_user_id(NULL))
  expect_false(.dbr_env$.db_chat_valid_user_id(integer(0)))
})

# -----------------------------------------------------------------------------
# .db_chat_timestamp_missing
# -----------------------------------------------------------------------------

test_that(".db_chat_timestamp_missing eksik/NA/boş değerleri eksik sayar", {
  expect_true(.dbr_env$.db_chat_timestamp_missing(NULL))
  expect_true(.dbr_env$.db_chat_timestamp_missing(character(0)))
  expect_true(.dbr_env$.db_chat_timestamp_missing(NA))

  expect_false(.dbr_env$.db_chat_timestamp_missing("2026-01-01 00:00:00"))
  expect_false(.dbr_env$.db_chat_timestamp_missing(Sys.time()))
})

# -----------------------------------------------------------------------------
# .db_chat_as_numeric_timestamp
# -----------------------------------------------------------------------------

test_that(".db_chat_as_numeric_timestamp eksik/geçersiz değer için 0 döndürür", {
  expect_equal(.dbr_env$.db_chat_as_numeric_timestamp(NULL), 0)
  expect_equal(.dbr_env$.db_chat_as_numeric_timestamp(NA), 0)
  expect_equal(.dbr_env$.db_chat_as_numeric_timestamp("ayrıştırılamaz"), 0)
})

test_that(".db_chat_as_numeric_timestamp POSIXct ve Date değerlerini sayıya çevirir", {
  t <- as.POSIXct("2026-01-01 00:00:00", tz = "UTC")
  expect_equal(.dbr_env$.db_chat_as_numeric_timestamp(t), as.numeric(t))

  d <- as.Date("2026-01-01")
  expect_equal(.dbr_env$.db_chat_as_numeric_timestamp(d), as.numeric(as.POSIXct(d, tz = "UTC")))
})

test_that(".db_chat_as_numeric_timestamp geçerli zaman string'ini pozitif sayıya çevirir", {
  val <- .dbr_env$.db_chat_as_numeric_timestamp("2026-01-01 12:00:00")
  expect_true(is.numeric(val))
  expect_gt(val, 0)
})
