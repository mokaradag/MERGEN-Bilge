# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-user-guard-behavior.R
# Açıklama: R/helpers_claude_code_user_guard.R içindeki saf yapı-taşı
#           yardımcılarının DAVRANIŞSAL testleri. Mevcut
#           test-claude-code-user-guard-contract.R üst seviye
#           cc_require_ready_user_id'i kapsar; alttaki üç yapı taşı doğrudan
#           çağrılarak test edilmiyordu:
#             - cc_normalize_ready_user_id (placeholder/geçersiz kimlik -> 0L)
#             - cc_auth_is_ready (SSO kapalı -> her zaman hazır; SSO açık -> kimlik)
#             - cc_resolve_effective_user_id (oturum/fallback/canlı sağlayıcı)
#           Güvenlik sözleşmesi: SSO açıkken kimlik hazır değilse hazır SAYILMAZ;
#           geçersiz/placeholder kullanıcı kimlikleri 0L'e indirgenir.
#           Shiny/DB/SSO sunucusu/ağ GEREKMEZ; sentetik environment oturumları.
# ==============================================================================

.ccguard_source_once <- function() {
  root <- resolve_repo_root_for_tests()

  # cc_resolve_effective_user_id, resolve_effective_user_id'e delege eder.
  if (!exists("resolve_effective_user_id", envir = globalenv(),
              mode = "function", inherits = TRUE)) {
    source(
      file.path(root, "R", "utils_common.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }

  if (!exists("cc_auth_is_ready", envir = globalenv(),
              mode = "function", inherits = TRUE)) {
    source(
      file.path(root, "R", "helpers_claude_code_user_guard.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  invisible(TRUE)
}

# environment tabanlı userData ile sahte oturum.
.ccguard_session <- function(...) {
  ud <- new.env(parent = emptyenv())
  vals <- list(...)
  for (nm in names(vals)) assign(nm, vals[[nm]], envir = ud)
  list(userData = ud)
}

# ------------------------------------------------------------------------------
# cc_normalize_ready_user_id
# ------------------------------------------------------------------------------
testthat::test_that("cc_normalize_ready_user_id geçerli pozitif kimliği integer döndürür", {
  .ccguard_source_once()
  testthat::expect_identical(cc_normalize_ready_user_id(42L), 42L)
  testthat::expect_identical(cc_normalize_ready_user_id("5"), 5L)
  # Vektör verilirse ilk öğe kullanılır
  testthat::expect_identical(cc_normalize_ready_user_id(c(7L, 9L)), 7L)
})

testthat::test_that("cc_normalize_ready_user_id placeholder/geçersiz kimliği 0L'e indirger", {
  .ccguard_source_once()
  testthat::expect_identical(cc_normalize_ready_user_id(NULL), 0L)
  testthat::expect_identical(cc_normalize_ready_user_id(integer(0)), 0L)
  testthat::expect_identical(cc_normalize_ready_user_id(0L), 0L)
  testthat::expect_identical(cc_normalize_ready_user_id(-3L), 0L)
  testthat::expect_identical(cc_normalize_ready_user_id(NA), 0L)
  testthat::expect_identical(cc_normalize_ready_user_id("abc"), 0L)
})

# ------------------------------------------------------------------------------
# cc_auth_is_ready
# ------------------------------------------------------------------------------
testthat::test_that("cc_auth_is_ready SSO kapalıyken her zaman TRUE döner", {
  .ccguard_source_once()
  testthat::expect_true(cc_auth_is_ready(NULL, sso_enabled = FALSE))
  # SSO bayrağı varsayılan FALSE
  testthat::expect_true(cc_auth_is_ready(NULL))
  # Oturum olsa bile SSO kapalıysa hazır sayılır
  testthat::expect_true(cc_auth_is_ready(.ccguard_session(auth_initialized = FALSE), sso_enabled = FALSE))
})

testthat::test_that("cc_auth_is_ready SSO açıkken yalnızca auth_initialized TRUE iken hazırdır", {
  .ccguard_source_once()
  # Oturum/userData yokken hazır değil
  testthat::expect_false(cc_auth_is_ready(NULL, sso_enabled = TRUE))
  testthat::expect_false(cc_auth_is_ready(list(userData = NULL), sso_enabled = TRUE))

  # auth_initialized TRUE -> hazır
  testthat::expect_true(
    cc_auth_is_ready(.ccguard_session(auth_initialized = TRUE), sso_enabled = TRUE)
  )
  # auth_initialized FALSE veya eksik -> hazır değil
  testthat::expect_false(
    cc_auth_is_ready(.ccguard_session(auth_initialized = FALSE), sso_enabled = TRUE)
  )
  testthat::expect_false(
    cc_auth_is_ready(.ccguard_session(), sso_enabled = TRUE)
  )
})

# ------------------------------------------------------------------------------
# cc_resolve_effective_user_id
# ------------------------------------------------------------------------------
testthat::test_that("cc_resolve_effective_user_id oturum kimliğini önceler", {
  .ccguard_source_once()
  s <- .ccguard_session(user_id = 42L)
  testthat::expect_identical(cc_resolve_effective_user_id(s, NULL), 42L)
  # Oturum kimliği geçerliyken fallback yok sayılır
  testthat::expect_identical(cc_resolve_effective_user_id(s, 99L), 42L)
})

testthat::test_that("cc_resolve_effective_user_id oturum geçersizken fallback ve canlı sağlayıcıya düşer", {
  .ccguard_source_once()
  s0 <- .ccguard_session(user_id = 0L)
  # Düz fallback değeri
  testthat::expect_identical(cc_resolve_effective_user_id(s0, 7L), 7L)
  # Canlı sağlayıcı fonksiyonu çözülür
  testthat::expect_identical(cc_resolve_effective_user_id(s0, function() 9L), 9L)
  # Hiçbir kaynak yoksa 0L
  testthat::expect_identical(cc_resolve_effective_user_id(NULL, NULL), 0L)
})
