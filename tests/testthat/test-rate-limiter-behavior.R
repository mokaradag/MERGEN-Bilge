# ==============================================================================
# Dosya Yolu: tests/testthat/test-rate-limiter-behavior.R
# Açıklama: R/utils_rate_limiter.R hız sınırlandırma DAVRANIŞSAL testleri:
#           check_rate_limit (kullanıcı başına) ve check_global_rate_limit
#           (sistem geneli). Durum, modül düzeyindeki ortamlarda (rate_limiter
#           ve global_rate_limiter) tutulduğundan testler izole başlangıç yapar
#           ve sonunda durumu temizler/eski haline döndürür. Ağ/DB/Shiny/future
#           GEREKMEZ; gerçek fonksiyonlar çağrılır.
# ==============================================================================

.ratelimit_source_once <- function() {
  if (exists("check_rate_limit", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("check_global_rate_limit", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "utils_rate_limiter.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# `rate_limiter` bir LİSTEdir: `rate_limiter$max_users_cache <- n` yalnızca test
# çerçevesinde yerel bir kopya üretir ve üretim kodu eski kapasiteyi görür.
# (`requests`/`cleanup_state` ORTAM olduğu için referansla paylaşılır.)
.ratelimit_set_kapasite <- function(n) {
  rl <- get("rate_limiter", envir = globalenv())
  rl$max_users_cache <- n
  assign("rate_limiter", rl, envir = globalenv())
  invisible(n)
}

# ------------------------------------------------------------------------------
# check_rate_limit (kullanıcı başına)
# ------------------------------------------------------------------------------
testthat::test_that("check_rate_limit kullanıcı limitine kadar TRUE, sonra FALSE döner", {
  .ratelimit_source_once()

  uid <- "tt_rate_limit_user_unique_001"
  limit <- rate_limiter$max_requests_per_user
  # İzole başlangıç: bu test kullanıcısının kaydını temizle.
  if (exists(uid, envir = rate_limiter$requests, inherits = FALSE)) {
    rm(list = uid, envir = rate_limiter$requests)
  }

  # İlk `limit` istek izinli (pencere içinde, test anlık çalışır).
  ilk_sonuclar <- vapply(seq_len(limit), function(i) check_rate_limit(uid), logical(1))
  testthat::expect_true(all(ilk_sonuclar))

  # Limit aşıldığında reddedilir.
  testthat::expect_false(check_rate_limit(uid))

  # Temizlik: test kullanıcısının kaydını kaldır.
  if (exists(uid, envir = rate_limiter$requests, inherits = FALSE)) {
    rm(list = uid, envir = rate_limiter$requests)
  }
})

testthat::test_that("check_rate_limit farklı kullanıcıların kotalarını ayrı tutar", {
  .ratelimit_source_once()

  uid_a <- "tt_rate_limit_user_AA"
  uid_b <- "tt_rate_limit_user_BB"
  for (u in c(uid_a, uid_b)) {
    if (exists(u, envir = rate_limiter$requests, inherits = FALSE)) {
      rm(list = u, envir = rate_limiter$requests)
    }
  }

  # A kullanıcısı limitini doldurur.
  invisible(vapply(seq_len(rate_limiter$max_requests_per_user),
                   function(i) check_rate_limit(uid_a), logical(1)))
  testthat::expect_false(check_rate_limit(uid_a))   # A bloklandı
  # B kullanıcısı hâlâ izinli.
  testthat::expect_true(check_rate_limit(uid_b))

  for (u in c(uid_a, uid_b)) {
    if (exists(u, envir = rate_limiter$requests, inherits = FALSE)) {
      rm(list = u, envir = rate_limiter$requests)
    }
  }
})

testthat::test_that("check_rate_limit süresi dolmuş kayıt varken yeni kullanıcıyı kabul eder", {
  .ratelimit_source_once()

  eski_kapasite <- rate_limiter$max_users_cache
  eski_anahtarlar <- ls(envir = rate_limiter$requests)
  eski_kayitlar <- mget(eski_anahtarlar, envir = rate_limiter$requests)
  eski_temizlik <- rate_limiter$cleanup_state$last_cleanup
  eski_sona_erme <- rate_limiter$cleanup_state$next_expiry
  withr::defer({
    rm(list = ls(envir = rate_limiter$requests), envir = rate_limiter$requests)
    for (ad in names(eski_kayitlar)) {
      rate_limiter$requests[[ad]] <- eski_kayitlar[[ad]]
    }
    .ratelimit_set_kapasite(eski_kapasite)
    rate_limiter$cleanup_state$last_cleanup <- eski_temizlik
    rate_limiter$cleanup_state$next_expiry <- eski_sona_erme
  })

  rm(list = ls(envir = rate_limiter$requests), envir = rate_limiter$requests)
  rate_limiter$cleanup_state$last_cleanup <- NULL
  rate_limiter$cleanup_state$next_expiry <- NULL
  .ratelimit_set_kapasite(3L)

  # Kayıtlar İLK çağrıda hâlâ CANLI; 0.3 sn sonra süreleri dolar.
  for (i in seq_len(3L)) {
    rate_limiter$requests[[paste0("tt_expired_", i)]] <-
      list(Sys.time() - (rate_limiter$window_size - 0.2))
  }

  # İlk çağrı: kapasite dolu ve tüm kayıtlar canlı -> reddedilir, tam tarama
  # damgası ŞİMDİ olur (bir saniyelik kelepçe devreye girer).
  testthat::expect_false(check_rate_limit("tt_rate_limit_new_user_001"))

  Sys.sleep(0.3)

  # Kelepçe penceresi içindeyiz ama kayıtların süresi DOLDU. Eski davranış
  # taramayı atlayıp yeni kullanıcıyı kalıcı olarak reddediyordu.
  testthat::expect_true(check_rate_limit("tt_rate_limit_new_user_001b"))
  testthat::expect_false(exists("tt_expired_1", envir = rate_limiter$requests,
                                inherits = FALSE))
})

testthat::test_that("check_rate_limit tüm kayıtlar canlıyken kapasitede reddeder", {
  .ratelimit_source_once()

  eski_kapasite <- rate_limiter$max_users_cache
  eski_anahtarlar <- ls(envir = rate_limiter$requests)
  eski_kayitlar <- mget(eski_anahtarlar, envir = rate_limiter$requests)
  eski_temizlik <- rate_limiter$cleanup_state$last_cleanup
  eski_sona_erme <- rate_limiter$cleanup_state$next_expiry
  withr::defer({
    rm(list = ls(envir = rate_limiter$requests), envir = rate_limiter$requests)
    for (ad in names(eski_kayitlar)) {
      rate_limiter$requests[[ad]] <- eski_kayitlar[[ad]]
    }
    .ratelimit_set_kapasite(eski_kapasite)
    rate_limiter$cleanup_state$last_cleanup <- eski_temizlik
    rate_limiter$cleanup_state$next_expiry <- eski_sona_erme
  })

  rm(list = ls(envir = rate_limiter$requests), envir = rate_limiter$requests)
  rate_limiter$cleanup_state$last_cleanup <- NULL
  rate_limiter$cleanup_state$next_expiry <- NULL
  .ratelimit_set_kapasite(3L)

  for (i in seq_len(3L)) {
    rate_limiter$requests[[paste0("tt_live_", i)]] <- list(Sys.time())
  }

  testthat::expect_false(check_rate_limit("tt_rate_limit_new_user_002"))
  # Tarama bir sonraki sona erme anını saklar; kelepçe ancak o ana kadar geçerli.
  testthat::expect_true(inherits(rate_limiter$cleanup_state$next_expiry, "POSIXct"))
})

# ------------------------------------------------------------------------------
# check_global_rate_limit (sistem geneli)
# ------------------------------------------------------------------------------
testthat::test_that("check_global_rate_limit toplam limite kadar izin verir, sonra mesajla reddeder", {
  .ratelimit_source_once()

  # İzole başlangıç: mevcut global durumu sakla, sıfırla.
  eski_istekler <- global_rate_limiter$requests
  global_rate_limiter$requests <- list()

  limit <- global_rate_limiter$max_total_requests
  ilk <- vapply(seq_len(limit), function(i) check_global_rate_limit()$allowed, logical(1))
  testthat::expect_true(all(ilk))

  # Limit dolunca reddedilir ve kullanıcıya mesaj verilir.
  reddedilen <- check_global_rate_limit()
  testthat::expect_false(reddedilen$allowed)
  testthat::expect_true(is.character(reddedilen$message) && nzchar(reddedilen$message))

  # İzin verilen yanıt mesajsızdır (NULL).
  global_rate_limiter$requests <- list()
  izinli <- check_global_rate_limit()
  testthat::expect_true(izinli$allowed)
  testthat::expect_null(izinli$message)

  # Eski global durumu geri yükle (sızıntı yok).
  global_rate_limiter$requests <- eski_istekler
})
