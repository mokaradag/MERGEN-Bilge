# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-lifecycle-hardening-contract.R
# Açıklama: Dosya yaşam döngüsü sertleştirme sözleşmelerini korur:
#           görünen ad normalizasyonu, kısmi stale indeks + filesystem birleşimi,
#           özetleme dosya türü filtresi ve MCP mutlak yol reddi.
# ==============================================================================

.find_file_lifecycle_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("Dosya yaşam döngüsü testi repo kökünü bulamadı.", call. = FALSE)
}

repo_root_file_lifecycle <- .find_file_lifecycle_repo_root()

if (!exists("resolve_repo_root_for_tests", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(repo_root_file_lifecycle, "tests", "testthat", "helper_bootstrap.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

repo_root_file_lifecycle <- resolve_repo_root_for_tests()

.old_wd_file_lifecycle <- getwd()
setwd(repo_root_file_lifecycle)
withr::defer(setwd(.old_wd_file_lifecycle), testthat::teardown_env())

.file_lifecycle_source <- function(path) {
  source(
    file.path(repo_root_file_lifecycle, path),
    encoding = "UTF-8",
    local = globalenv()
  )
}

for (source_file in c(
  "R/utils_common.R",
  "R/utils_text_encoding.R",
  "R/utils_path_helpers.R",
  "R/helpers_files_path.R",
  "R/utils_atomic_write.R",
  "R/config_file_store.R",
  "R/config_file_store_index_mutation.R",
  "R/config_file_store_registry.R",
  "R/helpers_file_manager_policy.R",
  "R/helpers_file_manager_table.R",
  "R/helpers_summarization_prompts.R",
  "R/module_summarization.R"
)) {
  .file_lifecycle_source(source_file)
}

.make_fake_session_for_lifecycle <- function(user_id = 42L) {
  user_data <- new.env(parent = emptyenv())
  user_data$user_id <- user_id
  user_data$current_session_files <- list()
  user_data$file_manager_data <- list(
    set_attachment_checked = function(filename, checked) TRUE
  )

  session <- new.env(parent = emptyenv())
  session$userData <- user_data
  session
}

test_that("merkezi display normalizasyonu explicit storage display degerini temizler", {
  storage_name <- "20260515123456789_ebb4c864d62182e6_3214515423b0_dummy_test_data.xlsx"

  expect_equal(
    normalize_file_display_name(storage_name),
    "dummy_test_data.xlsx"
  )

  expect_equal(
    fm_clean_file_display_name(
      file_name = "ignored.xlsx",
      file_info = list(display = storage_name)
    ),
    "dummy_test_data.xlsx"
  )

  turkish_storage <- "20260515123456_abcd1234_Türkçe_özet_dosyası.pdf"

  expect_equal(
    normalize_file_display_name(turkish_storage),
    "Türkçe_özet_dosyası.pdf"
  )
})

test_that("kismi stale indeks varken ayni kullanici klasorundeki fiziksel dosyalar gorunur", {
  old_index_path <- MERGEN_INDEX_PATH
  old_uploads_dir <- MERGEN_UPLOADS_DIR
  old_mcp_base_dir <- MERGEN_MCP_BASE_DIR

  temp_root <- tempfile("file_lifecycle_partial_index_")
  dir.create(temp_root, recursive = TRUE)

  test_uploads_dir <- file.path(temp_root, "uploads")
  test_mcp_base_dir <- file.path(temp_root, "mcp")
  user_dir <- file.path(test_mcp_base_dir, "user_42")

  dir.create(user_dir, recursive = TRUE)

  indexed_file <- file.path(user_dir, "20260515120000_abcd1111_rapor.pdf")
  orphan_file <- file.path(user_dir, "20260515120100_abcd2222_dummy_test_data.xlsx")

  writeLines("pdf", indexed_file, useBytes = TRUE)
  writeLines("xlsx", orphan_file, useBytes = TRUE)

  temp_index <- file.path(temp_root, "index.json")

  assign("MERGEN_INDEX_PATH", temp_index, envir = globalenv())
  assign("MERGEN_UPLOADS_DIR", test_uploads_dir, envir = globalenv())
  assign("MERGEN_MCP_BASE_DIR", test_mcp_base_dir, envir = globalenv())

  on.exit({
    assign("MERGEN_INDEX_PATH", old_index_path, envir = globalenv())
    assign("MERGEN_UPLOADS_DIR", old_uploads_dir, envir = globalenv())
    assign("MERGEN_MCP_BASE_DIR", old_mcp_base_dir, envir = globalenv())
    unlink(temp_root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  .save_index(list(
    "42" = list(
      "rapor.pdf" = list(
        path = indexed_file,
        display = "rapor.pdf"
      )
    )
  ))

  listed <- mergen_list_user_files(42L)

  expect_s3_class(listed, "data.frame")
  expect_true("rapor.pdf" %in% listed$name)
  expect_true("dummy_test_data.xlsx" %in% listed$name)
  expect_false(any(grepl("^\\d{8,20}[_-]", listed$name, perl = TRUE)))
})

test_that("ozetleme Excel secimini okumadan reddeder", {
  temp_root <- tempfile("summary_excel_reject_")
  dir.create(temp_root, recursive = TRUE)
  excel_path <- file.path(temp_root, "dummy_test_data.xlsx")
  writeLines("not a real excel but should be rejected before reading", excel_path, useBytes = TRUE)

  on.exit(unlink(temp_root, recursive = TRUE, force = TRUE), add = TRUE)

  session <- .make_fake_session_for_lifecycle(user_id = 42L)
  settings <- shiny::reactiveValues(model_selection = "test-model")

  result <- prepare_summarization_request(
    file_list = list(
      "dummy_test_data.xlsx" = list(
        name = "dummy_test_data.xlsx",
        datapath = excel_path,
        persisted_path = excel_path
      )
    ),
    session = session,
    settings = settings
  )

  expect_false(isTRUE(result$success))
  expect_true(grepl("Dosya Özetleme", result$message, fixed = TRUE))
  expect_true(grepl("dummy_test_data.xlsx", result$message, fixed = TRUE))
})

test_that("MCP resolver mutlak yol argumanini statik sozlesme olarak reddeder", {
  resolver_path <- file.path(repo_root_file_lifecycle, "R", "helpers_mcp_file_resolver.R")
  txt <- paste(readLines(resolver_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  expect_true(
    grepl("Absolute path argument rejected", txt, fixed = TRUE),
    info = "MCP resolver mutlak yol argumanini sadece loglayip basename'e dusmemeli; reddetmelidir."
  )

  expect_true(
    grepl("Mutlak dosya yolu kabul edilmez", txt, fixed = TRUE),
    info = "Kullaniciya acik ve guvenli bir mutlak yol reddi mesaji donmelidir."
  )
})