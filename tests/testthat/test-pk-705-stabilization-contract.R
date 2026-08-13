# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-705-stabilization-contract.R
# Açıklama: PR #705 inceleme borcunun KÖK NEDEN düzeltmeleri için odaklı
#           regresyon sözleşmeleri. Tümü çevrimdışı ve deterministiktir:
#           gerçek DB, LLM, tarayıcı, SSO, ağ veya gerçek sır KULLANILMAZ.
#
#           Bu dosya semptom başına bir test YAZMAZ; her blok, birden çok
#           inceleme bulgusunun paylaştığı TEK sözleşmeyi korur.
# ==============================================================================

.pk705_env <- function(files) {
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
  for (f in files) source(file.path(kok, "R", f), encoding = "UTF-8", local = env)
  env
}

.pk705_kaynak <- function(rel_path) {
  yol <- file.path(resolve_repo_root_for_tests(), rel_path)
  boyut <- suppressWarnings(file.info(yol)$size[1])
  if (is.na(boyut) || boyut <= 0) return("")
  ham <- readBin(yol, what = "raw", n = boyut)
  metin <- suppressWarnings(iconv(list(ham), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]])
  if (is.na(metin)) return("")
  satirlar <- strsplit(enc2utf8(metin), "\n", fixed = TRUE)[[1]]
  paste(satirlar[!grepl("^\\s*#", satirlar, perl = TRUE)], collapse = "\n")
}

# ==============================================================================
# P0 — MODEL URETIMI METIN R KODU OLARAK CALISTIRILAMAZ
# ==============================================================================

test_that("P0: hicbir filtre yolunda eval(parse()) kalmadi", {
  dosyalar <- c(
    "R/helpers_pk_analysis_filters.R",
    "R/helpers_pk_analysis_filters_base.R",
    "R/helpers_pk_analysis_filters_v2.R",
    "R/helpers_pk_filter_compile.R",
    "R/helpers_pk_filter_policy.R"
  )

  for (dosya in dosyalar) {
    kod <- .pk705_kaynak(dosya)
    expect_false(grepl("eval(parse(", kod, fixed = TRUE, useBytes = TRUE),
                 info = paste(dosya, "icinde eval(parse()) yeniden getirilmis."))
    expect_false(grepl("subset(dt, eval", kod, fixed = TRUE, useBytes = TRUE),
                 info = paste(dosya, "icinde subset(..., eval) yeniden getirilmis."))
  }
})

test_that("P0: cikarim istemi artik calistirilabilir ifade ISTEMEZ", {
  kod <- .pk705_kaynak("R/helpers_pk_analysis_filters_base.R")

  # Model'e "R data.table filtreleme stringi uret" demek, RCE yolunun girdi
  # ucudur. Istem yerine INERT grup yapisini ogretmelidir.
  expect_false(grepl("R data.table filtreleme stringi", kod, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("children", kod, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("ASLA R kodu", kod, fixed = TRUE, useBytes = TRUE))
})

# ==============================================================================
# FILTRE ANLAMBILIMI — TEK DERLEYICI SOZLESMESI
# ==============================================================================

.pk705_filtre_env <- function() {
  .pk705_env(c("helpers_pk_ascii_tokens.R", "helpers_pk_text_turkish.R",
               "helpers_pk_filter_compile.R"))
}

.pk705_veri <- function() {
  data.frame(
    Ad = c("SENTETIK ALFA", "SENTETIK BETA", "SENTETIK GAMA"),
    Durum = c("Aktif", "Pasif", "Aktif"),
    Tutar = c(100, 200, 300),
    stringsAsFactors = FALSE
  )
}

test_that("bilinmeyen islem ve cevrilemeyen deger SESSIZCE esitlige dusmez", {
  env <- .pk705_filtre_env()
  veri <- .pk705_veri()

  bilinmeyen <- env$pk_filter_compile(veri, list(
    list(column = "Tutar", value = "100", operation = "regex_match")
  ))
  expect_length(bilinmeyen$dropped, 1L)
  expect_true(isTRUE(bilinmeyen$all_dropped))

  cevrilemeyen <- env$pk_filter_compile(veri, list(
    list(column = "Tutar", value = "cok", operation = "greater_than")
  ))
  expect_length(cevrilemeyen$dropped, 1L)
  expect_true(isTRUE(cevrilemeyen$all_dropped))
})

test_that("integer64 filtre degerleri double uzerinden KAYBEDILMEZ", {
  skip_if_not_installed("bit64")
  env <- .pk705_filtre_env()

  # 2^53 ustunde ARDISIK iki kimlik: double'a dusurulurse ikisi de ayni
  # degere cokerdi ve filtre YANLIS satiri secerdi.
  veri <- data.frame(Ad = c("a", "b"), stringsAsFactors = FALSE)
  veri$Kimlik <- bit64::as.integer64(c("9007199254740993", "9007199254740994"))

  derleme <- env$pk_filter_compile(veri, list(
    list(column = "Kimlik", value = "9007199254740993", operation = "exact_match")
  ))

  expect_equal(sum(derleme$mask), 1L)
  expect_identical(veri$Ad[derleme$mask], "a")
})

test_that("politika: uygulanamayan filtre TUM kume uzerinden devam ETTIRMEZ", {
  env <- .pk705_env(c("helpers_pk_ascii_tokens.R", "helpers_pk_text_turkish.R",
                      "helpers_pk_filter_compile.R", "helpers_pk_filter_policy.R"))
  veri <- .pk705_veri()

  filtreler <- list(list(column = "Ad", value = "SENTETIK ALFA", operation = "regex_match"))
  derleme <- env$pk_filter_compile(veri, filtreler)
  politika <- env$pk_filter_zero_match_policy(veri, filtreler, derleme, NULL)

  expect_identical(politika$action, "refuse")
  expect_equal(sum(politika$mask), 0L)
})

# ==============================================================================
# KOKEN (PROVENANCE) — ISTEK SAHIPLIGI
# ==============================================================================

test_that("bekleyen koken kaydi YALNIZCA sahibi istek tarafindan tuketilir", {
  env <- .pk705_env(c("helpers_pk_provenance.R"))

  oturum <- list(userData = new.env(parent = emptyenv()))
  env$pk_provenance_clear(oturum, request_id = "A")
  env$pk_provenance_stash(oturum, footer = "\n\nALT-BILGI-A", request_id = "A")

  # Baska bir istegin tamamlanmasi A'nin kaydini ne OKUYABILIR ne SILEBILIR.
  expect_null(env$pk_provenance_take(oturum, request_id = "B"))

  # KIMLIKSIZ cagri da reddedilir: eski davranista bu, o an bekleyen HANGI
  # kayit varsa onu tuketiyordu ve gec biten bir yanit daha yeni bir istegin
  # olgularina gore dogrulanip onun alt bilgisini aliyordu.
  expect_null(env$pk_provenance_take(oturum, request_id = NULL))

  # Sahibi olan istek hala alabilir.
  expect_identical(env$pk_provenance_take(oturum, request_id = "A"), "\n\nALT-BILGI-A")
})

test_that("block kipinde dekorasyon hatasi HAM model metnini yayimlamaz", {
  env <- .pk705_env(c("helpers_pk_provenance.R"))

  oturum <- list(userData = new.env(parent = emptyenv()))
  env$pk_provenance_clear(oturum, request_id = "R1")
  env$pk_provenance_stash(
    oturum, footer = "\n\nALT-BILGI", request_id = "R1",
    facts = list(list(fact_id = "f1")), fallback_text = "DETERMINISTIK-YEDEK",
    mode = "block"
  )

  # Dogrulayici cokerse: kayit ZATEN tuketilmistir, yeniden denenemez. Dogru
  # davranis ham (dogrulanmamis) model metnine dusmek DEGIL, deterministik
  # yedege dusmektir.
  env$pk_numeric_provenance_apply <- function(...) stop("sentetik cokme")

  sonuc <- env$pk_provenance_decorate("DOGRULANMAMIS MODEL METNI", oturum, request_id = "R1")

  expect_false(grepl("DOGRULANMAMIS MODEL METNI", sonuc, fixed = TRUE))
  expect_true(grepl("DETERMINISTIK-YEDEK", sonuc, fixed = TRUE))
})

# ==============================================================================
# RLS — KAPALI BASARISIZ
# ==============================================================================

test_that("uygulanamayan yetki kapsami analizi DURDURUR", {
  env <- .pk705_env(c("helpers_pk_rls.R"))

  plan <- env$pk_rls_plan(
    list(Yetki = "PY", allowed_projects = "P1", scope_state_projects = "available"),
    list(),
    c("BaskaSutun")
  )

  expect_true(isTRUE(plan$abort))
  expect_identical(plan$reason, "unenforceable_column")
})

# ==============================================================================
# YEREL BAGIMSIZ MAKINE BELIRTECLERI
# ==============================================================================

test_that("makine belirtecleri Turkce yerelde de ASCII katlanir", {
  env <- .pk705_env(c("helpers_pk_ascii_tokens.R"))

  # Turkce yerelde `tolower("I")` noktasiz `i` (U+0131) uretir; protokol
  # belirtecleri bundan ETKILENMEMELIDIR.
  expect_identical(env$pk_ascii_lower("CONTAINS"), "contains")
  expect_identical(env$pk_ascii_lower("POSIXct"), "posixct")
  expect_identical(env$pk_ascii_token("  TRUE  "), "true")

  denendi <- tryCatch({
    eski <- Sys.getlocale("LC_CTYPE")
    on.exit(try(Sys.setlocale("LC_CTYPE", eski), silent = TRUE), add = TRUE)
    kuruldu <- suppressWarnings(Sys.setlocale("LC_CTYPE", "tr_TR.UTF-8"))
    if (!nzchar(kuruldu)) FALSE else {
      expect_identical(env$pk_ascii_lower("CONTAINS"), "contains")
      expect_identical(env$pk_ascii_lower("POSIXct"), "posixct")
      TRUE
    }
  }, error = function(e) FALSE)

  skip_if(!denendi, "Turkce yerel bu ortamda ayarlanamadi.")
})

# ==============================================================================
# REDAKSIYON — KAPALI BASARISIZ
# ==============================================================================

test_that("redaksiyon hatasi HAM hata metnine geri dusmez", {
  env <- .pk705_env(c("helpers_pk_safe_errors.R"))
  env$redact_sensitive_text <- function(x) stop("sentetik redaktor cokmesi")

  # Sentetik/sahte bir sir; gercek bir deger DEGILDIR.
  hassas <- paste0("DSN=", "SENTETIK", ";PWD=", "SAHTE123")

  guvenli <- env$pk_safe_error_message(hassas)
  expect_false(grepl("SAHTE123", guvenli, fixed = TRUE))
})
