# ==============================================================================
# Dosya Yolu: R/helpers_sso_jwks_cache.R
# Açıklama: Keycloak JWKS getirme ve süreç içi anahtar önbelleği.
#           R/helpers_sso_signature.R dosyasından ÖNCE source edilmelidir;
#           imza doğrulama katmanı `sso_resolve_signing_key()` üzerinden bu
#           dosyaya bağlıdır. Önbellek/negatif önbellek mantığını imza
#           dosyasına geri taşımayın (fonksiyon-yoğunluk bölme sözleşmesi).
#
# GÜVENLİK SÖZLEŞMESİ:
#   - Anahtar çözümlenemezse NULL döner; çağıran fail-closed davranır.
#   - Bilinmeyen `kid` için negatif önbellek TUTULUR ve SINIRLIDIR; ancak
#     yalnızca JWKS yenilemesi GERÇEKTEN başarılı olduğunda yazılır.
# ==============================================================================

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}

# ==============================================================================
# JWKS GETİRME VE ÖNBELLEK
# ==============================================================================
# JWKS bir kez alınıp süreç içi önbelleğe yazılır. Bilinmeyen kid (anahtar
# rotasyonu) veya TTL aşımında yeniden alınır. Böylece her giriş ağ çağrısı
# yapmaz, ancak rotasyon kaçırılmaz.

.sso_jwks_cache <- new.env(parent = emptyenv())

# Negatif (bilinmeyen kid) önbellek kapasitesi. Kimliği doğrulanmamış bir
# istemci sürekli farklı `kid` göndererek süreç ömrü boyunca önbelleği
# büyütebiliyordu; üst sınır bunu engeller.
.SSO_JWKS_NEGATIVE_CACHE_MAX <- 256L

# Doğrulanmamış JWT başlığından gelen `kid` için makul bayt sınırı.
.SSO_JWKS_MAX_KID_BYTES <- 256L

# Negatif pencere üst sınırı: rotasyon en fazla bu süre kadar gecikir.
.SSO_JWKS_NEGATIVE_TTL_MAX_SEC <- 60

# Başarısız JWKS getirmesi için kısa geri çekilme (senkron istek seli önlenir).
.SSO_JWKS_FETCH_BACKOFF_SEC <- 30

# NEGATİF ÖNBELLEK ile GETİRME GERİ ÇEKİLMESİ AYRI AD UZAYLARINDA tutulur.
# Eski biçimde ikisi de "<url>|<kid>" kalıbını paylaşıyordu; doğrulanmamış JWT
# başlığı `kid = "__fetch_backoff__"` gönderdiğinde negatif giriş geri çekilme
# kaydının ÜZERİNE yazılıyor ve 30 sn boyunca hem bayat önbellek tazelenemiyor
# hem de bilinmeyen kid yenilenemiyordu (rotasyon sırasında geçerli girişler
# reddediliyordu). `|kid|` öneki hiçbir kid değeriyle `|backoff` adını üretemez.
.SSO_JWKS_NEGATIVE_TAG <- "|kid|"
.SSO_JWKS_FETCH_BACKOFF_TAG <- "|backoff"

#' JWKS önbelleğini temizle (test ve operasyon için)
sso_jwks_cache_clear <- function() {
  rm(list = ls(.sso_jwks_cache), envir = .sso_jwks_cache)
  invisible(TRUE)
}

# Negatif giriş adları "<jwks_url>|kid|<kid>" biçimindedir; pozitif JWKS girişi
# yalnızca URL adını, getirme geri çekilmesi ise "<jwks_url>|backoff" adını
# taşır. Ad uzayları ayrık olduğu için geri çekilme kaydı negatif kapasiteye
# SAYILMAZ ve hiçbir `kid` değeri onu ezemez.
.sso_jwks_negative_names <- function() {
  adlar <- ls(.sso_jwks_cache)
  adlar[grepl(.SSO_JWKS_NEGATIVE_TAG, adlar, fixed = TRUE)]
}

# Ortam bağlantısını gerçekten kaldırır. `env[[ad]] <- NULL` bağlantıyı
# `ls()` içinde bırakıyor, süresi dolmuş girişler kapasiteye sayılmaya devam
# ediyor ve temizlik `giris$fetched_at` üzerinde NULL ile çalışıyordu.
.sso_jwks_negative_remove <- function(ad) {
  var <- ad[nzchar(ad) & vapply(ad, function(x) {
    exists(x, envir = .sso_jwks_cache, inherits = FALSE)
  }, logical(1))]
  if (length(var)) rm(list = var, envir = .sso_jwks_cache)
  invisible(TRUE)
}

# Süresi dolmuş (ya da bozuk) negatif girişleri ayıklar.
.sso_jwks_negative_prune <- function(now, negatif_ttl) {
  for (ad in .sso_jwks_negative_names()) {
    giris <- .sso_jwks_cache[[ad]]
    if (is.null(giris)) {
      .sso_jwks_negative_remove(ad)
      next
    }
    yas <- suppressWarnings(as.numeric(difftime(now, giris$fetched_at, units = "secs")))
    if (length(yas) != 1L || !is.finite(yas) || yas >= negatif_ttl) {
      .sso_jwks_negative_remove(ad)
    }
  }
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

  # `kid` DOĞRULANMAMIŞ JWT başlığından gelir ve negatif önbellek anahtarına
  # giriyordu. 256 kayıt sınırı tek bir anahtarın BOYUTUNU sınırlamaz: büyük ve
  # benzersiz değerler belleği büyütür ve her biri senkron JWKS yenilemesi
  # tetikler. Makul bayt sınırını aşan değer önbelleğe alınmadan reddedilir.
  kid_metin <- as.character(kid %||% "")[1]
  if (is.na(kid_metin)) kid_metin <- ""
  if (nchar(kid_metin, type = "bytes") > .SSO_JWKS_MAX_KID_BYTES) {
    log_warn("JWT başlığındaki kid değeri makul sınırı aşıyor; reddedildi (fail-closed).")
    return(NULL)
  }

  jwks_url <- config$jwks_endpoint %||% ""
  if (!nzchar(jwks_url)) {
    log_warn("JWKS uç noktası yapılandırılmamış; imza anahtarı çözümlenemiyor (fail-closed).")
    return(NULL)
  }

  # Geçersiz/sıfır/negatif TTL, `fresh` değerini her zaman FALSE yapıp her token
  # doğrulamasında SENKRON JWKS getirmeyi tetikliyordu; Keycloak yavaşsa her
  # giriş timeout bekliyordu. Sonlu ve pozitif olmayan değer varsayılana düşer.
  ttl <- suppressWarnings(as.numeric(config$jwks_cache_ttl_secs %||% 3600L))
  if (length(ttl) != 1L || !is.finite(ttl) || ttl <= 0) ttl <- 3600
  cache <- .sso_jwks_cache[[jwks_url]]
  keys <- if (!is.null(cache)) cache$keys else NULL

  fresh <- FALSE
  if (!is.null(cache)) {
    age <- as.numeric(difftime(now, cache$fetched_at, units = "secs"))
    fresh <- is.finite(age) && age < ttl
  }

  jwk <- sso_find_jwk_by_kid(keys, kid)

  # NEGATİF ÖNBELLEK: bilinmeyen bir `kid` her doğrulama denemesinde JWKS
  # getirmeyi tetikliyordu; geçersiz tokenlarla Keycloak'a istek seli
  # üretilebiliyordu. Aynı kid için yenileme en fazla TTL/10 (>= 30 sn) aralıkla
  # denenir; anahtar rotasyonu yine kısa sürede yakalanır.
  negatif_ttl <- min(.SSO_JWKS_NEGATIVE_TTL_MAX_SEC, max(30, ttl / 10))
  negatif_anahtar <- paste0(jwks_url, .SSO_JWKS_NEGATIVE_TAG, kid_metin)
  negatif <- .sso_jwks_cache[[negatif_anahtar]]
  negatif_taze <- FALSE
  if (!is.null(negatif)) {
    negatif_yas <- as.numeric(difftime(now, negatif$fetched_at, units = "secs"))
    negatif_taze <- is.finite(negatif_yas) && negatif_yas < negatif_ttl
  }

  # Negatif önbellek YALNIZCA bilinmeyen kid yenilemesini kısar. Bayat pozitif
  # önbelleğin tazelenmesini de engellerse (küçük TTL'de negatif TTL pozitifi
  # aşabiliyor) rotasyona uğramış anahtarlar negatif TTL boyunca kullanılırdı.
  pozitif_yenile <- is.null(keys) || !isTRUE(fresh)
  kid_yenile <- is.null(jwk) && !isTRUE(negatif_taze)

  # BAŞARISIZ yenileme için ayrı geri çekilme kaydı: negatif giriş yalnızca
  # getirme BAŞARILI olduğunda yazıldığı için, JWKS uç noktası erişilemezken
  # bilinmeyen `kid` her doğrulamada yeni bir SENKRON `httr::GET` başlatıyor ve
  # tek iş parçacıklı R süreci saniyelerce yanıt veremiyordu.
  getirme_backoff <- paste0(jwks_url, .SSO_JWKS_FETCH_BACKOFF_TAG)
  backoff <- .sso_jwks_cache[[getirme_backoff]]
  backoff_taze <- FALSE
  if (!is.null(backoff)) {
    backoff_yas <- as.numeric(difftime(now, backoff$fetched_at, units = "secs"))
    backoff_taze <- is.finite(backoff_yas) &&
      backoff_yas < .SSO_JWKS_FETCH_BACKOFF_SEC
  }

  # Bayat pozitif önbellek geri çekilme penceresinde de KULLANILMAZ; bilinmeyen
  # kid için de yeni istek başlatılmaz.
  if ((pozitif_yenile || kid_yenile) && isTRUE(backoff_taze)) return(NULL)

  if (pozitif_yenile || kid_yenile) {
    fresh_keys <- fetch_fn(jwks_url)
    if (is.null(fresh_keys)) {
      .sso_jwks_cache[[getirme_backoff]] <- list(keys = NULL, fetched_at = now)
    } else {
      .sso_jwks_negative_remove(getirme_backoff)
    }
    if (is.null(fresh_keys) && isTRUE(pozitif_yenile)) {
      # TTL bir TAZELİK sınırıdır: bayat önbellek yenilenemediğinde eski anahtar
      # kullanılmaz. Aksi hâlde JWKS kesintisi sürdükçe Keycloak'ta rotasyona
      # uğramış/iptal edilmiş bir anahtar token doğrulamaya devam ediyordu.
      log_warn("JWKS yenilenemedi ve önbellek bayat; imza anahtarı reddedildi (fail-closed).")
      return(NULL)
    }
    if (!is.null(fresh_keys)) {
      .sso_jwks_cache[[jwks_url]] <- list(keys = fresh_keys, fetched_at = now)
      keys <- fresh_keys
      jwk <- sso_find_jwk_by_kid(keys, kid)
    }

    if (is.null(jwk) && !is.null(fresh_keys)) {
      # Negatif giriş YALNIZCA yenileme gerçekten başarılı olduğunda yazılır.
      # `fetch_fn` taşıma/HTTP hatasında NULL döndürüyor; o durumda kaydedilen
      # negatif giriş, JWKS uç noktası toparlandıktan sonra da geçerli bir
      # tokenı negatif TTL boyunca reddediyordu.
      #
      # SINIR: her benzersiz `kid` için ayrı giriş biriktiğinden, kimliği
      # doğrulanmamış bir istemci sürekli farklı kid göndererek süreç ömrü
      # boyunca önbelleği şişirebiliyordu. Yazmadan önce süresi dolmuş negatif
      # girişler ayıklanır; kapasite hâlâ doluysa EN ESKİ giriş düşürülür,
      # aksi hâlde tüm girişler tazeyken yeni kid hiç önbelleklenmiyor ve her
      # istek JWKS getirmeyi tetikliyordu.
      .sso_jwks_negative_prune(now, negatif_ttl)
      negatif_adlar <- .sso_jwks_negative_names()
      if (length(negatif_adlar) >= .SSO_JWKS_NEGATIVE_CACHE_MAX) {
        yaslar <- vapply(negatif_adlar, function(ad) {
          giris <- .sso_jwks_cache[[ad]]
          zaman <- suppressWarnings(as.numeric(giris$fetched_at))
          if (length(zaman) != 1L || !is.finite(zaman)) -Inf else zaman
        }, numeric(1))
        dusurulecek <- negatif_adlar[order(yaslar)][
          seq_len(length(negatif_adlar) - .SSO_JWKS_NEGATIVE_CACHE_MAX + 1L)
        ]
        rm(list = dusurulecek, envir = .sso_jwks_cache)
      }
      .sso_jwks_cache[[negatif_anahtar]] <- list(keys = NULL, fetched_at = now)
    } else if (!is.null(jwk)) {
      .sso_jwks_negative_remove(negatif_anahtar)
    }
  }

  if (is.null(jwk)) return(NULL)
  sso_jwk_to_public_key(jwk)
}
