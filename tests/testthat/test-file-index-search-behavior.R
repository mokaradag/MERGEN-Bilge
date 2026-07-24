# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-index-search-behavior.R
# Açıklama: R/utils_file_index.R dosya indeks arama yardımcılarının DAVRANIŞSAL
#           testleri: .score_path_by_parts (yol parça eşleşme puanı) ve
#           .search_with_hint ("&&" ile parçalı ipucundan dosya çözümü; son parça
#           basename, soldakiler puanlama). .search_with_hint gerçek geçici
#           dizinlerle test edilir. path_exists_relaxed bootstrap'ta global olarak
#           sağlanır. Ağ/DB/Shiny GEREKMEZ.
# ==============================================================================

.fileidx_source_once <- function() {
  if (exists(".score_path_by_parts", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists(".search_with_hint", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists(".search_pdf_word_fallback", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("search_file_in_folder", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "utils_file_index.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# Aynı basename'e (rapor.pdf) sahip iki dosya: istanbul/ ve ankara/ altında.
.fileidx_make_tree <- function() {
  base <- tempfile("idx")
  dir.create(file.path(base, "istanbul"), recursive = TRUE)
  dir.create(file.path(base, "ankara"))
  writeLines("x", file.path(base, "istanbul", "rapor.pdf"))
  writeLines("x", file.path(base, "ankara", "rapor.pdf"))
  base
}

# ------------------------------------------------------------------------------
# .score_path_by_parts
# ------------------------------------------------------------------------------
testthat::test_that(".score_path_by_parts eşleşen parça sayısını (büyük/küçük harf duyarsız) sayar", {
  .fileidx_source_once()
  # Parça yoksa 0.
  testthat::expect_identical(.score_path_by_parts("/home/rapor.pdf", character(0)), 0L)
  # İki parça da yolda var.
  testthat::expect_identical(
    .score_path_by_parts("/home/user/rapor_istanbul.pdf", c("rapor", "istanbul")), 2L
  )
  # Büyük/küçük harf duyarsız: yalnızca biri eşleşir.
  testthat::expect_identical(
    .score_path_by_parts("/home/RAPOR_Ankara.pdf", c("rapor", "istanbul")), 1L
  )
  # Hiç eşleşme yok.
  testthat::expect_identical(.score_path_by_parts("/home/x.pdf", c("zzz")), 0L)
})

# ------------------------------------------------------------------------------
# .search_with_hint: geçersiz ipuçları
# ------------------------------------------------------------------------------
testthat::test_that(".search_with_hint geçersiz/eşleşmeyen ipuçlarında NULL döner", {
  .fileidx_source_once()
  base <- .fileidx_make_tree()

  testthat::expect_null(.search_with_hint(base, NULL))
  testthat::expect_null(.search_with_hint(base, character(0)))
  testthat::expect_null(.search_with_hint(base, NA_character_))
  testthat::expect_null(.search_with_hint(base, 123))            # karakter değil
  # Var olmayan basename.
  testthat::expect_null(.search_with_hint(base, "yokboyle.pdf"))
})

# ------------------------------------------------------------------------------
# .search_with_hint: basename ve puanlamalı çözüm
# ------------------------------------------------------------------------------
testthat::test_that(".search_with_hint basename ipucuyla var olan dosyayı bulur", {
  .fileidx_source_once()
  base <- .fileidx_make_tree()

  bulunan <- .search_with_hint(base, "rapor.pdf")
  testthat::expect_false(is.null(bulunan))
  testthat::expect_identical(basename(bulunan), "rapor.pdf")
})

testthat::test_that(".search_with_hint sol parçalarla en iyi adayı puanlayarak seçer", {
  .fileidx_source_once()
  base <- .fileidx_make_tree()

  # "istanbul && rapor.pdf": son parça basename, "istanbul" puanlama -> istanbul yolu.
  secilen <- .search_with_hint(base, "istanbul && rapor.pdf")
  testthat::expect_false(is.null(secilen))
  testthat::expect_true(grepl("/istanbul/", secilen, fixed = TRUE))

  # "ankara && rapor.pdf" -> ankara yolu seçilir.
  secilen2 <- .search_with_hint(base, "ankara && rapor.pdf")
  testthat::expect_true(grepl("/ankara/", secilen2, fixed = TRUE))
})

testthat::test_that("PDF kaynağı aynı adlı Word belgesine çözümlenir", {
  .fileidx_source_once()
  base <- tempfile("idx_word")
  dir.create(file.path(base, "surecler"), recursive = TRUE)
  word_file <- file.path(base, "surecler", "Is Akisi Talimati.docx")
  writeLines("x", word_file)

  bulunan <- search_file_in_folder(base, "surecler&&Is Akisi Talimati.pdf")

  testthat::expect_identical(
    normalizePath(bulunan, winslash = "/"),
    normalizePath(word_file, winslash = "/")
  )
})

testthat::test_that("tam PDF varsa Word yedeğinden önce seçilir", {
  .fileidx_source_once()
  base <- tempfile("idx_exact")
  dir.create(base, recursive = TRUE)
  pdf_file <- file.path(base, "Kilavuz.pdf")
  writeLines("pdf", pdf_file)
  writeLines("docx", file.path(base, "Kilavuz.docx"))

  bulunan <- search_file_in_folder(base, "Kilavuz.pdf")

  testthat::expect_identical(
    normalizePath(bulunan, winslash = "/"),
    normalizePath(pdf_file, winslash = "/")
  )
})

testthat::test_that("klasör ipucu aynı adlı Word belgeleri arasında doğru adayı seçer", {
  .fileidx_source_once()
  base <- tempfile("idx_hint_word")
  dir.create(file.path(base, "surec_a"), recursive = TRUE)
  dir.create(file.path(base, "surec_b"), recursive = TRUE)
  writeLines("a", file.path(base, "surec_a", "Talimati.docx"))
  word_file <- file.path(base, "surec_b", "Talimati.docx")
  writeLines("b", word_file)

  bulunan <- search_file_in_folder(base, "surec_b&&Talimati.pdf")

  testthat::expect_identical(
    normalizePath(bulunan, winslash = "/"),
    normalizePath(word_file, winslash = "/")
  )
})

testthat::test_that("ipucusuz belirsiz Word eşleşmesi yanlış dosya açmaz", {
  .fileidx_source_once()
  base <- tempfile("idx_ambiguous_word")
  dir.create(file.path(base, "a"), recursive = TRUE)
  dir.create(file.path(base, "b"), recursive = TRUE)
  writeLines("a", file.path(base, "a", "Talimati.docx"))
  writeLines("b", file.path(base, "b", "Talimati.docx"))

  testthat::expect_null(search_file_in_folder(base, "Talimati.pdf"))
  testthat::expect_null(search_file_in_folder(base, "Talimati.xlsx"))
})
