# ==============================================================================
# Dosya Yolu: tests/testthat/test-files-dataframe-markdown-behavior.R
# Açıklama: dataframeToMarkdown() davranışsal testleri. Veri çerçevesinin CSV/
#           metin temsiline çevrilmesini ve boş/geçersiz girdide güvenli mesaj
#           dönüşünü doğrular. DB/LLM/tarayıcı gerekmez.
# ==============================================================================

.files_helpers_source_once <- function() {
  if (exists("dataframeToMarkdown", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_files.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

testthat::test_that("dataframeToMarkdown boş/geçersiz girdide güvenli mesaj döner", {
  .files_helpers_source_once()

  out_null <- dataframeToMarkdown(NULL)
  testthat::expect_true(grepl("okunamad", enc2utf8(out_null), fixed = TRUE))

  out_empty <- dataframeToMarkdown(data.frame())
  testthat::expect_true(grepl("okunamad", enc2utf8(out_empty), fixed = TRUE))
})

testthat::test_that("dataframeToMarkdown veri çerçevesini başlık ve satırlarla metne çevirir", {
  .files_helpers_source_once()
  testthat::skip_if_not_installed("data.table")

  df <- data.frame(a = c(1L, 2L), b = c("x", "y"), stringsAsFactors = FALSE)
  out <- dataframeToMarkdown(df)

  testthat::expect_true(grepl("a,b", out, fixed = TRUE))
  testthat::expect_true(grepl("1,x", out, fixed = TRUE))
  testthat::expect_true(grepl("2,y", out, fixed = TRUE))
})
