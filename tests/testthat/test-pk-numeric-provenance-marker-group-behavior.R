# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-numeric-provenance-marker-group-behavior.R
# Açıklama: BİTİŞİK `[fact:...]` İŞARET GRUPLARI için davranışsal regresyon.
#
#           ÜRETİM BELİRTİSİ (PR #719): "Proje ve Kaynak Analizi" yanıtındaki
#           HER SAYI DOĞRUYKEN kullanıcı "Yanıt doğrulanamadı" görüyordu:
#             `iddia=116 | uyusmazlik=36 | oran=0.310 |
#              nedenler=missing_fact_marker,no_number,unit_missing,value_mismatch`
#           9.551 karakterlik analiz düzyazısı deterministik "Hesaplanan
#           değerler" listesiyle DEĞİŞTİRİLİYORDU.
#
#           KÖK NEDEN: model doğal Türkçe yazınca değerleri sıralayıp işaretleri
#           SONA topluyor. Eski tarayıcı yalnızca İLK işareti bir sayıya
#           bağlıyor ve YANLIŞ sayıyı (en sağdakini) seçiyor; kalan işaretler
#           boş pencere görüp `no_number`, önceki sayılar ise
#           `missing_fact_marker` sayılıyordu. TEK doğru cümle beş uyuşmazlık
#           üretiyordu.
#
#           KAPSAM SÖZLEŞMESİ: yanlış pozitifler, tanılamayı BASTIRARAK değil
#           GERÇEK hataların hâlâ yakalandığını KANITLAYARAK kapatılır. Eşik
#           düşürme, kip çevirme veya köken doğrulamasını devre dışı bırakma
#           YOKTUR.
#
#           Testler ÇEVRİMDIŞI ve DETERMİNİSTİKtir: gerçek LLM/DB/ağ yoktur;
#           üretim SQL'i, proje adı veya kimlik bilgisi KULLANILMAZ.
# ==============================================================================

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}

.prov_grup_env <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  # Bagimlilik sirasi calisma zamani manifestiyle AYNI: dogrulayici -> baglama
  # katmani -> duzyazi tarayicisi.
  for (dosya in c("helpers_pk_precision.R",
                  "helpers_pk_numeric_provenance.R",
                  "helpers_pk_numeric_provenance_binding.R",
                  "helpers_pk_numeric_provenance_claims.R")) {
    source(file.path(kok, "R", dosya), encoding = "UTF-8", local = env)
  }
  env
}

.prov_grup_olgu <- function(id, value, unit = NULL, aggregation = NULL,
                            kind = NULL) {
  list(fact_id = id, value = value, unit = unit, aggregation = aggregation,
       kind = kind, column = "SentetikSutun")
}

.prov_grup_nedenler <- function(sonuc) {
  sort(unique(vapply(sonuc$mismatches %||% list(),
                     function(m) as.character(m$reason %||% "?")[1], character(1))))
}

# Uretim yanitinin yapisini (coklu deger + sona toplanmis isaretler) taklit eden
# sentetik olgu kumesi. Degerler sentetiktir.
.prov_grup_olgular <- function() {
  list(
    .prov_grup_olgu("m_toplam.sum.overall.aaa", 50367, unit = "adet",
                    aggregation = "sum"),
    .prov_grup_olgu("m_zamaninda.sum.overall.bbb", 27707, unit = "adet",
                    aggregation = "sum"),
    .prov_grup_olgu("m_geciken.sum.overall.ccc", 15448, unit = "adet",
                    aggregation = "sum"),
    .prov_grup_olgu("m_erken.sum.overall.ddd", 3823, unit = "adet",
                    aggregation = "sum"),
    .prov_grup_olgu("m_toplam.mean.overall.eee", 149, unit = "adet",
                    aggregation = "mean"),
    .prov_grup_olgu("m_toplam.median.overall.fff", 57, unit = "adet",
                    aggregation = "median")
  )
}

# ---------------------------------------------------------------------------
# 1) Uretim senaryosu: uc deger, sona toplanmis uc isaret.
# ---------------------------------------------------------------------------

test_that("sona toplanmis isaret grubu ONCEKI sayilara SIRAYLA baglanir", {
  env <- .prov_grup_env()

  sonuc <- env$pk_numeric_provenance_validate(
    paste0("Aktivitelerin durum dagiliminda zamaninda bitenler 27.707, ",
           "gecikenler 15.448, erken bitenler 3.823 olarak gozleniyor ",
           "[fact:m_zamaninda.sum.overall.bbb]",
           "[fact:m_geciken.sum.overall.ccc]",
           "[fact:m_erken.sum.overall.ddd]."),
    .prov_grup_olgular()
  )

  expect_identical(sonuc$checked, 3L)
  expect_length(sonuc$mismatches, 0L)
  expect_identical(
    vapply(sonuc$claims, function(x) x$number_text, character(1)),
    c("27.707", "15.448", "3.823")
  )
})

test_that("grup icindeki sayilar SATIR SONU ile ayrilmis isaretlerde de eslesir", {
  env <- .prov_grup_env()

  # Model isaretleri satir sonuna tasiyabilir; bu bir BICIM ayrintisidir.
  sonuc <- env$pk_numeric_provenance_validate(
    paste0("- Toplam aktivite: 50.367 adet, proje basina ortalama 149, ",
           "medyan 57 [fact:m_toplam.sum.overall.aaa]",
           "[fact:m_toplam.mean.overall.eee]\n",
           "[fact:m_toplam.median.overall.fff]"),
    .prov_grup_olgular()
  )

  expect_identical(sonuc$checked, 3L)
  expect_length(sonuc$mismatches, 0L)
})

test_that("uretim benzeri TAM yanit sifir uyusmazlik verir", {
  env <- .prov_grup_env()

  metin <- paste0(
    "### Ozet\n",
    "Portfoyde 342 proje bulunmakta olup toplam 50.367 aktivite iceriyor ",
    "[fact:m_toplam.sum.overall.aaa]. Aktivitelerin durum dagiliminda ",
    "zamaninda bitenler 27.707, gecikenler 15.448, erken bitenler 3.823 ",
    "olarak gozleniyor [fact:m_zamaninda.sum.overall.bbb]",
    "[fact:m_geciken.sum.overall.ccc]\n[fact:m_erken.sum.overall.ddd].\n\n",
    "### Gozlemler\n",
    "- **Toplam aktivite**: 50.367 adet, proje basina ortalama 149, medyan 57 ",
    "[fact:m_toplam.sum.overall.aaa][fact:m_toplam.mean.overall.eee]\n",
    "[fact:m_toplam.median.overall.fff]\n"
  )

  sonuc <- env$pk_numeric_provenance_validate(metin, .prov_grup_olgular())

  expect_length(sonuc$mismatches, 0L)
  expect_equal(sonuc$rate, 0)

  # `block` kipi bu yaniti ARTIK ENGELLEMEZ; kullanici analiz duzyazisini gorur.
  uygulanan <- env$pk_numeric_provenance_apply(
    metin, .prov_grup_olgular(), mode = "block",
    fallback_text = "Hesaplanan degerler"
  )
  expect_false(isTRUE(uygulanan$blocked))
  expect_true(grepl("Gozlemler", uygulanan$text, fixed = TRUE))
  # Isaretler gosterimden SILINIR.
  expect_false(grepl("[fact:", uygulanan$text, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# 2) KORUMA GEVSEMEZ: gercek sayisal hatalar grup icinde de yakalanir.
# ---------------------------------------------------------------------------

test_that("grup icindeki YANLIS bir sayi hala value_mismatch uretir", {
  env <- .prov_grup_env()

  sonuc <- env$pk_numeric_provenance_validate(
    paste0("Zamaninda 27.707, geciken 99.999, erken 3.823 ",
           "[fact:m_zamaninda.sum.overall.bbb]",
           "[fact:m_geciken.sum.overall.ccc]",
           "[fact:m_erken.sum.overall.ddd]."),
    .prov_grup_olgular()
  )

  expect_true("value_mismatch" %in% .prov_grup_nedenler(sonuc))

  engellenen <- env$pk_numeric_provenance_apply(
    paste0("Zamaninda 27.707, geciken 99.999, erken 3.823 ",
           "[fact:m_zamaninda.sum.overall.bbb]",
           "[fact:m_geciken.sum.overall.ccc]",
           "[fact:m_erken.sum.overall.ddd]."),
    .prov_grup_olgular(), mode = "block", fallback_text = "Hesaplanan degerler"
  )
  expect_true(isTRUE(engellenen$blocked))
  expect_true(grepl("Hesaplanan degerler", engellenen$text, fixed = TRUE))
})

test_that("grup icinde bilinmeyen olgu kimligi hala reddedilir", {
  env <- .prov_grup_env()

  sonuc <- env$pk_numeric_provenance_validate(
    paste0("Zamaninda 27.707, geciken 15.448 ",
           "[fact:m_zamaninda.sum.overall.bbb][fact:olmayan.sum.overall.zzz]."),
    .prov_grup_olgular()
  )

  expect_true("unknown_fact" %in% .prov_grup_nedenler(sonuc))
})

test_that("gruptan ONCE alintilanmamis VERI gorunumlu sayi hala raporlanir", {
  env <- .prov_grup_env()

  # Iki isaret, UC sayi: en sondaki iki sayi baglanir, ilki KOKEN-SIZ kalir.
  sonuc <- env$pk_numeric_provenance_validate(
    paste0("Uydurma 77.777 adet, zamaninda 27.707, geciken 15.448 ",
           "[fact:m_zamaninda.sum.overall.bbb][fact:m_geciken.sum.overall.ccc]."),
    .prov_grup_olgular()
  )

  expect_true("missing_fact_marker" %in% .prov_grup_nedenler(sonuc))
})

test_that("CUMLE SINIRI grubun bagini keser", {
  env <- .prov_grup_env()

  # Ikinci cumlede sayi YOKTUR; onceki cumlenin sayilari baglanmamalidir.
  sonuc <- env$pk_numeric_provenance_validate(
    paste0("Zamaninda 27.707 ve geciken 15.448 olcumlendi. Durum ",
           "degerlendirildi [fact:m_zamaninda.sum.overall.bbb]",
           "[fact:m_geciken.sum.overall.ccc]."),
    .prov_grup_olgular()
  )

  # Sayilar baglanmadigi icin alintilanmamis sayilirlar.
  expect_length(sonuc$claims, 0L)
  expect_true("missing_fact_marker" %in% .prov_grup_nedenler(sonuc))
})

test_that("CUMLE SONU noktalamasi iki isareti AYNI gruba sokmaz", {
  env <- .prov_grup_env()

  sonuc <- env$pk_numeric_provenance_validate(
    paste0("Zamaninda 27.707 [fact:m_zamaninda.sum.overall.bbb]. ",
           "Geciken 15.448 [fact:m_geciken.sum.overall.ccc]."),
    .prov_grup_olgular()
  )

  expect_identical(sonuc$checked, 2L)
  expect_length(sonuc$mismatches, 0L)
})

# ---------------------------------------------------------------------------
# 3) KISITLI UZLASTIRMA: sira kusuru, sayisal hata degildir.
# ---------------------------------------------------------------------------

test_that("grup icinde SIRASI karisik isaretler uzlastirilir", {
  env <- .prov_grup_env()

  # Her sayi DOGRU bir olguya esittir; yalnizca isaret SIRASI farklidir.
  sonuc <- env$pk_numeric_provenance_validate(
    paste0("Zamaninda 27.707, geciken 15.448, erken 3.823 ",
           "[fact:m_erken.sum.overall.ddd]",
           "[fact:m_zamaninda.sum.overall.bbb]",
           "[fact:m_geciken.sum.overall.ccc]."),
    .prov_grup_olgular()
  )

  expect_length(sonuc$mismatches, 0L)
})

test_that("uzlastirma DEGER URETMEZ: esleme yoksa uyusmazlik raporlanir", {
  env <- .prov_grup_env()

  # Sayilardan biri HICBIR alintilanan olguya esit degildir; birebir esleme
  # kurulamaz ve konumsal sira korunarak gercek hata raporlanir.
  sonuc <- env$pk_numeric_provenance_validate(
    paste0("Birinci 27.707, ikinci 88.888 ",
           "[fact:m_geciken.sum.overall.ccc][fact:m_zamaninda.sum.overall.bbb]."),
    .prov_grup_olgular()
  )

  expect_true("value_mismatch" %in% .prov_grup_nedenler(sonuc))
})

# ---------------------------------------------------------------------------
# 4) Toplulastirma baglami HER SAYI icin AYRI cozulur.
# ---------------------------------------------------------------------------

test_that("grup icinde her sayi KENDI toplulastirma sozcugunu gorur", {
  env <- .prov_grup_env()

  # "ortalama" sozcugu SADECE ikinci sayiya aittir; ortak pencere kullanilsaydi
  # en sagdaki sozcuk hepsini ezerdi.
  sonuc <- env$pk_numeric_provenance_validate(
    paste0("Toplam 50.367, ortalama 149 ",
           "[fact:m_toplam.sum.overall.aaa][fact:m_toplam.mean.overall.eee]."),
    .prov_grup_olgular()
  )

  expect_false("aggregation_mismatch" %in% .prov_grup_nedenler(sonuc))
})

test_that("GERCEK toplulastirma uyusmazligi grup icinde de yakalanir", {
  env <- .prov_grup_env()

  # Ikinci sayi "ortalama" diye sunulur ama MEDYAN olgusu alintilanir.
  sonuc <- env$pk_numeric_provenance_validate(
    paste0("Toplam 50.367, ortalama 57 ",
           "[fact:m_toplam.sum.overall.aaa][fact:m_toplam.median.overall.fff]."),
    .prov_grup_olgular()
  )

  expect_true("aggregation_mismatch" %in% .prov_grup_nedenler(sonuc))
})

# ---------------------------------------------------------------------------
# 5) Sayisiz isaret UYUSMAZLIK degildir ama SESSIZ de degildir.
# ---------------------------------------------------------------------------

test_that("niteliksel cumledeki isaret uyusmazlik uretmez, tanilamada gorunur", {
  env <- .prov_grup_env()

  sonuc <- env$pk_numeric_provenance_validate(
    "Gecikme egilimi dikkat cekicidir [fact:m_geciken.sum.overall.ccc].",
    .prov_grup_olgular()
  )

  expect_length(sonuc$mismatches, 0L)
  expect_length(sonuc$numberless, 1L)
  expect_identical(sonuc$numberless[[1]]$fact_id, "m_geciken.sum.overall.ccc")
})

# ---------------------------------------------------------------------------
# 6) BOYUTSUZ sayim birimi uydurma degildir; olcek tasiyan birim uydurmadir.
# ---------------------------------------------------------------------------

test_that("birimsiz olguya 'adet' yazmak uyusmazlik uretmez", {
  env <- .prov_grup_env()
  olgular <- list(.prov_grup_olgu("f.sum.overall.aaa", 50367, aggregation = "sum"))

  sonuc <- env$pk_numeric_provenance_validate(
    "Toplam 50.367 adet [fact:f.sum.overall.aaa].", olgular
  )

  expect_length(sonuc$mismatches, 0L)
})

test_that("birimsiz olguya OLCEK tasiyan birim yazmak hala yakalanir", {
  env <- .prov_grup_env()
  olgular <- list(.prov_grup_olgu("f.sum.overall.aaa", 50367, aggregation = "sum"))

  sonuc <- env$pk_numeric_provenance_validate(
    "Toplam 50.367 saat [fact:f.sum.overall.aaa].", olgular
  )

  expect_true("unit_mismatch" %in% .prov_grup_nedenler(sonuc))
})

# ---------------------------------------------------------------------------
# 7) Telemetri: neden DAGILIMI ve olgu kimlikleri raporlanir, DEGERLER raporlanmaz.
# ---------------------------------------------------------------------------

test_that("rapor neden dagilimini verir ama iddia edilen DEGERI yazmaz", {
  env <- .prov_grup_env()

  sonuc <- env$pk_numeric_provenance_apply(
    paste0("Zamaninda 27.707, geciken 99.999 ",
           "[fact:m_zamaninda.sum.overall.bbb][fact:m_geciken.sum.overall.ccc]."),
    .prov_grup_olgular(), mode = "log"
  )

  cikti <- paste(utils::capture.output(
    env$pk_numeric_provenance_report(sonuc, "gen_00")
  ), collapse = "\n")

  expect_true(grepl("dagilim=", cikti, fixed = TRUE))
  expect_true(grepl("value_mismatch=1", cikti, fixed = TRUE))
  expect_true(grepl("m_geciken.sum.overall.ccc", cikti, fixed = TRUE))
  # Iddia edilen/gercek DEGERLER veri degeridir ve loga GIRMEZ.
  expect_false(grepl("99.999", cikti, fixed = TRUE))
  expect_false(grepl("15448", cikti, fixed = TRUE))
})
