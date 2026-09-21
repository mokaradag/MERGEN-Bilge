# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-numeric-provenance-contract.R
# Açıklama: Faz 2 — sayısal köken UYGULAMA katmanının KAMUSAL sözleşmesi
#           (§5.11).
#
#           Bu dosya, başka altsistemlerin (akış sonlandırma, Ortak Oturum
#           kancası, derin analiz, telemetri) bağlandığı yüzeyi kilitler:
#             * `MERGEN_PK_NUMERIC_PROVENANCE_MODE` değerleri ve varsayılan,
#             * `pk_numeric_provenance_apply()` dönüş ŞEKLİ,
#             * olgu kimliği/indeks sözleşmesi,
#             * telemetrinin gizlilik ve kategori ayrımı,
#             * kapalı başarısızlık davranışının kipe göre değişmesi.
#
#           Davranışın ayrıntısı `test-pk-fact-reference-behavior.R` ve
#           `test-pk-fact-reference-scan-behavior.R` dosyalarındadır.
#
#           Tümü ÇEVRİMDIŞI ve DETERMİNİSTİKTİR: gerçek DB, LLM, tarayıcı, ağ
#           veya gerçek sır KULLANILMAZ.
# ==============================================================================

.pk_prov_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x

  for (dosya in c("helpers_pk_config.R", "helpers_pk_fact_reference.R",
                  "helpers_pk_fact_reference_scan.R", "helpers_pk_precision.R",
                  "helpers_pk_packet_stats.R", "helpers_pk_packet_context_facts.R",
                  "helpers_pk_numeric_provenance.R")) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = env)
  }
  env
}

# Sentetik olgu kümesi: gerçek proje/program adı içermez.
.pk_prov_facts <- function(env) {
  list(
    env$pk_fact_record("measure", "KalanIscilik_sa", "sum", 18420.5,
                       list(label = "Kalan Iscilik", unit = "saat", decimals = 1L,
                            capability = "labor.remaining_hours")),
    env$pk_fact_record("measure", "TamamlanmaYuzde", "weighted_mean", 61.3,
                       list(label = "Tamamlanma", unit = "%", decimals = 1L,
                            capability = "progress.completion_pct")),
    env$pk_fact_record("measure", "KaynakAdi", "distinct", 47,
                       list(label = "Kaynak", decimals = 0L)),
    env$pk_fact_record("measure", "Butce", "sum", NULL, list(label = "Butce"),
                       status = env$PK_FACT_NO_FINITE)
  )
}

.pk_prov_id <- function(olgular, sutun, agg) {
  bulunan <- Filter(function(o) identical(o$column, sutun) &&
                      identical(o$aggregation, agg), olgular)
  bulunan[[1]]$fact_id
}

# --- Kamusal yapılandırma sözleşmesi -----------------------------------------

test_that("Kip degerleri KORUNUR ve varsayilan 'log'tur", {
  env <- .pk_prov_env()
  testthat::skip_if_not_installed("withr")

  # `log` operasyonel guvenlik agidir ve SESSIZCE kaldirilamaz.
  expect_identical(env$PK_PROV_MODES, c("off", "log", "warn", "block"))

  withr::with_envvar(list(MERGEN_PK_NUMERIC_PROVENANCE_MODE = NA_character_), {
    expect_identical(env$pk_numeric_provenance_mode(), "log")
  })
  withr::with_envvar(list(MERGEN_PK_NUMERIC_PROVENANCE_MODE = "saldirgan"), {
    expect_identical(env$pk_numeric_provenance_mode(), "log")
  })
  for (kip in env$PK_PROV_MODES) {
    withr::with_envvar(list(MERGEN_PK_NUMERIC_PROVENANCE_MODE = kip), {
      expect_identical(env$pk_numeric_provenance_mode(), kip)
    })
  }
})

test_that("Yapilandirma varsayilani ile kod varsayilani AYNIDIR", {
  env <- .pk_prov_env()
  tanim <- env$pk_config_spec[["MERGEN_PK_NUMERIC_PROVENANCE_MODE"]]

  expect_identical(tanim$default, "log")
  expect_identical(tanim$allowed, c("off", "log", "warn", "block"))
})

# --- Dönüş şekli (başka altsistemler bu alanlara bağlanır) -------------------

test_that("apply() dokumante edilen ALANLARI her kipte dondurur", {
  env <- .pk_prov_env()
  olgular <- .pk_prov_facts(env)
  kimlik <- .pk_prov_id(olgular, "KalanIscilik_sa", "sum")
  metin <- paste0("Toplam ", env$pk_fact_reference_token(kimlik), " harcandi.")

  for (kip in env$PK_PROV_MODES) {
    sonuc <- env$pk_numeric_provenance_apply(metin, olgular, mode = kip,
                                             fallback_text = "- Deger")
    for (alan in c("text", "mode", "blocked", "checked", "mismatches", "rate",
                   "references", "resolved", "protocol", "trust", "degraded")) {
      expect_true(alan %in% names(sonuc), info = paste(kip, alan))
    }
    expect_identical(sonuc$mode, kip)
    expect_type(sonuc$text, "character")
    expect_length(sonuc$text, 1L)
    expect_type(sonuc$blocked, "logical")
    # R'nin kanonik gosterimi HER kipte basilir; ic soz dizimi sizmaz.
    expect_true(grepl("18.420,5 saat", sonuc$text, fixed = TRUE), info = kip)
    expect_false(grepl("{{", sonuc$text, fixed = TRUE), info = kip)
  }
})

test_that("bos/NA metin ve bos olgu kumesi guvenle ele alinir", {
  env <- .pk_prov_env()
  for (metin in list("", NA_character_, NULL)) {
    sonuc <- env$pk_numeric_provenance_apply(metin, list(), mode = "log")
    expect_identical(sonuc$text, "")
    expect_length(sonuc$mismatches, 0L)
  }
})

# --- Yuva söz diziminin TEK SAHİBİ -------------------------------------------

test_that("yuva jetonu TEK yardimcidan uretilir ve kanonik desene UYAR", {
  env <- .pk_prov_env()
  jeton <- env$pk_fact_reference_token("olcu.sum.overall.ab12cd")

  expect_identical(jeton, "{{fact:olcu.sum.overall.ab12cd}}")
  expect_true(grepl(env$PK_FACT_REF_PATTERN, jeton, perl = TRUE))
})

test_that("paket yazicisi YALNIZCA kanonik yuva jetonu basar", {
  repo_root <- resolve_repo_root_for_tests()
  kod <- pk_test_code_only_file("R/helpers_pk_packet_render.R")

  # Eski alinti soz dizimi ARTIK URETILMEZ: yazici jetonu tek sahipten alir.
  expect_false(grepl("sprintf(\"[fact:", kod, fixed = TRUE))
  expect_true(grepl("pk_fact_reference_token", kod, fixed = TRUE))

  # Silinen ters-eslestirme dosyalari GERI GELMEZ.
  for (eski in c("R/helpers_pk_numeric_provenance_binding.R",
                 "R/helpers_pk_numeric_provenance_claims.R")) {
    expect_false(file.exists(file.path(repo_root, eski)), info = eski)
  }
})

# --- Olgu kimliği / indeks sözleşmesi ----------------------------------------

test_that("Olgu indeksi kimlige gore kurulur; CAKISAN kimlik cozulemez olur", {
  env <- .pk_prov_env()
  olgular <- .pk_prov_facts(env)
  index <- env$pk_facts_index(olgular)
  kimlik <- .pk_prov_id(olgular, "KalanIscilik_sa", "sum")

  # Kimlik ASCII protokol jetonudur (Windows/VM ayristirici dayanikliligi).
  expect_true(all(grepl("^[A-Za-z0-9_.]+$", names(index))))
  expect_equal(index[[kimlik]]$value, 18420.5)

  catisan <- index[[kimlik]]
  catisan$value <- 999
  catisan$display <- "999"
  catisan$column <- "BaskaSutun"
  cakisik <- env$pk_facts_index(list(index[[kimlik]], catisan))

  expect_null(cakisik[[kimlik]]$value)
  expect_identical(cakisik[[kimlik]]$status, "ambiguous_fact_id")
  expect_true(is.na(env$pk_fact_display_value(cakisik[[kimlik]])))
})

test_that("degeri olmayan olgu HICBIR gosterim uretmez", {
  env <- .pk_prov_env()
  olgular <- .pk_prov_facts(env)
  bos <- Filter(function(o) identical(o$column, "Butce"), olgular)[[1]]

  expect_null(bos$value)
  expect_true(is.na(env$pk_fact_display_value(bos)))
})

# --- Telemetri: kategori ayrımı ve gizlilik ----------------------------------

test_that("Telemetri PROTOKOL ve GUVEN bulgularini ayri raporlar, sir yazmaz", {
  env <- .pk_prov_env()
  olgular <- .pk_prov_facts(env)

  sonuc <- env$pk_numeric_provenance_apply(
    "Gizli proje adi ve 99.999,9 saat degerlendirildi.", olgular, mode = "log"
  )
  birlesik <- paste(utils::capture.output(
    env$pk_numeric_provenance_report(sonuc, "q_sentetik")
  ), collapse = "\n")

  expect_true(grepl("Olgu referansi", birlesik, fixed = TRUE))
  expect_true(grepl("protokol=1", birlesik, fixed = TRUE))
  expect_true(grepl("guven=0", birlesik, fixed = TRUE))
  expect_true(grepl("model_numeric_literal", birlesik, fixed = TRUE))
  # Duzyazi ve ham is degeri LOGA GIRMEZ.
  expect_false(grepl("Gizli proje adi", birlesik, fixed = TRUE))
  expect_false(grepl("99.999,9", birlesik, fixed = TRUE))
})

test_that("Bulgu yoksa oran sifirdir; off kipi HIC rapor yazmaz", {
  env <- .pk_prov_env()
  olgular <- .pk_prov_facts(env)

  sonuc <- env$pk_numeric_provenance_apply("Tamamen niteliksel bir degerlendirme.",
                                           olgular, mode = "log")
  expect_equal(sonuc$references, 0L)
  expect_equal(sonuc$rate, 0)
  cikti <- paste(utils::capture.output(env$pk_numeric_provenance_report(sonuc)),
                 collapse = "\n")
  expect_true(grepl("referans=0", cikti, fixed = TRUE))

  kapali <- env$pk_numeric_provenance_apply("Metin.", olgular, mode = "off")
  expect_length(utils::capture.output(env$pk_numeric_provenance_report(kapali)), 0L)
})

test_that("Raporlanan olgu kimlikleri SINIRLIDIR", {
  env <- .pk_prov_env()
  bulgular <- lapply(seq_len(20L), function(i) {
    list(reason = "unknown_fact", category = "trust",
         fact_id = sprintf("olcu%02d.sum.overall.aaaaaa", i))
  })
  sahte <- list(mode = "log", references = 20L, resolved = 0L, protocol = 0L,
                trust = 20L, rate = 1, mismatches = bulgular)

  cikti <- paste(utils::capture.output(
    env$pk_numeric_provenance_report(sahte, "q")
  ), collapse = "\n")
  expect_true(grepl(",...", cikti, fixed = TRUE))
})

# --- Kapalı başarısızlık kipe göre değişir -----------------------------------

test_that("Cozumleyici cokmesinde log/off TESLIM EDER, warn/block KAPALI BASARISIZ olur", {
  env <- .pk_prov_env()
  env$pk_numeric_provenance_validate <- function(text, facts) stop("sentetik cokme")
  metin <- "Model tarafindan uretilmis dogal analiz metni."

  for (kip in c("off", "log")) {
    sonuc <- env$pk_numeric_provenance_apply(metin, list(), mode = kip)
    expect_identical(sonuc$text, metin, info = kip)
    expect_false(sonuc$blocked, info = kip)
    expect_true(sonuc$degraded, info = kip)
  }

  uyari <- env$pk_numeric_provenance_apply(metin, list(), mode = "warn")
  expect_false(uyari$blocked)
  expect_true(grepl("Doğrulama notu", uyari$text))

  bloklu <- env$pk_numeric_provenance_apply(metin, list(), mode = "block",
                                            fallback_text = "- Hesaplanan deger")
  expect_true(bloklu$blocked)
  expect_false(grepl("dogal analiz metni", bloklu$text, fixed = TRUE))
  expect_true(grepl("- Hesaplanan deger", bloklu$text, fixed = TRUE))
})
