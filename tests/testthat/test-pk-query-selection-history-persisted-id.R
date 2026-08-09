# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-query-selection-history-persisted-id.R
# Açıklama: Kalıcı/oturum-yerel ileti kimliğinin kaydedilmiş söyleşi yeniden
#           yüklemesinde ve dönen kısa geçmiş pencerelerinde durumu koruduğunu
#           doğrular.
# ==============================================================================

pk_select_source_chain_for_tests()

test_that("history signatures prefer persisted db_id over temporary stream id", {
  bellekte <- list(
    list(role = "user", content = "ilk soru", id = "101"),
    list(
      role = "assistant", content = "ilk yanıt",
      id = "tmp-stream-42", db_id = "202"
    )
  )
  yeniden_yuklenmis <- list(
    list(role = "user", content = "ilk soru", id = "101"),
    list(role = "assistant", content = "ilk yanıt", id = "202")
  )

  expect_identical(
    .pk_select_history_signatures(bellekte),
    .pk_select_history_signatures(yeniden_yuklenmis)
  )
  expect_match(
    .pk_select_history_signatures(bellekte)[2],
    "assistant\\|id=202\\|",
    fixed = FALSE
  )
})

test_that("rolling three-message windows preserve selector state through message id", {
  session <- new.env(parent = emptyenv())
  session$userData <- new.env(parent = emptyenv())

  user1 <- list(role = "user", content = "ilk soru", id = "u-1")
  assistant1 <- list(role = "assistant", content = "ilk yanıt", id = "a-1")
  user2 <- list(role = "user", content = "ikinci soru", id = "u-2")
  assistant2 <- list(role = "assistant", content = "ikinci yanıt", id = "a-2")
  user3 <- list(role = "user", content = "peki 2024 için?", id = "u-3")

  ilk_pencere <- list(user1, assistant1, user2)
  sonraki_pencere <- list(user2, assistant2, user3)

  ilk_anahtar <- pk_select_chat_key(ilk_pencere, session)
  expect_true(pk_select_remember_query_id(session, "q001", ilk_anahtar))

  sonraki_anahtar <- pk_select_chat_key(sonraki_pencere, session)
  expect_identical(sonraki_anahtar, ilk_anahtar)
  expect_identical(pk_select_prior_query_id(session, sonraki_anahtar), "q001")
})

test_that("text-only single-message overlap is not conversation identity", {
  expect_identical(
    .pk_select_history_overlap(
      c("user|ilk soru", "assistant|aynı yanıt", "user|ortak soru"),
      c("user|ortak soru", "assistant|başka yanıt", "user|başka soru")
    ),
    0L
  )
})
