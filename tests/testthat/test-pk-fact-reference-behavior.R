# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-fact-reference-behavior.R
# Açıklama: §5.11 ANLAMSAL OLGU REFERANSI davranış sözleşmesi.
#
#           Merkezî iddia: SAYIYI R BASAR. Model yalnızca sayının durması
#           gereken yere bir yuva koyar; kimlik AÇIKTIR ve düzyazıdaki sayılar
#           olgulara GERİYE DOĞRU eşleştirilmez.
#
#           Tümü ÇEVRİMDIŞI ve DETERMİNİSTİKTİR: gerçek DB, LLM, tarayıcı, ağ
#           veya gerçek sır KULLANILMAZ.
# ==============================================================================

.pk_ref_env <- function() {
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

# Sentetik olgular: gerçek proje/program adı içermez.
.pk_ref_facts <- function(env) {
  list(
    env$pk_fact_record("measure", "GecikenAktivite", "sum", 15448,
                       list(label = "Geciken aktivite", decimals = 0L,
                            capability = "schedule.late_count")),
    env$pk_fact_record("measure", "TamamlanmaYuzde", "weighted_mean", 61.3,
                       list(label = "Tamamlanma", unit = "%", decimals = 1L,
                            capability = "progress.completion_pct")),
    env$pk_fact_record("measure", "KalanIscilik_sa", "sum", 18420.5,
                       list(label = "Kalan iscilik", unit = "saat", decimals = 1L,
                            capability = "labor.remaining_hours")),
    env$pk_fact_record("measure", "Butce", "sum", 125000,
                       list(label = "Butce", unit = "TL", decimals = 0L,
                            capability = "cost.budget")),
    env$pk_fact_record("measure", "SPI", "mean", 0.87,
                       list(label = "SPI", decimals = 2L, capability = "schedule.spi")),
    env$pk_fact_record("measure", "PlanlananSaatSapmasi", "sum", -2450,
                       list(label = "Planlanan saat sapmasi", unit = "saat",
                            decimals = 0L, capability = "labor.plan_variance")),
    env$pk_fact_record("measure", "StdSapma", "sd", NULL, list(label = "Std sapma"),
                       status = env$PK_FACT_INSUFFICIENT)
  )
}

.pk_ref_id <- function(olgular, sutun, agg) {
  bulunan <- Filter(function(o) identical(o$column, sutun) &&
                      identical(o$aggregation, agg), olgular)
  bulunan[[1]]$fact_id
}

.pk_ref_token <- function(env, olgular, sutun, agg) {
  env$pk_fact_reference_token(.pk_ref_id(olgular, sutun, agg))
}

# ---------------------------------------------------------------------------
# 1) DOĞAL SATIR İÇİ OLGU GÖSTERİMİ
# ---------------------------------------------------------------------------

test_that("model duzyazisi dogal kalir ve yuva KANONIK degerle doldurulur", {
  env <- .pk_ref_env()
  olgular <- .pk_ref_facts(env)

  metin <- paste0(
    "Projelerin genel gorunumunde gecikmeler belirli alanlarda yogunlasiyor. ",
    "Ozellikle ", .pk_ref_token(env, olgular, "GecikenAktivite", "sum"),
    " geciken aktivite, program takibinde daha ayrintili inceleme gerektiren ",
    "bir yuk olusturuyor. Bunun tek basina kaynak yetersizligini ",
    "kanitlamadigini belirtmek gerekir."
  )

  sonuc <- env$pk_numeric_provenance_apply(metin, olgular, mode = "log")

  expect_true(grepl("Ozellikle 15.448 geciken aktivite", sonuc$text, fixed = TRUE))
  # İç söz dizimi KULLANICIYA SIZMAZ.
  expect_false(grepl("{{", sonuc$text, fixed = TRUE))
  expect_false(grepl("fact:", sonuc$text, fixed = TRUE))
  expect_identical(sonuc$resolved, 1L)
  expect_length(sonuc$mismatches, 0L)
})

test_that("bir cumlede birden cok olgu dogal bicimde cozulur", {
  env <- .pk_ref_env()
  olgular <- .pk_ref_facts(env)

  metin <- paste0(
    "Program tarafinda ", .pk_ref_token(env, olgular, "GecikenAktivite", "sum"),
    " geciken aktivite ve ", .pk_ref_token(env, olgular, "TamamlanmaYuzde", "weighted_mean"),
    " tamamlanma ile birlikte ", .pk_ref_token(env, olgular, "SPI", "mean"),
    " SPI degeri, is programinin gerisinde kalindigina isaret ediyor."
  )

  sonuc <- env$pk_numeric_provenance_apply(metin, olgular, mode = "log")

  expect_true(grepl("15.448 geciken aktivite", sonuc$text, fixed = TRUE))
  expect_true(grepl("%61,3 tamamlanma", sonuc$text, fixed = TRUE))
  expect_true(grepl("0,87 SPI", sonuc$text, fixed = TRUE))
  expect_identical(sonuc$resolved, 3L)
  expect_identical(sonuc$trust, 0L)
  expect_identical(sonuc$protocol, 0L)
})

# ---------------------------------------------------------------------------
# 2) AYNI DEĞER, FARKLI OLGU — kimlik DEĞERDEN gelmez
# ---------------------------------------------------------------------------

test_that("ayni sayisal degere sahip iki olgu KIMLIGE gore ayrisir", {
  env <- .pk_ref_env()
  saat <- env$pk_fact_record("measure", "HarcananSaat", "sum", 100,
                             list(label = "Harcanan saat", unit = "saat",
                                  decimals = 0L, capability = "labor.spent"))
  tutar <- env$pk_fact_record("measure", "Tutar", "sum", 100,
                              list(label = "Tutar", unit = "TL", decimals = 0L,
                                   capability = "cost.amount"))
  expect_false(identical(saat$fact_id, tutar$fact_id))

  metin <- paste0("Once ", env$pk_fact_reference_token(tutar$fact_id),
                  " tutar, sonra ", env$pk_fact_reference_token(saat$fact_id),
                  " saat degerlendirildi.")
  sonuc <- env$pk_numeric_provenance_apply(metin, list(saat, tutar), mode = "log")

  expect_true(grepl("100 TL tutar", sonuc$text, fixed = TRUE))
  expect_true(grepl("100 saat saat", sonuc$text, fixed = TRUE))
  expect_identical(sonuc$resolved, 2L)
})

test_that("AYNI kimlige dusen iki FARKLI olgu hicbir deger basmaz", {
  env <- .pk_ref_env()
  bir <- env$pk_fact_record("measure", "Olcu", "sum", 10,
                            list(label = "Olcu", capability = "x.y"))
  iki <- env$pk_fact_record("measure", "Olcu", "sum", 99,
                            list(label = "Olcu", capability = "x.y"))
  expect_identical(bir$fact_id, iki$fact_id)

  sonuc <- env$pk_numeric_provenance_apply(
    paste0("Deger ", env$pk_fact_reference_token(bir$fact_id), " olarak olculdu."),
    list(bir, iki), mode = "log"
  )

  expect_false(grepl("10", sonuc$text, fixed = TRUE))
  expect_false(grepl("99", sonuc$text, fixed = TRUE))
  expect_identical(sonuc$mismatches[[1]]$reason, "ambiguous_fact")
})

# ---------------------------------------------------------------------------
# 3) TÜRKÇE BİÇİMLENDİRME — ayraç, yüzde, para birimi, negatif
# ---------------------------------------------------------------------------

test_that("binlik/ondalik ayraci, yuzde ve para birimi R tarafindan basilir", {
  env <- .pk_ref_env()
  olgular <- .pk_ref_facts(env)

  sonuc <- env$pk_numeric_provenance_apply(
    paste0(.pk_ref_token(env, olgular, "KalanIscilik_sa", "sum"), " | ",
           .pk_ref_token(env, olgular, "Butce", "sum"), " | ",
           .pk_ref_token(env, olgular, "TamamlanmaYuzde", "weighted_mean"), " | ",
           .pk_ref_token(env, olgular, "PlanlananSaatSapmasi", "sum")),
    olgular, mode = "log"
  )

  expect_true(grepl("18.420,5 saat", sonuc$text, fixed = TRUE))
  expect_true(grepl("125.000 TL", sonuc$text, fixed = TRUE))
  # Türkçede yüzde işareti sayıdan ÖNCE gelir.
  expect_true(grepl("%61,3", sonuc$text, fixed = TRUE))
  expect_true(grepl("-2.450 saat", sonuc$text, fixed = TRUE))
})

test_that("TL simgesi tasiyan bir gosterim kullaniciya AYNEN basilir", {
  env <- .pk_ref_env()
  tl <- intToUtf8(0x20BA)
  olgu <- env$pk_fact_record("measure", "Tutar", "sum", 1250,
                             list(label = "Tutar", unit = tl, decimals = 0L,
                                  capability = "cost.amount"))

  sonuc <- env$pk_numeric_provenance_apply(
    paste0("Butce ", env$pk_fact_reference_token(olgu$fact_id), " olarak belirlendi."),
    list(olgu), mode = "log"
  )

  expect_true(grepl(paste0("1.250 ", tl), sonuc$text, fixed = TRUE))
  expect_identical(sonuc$resolved, 1L)
})

# ---------------------------------------------------------------------------
# 4) KULLANICI GİRDİSİ — güvenilir istek değeri, veritabanı olgusu DEĞİLDİR
# ---------------------------------------------------------------------------

test_that("kullanicinin kendi esigi GUVENILIR ISTEK GIRDISI olarak tasinir", {
  env <- .pk_ref_env()
  paket <- list(
    scope = list(scope_signature = "yetki=10|filtre=4"),
    filters = list(applied = list(
      list(column = "KalanGun", value = "30", operation = "less_than")
    ))
  )

  istek <- env$pk_packet_request_facts(paket)
  expect_length(istek, 1L)
  expect_identical(istek[[1]]$kind, "request_input")
  expect_identical(istek[[1]]$display, "30")
  expect_identical(env$pk_fact_trusted_input_keys(istek), "30")

  # Model esigi yuva ile anabilir; deger yine R'den gelir.
  sonuc <- env$pk_numeric_provenance_apply(
    paste0("Bitisine ", env$pk_fact_reference_token(istek[[1]]$fact_id),
           " gunden az kalan aktiviteler izleniyor."),
    istek, mode = "log"
  )
  expect_true(grepl("Bitisine 30 gunden az", sonuc$text, fixed = TRUE))
  expect_identical(sonuc$resolved, 1L)
})

test_that("kullanici esigi DUZ YAZILDIGINDA protokol ihlali sayilmaz", {
  env <- .pk_ref_env()
  paket <- list(
    scope = list(),
    filters = list(applied = list(
      list(column = "KalanGun", value = "30", operation = "less_than")
    ))
  )
  olgular <- c(.pk_ref_facts(env), env$pk_packet_request_facts(paket))

  sonuc <- env$pk_numeric_provenance_apply(
    "Bitisine 30 gunden az kalan aktiviteler bu listede yer aliyor.",
    olgular, mode = "log"
  )
  expect_identical(sonuc$protocol, 0L)

  # ANALITIK bir sayi ayni muafiyeti ALMAZ.
  kaynaksiz <- env$pk_numeric_provenance_apply(
    "Toplam 99.999 saat harcanmistir.", olgular, mode = "log"
  )
  expect_identical(kaynaksiz$protocol, 1L)
  expect_identical(kaynaksiz$mismatches[[1]]$reason, "model_numeric_literal")
})

# ---------------------------------------------------------------------------
# 5) TÜRETİLMİŞ SAYI — model aritmetik uyduramaz, R hesaplarsa basılır
# ---------------------------------------------------------------------------

test_that("modelin uydurdugu turetilmis sayi protokol ihlalidir", {
  env <- .pk_ref_env()
  olgular <- .pk_ref_facts(env)

  sonuc <- env$pk_numeric_provenance_apply(
    "Kalan sure yaklasik 5 gunluk bir pencereye isaret ediyor ve 4.500 saat kaldi.",
    olgular, mode = "log"
  )
  nedenler <- vapply(sonuc$mismatches, function(m) m$reason, character(1))
  expect_true("model_numeric_literal" %in% nedenler)
})

test_that("R tarafindan hesaplanan turetilmis olgu normal bicimde basilir", {
  env <- .pk_ref_env()
  turetilmis <- env$pk_fact_record("measure", "OrtalamaGecikmeGun", "mean", 12.4,
                                   list(label = "Ortalama gecikme", unit = "gün",
                                        decimals = 1L, capability = "schedule.delay_days"))

  sonuc <- env$pk_numeric_provenance_apply(
    paste0("Ortalama gecikme ", env$pk_fact_reference_token(turetilmis$fact_id),
           " duzeyindedir."),
    list(turetilmis), mode = "log"
  )
  expect_true(grepl("12,4 gün", sonuc$text, fixed = TRUE))
  expect_identical(sonuc$protocol, 0L)
  expect_identical(sonuc$trust, 0L)
})

# ---------------------------------------------------------------------------
# 6-8) BİLİNMEYEN / KULLANILAMAZ / YETKİSİZ OLGU — hicbiri deger basmaz
# ---------------------------------------------------------------------------

test_that("bilinmeyen kimlik deger SIZDIRMAZ", {
  env <- .pk_ref_env()
  olgular <- .pk_ref_facts(env)

  sonuc <- env$pk_numeric_provenance_apply(
    "Sonuc {{fact:uydurma.sum.overall.ffffff}} olarak olculdu.", olgular, mode = "log"
  )
  expect_false(grepl("[0-9]", sonuc$text))
  expect_identical(sonuc$mismatches[[1]]$reason, "unknown_fact")
  expect_identical(sonuc$mismatches[[1]]$category, "trust")
})

test_that("KULLANILAMAZ olgu icin deger UYDURULMAZ", {
  env <- .pk_ref_env()
  olgular <- .pk_ref_facts(env)

  sonuc <- env$pk_numeric_provenance_apply(
    paste0("Std sapma ", .pk_ref_token(env, olgular, "StdSapma", "sd"), " olarak bulundu."),
    olgular, mode = "log"
  )
  expect_false(grepl("[0-9]", sonuc$text))
  expect_identical(sonuc$mismatches[[1]]$reason, "unavailable_fact")
})

test_that("BASKA istegin olgusu hicbir kipte cozulmez (kapali basarisizlik)", {
  env <- .pk_ref_env()
  benim <- .pk_ref_facts(env)
  baskasinin <- env$pk_fact_record("measure", "YetkisizTutar", "sum", 987654,
                                   list(label = "Yetkisiz olcu", unit = "TL", decimals = 0L,
                                        capability = "yetkisiz.tutar"))

  metin <- paste0("Tutar ", env$pk_fact_reference_token(baskasinin$fact_id), " kadardir.")
  for (kip in c("off", "log", "warn", "block")) {
    sonuc <- env$pk_numeric_provenance_apply(metin, benim, mode = kip,
                                             fallback_text = "- Hesaplanan deger yok")
    expect_false(grepl("987654", sonuc$text, fixed = TRUE), info = kip)
    expect_false(grepl("987.654", sonuc$text, fixed = TRUE), info = kip)
  }
})

# ---------------------------------------------------------------------------
# 9) BEKLENMEYEN MODEL SAYISI — yapisal tespit, TERS ESLESTIRME YOK
# ---------------------------------------------------------------------------

test_that("model sayisi yapisal olarak isaretlenir ama OLGUYA eslestirilmez", {
  env <- .pk_ref_env()
  olgular <- .pk_ref_facts(env)

  sonuc <- env$pk_numeric_provenance_apply(
    "Geciken aktivite sayisi 15.448 olarak gozleniyor.", olgular, mode = "log"
  )

  expect_identical(sonuc$protocol, 1L)
  expect_identical(sonuc$trust, 0L)
  expect_identical(sonuc$mismatches[[1]]$reason, "model_numeric_literal")
  # Deger dogru OLSA BILE olgu kimligi CIKARILMAZ.
  expect_true(is.na(sonuc$mismatches[[1]]$fact_id))
  expect_identical(sonuc$resolved, 0L)
})

test_that("yuvanin yanindaki YINELENEN sayi silinir, cumle korunur", {
  env <- .pk_ref_env()
  olgular <- .pk_ref_facts(env)

  sonuc <- env$pk_numeric_provenance_apply(
    paste0("Toplam 15.448 ", .pk_ref_token(env, olgular, "GecikenAktivite", "sum"),
           " geciken aktivite bulunuyor."),
    olgular, mode = "log"
  )

  expect_identical(sonuc$text, "Toplam 15.448 geciken aktivite bulunuyor.")
  expect_identical(sonuc$mismatches[[1]]$reason, "duplicate_numeric_literal")
})

test_that("ESKI bicim alinti isareti protokol ihlalidir ve SILINIR", {
  env <- .pk_ref_env()
  olgular <- .pk_ref_facts(env)
  kimlik <- .pk_ref_id(olgular, "GecikenAktivite", "sum")

  sonuc <- env$pk_numeric_provenance_apply(
    sprintf("Toplam 15.448 [fact:%s] aktivite gecikti.", kimlik), olgular, mode = "log"
  )
  nedenler <- vapply(sonuc$mismatches, function(m) m$reason, character(1))
  expect_true("legacy_reference" %in% nedenler)
  expect_false(grepl("[fact:", sonuc$text, fixed = TRUE))
})

test_that("bozuk yuva jetonu deger basmaz ve YAPISAL olarak raporlanir", {
  env <- .pk_ref_env()
  olgular <- .pk_ref_facts(env)

  sonuc <- env$pk_numeric_provenance_apply(
    "Sonuc {{olgu:gecikme}} olarak olculdu.", olgular, mode = "log"
  )
  expect_identical(sonuc$mismatches[[1]]$reason, "malformed_reference")
  expect_identical(sonuc$mismatches[[1]]$category, "protocol")
  expect_false(grepl("{{", sonuc$text, fixed = TRUE))
})

test_that("yil, tarih ve madde numarasi veri iddiasi SAYILMAZ", {
  env <- .pk_ref_env()
  olgular <- .pk_ref_facts(env)

  for (metin in c("2024 yilinda program yeniden planlandi.",
                  "Son guncelleme 31.12.2024 tarihinde yapildi.",
                  "1. Kaynak plani gozden gecirilsin.\n2. Oncelikler yeniden siralansin.")) {
    sonuc <- env$pk_numeric_provenance_apply(metin, olgular, mode = "log")
    expect_identical(sonuc$protocol, 0L, info = metin)
  }
})

# ---------------------------------------------------------------------------
# 10-12) İDDİA DÜZEYİ AYIKLAMA ve KİP DAVRANIŞI
# ---------------------------------------------------------------------------

test_that("tek bozuk referans diger gecerli cumleleri DUSURMEZ", {
  env <- .pk_ref_env()
  olgular <- .pk_ref_facts(env)

  metin <- paste0(
    "Genel gorunum program tarafinda baskiya isaret ediyor. ",
    "Sonuc {{fact:uydurma.sum.overall.ffffff}} olarak olculdu. ",
    "Buna karsilik ", .pk_ref_token(env, olgular, "GecikenAktivite", "sum"),
    " geciken aktivite izlenmeye devam ediyor. ",
    "Kirilimlarin birlikte degerlendirilmesi daha anlamli olacaktir."
  )

  bloklu <- env$pk_numeric_provenance_apply(metin, olgular, mode = "block",
                                            fallback_text = "- Hesaplanan deger")
  expect_false(bloklu$blocked)
  expect_true(grepl("Genel gorunum program tarafinda", bloklu$text, fixed = TRUE))
  expect_true(grepl("15.448 geciken aktivite", bloklu$text, fixed = TRUE))
  expect_true(grepl("daha anlamli olacaktir", bloklu$text, fixed = TRUE))
  # YALNIZCA sorunlu cumle dusrulur.
  expect_false(grepl("Sonuc", bloklu$text, fixed = TRUE))
})

test_that("block kipi ayiklamasi MARKDOWN YAPISINI bozmaz", {
  env <- .pk_ref_env()
  olgular <- .pk_ref_facts(env)

  metin <- paste0(
    "## Genel durum\n\n",
    "Program tarafinda gecikme birikimi dikkat cekiyor: ",
    .pk_ref_token(env, olgular, "GecikenAktivite", "sum"), " geciken aktivite. ",
    "Kapasite tarafinda {{fact:olmayan.sum.overall.zzzzzz}} kisi gorunuyor. ",
    "Kirilimlar birlikte degerlendirilmelidir.\n\n",
    "### Dikkat cekenler\n",
    "- Butce tarafinda ", .pk_ref_token(env, olgular, "Butce", "sum"), " tutar izleniyor.\n",
    "- Kapasite tarafinda {{fact:olmayan2.sum.overall.zzzzzz}} kisi gorunuyor.\n",
    "- Program disiplinlerinde farklilasma var.\n\n",
    "Bir siniri belirtmek gerekir: paket, gecikmelerin nedenini gostermez."
  )

  sonuc <- env$pk_numeric_provenance_apply(metin, olgular, mode = "block",
                                           fallback_text = "- Deger")
  expect_false(sonuc$blocked)
  satirlar <- strsplit(sonuc$text, "\n", fixed = TRUE)[[1]]

  # Basliklar, PARAGRAF SINIRLARI (bos satir) ve madde imleri KORUNUR; aksi
  # halde baslik, liste ve paragraf birbirine yapisip markdown bozulurdu.
  expect_identical(satirlar[1], "## Genel durum")
  expect_identical(satirlar[2], "")
  expect_identical(satirlar[4], "")
  expect_identical(satirlar[5], "### Dikkat cekenler")
  expect_true(any(satirlar == ""))
  expect_identical(
    grep("^- ", satirlar, value = TRUE),
    c("- Butce tarafinda 125.000 TL tutar izleniyor.",
      "- Program disiplinlerinde farklilasma var.")
  )

  # YALNIZCA sorunlu cumle ve sorunlu madde dusrulur.
  expect_false(grepl("Kapasite tarafinda", sonuc$text, fixed = TRUE))
  expect_true(grepl("15.448 geciken aktivite", sonuc$text, fixed = TRUE))
  expect_true(grepl("Kirilimlar birlikte degerlendirilmelidir", sonuc$text, fixed = TRUE))
  expect_true(grepl("Bir siniri belirtmek gerekir", sonuc$text, fixed = TRUE))
})

test_that("log kipi yaniti KULLANICIYA TESLIM EDER ve bastirmaz", {
  env <- .pk_ref_env()
  olgular <- .pk_ref_facts(env)

  metin <- paste0(
    "Program tarafinda gecikme birikimi dikkat cekiyor. ",
    "Sonuc {{fact:uydurma.sum.overall.ffffff}} olarak olculdu ve ayrica ",
    "99.999 saat harcandi. Kirilimlar birlikte degerlendirilmelidir."
  )

  sonuc <- env$pk_numeric_provenance_apply(metin, olgular, mode = "log",
                                           fallback_text = "- Hesaplanan deger")
  expect_false(sonuc$blocked)
  expect_true(grepl("Program tarafinda gecikme birikimi", sonuc$text, fixed = TRUE))
  expect_true(grepl("Kirilimlar birlikte degerlendirilmelidir", sonuc$text, fixed = TRUE))
  expect_false(grepl("Yanıt doğrulanamadı", sonuc$text))
  # Bulgular YINE kaydedilir.
  expect_gt(length(sonuc$mismatches), 0L)
})

test_that("warn kipi yaniti korur ve GORUNUR not ekler (ham deger YAZMAZ)", {
  env <- .pk_ref_env()
  olgular <- .pk_ref_facts(env)

  sonuc <- env$pk_numeric_provenance_apply(
    "Sonuc {{fact:uydurma.sum.overall.ffffff}} olarak olculdu.", olgular,
    mode = "warn", fallback_text = "- Hesaplanan deger"
  )
  expect_false(sonuc$blocked)
  expect_true(grepl("Doğrulama notu", sonuc$text))
  expect_true(grepl("bilinmeyen olgu", sonuc$text))
  expect_false(grepl("uydurma.sum.overall.ffffff", sonuc$text, fixed = TRUE))
})

test_that("block kipi kullanilabilir icerik kalmadiginda deterministik ozete iner", {
  env <- .pk_ref_env()
  olgular <- .pk_ref_facts(env)

  sonuc <- env$pk_numeric_provenance_apply(
    "Toplam 99.999 saat harcandi.", olgular, mode = "block",
    fallback_text = "- Geciken aktivite (sum): 15.448"
  )
  expect_true(sonuc$blocked)
  expect_true(grepl("Yanıt doğrulanamadı", sonuc$text))
  expect_true(grepl("- Geciken aktivite (sum): 15.448", sonuc$text, fixed = TRUE))
})

test_that("off kipi referanslari cozer ama telemetri/gorunur not URETMEZ", {
  env <- .pk_ref_env()
  olgular <- .pk_ref_facts(env)

  sonuc <- env$pk_numeric_provenance_apply(
    paste0(.pk_ref_token(env, olgular, "GecikenAktivite", "sum"), " aktivite gecikti."),
    olgular, mode = "off"
  )
  expect_identical(sonuc$text, "15.448 aktivite gecikti.")
  cikti <- utils::capture.output(env$pk_numeric_provenance_report(sonuc, "q_off"))
  expect_length(cikti, 0L)
})

test_that("cozumleyici cokmesi log kipinde yaniti KORUR, block kipinde KAPALI BASARISIZ olur", {
  env <- .pk_ref_env()
  env$pk_numeric_provenance_validate <- function(text, facts) stop("sentetik cokme")

  gevsek <- env$pk_numeric_provenance_apply("Dogal analiz metni.", list(), mode = "log")
  expect_identical(gevsek$text, "Dogal analiz metni.")
  expect_false(gevsek$blocked)
  expect_identical(gevsek$mismatches[[1]]$reason, "render_degraded")

  sert <- env$pk_numeric_provenance_apply("Dogal analiz metni.", list(), mode = "block",
                                          fallback_text = "- Deger")
  expect_true(sert$blocked)
  expect_false(grepl("Dogal analiz metni", sert$text, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# TELEMETRİ — protokol ve güven bulguları AYRI raporlanır
# ---------------------------------------------------------------------------

test_that("telemetri protokol ve guven bulgularini AYRI sayaclarla yazar", {
  env <- .pk_ref_env()
  olgular <- .pk_ref_facts(env)

  sonuc <- env$pk_numeric_provenance_apply(
    paste0("Toplam 99.999 saat harcandi. Sonuc {{fact:uydurma.sum.overall.ffffff}} ",
           "olarak olculdu ve ", .pk_ref_token(env, olgular, "GecikenAktivite", "sum"),
           " aktivite gecikti."),
    olgular, mode = "log"
  )

  cikti <- paste(utils::capture.output(
    env$pk_numeric_provenance_report(sonuc, "q_telemetri")
  ), collapse = "\n")

  expect_true(grepl("protokol=1", cikti, fixed = TRUE))
  expect_true(grepl("guven=1", cikti, fixed = TRUE))
  expect_true(grepl("protokol_dagilim=model_numeric_literal=1", cikti, fixed = TRUE))
  expect_true(grepl("guven_dagilim=unknown_fact=1", cikti, fixed = TRUE))
  # Ham is degeri ve duzyazi LOGA GIRMEZ.
  expect_false(grepl("99.999", cikti, fixed = TRUE))
  expect_false(grepl("harcandi", cikti, fixed = TRUE))
})

test_that("kip cozumlemesi gecersiz degerde log'a duser ve sozlesme degerlerini korur", {
  env <- .pk_ref_env()
  expect_identical(env$PK_PROV_MODES, c("off", "log", "warn", "block"))
  testthat::skip_if_not_installed("withr")

  withr::with_envvar(list(MERGEN_PK_NUMERIC_PROVENANCE_MODE = NA_character_), {
    expect_identical(env$pk_numeric_provenance_mode(), "log")
  })
  withr::with_envvar(list(MERGEN_PK_NUMERIC_PROVENANCE_MODE = "saldirgan"), {
    expect_identical(env$pk_numeric_provenance_mode(), "log")
  })
  withr::with_envvar(list(MERGEN_PK_NUMERIC_PROVENANCE_MODE = "block"), {
    expect_identical(env$pk_numeric_provenance_mode(), "block")
  })
})

# ---------------------------------------------------------------------------
# ÜRETİM ÖRÜNTÜLERİ — çok olgulu doğal cümleler
# ---------------------------------------------------------------------------

test_that("uretimde gorulen cok olgulu dogal cumleler TAM cozulur", {
  env <- .pk_ref_env()
  olgular <- .pk_ref_facts(env)

  metin <- paste0(
    "Zamaninda tamamlanan islerin yaninda ",
    .pk_ref_token(env, olgular, "GecikenAktivite", "sum"), " geciken aktivite, ",
    .pk_ref_token(env, olgular, "TamamlanmaYuzde", "weighted_mean"),
    " agirlikli tamamlanma ve ", .pk_ref_token(env, olgular, "SPI", "mean"),
    " SPI ile birlikte degerlendirildiginde, ",
    .pk_ref_token(env, olgular, "PlanlananSaatSapmasi", "sum"),
    " planlanan saat sapmasi program riskini artiriyor. ",
    "Toplam ", .pk_ref_token(env, olgular, "Butce", "sum"),
    " butce ve ", .pk_ref_token(env, olgular, "KalanIscilik_sa", "sum"),
    " kalan iscilik, kaynak planinin gozden gecirilmesini gerektiriyor."
  )

  sonuc <- env$pk_numeric_provenance_apply(metin, olgular, mode = "block",
                                           fallback_text = "- Deger")
  expect_false(sonuc$blocked)
  expect_identical(sonuc$resolved, 6L)
  expect_length(sonuc$mismatches, 0L)
  for (beklenen in c("15.448 geciken aktivite", "%61,3 agirlikli tamamlanma",
                     "0,87 SPI", "-2.450 saat planlanan saat sapmasi",
                     "125.000 TL butce", "18.420,5 saat kalan iscilik")) {
    expect_true(grepl(beklenen, sonuc$text, fixed = TRUE), info = beklenen)
  }
})
