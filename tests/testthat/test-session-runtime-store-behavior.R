# ==============================================================================
# Dosya Yolu: tests/testthat/test-session-runtime-store-behavior.R
# Açıklama: R/utils_session_cleanup.R oturum-yerel liste deposu yardımcılarının
#           DAVRANIŞSAL testleri (mevcut testlerde çağrılmıyordu):
#             - .session_user_data_normalize_key (anahtar doğrulama)
#             - session_user_data_env (session$userData environment sözleşmesi)
#             - session_runtime_store_keys (depo anahtar listesi, MCP dahil/hariç)
#             - session_runtime_store_get (+ set ile yaz-oku döngüsü)
#           Sentetik bir session (userData = environment) kullanılır; Shiny/DB/ağ
#           GEREKMEZ. session$userData'nın environment olması SÖZLEŞMEDİR.
# ==============================================================================

.sessstore_source_once <- function() {
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  if (!exists("session_runtime_store_keys",
              envir = globalenv(), mode = "function", inherits = TRUE)) {
    source(
      file.path(resolve_repo_root_for_tests(), "R", "utils_session_cleanup.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  invisible(TRUE)
}

# Sentetik oturum: userData environment OLMALIDIR.
.sessstore_fake_session <- function() {
  list(userData = new.env(parent = emptyenv()))
}

# ------------------------------------------------------------------------------
# .session_user_data_normalize_key
# ------------------------------------------------------------------------------
testthat::test_that(".session_user_data_normalize_key geçerli anahtarı döndürür, geçersizde durur", {
  .sessstore_source_once()
  testthat::expect_identical(.session_user_data_normalize_key("chart_store", "o"), "chart_store")
  # NULL / boş / çok-elemanlı anahtar reddedilir.
  testthat::expect_error(.session_user_data_normalize_key(NULL, "o"), "anahtar")
  testthat::expect_error(.session_user_data_normalize_key("", "o"), "anahtar")
  testthat::expect_error(.session_user_data_normalize_key(c("a", "b"), "o"), "anahtar")
})

# ------------------------------------------------------------------------------
# session_user_data_env
# ------------------------------------------------------------------------------
testthat::test_that("session_user_data_env userData environment'ını döndürür", {
  .sessstore_source_once()
  sess <- .sessstore_fake_session()
  testthat::expect_true(identical(session_user_data_env(sess), sess$userData))
})

testthat::test_that("session_user_data_env geçersiz session/userData için durur", {
  .sessstore_source_once()
  testthat::expect_error(session_user_data_env(NULL), "session")
  # userData yok / environment değil.
  testthat::expect_error(session_user_data_env(list(userData = NULL)), "userData")
  testthat::expect_error(session_user_data_env(list(userData = list())), "userData")
})

# ------------------------------------------------------------------------------
# session_runtime_store_keys
# ------------------------------------------------------------------------------
testthat::test_that("session_runtime_store_keys MCP dahil/hariç anahtar listesini döndürür", {
  .sessstore_source_once()
  tum <- session_runtime_store_keys()
  testthat::expect_true(all(c("current_session_files", "file_summaries", "chart_store") %in% tum))
  testthat::expect_true("mcp_registry_snapshot" %in% tum)

  # include_mcp = FALSE -> mcp anahtarı çıkarılır.
  mcpsuz <- session_runtime_store_keys(include_mcp = FALSE)
  testthat::expect_false("mcp_registry_snapshot" %in% mcpsuz)
  testthat::expect_true("chart_store" %in% mcpsuz)
})

# ------------------------------------------------------------------------------
# session_runtime_store_get (+ set roundtrip)
# ------------------------------------------------------------------------------
testthat::test_that("session_runtime_store_get boş depoda varsayılan listeyi döndürür", {
  .sessstore_source_once()
  sess <- .sessstore_fake_session()
  donen <- session_runtime_store_get(sess, "chart_store")
  testthat::expect_true(is.list(donen))
  testthat::expect_length(donen, 0L)
})

testthat::test_that("session_runtime_store_get set sonrası depolanan listeyi okur", {
  .sessstore_source_once()
  sess <- .sessstore_fake_session()
  session_user_data_set_list(
    sess,
    session_runtime_store_key("chart_store"),
    list(a = 1, b = 2)
  )
  donen <- session_runtime_store_get(sess, "chart_store")
  testthat::expect_length(donen, 2L)
  testthat::expect_identical(donen$a, 1)
  testthat::expect_identical(donen$b, 2)
})
