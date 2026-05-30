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
