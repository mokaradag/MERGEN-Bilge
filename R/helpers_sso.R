# Dosya Yolu: R/helpers_sso.R
# Açıklama: SSO (Tek Oturum Açma) yardımcı fonksiyonları.
#            JWT token çözümleme, doğrulama ve Keycloak claim işleme.

# ==============================================================================
# JWT TOKEN ÇÖZÜMLEME
# ==============================================================================

#' JWT Token Payload Çözümleme
#' @description JWT token'ın payload (gövde) kısmını Base64 ile çözer ve JSON olarak ayrıştırır.
#'   Token formatı: header.payload.signature (3 parça, nokta ile ayrılmış)
#' @param token JWT token dizesi
#' @return Liste olarak çözümlenmiş payload veya hata durumunda NULL
decode_jwt_payload <- function(token) {
  tryCatch({
    if (is.null(token) || !nzchar(token)) {
      log_warn("JWT token boş veya NULL")
      return(NULL)
    }

    # Token'ı 3 parçaya ayır
    parts <- strsplit(token, "\\.")[[1]]
    if (length(parts) != 3) {
      log_warn("JWT token formatı geçersiz: {length(parts)} parça bulundu (3 olmalı)")
      return(NULL)
    }

    # Payload kısmını al (2. parça)
    payload_b64 <- parts[2]

    # URL-safe Base64'ü standart Base64'e dönüştür
    payload_b64 <- gsub("-", "+", payload_b64, fixed = TRUE)
    payload_b64 <- gsub("_", "/", payload_b64, fixed = TRUE)

    # Base64 padding ekle (4'ün katı olmalı)
    padding_needed <- (4 - nchar(payload_b64) %% 4) %% 4
    if (padding_needed > 0) {
      payload_b64 <- paste0(payload_b64, paste(rep("=", padding_needed), collapse = ""))
    }

    # Base64 çöz ve JSON olarak ayrıştır
    raw_bytes <- base64enc::base64decode(payload_b64)
    json_str <- rawToChar(raw_bytes)
    Encoding(json_str) <- "UTF-8"

    payload <- jsonlite::fromJSON(json_str, simplifyVector = FALSE)

    if (isTRUE(SSO_CONFIG$debug_mode)) {
      log_info("JWT payload başarıyla çözümlendi. Alanlar: {paste(names(payload), collapse=', ')}")
    }

    return(payload)

  }, error = function(e) {
    log_error("JWT token çözümleme hatası: {e$message}")
    return(NULL)
  })
}


# ==============================================================================
# TOKEN DOĞRULAMA
# ==============================================================================

#' JWT Token Doğrulama
#' @description Token'ın geçerliliğini kontrol eder:
#'   1. Payload çözümlenebilir mi?
#'   2. Gerekli alanlar mevcut mu? (preferred_username zorunlu)
#'   3. Issuer (iss) doğru mu? (yapılandırmada aktifse)
#'   4. Token süresi dolmuş mu? (yapılandırmada aktifse)
#' @param token JWT token dizesi
#' @return Liste: list(valid = TRUE/FALSE, payload = ..., error = ...)
validate_jwt_token <- function(token) {
  # 1. Payload çözümle
  payload <- decode_jwt_payload(token)
  if (is.null(payload)) {
    return(list(valid = FALSE, payload = NULL, error = "Token çözümlenemedi"))
  }

  # 2. İmza (signature) doğrulaması.
  #    GÜVENLİK: İmza, issuer/exp gibi claim'lerden ÖNCE doğrulanır. Token
  #    gerçekten Keycloak tarafından imzalanmadıysa payload alanlarına
  #    güvenilemez. Doğrulama SSO_CONFIG$validate_signature ile yönetilir ve
  #    açıkken fail-closed davranır (anahtar/imza doğrulanamazsa token reddedilir).
  sig_result <- sso_validate_jwt_signature(token)
  if (!isTRUE(sig_result$valid)) {
    return(list(
      valid = FALSE,
      payload = payload,
      error = sig_result$error %||% "Token imzası doğrulanamadı"
    ))
  }

  # 3. Zorunlu alan kontrolü: preferred_username
  username <- payload[[SSO_CLAIM_MAP$username]]
  if (is.null(username) || !nzchar(username)) {
    return(list(valid = FALSE, payload = payload, error = "Token'da kullanıcı adı (preferred_username) bulunamadı"))
  }

  # 4. Issuer doğrulaması
  if (isTRUE(SSO_CONFIG$validate_issuer) && nzchar(SSO_CONFIG$issuer_url %||% "")) {
    token_issuer <- payload[["iss"]]
    if (is.null(token_issuer) || !identical(token_issuer, SSO_CONFIG$issuer_url)) {
      log_warn("JWT issuer uyuşmazlığı: beklenen={SSO_CONFIG$issuer_url}, gelen={token_issuer %||% 'BOŞ'}")
      return(list(valid = FALSE, payload = payload, error = "Token kaynağı (issuer) doğrulanamadı"))
    }
  }

  # 5. Süre dolum kontrolü
  if (isTRUE(SSO_CONFIG$validate_expiry)) {
    exp_time <- payload[["exp"]]
    if (!is.null(exp_time)) {
      current_time <- as.numeric(Sys.time())
      if (current_time > exp_time) {
        log_warn("JWT token süresi dolmuş: exp={exp_time}, şimdi={current_time}")
        return(list(valid = FALSE, payload = payload, error = "Token süresi dolmuş. Lütfen sayfayı yenileyiniz."))
      }
    }
  }

  # Tüm doğrulamalar başarılı
  return(list(valid = TRUE, payload = payload, error = NULL))
}


# ==============================================================================
# KEYCLOAK CLAIM'LERİNDEN KULLANICI BİLGİSİ ÇIKARMA
# ==============================================================================

#' Keycloak Claims'ten Kullanıcı Bilgisi Çıkar
#' @description JWT payload'ından kullanıcı bilgilerini çıkarır ve
#'   Türkçe karakter düzeltmesi uygular.
#' @param payload JWT payload (çözümlenmiş liste)
#' @return Kullanıcı bilgilerini içeren liste
extract_user_claims <- function(payload) {
  if (is.null(payload)) {
    log_warn("extract_user_claims: payload NULL")
    return(NULL)
  }

  # Claim değerlerini güvenli şekilde al
  safe_claim <- function(field_name) {
    claim_key <- SSO_CLAIM_MAP[[field_name]]
    if (is.null(claim_key)) return(NULL)
    val <- payload[[claim_key]]
    if (is.null(val) || !nzchar(as.character(val))) return(NULL)
    tryCatch(enc2utf8(as.character(val)), error = function(e) as.character(val))
  }

  # Ham değerleri çıkar
  raw_username   <- safe_claim("username")
  raw_full_name  <- safe_claim("full_name")
  raw_first_name <- safe_claim("first_name")
  raw_last_name  <- safe_claim("last_name")
  raw_email      <- safe_claim("email")
  raw_sicil      <- safe_claim("sicil")
  raw_sektor     <- safe_claim("sektor")
  raw_department <- safe_claim("department")
  raw_mudurluk   <- safe_claim("mudurluk")
  raw_session_id <- safe_claim("session_id")
  raw_subject    <- safe_claim("subject")

  normalize_sso_visible_claim <- function(value) {
    value <- value %||% ""
    if (!nzchar(value)) return("")

    if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
      return(normalize_text_utf8(value, repair_mojibake = TRUE))
    }

    fixTurkishEncoding(value)
  }

  normalize_sso_technical_claim <- function(value) {
    value <- value %||% ""
    if (!nzchar(value)) return(value)

    if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
      return(normalize_text_utf8(value, repair_mojibake = FALSE))
    }

    enc2utf8(value)
  }

  # Kullanıcı adı teknik anahtardır; mojibake onarımı sadece görünen alanlara uygulanır.
  username <- tolower(normalize_sso_technical_claim(raw_username))

  # Türkçe görünen SSO alanlarını merkezi metin yardımcısıyla düzelt.
  full_name  <- normalize_sso_visible_claim(raw_full_name)
  first_name <- normalize_sso_visible_claim(raw_first_name)
  last_name  <- normalize_sso_visible_claim(raw_last_name)
  sektor     <- normalize_sso_visible_claim(raw_sektor)
  department <- normalize_sso_visible_claim(raw_department)
  mudurluk   <- normalize_sso_visible_claim(raw_mudurluk)

  # İlk isim yoksa tam isimden çıkar
  if (!nzchar(first_name) && nzchar(full_name)) {
    first_name <- extractFirstName(full_name)
  }

  list(
    username       = username,
    full_name      = full_name,
    first_name     = first_name,
    last_name      = last_name,
    email          = normalize_sso_technical_claim(raw_email),
    sicil          = normalize_sso_technical_claim(raw_sicil),
    sektor         = sektor,
    department     = department,
    mudurluk       = mudurluk,
    keycloak_sid   = normalize_sso_technical_claim(raw_session_id),
    keycloak_sub   = normalize_sso_technical_claim(raw_subject),
    # Token meta verileri
    token_exp      = payload[["exp"]],
    token_iat      = payload[["iat"]]
  )
}


# ==============================================================================
# SSO OTURUM KAPATMA URL'Sİ OLUŞTURMA
# ==============================================================================

#' Keycloak Oturum Kapatma URL'si Oluştur
#' @description Keycloak'tan tam oturum kapatma (Single Sign-Out) için
#'   yönlendirme URL'si oluşturur.
#' @param redirect_uri Çıkış sonrası yönlendirilecek adres (opsiyonel)
#' @return Keycloak çıkış URL'si
build_sso_logout_url <- function(redirect_uri = NULL) {
  if (!isTRUE(SSO_ENABLED) || is.null(SSO_CONFIG$logout_endpoint)) {
    return(NULL)
  }

  logout_url <- SSO_CONFIG$logout_endpoint
  params <- list(client_id = SSO_CONFIG$client_id)

  if (!is.null(redirect_uri) && nzchar(redirect_uri)) {
    params$post_logout_redirect_uri <- redirect_uri
  }

  param_str <- paste(
    vapply(names(params), function(k) {
      paste0(k, "=", utils::URLencode(params[[k]], reserved = TRUE))
    }, character(1)),
    collapse = "&"
  )

  paste0(logout_url, "?", param_str)
}


# ==============================================================================
# VERİTABANI YETKİLENDİRME KONTROLÜ
# ==============================================================================

#' Kullanıcı Yetki Seviyesini Veritabanından Al
#' @description DC01_user_base tablosundan kullanıcının yetki seviyesini sorgular.
#'   Keycloak ile giriş yapan kullanıcının uygulamaya erişim hakkını doğrular.
#'   Önce KullaniciAdi ile, bulunamazsa sicil (SicilNo) ile eşleşme dener.
#' @param username Keycloak'tan gelen preferred_username
#' @param sicil Keycloak'tan gelen sicil numarası (opsiyonel, yedek eşleşme için)
#' @return Liste: list(authorized = TRUE/FALSE, yetki = ..., masraf_yeri_kodu = ...)
check_user_authorization <- function(username, sicil = NULL) {
  if (is.null(username) || !nzchar(username)) {
    return(list(authorized = FALSE, yetki = NULL, masraf_yeri_kodu = NULL, kaynak_adi = NULL))
  }

  tryCatch({
    conn_info <- get_connection()
    conn <- conn_info$conn
    on.exit(release_connection(conn_info))

    # 1. Önce KullaniciAdi ile eşleştir (preferred_username -> KullaniciAdi)
    query <- "SELECT KaynakAdi, Yetki, MasrafYeriKodu, KullaniciAdi FROM DC01_user_base WHERE LOWER(KullaniciAdi) = LOWER(?)"
    result <- dbGetQuery(conn, query, params = list(username))

    log_info("SSO yetki sorgusu: preferred_username='{username}', bulunan={nrow(result)} kayıt")

    # 2. KullaniciAdi ile bulunamazsa sicil numarası ile dene
    if (nrow(result) == 0 && !is.null(sicil) && nzchar(sicil)) {
      log_info("SSO yetki: KullaniciAdi ile bulunamadı, sicil ile deneniyor: {sicil}")
      query_sicil <- "SELECT KaynakAdi, Yetki, MasrafYeriKodu, KullaniciAdi FROM DC01_user_base WHERE LOWER(KullaniciAdi) = LOWER(?)"
      result <- dbGetQuery(conn, query_sicil, params = list(sicil))
      log_info("SSO yetki sorgusu (sicil): bulunan={nrow(result)} kayıt")
    }

    if (nrow(result) > 0) {
		row <- result[1, ]

		kaynak_adi <- normalize_db_visible_value(row$KaynakAdi %||% "")
		yetki <- normalize_db_technical_value(row$Yetki %||% "USER")
		masraf_yeri_kodu <- normalize_db_technical_value(row$MasrafYeriKodu %||% "")

		log_info("SSO yetki: Kullanıcı bulundu - DB.KullaniciAdi='{row$KullaniciAdi}', Yetki='{yetki}'")
		list(
		  authorized       = TRUE,
		  yetki            = yetki,
		  masraf_yeri_kodu = masraf_yeri_kodu,
		  kaynak_adi       = kaynak_adi
		)
    } else {
      log_warn("Kullanıcı DC01_user_base tablosunda bulunamadı: username='{username}', sicil='{sicil %||% 'YOK'}'")
      list(authorized = FALSE, yetki = NULL, masraf_yeri_kodu = NULL, kaynak_adi = NULL)
    }
  }, error = function(e) {
    log_error("Yetkilendirme sorgusu hatası: {e$message}")
    # GÜVENLİK (fail-closed): Veritabanı hatasında yetki AÇILMAZ. Geçici bir DB
    # kesintisi veya sorgu hatası, yetkisiz erişime yol açmamalıdır. Önceki
    # davranış hata durumunda "USER" yetkisi veriyordu (fail-open); bu, DB
    # erişilemezken yetkisiz kullanıcıların geçmesine neden olabilirdi.
    list(authorized = FALSE, yetki = NULL, masraf_yeri_kodu = NULL, kaynak_adi = NULL)
  })
}