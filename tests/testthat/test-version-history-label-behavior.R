# ==============================================================================
# Dosya Yolu: tests/testthat/test-version-history-label-behavior.R
# Açıklama: R/config_version_history.R get_current_version / get_app_version_label
#           fonksiyonlarının DAVRANIŞSAL testleri (mevcut testlerde çağrılmıyordu).
#           get_app_version_label() görünür sürüm etiketinin TEK KAYNAĞIDIR
#           (CLAUDE.md). version_history.md dosyadan okunur; ağ/DB/Shiny GEREKMEZ.
#           Gerçek davranış: get_current_version() sürümü DOĞRUDAN bir karakter
#           dize olarak döndürür (liste değil); get_app_version_label() "v"+sürüm
#           verir. Sürüm metni değişebileceği için sabit "1.0" beklenmez; tür,
#           biçim ve tutarlılık doğrulanır.
# ==============================================================================

.verlabel_source_once <- function() {
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  if (!exists("get_app_version_label",
              envir = globalenv(), mode = "function", inherits = TRUE)) {
    source(
      file.path(resolve_repo_root_for_tests(), "R", "config_version_history.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  invisible(TRUE)
}

testthat::test_that("get_current_version boş olmayan tek bir karakter sürüm döndürür", {
  .verlabel_source_once()
  cv <- get_current_version()
  testthat::expect_true(is.character(cv))
  testthat::expect_length(cv, 1L)
  testthat::expect_true(nzchar(trimws(cv)))
})

testthat::test_that("get_app_version_label 'v' önekli tek dize döndürür", {
  .verlabel_source_once()
  label <- get_app_version_label()
  testthat::expect_length(label, 1L)
  testthat::expect_true(is.character(label))
  testthat::expect_match(label, "^v", perl = TRUE)
})

testthat::test_that("get_app_version_label tam olarak 'v' + get_current_version değeridir", {
  .verlabel_source_once()
  cv <- get_current_version()
  label <- get_app_version_label()
  testthat::expect_identical(label, paste0("v", as.character(cv)[1]))
})
