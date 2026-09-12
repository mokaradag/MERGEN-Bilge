# ==============================================================================
# Dosya Yolu: tests/testthat/helper_load_sso.R
# Açıklama: SSO yardımcılarını (decode_jwt_payload, validate_jwt_token,
# extract_user_claims) testlere sunar. helper-load-app.R utils_common.R
# dosyasını zaten yüklemektedir.
# ==============================================================================

if (!exists("decode_jwt_payload", envir = globalenv(), inherits = FALSE) ||
    !exists("sso_validate_jwt_signature", envir = globalenv(), inherits = FALSE)) {
  required_pkgs <- c("base64enc", "jsonlite")
  for (pkg in required_pkgs) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf("Test ortamında '%s' paketi yüklü olmalıdır (helpers_sso.R gerektirir).", pkg))
    }
  }

  # SSO yapılandırması SSO_CONFIG ve SSO_CLAIM_MAP nesnelerini tanımlar.
  source(
    file.path(repo_root_for_tests, "R", "config_sso.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  # fixTurkishEncoding ve extractFirstName helpers_sso tarafından kullanılır.
  source(
    file.path(repo_root_for_tests, "R", "module_user_identity.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  # İmza doğrulama yardımcıları helpers_sso.R'den ÖNCE yüklenmeli;
  # validate_jwt_token() artık sso_validate_jwt_signature() çağırır.
  # JWKS önbelleği imza dosyasından önce gelir (çalışma zamanı manifest sırası).
  source(
    file.path(repo_root_for_tests, "R", "helpers_sso_jwks_cache.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  source(
    file.path(repo_root_for_tests, "R", "helpers_sso_signature.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  source(
    file.path(repo_root_for_tests, "R", "helpers_sso.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}