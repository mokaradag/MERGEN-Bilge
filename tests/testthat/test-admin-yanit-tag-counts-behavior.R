# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-yanit-tag-counts-behavior.R
# Açıklama: admin_yanit_tag_counts() davranışsal testleri. Yanıt geri bildirim
#           etiketlerinin ayrıştırılması, sayımı ve beğeni/beğenmeme ayrımını
#           doğrular. Saf veri dönüşümüdür; DB/LLM/tarayıcı gerekmez.
# ==============================================================================

.admin_yanit_source_once <- function() {
  if (exists("admin_yanit_tag_counts", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_admin_yanit_analizi.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

testthat::test_that("admin_yanit_tag_counts boş girdide boş çerçeve döner", {
  .admin_yanit_source_once()

  bos_null <- admin_yanit_tag_counts(NULL)
  testthat::expect_identical(nrow(bos_null), 0L)
  testthat::expect_true(all(c("etiket", "cnt", "tip") %in% names(bos_null)))

  bos_df <- admin_yanit_tag_counts(data.frame(
    FeedbackTags = character(0),
    FeedbackType = character(0),
    stringsAsFactors = FALSE
  ))
  testthat::expect_identical(nrow(bos_df), 0L)
})

testthat::test_that("admin_yanit_tag_counts etiketleri sayar ve beğeni/beğenmeme ayırır", {
  .admin_yanit_source_once()

  ham <- data.frame(
    FeedbackTags = c("hizli,dogru", "yavas", "hizli"),
    FeedbackType = c("like", "dislike", "like"),
    stringsAsFactors = FALSE
  )

  res <- admin_yanit_tag_counts(ham)

  # Üç benzersiz etiket: hizli, dogru, yavas.
  testthat::expect_identical(nrow(res), 3L)

  hizli <- res[res$etiket == "hizli", ]
  testthat::expect_identical(as.numeric(hizli$cnt), 2)
  testthat::expect_identical(as.numeric(hizli$begeni_cnt), 2)
  testthat::expect_identical(as.numeric(hizli$begenmeme_cnt), 0)

  yavas <- res[res$etiket == "yavas", ]
  testthat::expect_identical(as.numeric(yavas$cnt), 1)
  testthat::expect_identical(as.numeric(yavas$begeni_cnt), 0)
  testthat::expect_identical(as.numeric(yavas$begenmeme_cnt), 1)

  # En çok geçen etiket (hizli) sıralamada ilk sırada olmalı.
  testthat::expect_identical(res$etiket[1], "hizli")
})

testthat::test_that("admin_yanit_tag_counts boş/whitespace etiketleri atlar", {
  .admin_yanit_source_once()

  ham <- data.frame(
    FeedbackTags = c("", "  ", "gecerli"),
    FeedbackType = c("like", "dislike", "like"),
    stringsAsFactors = FALSE
  )

  res <- admin_yanit_tag_counts(ham)
  testthat::expect_identical(nrow(res), 1L)
  testthat::expect_identical(res$etiket[1], "gecerli")
})
