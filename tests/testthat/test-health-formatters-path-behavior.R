# ==============================================================================
# Dosya Yolu: tests/testthat/test-health-formatters-path-behavior.R
# Açıklama: Sistem Durumu formatter yardımcılarının saf davranışını doğrular:
#           health_is_storage_path_id, health_as_windows_explorer_path.
#           Çevrimdışı/deterministik.
# ==============================================================================

repo_root_health_fmt <- resolve_repo_root_for_tests()

.health_fmt_env <- new.env(parent = globalenv())
source(file.path(repo_root_health_fmt, "R/utils_common.R"), encoding = "UTF-8", local = .health_fmt_env)
source(file.path(repo_root_health_fmt, "R/helpers_health_formatters.R"), encoding = "UTF-8", local = .health_fmt_env)

test_that("health_is_storage_path_id bilinen depolama kimliklerini tanır", {
  expect_true(.health_fmt_env$health_is_storage_path_id("storage.files_root"))
  expect_true(.health_fmt_env$health_is_storage_path_id("storage.uploads_root"))
  expect_true(.health_fmt_env$health_is_storage_path_id("storage.index_json"))
  expect_true(.health_fmt_env$health_is_storage_path_id("storage.log_dir"))
  expect_true(.health_fmt_env$health_is_storage_path_id("storage.mcp_base"))
})

test_that("health_is_storage_path_id storage.path. önekini kabul eder", {
  expect_true(.health_fmt_env$health_is_storage_path_id("storage.path.custom_dir"))
  expect_true(.health_fmt_env$health_is_storage_path_id("storage.path.x"))
})

test_that("health_is_storage_path_id ilgisiz kimlikleri reddeder", {
  expect_false(.health_fmt_env$health_is_storage_path_id("db.connection"))
  expect_false(.health_fmt_env$health_is_storage_path_id("storage"))
  expect_false(.health_fmt_env$health_is_storage_path_id("storagex.files_root"))
  expect_false(.health_fmt_env$health_is_storage_path_id(""))
  expect_false(.health_fmt_env$health_is_storage_path_id(NULL))
})

test_that("health_as_windows_explorer_path eğik çizgileri ters çizgiye çevirir", {
  # NOT: kişisel mutlak Windows kullanıcı klasörü yolu KULLANILMAZ; secret-leak
  # sözleşmesi bunu repo içinde yasaklar. Bunun yerine genel bir yol kullanılır.
  expect_identical(
    .health_fmt_env$health_as_windows_explorer_path("C:/veri/proje/data"),
    "C:\\veri\\proje\\data"
  )
  expect_identical(
    .health_fmt_env$health_as_windows_explorer_path("//server/share/klasor"),
    "\\\\server\\share\\klasor"
  )
})

test_that("health_as_windows_explorer_path boş değeri olduğu gibi döndürür", {
  expect_identical(.health_fmt_env$health_as_windows_explorer_path(""), "")
  expect_identical(.health_fmt_env$health_as_windows_explorer_path(NULL), "")
})

test_that("health_as_windows_explorer_path zaten ters-çizgili yolu korur", {
  expect_identical(
    .health_fmt_env$health_as_windows_explorer_path("C:\\zaten\\boyle"),
    "C:\\zaten\\boyle"
  )
})
