# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-manager-context-policy-contract.R
# Açıklama: Dosya Yönetimi MCP model-bağlam temizleme politikasını doğrular.
# ==============================================================================

.find_repo_root_file_manager_context_policy <- function() {
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
        dir.exists(file.path(candidate, "R"))) {
      return(candidate)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.load_file_manager_context_policy_helpers <- function() {
  repo_root <- .find_repo_root_file_manager_context_policy()
  helper_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root, "R", "helpers_file_manager_context_policy.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  helper_env
}

test_that("MCP bağlam temizleme politikası sadece ilk Excel dosyasını tutar", {
  env <- .load_file_manager_context_policy_helpers()

  file_contents <- list(
    file_a = list(name = "rapor.xlsx"),
    file_b = list(name = "notlar.pdf"),
    file_c = list(name = "veri.xls")
  )

  files_in_context <- list(
    file_a = TRUE,
    file_b = TRUE,
    file_c = TRUE
  )

  plan <- env$fm_plan_mcp_context_cleanup(
    file_contents = file_contents,
    files_in_context = files_in_context
  )

  expect_equal(plan$keep_ids, "file_a")
  expect_equal(plan$non_excel_ids, "file_b")
  expect_equal(plan$excess_ids, "file_c")
  expect_equal(plan$remove_ids, c("file_b", "file_c"))
  expect_equal(plan$detached_names, c("notlar.pdf", "veri.xls"))
  expect_true(plan$removed_any)
  expect_true(plan$excess_removed)
})

test_that("MCP bağlam temizleme politikası stale id değerlerini sessizce kaldırır", {
  env <- .load_file_manager_context_policy_helpers()

  file_contents <- list(
    file_a = list(name = "rapor.xlsx")
  )

  files_in_context <- list(
    file_a = TRUE,
    ghost_id = TRUE
  )

  plan <- env$fm_plan_mcp_context_cleanup(
    file_contents = file_contents,
    files_in_context = files_in_context
  )

  expect_equal(plan$keep_ids, "file_a")
  expect_equal(plan$stale_ids, "ghost_id")
  expect_equal(plan$remove_ids, "ghost_id")
  expect_equal(plan$detached_names, character(0))
  expect_true(plan$removed_any)
  expect_false(plan$excess_removed)
})

test_that("MCP bağlam temizleme politikası boş veya bozuk state ile hata üretmez", {
  env <- .load_file_manager_context_policy_helpers()

  plan <- env$fm_plan_mcp_context_cleanup(
    file_contents = NULL,
    files_in_context = NULL
  )

  expect_equal(plan$keep_ids, character(0))
  expect_equal(plan$remove_ids, character(0))
  expect_false(plan$removed_any)
})