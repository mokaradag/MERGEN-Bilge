# ==============================================================================
# Dosya Yolu: tests/testthat/test-chat-runtime-behavior.R
# Açıklama: Sohbet çalışma zamanı saf/durum-mutasyon yardımcılarının davranışsal
#           testleri. chat_generate_title_from_prompt saf fonksiyon olarak,
#           chat_store_message_in_saved_chats ise referansla mutasyon yapan
#           bir environment üzerinden doğrulanır. DB, LLM, tarayıcı gerektirmez.
# ==============================================================================

.chat_runtime_source_once <- function() {
  if (exists("chat_generate_title_from_prompt", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("chat_store_message_in_saved_chats", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_chat_runtime.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

testthat::test_that("chat_generate_title_from_prompt boş girdide varsayılan başlık döner", {
  .chat_runtime_source_once()

  testthat::expect_identical(chat_generate_title_from_prompt(NULL), "Yeni Söyleşi")
  testthat::expect_identical(chat_generate_title_from_prompt(""), "Yeni Söyleşi")
  testthat::expect_identical(chat_generate_title_from_prompt("    "), "Yeni Söyleşi")
})

testthat::test_that("chat_generate_title_from_prompt boşlukları sadeleştirir ve noktalama kırpar", {
  .chat_runtime_source_once()

  # Çoklu boşluk tek boşluğa indirilir.
  testthat::expect_identical(
    chat_generate_title_from_prompt("  Merhaba    dunya  "),
    "Merhaba dunya"
  )

  # Baş/son noktalama işaretleri kırpılır.
  testthat::expect_identical(
    chat_generate_title_from_prompt("!!!Soru???"),
    "Soru"
  )
})

testthat::test_that("chat_generate_title_from_prompt uzun metni üç nokta ile kısaltır", {
  .chat_runtime_source_once()

  # Boşluksuz 200 karakterlik metin deterministik kesime düşer:
  # substr(1, max_len-3) + "..." => tam max_len uzunluğu.
  uzun <- paste(rep("a", 200), collapse = "")
  out <- chat_generate_title_from_prompt(uzun, max_len = 60)

  testthat::expect_true(endsWith(out, "..."))
  testthat::expect_identical(nchar(out), 60L)

  # Boşluk içeren uzun metin de kısaltılmalı ve makul uzunlukta kalmalı.
  uzun_bosluklu <- paste(rep("kelime", 40), collapse = " ")
  out2 <- chat_generate_title_from_prompt(uzun_bosluklu, max_len = 60)
  testthat::expect_true(endsWith(out2, "..."))
  testthat::expect_true(nchar(out2) <= 63L)
})

testthat::test_that("chat_store_message_in_saved_chats current_chat_id yoksa hiçbir şey yapmaz", {
  .chat_runtime_source_once()

  values <- new.env()
  values$current_chat_id <- NULL

  res <- chat_store_message_in_saved_chats(
    values,
    list(id = "m1", content = "merhaba", type = "user")
  )

  testthat::expect_null(res)
  testthat::expect_null(values$saved_chats)
})

testthat::test_that("chat_store_message_in_saved_chats yeni mesajı ekler ve sayacı günceller", {
  .chat_runtime_source_once()

  values <- new.env()
  values$current_chat_id <- "chat1"

  chat_store_message_in_saved_chats(
    values,
    list(id = "m1", content = "ilk mesaj", type = "user")
  )

  entry <- values$saved_chats[["chat1"]]
  testthat::expect_false(is.null(entry))
  testthat::expect_identical(length(entry$messages), 1L)
  testthat::expect_identical(entry$message_count, 1L)
  testthat::expect_identical(entry$messages[[1]]$id, "m1")
  # Başlık yoksa güvenli varsayılan atanır.
  testthat::expect_identical(entry$title, "Yeni Söyleşi")
  # Son aktivite damgası set edilmeli (recency invariantı için kritik).
  testthat::expect_false(is.null(entry$last_message_timestamp))

  # İkinci mesaj eklenince sayaç artar.
  chat_store_message_in_saved_chats(
    values,
    list(id = "m2", content = "ikinci mesaj", type = "ai")
  )

  entry2 <- values$saved_chats[["chat1"]]
  testthat::expect_identical(length(entry2$messages), 2L)
  testthat::expect_identical(entry2$message_count, 2L)
  testthat::expect_identical(entry2$messages[[2]]$id, "m2")
})

testthat::test_that("chat_store_message_in_saved_chats var olan başlığı korur", {
  .chat_runtime_source_once()

  values <- new.env()
  values$current_chat_id <- "chat9"
  values$saved_chats <- list(
    chat9 = list(
      title = "Var olan baslik",
      timestamp = Sys.time(),
      messages = list(),
      message_count = 0L
    )
  )

  chat_store_message_in_saved_chats(
    values,
    list(id = "m1", content = "mesaj", type = "user")
  )

  entry <- values$saved_chats[["chat9"]]
  testthat::expect_identical(entry$title, "Var olan baslik")
  testthat::expect_identical(length(entry$messages), 1L)
  testthat::expect_identical(entry$message_count, 1L)
})
