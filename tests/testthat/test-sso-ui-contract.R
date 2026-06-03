# ==============================================================================
# Dosya Yolu: tests/testthat/test-sso-ui-contract.R
# Açıklama: R/module_sso.R UI üreticilerinin DAVRANIŞSAL/YAPI testleri. Bu dosya
#           daha önce hiçbir test tarafından çağrılmıyordu.
#
#           ssoAuthUI(id): SSO kapalıysa boş div, açıksa kimlik-doğrulama overlay
#           ve Keycloak yapılandırma betiği üretir.
#           ssoPreflightScriptUI(): SSO kapalı/uç-nokta yoksa "enabled: false"
#           ön-kapı betiği, açıksa yönlendirme yapılandırmalı betik üretir.
#
#           SSO_ENABLED ve SSO_CONFIG globalleri izole ortamda set edilir; gerçek
#           Keycloak sunucusu GEREKMEZ.
# ==============================================================================

.source_sso_ui_for_test <- function(enabled, config = NULL) {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  env$SSO_ENABLED <- enabled
  env$SSO_CONFIG <- config %||% list(
    auth_endpoint   = "https://kc.ornek.local/auth",
    client_id       = "mergen-bilge",
    response_type   = "token",
    scope           = "openid",
    logout_endpoint = "https://kc.ornek.local/logout"
  )
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_sso.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# ------------------------------------------------------------------------------
# ssoAuthUI: SSO kapalı
# ------------------------------------------------------------------------------
testthat::test_that("ssoAuthUI SSO kapalıyken boş bir div döndürür", {
  env <- .source_sso_ui_for_test(enabled = FALSE)
  ui <- env$ssoAuthUI("sso")
  html <- paste(as.character(ui), collapse = "")
  # Overlay/yükleme metni içermemeli.
  testthat::expect_false(grepl("Kimlik Doğrulanıyor", html, fixed = TRUE))
  testthat::expect_false(grepl("sso-auth-overlay", html, fixed = TRUE))
  # Boş div: <div></div> civarı, anlamlı içerik yok.
  testthat::expect_lt(nchar(html), 40L)
})

# ------------------------------------------------------------------------------
# ssoAuthUI: SSO açık
# ------------------------------------------------------------------------------
testthat::test_that("ssoAuthUI SSO açıkken overlay, yükleme ve hata durumlarını üretir", {
  env <- .source_sso_ui_for_test(enabled = TRUE)
  html <- paste(as.character(env$ssoAuthUI("sso")), collapse = "\n")

  testthat::expect_true(grepl("sso-auth-overlay", html, fixed = TRUE))
  testthat::expect_true(grepl("Kimlik Doğrulanıyor...", html, fixed = TRUE))
  testthat::expect_true(grepl("Keycloak sunucusuna yönlendiriliyorsunuz.", html, fixed = TRUE))
  testthat::expect_true(grepl("Erişim Reddedildi", html, fixed = TRUE))
  testthat::expect_true(grepl("Tekrar Dene", html, fixed = TRUE))
  # Ad alanlı elemanlar.
  testthat::expect_true(grepl("sso-sso_overlay", html, fixed = TRUE))
  testthat::expect_true(grepl("sso-sso_loading", html, fixed = TRUE))
})

testthat::test_that("ssoAuthUI Keycloak yapılandırmasını JSON betiğine gömer", {
  env <- .source_sso_ui_for_test(enabled = TRUE)
  html <- paste(as.character(env$ssoAuthUI("sso")), collapse = "\n")
  # Yapılandırma JSON'unda client_id ve auth_endpoint yer almalı.
  testthat::expect_true(grepl("mergen-bilge", html, fixed = TRUE))
  testthat::expect_true(grepl("kc.ornek.local/auth", html, fixed = TRUE))
  testthat::expect_true(grepl("\"enabled\":true", html, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# ssoPreflightScriptUI
# ------------------------------------------------------------------------------
testthat::test_that("ssoPreflightScriptUI SSO kapalıyken devre dışı ön-kapı betiği üretir", {
  env <- .source_sso_ui_for_test(enabled = FALSE)
  html <- paste(as.character(env$ssoPreflightScriptUI()), collapse = "\n")
  testthat::expect_true(grepl("enabled: false", html, fixed = TRUE))
  testthat::expect_true(grepl("__mergenSsoPreflight", html, fixed = TRUE))
})

testthat::test_that("ssoPreflightScriptUI uç nokta boşsa devre dışı betiğe düşer", {
  env <- .source_sso_ui_for_test(enabled = TRUE, config = list(
    auth_endpoint = "", client_id = "x", response_type = "token", scope = "openid"
  ))
  html <- paste(as.character(env$ssoPreflightScriptUI()), collapse = "\n")
  testthat::expect_true(grepl("enabled: false", html, fixed = TRUE))
})

testthat::test_that("ssoPreflightScriptUI SSO açıkken yönlendirme yapılandırmalı betik üretir", {
  env <- .source_sso_ui_for_test(enabled = TRUE)
  html <- paste(as.character(env$ssoPreflightScriptUI()), collapse = "\n")
  # Etkin ön-kapı: client_id ve auth_endpoint config'i gömülmeli.
  testthat::expect_true(grepl("mergen-bilge", html, fixed = TRUE))
  testthat::expect_true(grepl("kc.ornek.local/auth", html, fixed = TRUE))
  testthat::expect_true(grepl("__mergenSsoPreflight", html, fixed = TRUE))
  # extractTokenFromHash gibi yönlendirme yardımcıları yer almalı.
  testthat::expect_true(grepl("extractTokenFromHash", html, fixed = TRUE))
})
