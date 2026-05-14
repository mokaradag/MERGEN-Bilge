# ==============================================================================
# Dosya Yolu: R/helpers_db_user_encoding.R
# Açıklama: MB_Users / SSO DB yazım sınırında kullanıcıya görünen metinler ile
#           teknik claim alanlarını ayrı normalize eden küçük yardımcılar.
# ==============================================================================

normalize_sso_claims_for_db <- function(sso_claims) {
  if (is.null(sso_claims) || !is.list(sso_claims)) return(sso_claims)

  visible_fields <- c("full_name", "first_name", "last_name", "sektor", "department", "mudurluk")
  technical_fields <- c(
    "username", "email", "sicil", "masraf_yeri_kodu",
    "keycloak_sid", "keycloak_sub", "yetki", "token_exp", "token_iat"
  )

  for (field_name in intersect(visible_fields, names(sso_claims))) {
    sso_claims[[field_name]] <- normalize_db_visible_value(sso_claims[[field_name]])
  }

  for (field_name in intersect(technical_fields, names(sso_claims))) {
    sso_claims[[field_name]] <- normalize_db_technical_value(sso_claims[[field_name]])
  }

  sso_claims
}

update_sso_fields <- function(conn, user_id, sso_claims) {
  sso_claims <- normalize_sso_claims_for_db(sso_claims)

  tryCatch({
    existing_cols <- dbGetQuery(
      conn,
      paste(
        "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS",
        "WHERE TABLE_NAME = 'MB_Users'",
        "AND COLUMN_NAME IN (",
        "'Sicil', 'Email', 'Sektor', 'Departman', 'Mudurluk',",
        "'MasrafYeriKodu', 'SonGirisKaynagi')"
      )
    )$COLUMN_NAME

    if (length(existing_cols) == 0) return(invisible(NULL))

    set_parts <- c()
    params <- list()

    if ("Sicil" %in% existing_cols && !is.null(sso_claims$sicil)) {
      set_parts <- c(set_parts, "Sicil = ?")
      params <- c(params, list(normalize_db_technical_value(sso_claims$sicil)))
    }
    if ("Email" %in% existing_cols && !is.null(sso_claims$email)) {
      set_parts <- c(set_parts, "Email = ?")
      params <- c(params, list(normalize_db_technical_value(sso_claims$email)))
    }
    if ("Sektor" %in% existing_cols && !is.null(sso_claims$sektor)) {
      set_parts <- c(set_parts, "Sektor = ?")
      params <- c(params, list(normalize_db_visible_value(sso_claims$sektor)))
    }
    if ("Departman" %in% existing_cols && !is.null(sso_claims$department)) {
      set_parts <- c(set_parts, "Departman = ?")
      params <- c(params, list(normalize_db_visible_value(sso_claims$department)))
    }
    if ("Mudurluk" %in% existing_cols && !is.null(sso_claims$mudurluk)) {
      set_parts <- c(set_parts, "Mudurluk = ?")
      params <- c(params, list(normalize_db_visible_value(sso_claims$mudurluk)))
    }
    if ("MasrafYeriKodu" %in% existing_cols && !is.null(sso_claims$masraf_yeri_kodu)) {
      set_parts <- c(set_parts, "MasrafYeriKodu = ?")
      params <- c(params, list(normalize_db_technical_value(sso_claims$masraf_yeri_kodu)))
    }
    if ("SonGirisKaynagi" %in% existing_cols) {
      set_parts <- c(set_parts, "SonGirisKaynagi = ?")
      params <- c(params, list(normalize_db_technical_value("keycloak")))
    }

    if (length(set_parts) > 0) {
      query <- paste0(
        "UPDATE MB_Users SET ",
        paste(set_parts, collapse = ", "),
        " WHERE UserID = ?"
      )
      dbExecute(conn, query, params = normalize_db_params(c(params, list(user_id))))
    }
  }, error = function(e) {
    log_warn("SSO alanları güncellenemedi (UserID={user_id}): {e$message}")
  })

  invisible(NULL)
}