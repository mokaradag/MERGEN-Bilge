# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-review-705-p3-regressions.R
# Açıklama: PR #705 P3 inceleme bulgularının çalışma zamanı davranış
#           regresyonları. Çevrimdışı ve deterministiktir: gerçek DB, LLM,
#           tarayıcı, SSO veya ağ ERİŞİMİ YOKTUR.
# ==============================================================================

.p3_705_source <- function(...) {
  kok <- resolve_repo_root_for_tests()
  ortam <- new.env(parent = globalenv())
  if (!exists("%||%", envir = ortam, mode = "function", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = ortam)
  }
  for (dosya in c(...)) {
    source(file.path(kok, "R", dosya), encoding = "UTF-8", local = ortam)
  }
  ortam
}

test_that("geçersiz havuz boyutu NA yerine varsayılana düşer", {
  ortam <- .p3_705_source("helpers_db_pool.R")

  eski <- Sys.getenv(c("MERGEN_DB_POOL_MAX_SIZE", "MERGEN_DB_POOL_MIN_SIZE"),
                     unset = NA_character_, names = TRUE)
  on.exit({
    for (anahtar in names(eski)) {
      if (is.na(eski[[anahtar]])) Sys.unsetenv(anahtar)
      else do.call(Sys.setenv, stats::setNames(list(eski[[anahtar]]), anahtar))
    }
  }, add = TRUE)

  # `as.integer(Inf)` NA üretir; `max(1L, NA)` de NA döner ve `pool::dbPool()`
  # NA `maxSize` ile açılamaz (fail_fast açıkken boot durur).
  Sys.setenv(MERGEN_DB_POOL_MAX_SIZE = "Inf", MERGEN_DB_POOL_MIN_SIZE = "1e30")
  bozuk <- ortam$db_pool_config()
  expect_false(is.na(bozuk$max_size))
  expect_false(is.na(bozuk$min_size))
  expect_identical(bozuk$admission_cap, 8L)

  # Geçerli değerler AYNEN korunur.
  Sys.setenv(MERGEN_DB_POOL_MAX_SIZE = "4", MERGEN_DB_POOL_MIN_SIZE = "2")
  saglam <- ortam$db_pool_config()
  expect_identical(saglam$admission_cap, 4L)
  expect_identical(saglam$min_size, 2L)
})

test_that("kodlama kurtarma vektörel geçişte aynı sonucu üretir", {
  ortam <- .p3_705_source("helpers_pk_analysis_core_impl.R")

  latin_bayt <- rawToChar(as.raw(c(0x54, 0xFC, 0x72)))  # WINDOWS-1254 "Tür"
  girdi <- c("Türkçe", NA, "", "plain", latin_bayt)
  cikti <- ortam$normalize_pk_text_utf8(girdi)

  expect_length(cikti, length(girdi))
  expect_identical(cikti[1], "Türkçe")
  expect_true(is.na(cikti[2]))
  expect_identical(cikti[3], "")
  expect_identical(cikti[4], "plain")
  expect_false(is.na(cikti[5]))

  # Boş vektör ve faktör girdisi düşmez.
  expect_length(ortam$normalize_pk_text_utf8(character(0)), 0L)
  expect_identical(ortam$normalize_pk_text_utf8(factor(c("Ürün", "Şey"))),
                   c("Ürün", "Şey"))
})

test_that("çözülemeyen sistem saat dilimi as.Date'e NA olarak GEÇMEZ", {
  ortam <- .p3_705_source("helpers_pk_analysis_packet.R")

  # `Sys.timezone()` platform saat dilimi çözülemediğinde `NA_character_`
  # döner ve depo `%||%` operatörü (yalnız `is.null`) NA'yı geçirir.
  # `as.Date(..., tz = NA)` DAVRANIŞI TANIMSIZDIR (bazı platformlarda
  # "invalid 'tz' value'"). Sözleşme: NA asla `tz` argümanına ulaşmaz.
  gecen_tz <- new.env(parent = emptyenv())
  gecen_tz$deger <- "AYARLANMADI"
  ortam$as.Date <- function(x, tz, ...) {
    if (!missing(tz)) gecen_tz$deger <- tz
    base::as.Date(x, tz = if (missing(tz)) "UTC" else tz, ...)
  }

  ortam$Sys.timezone <- function(...) NA_character_
  degerler <- as.POSIXct(c("2024-03-01 00:30:00", "2024-03-01 23:30:00"), tz = "UTC")
  attr(degerler, "tzone") <- NULL

  sonuc <- ortam$.pk_as_date_safe(degerler)
  expect_identical(gecen_tz$deger, "UTC")
  expect_s3_class(sonuc, "Date")
  expect_length(sonuc, 2L)

  # `Sys.timezone()` PATLADIĞINDA da yedek UTC'dir.
  gecen_tz$deger <- "AYARLANMADI"
  ortam$Sys.timezone <- function(...) stop("saat dilimi çözülemedi")
  expect_s3_class(ortam$.pk_as_date_safe(degerler), "Date")
  expect_identical(gecen_tz$deger, "UTC")

  # Açık `tzone` HÂLÂ korunur.
  gecen_tz$deger <- "AYARLANMADI"
  ortam$Sys.timezone <- function(...) "UTC"
  tanimli <- as.POSIXct("2024-03-01 00:30:00", tz = "Europe/Istanbul")
  expect_identical(ortam$.pk_as_date_safe(tanimli), as.Date("2024-03-01"))
  expect_identical(gecen_tz$deger, "Europe/Istanbul")
})

test_that("RLS durdurma mesajı son tarihi kullanıcı iptali olarak raporlamaz", {
  ortam <- .p3_705_source("helpers_pk_analysis_security_summary.R")

  ortam$pk_async_halt_message <- function(status) {
    if (identical(as.character(status)[1], "deadline")) "ZAMAN_ASIMI" else "IPTAL"
  }
  ortam$pk_deadline_expired <- function(deadline_at) TRUE
  ortam$pk_cancel_token_is_signalled <- function(token_path) FALSE

  eski <- options(mergen.pk.async.deadline_at = Sys.time() - 5,
                  mergen.pk.async.cancel_token = NULL)
  on.exit(options(eski), add = TRUE)

  # `pk_active_stage_halt` YÜKLÜ DEĞİL: son tarih dalı yine de çalışmalıdır.
  expect_identical(ortam$pk_rls_halt_message(list(reason = NULL)), "ZAMAN_ASIMI")

  # Son tarih seçeneği HİÇ ayarlanmamış geçen-süre bütçesi durdurması da
  # zaman aşımıdır; kullanıcı iptal jetonunu tetiklemedi.
  options(mergen.pk.async.deadline_at = NULL)
  expect_identical(ortam$pk_rls_halt_message(list(reason = NULL)), "ZAMAN_ASIMI")

  # GERÇEK kullanıcı iptali hâlâ iptal metnini alır.
  ortam$pk_cancel_token_is_signalled <- function(token_path) TRUE
  options(mergen.pk.async.cancel_token = "jeton")
  expect_identical(ortam$pk_rls_halt_message(list(reason = NULL)), "IPTAL")
})

test_that("atomik kimlik çözümleyici sonucu derin analizi düşürmez", {
  ortam <- .p3_705_source("helpers_deep_analysis_sql.R")

  # `$` atomik vektörde hata verir; fail-closed kimlik mesajı yutulurdu.
  sonuc <- ortam$pk_deep_resolve_username(NULL, resolver = function(session) FALSE)
  expect_false(isTRUE(sonuc$ready))
  expect_identical(sonuc$reason, "unknown")
  expect_true(nzchar(sonuc$message))

  metin <- ortam$pk_deep_resolve_username(NULL, resolver = function(session) "bozuk")
  expect_identical(metin$reason, "unknown")

  # Yapılandırılmış liste sonucu DEĞİŞMEZ.
  yapili <- ortam$pk_deep_resolve_username(
    NULL, resolver = function(session) list(ready = FALSE, reason = "sso_pending")
  )
  expect_identical(yapili$reason, "sso_pending")
})
