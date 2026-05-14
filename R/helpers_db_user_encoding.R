# ==============================================================================
# Dosya Yolu: R/helpers_db_user_encoding.R
# Açıklama: MB_Users / SSO DB yazım sınırında kullanıcıya görünen metinler ile
#           teknik claim alanlarını ayrı normalize eden küçük yardımcılar.
# ==============================================================================

normalize_sso_claims_for_db <- function(sso_claims) {
  if (is.null(sso_claims) || !is.list(sso_claims)) return(sso_claims)

  visible_fields <- c(
    "full_name",
    "first_name",
    "last_name",
    "sektor",
    "department",
    "mudurluk"
  )

  technical_fields <- c(
    "username",
    "email",
    "sicil",
    "masraf_yeri_kodu",
    "keycloak_sid",
    "keycloak_sub",
    "yetki",
    "token_exp",
    "token_iat"
  )

  for (field_name in intersect(visible_fields, names(sso_claims))) {
    sso_claims[[field_name]] <- normalize_db_visible_value(sso_claims[[field_name]])
  }

  for (field_name in intersect(technical_fields, names(sso_claims))) {
    sso_claims[[field_name]] <- normalize_db_technical_value(sso_claims[[field_name]])
  }

  sso_claims
}