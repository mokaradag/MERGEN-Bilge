# ==============================================================================
# Dosya Yolu: R/helpers_api_key_crypto.R
# Açıklama: Kullanıcı API anahtarlarının dosya tabanlı şifreli saklama katmanı:
#           anahtar dosya yolu, tuzlu SHA256 hash, AES-256-GCM/CBC şifreleme ve
#           çözme, kaydet/yükle/var-mı/doğrula akışı. config_api.R içinden bu
#           dosyaya taşınmıştır; fonksiyon adları ve davranış birebir korunur.
#
#           Güvenlik notları:
#           - Ham anahtar değeri asla loglanmaz, dosyaya düz yazılmaz.
#           - Türkçe karakter içeren anahtarlar UTF-8 baytlarıyla şifrelenir ve
#             çözümde UTF-8 olarak geri okunur (Windows/VM gidiş-dönüş güvenli).
#           - save_user_api_key() içindeki NUL-tuz eşlemesi korunan regresyon
#             guard'ıdır; hash yolu yeniden tasarlanmadan kaldırılmamalıdır.
# ==============================================================================

# --- KULLANICI API ANAHTARI YÖNETİMİ ---
API_KEYS_DIR <- normalizePath(file.path(getwd(), "api_keys"), winslash = "/", mustWork = FALSE)
dir.create(API_KEYS_DIR, showWarnings = FALSE, recursive = TRUE)

# Kayıt SAHİBİ doğrulaması. Harf büyüklüğüne duyarsız dosya sisteminde `Alice`
# ve `alice` aynı dosyaya çözülüyor; kayıttaki `user` alanı kontrol edilmezse
# bir kullanıcı diğerinin anahtarını okuyabiliyordu (IDOR). Eski kayıtlarda
# `user` alanı yoksa geriye dönük uyumluluk için kabul edilir.
.api_kayit_sahibi_mi <- function(rec, system_username) {
  # NESNE OLMAYAN kayıt reddedilir: anahtar dosyası geçerli ama skaler JSON
  # ("invalid") içerdiğinde `read_json()` başarılı oluyor, `rec$user` ise
  # "$ operator is invalid for atomic vectors" hatası fırlatıyor ve
  # `verify_user_api_key()` FALSE dönmek yerine tamamen düşüyordu.
  if (!is.list(rec)) return(FALSE)
  sahip <- as.character(rec$user %||% "")[1]
  if (is.na(sahip) || !nzchar(sahip)) return(TRUE)
  identical(sahip, as.character(system_username %||% "")[1])
}

# `enc` alanı ÇÖZÜLEBİLİR bir nesne mi? `.dec_key()` `iv_b64` ve `cipher_b64`
# alanlarına erişir; skaler bir değer ("invalid") `$` erişiminde hata fırlatır.
.api_enc_bicimi_gecerli <- function(enc) {
  if (!is.list(enc)) return(FALSE)
  for (alan in c("iv_b64", "cipher_b64")) {
    deger <- enc[[alan]]
    if (!is.character(deger) || length(deger) != 1L ||
        is.na(deger) || !nzchar(deger)) {
      return(FALSE)
    }
  }
  TRUE
}

# Kullanıcıya özel anahtar dosya yolu
#
# `must_work = FALSE`: OKUMA yollarında geçersiz kullanıcı adı için boş dize
# döner. Eskiden bu yardımcı `stop()` çağırdığı için `load_user_api_key()`,
# `user_api_key_exists()` ve `verify_user_api_key()` sözleşmelerindeki
# `NULL`/`FALSE` yerine İSTİSNA fırlatıyordu (`module_api_key.R` istisnayı
# `try-error` olarak görüp kullanıcıyı anahtar hiç yokmuş gibi onboarding'e
# yönlendiriyordu). YAZMA yolunda `stop()` KORUNUR: güvensiz bir ada sessizce
# yazmak yerine açık hata gerekir.
#
# NOT: Kullanıcı adı KODLANMAZ (ör. karma eklenmez). Kodlama, aynı kullanıcı için
# ikinci bir anahtar dosyası üretip mevcut kişisel anahtarı görünmez yapardı;
# güvenli ad üretmek `mb_api_key_resolve_owner()` sorumluluğundadır.
.api_user_file <- function(system_username, must_work = TRUE) {
  kullanici <- as.character(system_username %||% "")[1]
  # Kullanıcı adı yol bileşeni olarak güvenli olmalı; ayraç içeren değer
  # anahtar dosyasını API_KEYS_DIR dışına taşıyabilirdi. Ayraç ve basename
  # denetimi traversal için YETERLİDİR; ayrıca ".." dizisini reddetmek
  # `ad..soyad` gibi GEÇERLİ kullanıcı adlarında kişisel anahtar kaydını ve
  # okumasını engelliyordu (üretilen `ad..soyad_api_key` bir geçiş bileşeni
  # değildir).
  # Windows `: * ? " < > |` karakterlerini dosya adında kabul etmez; bu değerler
  # geçtiğinde kullanıcı anahtarını Windows'ta HİÇ kaydedemiyor/okuyamıyordu.
  if (is.na(kullanici) || !nzchar(kullanici) ||
      grepl("[/\\\\]", kullanici) ||
      grepl("[:*?\"<>|]", kullanici, perl = TRUE) ||
      !identical(basename(kullanici), kullanici)) {
    if (!isTRUE(must_work)) return("")
    stop("Geçersiz kullanıcı adı: API anahtarı dosya yolu üretilemedi.", call. = FALSE)
  }
  file.path(API_KEYS_DIR, sprintf("%s_api_key", kullanici))
}

# Tuzlu hash oluştur (SHA256 hex): SHA256(salt || key)
.hash_key_hex <- function(key_plain, salt_raw) {
  stopifnot(is.character(key_plain), length(key_plain) == 1)
  openssl::sha256(paste0(rawToChar(salt_raw), key_plain)) |>
    as.character() # hex string
}

# AES-256-GCM (kimlik doğrulamalı) şifreleme
# Geriye dönük uyumluluk: GCM yoksa CBC'ye düşer
.enc_key <- function(plain_text, master) {
  stopifnot(is.character(plain_text), length(plain_text) == 1)

  # Türkçe karakterler dahil tüm metinleri platformdan bağımsız UTF-8 baytlarıyla şifrele.
  plain_raw <- charToRaw(enc2utf8(plain_text))

  # 32 baytlık anahtar türet
  k <- openssl::sha256(charToRaw(master))

  # GCM mevcutsa ve beklenen yapıyı döndürüyorsa tercih et
  use_gcm <- isTRUE(exists("aes_gcm_encrypt", where = asNamespace("openssl"), inherits = FALSE))
  if (use_gcm) {
    iv12 <- openssl::rand_bytes(12L)
    gcm  <- openssl::aes_gcm_encrypt(
      data = plain_raw,
      key  = k,
      iv   = iv12
    )

    # Bazı openssl sürümleri list(data=raw, tag=raw) döndürür, bazıları farklı
    if (is.list(gcm) && !is.null(gcm$data) && is.raw(gcm$data) && !is.null(gcm$tag) && is.raw(gcm$tag)) {
      return(list(
        alg        = "aes-256-gcm",
        iv_b64     = base64enc::base64encode(iv12),
        cipher_b64 = base64enc::base64encode(gcm$data),
        tag_b64    = base64enc::base64encode(gcm$tag)
      ))
    }
    # GCM var ama beklenen yapıyı döndürmedi -> CBC'ye düş
  }

  # Yedek: AES-256-CBC (her zaman mevcut)
  iv16 <- openssl::rand_bytes(16L)
  ct   <- openssl::aes_cbc_encrypt(plain_raw, key = k, iv = iv16)
  list(
    alg        = "aes-256-cbc",
    iv_b64     = base64enc::base64encode(iv16),
    cipher_b64 = base64enc::base64encode(ct)
    # CBC'de tag_b64 yok
  )
}

# AES-256-GCM / CBC çözme (geriye dönük uyumlu)
.dec_key <- function(enc_obj, master) {

  # Basit doğrulama: zorunlu alanlar
  if (is.null(enc_obj$iv_b64) || is.null(enc_obj$cipher_b64)) {
    stop("Kayıt bozuk: iv/cipher alanı yok.")
  }

  k <- openssl::sha256(charToRaw(master))

  # Şifre çözme sonrası raw baytları açıkça UTF-8 metne çevir.
  # Bu, Windows/RStudio ortamında Türkçe karakterlerin ÅŸ/ÄŸ gibi bozulmasını önler.
  .decode_utf8_raw <- function(raw_value) {
    out <- rawToChar(raw_value)
    Encoding(out) <- "UTF-8"
    enc2utf8(out)
  }

  # Önce GCM varsay: tag varsa GCM çöz
  if (!is.null(enc_obj$tag_b64)) {
    iv <- base64enc::base64decode(enc_obj$iv_b64 %||% "")
    ct <- base64enc::base64decode(enc_obj$cipher_b64 %||% "")
    tg <- base64enc::base64decode(enc_obj$tag_b64 %||% "")

    raw <- openssl::aes_gcm_decrypt(
      data = ct,
      key  = k,
      iv   = iv,
      tag  = tg
    )
    return(.decode_utf8_raw(raw))
  }

  # Geriye dönük: eski CBC kayıtları için çözüm
  iv <- base64enc::base64decode(enc_obj$iv_b64 %||% "")
  ct <- base64enc::base64decode(enc_obj$cipher_b64 %||% "")
  .decode_utf8_raw(openssl::aes_cbc_decrypt(ct, key = k, iv = iv))
}

# Kullanıcı API anahtarını şifrele ve kaydet
save_user_api_key <- function(system_username, key_plain) {
  f <- .api_user_file(system_username)
  master <- Sys.getenv("AI_KEYS_MASTER", "")
  if (!nzchar(master)) stop("AI_KEYS_MASTER is missing in .Renviron")

  # openssl::rand_bytes() 0x00 bayt üretebilir; .hash_key_hex() tuzu rawToChar()
  # ile metne çevirdiği için gömülü NUL "embedded nul in string" hatası verir ve
  # kaydı ~%6 olasılıkla çökertir. Tuz yalnızca hash karıştırması içindir; NUL
  # baytları 0x01'e eşlenerek hash algoritması ve mevcut kayıtlarla uyum korunur.
  salt <- openssl::rand_bytes(16L)
  salt[salt == as.raw(0L)] <- as.raw(1L)
  hash_hex <- .hash_key_hex(key_plain, salt)
  enc <- .enc_key(key_plain, master)

  rec <- list(
    user = system_username,
    salt_b64 = base64enc::base64encode(salt),
    hash_hex = hash_hex,
    enc = enc,
    created_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
  # API anahtarı kayıt dosyası kısmi yazıma karşı kritiktir; atomik yardımcıdan
  # geçirilir (tmp -> rename) ve Windows VM'de kilitli dosya durumunda kopya
  # fallback davranışı korunur.
  atomic_write_json(rec, f, pretty = TRUE, auto_unbox = TRUE)
  normalizePath(f, winslash = "/", mustWork = FALSE)
}

# Kullanıcı API anahtarını çöz ve döndür
load_user_api_key <- function(system_username) {
  f <- .api_user_file(system_username, must_work = FALSE)
  if (!nzchar(f) || !file.exists(f)) return(NULL)
  master <- Sys.getenv("AI_KEYS_MASTER", "")
  if (!nzchar(master)) return(NULL)
  rec <- try(jsonlite::read_json(f, simplifyVector = TRUE), silent = TRUE)
  # NESNE denetimi `rec$enc` erişiminden ÖNCE gelir: skaler JSON ("invalid")
  # geçerli biçimde ayrıştırılıyor, `$` ise atomik vektörde hata fırlatıyordu.
  if (inherits(rec, "try-error") || !is.list(rec) || is.null(rec$enc)) return(NULL)
  if (!.api_kayit_sahibi_mi(rec, system_username)) return(NULL)
  tryCatch(.dec_key(rec$enc, master), error = function(e) NULL)
}

# Kullanıcının kayıtlı API anahtarı var mı? (sahiplik de doğrulanır)
# Geçerli ama EKSİK bir JSON nesnesi (`{}`) sahiplik denetiminden geçiyor ve
# burada TRUE dönüyordu; `load_user_api_key()` ise NULL döndürdüğü için çağıran
# "anahtar var ama okunamıyor" durumuna düşüyordu. Kayıt KULLANILABİLİR olmalı.
user_api_key_exists <- function(system_username) {
  f <- .api_user_file(system_username, must_work = FALSE)
  if (!nzchar(f) || !file.exists(f)) return(FALSE)
  rec <- try(jsonlite::read_json(f, simplifyVector = TRUE), silent = TRUE)
  if (inherits(rec, "try-error") || !is.list(rec)) return(FALSE)
  # `enc` ÇÖZÜLEBİLİR BİÇİMDE olmalı. `{"enc":"invalid",...}` kaydı eski
  # denetimlerden geçiyordu: burada TRUE dönüyor, `load_user_api_key()` ise
  # `.dec_key()` içindeki `iv_b64`/`cipher_b64` erişimi hata verdiği için NULL
  # dönüyordu. Çağıran "anahtar var ama okunamıyor" durumuna düşüyordu.
  if (!.api_enc_bicimi_gecerli(rec$enc)) return(FALSE)
  degerler <- c(
    as.character(rec$salt_b64 %||% "")[1],
    as.character(rec$hash_hex %||% "")[1]
  )
  if (length(degerler) != 2L || anyNA(degerler) || !all(nzchar(degerler))) return(FALSE)
  .api_kayit_sahibi_mi(rec, system_username)
}

# Kullanıcının girdiği anahtarı mevcut kayıtla doğrula (hash karşılaştırması)
verify_user_api_key <- function(system_username, candidate_plain) {
  f <- .api_user_file(system_username, must_work = FALSE)
  if (!nzchar(f) || !file.exists(f)) return(FALSE)
  rec <- try(jsonlite::read_json(f, simplifyVector = TRUE), silent = TRUE)
  if (inherits(rec, "try-error")) return(FALSE)
  if (!.api_kayit_sahibi_mi(rec, system_username)) return(FALSE)

  # KAYIT BİÇİMİ çözümlemeden ÖNCE denetlenir. `salt_b64` skaler değilse
  # (ör. `{}`) `base64enc::base64decode()` FALSE dönmek yerine hata fırlatıyor,
  # geçersiz `hash_hex` biçimi de karşılaştırmada düşüyordu. Çözme ve hash adımı
  # ayrıca `tryCatch` ile sarılır: `.hash_key_hex()` içindeki `stopifnot()`
  # skaler olmayan bir adayda istisna üretir.
  salt_b64 <- rec$salt_b64
  beklenen_hash <- rec$hash_hex
  if (!is.character(salt_b64) || length(salt_b64) != 1L ||
      is.na(salt_b64) || !nzchar(salt_b64) ||
      !is.character(beklenen_hash) || length(beklenen_hash) != 1L ||
      is.na(beklenen_hash) || !nzchar(beklenen_hash)) {
    return(FALSE)
  }

  hash_hex <- tryCatch({
    salt <- base64enc::base64decode(salt_b64)
    .hash_key_hex(candidate_plain, salt)
  }, error = function(e) "")
  if (length(hash_hex) != 1L || is.na(hash_hex) || !nzchar(hash_hex)) return(FALSE)

  isTRUE(identical(tolower(hash_hex), tolower(beklenen_hash)))
}
