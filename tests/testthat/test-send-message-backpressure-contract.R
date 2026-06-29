# ==============================================================================
# Dosya Yolu: tests/testthat/test-send-message-backpressure-contract.R
# Açıklama: send_message (R/server_send_message.R) içindeki süreç-geneli
#           kabul-denetimi (backpressure) wiring sözleşmesi.
#
# send_message ağır biçimde sözleşmeli/asenkron olduğu için bu test STATİK wiring
# bütünlüğünü doğrular (app'i BAŞLATMADAN) ve davranışsal "varsayılan KAPALI =
# no-op" garantisini saf yardımcı üzerinden teyit eder. Böylece:
#   - Slot, mesaj gönderme girişinde edinilir; tüm sonlandırma/iptal yollarında
#     (cleanup/abort) ve erken-dönüşte (on.exit) serbest bırakılır.
#   - Devir bayrağı (bp_handoff) asenkron yaşam döngüsüne devri yönetir.
#   - Reddedilen istek dostça "sunucu yoğun" mesajıyla döner (stop/iptal bozulmaz).
#   - Limit 0 (varsayılan) iken acquire token=NULL döndürür -> wiring no-op.
# ==============================================================================

testthat::local_edition(3)

source("../../R/helpers_runtime_metrics.R")
source("../../R/helpers_request_backpressure.R")
source("../../R/helpers_streaming_io.R")
source("../../R/helpers_stream_load_control.R")

.read_repo_file <- function(rel) {
  cand <- c(file.path("..", "..", rel), file.path(getwd(), rel))
  for (p in cand) if (file.exists(p)) {
    con <- file(p, open = "r", encoding = "UTF-8")
    on.exit(close(con), add = TRUE)
    return(paste(readLines(con, warn = FALSE), collapse = "\n"))
  }
  stop(rel, " bulunamadi")
}
.send_message_src <- function() .read_repo_file("R/server_send_message.R")
.core_src <- function() .read_repo_file("R/helpers_send_message_core.R")

test_that("backpressure slot yardimcilari core helper'da tanimli", {
  core <- .core_src()
  # Ratchet bütçesi nedeniyle slot yardimcilari helpers_send_message_core.R'de.
  expect_true(grepl("mergen_send_message_acquire_slot <- function", core, fixed = TRUE))
  expect_true(grepl("mergen_send_message_release_slot <- function", core, fixed = TRUE))
  expect_true(grepl("mergen_send_message_release_values_token <- function", core, fixed = TRUE))
})

test_that("send_message backpressure wiring tokenlari mevcut", {
  txt <- .send_message_src()
  # Tur, arac ailesinden cozulur ve slot ona gore edinilir; devir oncesi on.exit
  # ile sizinti korunur.
  expect_true(grepl("bp_kind <- mergen_send_message_backpressure_kind(tool_family)", txt, fixed = TRUE))
  expect_true(grepl("bp_admission <- mergen_send_message_acquire_slot(bp_kind)", txt, fixed = TRUE))
  expect_true(grepl("on.exit(", txt, fixed = TRUE))
  expect_true(grepl("bp_handoff", txt, fixed = TRUE))
  # Token ve request kimliği reaktif state'e devredilir.
  expect_true(grepl("values$backpressure_token <- bp_admission$token", txt, fixed = TRUE))
  expect_true(grepl("values$backpressure_request_id <- req_id", txt, fixed = TRUE))
})

test_that("backpressure turu arac ailesinden dogru cozulur", {
  expect_identical(mergen_send_message_backpressure_kind("sql_analysis"), "sql_analysis")
  expect_identical(mergen_send_message_backpressure_kind("mcp_excel"), "mcp_excel")
  expect_identical(mergen_send_message_backpressure_kind("summarization"), "summarization")
  # none/coding/process/app_expert/image -> genel "llm" havuzu.
  expect_identical(mergen_send_message_backpressure_kind("none"), "llm")
  expect_identical(mergen_send_message_backpressure_kind("coding"), "llm")
  expect_identical(mergen_send_message_backpressure_kind("image"), "llm")
  expect_identical(mergen_send_message_backpressure_kind(NA), "llm")
  expect_identical(mergen_send_message_backpressure_kind(NULL), "llm")
})

test_that("bir tur reddi baska turu reddetmez (havuzlar ayri)", {
  withr::with_envvar(c(
    MERGEN_MAX_CONCURRENT_SQL_ANALYSIS = "1",
    MERGEN_MAX_CONCURRENT_LLM = ""
  ), {
    mergen_backpressure_reset()
    # sql_analysis havuzu 1; ilk kabul edilir, ikinci reddedilir.
    a1 <- mergen_backpressure_try_acquire("sql_analysis")
    a2 <- mergen_backpressure_try_acquire("sql_analysis")
    expect_true(a1$acquired)
    expect_false(a2$acquired)
    # Farkli tur (llm) limit kapali oldugu icin etkilenmez.
    b <- mergen_backpressure_try_acquire("llm")
    expect_true(b$acquired)
    mergen_backpressure_release(a1$token)
  })
})

test_that("slot tum sonlandirma/iptal yollarinda serbest birakilir", {
  txt <- .send_message_src()
  # cleanup wrapper, abort wrapper ve giris bayat-slot temizligi: >= 3 cagri.
  releases <- gregexpr("mergen_send_message_release_values_token(values)",
                       txt, fixed = TRUE)[[1]]
  expect_true(releases[1] != -1L && length(releases) >= 3L,
              info = "cleanup + abort + giris yollari token birakmali (>=3 cagri).")
})

test_that("reddedilen istek dostca 'sunucu yogun' mesajiyla doner", {
  txt <- enc2utf8(.send_message_src())
  busy_msg <- "Sunucu \u015fu anda yo\u011fun"

  expect_true(grepl("!isTRUE(bp_admission$acquired)", txt, fixed = TRUE))
  expect_true(
    grepl(busy_msg, txt, fixed = TRUE),
    info = "R/server_send_message.R rejected backpressure path should include the friendly server-busy toast."
  )
})

test_that("VARSAYILAN KAPALI: acquire token=NULL -> wiring no-op", {
  withr::with_envvar(c(MERGEN_MAX_CONCURRENT_LLM = ""), {
    mergen_backpressure_reset()
    a <- mergen_backpressure_try_acquire("llm")
    expect_true(a$acquired)
    expect_null(a$token)
    # NULL token release no-op -> reaktif state'e dokunmadan guvenli.
    expect_false(mergen_backpressure_release(a$token))
  })
})