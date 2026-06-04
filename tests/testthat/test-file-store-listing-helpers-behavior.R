# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-store-listing-helpers-behavior.R
# Açıklama: R/config_file_store_listing_helpers.R saf liste/dataframe dönüşüm
#           yardımcılarının davranış testleri. File Store public API'si
#           helper_load_file_store.R tarafından global ortama yüklenir.
#           Gerçek DB/SSO/ağ GEREKMEZ; yalnızca geçici dizin/dosya kullanılır.
# ==============================================================================

testthat::test_that(".file_store_lifecycle_key görünen adı küçük harfe indirger", {
  testthat::skip_if_not(exists(".file_store_lifecycle_key", mode = "function"))
  key <- .file_store_lifecycle_key("/veri/Rapor.XLSX", "Rapor.XLSX")
  testthat::expect_type(key, "character")
  testthat::expect_identical(key, tolower(key))  # idempotent küçük harf
  testthat::expect_true(nzchar(key))
})

testthat::test_that(".file_store_deduplicate_rows aynı isimli satırları teke indirir", {
  testthat::skip_if_not(exists(".file_store_deduplicate_rows", mode = "function"))
  df <- data.frame(
    key = c("a", "b"),
    path = c("/x/rapor.xlsx", "/y/rapor.xlsx"),
    name = c("rapor.xlsx", "rapor.xlsx"),
    stringsAsFactors = FALSE
  )
  res <- .file_store_deduplicate_rows(df)
  testthat::expect_identical(nrow(res), 1L)
})

testthat::test_that(".file_store_deduplicate_rows farklı isimleri korur", {
  testthat::skip_if_not(exists(".file_store_deduplicate_rows", mode = "function"))
  df <- data.frame(
    key = c("a", "b", "c"),
    path = c("/x/rapor.xlsx", "/y/diger.pdf", "/z/ucuncu.csv"),
    name = c("rapor.xlsx", "diger.pdf", "ucuncu.csv"),
    stringsAsFactors = FALSE
  )
  res <- .file_store_deduplicate_rows(df)
  testthat::expect_identical(nrow(res), 3L)
})

testthat::test_that(".file_store_deduplicate_rows boş/NULL girdiyi güvenle döndürür", {
  testthat::skip_if_not(exists(".file_store_deduplicate_rows", mode = "function"))
  testthat::expect_null(.file_store_deduplicate_rows(NULL))
  empty_df <- data.frame(key = character(0), path = character(0), name = character(0), stringsAsFactors = FALSE)
  testthat::expect_identical(nrow(.file_store_deduplicate_rows(empty_df)), 0L)
})

testthat::test_that(".file_store_list_user_files_relaxed boş/yok dizin için character(0) döndürür", {
  testthat::skip_if_not(exists(".file_store_list_user_files_relaxed", mode = "function"))
  testthat::expect_identical(.file_store_list_user_files_relaxed(""), character(0))
  testthat::expect_identical(.file_store_list_user_files_relaxed(NULL), character(0))
  yok <- file.path(tempdir(), paste0("yok_", as.integer(runif(1, 1e6, 9e6))))
  testthat::expect_identical(.file_store_list_user_files_relaxed(yok), character(0))
})

testthat::test_that(".file_store_list_user_files_relaxed gerçek dizindeki dosyaları listeler", {
  testthat::skip_if_not(exists(".file_store_list_user_files_relaxed", mode = "function"))
  d <- file.path(tempdir(), paste0("fsl_", as.integer(runif(1, 1e6, 9e6))))
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  writeLines("a", file.path(d, "bir.txt"))
  writeLines("b", file.path(d, "iki.txt"))
  res <- .file_store_list_user_files_relaxed(d)
  testthat::expect_true(length(res) >= 2L)
  testthat::expect_true(all(grepl("\\.txt$", basename(res))))
})

testthat::test_that(".file_store_file_size_safe gerçek dosya boyutu / yok için NA döndürür", {
  testthat::skip_if_not(exists(".file_store_file_size_safe", mode = "function"))
  f <- tempfile(fileext = ".txt")
  writeLines("merhaba dünya", f)
  on.exit(unlink(f), add = TRUE)
  testthat::expect_true(.file_store_file_size_safe(f) > 0)
  testthat::expect_true(is.na(.file_store_file_size_safe(file.path(tempdir(), "kesinlikle_yok_12345.bin"))))
})

testthat::test_that(".file_store_index_record_row liste değerinden key/path/name üretir", {
  testthat::skip_if_not(exists(".file_store_index_record_row", mode = "function"))
  rec <- .file_store_index_record_row("k1", list(path = "/veri/file.pdf", display = "Güzel Dosya.pdf"))
  testthat::expect_identical(rec$key, "k1")
  testthat::expect_true(grepl("file.pdf", rec$path, fixed = TRUE))
  testthat::expect_true(nzchar(rec$name))
})

testthat::test_that(".file_store_merge_same_user_filesystem dosya yoksa deduplike df döndürür", {
  testthat::skip_if_not(exists(".file_store_merge_same_user_filesystem", mode = "function"))
  # Var olmayan kullanıcı: filesystem taraması boş döner, yalnızca dedup uygulanır.
  df <- data.frame(
    key = c("a", "b"),
    path = c("/x/rapor.xlsx", "/y/rapor.xlsx"),
    name = c("rapor.xlsx", "rapor.xlsx"),
    stringsAsFactors = FALSE
  )
  res <- .file_store_merge_same_user_filesystem(df, user_id = 99999987L, idx = list())
  testthat::expect_identical(nrow(res), 1L)
})

testthat::test_that(".file_store_user_dir_paths var olmayan kullanıcı için boş döndürür", {
  testthat::skip_if_not(exists(".file_store_user_dir_paths", mode = "function"))
  res <- .file_store_user_dir_paths(99999987L)
  testthat::expect_identical(res, character(0))
})
