# ==============================================================================
# Dosya Yolu: tests/testthat/test-config-file-store-listing-helpers-behavior.R
# Açıklama: R/config_file_store_listing_helpers.R saf liste/dataframe
#           dönüşümlerinin davranışsal testleri. Dosya boyutu, yaşam-döngüsü
#           anahtarı, satır tekilleştirme, index kaydı satırı ve gevşek dizin
#           listeleme doğrulanır. Gerçek index mutasyonu/ağ yoktur.
# ==============================================================================

testthat::local_edition(3)

# Bu yardımcılar bağımlı oldukları display-name/yol fonksiyonlarıyla birlikte
# helper_load_file_store.R tarafından globalenv'e yüklenir; izole bir ortama
# kaynaklanır ki bağımlılıklar parent (globalenv) üzerinden çözülsün.
.fsl_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "config_file_store_listing_helpers.R"),
  encoding = "UTF-8",
  local = .fsl_env
)

.fsl_ready <- exists("normalize_file_display_name", envir = globalenv(), inherits = TRUE) &&
  exists("recover_display_name_from_storage_name", envir = globalenv(), inherits = TRUE)

# -----------------------------------------------------------------------------
# .file_store_file_size_safe
# -----------------------------------------------------------------------------

test_that(".file_store_file_size_safe var olan dosyanın boyutunu, eksik dosya için NA döner", {
  tf <- tempfile()
  writeBin(as.raw(rep(1L, 42L)), tf)
  expect_equal(.fsl_env$.file_store_file_size_safe(tf), 42)
  expect_true(is.na(.fsl_env$.file_store_file_size_safe(file.path(tempdir(), "yok_olan_dosya_xyz"))))
})

# -----------------------------------------------------------------------------
# .file_store_lifecycle_key
# -----------------------------------------------------------------------------

test_that(".file_store_lifecycle_key görünen adı küçük harfe çevirerek tekil anahtar üretir", {
  skip_if_not(.fsl_ready, "display-name yardımcıları yüklü değil")
  k <- .fsl_env$.file_store_lifecycle_key("/x/1700000000_abc_Rapor.PDF", "Rapor.PDF")
  expect_identical(k, "rapor.pdf")
})

# -----------------------------------------------------------------------------
# .file_store_deduplicate_rows
# -----------------------------------------------------------------------------

test_that(".file_store_deduplicate_rows aynı yaşam-döngüsü anahtarlı satırları teke indirir", {
  skip_if_not(.fsl_ready, "display-name yardımcıları yüklü değil")
  df <- data.frame(
    key = c("a", "b", "c"),
    path = c("/x/1_Rapor.pdf", "/x/2_Rapor.pdf", "/x/3_Baska.pdf"),
    name = c("Rapor.pdf", "Rapor.pdf", "Baska.pdf"),
    stringsAsFactors = FALSE
  )
  dd <- .fsl_env$.file_store_deduplicate_rows(df)
  # İki "Rapor.pdf" tek satıra iner; "Baska.pdf" korunur.
  expect_equal(nrow(dd), 2L)
  expect_setequal(dd$name, c("Rapor.pdf", "Baska.pdf"))
  # İlk eşleşen korunur (path 1).
  expect_identical(dd$path[dd$name == "Rapor.pdf"], "/x/1_Rapor.pdf")
})

test_that(".file_store_deduplicate_rows boş/NULL/data.frame olmayan girdiyi olduğu gibi döner", {
  expect_null(.fsl_env$.file_store_deduplicate_rows(NULL))
  bos <- data.frame(key = character(0), path = character(0), name = character(0), stringsAsFactors = FALSE)
  expect_equal(nrow(.fsl_env$.file_store_deduplicate_rows(bos)), 0L)
})

# -----------------------------------------------------------------------------
# .file_store_index_record_row
# -----------------------------------------------------------------------------

test_that(".file_store_index_record_row liste değerden key/path/name üreten kayıt üretir", {
  skip_if_not(.fsl_ready, "display-name yardımcıları yüklü değil")
  rr <- .fsl_env$.file_store_index_record_row("Belge.txt", list(path = "/x/9_Belge.txt", display = "Belge.txt"))
  expect_identical(rr$key, "Belge.txt")
  expect_identical(rr$name, "Belge.txt")
  expect_true(grepl("Belge.txt$", rr$path))
})

test_that(".file_store_index_record_row düz karakter değerden de kayıt üretir", {
  skip_if_not(.fsl_ready, "display-name yardımcıları yüklü değil")
  rr <- .fsl_env$.file_store_index_record_row("Veri.csv", "/x/Veri.csv")
  expect_identical(rr$key, "Veri.csv")
  # Düz değerde display yoksa key görünen ad olarak kullanılır.
  expect_true(nzchar(rr$name))
})

# -----------------------------------------------------------------------------
# .file_store_list_user_files_relaxed
# -----------------------------------------------------------------------------

test_that(".file_store_list_user_files_relaxed klasördeki dosyaları tam yolla listeler", {
  d <- file.path(tempdir(), paste0("fsl_", as.integer(stats::runif(1, 1, 1e7))))
  dir.create(d, showWarnings = FALSE, recursive = TRUE)
  writeLines("a", file.path(d, "f1.txt"))
  writeLines("b", file.path(d, "f2.txt"))

  out <- .fsl_env$.file_store_list_user_files_relaxed(d)
  expect_equal(length(out), 2L)
  expect_setequal(basename(out), c("f1.txt", "f2.txt"))
})

test_that(".file_store_list_user_files_relaxed boş/olmayan dizin için boş karakter döner", {
  expect_equal(length(.fsl_env$.file_store_list_user_files_relaxed("")), 0L)
  expect_equal(length(.fsl_env$.file_store_list_user_files_relaxed(NULL)), 0L)
  expect_equal(
    length(.fsl_env$.file_store_list_user_files_relaxed(file.path(tempdir(), "yok_dizin_xyz"))),
    0L
  )
})
