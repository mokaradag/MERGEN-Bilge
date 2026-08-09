# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-query-selection-history-persisted-id.R
# Açıklama: Kaydedilmiş söyleşi yeniden yüklenirken kalıcı ileti kimliğinin
#           seçim durumu imzasını sabit tuttuğunu doğrular.
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
