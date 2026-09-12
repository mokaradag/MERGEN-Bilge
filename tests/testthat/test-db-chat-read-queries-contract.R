# ==============================================================================
# Dosya Yolu: tests/testthat/test-db-chat-read-queries-contract.R
# Açıklama: Sohbet okuma SQL sorgu üreticilerinin (R/helpers_db_chat_read_queries.R)
#           helpers_db_chat_readers.R orkestrasyonundan ayrılması sözleşmesi.
#           Yapısal ayrım + saf SQL üretici davranışı (with_reasoning / scoped
#           dalları, kullanıcı izolasyonu + soft-delete filtresi, placeholder
#           enjeksiyonu). DB bağlantısı gerektirmez.
# ==============================================================================

testthat::local_edition(3)

.dbq_repo_root <- resolve_repo_root_for_tests()
.dbq_query_path <- file.path(.dbq_repo_root, "R", "helpers_db_chat_read_queries.R")
.dbq_reader_path <- file.path(.dbq_repo_root, "R", "helpers_db_chat_readers.R")

# ASCII çapaları için bayt-güvenli okuyucu (Windows VM'de geçersiz UTF-8'e dayanıklı).
.dbq_read_bytes <- function(path) {
  raw <- readBin(path, what = "raw", n = file.info(path)$size)
  iconv(rawToChar(raw), from = "UTF-8", to = "UTF-8", sub = "byte")
}

.dbq_env <- new.env(parent = globalenv())
source(.dbq_query_path, encoding = "UTF-8", local = .dbq_env)

# -----------------------------------------------------------------------------
# Yapısal ayrım sözleşmesi
# -----------------------------------------------------------------------------

test_that("SQL üreticileri yeni query dosyasında tanımlıdır", {
  for (fn in c(
    "db_chat_preview_query_sql",
    "db_chat_list_summary_query_sql",
    "db_chat_list_full_query_sql",
    "db_chat_messages_query_sql",
    "db_chat_messages_batch_query_sql",
    "db_history_rows_query_sql"
  )) {
    expect_true(exists(fn, envir = .dbq_env, inherits = FALSE), info = fn)
    expect_true(is.function(get(fn, envir = .dbq_env, inherits = FALSE)), info = fn)
  }
})

test_that("reader dosyası satır içi SQL yerine üreticileri çağırır", {
  reader_txt <- .dbq_read_bytes(.dbq_reader_path)

  # Üretici çağrıları reader dosyasında bulunmalı.
  for (call in c(
    "db_chat_preview_query_sql(",
    "db_chat_list_summary_query_sql(",
    "db_chat_list_full_query_sql(",
    "db_chat_messages_query_sql(",
    "db_chat_messages_batch_query_sql(",
    "db_history_rows_query_sql("
  )) {
    expect_true(grepl(call, reader_txt, fixed = TRUE, useBytes = TRUE), info = call)
  }

  # Büyük satır içi SQL gövdeleri reader dosyasından çıkarıldı (query dosyasının sahipliği).
  expect_false(grepl("WITH filtered AS (", reader_txt, fixed = TRUE, useBytes = TRUE))
  expect_false(grepl("SELECT TOP %d", reader_txt, fixed = TRUE, useBytes = TRUE))
  expect_false(grepl("OVER (PARTITION BY c.ChatID)", reader_txt, fixed = TRUE, useBytes = TRUE))
})

test_that("manifest query dosyasını reader'dan önce yükler (bağımlılık-önce)", {
  expect_source_manifest_contains_for_tests(c(
    "R/helpers_db_chat_read_queries.R",
    "R/helpers_db_chat_readers.R"
  ))
  expect_source_manifest_order_for_tests(c(
    "R/helpers_db_chat_read_queries.R",
    "R/helpers_db_chat_readers.R"
  ))
})

# -----------------------------------------------------------------------------
# Saf SQL üretici davranışı
# -----------------------------------------------------------------------------

.dbq <- function(fn) get(fn, envir = .dbq_env, inherits = FALSE)

test_that("önizleme üreticisi TOP limitini ve güvenlik filtresini içerir", {
  sql <- .dbq("db_chat_preview_query_sql")(30L)
  expect_true(grepl("SELECT TOP 30", sql, fixed = TRUE))
  expect_true(grepl("c.UserID = ? AND c.IsDeleted = 0", sql, fixed = TRUE))
  expect_true(grepl("MAX(m.MessageTimestamp) AS LastMessageTimestamp", sql, fixed = TRUE))

  # limit parametresi gerçekten enjekte edilir.
  expect_true(grepl("SELECT TOP 7", .dbq("db_chat_preview_query_sql")(7L), fixed = TRUE))
})

test_that("listeleme özet üreticisi sayım + güvenlik filtresi içerir, mesaj içeriği içermez", {
  sql <- .dbq("db_chat_list_summary_query_sql")()
  expect_true(grepl("COUNT(m.MessageID) AS MessageCount", sql, fixed = TRUE))
  expect_true(grepl("c.UserID = ? AND c.IsDeleted = 0", sql, fixed = TRUE))
  expect_false(grepl("m.MessageContent", sql, fixed = TRUE))
})

test_that("tam listeleme üreticisi with_reasoning'a göre ReasoningContent ekler", {
  wr <- .dbq("db_chat_list_full_query_sql")(with_reasoning = TRUE)
  lg <- .dbq("db_chat_list_full_query_sql")(with_reasoning = FALSE)

  expect_true(grepl("m.ReasoningContent,", wr, fixed = TRUE))
  expect_false(grepl("m.ReasoningContent", lg, fixed = TRUE))
  expect_true(grepl("c.UserID = ? AND c.IsDeleted = 0", wr, fixed = TRUE))
  expect_true(grepl("c.UserID = ? AND c.IsDeleted = 0", lg, fixed = TRUE))
  expect_true(grepl("AS SortTimestamp", lg, fixed = TRUE))

  # with_reasoning ve legacy YALNIZCA reasoning satırıyla farklılaşır.
  expect_identical(gsub("\n           m.ReasoningContent,", "", wr, fixed = TRUE), lg)
})

test_that("tek-sohbet mesaj üreticisi with_reasoning + scoped dallarını uygular", {
  wr_un <- .dbq("db_chat_messages_query_sql")(with_reasoning = TRUE, scoped = FALSE)
  lg_un <- .dbq("db_chat_messages_query_sql")(with_reasoning = FALSE, scoped = FALSE)
  wr_sc <- .dbq("db_chat_messages_query_sql")(with_reasoning = TRUE, scoped = TRUE)

  expect_true(grepl(", m.ReasoningContent", wr_un, fixed = TRUE))
  expect_false(grepl("m.ReasoningContent", lg_un, fixed = TRUE))

  expect_true(grepl("WHERE c.ChatID = ?", wr_un, fixed = TRUE))
  expect_false(grepl("AND c.UserID = ?", wr_un, fixed = TRUE))
  expect_true(grepl("WHERE c.ChatID = ? AND c.UserID = ?", wr_sc, fixed = TRUE))
})

test_that("toplu mesaj üreticisi placeholder + with_reasoning + scoped uygular", {
  wr_sc <- .dbq("db_chat_messages_batch_query_sql")("?, ?", with_reasoning = TRUE, scoped = TRUE)
  lg_un <- .dbq("db_chat_messages_batch_query_sql")("?", with_reasoning = FALSE, scoped = FALSE)

  expect_true(grepl("c.ChatID IN (?, ?) AND c.UserID = ?", wr_sc, fixed = TRUE))
  expect_true(grepl(", m.ReasoningContent", wr_sc, fixed = TRUE))

  expect_true(grepl("c.ChatID IN (?)", lg_un, fixed = TRUE))
  expect_false(grepl("AND c.UserID = ?", lg_un, fixed = TRUE))
  expect_false(grepl("m.ReasoningContent", lg_un, fixed = TRUE))
})

test_that("geçmiş üreticisi CTE + placeholder + scoped uygular", {
  sc <- .dbq("db_history_rows_query_sql")("?, ?", scoped = TRUE)
  un <- .dbq("db_history_rows_query_sql")("?", scoped = FALSE)

  expect_true(grepl("WITH filtered AS (", sc, fixed = TRUE))
  expect_true(grepl("ROW_NUMBER() OVER (PARTITION BY ChatID", sc, fixed = TRUE))
  expect_true(grepl("c.ChatID IN (?, ?) AND c.UserID = ?", sc, fixed = TRUE))

  expect_true(grepl("c.ChatID IN (?)", un, fixed = TRUE))
  expect_false(grepl("AND c.UserID = ?", un, fixed = TRUE))
})

test_that("geçmiş eşleştirmesi MessageID eşitlik ayracını iki sınırda da uygular", {
  sc <- .dbq("db_history_rows_query_sql")("?, ?", scoped = TRUE)

  # Sıralama (MessageOrder, MessageID) ikilisidir. Sıkı `>` / `<` denetimleri
  # eşit MessageOrder taşıyan satırları yanlış tarafta bırakıp soruyu geçmişten
  # tamamen düşürüyordu.
  expect_true(grepl("LEAD(MessageID) OVER (PARTITION BY ChatID", sc, fixed = TRUE))
  expect_true(grepl("AS NextUserId", sc, fixed = TRUE))
  expect_true(grepl("f.MessageOrder = u.MessageOrder AND f.MessageID > u.MessageID", sc, fixed = TRUE))
  expect_true(grepl("f.MessageOrder = u.NextUserOrder AND f.MessageID < u.NextUserId", sc, fixed = TRUE))
})

