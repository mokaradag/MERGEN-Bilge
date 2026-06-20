# ==============================================================================
# Dosya Yolu: tests/testthat/test-db-user-scope-contract.R
# Açıklama: Sohbet geçmişi/veri görünürlüğü sorgularında UserID ve IsDeleted
#           filtrelerinin sohbet okuma yardımcılarında korunmasını statik sözleşme
#           olarak doğrular. Gerçek veritabanına bağlanmaz.
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

# Sohbet okuma SQL'i R/helpers_db_chat_read_queries.R üreticilerine taşındı.
# Bu sözleşme kullanıcı izolasyonu + soft-delete güvenlik filtresinin korunduğunu
# ve okuyucuların kullanıcı-kapsamlı üreticilere yönlendiğini doğrular.

test_that("listeleme okuyucuları kullanıcı-kapsamlı SQL üreticilerine yönlenir", {
  reader_txt <- .read_repo_file_bytes_for_db_contract("R/helpers_db_chat_readers.R")

  expect_true(
    regexpr("load_chats_preview_from_db", reader_txt, fixed = TRUE, useBytes = TRUE)[[1]] > 0L,
    info = "load_chats_preview_from_db fonksiyonu helpers_db_chat_readers.R içinde bulunmalı."
  )
  expect_true(
    regexpr("load_chats_from_db", reader_txt, fixed = TRUE, useBytes = TRUE)[[1]] > 0L,
    info = "load_chats_from_db fonksiyonu helpers_db_chat_readers.R içinde bulunmalı."
  )

  # Okuyucular her-zaman-kapsamlı listeleme üreticilerini çağırmalı.
  expect_true(
    .byte_fixed_count("db_chat_preview_query_sql(", reader_txt) >= 1L,
    info = "load_chats_preview_from_db db_chat_preview_query_sql() üreticisini çağırmalı."
  )
  expect_true(
    .byte_fixed_count("db_chat_list_summary_query_sql(", reader_txt) >= 1L,
    info = "load_chats_from_db (mesajsız) db_chat_list_summary_query_sql() çağırmalı."
  )
  expect_true(
    .byte_fixed_count("db_chat_list_full_query_sql(", reader_txt) >= 1L,
    info = "load_chats_from_db (mesajlı) db_chat_list_full_query_sql() çağırmalı."
  )
})

test_that("her-zaman-kapsamlı listeleme üreticileri kullanıcı ve soft-delete filtresini korur", {
  query_txt <- .read_repo_file_bytes_for_db_contract("R/helpers_db_chat_read_queries.R")

  # Önizleme/özet/tam listeleme üreticileri DAİMA UserID + IsDeleted filtresini içerir.
  for (builder in c(
    "db_chat_preview_query_sql",
    "db_chat_list_summary_query_sql",
    "db_chat_list_full_query_sql"
  )) {
    fn_pos <- regexpr(builder, query_txt, fixed = TRUE, useBytes = TRUE)[[1]]
    expect_true(
      fn_pos > 0L,
      info = sprintf("%s üreticisi helpers_db_chat_read_queries.R içinde bulunmalı.", builder)
    )

    filter_positions <- .byte_fixed_positions("c.UserID = ? AND c.IsDeleted = 0", query_txt)
    expect_true(
      any(filter_positions > fn_pos & filter_positions < fn_pos + 800L),
      info = sprintf("%s içinde c.UserID = ? AND c.IsDeleted = 0 filtresi korunmalı.", builder)
    )
  }

  # En az üç (önizleme + özet + tam) her-zaman-kapsamlı filtre bulunmalı.
  expect_true(
    .byte_fixed_count("c.UserID = ? AND c.IsDeleted = 0", query_txt) >= 3L,
    info = "Listeleme SQL üreticileri için beklenen UserID/IsDeleted filtre sayısı az görünüyor."
  )
})

test_that("kapsamlı mesaj/geçmiş üreticileri scoped dalda AND c.UserID = ? ekler", {
  query_txt <- .read_repo_file_bytes_for_db_contract("R/helpers_db_chat_read_queries.R")

  # Tek-sohbet / toplu / geçmiş üreticileri scoped olduğunda kullanıcı filtresi ekler.
  expect_true(
    .byte_fixed_count("AND c.UserID = ?", query_txt) >= 1L,
    info = "Scoped mesaj/geçmiş üreticilerinde AND c.UserID = ? koşullu parçası bulunmalı."
  )
})