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

test_that("küme değerli yetki kapsamı DB satır sırasından bağımsızdır", {
  ortam <- .p3_705_source("helpers_pk_cache_key.R")

  # İzin sorgularında `ORDER BY` yoktur: aynı yetki bir istekte
  # `c("P1","P2")`, diğerinde `c("P2","P1")` gelebilir.
  a <- list(authorized = TRUE, allowed_projects = c("P1", "P2"),
            allowed_eps = c("E2", "E1"), allowed_depts = c("D1"), rol = "X")
  b <- list(authorized = TRUE, allowed_projects = c("P2", "P1"),
            allowed_eps = c("E1", "E2"), allowed_depts = c("D1"), rol = "X")
  expect_identical(ortam$pk_cache_rls_signature(a), ortam$pk_cache_rls_signature(b))

  # GERÇEKTEN FARKLI kapsam hâlâ ayrılır (yetki sınırı zayıflamaz).
  dar <- list(authorized = TRUE, allowed_projects = c("P1"),
              allowed_eps = c("E1", "E2"), allowed_depts = c("D1"), rol = "X")
  expect_false(identical(ortam$pk_cache_rls_signature(a),
                         ortam$pk_cache_rls_signature(dar)))

  # Sıra duyarlı (küme olmayan) alanlar DEĞİŞMEDEN kalır.
  s1 <- list(authorized = TRUE, allowed_projects = c("P1"), sirali = c("b", "a"))
  s2 <- list(authorized = TRUE, allowed_projects = c("P1"), sirali = c("a", "b"))
  expect_false(identical(ortam$pk_cache_rls_signature(s1),
                         ortam$pk_cache_rls_signature(s2)))
})

test_that("Türkçe `hayır` yazımı mantıksal yaprağı düşürmez", {
  ortam <- .p3_705_source("helpers_pk_ascii_tokens.R", "helpers_pk_filter_compile.R")

  sutun <- c(TRUE, FALSE, TRUE)
  maske <- ortam$.pk_filter_mask_logical(sutun, list(values = "hayır"))
  expect_identical(maske, c(FALSE, TRUE, FALSE))

  # ASCII yazım ve büyük harf biçimleri de çalışmaya devam eder.
  expect_identical(ortam$.pk_filter_mask_logical(sutun, list(values = "hayir")),
                   c(FALSE, TRUE, FALSE))
  expect_identical(ortam$.pk_filter_mask_logical(sutun, list(values = "HAYIR")),
                   c(FALSE, TRUE, FALSE))
  expect_identical(ortam$.pk_filter_mask_logical(sutun, list(values = "evet")),
                   c(TRUE, FALSE, TRUE))

  # SÖZLÜK DIŞI değer HÂLÂ yaprağı düşürür (FALSE'a çevrilmez).
  expect_null(ortam$.pk_filter_mask_logical(sutun, list(values = "belirsiz")))
})

test_that("kapsayıcı üst sınır YAZ SAATİ geçiş gününde günün tamamını kapsar", {
  ortam <- .p3_705_source("helpers_pk_ascii_tokens.R", "helpers_pk_filter_compile.R")

  # Şili 2024-04-06'da bir saat KAZANIR (25 saatlik gün). Sabit `86399.999`
  # saniye eklemek sınırı günün son saatinden ÖNCE bitiriyordu.
  tz <- "America/Santiago"
  gec_kayit <- as.POSIXct("2024-04-06 23:30:00", tz = tz)
  attr(gec_kayit, "tzone") <- tz

  maske <- ortam$.pk_filter_mask_posix(
    gec_kayit,
    list(values = "2024-04-06", operation = "less_or_equal")
  )
  expect_identical(maske, TRUE)

  # KATI karşılaştırma HÂLÂ gün başında biter.
  kati <- ortam$.pk_filter_mask_posix(
    gec_kayit,
    list(values = "2024-04-06", operation = "less_than")
  )
  expect_identical(kati, FALSE)

  # ERTESİ günün kaydı kapsayıcı sınıra GİRMEZ.
  ertesi_kayit <- as.POSIXct("2024-04-07 00:30:00", tz = tz)
  attr(ertesi_kayit, "tzone") <- tz
  expect_identical(
    ortam$.pk_filter_mask_posix(
      ertesi_kayit, list(values = "2024-04-06", operation = "less_or_equal")
    ),
    FALSE
  )
})

test_that("büyük satır sayıları alt bilgi kurulumunu düşürmez", {
  ortam <- .p3_705_source("helpers_pk_provenance_peek.R", "helpers_pk_provenance.R")

  # 2147483647'nin üzerinde `as.integer()` NA + uyarı üretiyor, ardından
  # `if (NA < 0L)` "missing value where TRUE/FALSE needed" hatası veriyordu.
  expect_identical(ortam$.pk_format_count(3e9), "3.000.000.000")
  expect_identical(ortam$.pk_format_count(1234567), "1.234.567")
  expect_identical(ortam$.pk_format_count(-4567), "-4.567")
  expect_identical(ortam$.pk_format_count(0), "0")
  expect_identical(ortam$.pk_format_count(NA), "?")

  # Uyarı üretilmez (katı test paketi uyarıyı hata sayar).
  expect_silent(ortam$.pk_format_count(5e10))
})

test_that("her red yolu maskeyi kapatır", {
  ortam <- .p3_705_source("helpers_pk_ascii_tokens.R", "helpers_pk_filter_policy.R")

  veri <- data.frame(ProjeAdi = c("ANKA", "ALTAY"), Yil = c(2024, 2024),
                     stringsAsFactors = FALSE)

  # Birincil varlık BİLİNMİYOR ve uygulanan filtre sıfır eşleşti -> RED.
  derlenmis <- list(
    ok = TRUE, all_dropped = FALSE, mask = c(TRUE, TRUE), dropped = list(),
    groups = list(list(column = "ProjeAdi", zero_match = TRUE,
                       applied = list(list(values = "YOKPROJE"))))
  )

  sonuc <- ortam$pk_filter_zero_match_policy(veri, list(), derlenmis, query = NULL)
  expect_identical(sonuc$action, "refuse")
  # `action` denetlemeyen bir tüketici maskeyle TÜM yetkili kümeyi analiz
  # ederdi; maske reddin kendisiyle tutarlı olmalıdır.
  expect_identical(sonuc$mask, c(FALSE, FALSE))
})

test_that("varyant doğrulaması tek sebep için tek bulgu üretir", {
  ortam <- .p3_705_source(
    "helpers_pk_config.R", "helpers_pk_text_turkish.R",
    "helpers_pk_query_meta_schema.R", "helpers_pk_query_meta_access.R",
    "helpers_pk_query_meta_layers.R", "helpers_pk_query_meta.R"
  )

  kayit <- list("labor.remaining_hours" = list(role = "measure", unit = "saat"))
  meta <- list(entity = "project", column_meta = list(
    A = list(label = "A", role = "measure", capability = "labor.remaining_hours",
             unit = "saat", additive = TRUE),
    B = list(label = "B", role = "measure", capability = "labor.remaining_hours",
             unit = "saat", additive = TRUE)
  ))

  # 1) Birden çok sahip, varyant beyanı YOK.
  cok_sahip <- ortam$pk_meta_validate_query("q", meta, kayit)
  expect_length(cok_sahip, 1L)
  expect_true(any(grepl("birden fazla sutunda", cok_sahip, fixed = TRUE)))

  # 2) Geçersiz `prefer`: TEK bulgu (eskiden iki bulgu üretiyordu).
  gecersiz <- meta
  gecersiz$capability_variants <- list("labor.remaining_hours" = list(prefer = "YOK"))
  hatalar <- ortam$pk_meta_validate_query("q", gecersiz, kayit)
  expect_length(hatalar, 1L)
  expect_true(any(grepl("$prefer", hatalar, fixed = TRUE)))

  # 3) Varyant liste değil: TEK bulgu.
  liste_degil <- meta
  liste_degil$capability_variants <- list("labor.remaining_hours" = "metin")
  expect_length(ortam$pk_meta_validate_query("q", liste_degil, kayit), 1L)

  # 4) Geçerli beyan: hiç bulgu yok.
  gecerli <- meta
  gecerli$capability_variants <- list("labor.remaining_hours" = list(prefer = "A"))
  expect_length(ortam$pk_meta_validate_query("q", gecerli, kayit), 0L)
})
