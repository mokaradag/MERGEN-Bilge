# ==============================================================================
# Dosya Yolu: tests/testthat/test-db-user-scope-contract.R
# Açıklama: Sohbet geçmişi/veri görünürlüğü sorgularında UserID ve IsDeleted
# filtrelerinin korunmasını statik sözleşme olarak doğrular. Gerçek veritabanına
# bağlanmaz.
# ==============================================================================

# Windows VM'de bazı kaynak dosyaları tam suite içinde UTF-8 olarak işaretlenirken
# grepl() "invalid UTF-8" uyarısı üretebilir. Bu test yalnızca ASCII SQL
# sözleşmesini aradığı için dosyayı raw-byte olarak okur ve eşleşmeleri byte
# modunda yapar.
.read_repo_file_bytes_for_db_contract <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  # UTF-8 BOM varsa kaldır.
  if (length(raw_data) >= 3L &&
      identical(as.integer(raw_data[1:3]), c(239L, 187L, 191L))) {
    raw_data <- raw_data[-(1:3)]
  }

  # NUL bayt regex/gsub tarafını bozmasın.
  raw_data <- raw_data[raw_data != as.raw(0)]

  txt <- rawToChar(raw_data, multiple = FALSE)
  Encoding(txt) <- "bytes"

  txt <- gsub("\r\n", "\n", txt, fixed = TRUE, useBytes = TRUE)
  txt <- gsub("\r", "\n", txt, fixed = TRUE, useBytes = TRUE)

  txt
}

.byte_fixed_positions <- function(pattern, txt) {
  positions <- gregexpr(pattern, txt, fixed = TRUE, useBytes = TRUE)[[1]]
  positions[positions > 0L]
}

.byte_fixed_count <- function(pattern, txt) {
  length(.byte_fixed_positions(pattern, txt))
}

test_that("sohbet önizleme sorgusu kullanıcı ve soft-delete filtresini korur", {
  txt <- .read_repo_file_bytes_for_db_contract("R/helpers_database.R")

  fn_pos <- regexpr(
    "load_chats_preview_from_db",
    txt,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  expect_true(
    fn_pos > 0L,
    info = "load_chats_preview_from_db fonksiyonu bulunmalı."
  )

  filter_positions <- .byte_fixed_positions(
    "c.UserID = ? AND c.IsDeleted = 0",
    txt
  )

  expect_true(
    any(filter_positions > fn_pos & filter_positions < fn_pos + 5000L),
    info = "load_chats_preview_from_db içinde c.UserID = ? AND c.IsDeleted = 0 filtresi korunmalı."
  )
})

test_that("sohbet yükleme sorguları kullanıcı ve soft-delete filtresini korur", {
  txt <- .read_repo_file_bytes_for_db_contract("R/helpers_database.R")

  fn_pos <- regexpr(
    "load_chats_from_db",
    txt,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  expect_true(
    fn_pos > 0L,
    info = "load_chats_from_db fonksiyonu bulunmalı."
  )

  filter_positions <- .byte_fixed_positions(
    "c.UserID = ? AND c.IsDeleted = 0",
    txt
  )

  expect_true(
    any(filter_positions > fn_pos & filter_positions < fn_pos + 9000L),
    info = "load_chats_from_db içinde kullanıcı ve IsDeleted filtresi korunmalı."
  )

  filter_count <- .byte_fixed_count(
    "c.UserID = ? AND c.IsDeleted = 0",
    txt
  )

  expect_true(
    filter_count >= 3L,
    info = "helpers_database.R içinde chat sorguları için beklenen UserID/IsDeleted filtre sayısı az görünüyor."
  )
})