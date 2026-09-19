# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-numeric-provenance-token-scan-behavior.R
# Açıklama: Sayısal köken TARAYICISININ jeton sınırı, birim tanıma ve
#           bitişiklik kararları için davranışsal regresyon.
#
#           Bu dosya, PR #719 incelemesinde açılan ve TAMAMI ÜRETİMDE GÖZLENEN
#           bir davranış farkı üreten bulguları kapatır:
#
#             * madde numarası (`1. Oneri: 5.000 TL`) desen tarafından
#               yutulduğunda bir olguya BAĞLANABİLİYORDU;
#             * `15.574.` biçiminde sondaki nokta jetonun kayıtlı bitişine
#               giriyor, jeton parça sınırının DIŞINDA kalıyor ve doğru alıntı
#               "işaret var, sayı yok" sayılıyordu;
#             * önek para birimi (`TL`/`USD`/`EUR` simgeleri) ve üstel gösterim
#               (`1e6`) hiç sayı sayılmıyor, alıntılanmamış bir büyüklük
#               `missing_fact_marker` ÜRETMEDEN yayımlanıyordu;
#             * türetme ekli birim (`47 saatlik`) ve boyutsuz sayım birimi
#               (`47 kayit`) alıntısız tarayıcıda TANINMIYORDU;
#             * `-2024` işaretli sayı YIL muafiyetine düşüp denetimi atlıyordu;
#             * uzun bir cümlenin BAŞINDAKİ ilgisiz yıl, cümle parçası aynı
#               olduğu için işarete bağlanıp `value_mismatch` üretiyordu.
#
#           KAPSAM SÖZLEŞMESİ: her düzeltme için hem YANLIŞ POZİTİFİN kapandığı
#           hem de GERÇEK korumanın sürdüğü ayrı ayrı kanıtlanır. Testler
#           çevrimdışı ve deterministiktir; gerçek LLM/DB/ağ, üretim SQL'i,
#           proje adı veya kimlik bilgisi KULLANILMAZ.
# ==============================================================================

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}

.prov_tarama_env <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  # Bagimlilik sirasi calisma zamani manifestiyle AYNI.
  for (dosya in c("helpers_pk_precision.R",
                  "helpers_pk_numeric_provenance.R",
                  "helpers_pk_numeric_provenance_binding.R",
                  "helpers_pk_numeric_provenance_claims.R")) {
    source(file.path(kok, "R", dosya), encoding = "UTF-8", local = env)
  }
  env
}

.prov_tarama_olgu <- function(id, value, unit = NULL, aggregation = NULL,
                              column = "SentetikSutun") {
  list(fact_id = id, value = value, unit = unit, aggregation = aggregation,
       column = column)
}

.prov_tarama_nedenler <- function(sonuc) {
  sort(unique(vapply(sonuc$mismatches %||% list(),
                     function(m) as.character(m$reason %||% "?")[1], character(1))))
}

# ---------------------------------------------------------------------------
# 1) MADDE NUMARASI bir olcu degildir ve bir olguya baglanamaz.
# ---------------------------------------------------------------------------

test_that("satir basindaki madde numarasi baglama adayi olmaz", {
  env <- .prov_tarama_env()
  olgular <- list(.prov_tarama_olgu("a", 5000, unit = "TL"))

  # Desen "1. Oneri" ifadesini TEK jeton olarak yutar; eski kalip (`^[0-9]+[.)]?$`)
  # artik tutmaz ve madde numarasi `1` bir olguya baglanabilirdi.
  sonuc <- env$pk_numeric_provenance_validate(
    "1. Oneri: 5.000 TL [fact:a]", olgular
  )

  expect_identical(sonuc$checked, 1L)
  expect_length(sonuc$mismatches %||% list(), 0L)
  expect_identical(as.character(sonuc$claims[[1]]$number_text)[1], "5.000")
})

test_that("madde numarasi olmayan cumle basi sayisi HALA olcudur", {
  env <- .prov_tarama_env()
  olgular <- list(.prov_tarama_olgu("a", 27707))

  # "27.707" satir basinda ama madde numarasi DEGILDIR (noktadan sonra rakam
  # gelir); koruma daralmamalidir.
  sonuc <- env$pk_numeric_provenance_validate("27.707 aktivite [fact:a]", olgular)
  expect_identical(sonuc$checked, 1L)
  expect_length(sonuc$mismatches %||% list(), 0L)
})

test_that("sayısal madde içeriği liste numarasına bağlanmaz", {
  env <- .prov_tarama_env()
  olgular <- list(.prov_tarama_olgu("a", 15574, aggregation = "count"),
                 .prov_tarama_olgu("b", 15574, aggregation = "count"))
  for (ayrac in c(" ", "\t", intToUtf8(0x00a0))) {
    for (madde in c("1.", "12.", "1)", "12)")) {
      metin <- paste0(madde, ayrac, "15.574 adet [fact:a][fact:b]")
      sonuc <- env$pk_numeric_provenance_validate(metin, olgular)
      expect_identical(sonuc$checked, 1L, info = metin)
      expect_length(sonuc$mismatches, 0L)
      expect_identical(sonuc$claims[[1]]$number_text, "15.574")
      yanlis <- env$pk_numeric_provenance_validate(
        sub("15.574", "11.111", metin, fixed = TRUE), olgular
      )
      expect_true("value_mismatch" %in% .prov_tarama_nedenler(yanlis))
    }
  }
})

# ---------------------------------------------------------------------------
# 2) SONDAKI NOKTALAMA jetonun parcasi degildir.
# ---------------------------------------------------------------------------

test_that("cumle sonu noktasi jetonu parca sinirindan DUSURMEZ", {
  env <- .prov_tarama_env()
  olgular <- list(.prov_tarama_olgu("f", 15574))

  sonuc <- env$pk_numeric_provenance_validate("Toplam 15.574. [fact:f]", olgular)

  expect_identical(sonuc$checked, 1L)
  expect_length(sonuc$mismatches %||% list(), 0L)
  expect_length(sonuc$numberless %||% list(), 0L)
  expect_identical(as.character(sonuc$claims[[1]]$number_text)[1], "15.574")
})

test_that("noktalamali jetonda YANLIS deger hala yakalanir", {
  env <- .prov_tarama_env()
  olgular <- list(.prov_tarama_olgu("f", 15574))

  sonuc <- env$pk_numeric_provenance_validate("Toplam 11.111. [fact:f]", olgular)
  expect_true("value_mismatch" %in% .prov_tarama_nedenler(sonuc))
})

# ---------------------------------------------------------------------------
# 3) ONEK PARA BIRIMI ve USTEL GOSTERIM sayisal iddiadir.
# ---------------------------------------------------------------------------

test_that("onek para birimi ve ustel gosterim ALINTISIZ iddia olarak taranir", {
  env <- .prov_tarama_env()

  ornekler <- list(
    list(metin = paste0("Butce ", intToUtf8(8378L), "1.250.000 olarak belirlendi."),
         ad = "TL simgesi"),
    list(metin = "Butce $250.000 olarak belirlendi.", ad = "USD simgesi"),
    list(metin = "Kapasite 1e6 olarak olculdu.", ad = "ustel gosterim")
  )

  for (ornek in ornekler) {
    tarama <- env$pk_prov_scan_claims(ornek$metin)
    expect_equal(length(tarama$uncited), 1L, info = ornek$ad)
  }
})

test_that("ustel gosterimin DEGERI dogru cozulur", {
  env <- .prov_tarama_env()

  expect_equal(env$pk_parse_number_candidates("1e6"), 1e6)
  expect_equal(env$pk_parse_number_candidates("1E6"), 1e6)
  expect_equal(env$pk_parse_number_candidates("-1e3"), -1000)
  expect_equal(env$pk_parse_number_candidates("2,5e-3"), 0.0025)
  # Tasan us SONLU bir deger uretmez ve aday DONDURULMEZ.
  expect_length(env$pk_parse_number_candidates("1e999"), 0L)
  # Mevcut Turkce ayrac davranisi DEGISMEZ.
  expect_equal(env$pk_parse_number_candidates("15.574"), 15574)
})

test_that("onek para birimi ALINTILI yolda birim olarak cozulur", {
  env <- .prov_tarama_env()
  olgular <- list(.prov_tarama_olgu("b", 1250, unit = "TL"))

  sonuc <- env$pk_numeric_provenance_validate(
    paste0("Butce ", intToUtf8(8378L), "1.250 [fact:b] olarak belirlendi."),
    olgular
  )

  expect_identical(sonuc$checked, 1L)
  expect_length(sonuc$mismatches %||% list(), 0L)
})

# ---------------------------------------------------------------------------
# 4) ALINTISIZ tarayici, alintili yolla AYNI birim sozlugunu kullanir.
# ---------------------------------------------------------------------------

test_that("turetme ekli ve sayim birimleri alintisiz taramada TANINIR", {
  env <- .prov_tarama_env()

  for (metin in c("Sure 47 saatlik bir araliktir.",
                  "Toplam 47 kayit bulundu.",
                  "Toplam 47 tane bulundu.",
                  "Toplam 47 adet bulundu.")) {
    tarama <- env$pk_prov_scan_claims(metin)
    expect_equal(length(tarama$uncited), 1L, info = metin)
  }
})

test_that("siradan Turkce ad HALA veri iddiasi sayilmaz", {
  env <- .prov_tarama_env()

  # "farkli kaynak" bir olcu birimi degildir; yanlis pozitif uretmemelidir.
  for (metin in c("Toplam 47 farkli kaynak vardir.",
                  "Konu 3 kez gundeme geldi.")) {
    tarama <- env$pk_prov_scan_claims(metin)
    expect_equal(length(tarama$uncited), 0L, info = metin)
  }
})

# ---------------------------------------------------------------------------
# 5) ISARETLI sayi YIL muafiyetine dusmez.
# ---------------------------------------------------------------------------

test_that("eksi imli dort haneli sayi YIL sayilmaz", {
  env <- .prov_tarama_env()

  eksi <- env$pk_prov_scan_claims("Fark -2024 olarak olculdu.")
  expect_length(eksi$uncited, 1L)

  # Gercek yil muafiyeti KORUNUR.
  yil <- env$pk_prov_scan_claims("Yil 2024 icinde gerceklesti.")
  expect_length(yil$uncited, 0L)
})

# ---------------------------------------------------------------------------
# 6) BITISIKLIK: uzak bir sayi isarete baglanmaz.
# ---------------------------------------------------------------------------

test_that("uzak sayi isarete baglanmaz, isaret SAYISIZ kalir", {
  env <- .prov_tarama_env()
  olgular <- list(.prov_tarama_olgu("g", 15448))

  uzak <- paste0("2024 yilinda bir iki uc dort bes alti yedi sekiz dokuz on ",
                 "onbir onikinci gecikme egilimi dikkat cekicidir [fact:g]")
  sonuc <- env$pk_numeric_provenance_validate(uzak, olgular)

  # Ilgisiz yil `value_mismatch` URETMEZ; nitel atif sayisiz raporlanir.
  expect_length(sonuc$mismatches %||% list(), 0L)
  expect_length(sonuc$numberless %||% list(), 1L)
})

test_that("mesafe sayimi TURKCE harfleri ayrac saymaz", {
  env <- .prov_tarama_env()

  # PCRE'de `[:alnum:]` varsayilan olarak YALNIZCA ASCII esler. Turkce
  # harfleri ayrac sayan bir bolme ayni ifadeyi DAHA COK sozcuk sayar, mesafe
  # tavani Turkce duzyazida sistematik olarak DARALIR ve gecerli alintilar
  # kopardi.
  ascii <- "X gecikme egilimi dikkat cekicidir Y"
  turkce <- paste0("X gecikme e", intToUtf8(287L), "ilimi dikkat ",
                   intToUtf8(231L), "ekicidir Y")

  expect_identical(
    env$.pk_prov_gap_words(ascii, 3L, nchar(ascii) - 2L),
    env$.pk_prov_gap_words(turkce, 3L, nchar(turkce) - 2L)
  )
  expect_identical(env$.pk_prov_gap_words(ascii, 3L, nchar(ascii) - 2L), 4L)

  # Salt noktalama sozcuk SAYILMAZ.
  expect_identical(env$.pk_prov_gap_words(", - : ", 1L, 6L), 0L)
})

test_that("dogal Turkce mesafedeki gecerli alinti HALA baglanir", {
  env <- .prov_tarama_env()
  olgular <- list(.prov_tarama_olgu("f", 46978))

  # Uretimde olculen en uzun gecerli aralik (alti sozcuk) bagli KALMALIDIR.
  sonuc <- env$pk_numeric_provenance_validate(
    "46.978 ile toplam aktivitelerin buyuk bolumunu olusturuyor [fact:f]",
    olgular
  )

  expect_identical(sonuc$checked, 1L)
  expect_length(sonuc$mismatches %||% list(), 0L)
})

# ---------------------------------------------------------------------------
# 7) UZLASTIRMA anlamsal uyumu GOZETIR; gercek hata yine yakalanir.
# ---------------------------------------------------------------------------

test_that("esit degerli olgular BIRIM uyumuyla ayristirilir", {
  env <- .prov_tarama_env()
  olgular <- list(
    .prov_tarama_olgu("f_tl", 100, unit = "TL", aggregation = "sum"),
    .prov_tarama_olgu("f_saat", 100, unit = "saat", aggregation = "sum")
  )

  # Iki olgu AYNI degeri tasir; yalnizca birim ayirt eder ve isaretler TERS
  # siradadir. Yalnizca degere bakan uzlastirma keyfi bir esleme secip
  # `unit_mismatch` ureterek GECERLI yaniti dusuruyordu.
  sonuc <- env$pk_numeric_provenance_validate(
    "Sure 100 saat, butce 100 TL [fact:f_tl][fact:f_saat].", olgular
  )

  expect_identical(sonuc$checked, 2L)
  expect_length(sonuc$mismatches %||% list(), 0L)
})

test_that("toplulastirma baglami METIN sirasinda cozulur", {
  env <- .prov_tarama_env()
  olgular <- list(
    .prov_tarama_olgu("sum50", 50, aggregation = "sum"),
    .prov_tarama_olgu("mean100", 100, aggregation = "mean")
  )

  # Uzlastirma jeton sirasini TERSINE cevirir. Baglam "onceki ISARET" uzerinden
  # kurulunca ikinci jeton BOS baglam aliyor ve `100` sayisinin TOPLAM diye
  # sunuldugu hic fark edilmiyordu.
  sonuc <- env$pk_numeric_provenance_validate(
    "Toplam 100, ortalama 50 [fact:sum50][fact:mean100].", olgular
  )

  expect_true("aggregation_mismatch" %in% .prov_tarama_nedenler(sonuc))
})

# ---------------------------------------------------------------------------
# 8) SAYIM OLGUSU KANITI: muafiyet yalnizca GERCEK sayimlara acilir.
# ---------------------------------------------------------------------------

test_that("sayim kaniti toplulastirmadan VEYA sutun adindan gelir", {
  env <- .prov_tarama_env()

  # SAYIM: uretimdeki `sum`-over-count-column ornegi ve yaygin Turkce
  # CamelCase adlandirmalar. Bunlar muaf KALMALIDIR, aksi hâlde dogru bir
  # sayimi "adet" diye sunmak `unit_mismatch` uretirdi.
  for (ad in c("activity_total_count", "ToplamSayi", "AktiviteAdedi",
               "KayitSayisi")) {
    expect_true(
      env$.pk_prov_fact_is_count(list(column = ad, aggregation = "sum")),
      info = ad
    )
  }
  for (agg in c("count", "distinct_count", "row_count", "category_count")) {
    expect_true(
      env$.pk_prov_fact_is_count(list(column = "X", aggregation = agg)),
      info = agg
    )
  }

  # SAYIM DEGIL: birimsiz bir oran/tutar sayim sayilmaz.
  for (durum in list(
    list(column = "TamamlanmaOrani", aggregation = "mean"),
    list(column = "SentetikSutun", aggregation = "sum"),
    list(column = "Butce", aggregation = "weighted_mean")
  )) {
    expect_false(env$.pk_prov_fact_is_count(durum), info = durum$column)
  }

  # Olgu OLMAYAN girdi guvenle FALSE doner.
  expect_false(env$.pk_prov_fact_is_count(NULL))
  expect_false(env$.pk_prov_fact_is_count("metin"))
})

test_that("yetenek adı sayım sütununun kanıtını gizlemez", {
  env <- .prov_tarama_env()
  for (capability in c("activity.total", "", "activity.count")) {
    olgu <- .prov_tarama_olgu("a", 50367, aggregation = "sum",
                             column = "ActivityTotalCount")
    olgu$measure_capability <- capability
    sonuc <- env$pk_numeric_provenance_validate("50.367 adet [fact:a]", list(olgu))
    expect_identical(sonuc$checked, 1L)
    expect_length(sonuc$mismatches, 0L)
  }
  olgu$column <- "ActivityTotal"
  expect_true(env$.pk_prov_fact_is_count(olgu))
  olgu$measure_capability <- "activity.total"
  expect_false(env$.pk_prov_fact_is_count(olgu))
  sonuc <- env$pk_numeric_provenance_validate("50.367 adet [fact:a]", list(olgu))
  expect_true("unit_mismatch" %in% .prov_tarama_nedenler(sonuc))
})
