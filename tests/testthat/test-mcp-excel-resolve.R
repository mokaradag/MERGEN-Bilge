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
    file.path(repo_root_for_tests, "R", "helpers_mcp_table_readers.R"),
    file.path(repo_root_for_tests, "R", "helpers_mcp_file_resolver.R")
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

test_that("resolve_file_argument varsayılan olarak başka kullanıcı bucket'ına düşmez", {
  temp_dir <- withr::local_tempdir()
  other_user_file <- file.path(temp_dir, "shared_name.csv")
  writeLines(c("a,b", "1,2"), other_user_file, useBytes = TRUE)

  index_path <- file.path(temp_dir, "index.json")
  jsonlite::write_json(
    list(
      "999" = list(
        "shared_name.csv" = list(
          path = other_user_file,
          display = "shared_name.csv"
        )
      )
    ),
    index_path,
    auto_unbox = TRUE
  )

  session <- .make_mock_session(user_id = 1L)

  withr::local_options(list(
    mergen.index_path = index_path,
    mergen.mcp.allow_cross_bucket_lookup = FALSE
  ))

  sonuc <- helpers_mcp_tools$resolve_file_argument(
    arg = "shared_name.csv",
    session = session
  )

  expect_false(
    isTRUE(sonuc$ok),
    info = "MCP dosya çözümleme varsayılan olarak başka kullanıcı bucket'ındaki aynı adlı dosyayı döndürmemelidir."
  )

  withr::local_options(list(
    mergen.index_path = index_path,
    mergen.mcp.allow_cross_bucket_lookup = TRUE
  ))

  opt_in_sonuc <- helpers_mcp_tools$resolve_file_argument(
    arg = "shared_name.csv",
    session = session
  )

  expect_true(
    isTRUE(opt_in_sonuc$ok),
    info = "Geçiş/migrasyon için cross-bucket lookup yalnızca açık opt-in ile çalışmalıdır."
  )
  expect_equal(opt_in_sonuc$display, "shared_name.csv")
})

test_that("resolve_file_argument mutlak path argümanını session registry yoksa reddeder", {
  temp_dir <- withr::local_tempdir()
  secret_path <- file.path(temp_dir, "secret.xlsx")

  writeLines("secret", secret_path, useBytes = TRUE)
  expect_true(file.exists(secret_path))

  session <- .make_mock_session(user_id = 1L)

  sonuc <- helpers_mcp_tools$resolve_file_argument(
    arg = secret_path,
    session = session
  )

  expect_false(
    isTRUE(sonuc$ok),
    info = "MCP resolve_file_argument doğrudan mutlak dosya yolunu kabul etmemelidir."
  )
})

test_that("resolve_file_argument aynı mutlak path'i yalnızca session registry üzerinden çözer", {
  temp_dir <- withr::local_tempdir()
  excel_path <- file.path(temp_dir, "registered.xlsx")

  writeLines("registered", excel_path, useBytes = TRUE)
  expect_true(file.exists(excel_path))

  session <- .make_mock_session(user_id = 1L)

  helpers_mcp_tools$register_uploaded_file(
    session = session,
    token = "registered.xlsx",
    abs_path = excel_path,
    display_name = "registered.xlsx"
  )

  sonuc <- helpers_mcp_tools$resolve_file_argument(
    arg = "registered.xlsx",
    session = session
  )

  expect_true(isTRUE(sonuc$ok))
  expect_equal(sonuc$display, "registered.xlsx")
  expect_true(helpers_mcp_tools$path_exists_relaxed(sonuc$path))
})

test_that("resolve_file_argument legacy root-level index kaydını varsayılan olarak kullanmaz", {
  temp_dir <- withr::local_tempdir()
  legacy_file <- file.path(temp_dir, "legacy_root.csv")
  writeLines(c("a,b", "1,2"), legacy_file, useBytes = TRUE)

  index_path <- file.path(temp_dir, "index.json")

  jsonlite::write_json(
    list(
      "legacy_root.csv" = list(
        path = legacy_file,
        display = "legacy_root.csv"
      )
    ),
    index_path,
    auto_unbox = TRUE
  )

  session <- .make_mock_session(user_id = 1L)

  withr::local_options(list(
    mergen.index_path = index_path,
    mergen.mcp.allow_cross_bucket_lookup = FALSE
  ))

  sonuc <- helpers_mcp_tools$resolve_file_argument(
    arg = "legacy_root.csv",
    session = session
  )

  expect_false(
    isTRUE(sonuc$ok),
    info = "MCP resolver legacy root-level index fallback'ı varsayılan olarak kullanmamalıdır."
  )
})