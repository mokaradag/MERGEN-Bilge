# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-fact-reference-hardening-behavior.R
# Açıklama: §5.11 anlamsal olgu referansı — KAPALI BAŞARISIZLIK ve yuva
#           sözleşmesinin uç durumları: kapanmamış/eski işaret, birim çatışması,
#           yinelenen sayı, `warn` notu, bozulma yolu, IQR sınırları, bütçe
#           aşımı özeti, istem örnekleri ve deterministik tablo hücreleri.
#
#           Tümü ÇEVRİMDIŞI ve DETERMİNİSTİKTİR: gerçek DB, LLM, tarayıcı, ağ
#           veya gerçek sır KULLANILMAZ.
# ==============================================================================

.pk_hard_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x

  for (dosya in c("helpers_pk_config.R", "helpers_pk_fact_reference.R",
                  "helpers_pk_fact_reference_scan.R", "helpers_pk_precision.R",
                  "helpers_pk_packet_stats.R", "helpers_pk_packet_context_facts.R",
                  "helpers_pk_packet_keys.R", "helpers_pk_packet_render.R",
                  "helpers_pk_numeric_provenance.R", "helpers_pk_analysis_prompts.R",
                  "helpers_pk_answer_compose.R", "helpers_pk_answer_facts_summary.R")) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = env)
  }
  env
}

# Sentetik olgular: gerçek proje/program adı içermez.
.pk_hard_facts <- function(env) {
  list(
    env$pk_fact_record("measure", "GecikenAktivite", "sum", 15448,
                       list(label = "Geciken aktivite", decimals = 0L)),
    env$pk_fact_record("measure", "KalanIscilik", "sum", 18420.5,
                       list(label = "Kalan iscilik", unit = "saat", decimals = 1L))
  )
}

.pk_hard_token <- function(env, olgular, i) env$pk_fact_reference_token(olgular[[i]]$fact_id)

.pk_hard_reasons <- function(sonuc) {
  vapply(sonuc$mismatches, function(m) as.character(m$reason)[1], character(1))
}

# ---------------------------------------------------------------------------
# 1) KAPANMAMIŞ ve ESKİ işaretler kaynaksız iddiayı yayımlatmaz
# ---------------------------------------------------------------------------

test_that("kapanmamis yuva acicisi bozuk referanstir ve block kipinde cumle duser", {
  env <- .pk_hard_env()
  olgular <- .pk_hard_facts(env)
  metin <- paste0("Genel gorunum dengeli. Toplam 47 proje {{fact:bogus")

  log <- env$pk_numeric_provenance_apply(metin, olgular, mode = "log")
  expect_true("malformed_reference" %in% .pk_hard_reasons(log))
  expect_false(grepl("{{", log$text, fixed = TRUE))

  blok <- env$pk_numeric_provenance_apply(metin, olgular, mode = "block")
  expect_true(grepl("Genel gorunum dengeli.", blok$text, fixed = TRUE))
  expect_false(grepl("47 proje", blok$text, fixed = TRUE))

  # Windows satir sonu (CRLF) acicinin taninmasini engellemez.
  crlf <- env$pk_numeric_provenance_apply("Tamam.\r\nToplam 47 proje {{fact:bogus\r\nSon.",
                                          olgular, mode = "block")
  expect_false(grepl("{{", crlf$text, fixed = TRUE))
  expect_false(grepl("47 proje", crlf$text, fixed = TRUE))
  expect_true(grepl("Son.", crlf$text, fixed = TRUE))
})

test_that("eski isaretli kaynaksiz iddia block kipinde ayiklanir", {
  env <- .pk_hard_env()
  olgular <- .pk_hard_facts(env)
  blok <- env$pk_numeric_provenance_apply(
    "Genel gorunum dengeli. Toplam 47 proje [fact:bogus] gecikti.", olgular, mode = "block"
  )
  expect_true(grepl("Genel gorunum dengeli.", blok$text, fixed = TRUE))
  expect_false(grepl("47 proje", blok$text, fixed = TRUE))
  expect_false(grepl("[fact:", blok$text, fixed = TRUE))
})

test_that("yuvaya bitisik eski isaret KURTARILABILIR: cumle ve not korunur", {
  env <- .pk_hard_env()
  olgular <- .pk_hard_facts(env)
  metin <- paste0("Toplam ", .pk_hard_token(env, olgular, 1),
                  " [fact:x] geciken aktivite var.")

  blok <- env$pk_numeric_provenance_apply(metin, olgular, mode = "block")
  expect_identical(blok$text, "Toplam 15.448 geciken aktivite var.")

  uyari <- env$pk_numeric_provenance_apply(metin, olgular, mode = "warn")
  expect_true("legacy_reference" %in% .pk_hard_reasons(uyari))
  expect_false(grepl("Doğrulama notu", uyari$text))
})

# ---------------------------------------------------------------------------
# 2) YİNELENEN SAYI ve `warn` NOTU
# ---------------------------------------------------------------------------

test_that("yinelenen sayi silinirken siradan sozcuk KORUNUR", {
  env <- .pk_hard_env()
  olgular <- .pk_hard_facts(env)
  sonuc <- env$pk_numeric_provenance_apply(
    paste0("Toplam 15.448 aktivite ", .pk_hard_token(env, olgular, 1), " gecikti."),
    olgular, mode = "log"
  )
  expect_true(grepl("aktivite", sonuc$text, fixed = TRUE))
  expect_identical(sonuc$mismatches[[1]]$reason, "duplicate_numeric_literal")
  expect_false(grepl("15.448 aktivite 15.448", sonuc$text, fixed = TRUE))
})

test_that("warn notu yalnizca KURTARILAMAZ bulgular icin gorunur", {
  env <- .pk_hard_env()
  olgular <- .pk_hard_facts(env)
  cozulmus <- env$pk_numeric_provenance_apply(
    paste0("Toplam 15.448 ", .pk_hard_token(env, olgular, 1), " geciken aktivite."),
    olgular, mode = "warn"
  )
  expect_identical(cozulmus$text, "Toplam 15.448 geciken aktivite.")
  expect_identical(cozulmus$protocol, 1L)

  sorunlu <- env$pk_numeric_provenance_apply(
    "Sonuc {{fact:uydurma.sum.overall.ffffff}} olarak olculdu.", olgular, mode = "warn"
  )
  expect_true(grepl("Doğrulama notu", sorunlu$text))
})

# ---------------------------------------------------------------------------
# 3) BİRİM ÇATIŞMASI — kimlik doğru, anlam yanlış
# ---------------------------------------------------------------------------

test_that("birimsiz olguya para birimi ilistirmek guven bulgusudur", {
  env <- .pk_hard_env()
  olgular <- .pk_hard_facts(env)
  metin <- paste0("Genel gorunum dengeli. Toplam butce ",
                  .pk_hard_token(env, olgular, 1), " TL oldu.")

  log <- env$pk_numeric_provenance_apply(metin, olgular, mode = "log")
  expect_true("unit_conflict" %in% .pk_hard_reasons(log))
  expect_identical(log$trust, 1L)

  blok <- env$pk_numeric_provenance_apply(metin, olgular, mode = "block")
  expect_identical(blok$text, "Genel gorunum dengeli.")
})

test_that("olgunun KENDI birimiyle celisen birim yakalanir, uyumlu sozcuk yakalanmaz", {
  env <- .pk_hard_env()
  olgular <- .pk_hard_facts(env)
  celiski <- env$pk_numeric_provenance_apply(
    paste0("Kalan is ", .pk_hard_token(env, olgular, 2), " gun."), olgular, mode = "log"
  )
  expect_true("unit_conflict" %in% .pk_hard_reasons(celiski))

  dogal <- env$pk_numeric_provenance_apply(
    paste0("Toplam ", .pk_hard_token(env, olgular, 1), " geciken aktivite var."),
    olgular, mode = "log"
  )
  expect_length(dogal$mismatches, 0L)
})

# ---------------------------------------------------------------------------
# 4) BİÇİM ve İSTEK DEĞERİ
# ---------------------------------------------------------------------------

test_that("negatif yuzdede eksi isareti yuzde simgesinin ONUNDEDIR", {
  env <- .pk_hard_env()
  expect_identical(env$pk_fmt_number(-61.3, 1L, "%"), "-%61,3")
  expect_identical(env$pk_fmt_number(61.3, 1L, "%"), "%61,3")
})

test_that("istek olgusunun sayisal degeri binlik ayracini ondalik SANMAZ", {
  env <- .pk_hard_env()
  paket <- list(filters = list(applied = list(
    list(column = "Butce", operation = "greater_than", values = "12.500")
  )), scope = list(scope_signature = "sentetik"))
  olgu <- env$pk_packet_request_facts(paket)[[1]]
  expect_equal(olgu$value, 12500)
})

# ---------------------------------------------------------------------------
# 5) IQR SINIRLARI da yuvalıdır ve olgu dizininde bulunur
# ---------------------------------------------------------------------------

test_that("IQR uc deger notundaki sinirlar yuvayla basilir ve cozulur", {
  env <- .pk_hard_env()
  olgular <- env$pk_measure_facts(c(1, 2, 3, 4, 5, 6, 7, 8, 100), "Saat",
                                  list(label = "Saat", decimals = 1L))
  paket <- list(facts = olgular, scope = list(scope_signature = "sentetik"),
                coverage = list(rows = 9L, columns = 1L))
  metin <- env$.pk_render_facts(paket)
  satir <- grep("IQR uc deger", strsplit(metin, "\n", fixed = TRUE)[[1]], value = TRUE)
  expect_length(satir, 1L)
  expect_true(grepl("Sinirlar:", satir, fixed = TRUE))

  jetonlar <- regmatches(satir, gregexpr(env$PK_FACT_REF_PATTERN, satir, perl = TRUE))[[1]]
  expect_length(jetonlar, 3L)  # sayim + iki sinir
  kimlikler <- vapply(env$pk_packet_all_facts(paket), function(o) o$fact_id, character(1))
  cozulen <- gsub("^\\{\\{fact:|\\}\\}$", "", jetonlar)
  expect_identical(setdiff(cozulen, kimlikler), character(0))

  # Modelin ELLE yazmak zorunda kalacagi yuvasiz sinir sayisi kalmaz.
  tarama <- env$pk_fact_literal_scan(sub("^.*Sinirlar:", "", satir), character(0))
  degerler <- vapply(tarama$tokens, function(j) j$raw, character(1))
  sinir_goruntuleri <- vapply(Filter(function(o) o$aggregation %in% c("iqr_lower", "iqr_upper"),
                                     env$pk_packet_all_facts(paket)),
                              function(o) o$display, character(1))
  expect_length(sinir_goruntuleri, 2L)
  for (g in sinir_goruntuleri) expect_true(grepl(g, satir, fixed = TRUE))
  expect_true(all(degerler %in% sinir_goruntuleri))
})

# ---------------------------------------------------------------------------
# 6) BÜTÇE AŞIMI ÖZETİ ve İSTEM ÖRNEKLERİ
# ---------------------------------------------------------------------------

test_that("isteme giden butce asimi ozeti DEGER degil YUVA tasir", {
  env <- .pk_hard_env()
  olgular <- .pk_hard_facts(env)
  ozet <- env$pk_compose_facts_prompt_summary(olgular)
  expect_true(grepl(.pk_hard_token(env, olgular, 1), ozet, fixed = TRUE))
  expect_false(grepl("15.448", ozet, fixed = TRUE))
  expect_false(grepl("18.420,5", ozet, fixed = TRUE))

  # Kullaniciya giden deterministik ozet DEGERI tasir, yuva tasimaz.
  kullanici <- env$pk_compose_facts_summary(olgular)
  expect_true(grepl("15.448", kullanici, fixed = TRUE))
  expect_false(grepl("{{fact:", kullanici, fixed = TRUE))

  # Sonuc kurucusu butce asiminda yuvali ozeti kullanir.
  kod <- pk_test_code_only_file("R/helpers_pk_analysis_result.R")
  expect_true(grepl("pk_compose_facts_prompt_summary(paket$facts)", kod, fixed = TRUE))
})

test_that("istem metinleri kopyalanabilir KANONIK ornek jeton tasimaz", {
  env <- .pk_hard_env()
  kanonik <- env$PK_FACT_REF_PATTERN
  for (kip in c("summary", "full")) {
    istem <- env$pk_build_analysis_system_prompt_v2(kip, list(name = "q", description = "d"))
    expect_false(grepl(kanonik, istem, perl = TRUE), info = kip)
    expect_true(grepl("{{fact:", istem, fixed = TRUE), info = kip)
  }
})

# ---------------------------------------------------------------------------
# 7) DETERMİNİSTİK TABLO HÜCRELERİ tek süslü parantezi korur
# ---------------------------------------------------------------------------

test_that("tablo hucresi tek suslu parantezi KORUR, yuva soz dizimini bozar", {
  env <- .pk_hard_env()
  expect_identical(env$.pk_compose_escape("Proje {A-17}")$text, "Proje {A-17}")
  expect_identical(env$.pk_compose_escape('{"durum":"aktif"}')$text, '{"durum":"aktif"}')
  expect_false(identical(env$.pk_compose_escape("A{B}")$text,
                         env$.pk_compose_escape("AB")$text))
  hucre <- env$.pk_compose_escape("x {{fact:olcu.sum.overall.abc123}} y")$text
  expect_false(grepl(env$PK_FACT_REF_PATTERN, hucre, perl = TRUE))
  expect_false(grepl("[", env$.pk_compose_escape("[etiket](http://x)")$text, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# 8) NÖTRLEYİCİ — PK dışı şablon metnine dokunmaz
# ---------------------------------------------------------------------------

test_that("notrleyici yalnizca fact onekli bicimlere dokunur (strict disinda)", {
  env <- .pk_hard_env()
  expect_identical(env$pk_fact_reference_neutralize("Jinja {{ ad }} yazin."),
                   "Jinja {{ ad }} yazin.")
  expect_identical(env$pk_fact_reference_neutralize("A {{fact:x.sum.o.1}} B"),
                   "A (değer yok) B")
  expect_identical(env$pk_fact_reference_neutralize("A {{fact:yarim"), "A (değer yok)")
  expect_identical(env$pk_fact_reference_neutralize("A {{olgu:x}} B", strict = TRUE),
                   "A (değer yok) B")
  expect_null(env$pk_fact_reference_neutralize(NULL))
})
