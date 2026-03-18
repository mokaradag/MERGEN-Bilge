# Dosya Yolu: R/config_sso.R
# Açıklama: SSO (Tek Oturum Açma) yapılandırması ve küresel mod anahtarı.
#            Keycloak entegrasyonu için gerekli tüm ayarları .Renviron'dan okur.
#            SSO_ENABLED=TRUE -> Keycloak modu (sanal makine), FALSE -> yerel geliştirme modu.

# ==============================================================================
# SSO KÜRESEL MOD ANAHTARI
# ==============================================================================
# Bu değişken uygulamanın kimlik doğrulama modunu belirler:
#   TRUE  -> Keycloak SSO aktif (sanal makine / üretim ortamı)
#   FALSE -> Yerel geliştirme modu (sistem kullanıcı adı ile çalışır)
SSO_ENABLED <- as.logical(Sys.getenv("SSO_ENABLED", "FALSE"))

# Güvenlik kontrolü: geçersiz değer durumunda FALSE olarak ayarla
if (is.na(SSO_ENABLED)) {
  SSO_ENABLED <- FALSE
  warning("SSO_ENABLED ortam değişkeni geçersiz. Yerel mod kullanılıyor.")
}

# ==============================================================================
# KEYCLOAK YAPILANDIRMASI
# ==============================================================================
SSO_CONFIG <- list(
  # Keycloak sunucu adresi ve realm bilgisi
  keycloak_base_url = Sys.getenv("SSO_KEYCLOAK_URL", ""),
  realm             = Sys.getenv("SSO_REALM", "byd_intranet_apps"),
  client_id         = Sys.getenv("SSO_CLIENT_ID", "mergen_bilge"),

  # OAuth 2.0 akış tipi
  response_type     = "token",
  scope             = "openid",

  # Token doğrulama ayarları
  validate_issuer   = as.logical(Sys.getenv("SSO_VALIDATE_ISSUER", "TRUE")),
  validate_expiry   = as.logical(Sys.getenv("SSO_VALIDATE_EXPIRY", "TRUE")),

  # Oturum yönetimi
  token_refresh_margin_secs = as.integer(Sys.getenv("SSO_TOKEN_REFRESH_MARGIN", "300")),

  # Geliştirme ve hata ayıklama
  debug_mode        = as.logical(Sys.getenv("SSO_DEBUG", "FALSE"))
)

# NA güvenlik düzeltmeleri
if (is.na(SSO_CONFIG$validate_issuer)) SSO_CONFIG$validate_issuer <- TRUE
if (is.na(SSO_CONFIG$validate_expiry)) SSO_CONFIG$validate_expiry <- TRUE
if (is.na(SSO_CONFIG$debug_mode))      SSO_CONFIG$debug_mode <- FALSE
if (is.na(SSO_CONFIG$token_refresh_margin_secs)) SSO_CONFIG$token_refresh_margin_secs <- 300L

# ==============================================================================
# KEYCLOAK URL'LERİ (TÜRETME)
# ==============================================================================
# Keycloak uç noktalarını otomatik olarak oluştur.
# SSO_KEYCLOAK_URL iki formatta kabul edilir:
#   1. Sadece sunucu URL'si: https://keycloak.example.com
#   2. Tam issuer URL'si:    https://keycloak.example.com/realms/my_realm
# Her iki durumda da doğru uç noktalar türetilir.
if (nzchar(SSO_CONFIG$keycloak_base_url)) {
  # URL'nin sonundaki eğik çizgiyi temizle
  keycloak_url_clean <- sub("/+$", "", SSO_CONFIG$keycloak_base_url)

  # URL zaten /realms/{realm} içeriyor mu kontrol et
  realm_suffix <- paste0("/realms/", SSO_CONFIG$realm)
  if (grepl(paste0(realm_suffix, "$"), keycloak_url_clean, fixed = FALSE)) {
    # SSO_KEYCLOAK_URL zaten issuer URL'si formatında (örn: .../realms/byd_intranet_apps)
    # Realm tekrar eklenmemeli - doğrudan issuer URL olarak kullan
    issuer_base <- keycloak_url_clean
  } else {
    # SSO_KEYCLOAK_URL sadece sunucu adresi (örn: https://keycloak.example.com)
    # Realm bilgisini ekle
    issuer_base <- paste0(keycloak_url_clean, "/realms/", SSO_CONFIG$realm)
  }

  SSO_CONFIG$issuer_url      <- issuer_base
  SSO_CONFIG$auth_endpoint   <- paste0(issuer_base, "/protocol/openid-connect/auth")
  SSO_CONFIG$logout_endpoint <- paste0(issuer_base, "/protocol/openid-connect/logout")
  SSO_CONFIG$token_endpoint  <- paste0(issuer_base, "/protocol/openid-connect/token")
} else if (isTRUE(SSO_ENABLED)) {
  warning("SSO_ENABLED=TRUE ancak SSO_KEYCLOAK_URL tanımlanmamış! Keycloak çalışmayacak.")
}

# ==============================================================================
# KEYCLOAK ALAN HARITALAMA (CLAIM MAPPING)
# ==============================================================================
# Keycloak JWT token'ından gelen alanların uygulama içi karşılıkları
SSO_CLAIM_MAP <- list(
  username       = "preferred_username",
  full_name      = "name",
  first_name     = "given_name",
  last_name      = "family_name",
  email          = "email",
  sicil          = "sicil",
  sektor         = "sektor",
  department     = "department",
  mudurluk       = "mudurluk",
  session_id     = "sid",
  subject        = "sub"
)

# ==============================================================================
# BAŞLATMA LOGU
# ==============================================================================
if (isTRUE(SSO_ENABLED)) {
  log_info("SSO modu AKTİF - Keycloak kimlik doğrulama kullanılacak")
  log_info("SSO Keycloak URL (girilen): {SSO_CONFIG$keycloak_base_url}")
  log_info("SSO Issuer URL (türetilen): {SSO_CONFIG$issuer_url}")
  log_info("SSO Auth Endpoint: {SSO_CONFIG$auth_endpoint}")
  log_info("SSO Realm: {SSO_CONFIG$realm}")
  log_info("SSO Client ID: {SSO_CONFIG$client_id}")
} else {
  log_info("SSO modu KAPALI - Yerel geliştirme modu kullanılacak (sistem kullanıcı adı)")
}