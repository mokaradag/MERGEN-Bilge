# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-manager-policy-contract.R
# Açıklama: Dosya Yönetimi seçim/uzantı/yükleme politikası yardımcılarının
#           saf ve UTF-8 güvenli sözleşmesini doğrular.
# ==============================================================================

.find_repo_root_file_manager_policy <- function() {
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

.load_file_manager_policy_helpers <- function() {
  repo_root <- .find_repo_root_file_manager_policy()
  helper_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root, "R", "utils_common.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  source(
    file.path(repo_root, "R", "utils_upload_validator.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  source(
    file.path(repo_root, "R", "helpers_file_manager_policy.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  source(
    file.path(repo_root, "R", "helpers_file_manager_context_policy.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  source(
    file.path(repo_root, "R", "helpers_file_manager_refresh_guard.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  source(
    file.path(repo_root, "R", "helpers_file_manager_storage.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  helper_env
}

test_that("file manager seçim kuralı metinleri korunur", {
  env <- .load_file_manager_policy_helpers()

  expect_equal(
    env$fm_attach_rule_hint_text(mcp_enabled = TRUE),
    "Seçim kuralı: MCP açıkken yalnızca 1 dosya eklenebilir."
  )

  expect_equal(
    env$fm_attach_rule_hint_text(
      summarization_mode = TRUE,
      allow_summarization_text = TRUE
    ),
    "Seçim kuralı: Dosya Özetleme modunda birden fazla dosya seçebilirsiniz."
  )

  expect_equal(
    env$fm_attach_rule_hint_text(),
    "Seçim kuralı: MCP kapalıyken birden fazla dosya seçebilirsiniz."
  )
})

test_that("file manager uzantı politikası korunur", {
  env <- .load_file_manager_policy_helpers()

  expect_equal(
    env$fm_summarization_allowed_extensions(),
    c("doc", "docx", "pdf", "txt")
  )

  expect_equal(
    env$fm_resolve_allowed_extensions(
      generate_message = TRUE,
      summarization_mode = TRUE
    ),
    env$fm_summarization_allowed_extensions()
  )

  expect_equal(
    env$fm_resolve_allowed_extensions(
      generate_message = FALSE,
      summarization_mode = TRUE
    ),
    env$fm_normal_allowed_extensions()
  )

  expect_true(all(c("xlsx", "xls", "csv", "json", "py", "html") %in%
                    env$fm_normal_allowed_extensions()))
})

test_that("özetleme upload politikası Excel dosyasını reddeder ve UTF-8 belge adını kabul eder", {
  env <- .load_file_manager_policy_helpers()
  allowed <- env$fm_resolve_allowed_extensions(
    generate_message = TRUE,
    summarization_mode = TRUE
  )

  expect_false("xlsx" %in% allowed)
  expect_false("xls" %in% allowed)

  xlsx_file <- tempfile("fm_summary_", fileext = ".xlsx")
  writeLines("x", xlsx_file, useBytes = TRUE)
  on.exit(unlink(xlsx_file, force = TRUE), add = TRUE)

  rejected <- env$validate_uploaded_file(
    xlsx_file,
    filename = "bütçe.xlsx",
    allowed_ext = allowed
  )

  expect_false(rejected$ok)
  expect_equal(rejected$code, "ext_not_allowed")

  pdf_file <- tempfile("fm_summary_", fileext = ".pdf")
  writeLines("x", pdf_file, useBytes = TRUE)
  on.exit(unlink(pdf_file, force = TRUE), add = TRUE)

  accepted <- env$validate_uploaded_file(
    pdf_file,
    filename = "İğdır_özeti.pdf",
    allowed_ext = allowed
  )

  expect_true(accepted$ok)
  expect_null(accepted$code)
})

test_that("MCP Excel bağlam temizliği non-Excel ve fazla Excel seçimlerini kaldırır", {
  env <- .load_file_manager_policy_helpers()

  file_contents <- list(
    pdf1 = list(name = "notlar.pdf"),
    xlsx1 = list(name = "veri.xlsx"),
    xls1 = list(name = "plan.xls")
  )

  files_in_context <- list(
    pdf1 = TRUE,
    xlsx1 = TRUE,
    xls1 = TRUE,
    ghost = TRUE
  )

  plan <- env$fm_plan_mcp_context_cleanup(
    file_contents = file_contents,
    files_in_context = files_in_context
  )

  expect_identical(plan$keep_ids, "xlsx1")
  expect_setequal(plan$stale_ids, "ghost")
  expect_setequal(plan$non_excel_ids, "pdf1")
  expect_setequal(plan$excess_ids, "xls1")
  expect_setequal(plan$remove_ids, c("ghost", "pdf1", "xls1"))
  expect_true(plan$removed_any)
  expect_true(plan$excess_removed)
})

test_that("file manager refresh guard eski refresh sonucunun yeni state'i ezmesini engeller", {
  env <- .load_file_manager_policy_helpers()

  guard <- env$fm_create_refresh_request_guard()
  old_request <- guard$next_id()
  new_request <- guard$next_id()

  expect_false(guard$is_latest(old_request))
  expect_true(guard$is_latest(new_request))
  expect_false(guard$is_latest(NA_integer_))
  expect_false(guard$is_latest("gecersiz"))
})

test_that("file manager upload limiti sayısal ve deterministiktir", {
  env <- .load_file_manager_policy_helpers()

  withr::local_options(list(mergen.upload_max_mb = 25L))
  expect_equal(env$fm_upload_limit_mb(), 25L)
  expect_equal(env$fm_upload_limit_bytes(), 25 * 1024^2)

  withr::local_options(list(mergen.upload_max_mb = "gecersiz"))
  expect_equal(env$fm_upload_limit_mb(default = 25L), 25L)
})

test_that("file manager kullanıcı kimliği normalizasyonu placeholder değerleri reddeder", {
  env <- .load_file_manager_policy_helpers()

  expect_equal(env$fm_normalize_user_id(NULL), "unknown")
  expect_equal(env$fm_normalize_user_id(0L), "unknown")
  expect_equal(env$fm_normalize_user_id(" unknown "), "unknown")
  expect_equal(env$fm_normalize_user_id("NaN"), "unknown")
  expect_equal(env$fm_normalize_user_id(42L), "42")

  expect_true(env$fm_valid_user_id(42L))
  expect_false(env$fm_valid_user_id("0"))
})

test_that("file manager kullanıcıya özel yükleme klasörünü deterministik türetir", {
  env <- .load_file_manager_policy_helpers()

  base_dir <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
  withr::local_options(list(mergen.mcp_base_dir = base_dir))

  helpers <- env$fm_create_server_storage_helpers(
    module_user_id_chr = function() "42",
    fm_debug = function(...) invisible(NULL)
  )

  expect_equal(
    normalizePath(helpers$get_user_upload_dir(), winslash = "/", mustWork = FALSE),
    normalizePath(file.path(base_dir, "user_42"), winslash = "/", mustWork = FALSE)
  )
})

test_that("file manager geçersiz kullanıcı kimliğiyle kalıcı indeks yazmaz", {
  env <- .load_file_manager_policy_helpers()

  calls <- new.env(parent = emptyenv())
  calls$n <- 0L

  env$path_exists_relaxed <- function(path) file.exists(path)
  env$mergen_register_uploaded_file <- function(src_path,
                                                as_name,
                                                user_id,
                                                persist_under_mcp_base = TRUE) {
    calls$n <- calls$n + 1L
    invisible(TRUE)
  }

  tmp_file <- tempfile("fm_policy_", fileext = ".txt")
  writeLines("deneme", tmp_file, useBytes = TRUE)
  on.exit(unlink(tmp_file, force = TRUE), add = TRUE)

  helpers <- env$fm_create_server_storage_helpers(
    module_user_id_chr = function() "42",
    fm_debug = function(...) invisible(NULL)
  )

  expect_false(isTRUE(helpers$ensure_persisted_upload_index(
    abs_path = tmp_file,
    display_name = "güvenli.txt",
    uid = "0"
  )))
  expect_identical(calls$n, 0L)

  expect_false(isTRUE(helpers$ensure_persisted_upload_index(
    abs_path = tmp_file,
    display_name = "güvenli.txt",
    uid = "unknown"
  )))
  expect_identical(calls$n, 0L)

  expect_true(isTRUE(helpers$ensure_persisted_upload_index(
    abs_path = tmp_file,
    display_name = "güvenli.txt",
    uid = "42"
  )))
  expect_identical(calls$n, 1L)
})

test_that("file manager saf biçimlendirme yardımcıları modülden bağımsızdır", {
  env <- .load_file_manager_policy_helpers()

  expect_true(grepl("fa-file-pdf", env$fm_file_ext_icon_html("PDF"), fixed = TRUE))
  expect_true(grepl("PDF", env$fm_file_ext_icon_html("PDF"), fixed = TRUE))
  expect_true(grepl("fa-file", env$fm_file_ext_icon_html("bilinmeyen"), fixed = TRUE))

  fallback_time <- as.POSIXct("2024-01-02 03:04:05", tz = "UTC")
  expect_equal(
    env$fm_format_file_timestamp(path = NULL, fallback_time = fallback_time),
    "2024-01-02 03:04"
  )
})