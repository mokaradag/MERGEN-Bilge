# ==============================================================================
# Dosya Yolu: tests/testthat/test-stream-abort-cleanup-behavior.R
# Açıklama: R/helpers_streaming_abort_lifecycle.R saf karar yardımcısının
#           DAVRANIŞSAL testleri. True-streaming durdurma/iptal/hata sonuçlarında
#           UI temizleme planının (finalize_partial vs remove_placeholder, toast
#           tipi, hata izleme) doğru üretildiğini gerçek fonksiyonu çağırarak
#           doğrular. Shiny/DB/LLM gerekmez.
# ==============================================================================

.abortplan_source_once <- function() {
  if (exists("mergen_stream_abort_cleanup_plan", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_streaming_abort_lifecycle.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

testthat::test_that("kısmi metin olmadan iptal: placeholder kaldırılır, hata gösterilmez", {
  .abortplan_source_once()
  plan <- mergen_stream_abort_cleanup_plan("", result = list(aborted = TRUE))
  testthat::expect_identical(plan$action, "remove_placeholder")
  testthat::expect_true(plan$aborted)
  testthat::expect_false(plan$track_error)
  testthat::expect_false(plan$show_toast)
  testthat::expect_false(plan$request_success)
})

testthat::test_that("kısmi metinle iptal: kısmi yanıt finalize edilir, uyarı toast'ı", {
  .abortplan_source_once()
  plan <- mergen_stream_abort_cleanup_plan("Yarım kalan yanıt", result = list(aborted = TRUE))
  testthat::expect_identical(plan$action, "finalize_partial")
  testthat::expect_identical(plan$final_text, "Yarım kalan yanıt")
  testthat::expect_identical(plan$toast_type, "warning")
  testthat::expect_false(plan$track_error)   # iptal hata sayılmaz
})

testthat::test_that("kısmi metinsiz hata: placeholder kaldırılır, hata izlenir ve gösterilir", {
  .abortplan_source_once()
  plan <- mergen_stream_abort_cleanup_plan("", result = list(error = "Bağlantı koptu"))
  testthat::expect_identical(plan$action, "remove_placeholder")
  testthat::expect_true(plan$track_error)
  testthat::expect_true(plan$show_toast)
  testthat::expect_identical(plan$toast_type, "error")
  testthat::expect_identical(plan$error, "Bağlantı koptu")
})

testthat::test_that("kısmi metinli hata: kısmi yanıt korunur, uyarı toast'ı, hata izlenir", {
  .abortplan_source_once()
  plan <- mergen_stream_abort_cleanup_plan(
    "Kısmi içerik",
    result = list(error = "timeout")
  )
  testthat::expect_identical(plan$action, "finalize_partial")
  testthat::expect_identical(plan$final_text, "Kısmi içerik")
  testthat::expect_identical(plan$toast_type, "warning")
  testthat::expect_true(plan$track_error)
  testthat::expect_true(plan$show_toast)
})

testthat::test_that("temiz sonuç (hata/iptal yok, metin yok): sessiz placeholder kaldırma", {
  .abortplan_source_once()
  plan <- mergen_stream_abort_cleanup_plan("", result = list())
  testthat::expect_identical(plan$action, "remove_placeholder")
  testthat::expect_false(plan$track_error)
  testthat::expect_false(plan$show_toast)
})

testthat::test_that("NA/NULL accumulated_text güvenle boş metne düşer", {
  .abortplan_source_once()
  plan_na <- mergen_stream_abort_cleanup_plan(NA, result = list(aborted = TRUE))
  testthat::expect_identical(plan_na$final_text, "")
  testthat::expect_identical(plan_na$action, "remove_placeholder")

  plan_null <- mergen_stream_abort_cleanup_plan(NULL, result = list())
  testthat::expect_identical(plan_null$final_text, "")
})

testthat::test_that("duration sonuç içinden geçirilir; iptal hatayı bastırır", {
  .abortplan_source_once()
  plan <- mergen_stream_abort_cleanup_plan(
    "metin",
    result = list(aborted = TRUE, error = "yoksay", duration = 1.23)
  )
  testthat::expect_identical(plan$duration, 1.23)
  # aborted=TRUE iken hata bastırılır (has_error sadece abort yokken true olur).
  testthat::expect_false(plan$track_error)
})

testthat::test_that("özel normalize_fn accumulated_text'e uygulanır", {
  .abortplan_source_once()
  plan <- mergen_stream_abort_cleanup_plan(
    "  bosluklu  ",
    result = list(aborted = TRUE),
    normalize_fn = function(x) trimws(x)
  )
  testthat::expect_identical(plan$final_text, "bosluklu")
})
