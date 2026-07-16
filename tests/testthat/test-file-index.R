# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-index.R
# Açıklama: Dosya indeksleme yardımcılarının, hem doğrudan dosya adıyla hem de
# ipucu (hiyerarşik parça) formatıyla doğru dosyayı bulmasını test eder.
# ==============================================================================

# Basit basename aramasında hedef dosyanın doğru bulunduğunu doğrular.
test_that("search_file_in_folder basename ile dosyayı bulur", {
  base_dir <- tempfile()
  dir.create(base_dir, recursive = TRUE)

  nested_dir <- file.path(base_dir, "alt")
  dir.create(nested_dir, recursive = TRUE)

  target_file <- file.path(nested_dir, "rapor.docx")
  writeLines("ornek", target_file)

  found <- search_file_in_folder(base_dir, "rapor.docx")
  expect_equal(normalizePath(found, winslash = "/"), normalizePath(target_file, winslash = "/"))
})

# `&&` ile verilen klasör ipuçları kullanıldığında doğru dosyanın bulunduğunu doğrular.
test_that("search_file_in_folder ipucu ile dosyayı bulur", {
  base_dir <- tempfile()
  dir.create(base_dir, recursive = TRUE)

  nested_dir <- file.path(base_dir, "projeA", "mart")
  dir.create(nested_dir, recursive = TRUE)

  target_file <- file.path(nested_dir, "butce.xlsx")
  writeLines("ornek", target_file)

  found <- search_file_in_folder(base_dir, "projeA&&mart&&butce.xlsx")
  expect_equal(normalizePath(found, winslash = "/"), normalizePath(target_file, winslash = "/"))
})

# Dosya adlarının kendisi literal `&&` taşıyabilir. Aynı kökte son parçaya
# benzeyen ayrı bir dosya olsa bile tam basename eşleşmesi öncelikli olmalıdır.
test_that("search_file_in_folder literal && içeren tam dosya adını önce bulur", {
  base_dir <- tempfile()
  dir.create(base_dir, recursive = TRUE)

  nested_dir <- file.path(base_dir, "birim", "alt-surec")
  dir.create(nested_dir, recursive = TRUE)

  exact_file <- file.path(nested_dir, "uretim&&rehberi.pdf")
  misleading_file <- file.path(base_dir, "rehberi.pdf")
  writeLines("exact", exact_file)
  writeLines("misleading", misleading_file)

  found <- search_file_in_folder(base_dir, "uretim&&rehberi.pdf")
  expect_equal(normalizePath(found, winslash = "/"), normalizePath(exact_file, winslash = "/"))
})
