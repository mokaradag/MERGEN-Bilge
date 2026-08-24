# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-numeric-provenance-contract.R
# Açıklama: Faz 2 — sayısal köken doğrulaması (§5.11).
#
#           Merkezî iddia: çıplak jeton üyeliği YETERSİZDİR. `47` sayısı pakette
#           "farklı kişi sayısı" olarak varsa, "tamamlanma %47" ifadesi jeton
#           olarak eşleşse bile REDDEDİLMELİDİR. Doğrulayıcı bu yüzden değeri
#           olgunun kimliği, birimi ve kullanılabilirliğiyle birlikte denetler.
#
#           Tümü ÇEVRİMDIŞI ve DETERMİNİSTİKTİR: gerçek DB, LLM, tarayıcı, ağ
#           veya gerçek sır KULLANILMAZ.
# ==============================================================================

.pk_prov_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x

  for (dosya in c("helpers_pk_config.R", "helpers_pk_precision.R", "helpers_pk_packet_stats.R", "helpers_pk_packet_context_facts.R",
                  "helpers_pk_numeric_provenance.R")) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = env)
  }
  env
}

# Sentetik olgu kümesi: gerçek proje/program adı içermez.
.pk_prov_facts <- function(env) {
  list(
    env$pk_fact_record("measure", "KalanIscilik_sa", "sum", 18420.5,
                       list(label = "Kalan İşçilik", unit = "saat", decimals = 1L,
                            capability = "labor.remaining_hours")),
    env$pk_fact_record("measure", "TamamlanmaYuzde", "weighted_mean", 61.3,
                       list(label = "Tamamlanma", unit = "%", decimals = 1L,
                            capability = "progress.completion_pct")),
    env$pk_fact_record("measure", "KaynakAdi", "distinct", 47,
                       list(label = "Kaynak", decimals = 0L)),
    env$pk_fact_record("measure", "Butce", "sum", NULL, list(label = "Bütçe"),
                       status = env$PK_FACT_NO_FINITE)
  )
}

.pk_prov_id <- function(olgular, sutun, agg) {
  bulunan <- Filter(function(o) identical(o$column, sutun) &&
                      identical(o$aggregation, agg), olgular)
  bulunan[[1]]$fact_id
}

# --- Turkce sayi ayristirma ---------------------------------------------------

test_that("Turkce ve sade sayi bicimleri ayristirilir, belirsizler REDDEDILIR", {
  env <- .pk_prov_env()

  expect_equal(env$pk_parse_number_tr("18.420,5"), 18420.5)
  expect_equal(env$pk_parse_number_tr("61,3"), 61.3)
  expect_equal(env$pk_parse_number_tr("18420.5"), 18420.5)
  expect_equal(env$pk_parse_number_tr("1.234"), 1234)
  expect_equal(env$pk_parse_number_tr("-125,50"), -125.5)
  expect_equal(env$pk_parse_number_tr("47"), 47)

  expect_null(env$pk_parse_number_tr("1.234,56.7"))
  expect_null(env$pk_parse_number_tr("1,2,3"))
  expect_null(env$pk_parse_number_tr("abc"))
  expect_null(env$pk_parse_number_tr(""))
})

# --- Deger dogrulamasi --------------------------------------------------------

test_that("Dogru olguya bagli dogru sayi GECERLIDIR", {
  env <- .pk_prov_env()
  olgular <- .pk_prov_facts(env)
  kimlik <- .pk_prov_id(olgular, "KalanIscilik_sa", "sum")

  metin <- sprintf("Toplam kalan işçilik 18.420,5 saat [fact:%s] olarak hesaplandı.", kimlik)
  sonuc <- env$pk_numeric_provenance_validate(metin, olgular)

  expect_equal(sonuc$checked, 1L)
  expect_length(sonuc$mismatches, 0L)
  expect_equal(sonuc$rate, 0)
})

test_that("Yanlis deger value_mismatch olarak reddedilir", {
  env <- .pk_prov_env()
  olgular <- .pk_prov_facts(env)
  kimlik <- .pk_prov_id(olgular, "KalanIscilik_sa", "sum")

  sonuc <- env$pk_numeric_provenance_validate(
    sprintf("Toplam 19.500,0 saat [fact:%s].", kimlik), olgular
  )

  expect_length(sonuc$mismatches, 1L)
  expect_identical(sonuc$mismatches[[1]]$reason, "value_mismatch")
  expect_equal(sonuc$rate, 1)
})

test_that("Bildirilen yuvarlama toleransi kabul edilir, otesi reddedilir", {
  env <- .pk_prov_env()
  olgular <- .pk_prov_facts(env)
  kimlik <- .pk_prov_id(olgular, "KalanIscilik_sa", "sum")

  # 18.420,5 -> tam sayiya yuvarlanmis alinti: tolerans 0,5
  kabul <- env$pk_numeric_provenance_validate(
    sprintf("Yaklasik 18.420 saat [fact:%s].", kimlik), olgular
  )
  expect_length(kabul$mismatches, 0L)

  ret <- env$pk_numeric_provenance_validate(
    sprintf("Yaklasik 18.419 saat [fact:%s].", kimlik), olgular
  )
  expect_length(ret$mismatches, 1L)
})

# --- ANLAMSAL denetim: dogru sayi, YANLIS olcu --------------------------------

test_that("AYNI jeton YANLIS olcu icin alintilandiginda REDDEDILIR", {
  env <- .pk_prov_env()
  olgular <- .pk_prov_facts(env)
  kisi_kimligi <- .pk_prov_id(olgular, "KaynakAdi", "distinct")

  # 47 pakette VARDIR (farkli kisi sayisi) ama "tamamlanma %47" yanlistir.
  sonuc <- env$pk_numeric_provenance_validate(
    sprintf("Tamamlanma %%47 [fact:%s] seviyesindedir.", kisi_kimligi), olgular
  )

  expect_length(sonuc$mismatches, 1L)
  expect_identical(sonuc$mismatches[[1]]$reason, "unit_mismatch")
})

test_that("Ayni sayi DOGRU olcuye baglandiginda kabul edilir", {
  env <- .pk_prov_env()
  olgular <- .pk_prov_facts(env)
  kisi_kimligi <- .pk_prov_id(olgular, "KaynakAdi", "distinct")

  sonuc <- env$pk_numeric_provenance_validate(
    sprintf("Toplam 47 [fact:%s] farkli kaynak gorevlidir.", kisi_kimligi), olgular
  )
  expect_length(sonuc$mismatches, 0L)
})

test_that("Yuzde olgusu yuzde isaretiyle alintilanabilir", {
  env <- .pk_prov_env()
  olgular <- .pk_prov_facts(env)
  kimlik <- .pk_prov_id(olgular, "TamamlanmaYuzde", "weighted_mean")

  sonuc <- env$pk_numeric_provenance_validate(
    sprintf("Agirlikli tamamlanma %%61,3 [fact:%s].", kimlik), olgular
  )
  expect_length(sonuc$mismatches, 0L)
})

test_that("Birim uyusmazligi (saat yerine TL) reddedilir", {
  env <- .pk_prov_env()
  olgular <- .pk_prov_facts(env)
  kimlik <- .pk_prov_id(olgular, "KalanIscilik_sa", "sum")

  sonuc <- env$pk_numeric_provenance_validate(
    sprintf("Toplam 18.420,5 TL [fact:%s].", kimlik), olgular
  )
  expect_length(sonuc$mismatches, 1L)
  expect_identical(sonuc$mismatches[[1]]$reason, "unit_mismatch")
})

# --- Bilinmeyen ve kullanilamaz olgular ---------------------------------------

test_that("Bilinmeyen olgu kimligi reddedilir", {
  env <- .pk_prov_env()
  sonuc <- env$pk_numeric_provenance_validate(
    "Toplam 999 [fact:uydurma.sum.overall].", .pk_prov_facts(env)
  )
  expect_length(sonuc$mismatches, 1L)
  expect_identical(sonuc$mismatches[[1]]$reason, "unknown_fact")
})

test_that("KULLANILAMAZ olgunun sayisi alintilanamaz", {
  env <- .pk_prov_env()
  olgular <- .pk_prov_facts(env)
  kimlik <- .pk_prov_id(olgular, "Butce", "sum")

  sonuc <- env$pk_numeric_provenance_validate(
    sprintf("Toplam butce 0 [fact:%s].", kimlik), olgular
  )
  expect_length(sonuc$mismatches, 1L)
  expect_identical(sonuc$mismatches[[1]]$reason, "unavailable_fact")
})

test_that("RLS oncesi sayi diye bir olgu YOKTUR; alintisi reddedilir", {
  env <- .pk_prov_env()
  sonuc <- env$pk_numeric_provenance_validate(
    "Toplam 41.930 kayit [fact:pre_rls.count.overall] bulunmaktadir.",
    .pk_prov_facts(env)
  )
  expect_length(sonuc$mismatches, 1L)
  expect_identical(sonuc$mismatches[[1]]$reason, "unknown_fact")
})

# --- Kipler -------------------------------------------------------------------

test_that("Varsayilan kip 'log'tur ve kullanicinin gordugu metni DEGISTIRMEZ", {
  env <- .pk_prov_env()
  withr::with_envvar(list(MERGEN_PK_NUMERIC_PROVENANCE_MODE = NA_character_), {
    expect_identical(env$pk_numeric_provenance_mode(), "log")
  })

  olgular <- .pk_prov_facts(env)
  kimlik <- .pk_prov_id(olgular, "KalanIscilik_sa", "sum")
  metin <- sprintf("Toplam 99.999,9 saat [fact:%s].", kimlik)

  sonuc <- env$pk_numeric_provenance_apply(metin, olgular, mode = "log")

  expect_identical(sonuc$mode, "log")
  expect_length(sonuc$mismatches, 1L)
  expect_false(sonuc$blocked)
  # Uyusmazlik VAR ama log kipinde metne uyari EKLENMEZ (kalibrasyon kipi).
  expect_identical(sonuc$text, "Toplam 99.999,9 saat.")
  expect_false(grepl("Doğrulanamayan", sonuc$text, fixed = TRUE))
})

test_that("Referans isaretleri her kipte gosterimden SILINIR", {
  env <- .pk_prov_env()
  olgular <- .pk_prov_facts(env)
  kimlik <- .pk_prov_id(olgular, "KalanIscilik_sa", "sum")
  metin <- sprintf("Toplam 18.420,5 saat [fact:%s] hesaplandi.", kimlik)

  for (kip in c("off", "log", "warn")) {
    sonuc <- env$pk_numeric_provenance_apply(metin, olgular, mode = kip)
    expect_false(grepl("[fact:", sonuc$text, fixed = TRUE),
                 info = sprintf("%s kipinde isaret silinmedi.", kip))
    expect_true(grepl("18.420,5 saat", sonuc$text, fixed = TRUE))
  }
})

test_that("warn kipi dogrulanamayan sayilari GORUNUR bicimde isaretler", {
  env <- .pk_prov_env()
  olgular <- .pk_prov_facts(env)
  kimlik <- .pk_prov_id(olgular, "KalanIscilik_sa", "sum")

  sonuc <- env$pk_numeric_provenance_apply(
    sprintf("Toplam 99.999,9 saat [fact:%s].", kimlik), olgular, mode = "warn"
  )

  expect_false(sonuc$blocked)
  expect_true(grepl("Doğrulanamayan sayılar", sonuc$text, fixed = TRUE))
  expect_true(grepl("value_mismatch", sonuc$text, fixed = TRUE))
})

test_that("block kipi duzyazi yerine DETERMINISTIK metni gosterir", {
  env <- .pk_prov_env()
  olgular <- .pk_prov_facts(env)
  kimlik <- .pk_prov_id(olgular, "KalanIscilik_sa", "sum")

  sonuc <- env$pk_numeric_provenance_apply(
    sprintf("Uydurma yorum 99.999,9 saat [fact:%s].", kimlik), olgular,
    mode = "block", fallback_text = "**Hesaplanan değerler**\n- Kalan İşçilik (sum): 18.420,5 saat"
  )

  expect_true(sonuc$blocked)
  expect_false(grepl("Uydurma yorum", sonuc$text, fixed = TRUE))
  expect_true(grepl("Yanıt doğrulanamadı", sonuc$text, fixed = TRUE))
  expect_true(grepl("18.420,5 saat", sonuc$text, fixed = TRUE))
})

test_that("block kipi uyusmazlik YOKSA duzyaziyi engellemez", {
  env <- .pk_prov_env()
  olgular <- .pk_prov_facts(env)
  kimlik <- .pk_prov_id(olgular, "KalanIscilik_sa", "sum")

  sonuc <- env$pk_numeric_provenance_apply(
    sprintf("Toplam 18.420,5 saat [fact:%s].", kimlik), olgular, mode = "block"
  )
  expect_false(sonuc$blocked)
  expect_true(grepl("Toplam 18.420,5 saat", sonuc$text, fixed = TRUE))
})

test_that("off kipi dogrulama yapmaz ama isaretleri yine de temizler", {
  env <- .pk_prov_env()
  olgular <- .pk_prov_facts(env)
  kimlik <- .pk_prov_id(olgular, "KalanIscilik_sa", "sum")

  sonuc <- env$pk_numeric_provenance_apply(
    sprintf("Yanlis 1,0 saat [fact:%s].", kimlik), olgular, mode = "off"
  )
  expect_equal(sonuc$checked, 0L)
  expect_length(sonuc$mismatches, 0L)
  expect_false(grepl("fact:", sonuc$text, fixed = TRUE))
})

test_that("Gecersiz kip degeri sessizce 'log'a duser", {
  env <- .pk_prov_env()
  withr::with_envvar(list(MERGEN_PK_NUMERIC_PROVENANCE_MODE = "saldirgan"), {
    expect_identical(env$pk_numeric_provenance_mode(), "log")
  })
})

# --- Olculen uyusmazlik orani raporlanir --------------------------------------

test_that("Uyusmazlik orani sirsiz bicimde raporlanir; duzyazi loga GIRMEZ", {
  env <- .pk_prov_env()
  olgular <- .pk_prov_facts(env)
  kimlik <- .pk_prov_id(olgular, "KalanIscilik_sa", "sum")

  sonuc <- env$pk_numeric_provenance_apply(
    sprintf("Gizli proje adi ve 99,9 saat [fact:%s].", kimlik), olgular, mode = "log"
  )

  cikti <- utils::capture.output(env$pk_numeric_provenance_report(sonuc, "q_sentetik"))
  birlesik <- paste(cikti, collapse = "\n")

  expect_true(grepl("Sayisal koken", birlesik, fixed = TRUE))
  expect_true(grepl("uyusmazlik=1", birlesik, fixed = TRUE))
  expect_true(grepl("oran=1.000", birlesik, fixed = TRUE))
  expect_true(grepl("value_mismatch", birlesik, fixed = TRUE))
  expect_false(grepl("Gizli proje adi", birlesik, fixed = TRUE))
})

test_that("Iddia yoksa oran sifirdir ve rapor yine uretilir", {
  env <- .pk_prov_env()
  sonuc <- env$pk_numeric_provenance_apply("Referanssiz duz metin.",
                                           .pk_prov_facts(env), mode = "log")
  expect_equal(sonuc$checked, 0L)
  expect_equal(sonuc$rate, 0)

  cikti <- paste(utils::capture.output(env$pk_numeric_provenance_report(sonuc)),
                 collapse = "\n")
  expect_true(grepl("iddia=0", cikti, fixed = TRUE))
})

# --- Deterministik tablo/ek LLM iddia ayristirmasindan GECMEZ -----------------

test_that("Olgu indeksi kimliğe gore kurulur; CAKISAN kimlik alintilanamaz olur", {
  env <- .pk_prov_env()
  olgular <- .pk_prov_facts(env)
  index <- env$pk_facts_index(olgular)
  kimlik <- .pk_prov_id(olgular, "KalanIscilik_sa", "sum")

  expect_true(all(grepl("^[A-Za-z0-9_.]+$", names(index))))
  expect_equal(index[[kimlik]]$value, 18420.5)

  # inceleme bulgusu: aynı kimliğe iki FARKLI olgu düşerse sessizce biri
  # ezilmez; ikisi de kullanılamaz olur. Aksi hâlde doğru alıntılanmış bir sayı
  # YANLIŞ ölçüye karşı doğrulanırdı.
  catisan <- index[[kimlik]]
  catisan$value <- 999
  catisan$column <- "BaskaSutun"
  cakisik <- env$pk_facts_index(list(index[[kimlik]], catisan))

  expect_null(cakisik[[kimlik]]$value)
  expect_identical(cakisik[[kimlik]]$status, "ambiguous_fact_id")
})

# --- PR #705: ISARETSIZ SAYISAL IDDIALAR ------------------------------------

test_that("isaretsiz sayisal iddia UYUSMAZLIK sayilir", {
  env <- .pk_prov_env()
  olgular <- list(list(fact_id = "f1", value = 1234.5, column = "Saat",
                       aggregation = "sum", unit = "saat"))

  # KUSUR: model istem kuralini yok sayip isaretsiz bir sayi yazdiginda iddia
  # kumesi BOS kaliyor, dogrulayici "uyusmazlik yok" diyor ve `warn`/`block`
  # kipleri bile halusinasyon sayiyi DEGISMEDEN yayimliyordu.
  sonuc <- env$pk_numeric_provenance_validate("Toplam 99.999 saat harcandi.", olgular)
  expect_identical(sonuc$checked, 1L)
  expect_length(sonuc$mismatches, 1L)
  expect_identical(sonuc$mismatches[[1]]$reason, "missing_fact_marker")
  expect_true(sonuc$rate > 0)

  # Dogru alintilanan sayi UYUSMAZLIK DEGILDIR.
  temiz <- env$pk_numeric_provenance_validate(
    "Toplam 1.234,5 saat [fact:f1] harcandi.", olgular
  )
  expect_length(temiz$mismatches, 0L)

  # Karisik metin: yalnizca isaretsiz olan yakalanir.
  karisik <- env$pk_numeric_provenance_validate(
    "Once 1.234,5 saat [fact:f1], ayrica 88.888 saat daha.", olgular
  )
  expect_identical(karisik$checked, 2L)
  expect_length(karisik$mismatches, 1L)
  expect_identical(karisik$mismatches[[1]]$reason, "missing_fact_marker")
})

test_that("siradan sayilar YANLIS POZITIF uretmez", {
  env <- .pk_prov_env()
  olgular <- list(list(fact_id = "f1", value = 1L, column = "Adet",
                       aggregation = "count", unit = "adet"))

  # Yil, kucuk tam sayi ve madde numarasi veri iddiasi DEGILDIR; `block`
  # kipinde gecerli yanitlari dusurmemelidirler.
  for (metin in c("2024 yilinda 3 kez incelendi.",
                  "1. Birinci bulgu\n2. Ikinci bulgu",
                  "Yaklasik 5 proje etkilendi.",
                  "")) {
    sonuc <- env$pk_numeric_provenance_validate(metin, olgular)
    expect_equal(length(sonuc$mismatches), 0L, info = metin)
  }

  # Olcek isareti tasiyan sayilar YAKALANIR.
  for (metin in c("Toplam 1500 saat.", "Oran %61,3 seviyesinde.", "Butce 12.500 TL.")) {
    sonuc <- env$pk_numeric_provenance_validate(metin, olgular)
    expect_true(length(sonuc$mismatches) >= 1L, info = metin)
  }
})
