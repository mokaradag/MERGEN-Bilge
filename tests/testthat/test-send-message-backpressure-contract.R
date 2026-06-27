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

.read_repo_file <- function(rel) {
  cand <- c(file.path("..", "..", rel), file.path(getwd(), rel))
  for (p in cand) if (file.exists(p)) {
    return(rawToChar(readBin(p, what = "raw", n = file.info(p)$size)))
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
  # Giriste edinilir ve devir oncesi on.exit ile sizinti korunur.
  expect_true(grepl("bp_admission <- mergen_send_message_acquire_slot()", txt, fixed = TRUE))
  expect_true(grepl("on.exit(", txt, fixed = TRUE))
  expect_true(grepl("bp_handoff", txt, fixed = TRUE))
  # Token ve request kimliği reaktif state'e devredilir.
  expect_true(grepl("values$backpressure_token <- bp_admission$token", txt, fixed = TRUE))
  expect_true(grepl("values$backpressure_request_id <- req_id", txt, fixed = TRUE))
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
  txt <- .send_message_src()
  expect_true(grepl("!isTRUE(bp_admission$acquired)", txt, fixed = TRUE))
  expect_true(grepl("Sunucu şu anda yoğun", txt))  # "Sunucu şu anda yoğun"
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
