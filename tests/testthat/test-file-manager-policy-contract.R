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
    file.path(repo_root, "R", "helpers_file_manager_policy.R"),
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

test_that("file manager upload limiti sayısal ve deterministiktir", {
  env <- .load_file_manager_policy_helpers()

  withr::local_options(list(mergen.upload_max_mb = 25L))
  expect_equal(env$fm_upload_limit_mb(), 25L)
  expect_equal(env$fm_upload_limit_bytes(), 25 * 1024^2)

  withr::local_options(list(mergen.upload_max_mb = "gecersiz"))
  expect_equal(env$fm_upload_limit_mb(default = 25L), 25L)
})
