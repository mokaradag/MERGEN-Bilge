# ==============================================================================
# Dosya Yolu: tests/testthat/test-messaging-html-builders-behavior.R
# Açıklama: helpers_messaging.R HTML üretici yardımcılarının davranışsal
#           testleri. build_reasoning_details_block (akıl yürütme arşiv bloğu +
#           HTML kaçışı) ve build_followup_container (takip sorusu kapsayıcısı)
#           doğrulanır. DB/LLM/tarayıcı gerekmez.
# ==============================================================================

# İzole çalıştırma için: build_* yardımcıları shiny tags/HTML'i niteliksiz çağırır.
# Tam suite'te shiny başka testlerce attach edilir; tek başına koşumda gerekir.
suppressMessages(library(shiny))

.messaging_builders_source_once <- function() {
  if (exists("build_reasoning_details_block", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("build_followup_container", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_messaging.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

testthat::test_that("build_reasoning_details_block boş girdide boş string döner", {
  .messaging_builders_source_once()

  testthat::expect_identical(build_reasoning_details_block(NULL), "")
  testthat::expect_identical(build_reasoning_details_block(""), "")
  testthat::expect_identical(build_reasoning_details_block("   "), "")
})

testthat::test_that("build_reasoning_details_block arşiv bloğu üretir ve içeriği kaçışlar", {
  .messaging_builders_source_once()

  out <- build_reasoning_details_block("a & b < c")

  # details/summary iskeleti ve arşiv rolü bulunmalı.
  testthat::expect_true(grepl("reasoning-block", out, fixed = TRUE))
  testthat::expect_true(grepl("reasoning-archive", out, fixed = TRUE))

  # HTML kaçışı: & -> &amp;, < -> &lt;.
  testthat::expect_true(grepl("a &amp; b &lt; c", out, fixed = TRUE))

  # Karakter sayısı meta bilgisi (ASCII "karakter").
  testthat::expect_true(grepl("karakter", out, fixed = TRUE))
})

testthat::test_that("build_followup_container boş/geçersiz öneride NULL döner", {
  .messaging_builders_source_once()
  testthat::skip_if_not_installed("htmltools")

  testthat::expect_null(build_followup_container("m1", NULL))
  testthat::expect_null(build_followup_container("m1", list()))
  # Tüm öneriler boş string ise (filtrelenir) NULL döner.
  testthat::expect_null(build_followup_container("m1", c("", "")))
})

testthat::test_that("build_followup_container geçerli önerilerle kapsayıcı üretir", {
  .messaging_builders_source_once()
  testthat::skip_if_not_installed("htmltools")

  out <- as.character(build_followup_container("m1", c("Soru bir?", "Soru iki?")))

  testthat::expect_true(grepl("followup_container_m1", out, fixed = TRUE))
  testthat::expect_true(grepl("data-question=\"Soru bir?\"", out, fixed = TRUE))
  testthat::expect_true(grepl("Soru iki?", out, fixed = TRUE))
})
