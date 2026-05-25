# ============================================================
# Başlık: Çıkış (Logout) URL Yardımcısı
# Dosya: R/helpers_logout_url.R
# Açıklama: Sidebar çıkış (logout) butonu için tek doğru kaynak. URL
#           öncelik sırası:
#             1. MERGEN_LOGOUT_URL (.Renviron / sistem ortamı)
#             2. SSO_LOGOUT_URL (geriye dönük destek)
#             3. KEYCLOAK_LOGOUT_URL (geriye dönük destek)
#             4. SSO aktifse SSO_CONFIG$logout_endpoint (türetilmiş)
#
#           Bu yardımcı:
#             - URL döner ya da uygun değilse boş dize döner;
#             - boş dönüş çıkış butonunun sidebar üzerinde
#               GÖSTERİLMEMESİ anlamına gelir (yerel modda kırık
#               buton sergilememek için);
#             - URL şeması yalnızca http:// veya https:// olmalı;
#             - JavaScript scheme'leri kasıtlı olarak reddedilir
#               (XSS önlemesi).
#
# Not: Bu helper kendi başına SSO modunu değiştirmez; yalnızca URL
#       sağlar. window.ssoLogout (sso_auth.js) hâlâ SSO içeren
#       gerçek çıkış akışını sürdürür; bu URL ise SSO yokken veya
#       özel bir kurumsal çıkış sayfası varsa kullanılır.
# ============================================================

#' Güvenli logout URL doğrulama
#'
#' @description URL'nin http(s) şemasında olduğunu, boş olmadığını ve
#'   javascript:/data:/vbscript:/file: gibi tehlikeli şemalar
#'   içermediğini doğrular. Geçersizse boş dize döner.
#'
#' @param url Karakter (NULL/NA olabilir)
#' @return Geçerli URL ya da boş dize
mergen_validate_logout_url <- function(url) {
  if (is.null(url)) return("")
  url <- as.character(url)[1]
  if (is.na(url)) return("")
  url <- trimws(url)
  if (!nzchar(url)) return("")

  # Yalnızca http(s) (kuruluş içi mutlak ya da düzgün relatif olabilir)
  lower <- tolower(url)
  forbidden_schemes <- c("javascript:", "data:", "vbscript:", "file:")
  for (s in forbidden_schemes) {
    if (startsWith(lower, s)) {
      return("")
    }
  }

  # Mutlak şema yoksa app içi göreli yola izin verilir (örn. "/sso/logout")
  if (grepl("^https?://", lower, perl = TRUE)) {
    return(url)
  }

  if (startsWith(url, "/")) {
    # Göreli kök yol - kabul
    return(url)
  }

  # Diğer durumlar reddedilir
  ""
}

#' Yapılandırılmış logout URL'sini çöz
#'
#' @description .Renviron sırasıyla MERGEN_LOGOUT_URL, SSO_LOGOUT_URL,
#'   KEYCLOAK_LOGOUT_URL ortam değişkenlerini denedikten sonra SSO
#'   aktifse SSO_CONFIG$logout_endpoint değerine düşer.
#'
#'   Üretim ortamında kullanıcı butonu yalnızca bir geçerli URL
#'   döndüğünde gösterilmelidir.
#'
#' @param sso_enabled Mantıksal; SSO etkin mi? (NULL ise SSO_ENABLED'dan okur)
#' @return Karakter (boş olabilir)
mergen_resolve_logout_url <- function(sso_enabled = NULL) {
  # 1) Birincil ortam değişkeni
  env_keys <- c("MERGEN_LOGOUT_URL", "SSO_LOGOUT_URL", "KEYCLOAK_LOGOUT_URL")
  for (k in env_keys) {
    raw <- Sys.getenv(k, "")
    validated <- mergen_validate_logout_url(raw)
    if (nzchar(validated)) {
      return(validated)
    }
  }

  # 2) SSO modu açıksa türetilmiş logout endpoint
  effective_sso <- if (is.null(sso_enabled)) {
    tryCatch(
      isTRUE(get("SSO_ENABLED", inherits = TRUE)),
      error = function(e) FALSE
    )
  } else {
    isTRUE(sso_enabled)
  }

  if (isTRUE(effective_sso)) {
    cfg <- tryCatch(
      get("SSO_CONFIG", inherits = TRUE),
      error = function(e) NULL
    )
    ep <- if (is.list(cfg)) cfg$logout_endpoint else NULL
    validated <- mergen_validate_logout_url(ep)
    if (nzchar(validated)) {
      return(validated)
    }
  }

  ""
}

#' Sidebar çıkış butonu için uygun durumu döndür
#'
#' @description Çıkış butonu gösterilmeli mi karar verirken kullanılır.
#'   URL boş ya da geçersizse buton gizlenir.
#'
#' @param sso_enabled Mantıksal
#' @return Mantıksal
mergen_logout_button_available <- function(sso_enabled = NULL) {
  nzchar(mergen_resolve_logout_url(sso_enabled = sso_enabled))
}
