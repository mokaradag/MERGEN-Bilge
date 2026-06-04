# ==============================================================================
# Dosya Yolu: tests/testthat/test-scalar-coercion-helpers-behavior.R
# Açıklama: Birkaç modülde tanımlı, daha önce doğrudan test edilmeyen küçük saf
#           skaler dönüştürme/kimlik yardımcılarının davranış testleri:
#             - .normalize_user_session_id (R/helpers_user_session_identity.R)
#             - .mb_feature_api_key_scalar (R/helpers_feature_api_key.R)
#             - .fm_context_chr            (R/helpers_file_manager_context_policy.R)
#           Her dosya izole bir environment'e kaynaklanır. Gerçek DB/SSO/ağ yok.
# ==============================================================================

.source_into_env <- function(rel_path) {
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  source(file.path(resolve_repo_root_for_tests(), rel_path), encoding = "UTF-8", local = env)
  env
}

# --- .normalize_user_session_id -----------------------------------------------

testthat::test_that(".normalize_user_session_id geçerli sayısal/karakter kimlikleri integer'a çevirir", {
  env <- .source_into_env("R/helpers_user_session_identity.R")
  testthat::expect_identical(env$.normalize_user_session_id(5), 5L)
  testthat::expect_identical(env$.normalize_user_session_id("7"), 7L)
  testthat::expect_identical(env$.normalize_user_session_id(3.0), 3L)
})

testthat::test_that(".normalize_user_session_id geçersiz/negatif kimliklerde 0 döndürür", {
  env <- .source_into_env("R/helpers_user_session_identity.R")
  testthat::expect_identical(env$.normalize_user_session_id(-3), 0L)
  testthat::expect_identical(env$.normalize_user_session_id("abc"), 0L)
  testthat::expect_identical(env$.normalize_user_session_id(NULL), 0L)
  testthat::expect_identical(env$.normalize_user_session_id(NA), 0L)
})

testthat::test_that(".normalize_user_session_id allow_zero=FALSE iken sıfırı reddeder", {
  env <- .source_into_env("R/helpers_user_session_identity.R")
  testthat::expect_identical(env$.normalize_user_session_id(0, allow_zero = TRUE), 0L)
  testthat::expect_identical(env$.normalize_user_session_id(0, allow_zero = FALSE), 0L)
  # Pozitif kimlik allow_zero=FALSE'ta da korunur.
  testthat::expect_identical(env$.normalize_user_session_id(9, allow_zero = FALSE), 9L)
})

# --- .mb_feature_api_key_scalar -----------------------------------------------

testthat::test_that(".mb_feature_api_key_scalar NULL/NA için boş string döndürür", {
  env <- .source_into_env("R/helpers_feature_api_key.R")
  testthat::expect_identical(env$.mb_feature_api_key_scalar(NULL), "")
  testthat::expect_identical(env$.mb_feature_api_key_scalar(NA), "")
})

testthat::test_that(".mb_feature_api_key_scalar değeri trimler ve ilk elemanı alır", {
  env <- .source_into_env("R/helpers_feature_api_key.R")
  testthat::expect_identical(env$.mb_feature_api_key_scalar("  sk-test-123 "), "sk-test-123")
  testthat::expect_identical(env$.mb_feature_api_key_scalar(c("ilk", "ikinci")), "ilk")
})

# --- .fm_context_chr ----------------------------------------------------------

testthat::test_that(".fm_context_chr boş/NA/NULL için default döndürür", {
  env <- .source_into_env("R/helpers_file_manager_context_policy.R")
  testthat::expect_identical(env$.fm_context_chr(NULL, default = "d"), "d")
  testthat::expect_identical(env$.fm_context_chr(NA, default = "d"), "d")
  testthat::expect_identical(env$.fm_context_chr("   ", default = "d"), "d")
})

testthat::test_that(".fm_context_chr geçerli değeri trimleyerek döndürür", {
  env <- .source_into_env("R/helpers_file_manager_context_policy.R")
  testthat::expect_identical(env$.fm_context_chr("  veri.xlsx "), "veri.xlsx")
})
