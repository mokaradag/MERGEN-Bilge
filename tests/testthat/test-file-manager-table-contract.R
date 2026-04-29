# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-manager-table-contract.R
# Açıklama: Dosya Yönetimi tablo yardımcılarının saf HTML/satır sözleşmesini doğrular.
# ==============================================================================

.load_file_manager_table_helpers <- function() {
  repo_root <- resolve_repo_root_for_tests()
  helper_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root, "R", "helpers_file_manager_policy.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  source(
    file.path(repo_root, "R", "helpers_file_manager_table.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  helper_env
}

test_that("file manager tablo şeması korunur", {
  env <- .load_file_manager_table_helpers()
  df <- env$fm_empty_files_df()

  expect_true(is.data.frame(df))
  expect_equal(nrow(df), 0L)
  expect_equal(
    names(df),
    c("Dosya_Adi", "Boyut", "Tur", "Yuklenme_Tarihi", "Islemler", "Model_Baglam")
  )
})

test_that("file manager tablo eylem HTML sözleşmesi korunur", {
  env <- .load_file_manager_table_helpers()
  ns <- function(x) paste0("fm-", x)

  actions <- env$fm_build_file_actions_html("abc123", ns = ns)

  expect_true(grepl("file-action-btn file-view js-file-action", actions, fixed = TRUE))
  expect_true(grepl("data-action=\"view\"", actions, fixed = TRUE))
  expect_true(grepl("data-download-id=\"abc123\"", actions, fixed = TRUE))
  expect_true(grepl("data-action=\"delete\"", actions, fixed = TRUE))
  expect_true(grepl("id=\"fm-download_abc123\"", actions, fixed = TRUE))
})

test_that("file manager bağlam checkbox HTML sözleşmesi korunur", {
  env <- .load_file_manager_table_helpers()
  ns <- function(x) paste0("fm-", x)

  attach <- env$fm_build_attach_cell_html(
    file_id = "abc123",
    file_name = "Türkçe Dosya.pdf",
    ns = ns
  )

  expect_true(grepl("class=\"attach-checkbox\"", attach, fixed = TRUE))
  expect_true(grepl("id=\"fm-attach_abc123\"", attach, fixed = TRUE))
  expect_true(grepl("data-file-id=\"abc123\"", attach, fixed = TRUE))
  expect_true(grepl("Türkçe Dosya.pdf", attach, fixed = TRUE))
  expect_true(grepl("Model bağlamına ekle veya çıkar", attach, fixed = TRUE))
})

test_that("file manager tablo satırı kullanıcıya görünen alanları korur", {
  withr::local_envvar(c(TZ = "UTC"))

  env <- .load_file_manager_table_helpers()
  ns <- function(x) paste0("fm-", x)

  temp_pdf <- tempfile(fileext = ".pdf")
  writeBin(charToRaw("%PDF-1.4\n"), temp_pdf)

  target_time <- as.POSIXct("2024-01-02 03:04:05", tz = "UTC")
  try(Sys.setFileTime(temp_pdf, target_time), silent = TRUE)

  row <- env$fm_build_file_table_row(
    file_name = "rapor.pdf",
    file_size = 2048,
    file_info = list(datapath = temp_pdf),
    file_id = "f1",
    ns = ns
  )

  expect_true(is.data.frame(row))
  expect_equal(nrow(row), 1L)
  expect_equal(row$Dosya_Adi[[1]], "rapor.pdf")
  expect_equal(row$Boyut[[1]], "2 KB")
  expect_true(grepl("PDF", row$Tur[[1]], fixed = TRUE))
  expect_equal(row$Yuklenme_Tarihi[[1]], "2024-01-02 03:04")
  expect_true(grepl("data-download-id=\"f1\"", row$Islemler[[1]], fixed = TRUE))
  expect_true(grepl("id=\"fm-attach_f1\"", row$Model_Baglam[[1]], fixed = TRUE))
})