# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-api-key-runtime-behavior.R
# Açıklama: R/helpers_claude_code_api_key.R içindeki Bilge Yolaç çalışma zamanı
#           API anahtarı yardımcılarının DAVRANIŞSAL testleri. Bu fonksiyonlar
#           doğrudan çağrılarak test edilmiyordu:
#             - cc_resolve_runtime_api_key (kişisel anahtarı çözer; yoksa/auth
#               hazır değilse ok=FALSE + kullanıcı mesajı)
#             - cc_apply_runtime_api_key_env (anahtarı yalnızca ANTHROPIC_AUTH_TOKEN
#               ortam değişkeni olarak verir; boş/NA/NULL'da değişiklik yok)
#           Güvenlik sözleşmesi: anahtar dosyaya yazılmaz, yalnızca süreç ortamına
#           geçer; kişisel anahtar sahibi eşleşmeli ve kimlik hazır olmalıdır.
#           Shiny/DB/ağ GEREKMEZ; sentetik environment oturumları kullanılır.
# ==============================================================================

.cckey_source_once <- function() {
  root <- resolve_repo_root_for_tests()
  if (!exists("mb_api_key_get_effective_key", envir = globalenv(),
              mode = "function", inherits = TRUE)) {
    source(
      file.path(root, "R", "helpers_api_key_identity.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  if (!exists("cc_resolve_runtime_api_key", envir = globalenv(),
              mode = "function", inherits = TRUE)) {
    source(
      file.path(root, "R", "helpers_claude_code_api_key.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  invisible(TRUE)
}

# environment tabanlı userData ile sahte oturum (helper'lar exists/get/rm kullanır).
.cckey_session <- function(...) {
  ud <- new.env(parent = emptyenv())
  vals <- list(...)
  for (nm in names(vals)) assign(nm, vals[[nm]], envir = ud)
  list(userData = ud)
}

# ------------------------------------------------------------------------------
# cc_apply_runtime_api_key_env
# ------------------------------------------------------------------------------
testthat::test_that("cc_apply_runtime_api_key_env anahtarı ANTHROPIC_AUTH_TOKEN olarak yazar ve diğerlerini korur", {
  .cckey_source_once()
  env <- list(FOO = "bar")
  out <- cc_apply_runtime_api_key_env(env, "secret-fake-123")
  testthat::expect_identical(out[["ANTHROPIC_AUTH_TOKEN"]], "secret-fake-123")
  testthat::expect_identical(out[["FOO"]], "bar")
})

testthat::test_that("cc_apply_runtime_api_key_env boş/NA/NULL anahtarda ortamı değiştirmez", {
  .cckey_source_once()
  env <- list(FOO = "bar")
  testthat::expect_identical(cc_apply_runtime_api_key_env(env, ""), env)
  testthat::expect_identical(cc_apply_runtime_api_key_env(env, NA), env)
  testthat::expect_identical(cc_apply_runtime_api_key_env(env, NULL), env)
  # Token anahtarı eklenmemiş olmalı
  testthat::expect_null(cc_apply_runtime_api_key_env(env, "")[["ANTHROPIC_AUTH_TOKEN"]])
})

testthat::test_that("cc_apply_runtime_api_key_env env NULL ise Sys.getenv'den başlar ve token ekler", {
  .cckey_source_once()
  out <- cc_apply_runtime_api_key_env(NULL, "k-fake")
  testthat::expect_identical(out[["ANTHROPIC_AUTH_TOKEN"]], "k-fake")
  # Sys.getenv() isimli bir karakter vektörü döndürür
  testthat::expect_true(!is.null(names(out)))
  testthat::expect_true(length(out) > 1L)
})

# ------------------------------------------------------------------------------
# cc_resolve_runtime_api_key
# ------------------------------------------------------------------------------
testthat::test_that("cc_resolve_runtime_api_key sahibi eşleşen kişisel anahtarı çözer", {
  .cckey_source_once()
  sess <- .cckey_session(
    auth_initialized = TRUE,
    system_username = "alice",
    ai_api_key = "kisisel-fake",
    ai_api_key_owner = "alice"
  )
  out <- cc_resolve_runtime_api_key(sess)
  testthat::expect_true(out$ok)
  testthat::expect_identical(out$key, "kisisel-fake")
  testthat::expect_identical(out$source, "personal")
  testthat::expect_identical(out$message, "")
})

testthat::test_that("cc_resolve_runtime_api_key anahtar yoksa ok=FALSE ve kullanıcı mesajı döner", {
  .cckey_source_once()
  # Varsayılan kurum anahtarı yapılandırılmamış olsun ki sonuç deterministik kalsın.
  withr::local_envvar(MERGEN_DEFAULT_API_KEY = NA)
  sess <- .cckey_session(auth_initialized = TRUE, system_username = "bob")
  out <- cc_resolve_runtime_api_key(sess)
  testthat::expect_false(out$ok)
  testthat::expect_identical(out$key, "")
  testthat::expect_identical(out$source, "missing")
  testthat::expect_true(nzchar(out$message))
  testthat::expect_match(out$message, "API anahtar", fixed = TRUE)
})

testthat::test_that("cc_resolve_runtime_api_key kimlik hazır değilken anahtarı sızdırmaz", {
  .cckey_source_once()
  withr::local_envvar(MERGEN_DEFAULT_API_KEY = NA)
  # auth_initialized FALSE: require_auth=TRUE olduğu için depolanmış kişisel
  # anahtar bağlanmaz.
  sess <- .cckey_session(
    auth_initialized = FALSE,
    system_username = "alice",
    ai_api_key = "kisisel-fake",
    ai_api_key_owner = "alice"
  )
  out <- cc_resolve_runtime_api_key(sess)
  testthat::expect_false(out$ok)
  testthat::expect_identical(out$key, "")
  testthat::expect_identical(out$source, "missing")
})
