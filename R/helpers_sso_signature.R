# Dosya Yolu: R/helpers_sso_signature.R
# Açıklama: SSO JWT imza (signature) doğrulama yardımcıları.
#           Keycloak realm'inin JWKS uç noktasından genel anahtarları alır,
#           RS256/RS384/RS512 imzalarını openssl ile kriptografik olarak
#           doğrular. Yeni bağımlılık eklemez: yalnızca openssl, httr,
#           base64enc ve jsonlite kullanır (hepsi config_packages.R içinde
#           zorunlu paketlerdir).
#
# GÜVENLİK SÖZLEŞMESİ:
#   - İmza doğrulaması SSO_CONFIG$validate_signature ile yönetilir (vars. TRUE).
#   - Doğrulama AÇIK iken anahtar çözümlenemezse veya imza geçersizse token
#     REDDEDİLİR (fail-closed). Geçici JWKS erişim sorunu yetkisiz kabule yol
#     açmamalıdır; ancak daha önce alınmış anahtarlar TTL içinde önbellekten
#     kullanılabilir (anahtar rotasyonunda yenilenir).

# ==============================================================================
# BASE64URL ÇÖZME VE TOKEN PARÇALAMA
# ==============================================================================

#' base64url dizesini ham bayta çöz
#' @param x base64url (URL-safe, padding'siz olabilir) dize
#' @return raw vektör (boş/NULL girişte uzunluk 0 raw)
sso_base64url_decode <- function(x) {
  if (is.null(x) || length(x) == 0 || !nzchar(x)) {
    return(raw(0))
  }
  s <- gsub("-", "+", x, fixed = TRUE)
  s <- gsub("_", "/", s, fixed = TRUE)
  pad <- (4 - nchar(s) %% 4) %% 4
  if (pad > 0) {
    s <- paste0(s, strrep("=", pad))
  }
  tryCatch(base64enc::base64decode(s), error = function(e) raw(0))
}

#' PEM gövdesini 64 karakterlik satırlara böler
.sso_pem_wrap <- function(b64) {
  n <- nchar(b64)
  if (n == 0) return("")
  starts <- seq(1, n, by = 64)
  ends <- pmin(starts + 63, n)
  paste(substring(b64, starts, ends), collapse = "\n")
}

#' JWT'yi üç parçaya ve imza girdisine ayır
#' @return list(header_b64, payload_b64, signature_b64, signing_input) veya NULL
sso_jwt_segments <- function(token) {
  if (is.null(token) || length(token) != 1 || !nzchar(token)) {
    return(NULL)
  }
  parts <- strsplit(token, ".", fixed = TRUE)[[1]]
  if (length(parts) != 3) {
    return(NULL)
  }
  list(
    header_b64    = parts[1],
    payload_b64   = parts[2],
    signature_b64 = parts[3],
    # İmza girdisi: ilk iki parçanın nokta ile birleşimi (ASCII bayt).
    signing_input = paste0(parts[1], ".", parts[2])
  )
}

#' JWT başlığını (header) çöz - kid ve alg almak için kullanılır
sso_decode_jwt_header <- function(token) {
  tryCatch({
    seg <- sso_jwt_segments(token)
    if (is.null(seg)) return(NULL)
    raw_bytes <- sso_base64url_decode(seg$header_b64)
    if (length(raw_bytes) == 0) return(NULL)
    json_str <- rawToChar(raw_bytes)
    Encoding(json_str) <- "UTF-8"
    jsonlite::fromJSON(json_str, simplifyVector = FALSE)
  }, error = function(e) NULL)
}

# ==============================================================================
# JWK -> GENEL ANAHTAR (PUBLIC KEY) DÖNÜŞÜMÜ
# ==============================================================================
# Keycloak JWKS girişleri genellikle hem x5c sertifika zinciri hem de RSA
# modulus/exponent (n/e) içerir. x5c varsa onu tercih ederiz; yoksa n/e'den
# standart SubjectPublicKeyInfo (SPKI) DER üretip PEM'e çeviririz.

#' DER uzunluk baytlarını üret (kısa/uzun form)
.sso_der_length <- function(n) {
  if (n < 0) stop("DER uzunluğu negatif olamaz")
  if (n < 128) {
    return(as.raw(n))
  }
  bytes <- integer(0)
  v <- n
  while (v > 0) {
    bytes <- c(v %% 256, bytes)
    v <- v %/% 256
  }
  as.raw(c(128 + length(bytes), bytes))
}

#' DER TLV (tag-length-value) blok üret
.sso_der_tlv <- function(tag, content) {
  len <- .sso_der_length(length(content))
  as.raw(c(as.integer(tag), as.integer(len), as.integer(content)))
}

#' DER INTEGER kodla (işaretsiz büyük-endian magnitude'dan)
#' Baştaki gereksiz 0x00 baytları temizlenir; en yüksek baytın MSB'si set ise
#' pozitif işaret için tek 0x00 öne eklenir.
.sso_der_integer <- function(magnitude) {
  m <- as.integer(magnitude)
  while (length(m) > 1 && m[1] == 0) {
    m <- m[-1]
  }
  if (length(m) == 0) {
    m <- 0L
  }
  if (m[1] >= 128) {
    m <- c(0L, m)
  }
  .sso_der_tlv(0x02, as.raw(m))
}

#' RSA n/e'den SPKI PEM üret
sso_jwk_rsa_to_pem <- function(n_b64url, e_b64url) {
  n_raw <- sso_base64url_decode(n_b64url)
  e_raw <- sso_base64url_decode(e_b64url)
  if (length(n_raw) == 0 || length(e_raw) == 0) {
    return(NULL)
  }
  # RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent INTEGER }
  rsa_pub <- .sso_der_tlv(0x30, c(.sso_der_integer(n_raw), .sso_der_integer(e_raw)))
  # AlgorithmIdentifier: rsaEncryption OID (1.2.840.113549.1.1.1) + NULL
  rsa_oid <- as.raw(c(0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01))
  null_param <- as.raw(c(0x05, 0x00))
  alg_id <- .sso_der_tlv(0x30, c(rsa_oid, null_param))
  # subjectPublicKey BIT STRING: 0x00 (kullanılmayan bit) öneki + RSAPublicKey
  bit_string <- .sso_der_tlv(0x03, c(as.raw(0x00), rsa_pub))
  spki <- .sso_der_tlv(0x30, c(alg_id, bit_string))
  b64 <- base64enc::base64encode(spki)
  paste0(
    "-----BEGIN PUBLIC KEY-----\n",
    .sso_pem_wrap(b64),
    "\n-----END PUBLIC KEY-----\n"
  )
}

#' x5c (standart base64 DER sertifika) gövdesinden PEM sertifika üret
sso_jwk_x5c_to_pem <- function(x5c_first) {
  if (is.null(x5c_first) || length(x5c_first) == 0 || !nzchar(x5c_first)) {
    return(NULL)
  }
  b64 <- gsub("[[:space:]]", "", x5c_first)
  if (!nzchar(b64)) return(NULL)
  paste0(
    "-----BEGIN CERTIFICATE-----\n",
    .sso_pem_wrap(b64),
    "\n-----END CERTIFICATE-----\n"
  )
}

#' Tek bir JWK girişini openssl genel anahtarına çevir
#' @return openssl pubkey nesnesi veya NULL
sso_jwk_to_public_key <- function(jwk) {
  tryCatch({
    if (is.null(jwk)) return(NULL)

    # 1. Tercih: x5c sertifika zinciri (Keycloak varsayılan olarak sağlar)
    x5c <- jwk[["x5c"]]
    if (!is.null(x5c) && length(x5c) >= 1) {
      pem <- sso_jwk_x5c_to_pem(x5c[[1]])
      if (!is.null(pem)) {
        cert <- openssl::read_cert(pem)
        return(cert$pubkey)
      }
    }

    # 2. Yedek: RSA modulus/exponent
    n_val <- jwk[["n"]]
    e_val <- jwk[["e"]]
    if (!is.null(n_val) && !is.null(e_val) && nzchar(n_val) && nzchar(e_val)) {
      pem <- sso_jwk_rsa_to_pem(n_val, e_val)
      if (!is.null(pem)) {
        return(openssl::read_pubkey(pem))
      }
    }

    NULL
  }, error = function(err) {
    log_warn("JWK genel anahtara dönüştürülemedi: {conditionMessage(err)}")
    NULL
  })
}

# ==============================================================================
# İMZA DOĞRULAMA (RS256 / RS384 / RS512)
# ==============================================================================

#' Algoritma adından openssl hash fonksiyonu döndür
sso_alg_to_hash <- function(alg) {
  switch(
    toupper(alg %||% ""),
    "RS256" = openssl::sha256,
    "RS384" = openssl::sha384,
    "RS512" = openssl::sha512,
    NULL
  )
}

#' JWT imzasını verilen genel anahtarla doğrula
#' @param token JWT dizesi
#' @param public_key openssl genel anahtar nesnesi
#' @param allowed_algs İzin verilen imza algoritmaları (alg confusion koruması)
#' @return TRUE (geçerli) / FALSE (geçersiz veya hata)
sso_verify_jwt_signature <- function(token, public_key,
                                     allowed_algs = c("RS256", "RS384", "RS512")) {
  tryCatch({
    if (is.null(public_key)) return(FALSE)

    seg <- sso_jwt_segments(token)
    if (is.null(seg)) return(FALSE)

    header <- sso_decode_jwt_header(token)
    alg <- toupper(header[["alg"]] %||% "")
    # "none" ve izinli olmayan algoritmalar reddedilir (alg confusion saldırısı).
    if (!nzchar(alg) || !(alg %in% allowed_algs)) {
      log_warn("JWT imza algoritması izinli değil veya desteklenmiyor: '{alg}'")
      return(FALSE)
    }

    hash_fn <- sso_alg_to_hash(alg)
    if (is.null(hash_fn)) return(FALSE)

    sig_raw <- sso_base64url_decode(seg$signature_b64)
    if (length(sig_raw) == 0) return(FALSE)

    data_raw <- charToRaw(seg$signing_input)
    isTRUE(openssl::signature_verify(data_raw, sig_raw, hash = hash_fn, pubkey = public_key))
  }, error = function(err) {
    # signature_verify uyuşmazlıkta hata fırlatabilir; bu da geçersiz imza demektir.
    log_warn("JWT imza doğrulama başarısız: {conditionMessage(err)}")
    FALSE
  })
}

# ==============================================================================
# JWKS GETİRME VE ÖNBELLEK
# ==============================================================================
# JWKS bir kez alınıp süreç içi önbelleğe yazılır. Bilinmeyen kid (anahtar
# rotasyonu) veya TTL aşımında yeniden alınır. Böylece her giriş ağ çağrısı
# yapmaz, ancak rotasyon kaçırılmaz.

.sso_jwks_cache <- new.env(parent = emptyenv())

#' JWKS önbelleğini temizle (test ve operasyon için)
sso_jwks_cache_clear <- function() {
  rm(list = ls(.sso_jwks_cache), envir = .sso_jwks_cache)
  invisible(TRUE)
}

#' JWKS uç noktasından anahtar listesini al
#' @return JWK listesi veya NULL
sso_fetch_jwks <- function(jwks_url, timeout_secs = 10) {
  tryCatch({
    if (is.null(jwks_url) || !nzchar(jwks_url)) return(NULL)
    resp <- httr::GET(jwks_url, httr::timeout(timeout_secs))
    status <- httr::status_code(resp)
    if (status != 200) {
      log_warn("JWKS alınamadı (HTTP {status}): {jwks_url}")
      return(NULL)
    }
    txt <- httr::content(resp, as = "text", encoding = "UTF-8")
    parsed <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
    keys <- parsed[["keys"]]
    if (is.null(keys) || length(keys) == 0) return(NULL)
    keys
  }, error = function(err) {
    log_warn("JWKS getirme hatası: {conditionMessage(err)}")
    NULL
  })
}

#' Anahtar listesinde kid'e göre JWK bul
#' kid yoksa ilk imzalama (use=sig veya belirsiz) anahtarına düşer.
sso_find_jwk_by_kid <- function(keys, kid) {
  if (is.null(keys) || length(keys) == 0) return(NULL)
  for (k in keys) {
    k_kid <- k[["kid"]]
    if (!is.null(kid) && nzchar(kid)) {
      if (identical(as.character(k_kid), as.character(kid))) {
        return(k)
      }
    } else {
      k_use <- k[["use"]]
      if (is.null(k_use) || identical(k_use, "sig")) {
        return(k)
      }
    }
  }
  NULL
}

#' Token başlığındaki kid için imzalama genel anahtarını çöz
#' Önbellek taze ve kid mevcutsa ağ çağrısı yapılmaz; aksi halde JWKS yenilenir.
sso_resolve_signing_key <- function(token, config = SSO_CONFIG,
                                    fetch_fn = sso_fetch_jwks, now = Sys.time()) {
  header <- sso_decode_jwt_header(token)
  if (is.null(header)) return(NULL)
  kid <- header[["kid"]]

  jwks_url <- config$jwks_endpoint %||% ""
  if (!nzchar(jwks_url)) {
    log_warn("JWKS uç noktası yapılandırılmamış; imza anahtarı çözümlenemiyor (fail-closed).")
    return(NULL)
  }

  ttl <- as.numeric(config$jwks_cache_ttl_secs %||% 3600L)
  cache <- .sso_jwks_cache[[jwks_url]]
  keys <- if (!is.null(cache)) cache$keys else NULL

  fresh <- FALSE
  if (!is.null(cache)) {
    age <- as.numeric(difftime(now, cache$fetched_at, units = "secs"))
    fresh <- is.finite(age) && age < ttl
  }

  jwk <- sso_find_jwk_by_kid(keys, kid)

  # Önbellek yok, bayat ya da istenen kid önbellekte değilse JWKS'i yenile.
  if (is.null(keys) || !fresh || is.null(jwk)) {
    fresh_keys <- fetch_fn(jwks_url)
    if (!is.null(fresh_keys)) {
      .sso_jwks_cache[[jwks_url]] <- list(keys = fresh_keys, fetched_at = now)
      keys <- fresh_keys
      jwk <- sso_find_jwk_by_kid(keys, kid)
    }
  }

  if (is.null(jwk)) return(NULL)
  sso_jwk_to_public_key(jwk)
}

# ==============================================================================
# ÜST SEVİYE İMZA DOĞRULAMA (validate_jwt_token tarafından çağrılır)
# ==============================================================================

#' JWT imzasını yapılandırmaya göre doğrula
#' @return list(valid = TRUE/FALSE, error = ..., skipped = TRUE/FALSE)
sso_validate_jwt_signature <- function(token, config = SSO_CONFIG,
                                       key_resolver = sso_resolve_signing_key) {
  # İmza doğrulaması kapalıysa atla (issuer/expiry kontrolleri ayrıca çalışır).
  if (!isTRUE(config$validate_signature)) {
    return(list(valid = TRUE, error = NULL, skipped = TRUE))
  }

  # openssl yoksa fail-closed: doğrulanamayan token kabul edilmez.
  if (!requireNamespace("openssl", quietly = TRUE)) {
    log_error("openssl paketi bulunamadı; JWT imzası doğrulanamıyor (fail-closed).")
    return(list(valid = FALSE, error = "İmza doğrulama altyapısı kullanılamıyor", skipped = FALSE))
  }

  public_key <- tryCatch(
    key_resolver(token, config = config),
    error = function(e) {
      log_warn("İmza anahtarı çözümlenemedi: {conditionMessage(e)}")
      NULL
    }
  )

  if (is.null(public_key)) {
    return(list(valid = FALSE, error = "Token imza anahtarı doğrulanamadı (JWKS)", skipped = FALSE))
  }

  if (!isTRUE(sso_verify_jwt_signature(token, public_key))) {
    return(list(valid = FALSE, error = "Token imzası geçersiz", skipped = FALSE))
  }

  list(valid = TRUE, error = NULL, skipped = FALSE)
}
