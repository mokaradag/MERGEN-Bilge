# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-manager-display-name-contract.R
# Açıklama: Dosya Yönetimi tablosunda kalıcı storage adlarının değil, temiz
#           kullanıcı dosya adlarının gösterildiğini doğrular.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()

  gerekli_dosyalar <- c(
    file.path(repo_root, "R", "utils_common.R"),
    file.path(repo_root, "R", "utils_text_encoding.R"),
    file.path(repo_root, "R", "config_file_store_index_mutation.R"),
    file.path(repo_root, "R", "helpers_file_manager_policy.R"),
    file.path(repo_root, "R", "helpers_file_manager_table.R")
  )

  for (dosya in gerekli_dosyalar) {
    source(dosya, encoding = "UTF-8", local = globalenv())
  }
})

test_that("storage prefix temiz dosya adına geri çevrilir", {
  expect_equal(
    recover_display_name_from_storage_name(
      "20260505120545839_ebb4c864d62182e6_3214515423b0_dummy_test_data.xlsx"
    ),
    "dummy_test_data.xlsx"
  )

  expect_equal(
    recover_display_name_from_storage_name(
      "20260505-120545_ebb4c864d62182e6_EK-U Süreç İş Akışları.pdf"
    ),
    "EK-U Süreç İş Akışları.pdf"
  )

  bad_filename <- paste0(
    "20260505-120545_ebb4c864d62182e6_",
    "Ã§alÄ±ÅŸma_Ã¶zet_Ä°ÅŸ.xlsx"
  )

  expect_equal(
    recover_display_name_from_storage_name(bad_filename),
    "çalışma_özet_İş.xlsx"
  )

  expect_equal(
    recover_display_name_from_storage_name(
      "20260505120545_1234_rapor.pdf"
    ),
    "rapor.pdf"
  )
})

test_that("Dosya Yönetimi tablo satırı storage adını kullanıcıya göstermez", {
  storage_name <- "20260505120630621_a8ff2730352d31a4_321450bc407b_dummy_test_data.xlsx"

  row <- fm_build_file_table_row(
    file_name = storage_name,
    file_size = 17715,
    file_info = list(
      name = storage_name,
      datapath = tempfile(fileext = ".xlsx")
    ),
    file_id = "file_test_001",
    ns = identity
  )

  expect_equal(row$Dosya_Adi, "dummy_test_data.xlsx")

  expect_false(
    grepl("^\\d{15,20}_", row$Dosya_Adi, perl = TRUE),
    info = "Dosya tablosunda storage prefix gösterilmemelidir."
  )

  expect_true(
    grepl('data-filename="dummy_test_data.xlsx"', row$Model_Baglam, fixed = TRUE),
    info = "Model Bağlamı checkbox metadata temiz dosya adını taşımalıdır."
  )
})