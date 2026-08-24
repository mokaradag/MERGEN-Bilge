# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-numeric-provenance-false-positive-behavior.R
# Açıklama: PR #705 üretim gözleminde ortaya çıkan SAYISAL KÖKEN (numeric
#           provenance) YANLIŞ POZİTİFLERİNİN davranışsal regresyon kapsamı.
#
#           ÜRETİM BELİRTİSİ: cevaplar DOĞRUYKEN
#           `iddia=11 | uyusmazlik=6 | oran=0.545 |
#            nedenler=missing_fact_marker,no_number,unit_mismatch`
#           raporlanıyordu.
#
#           KÖK NEDENLER (üçü de AYRI kusurdur):
#             1) Markdown vurgusu / noktalama / Türkçe kesme eki, sayı ile
#                `[fact:...]` işareti ARASINA girdiğinde alıntılı tarayıcı
#                eşleşmiyor, alıntısız tarayıcı ise AYNI sayıyı köksüz sayıyordu.
#                Tek sayı hem payda hem paya İKİ KEZ giriyordu.
#             2) Sayıyı izleyen HER sözcük "iddia edilen birim" sanılıyordu;
#                `15.574 aktivite` gibi doğru bir cümle `unit_mismatch` üretiyordu.
#             3) Sayım olguları (`kind = "context"` / `aggregation = "count"`)
#                birim BEYAN ETMEZ ama modelin doğal Türkçesi "adet" yazar; bu
#                da birimsiz olguya birim uydurmak sayılıyordu.
#
#           KAPSAM SÖZLEŞMESİ: bu dosya, tanılamayı BASTIRARAK değil, GERÇEK
#           hataların hâlâ yakalandığını KANITLAYARAK yanlış pozitifleri kapatır.
#           Eşik düşürme, şiddet azaltma, blok/uyarı -> log çevirme, şablon
#           muafiyeti veya köken doğrulamasını devre dışı bırakma YOKTUR.
#
#           Testler ÇEVRİMDIŞI ve DETERMİNİSTİKtir: gerçek LLM/DB/ağ yoktur ve
#           üretim SQL'i, proje adı, kimlik bilgisi veya VM veri kümesi
#           KULLANILMAZ; tüm olgular SENTETİKtir.
# ==============================================================================

# DOSYA KAPSAMINDA DA TANIMLIDIR. `.prov_fp_fact()` dosya kapsamında tanımlıdır
# ve `%||%` ifadesini TEST DOSYASI ortamında değerlendirir; yalnızca `env`
# içinde tanımlamak, operatörün paylaşılan testthat ortamına BAŞKA bir dosyanın
# yan etkisiyle gelmesine bağlı kalırdı. Bu dosya TEK BAŞINA çalıştırıldığında
# (triyaj sırasında `testthat::test_file()`) her test köken davranışını
# sınamak yerine "could not find function" ile düşerdi.
if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
}

.prov_fp_env <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  env$`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
  # Bagimlilik sirasi calisma zamani manifestiyle AYNI tutulur: koken
  # dogrulayicisi kesinlik yardimcilariyla ayni sinirda calisir. Izole ortam
  # onu yuklemezse, ileride eklenen bir kesinlik cagrisi bu dosyada
  # "cozulmemis sembol" olarak patlar ve gercek regresyon davranisi degil
  # yukleme sirasi test edilmis olur.
  source(file.path(kok, "R", "helpers_pk_precision.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_pk_numeric_provenance.R"), encoding = "UTF-8", local = env)
  env
}

# Sentetik olgu kurucusu. Üretim metadatası veya gerçek sütun adı kullanılmaz.
.prov_fp_fact <- function(id, value, unit = NULL, aggregation = NULL,
                          kind = NULL, column = NULL) {
  olgu <- list(fact_id = id, value = value, column = column %||% "SentetikSutun")
  if (!is.null(unit)) olgu$unit <- unit
  if (!is.null(aggregation)) olgu$aggregation <- aggregation
  if (!is.null(kind)) olgu$kind <- kind
  olgu
}

.prov_fp_reasons <- function(sonuc) {
  sort(unique(vapply(sonuc$mismatches %||% list(),
                     function(m) as.character(m$reason %||% "")[1], character(1))))
}

# ---------------------------------------------------------------------------
# 1) Türkçe binlik ayıracı: "15.574 adet" YANLIŞ `no_number` üretmez.
# ---------------------------------------------------------------------------

test_that("Türkçe binlik ayıraçlı sayı doğru ayrıştırılır ve uyuşmazlık üretmez", {
  env <- .prov_fp_env()
  olgular <- list(.prov_fp_fact("gecikme_sayisi", 15574, unit = "adet",
                                aggregation = "count", kind = "context"))

  sonuc <- env$pk_numeric_provenance_validate(
    "Geciken aktivite sayisi 15.574 adet [fact:gecikme_sayisi] olarak bulundu.",
    olgular
  )

  expect_equal(sonuc$checked, 1L)
  expect_length(sonuc$mismatches, 0L)
  expect_equal(sonuc$rate, 0)
})

test_that("ondalık virgüllü Türkçe sayı da doğru eşleşir", {
  env <- .prov_fp_env()
  olgular <- list(.prov_fp_fact("oran", 61.3, unit = "%"))

  sonuc <- env$pk_numeric_provenance_validate(
    "Tamamlanma orani %61,3 [fact:oran] seviyesindedir.", olgular
  )

  expect_length(sonuc$mismatches, 0L)
})

# ---------------------------------------------------------------------------
# 2) Birim uyumu: doğru birim uyuşmazlık üretmez.
# ---------------------------------------------------------------------------

test_that("olgunun beyan ettiği birim doğru yazıldığında uyuşmazlık yoktur", {
  env <- .prov_fp_env()
  olgular <- list(.prov_fp_fact("kalan_saat", 3783, unit = "saat", aggregation = "sum"))

  sonuc <- env$pk_numeric_provenance_validate(
    "Toplam kalan is 3.783 saat [fact:kalan_saat] olarak hesaplandi.", olgular
  )

  expect_length(sonuc$mismatches, 0L)
})

# ---------------------------------------------------------------------------
# 3) GERÇEK yanlış birim hâlâ `unit_mismatch` üretir.
# ---------------------------------------------------------------------------

test_that("yanlış birim hâlâ unit_mismatch olarak yakalanır", {
  env <- .prov_fp_env()
  olgular <- list(.prov_fp_fact("kalan_saat", 3783, unit = "saat", aggregation = "sum"))

  sonuc <- env$pk_numeric_provenance_validate(
    "Toplam kalan is 3.783 gun [fact:kalan_saat] olarak hesaplandi.", olgular
  )

  expect_true("unit_mismatch" %in% .prov_fp_reasons(sonuc))
})

test_that("yüzde olguyu mutlak sayı gibi sunmak yakalanır", {
  env <- .prov_fp_env()
  olgular <- list(.prov_fp_fact("oran", 61.3, unit = "%"))

  sonuc <- env$pk_numeric_provenance_validate(
    "Deger 61,3 [fact:oran] olarak olculdu.", olgular
  )

  expect_true("unit_missing" %in% .prov_fp_reasons(sonuc))
})

test_that("birimsiz ÖLÇÜYE ölçek taşıyan birim uydurmak yakalanır", {
  env <- .prov_fp_env()
  # Sayım DEĞİL: kind/aggregation beyan edilmemiş sıradan bir ölçü.
  olgular <- list(.prov_fp_fact("ham_deger", 120))

  sonuc <- env$pk_numeric_provenance_validate(
    "Sonuc 120 saat [fact:ham_deger] olarak bulundu.", olgular
  )

  expect_true("unit_mismatch" %in% .prov_fp_reasons(sonuc))
})

# ---------------------------------------------------------------------------
# 4) GERÇEK eksik işaret hâlâ `missing_fact_marker` üretir.
# ---------------------------------------------------------------------------

test_that("işaretsiz sayısal iddia hâlâ missing_fact_marker üretir", {
  env <- .prov_fp_env()
  olgular <- list(.prov_fp_fact("toplam", 27028, unit = "adet",
                                aggregation = "count", kind = "context"))

  sonuc <- env$pk_numeric_provenance_validate(
    "Toplam 27.028 adet [fact:toplam] kayit vardir; ayrica 1.999 adet ek kayit bulundu.",
    olgular
  )

  expect_true("missing_fact_marker" %in% .prov_fp_reasons(sonuc))
  # Alintili olan sayi uyusmazlik URETMEZ.
  expect_length(Filter(function(m) identical(m$reason, "missing_fact_marker"),
                       sonuc$mismatches), 1L)
})

# ---------------------------------------------------------------------------
# 5) GERÇEK yanlış değer hâlâ yakalanır (halüsinasyon tespiti korunur).
# ---------------------------------------------------------------------------

test_that("olguyla uyuşmayan sayı value_mismatch üretir", {
  env <- .prov_fp_env()
  olgular <- list(.prov_fp_fact("toplam", 27028, unit = "adet",
                                aggregation = "count", kind = "context"))

  sonuc <- env$pk_numeric_provenance_validate(
    "Toplam 27.029 adet [fact:toplam] kayit bulundu.", olgular
  )

  nedenler <- .prov_fp_reasons(sonuc)
  expect_true(length(nedenler) > 0L)
  expect_false(identical(nedenler, "missing_fact_marker"))
})

test_that("var olmayan olgu kimliği unknown_fact üretir", {
  env <- .prov_fp_env()
  olgular <- list(.prov_fp_fact("toplam", 10, unit = "adet",
                                aggregation = "count", kind = "context"))

  sonuc <- env$pk_numeric_provenance_validate(
    "Deger 10 adet [fact:olmayan_olgu] seklindedir.", olgular
  )

  expect_true("unknown_fact" %in% .prov_fp_reasons(sonuc))
})

# ---------------------------------------------------------------------------
# 6) Birden fazla sayı DOĞRU olgulara eşlenir.
# ---------------------------------------------------------------------------

test_that("çok sayıda alıntı doğru olgulara eşlenir ve karışmaz", {
  env <- .prov_fp_env()
  olgular <- list(
    .prov_fp_fact("a", 15574, unit = "adet", aggregation = "count", kind = "context"),
    .prov_fp_fact("b", 27028, unit = "adet", aggregation = "count", kind = "context"),
    .prov_fp_fact("c", 3783, unit = "saat", aggregation = "sum"),
    .prov_fp_fact("d", 50045, unit = "adet", aggregation = "count", kind = "context"),
    .prov_fp_fact("e", 46385, unit = "adet", aggregation = "count", kind = "context")
  )
  metin <- paste0(
    "Geciken 15.574 adet [fact:a], toplam 27.028 adet [fact:b], ",
    "kalan 3.783 saat [fact:c], kayit 50.045 adet [fact:d] ve ",
    "tamamlanan 46.385 adet [fact:e] olarak olculdu."
  )

  sonuc <- env$pk_numeric_provenance_validate(metin, olgular)

  expect_equal(sonuc$checked, 5L)
  expect_length(sonuc$mismatches, 0L)
  expect_identical(vapply(sonuc$claims, function(x) x$fact_id, character(1)),
                   c("a", "b", "c", "d", "e"))
})

test_that("sayılar çapraz eşlendiğinde uyuşmazlık raporlanır", {
  env <- .prov_fp_env()
  olgular <- list(
    .prov_fp_fact("a", 15574, unit = "adet", aggregation = "count", kind = "context"),
    .prov_fp_fact("b", 27028, unit = "adet", aggregation = "count", kind = "context")
  )

  # Degerler BILEREK takas edilmistir.
  sonuc <- env$pk_numeric_provenance_validate(
    "Geciken 27.028 adet [fact:a] ve toplam 15.574 adet [fact:b] bulundu.", olgular
  )

  expect_equal(length(sonuc$mismatches), 2L)
})

# ---------------------------------------------------------------------------
# 7) Sayı ayıraçları normalize edilir (nokta/virgül/boşluk/NBSP).
# ---------------------------------------------------------------------------

test_that("farklı binlik ayıraç yazımları aynı değere çözülür", {
  env <- .prov_fp_env()
  olgular <- list(.prov_fp_fact("v", 50045, unit = "adet",
                                aggregation = "count", kind = "context"))

  # Turkce yazim binlik ayraci NOKTAdir; bosluk/NBSP desteklenmez (iki ayri
  # sayiyla karisirdi) ve BILINCLI olarak kapsam disidir.
  yazimlar <- c("50.045", "50045")
  for (yazim in yazimlar) {
    sonuc <- env$pk_numeric_provenance_validate(
      sprintf("Toplam %s adet [fact:v] kayit vardir.", yazim), olgular
    )
    expect_length(sonuc$mismatches, 0L)
    expect_equal(sonuc$checked, 1L, info = yazim)
  }
})

# ---------------------------------------------------------------------------
# 8) Tam sayılar ile ondalıklar ayırt edilir.
# ---------------------------------------------------------------------------

test_that("tam sayı ve ondalık gösterim birbirine karıştırılmaz", {
  env <- .prov_fp_env()

  tam <- env$pk_numeric_provenance_validate(
    "Deger 1.250 adet [fact:t] olarak olculdu.",
    list(.prov_fp_fact("t", 1250, unit = "adet", aggregation = "count", kind = "context"))
  )
  expect_length(tam$mismatches, 0L)

  ondalik <- env$pk_numeric_provenance_validate(
    "Deger 1,25 saat [fact:o] olarak olculdu.",
    list(.prov_fp_fact("o", 1.25, unit = "saat", aggregation = "mean"))
  )
  expect_length(ondalik$mismatches, 0L)

  # BELIRSIZ OLMAYAN yazim: 12.500 (on iki bin bes yuz) 1,25 DEGILDIR.
  yanlis <- env$pk_numeric_provenance_validate(
    "Deger 12.500 saat [fact:o] olarak olculdu.",
    list(.prov_fp_fact("o", 1.25, unit = "saat", aggregation = "mean"))
  )
  expect_true(length(yanlis$mismatches) > 0L)
})

# Tek noktali gruplama BELIRSIZDIR ("1.250" hem 1250 hem 1,250 okunabilir);
# dogrulayici HER IKI okumayi da kabul eder. Bu BILINCLI bir sozlesmedir:
# tek bir okumayi dayatmak, sade bicimli mesru alintilari reddederdi.
test_that("tek noktalı gruplama iki okumayı da kabul eder (belirsizlik sözleşmesi)", {
  env <- .prov_fp_env()

  binli <- env$pk_numeric_provenance_validate(
    "Deger 1.250 saat [fact:o] olarak olculdu.",
    list(.prov_fp_fact("o", 1250, unit = "saat", aggregation = "sum"))
  )
  expect_length(binli$mismatches, 0L)

  ondalikli <- env$pk_numeric_provenance_validate(
    "Deger 1.250 saat [fact:o] olarak olculdu.",
    list(.prov_fp_fact("o", 1.25, unit = "saat", aggregation = "mean"))
  )
  expect_length(ondalikli$mismatches, 0L)
})

# ---------------------------------------------------------------------------
# 9) Birimler (adet/saat/gün/iş günü/%/TL) birbirinden ayırt edilebilir.
# ---------------------------------------------------------------------------

test_that("desteklenen birimler birbirinden ayırt edilir", {
  env <- .prov_fp_env()
  birimler <- c("adet", "saat", "gun", "%", "TL")

  for (dogru in birimler) {
    olgular <- list(.prov_fp_fact("x", 12, unit = dogru))
    metin <- if (identical(dogru, "%")) {
      "Deger %12 [fact:x] olarak olculdu."
    } else {
      sprintf("Deger 12 %s [fact:x] olarak olculdu.", dogru)
    }
    sonuc <- env$pk_numeric_provenance_validate(metin, olgular)
    expect_length(sonuc$mismatches, 0L)
  }

  # Capraz birim: her yanlis eslesme yakalanmalidir.
  for (dogru in c("saat", "gun", "TL")) {
    yanlis <- setdiff(c("saat", "gun", "TL"), dogru)[1]
    sonuc <- env$pk_numeric_provenance_validate(
      sprintf("Deger 12 %s [fact:x] olarak olculdu.", yanlis),
      list(.prov_fp_fact("x", 12, unit = dogru))
    )
    expect_true("unit_mismatch" %in% .prov_fp_reasons(sonuc),
                info = sprintf("%s yerine %s", dogru, yanlis))
  }
})

# ---------------------------------------------------------------------------
# 10) DOĞRU cevaplar büyük yanlış uyuşmazlık ORANI üretmez (üretim belirtisi).
# ---------------------------------------------------------------------------

test_that("tamamen doğru üretim benzeri yanıt sıfır uyuşmazlık oranı verir", {
  env <- .prov_fp_env()
  olgular <- list(
    .prov_fp_fact("f1", 15574, unit = "adet", aggregation = "count", kind = "context"),
    .prov_fp_fact("f2", 27028, unit = "adet", aggregation = "count", kind = "context"),
    .prov_fp_fact("f3", 3783, unit = "adet", aggregation = "count", kind = "context"),
    .prov_fp_fact("f4", 50045, unit = "adet", aggregation = "count", kind = "context"),
    .prov_fp_fact("f5", 46385, unit = "adet", aggregation = "count", kind = "context")
  )

  # Uretimdeki gibi MARKDOWN VURGUSU, noktalama ve Turkce kesme eki icerir.
  metin <- paste0(
    "## Ozet\n\n",
    "- **15.574 adet** [fact:f1] geciken kayit bulundu.\n",
    "- Toplam *27.028 adet* [fact:f2] kayit incelendi.\n",
    "- `3.783 adet` [fact:f3] kayit onceliklidir.\n",
    "- Genel toplam 50.045 adet [fact:f4]'tir.\n",
    "- Tamamlanan 46.385 adet [fact:f5].\n"
  )

  sonuc <- env$pk_numeric_provenance_validate(metin, olgular)

  # Regresyon: her sayi HEM `no_number`/`missing_fact_marker` HEM de birim
  # uyusmazligi uretip oran 0.545'e ciktigi durum.
  expect_equal(sonuc$checked, 5L)
  expect_length(sonuc$mismatches, 0L)
  expect_equal(sonuc$rate, 0)
})

test_that("vurgu ve noktalama aynı sayıyı İKİ KEZ saydırmaz", {
  env <- .prov_fp_env()
  olgular <- list(.prov_fp_fact("f", 15574, unit = "adet",
                                aggregation = "count", kind = "context"))

  sonuc <- env$pk_numeric_provenance_validate(
    "Sonuc **15.574 adet** [fact:f]'tir.", olgular
  )

  # `checked` = alintili iddialar + koksuz iddialar. Ayni sayi tek kez sayilir.
  expect_equal(sonuc$checked, 1L)
  expect_length(sonuc$uncited, 0L)
})

# ---------------------------------------------------------------------------
# 11) Halüsinasyon tespiti korunur: uydurulmuş sayı hâlâ yakalanır.
# ---------------------------------------------------------------------------

test_that("uydurulmuş ek sayılar hâlâ yakalanır (halüsinasyon koruması)", {
  env <- .prov_fp_env()
  olgular <- list(.prov_fp_fact("f", 100, unit = "adet",
                                aggregation = "count", kind = "context"))

  sonuc <- env$pk_numeric_provenance_validate(
    paste0("Toplam **100 adet** [fact:f] kayit vardir. ",
           "Bunlarin 1.234 adedi kritik, 5.678 adedi ise beklemededir."),
    olgular
  )

  expect_true("missing_fact_marker" %in% .prov_fp_reasons(sonuc))
  expect_true(sonuc$rate > 0)
})

# ---------------------------------------------------------------------------
# 12) Toplulaştırma çelişkisi hâlâ yakalanır.
# ---------------------------------------------------------------------------

test_that("toplamı ortalama diye sunmak aggregation_mismatch üretir", {
  env <- .prov_fp_env()
  olgular <- list(.prov_fp_fact("f", 500, unit = "saat", aggregation = "sum"))

  sonuc <- env$pk_numeric_provenance_validate(
    "Ortalama 500 saat [fact:f] olarak hesaplandi.", olgular
  )

  expect_true("aggregation_mismatch" %in% .prov_fp_reasons(sonuc))
})

# ---------------------------------------------------------------------------
# 13) Kip davranışı: tanılama BASTIRILMAZ, kapalı başarısız korunur.
# ---------------------------------------------------------------------------

test_that("block kipi gerçek uyuşmazlıkta hâlâ engeller", {
  env <- .prov_fp_env()
  olgular <- list(.prov_fp_fact("f", 100, unit = "adet",
                                aggregation = "count", kind = "context"))

  sonuc <- env$pk_numeric_provenance_apply(
    "Toplam 101 adet [fact:f] kayit vardir.", olgular,
    mode = "block", fallback_text = "Deterministik yedek metin."
  )

  expect_true(isTRUE(sonuc$blocked))
  expect_true(length(sonuc$mismatches) > 0L)
})

test_that("block kipi DOĞRU yanıtı engellemez", {
  env <- .prov_fp_env()
  olgular <- list(.prov_fp_fact("f", 100, unit = "adet",
                                aggregation = "count", kind = "context"))

  sonuc <- env$pk_numeric_provenance_apply(
    "Toplam **100 adet** [fact:f] kayit vardir.", olgular,
    mode = "block", fallback_text = "Deterministik yedek metin."
  )

  expect_false(isTRUE(sonuc$blocked))
  expect_length(sonuc$mismatches, 0L)
})

# ---------------------------------------------------------------------------
# 14) Deterministik bölüm muafiyeti YOKTUR.
# ---------------------------------------------------------------------------

test_that("hiçbir bölüm/şablon köken doğrulamasından muaf tutulmaz", {
  env <- .prov_fp_env()
  olgular <- list(.prov_fp_fact("f", 100, unit = "adet",
                                aggregation = "count", kind = "context"))

  # Baslik/tablo/kod blogu gibi "deterministik gorunumlu" bolumler de taranir.
  metin <- paste0(
    "## Deterministik Ozet\n\n",
    "| Olcut | Deger |\n|---|---|\n| Kayit | 100 adet [fact:f] |\n",
    "| Uydurma | 7.777 adet |\n"
  )

  sonuc <- env$pk_numeric_provenance_validate(metin, olgular)

  expect_true("missing_fact_marker" %in% .prov_fp_reasons(sonuc))
})

test_that("köken doğrulaması kaynak dosyada muafiyet listesi TAŞIMAZ", {
  kok <- resolve_repo_root_for_tests()
  yol <- file.path(kok, "R", "helpers_pk_numeric_provenance.R")
  ham <- readBin(yol, "raw", file.size(yol))
  metin <- iconv(rawToChar(ham), "UTF-8", "UTF-8", sub = "byte")

  # Bolum/sablon bazli atlama, esik dusurme veya sessizce gecme YOKTUR.
  for (kalip in c("exempt", "whitelist", "allowlist", "skip_section", "bypass")) {
    expect_false(grepl(kalip, metin, fixed = TRUE, useBytes = TRUE),
                 info = kalip)
  }
})
