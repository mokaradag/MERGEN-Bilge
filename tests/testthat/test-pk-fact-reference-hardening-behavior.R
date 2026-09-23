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

# ---------------------------------------------------------------------------
# 7) KIRIK `fact` AÇICISI hiçbir kipte ham söz dizimi olarak kalmaz
# ---------------------------------------------------------------------------

test_that("tek kapanisli ve uzun kapanissiz fact acicisi notrlenir ve rapor edilir", {
  env <- .pk_hard_env()
  olgular <- .pk_hard_facts(env)
  uzun <- paste(rep("x", 200L), collapse = "")
  for (metin in c("Toplam {{fact:x} saat harcandi.",
                  paste0("Toplam {{fact:bogus ", uzun, " sonuc."),
                  "Kod {{fact:12345} olarak gorunuyor.")) {
    for (kip in c("off", "log", "warn")) {
      sonuc <- env$pk_numeric_provenance_apply(metin, olgular, mode = kip)
      expect_false(grepl("{{fact", sonuc$text, fixed = TRUE), info = paste(kip, metin))
      expect_false(grepl("12345", sonuc$text, fixed = TRUE), info = paste(kip, metin))
    }
    log_sonuc <- env$pk_numeric_provenance_apply(metin, olgular, mode = "log")
    expect_true("malformed_reference" %in% .pk_hard_reasons(log_sonuc))
    # Kimlik içindeki rakamlar model sayısı SAYILMAZ.
    expect_false("model_numeric_literal" %in% .pk_hard_reasons(log_sonuc))
  }
  # Doğrulayıcı dışı yol da kırık açıcıyı nötrler; sıradan şablon korunur.
  expect_identical(env$pk_fact_reference_neutralize("A {{fact:x} B {{ ad }}"),
                   "A (değer yok) B {{ ad }}")
})

# ---------------------------------------------------------------------------
# 8) YİNELENEN BİRİM ikinci kez basılmaz; komşu sayı bozulmaz
# ---------------------------------------------------------------------------

test_that("yuvanin ardindaki ya da onundeki AYNI birim yinelenmez", {
  env <- .pk_hard_env()
  saat <- env$pk_fact_record("measure", "Saat", "sum", 100,
                             list(label = "Saat", unit = "saat", decimals = 0L))
  yuzde <- env$pk_fact_record("measure", "Oran", "mean", 61.3,
                              list(label = "Oran", unit = "%", decimals = 1L))
  tutar <- env$pk_fact_record("measure", "Tutar", "sum", 1250,
                              list(label = "Tutar", unit = "TL", decimals = 0L))
  jeton <- function(o) env$pk_fact_reference_token(o$fact_id)
  olgular <- list(saat, yuzde, tutar)
  tl <- intToUtf8(0x20BA)

  sonuc <- env$pk_numeric_provenance_apply(
    paste0("Toplam ", jeton(saat), " saat, oran %", jeton(yuzde), ", tutar ",
           tl, jeton(tutar), " TL oldu."), olgular, mode = "log")
  expect_identical(sonuc$text, "Toplam 100 saat, oran %61,3, tutar 1.250 TL oldu.")
  expect_length(sonuc$mismatches, 0L)

  # Birim komşu bir SAYIYA aitse silinmez: sayı birleşip bozulamaz.
  komsu <- env$pk_numeric_provenance_apply(
    paste0("Oran ", jeton(yuzde), " %5 artti."), olgular, mode = "log")
  expect_false(grepl("61,35", komsu$text, fixed = TRUE))
  expect_true(grepl("%61,3", komsu$text, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# 9) `block`: numaralı madde düşerken yetim "1." satırı kalmaz
# ---------------------------------------------------------------------------

test_that("block kipi numarali maddeyi tumuyle dusurur, kalan cumlede oneki korur", {
  env <- .pk_hard_env()
  olgular <- .pk_hard_facts(env)
  metin <- paste0(
    "Oneriler:\n",
    "1. Kapasite {{fact:bilinmeyen.olgu}} kisi gorunuyor.\n",
    "2. Planlama ekibi guclendirilmeli.\n",
    "- Birinci cumle korunur. Ikinci cumle {{fact:bilinmeyen.olgu}} duser."
  )
  blok <- env$pk_numeric_provenance_apply(metin, olgular, mode = "block")
  satirlar <- strsplit(blok$text, "\n", fixed = TRUE)[[1]]
  expect_false(any(grepl("^[[:space:]]*1\\.[[:space:]]*$", satirlar)))
  expect_false(any(grepl("Kapasite", satirlar, fixed = TRUE)))
  expect_true("2. Planlama ekibi guclendirilmeli." %in% satirlar)
  expect_true("- Birinci cumle korunur." %in% satirlar)
})

# ---------------------------------------------------------------------------
# 10) IQR SINIRLARI ölçünün BİRİMİNİ taşır (TL / kesir yüzdesi)
# ---------------------------------------------------------------------------

test_that("IQR sinir olgulari olcunun birimini tasir; dogru birim catisma sayilmaz", {
  env <- .pk_hard_env()
  olgular <- env$pk_measure_facts(c(10, 20, 30, 40, 50, 60, 70, 80, 5000), "Butce",
                                  list(label = "Butce", unit = "TL", decimals = 0L))
  paket <- list(facts = olgular, scope = list(scope_signature = "sentetik"),
                coverage = list(rows = 9L, columns = 1L))
  hepsi <- env$pk_packet_all_facts(paket)
  ust <- Filter(function(o) identical(o$aggregation, "iqr_upper"), hepsi)[[1]]
  expect_identical(ust$unit, "TL")
  expect_true(grepl(" TL$", ust$display))
  expect_true(grepl(ust$display, env$.pk_render_facts(paket), fixed = TRUE))

  sonuc <- env$pk_numeric_provenance_apply(
    paste0("Ust sinir ", env$pk_fact_reference_token(ust$fact_id), " TL olarak hesaplandi."),
    hepsi, mode = "log")
  expect_false("unit_conflict" %in% .pk_hard_reasons(sonuc))
  expect_false(grepl("TL TL", sonuc$text, fixed = TRUE))

  kesir <- env$pk_measure_facts(c(0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.99), "Ilerleme",
                                list(label = "Ilerleme", unit = "%", decimals = 1L,
                                     percent_scale = "fraction"))
  paket2 <- list(facts = kesir, scope = list(), coverage = list(rows = 9L, columns = 1L))
  alt <- Filter(function(o) identical(o$aggregation, "iqr_lower"),
                env$pk_packet_all_facts(paket2))[[1]]
  expect_true(startsWith(alt$display, "%") || startsWith(alt$display, "-%"))
})

# ---------------------------------------------------------------------------
# 11) `warn` notu kaynaksız sayı görünürken "sayılar R'den" DEMEZ
# ---------------------------------------------------------------------------

test_that("warn notu kaynaksiz sayi varsa dogrulanmamis der, yoksa R hesabini belirtir", {
  env <- .pk_hard_env()
  olgular <- .pk_hard_facts(env)
  kaynaksiz <- env$pk_numeric_provenance_apply("Toplam 99.999 saat harcandi.",
                                               olgular, mode = "warn")
  expect_true(grepl("doğrulanmamıştır", kaynaksiz$text, fixed = TRUE))
  expect_false(grepl("R tarafından hesaplanmıştır", kaynaksiz$text, fixed = TRUE))

  bilinmeyen <- env$pk_numeric_provenance_apply("Deger {{fact:yok.olgu}} oldu.",
                                                olgular, mode = "warn")
  expect_true(grepl("R tarafından hesaplanmıştır", bilinmeyen$text, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# 12) Tarayıcı: noktalı kodlar ölçü değildir; binlik gruplu sayı ölçüdür
# ---------------------------------------------------------------------------

test_that("WBS ve noktali kimlik kodlari muaf, gecerli binlik sayi muaf degil", {
  env <- .pk_hard_env()
  tara <- function(x) length(env$pk_fact_literal_scan(x, character(0))$tokens)
  expect_identical(tara("WBS 1.2.3 kalemi gecikti."), 0L)
  expect_identical(tara("Aktivite P.01.02 tamamlandi."), 0L)
  expect_identical(tara("Sunucu 10.0.0.1 adresinde."), 0L)
  expect_identical(tara("Toplam 1.234.567 saat harcandi."), 1L)
  expect_identical(tara("Butce 1.234,5 TL oldu."), 1L)
})

# ---------------------------------------------------------------------------
# 13) Kullanıcı kriterine birim eklemek güven bulgusu DEĞİLDİR
# ---------------------------------------------------------------------------

test_that("istek girdisi yuvasina eklenen para birimi unit_conflict sayilmaz", {
  env <- .pk_hard_env()
  paket <- list(filters = list(applied = list(
    list(column = "Butce", operation = "greater_than", values = "1000000")
  )), scope = list(scope_signature = "sentetik"))
  istek <- env$pk_packet_request_facts(paket)
  metin <- paste0("Butcesi ", env$pk_fact_reference_token(istek[[1]]$fact_id),
                  " TL uzerindeki projeler listelendi.")
  for (kip in c("log", "block")) {
    sonuc <- env$pk_numeric_provenance_apply(metin, istek, mode = kip)
    expect_false("unit_conflict" %in% .pk_hard_reasons(sonuc), info = kip)
    expect_true(grepl("1000000 TL uzerindeki", sonuc$text, fixed = TRUE), info = kip)
  }
  # Ölçü olgusu için kural DEĞİŞMEZ: birimsiz sayıma TL eklemek bulgudur.
  olgular <- .pk_hard_facts(env)
  olcu <- env$pk_numeric_provenance_apply(
    paste0("Toplam ", .pk_hard_token(env, olgular, 1), " TL."), olgular, mode = "log")
  expect_true("unit_conflict" %in% .pk_hard_reasons(olcu))
})

# ---------------------------------------------------------------------------
# 14) İstem ve paket oran HESAPLATMAZ; boş değer oranı da yuvalıdır
# ---------------------------------------------------------------------------

test_that("v2 istemi ve filtre uyarisi payda tarif etmez, oran hesaplamayi yasaklar", {
  env <- .pk_hard_env()
  istem <- env$pk_build_analysis_system_prompt_v2("summary", list(name = "S", description = "D"))
  expect_false(grepl("payda", istem, fixed = TRUE))
  expect_true(grepl("oran/yüzde HESAPLAMA", istem, fixed = TRUE))

  paket <- list(scope = list(authorized_rows = 100L, filtered_rows = 40L),
                filters = list(user_filter_applied = TRUE, applied = list()))
  uyari <- env$.pk_render_filters(paket)
  expect_false(grepl("payda", uyari, fixed = TRUE))
  expect_true(grepl("Oran/yuzde HESAPLAMA", uyari, fixed = TRUE))
})

test_that("bos deger orani yuvayla basilir ve olgu dizininde cozulur", {
  env <- .pk_hard_env()
  paket <- list(coverage = list(rows = 8L, columns = 2L,
                                missing = list(list(column = "Bitis", missing = 2L))),
                scope = list(scope_signature = "sentetik"))
  metin <- env$.pk_render_coverage(paket)
  satir <- grep("Bos deger orani", strsplit(metin, "\n", fixed = TRUE)[[1]], value = TRUE)
  expect_length(satir, 1L)
  pay <- Filter(function(o) identical(o$aggregation, "missing_share"),
                env$pk_packet_all_facts(paket))
  expect_length(pay, 1L)
  expect_identical(pay[[1]]$display, "%25,0")
  expect_true(grepl(paste0("%25,0 ", env$pk_fact_reference_token(pay[[1]]$fact_id)),
                    satir, fixed = TRUE))
  # Yuvasız sayı kalmaz: tarayıcı satırda model sayısı sanacağı değer bulmaz.
  kalan <- env$pk_fact_literal_scan(sub("^.*orani: ", "", satir), character(0))$tokens
  expect_true(all(vapply(kalan, function(j) j$raw, character(1)) %in%
                    c("%25,0", "2")))

  # Satır sayısı yoksa pay da yuvası da basılmaz.
  bos <- env$.pk_render_coverage(list(coverage = list(
    missing = list(list(column = "Bitis", missing = 2L)))))
  expect_false(grepl("missing_share", bos, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# 15) Sorudaki DÖNEM sayısı güvenilir istek girdisidir ("son 6 ayda")
# ---------------------------------------------------------------------------

test_that("sorudaki gun/ay/yil sayilari donem istek girdisine donusur", {
  env <- .pk_hard_env()
  expect_identical(
    env$pk_request_period_values("Son 6 ayda baslayan, 30 günden az kalan; 2 YIL; 1.5 ay"),
    c("6 ay", "30 gün", "2 yıl")
  )
  expect_identical(env$pk_request_period_values("Projeleri ozetle"), character(0))
  expect_identical(env$pk_request_period_values(NULL), character(0))

  # Birim tam kelimedir: birimle BAŞLAYAN başka kelimeler dönem değildir.
  for (metin in c("3 ayrı proje", "2 aynı kod", "son 3 güncel kayıt", "2 güney bölge",
                  "5 yıldız", "3 yılan")) {
    expect_identical(env$pk_request_period_values(metin), character(0), info = metin)
  }
  # Takvim yılı süre değildir; gerçek süreler ekli biçimleriyle korunur.
  expect_identical(env$pk_request_period_values("2024 yılında başlayan, 2023 yılı projeleri"), character(0))
  expect_identical(
    env$pk_request_period_values("12 aylık plan, 2 yıldır süren, 7 gündür, 3 aylarda"),
    c("12 ay", "2 yıl", "7 gün", "3 ay")
  )
})

test_that("donem istek girdisi yuvayla basilir; duz yinelemesi ihlal sayilmaz", {
  env <- .pk_hard_env()
  paket <- list(scope = list(scope_signature = "sentetik"),
                filters = list(applied = list(), request_periods = "6 ay"))
  istek <- env$pk_packet_request_facts(paket)
  expect_length(istek, 1L)
  expect_identical(istek[[1]]$kind, "request_input")
  expect_identical(istek[[1]]$display, "6")
  expect_true(grepl(env$pk_fact_reference_token(istek[[1]]$fact_id),
                    env$.pk_render_filters(paket), fixed = TRUE))

  metin <- "Son 6 ay icinde baslayan projeler listelendi."
  expect_identical(env$pk_numeric_provenance_apply(metin, istek, mode = "log")$protocol, 0L)
  expect_identical(env$pk_numeric_provenance_apply(metin, list(), mode = "log")$protocol, 1L)

  yuvali <- env$pk_numeric_provenance_apply(
    paste0("Son ", env$pk_fact_reference_token(istek[[1]]$fact_id), " ayda baslayanlar."),
    istek, mode = "block")
  expect_identical(yuvali$text, "Son 6 ayda baslayanlar.")
})
