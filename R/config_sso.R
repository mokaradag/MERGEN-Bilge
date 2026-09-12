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
# Toleranslı ayrıştırma (TRUE/1/yes/on, FALSE/0/no/off); tanınmayan değerde
# KAPALI-BAŞARISIZ: kimlik doğrulama modu belirsizken sessizce yerel moda
# düşülmez, açılış durdurulur. Açıkça boş bırakılan SSO_ENABLED= de geçersizdir;
# aksi hâlde yerel mod (varsayılan ADMIN yetkisi) sessizce açılırdı. Windows
# boş değeri değişkeni silerek sakladığı için (?Sys.setenv) orada bu durum
# tanımsız değişkenle aynıdır ve belgelenen FALSE varsayılanına düşer.
.sso_enabled_raw <- trimws(Sys.getenv("SSO_ENABLED", "FALSE"))
.sso_enabled_key <- chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", .sso_enabled_raw)
SSO_ENABLED <- if (.sso_enabled_key %in% c("true", "t", "1", "yes", "on")) {
  TRUE
} else if (.sso_enabled_key %in% c("false", "f", "0", "no", "off")) {
  FALSE
} else {
  NA
}
if (is.na(SSO_ENABLED)) {
  stop(sprintf(
    "SSO_ENABLED ortam değişkeni geçersiz ('%s'). Kimlik doğrulama modu belirsizken uygulama başlatılmaz; TRUE veya FALSE verin.",
    .sso_enabled_raw
  ), call. = FALSE)
}
rm(.sso_enabled_raw, .sso_enabled_key)

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

  # JWT imza (signature) doğrulaması. Varsayılan AÇIK (güvenli varsayılan):
  # token'ın gerçekten Keycloak tarafından imzalandığı JWKS genel anahtarı ile
  # kriptografik olarak doğrulanır. JWKS uygulama sunucusundan erişilemiyorsa
  # operatör SSO_VALIDATE_SIGNATURE=FALSE ile geçici olarak kapatabilir.
  validate_signature = as.logical(Sys.getenv("SSO_VALIDATE_SIGNATURE", "TRUE")),

  # JWKS uç noktası override'ı (boşsa issuer'dan türetilir).
  jwks_url            = Sys.getenv("SSO_JWKS_URL", ""),

  # JWKS önbellek ömrü (saniye). Anahtarlar bu süre boyunca yeniden alınmaz;
  # bilinmeyen kid (anahtar rotasyonu) durumunda süreye bakılmaksızın yenilenir.
  jwks_cache_ttl_secs = as.integer(Sys.getenv("SSO_JWKS_CACHE_TTL", "3600")),

  # Oturum yönetimi
  token_refresh_margin_secs = as.integer(Sys.getenv("SSO_TOKEN_REFRESH_MARGIN", "300")),

  # Geliştirme ve hata ayıklama
  debug_mode        = as.logical(Sys.getenv("SSO_DEBUG", "FALSE"))
)

# NA güvenlik düzeltmeleri
if (is.na(SSO_CONFIG$validate_issuer)) SSO_CONFIG$validate_issuer <- TRUE
if (is.na(SSO_CONFIG$validate_expiry)) SSO_CONFIG$validate_expiry <- TRUE
if (is.na(SSO_CONFIG$validate_signature)) SSO_CONFIG$validate_signature <- TRUE
if (is.na(SSO_CONFIG$debug_mode))      SSO_CONFIG$debug_mode <- FALSE
if (is.na(SSO_CONFIG$token_refresh_margin_secs)) SSO_CONFIG$token_refresh_margin_secs <- 300L
if (is.na(SSO_CONFIG$jwks_cache_ttl_secs)) SSO_CONFIG$jwks_cache_ttl_secs <- 3600L

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
  # JWKS (genel imza anahtarları) uç noktası. Override verilmemişse issuer'dan türetilir.
  SSO_CONFIG$jwks_endpoint   <- if (nzchar(SSO_CONFIG$jwks_url)) {
    SSO_CONFIG$jwks_url
  } else {
    paste0(issuer_base, "/protocol/openid-connect/certs")
  }
} else if (isTRUE(SSO_ENABLED)) {
  # Issuer türetilemezse token doğrulaması sessizce zayıflar; KAPALI-BAŞARISIZ.
  stop("SSO_ENABLED=TRUE ancak SSO_KEYCLOAK_URL tanımlanmamış; Keycloak issuer doğrulaması yapılamayacağı için uygulama başlatılmaz.", call. = FALSE)
}

# Issuer türetilemese bile açık bir JWKS override verilmişse onu kullan.
.sso_jwks_ep <- SSO_CONFIG$jwks_endpoint
if (is.null(.sso_jwks_ep) || length(.sso_jwks_ep) == 0 || !nzchar(.sso_jwks_ep)) {
  if (nzchar(SSO_CONFIG$jwks_url)) {
    SSO_CONFIG$jwks_endpoint <- SSO_CONFIG$jwks_url
  }
}
rm(.sso_jwks_ep)

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
  log_info("SSO JWKS Endpoint: {SSO_CONFIG$jwks_endpoint %||% 'YOK'}")
  log_info("SSO İmza doğrulaması: {if (isTRUE(SSO_CONFIG$validate_signature)) 'AÇIK' else 'KAPALI'}")
  log_info("SSO Realm: {SSO_CONFIG$realm}")
  log_info("SSO Client ID: {SSO_CONFIG$client_id}")
} else {
  log_info("SSO modu KAPALI - Yerel geliştirme modu kullanılacak (sistem kullanıcı adı)")
}