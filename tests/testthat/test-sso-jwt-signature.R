# ==============================================================================
# Dosya Yolu: tests/testthat/test-sso-jwt-signature.R
# Açıklama: SSO JWT imza (signature) doğrulama yardımcılarının DAVRANIŞSAL
#           testleri. Gerçek üretim kodunu (R/helpers_sso_signature.R) çağırır:
#           - base64url çözme
#           - DER uzunluk/integer/SPKI kodlama (deterministik bayt doğrulaması)
#           - RS256 imza oluşturma/doğrulama (gerçek openssl anahtarı ile)
#           - alg-confusion / kurcalama / yanlış-anahtar reddi
#           - JWKS önbellek/anahtar çözümleme (enjekte edilen fetch ile, ağsız)
#           - sso_validate_jwt_signature fail-closed/skip mantığı
#           - validate_jwt_token() ile uçtan uca entegrasyon
#           Ağ, DB, tarayıcı veya Keycloak sunucusu GEREKMEZ. Sentetik anahtarlar
#           ve enjekte edilen çözümleyiciler kullanılır.
# ==============================================================================

.sso_sig_source_once <- function() {
  if (exists("sso_verify_jwt_signature", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_sso_signature.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
  invisible(TRUE)
}

# --- base64url yardımcıları (test tarafı) -------------------------------------
.sig_b64url_raw <- function(raw_bytes) {
  b64 <- base64enc::base64encode(raw_bytes)
  gsub("=+$", "", gsub("/", "_", gsub("+", "-", b64, fixed = TRUE), fixed = TRUE))
}
.sig_b64url_text <- function(txt) {
  .sig_b64url_raw(charToRaw(enc2utf8(txt)))
}

# Gerçek bir RS256 imzalı JWT üretir.
.sig_make_signed_jwt <- function(key, payload_list,
                                 alg = "RS256", kid = "testkid",
                                 hash = openssl::sha256) {
  header <- list(alg = alg, typ = "JWT", kid = kid)
  h <- .sig_b64url_text(jsonlite::toJSON(header, auto_unbox = TRUE))
  p <- .sig_b64url_text(jsonlite::toJSON(payload_list, auto_unbox = TRUE))
  signing_input <- paste0(h, ".", p)
  sig <- openssl::signature_create(charToRaw(signing_input), hash, key)
  paste0(signing_input, ".", .sig_b64url_raw(sig))
}

# ==============================================================================
# base64url ÇÖZME
# ==============================================================================
testthat::test_that("sso_base64url_decode boş/NULL girişte uzunluk 0 raw döner", {
  .sso_sig_source_once()
  testthat::expect_identical(sso_base64url_decode(NULL), raw(0))
  testthat::expect_identical(sso_base64url_decode(""), raw(0))
})

testthat::test_that("sso_base64url_decode padding'li/padding'siz girişte aynı sonucu verir", {
  .sso_sig_source_once()
  testthat::skip_if_not_installed("base64enc")

  original <- charToRaw("Mergen Bilge JWT")
  encoded_nopad <- .sig_b64url_raw(original)         # padding yok
  decoded <- sso_base64url_decode(encoded_nopad)
  testthat::expect_identical(decoded, original)

  # URL-safe karakterler (- ve _) doğru şekilde +/'ye çevrilmeli.
  tricky <- as.raw(c(0xFB, 0xFF, 0xBF))              # base64'te +/_ üretir
  enc <- .sig_b64url_raw(tricky)
  testthat::expect_identical(sso_base64url_decode(enc), tricky)
})

# ==============================================================================
# DER KODLAMA (deterministik bayt doğrulaması, openssl gerekmez)
# ==============================================================================
testthat::test_that(".sso_der_length kısa ve uzun formu doğru üretir", {
  .sso_sig_source_once()
  testthat::expect_identical(.sso_der_length(5L),   as.raw(5))
  testthat::expect_identical(.sso_der_length(127L), as.raw(0x7F))
  testthat::expect_identical(.sso_der_length(128L), as.raw(c(0x81, 0x80)))
  testthat::expect_identical(.sso_der_length(256L), as.raw(c(0x82, 0x01, 0x00)))
  testthat::expect_identical(.sso_der_length(300L), as.raw(c(0x82, 0x01, 0x2C)))
})

testthat::test_that(".sso_der_integer işaret/sıfır kurallarını uygular", {
  .sso_sig_source_once()
  # Normal pozitif bayt (MSB set değil).
  testthat::expect_identical(.sso_der_integer(as.raw(0x05)), as.raw(c(0x02, 0x01, 0x05)))
  # MSB set -> pozitif kalması için 0x00 öne eklenir.
  testthat::expect_identical(.sso_der_integer(as.raw(0xF0)), as.raw(c(0x02, 0x02, 0x00, 0xF0)))
  # Baştaki gereksiz sıfır baytları temizlenir.
  testthat::expect_identical(
    .sso_der_integer(as.raw(c(0x00, 0x00, 0x2A))),
    as.raw(c(0x02, 0x01, 0x2A))
  )
})

testthat::test_that("sso_jwk_rsa_to_pem yapısal olarak geçerli SPKI PEM üretir", {
  .sso_sig_source_once()
  # e = 65537 (AQAB), n = küçük sentetik modulus.
  n_b64 <- .sig_b64url_raw(as.raw(c(0xC0, 0x01, 0x02, 0x03, 0x04, 0x05)))
  pem <- sso_jwk_rsa_to_pem(n_b64, "AQAB")
  testthat::expect_true(grepl("-----BEGIN PUBLIC KEY-----", pem, fixed = TRUE))
  testthat::expect_true(grepl("-----END PUBLIC KEY-----", pem, fixed = TRUE))

  # PEM gövdesi geçerli base64 olmalı ve DER bir SEQUENCE (0x30) ile başlamalı.
  body <- gsub("-----[A-Z ]+-----|\\s", "", pem)
  der <- base64enc::base64decode(body)
  testthat::expect_identical(der[1], as.raw(0x30))
  # rsaEncryption OID baytları gömülü olmalı.
  oid <- as.raw(c(0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01))
  hay <- paste(sprintf("%02x", as.integer(der)), collapse = "")
  needle <- paste(sprintf("%02x", as.integer(oid)), collapse = "")
  testthat::expect_true(grepl(needle, hay, fixed = TRUE))
})

# ==============================================================================
# RS256 İMZA DOĞRULAMA (gerçek openssl anahtarı)
# ==============================================================================
testthat::test_that("sso_verify_jwt_signature geçerli RS256 imzayı kabul eder", {
  .sso_sig_source_once()
  testthat::skip_if_not_installed("openssl")

  key <- openssl::rsa_keygen(2048)
  token <- .sig_make_signed_jwt(key, list(preferred_username = "mkaradag", exp = 9999999999))
  testthat::expect_true(sso_verify_jwt_signature(token, key$pubkey))
})

testthat::test_that("sso_verify_jwt_signature kurcalanmış payload'ı reddeder", {
  .sso_sig_source_once()
  testthat::skip_if_not_installed("openssl")

  key <- openssl::rsa_keygen(2048)
  token <- .sig_make_signed_jwt(key, list(preferred_username = "mkaradag", role = "user"))

  parts <- strsplit(token, ".", fixed = TRUE)[[1]]
  forged_payload <- .sig_b64url_text(
    jsonlite::toJSON(list(preferred_username = "mkaradag", role = "admin"), auto_unbox = TRUE)
  )
  tampered <- paste0(parts[1], ".", forged_payload, ".", parts[3])
  testthat::expect_false(sso_verify_jwt_signature(tampered, key$pubkey))
})

testthat::test_that("sso_verify_jwt_signature kurcalanmış imzayı reddeder", {
  .sso_sig_source_once()
  testthat::skip_if_not_installed("openssl")

  key <- openssl::rsa_keygen(2048)
  token <- .sig_make_signed_jwt(key, list(preferred_username = "u"))
  parts <- strsplit(token, ".", fixed = TRUE)[[1]]
  bad_sig <- .sig_b64url_raw(charToRaw("definitely-not-a-real-signature"))
  tampered <- paste0(parts[1], ".", parts[2], ".", bad_sig)
  testthat::expect_false(sso_verify_jwt_signature(tampered, key$pubkey))
})

testthat::test_that("sso_verify_jwt_signature yanlış genel anahtarı reddeder", {
  .sso_sig_source_once()
  testthat::skip_if_not_installed("openssl")

  signer <- openssl::rsa_keygen(2048)
  attacker <- openssl::rsa_keygen(2048)
  token <- .sig_make_signed_jwt(signer, list(preferred_username = "u"))
  # Saldırganın anahtarıyla imzalanan token, gerçek anahtarla doğrulanmamalı.
  testthat::expect_false(sso_verify_jwt_signature(token, attacker$pubkey))
})

testthat::test_that("sso_verify_jwt_signature alg=none ve izinsiz algoritmayı reddeder", {
  .sso_sig_source_once()
  testthat::skip_if_not_installed("openssl")

  key <- openssl::rsa_keygen(2048)
  token_none <- .sig_make_signed_jwt(key, list(preferred_username = "u"), alg = "none")
  testthat::expect_false(sso_verify_jwt_signature(token_none, key$pubkey))

  token_hs <- .sig_make_signed_jwt(key, list(preferred_username = "u"), alg = "HS256")
  testthat::expect_false(sso_verify_jwt_signature(token_hs, key$pubkey))

  # allowed_algs ile RS384 sınırlandığında RS256 token reddedilmeli.
  token_rs256 <- .sig_make_signed_jwt(key, list(preferred_username = "u"), alg = "RS256")
  testthat::expect_false(
    sso_verify_jwt_signature(token_rs256, key$pubkey, allowed_algs = "RS384")
  )
})

testthat::test_that("sso_verify_jwt_signature bozuk token ve NULL anahtarı güvenli reddeder", {
  .sso_sig_source_once()
  testthat::expect_false(sso_verify_jwt_signature("iki.parca", NULL))
  testthat::expect_false(sso_verify_jwt_signature(NULL, NULL))
  testthat::expect_false(sso_verify_jwt_signature("a.b.c", NULL))
})

# ==============================================================================
# JWK -> GENEL ANAHTAR (n/e yuvarlak gidiş-dönüş; en iyi çaba, gerekirse atlanır)
# ==============================================================================
testthat::test_that("sso_jwk_to_public_key n/e JWK'sını çözüp imzayı doğrular", {
  .sso_sig_source_once()
  testthat::skip_if_not_installed("openssl")

  key <- openssl::rsa_keygen(2048)

  # Anahtarın kanonik SPKI DER'inden n ve e'yi ayrıştır (TLV yürüyüşü).
  ne <- tryCatch({
    der <- openssl::write_der(key$pubkey)
    read_tlv <- function(b, pos) {
      tag <- b[pos]; pos <- pos + 1L
      lb <- as.integer(b[pos]); pos <- pos + 1L
      if (lb < 128L) {
        len <- lb
      } else {
        nb <- lb - 128L
        len <- 0L
        for (i in seq_len(nb)) { len <- len * 256L + as.integer(b[pos]); pos <- pos + 1L }
      }
      list(tag = tag, content = b[pos:(pos + len - 1L)], next_pos = pos + len)
    }
    outer <- read_tlv(der, 1L)               # SubjectPublicKeyInfo SEQUENCE
    inner <- outer$content
    algid <- read_tlv(inner, 1L)             # AlgorithmIdentifier (atla)
    bitstr <- read_tlv(inner, algid$next_pos)# BIT STRING
    rsa_der <- bitstr$content[-1]            # ilk bayt 0x00 (kullanılmayan bit)
    rsa_seq <- read_tlv(rsa_der, 1L)         # RSAPublicKey SEQUENCE
    modint <- read_tlv(rsa_seq$content, 1L)  # modulus INTEGER
    expint <- read_tlv(rsa_seq$content, modint$next_pos) # exponent INTEGER
    n_bytes <- modint$content
    while (length(n_bytes) > 1 && n_bytes[1] == as.raw(0)) n_bytes <- n_bytes[-1]
    e_bytes <- expint$content
    while (length(e_bytes) > 1 && e_bytes[1] == as.raw(0)) e_bytes <- e_bytes[-1]
    list(n = .sig_b64url_raw(n_bytes), e = .sig_b64url_raw(e_bytes))
  }, error = function(e) NULL)

  if (is.null(ne)) {
    testthat::skip("openssl::write_der ayrıştırması bu ortamda yapılamadı")
  }

  pubkey <- sso_jwk_to_public_key(list(kty = "RSA", n = ne$n, e = ne$e))
  testthat::expect_false(is.null(pubkey))

  token <- .sig_make_signed_jwt(key, list(preferred_username = "roundtrip"))
  testthat::expect_true(sso_verify_jwt_signature(token, pubkey))
})

testthat::test_that("sso_find_jwk_by_kid kid eşleşmesini ve yedek davranışı uygular", {
  .sso_sig_source_once()
  keys <- list(
    list(kid = "k1", use = "sig"),
    list(kid = "k2", use = "enc"),
    list(kid = "k3", use = "sig")
  )
  testthat::expect_identical(sso_find_jwk_by_kid(keys, "k3")$kid, "k3")
  testthat::expect_null(sso_find_jwk_by_kid(keys, "yok"))
  # kid verilmezse ilk imzalama (sig) anahtarı seçilmeli.
  testthat::expect_identical(sso_find_jwk_by_kid(keys, NULL)$kid, "k1")
  testthat::expect_null(sso_find_jwk_by_kid(NULL, "k1"))
})

# ==============================================================================
# JWKS ÖNBELLEK VE ANAHTAR ÇÖZÜMLEME (enjekte edilen fetch, ağsız)
# ==============================================================================
# Kid içeren minimal bir token üretir (imza önemli değil; çözümleme yolu test edilir).
.sig_kid_token <- function(kid) {
  paste0(
    .sig_b64url_text(jsonlite::toJSON(list(alg = "RS256", kid = kid), auto_unbox = TRUE)),
    ".", .sig_b64url_text(jsonlite::toJSON(list(sub = "x"), auto_unbox = TRUE)),
    ".", .sig_b64url_raw(charToRaw("sig"))
  )
}

testthat::test_that("sso_resolve_signing_key JWKS'i bir kez alır ve önbellekten kullanır", {
  .sso_sig_source_once()
  sso_jwks_cache_clear()
  on.exit(sso_jwks_cache_clear(), add = TRUE)

  jwk <- list(kid = "kc-1", kty = "RSA", n = "AAAA", e = "AQAB")
  calls <- new.env(parent = emptyenv()); calls$n <- 0L
  fake_fetch <- function(url) { calls$n <- calls$n + 1L; list(jwk) }
  cfg <- list(jwks_endpoint = "https://kc.local/certs", jwks_cache_ttl_secs = 3600L)
  token <- .sig_kid_token("kc-1")

  invisible(sso_resolve_signing_key(token, config = cfg, fetch_fn = fake_fetch))
  invisible(sso_resolve_signing_key(token, config = cfg, fetch_fn = fake_fetch))
  # İkinci çağrı taze önbellekten gelmeli: fetch yalnızca 1 kez çağrılmalı.
  testthat::expect_identical(calls$n, 1L)
})

testthat::test_that("sso_resolve_signing_key bilinmeyen kid'de JWKS'i yeniden alır (rotasyon)", {
  .sso_sig_source_once()
  sso_jwks_cache_clear()
  on.exit(sso_jwks_cache_clear(), add = TRUE)

  calls <- new.env(parent = emptyenv()); calls$n <- 0L
  fake_fetch <- function(url) {
    calls$n <- calls$n + 1L
    # İlk alımda yalnızca eski anahtar; sonraki alımda yeni kid de var (rotasyon).
    if (calls$n == 1L) {
      list(list(kid = "old", kty = "RSA", n = "AAAA", e = "AQAB"))
    } else {
      list(
        list(kid = "old", kty = "RSA", n = "AAAA", e = "AQAB"),
        list(kid = "new", kty = "RSA", n = "AAAA", e = "AQAB")
      )
    }
  }
  cfg <- list(jwks_endpoint = "https://kc.local/certs", jwks_cache_ttl_secs = 3600L)

  # 1) "old" kid çözülür: önbellek boş -> fetch (n=1), [old] önbelleğe alınır.
  invisible(sso_resolve_signing_key(.sig_kid_token("old"), config = cfg, fetch_fn = fake_fetch))
  testthat::expect_identical(calls$n, 1L)

  # 2) "new" kid istenir: önbellek taze ama "new" yok -> rotasyon için yeniden fetch (n=2).
  invisible(sso_resolve_signing_key(.sig_kid_token("new"), config = cfg, fetch_fn = fake_fetch))
  testthat::expect_identical(calls$n, 2L)
})

testthat::test_that("sso_resolve_signing_key JWKS uç noktası yoksa NULL döner (fail-closed)", {
  .sso_sig_source_once()
  sso_jwks_cache_clear()
  token <- paste0(
    .sig_b64url_text(jsonlite::toJSON(list(alg = "RS256", kid = "k"), auto_unbox = TRUE)),
    ".aa.bb"
  )
  res <- sso_resolve_signing_key(token, config = list(jwks_endpoint = ""),
                                 fetch_fn = function(u) stop("çağrılmamalı"))
  testthat::expect_null(res)
})

# ==============================================================================
# ÜST SEVİYE: sso_validate_jwt_signature (flag / fail-closed / valid)
# ==============================================================================
testthat::test_that("sso_validate_jwt_signature kapalıyken atlar (skipped=TRUE)", {
  .sso_sig_source_once()
  res <- sso_validate_jwt_signature(
    "a.b.c",
    config = list(validate_signature = FALSE),
    key_resolver = function(...) stop("çağrılmamalı")
  )
  testthat::expect_true(res$valid)
  testthat::expect_true(isTRUE(res$skipped))
})

testthat::test_that("sso_validate_jwt_signature açıkken anahtar çözülemezse REDDEDER (fail-closed)", {
  .sso_sig_source_once()
  testthat::skip_if_not_installed("openssl")
  res <- sso_validate_jwt_signature(
    "a.b.c",
    config = list(validate_signature = TRUE),
    key_resolver = function(token, config = NULL) NULL
  )
  testthat::expect_false(res$valid)
  testthat::expect_false(isTRUE(res$skipped))
  testthat::expect_true(nzchar(res$error))
})

testthat::test_that("sso_validate_jwt_signature geçerli imzayı kabul, geçersizi reddeder", {
  .sso_sig_source_once()
  testthat::skip_if_not_installed("openssl")

  key <- openssl::rsa_keygen(2048)
  token <- .sig_make_signed_jwt(key, list(preferred_username = "u"))
  resolver <- function(t, config = NULL) key$pubkey

  ok <- sso_validate_jwt_signature(token, config = list(validate_signature = TRUE),
                                   key_resolver = resolver)
  testthat::expect_true(ok$valid)

  parts <- strsplit(token, ".", fixed = TRUE)[[1]]
  bad <- paste0(parts[1], ".", parts[2], ".", .sig_b64url_raw(charToRaw("x")))
  ko <- sso_validate_jwt_signature(bad, config = list(validate_signature = TRUE),
                                   key_resolver = resolver)
  testthat::expect_false(ko$valid)
})

# ==============================================================================
# UÇTAN UCA: validate_jwt_token() imza kapısı (gerçek wiring)
# ==============================================================================
testthat::test_that("validate_jwt_token imza açıkken geçerli imzalı token'ı kabul eder", {
  .sso_sig_source_once()
  testthat::skip_if_not_installed("openssl")

  # validate_jwt_token, sso_resolve_signing_key'i global ortamda arar; test
  # için onu sentetik anahtara döndüren bir stub ile değiştiririz.
  key <- openssl::rsa_keygen(2048)
  had_resolver <- exists("sso_resolve_signing_key", envir = globalenv(), inherits = FALSE)
  old_resolver <- if (had_resolver) get("sso_resolve_signing_key", envir = globalenv()) else NULL
  assign("sso_resolve_signing_key", function(token, config = NULL, ...) key$pubkey, envir = globalenv())

  eski_sig <- SSO_CONFIG$validate_signature
  eski_iss <- SSO_CONFIG$validate_issuer
  eski_exp <- SSO_CONFIG$validate_expiry
  SSO_CONFIG$validate_signature <<- TRUE
  SSO_CONFIG$validate_issuer <<- FALSE
  SSO_CONFIG$validate_expiry <<- FALSE
  on.exit({
    SSO_CONFIG$validate_signature <<- eski_sig
    SSO_CONFIG$validate_issuer <<- eski_iss
    SSO_CONFIG$validate_expiry <<- eski_exp
    if (had_resolver) assign("sso_resolve_signing_key", old_resolver, envir = globalenv())
    else if (exists("sso_resolve_signing_key", envir = globalenv(), inherits = FALSE)) {
      rm(list = "sso_resolve_signing_key", envir = globalenv())
    }
  }, add = TRUE)

  token <- .sig_make_signed_jwt(key, list(preferred_username = "imzali_user"))
  sonuc <- validate_jwt_token(token)
  testthat::expect_true(sonuc$valid)
  testthat::expect_identical(sonuc$payload$preferred_username, "imzali_user")
})

testthat::test_that("validate_jwt_token imza açıkken geçersiz imzalı token'ı reddeder", {
  .sso_sig_source_once()
  testthat::skip_if_not_installed("openssl")

  key <- openssl::rsa_keygen(2048)
  attacker <- openssl::rsa_keygen(2048)
  had_resolver <- exists("sso_resolve_signing_key", envir = globalenv(), inherits = FALSE)
  old_resolver <- if (had_resolver) get("sso_resolve_signing_key", envir = globalenv()) else NULL
  # Çözümleyici gerçek anahtarı döndürür ama token saldırgan anahtarıyla imzalanır.
  assign("sso_resolve_signing_key", function(token, config = NULL, ...) key$pubkey, envir = globalenv())

  eski_sig <- SSO_CONFIG$validate_signature
  SSO_CONFIG$validate_signature <<- TRUE
  on.exit({
    SSO_CONFIG$validate_signature <<- eski_sig
    if (had_resolver) assign("sso_resolve_signing_key", old_resolver, envir = globalenv())
    else if (exists("sso_resolve_signing_key", envir = globalenv(), inherits = FALSE)) {
      rm(list = "sso_resolve_signing_key", envir = globalenv())
    }
  }, add = TRUE)

  forged <- .sig_make_signed_jwt(attacker, list(preferred_username = "saldirgan"))
  sonuc <- validate_jwt_token(forged)
  testthat::expect_false(sonuc$valid)
})
