# ==============================================================================
# Dosya Yolu: tests/testthat/test-session-user-data-store.R
# Açıklama: session$userData içindeki liste tabanlı oturum depolarının merkezi
#           yardımcılarla güvenli biçimde yönetildiğini doğrular.
# ==============================================================================

repo_root <- resolve_repo_root_for_tests()

source(
  file.path(repo_root, "R", "utils_common.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root, "R", "utils_session_cleanup.R"),
  encoding = "UTF-8",
  local = globalenv()
)

.fake_session_user_data_store <- function() {
  list(
    userData = new.env(parent = emptyenv()),
    token = "test-token"
  )
}

test_that("session_user_data_get_list eksik listeyi güvenli şekilde oluşturur", {
  session <- .fake_session_user_data_store()

  out <- session_user_data_get_list(session, "file_summaries")

  expect_true(is.list(out))
  expect_identical(out, list())
  expect_true(is.list(session$userData$file_summaries))
})

test_that("session_user_data_set_list yalnızca liste değerleri kabul eder", {
  session <- .fake_session_user_data_store()

  session_user_data_set_list(
    session,
    "current_session_files",
    list("a.xlsx" = list(path = "a.xlsx"))
  )

  expect_true(is.list(session$userData$current_session_files))
  expect_equal(names(session$userData$current_session_files), "a.xlsx")

  expect_error(
    session_user_data_set_list(session, "broken", "liste değil"),
    "liste bekleniyor"
  )
})

test_that("session_user_data_put_list_item ve remove item adlandırılmış öğeleri yönetir", {
  session <- .fake_session_user_data_store()

  session_user_data_put_list_item(
    session,
    "current_session_files",
    "rapor.xlsx",
    list(name = "rapor.xlsx", path = "tmp/rapor.xlsx")
  )

  expect_equal(
    session$userData$current_session_files$rapor.xlsx$name,
    "rapor.xlsx"
  )

  session_user_data_remove_list_item(
    session,
    "current_session_files",
    "rapor.xlsx"
  )

  expect_null(session$userData$current_session_files$rapor.xlsx)
})

test_that("session_user_data_reset_lists birden fazla store alanını temizler", {
  session <- .fake_session_user_data_store()

  session_user_data_put_list_item(session, "file_summaries", "a.txt", "özet")
  session_user_data_put_list_item(session, "mcp_registry_snapshot", "a.txt", list(path = "a.txt"))

  session_user_data_reset_lists(
    session,
    c("file_summaries", "mcp_registry_snapshot")
  )

  expect_identical(session$userData$file_summaries, list())
  expect_identical(session$userData$mcp_registry_snapshot, list())
})

test_that("session_user_data_get_list liste olmayan mevcut alanı erken yakalar", {
  session <- .fake_session_user_data_store()
  session$userData$file_summaries <- "yanlış tip"

  expect_error(
    session_user_data_get_list(session, "file_summaries"),
    "liste olmalıdır"
  )
})