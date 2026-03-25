# Dosya Yolu: R/module_user_identity.R
# Açıklama: Kullanıcı kimlik bilgilerini yöneten modül.
#            SSO_ENABLED anahtarına göre iki modda çalışır:
#            - SSO aktif (TRUE): Keycloak token'ından kullanıcı bilgisi alır
#            - SSO kapalı (FALSE): Sistem kullanıcı adı + veritabanı sorgusu kullanır

#' Kullanıcı Kimlik Bilgilerini Al
#' @description SSO moduna göre kullanıcı kimlik bilgilerini çözümler.
#'   SSO aktif: sso_claims parametresinden Keycloak bilgilerini kullanır.
#'   SSO kapalı: Sistem kullanıcı adı + DB'den ad bilgisi alır.
#' @param sso_claims SSO kullanıcı bilgileri (SSO aktifken sso_state$user_claims)
#' @return Liste: username, first_name, full_name, sicil ve diğer SSO alanları
resolveUserIdentity <- function(sso_claims = NULL) {

  # ===========================================================================
  # MOD 1: SSO AKTİF (Keycloak)
  # ===========================================================================
  if (isTRUE(SSO_ENABLED) && !is.null(sso_claims)) {

    username   <- sso_claims$username %||% ""
    first_name <- sso_claims$first_name %||% ""
    full_name  <- sso_claims$full_name %||% ""
    sicil      <- sso_claims$sicil

    # İlk isim boşsa tam isimden çıkar
    if (!nzchar(first_name) && nzchar(full_name)) {
      first_name <- extractFirstName(full_name)
    }

    # Tam isim boşsa kullanıcı adını kullan
    if (!nzchar(full_name)) {
      full_name <- capitalizeFirst(username)
    }

    # İlk ismi düzelt (baş harfi büyük)
    if (nzchar(first_name)) {
      first_name <- capitalizeFirst(first_name)
    }

    log_info("SSO kimlik çözümleme: kullanıcı={username}, ad={full_name}, sicil={sicil %||% 'YOK'}")

    return(list(
      username        = username,
      first_name      = first_name,
      full_name       = full_name,
      sicil           = sicil,
      email           = sso_claims$email,
      last_name       = sso_claims$last_name,
      sektor          = sso_claims$sektor,
      department      = sso_claims$department,
      mudurluk        = sso_claims$mudurluk,
      masraf_yeri_kodu = sso_claims$masraf_yeri_kodu,
      auth_level      = sso_claims$yetki %||% "USER",
      keycloak_sid    = sso_claims$keycloak_sid,
      keycloak_sub    = sso_claims$keycloak_sub,
      auth_source     = "keycloak"
    ))
  }

  # ===========================================================================
  # MOD 2: YEREL GELİŞTİRME (SSO kapalı)
  # ===========================================================================
  system_username <- Sys.info()["user"]

  # Veritabanından kullanıcı tam adını al
  db_result <- tryCatch({
    conn_info <- get_connection()
    conn <- conn_info$conn
    on.exit(release_connection(conn_info))

    # DC01_user_base'den tam adı al
    query <- "SELECT KaynakAdi FROM DC01_user_base WHERE KullaniciAdi = ?"
    result <- dbGetQuery(conn, query, params = list(system_username))

    if (nrow(result) > 0 && nzchar(result$KaynakAdi[1])) {
      result$KaynakAdi[1]
    } else {
      # DB'de kayıt yoksa MB_Users tablosundan dene
      query2 <- "SELECT KaynakAdi FROM MB_Users WHERE KullaniciAdi = ?"
      result2 <- dbGetQuery(conn, query2, params = list(system_username))
      if (nrow(result2) > 0 && nzchar(result2$KaynakAdi[1])) {
        result2$KaynakAdi[1]
      } else {
        NULL
      }
    }
  }, error = function(e) {
    log_warn("Kullanıcı adı DB'den alınamadı: {e$message}")
    NULL
  })

  # Tam ad ve ilk isim belirle
  if (!is.null(db_result) && nzchar(db_result)) {
    full_name  <- db_result
    first_name <- extractFirstName(full_name)
  } else {
    full_name  <- capitalizeFirst(system_username)
    first_name <- full_name
  }

  list(
    username        = system_username,
    first_name      = first_name,
    full_name       = full_name,
    sicil           = NULL,
    email           = NULL,
    last_name       = NULL,
    sektor          = NULL,
    department      = NULL,
    mudurluk        = NULL,
    masraf_yeri_kodu = NULL,
    auth_level      = Sys.getenv("MERGEN_AUTH_LEVEL", "ADMIN"),
    keycloak_sid    = NULL,
    keycloak_sub    = NULL,
    auth_source     = "local"
  )
}


#' Türkçe Karakter Encoding Düzeltme
#' @description Keycloak'tan gelen bozuk UTF-8 Türkçe karakterleri düzeltir.
#'   Örnek: "KARADAĞ" bozuk gelirse düzeltir.
#' @param text Düzeltilecek metin
#' @return Düzeltilmiş metin
fixTurkishEncoding <- function(text) {
  if (is.null(text)) return(text)
  if (!length(text)) return(text)

  out <- tryCatch(enc2utf8(as.character(text)), error = function(e) as.character(text))
  tryCatch(iconv(out, from = "", to = "UTF-8", sub = ""), error = function(e) out)
}


#' İlk İsmi Çıkar
#' @description Tam isimden ilk ismi çıkarır ve baş harfi büyütür.
#' @param full_name Tam isim
#' @return İlk isim (baş harfi büyük, geri kalanı küçük)
extractFirstName <- function(full_name) {
  if (is.null(full_name) || !nzchar(full_name)) return("")

  parts <- strsplit(trimws(full_name), "\\s+")[[1]]
  first <- parts[1]
  capitalizeFirst(first)
}


#' Baş Harfi Büyült
#' @description Metnin baş harfini büyük, geri kalanını küçük yapar.
#' @param text Metin
#' @return Baş harfi büyük metin
capitalizeFirst <- function(text) {
  if (is.null(text) || !nzchar(text)) return("")

  text <- trimws(text)
  first_char <- substring(text, 1, 1)
  rest <- substring(text, 2)

  paste0(
    toupper(first_char),
    tolower(rest)
  )
}
