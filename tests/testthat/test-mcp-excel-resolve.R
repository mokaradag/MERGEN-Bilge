# ==============================================================================
# Dosya Yolu: tests/testthat/test-mcp-excel-resolve.R
# Açıklama: MCP Excel araç zincirinde oturum dosya kayıt defteri ve yardımcı
# fonksiyonların araç ortamına taşınması kaynaklı regresyonları yakalar.
# Bu test canlı UNC paylaşımı gerektirmez; geçici dosya ile aynı çözüm yolunu
# doğrular.
# ==============================================================================

local({
  gerekli_dosyalar <- c(
    file.path(repo_root_for_tests, "R", "utils_common.R"),
    file.path(repo_root_for_tests, "R", "utils_path_helpers.R"),
    file.path(repo_root_for_tests, "R", "helpers_files.R"),
    file.path(repo_root_for_tests, "R", "utils_excel_reader.R"),
    file.path(repo_root_for_tests, "R", "helpers_mcp_context.R"),
    file.path(repo_root_for_tests, "R", "helpers_mcp_tools.R"),
    file.path(repo_root_for_tests, "R", "helpers_mcp_table_readers.R")
  )

  for (dosya in gerekli_dosyalar) {
    source(dosya, encoding = "UTF-8", local = globalenv())
  }
})

.make_mock_session <- function(user_id = 1L) {
  ud <- new.env(parent = emptyenv())
  ud$current_session_files <- list()
  ud$user_id <- user_id

  session <- new.env(parent = emptyenv())
  session$userData <- ud
  session
}

test_that("helpers_mcp_tools kritik yol yardımcılarını kendi ortamında taşır", {
  expect_true(exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE))

  expect_true(exists("path_exists_relaxed", envir = helpers_mcp_tools, inherits = FALSE))
  expect_true(exists("resolve_readable_path", envir = helpers_mcp_tools, inherits = FALSE))
  expect_true(is.function(helpers_mcp_tools$path_exists_relaxed))
  expect_true(is.function(helpers_mcp_tools$resolve_readable_path))
})

test_that("resolve_file_argument oturum kaydındaki Excel dosyasını fiziksel yoldan çözer", {
  skip_if_not_installed("openxlsx")

  temp_dir <- withr::local_tempdir()
  excel_path <- file.path(temp_dir, "dummy_test_data.xlsx")

  openxlsx::write.xlsx(
    data.frame(
      CalisanID = 1:3,
      Departman = c("IT", "IK", "Finans"),
      Maas = c(100, 120, 140),
      stringsAsFactors = FALSE
    ),
    excel_path
  )

  expect_true(file.exists(excel_path))

  session <- .make_mock_session(user_id = 1L)

  helpers_mcp_tools$register_uploaded_file(
    session = session,
    token = "dummy_test_data.xlsx",
    abs_path = excel_path,
    display_name = "dummy_test_data.xlsx"
  )

  sonuc <- helpers_mcp_tools$resolve_file_argument(
    arg = "dummy_test_data.xlsx",
    session = session
  )

  expect_true(isTRUE(sonuc$ok))
  expect_equal(sonuc$display, "dummy_test_data.xlsx")
  expect_true(helpers_mcp_tools$path_exists_relaxed(sonuc$path))

  okunan <- helpers_mcp_tools$safe_read_excel_table(sonuc$path)
  expect_s3_class(okunan, "data.frame")
  expect_equal(names(okunan), c("CalisanID", "Departman", "Maas"))
  expect_equal(nrow(okunan), 3)
})

test_that("resolve_file_argument file_id alias ile de aynı Excel dosyasını çözer", {
  skip_if_not_installed("openxlsx")

  temp_dir <- withr::local_tempdir()
  excel_path <- file.path(temp_dir, "dummy_test_data.xlsx")

  openxlsx::write.xlsx(
    data.frame(
      CalisanID = 1:2,
      Departman = c("IT", "IK"),
      Maas = c(100, 200),
      stringsAsFactors = FALSE
    ),
    excel_path
  )

  session <- .make_mock_session(user_id = 1L)

  helpers_mcp_tools$register_uploaded_file(
    session = session,
    token = "file_123",
    abs_path = excel_path,
    display_name = "dummy_test_data.xlsx"
  )

  sonuc <- helpers_mcp_tools$resolve_file_argument(
    arg = "file_123",
    session = session
  )

  expect_true(isTRUE(sonuc$ok))
  expect_equal(sonuc$display, "dummy_test_data.xlsx")
  expect_true(helpers_mcp_tools$path_exists_relaxed(sonuc$path))

  okunan <- helpers_mcp_tools$safe_read_excel_table(sonuc$path)
  expect_s3_class(okunan, "data.frame")
  expect_equal(nrow(okunan), 2)
  expect_equal(names(okunan), c("CalisanID", "Departman", "Maas"))
})

test_that("MCP Excel okuyucu global normalize_excel_path bağımlılığına düşmeden çalışır", {
  skip_if_not_installed("openxlsx")

  temp_dir <- withr::local_tempdir()
  excel_path <- file.path(temp_dir, "reader_env_test.xlsx")

  openxlsx::write.xlsx(
    data.frame(
      CalisanID = 1:2,
      Departman = c("IT", "IK"),
      Maas = c(100, 120),
      stringsAsFactors = FALSE
    ),
    excel_path
  )

  expect_identical(environment(helpers_mcp_tools$safe_read_excel_table), helpers_mcp_tools)

  okunan <- helpers_mcp_tools$safe_read_excel_table(excel_path)

  expect_s3_class(okunan, "data.frame")
  expect_equal(names(okunan), c("CalisanID", "Departman", "Maas"))
  expect_equal(nrow(okunan), 2)
})