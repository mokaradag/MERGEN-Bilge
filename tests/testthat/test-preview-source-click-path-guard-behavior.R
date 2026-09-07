# ==============================================================================
# Dosya Yolu: tests/testthat/test-preview-source-click-path-guard-behavior.R
# Açıklama: R/helpers_preview.R kaynak-tıklama yol koruması. İstemciden gelen
#           '&&' ipucu parçaları doğrulanmadan birleştirildiğinde model baz
#           klasörünün dışına çıkılabiliyordu (yol geçişi). Saf yardımcılar
#           .preview_hint_parts_safe() ve .preview_path_inside() sınanır;
#           DB, oturum, ağ veya gerçek önizleme GEREKMEZ.
# ==============================================================================

.prev_env <- function() {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  # Dosya yalnızca üst düzey fonksiyon tanımları içerdiği için doğrudan source edilir.
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_preview.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

testthat::test_that("ipucu parçaları yol geçişi ve mutlak yol içeremez", {
  env <- .prev_env()

  testthat::expect_true(env$.preview_hint_parts_safe(c("alt", "rapor.pdf")))
  testthat::expect_true(env$.preview_hint_parts_safe("rapor.pdf"))

  testthat::expect_false(env$.preview_hint_parts_safe(c("..", "rapor.pdf")))
  testthat::expect_false(env$.preview_hint_parts_safe(c(".", "rapor.pdf")))
  testthat::expect_false(env$.preview_hint_parts_safe(c("a/b", "rapor.pdf")))
  testthat::expect_false(env$.preview_hint_parts_safe(c("a\\b", "rapor.pdf")))
  testthat::expect_false(env$.preview_hint_parts_safe(c("C:", "rapor.pdf")))
  testthat::expect_false(env$.preview_hint_parts_safe(character(0)))
  testthat::expect_false(env$.preview_hint_parts_safe(c("", "rapor.pdf")))
})

testthat::test_that("çözülen aday kökün dışındaysa reddedilir", {
  env <- .prev_env()

  kok <- withr::local_tempdir()
  dir.create(file.path(kok, "alt"), recursive = TRUE, showWarnings = FALSE)
  icerideki <- file.path(kok, "alt", "rapor.txt")
  writeLines("x", icerideki)

  disarisi <- withr::local_tempfile(fileext = ".txt")
  writeLines("y", disarisi)

  testthat::expect_true(env$.preview_path_inside(icerideki, kok))
  testthat::expect_true(env$.preview_path_inside(kok, kok))
  testthat::expect_false(env$.preview_path_inside(disarisi, kok))
  testthat::expect_false(env$.preview_path_inside(file.path(kok, "..", "x.txt"), kok))
})
