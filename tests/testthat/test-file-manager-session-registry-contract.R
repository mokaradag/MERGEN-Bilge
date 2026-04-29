# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-manager-session-registry-contract.R
# Açıklama: Dosya Yönetimi oturum dosya kayıt defteri yardımcılarının sözleşmesini doğrular.
# ==============================================================================

.find_repo_root_file_manager_session_registry <- function() {
  adaylar <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (aday in adaylar) {
    if (file.exists(file.path(aday, "app.R")) &&
        dir.exists(file.path(aday, "R"))) {
      return(aday)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.load_file_manager_session_registry_helpers <- function() {
  repo_root <- .find_repo_root_file_manager_session_registry()
  helper_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root, "R", "helpers_file_manager_session_registry.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  helper_env
}

test_that("file manager session registry path normalizasyonu UNC ve Türkçe adları korur", {
  env <- .load_file_manager_session_registry_helpers()

  unc_path <- "\\\\server\\paylasim\\Türkçe Dosya.pdf"

  normalized <- env$fm_normalize_session_registry_path(
    unc_path,
    path_exists_fn = function(path) identical(path, unc_path)
  )

  expect_equal(normalized, "//server/paylasim/Türkçe Dosya.pdf")
})

test_that("file manager session registry path normalizasyonu eksik path için fallback kullanır", {
  env <- .load_file_manager_session_registry_helpers()

  normalized <- env$fm_normalize_session_registry_path(
    "C:\\temp\\olmayan.xlsx",
    path_exists_fn = function(path) FALSE,
    normalize_path_fn = function(path) "C:/temp/olmayan.xlsx"
  )

  expect_equal(normalized, "C:/temp/olmayan.xlsx")
})

test_that("file manager session registry kayıt ekleme ve silme sözleşmesi korunur", {
  env <- .load_file_manager_session_registry_helpers()

  session <- list(userData = new.env(parent = emptyenv()))
  unc_path <- "\\\\server\\paylasim\\Türkçe Dosya.pdf"

  ok <- env$fm_register_session_file(
    session = session,
    filename = "Türkçe Dosya.pdf",
    fpath = unc_path,
    path_exists_fn = function(path) TRUE
  )

  expect_true(isTRUE(ok))
  expect_true(is.list(session$userData$current_session_files))

  entry <- session$userData$current_session_files[["Türkçe Dosya.pdf"]]
  expect_true(is.list(entry))
  expect_equal(entry$name, "Türkçe Dosya.pdf")
  expect_equal(entry$datapath, "//server/paylasim/Türkçe Dosya.pdf")
  expect_equal(entry$path, entry$datapath)
  expect_equal(entry$persisted_path, entry$datapath)

  removed <- env$fm_unregister_session_file(session, "Türkçe Dosya.pdf")

  expect_true(isTRUE(removed))
  expect_null(session$userData$current_session_files[["Türkçe Dosya.pdf"]])
})

test_that("file manager session registry geçersiz girişleri sessizce reddeder", {
  env <- .load_file_manager_session_registry_helpers()

  session <- list(userData = new.env(parent = emptyenv()))

  expect_false(isTRUE(env$fm_register_session_file(session, "", "C:/temp/a.txt")))
  expect_false(isTRUE(env$fm_register_session_file(session, "a.txt", "")))
  expect_false(isTRUE(env$fm_unregister_session_file(session, "")))

  initialized <- env$fm_ensure_session_registry(session)
  expect_true(isTRUE(initialized))
  expect_true(is.list(session$userData$current_session_files))
})