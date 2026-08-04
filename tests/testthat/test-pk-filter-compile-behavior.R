# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-filter-compile-behavior.R
# Açıklama: D1 / D2 / D3 — sütun içinde VEYA, sütunlar arasında VE, tamamlayıcı
#           aralık sınırlarının VE kalması, çok değerli filtreler ve Türkçe
#           katlamalı karşılaştırma. Tümü çevrimdışı ve deterministiktir:
#           gerçek DB, LLM, tarayıcı, SSO, ağ veya gerçek sır KULLANILMAZ.
#           Fixture'lar sentetiktir; gerçek proje/program adı geçmez.
# ==============================================================================

.pk_compile_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
  source(file.path(repo_root, "R", "helpers_pk_text_turkish.R"),
         encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_pk_filter_compile.R"),
         encoding = "UTF-8", local = env)
  env
}

# Sentetik veri: gerçek hiçbir proje/program adı içermez.
.pk_compile_data <- function() {
  data.frame(
    ProjeAdi = c(
      "SENTETIK RADAR MODERNIZASYON",
      "SENTETIK ELEKTRONIK HARP MODERNIZASYON",
      "SENTETIK LOJISTIK DESTEK",
      "İSTANBUL SENTETİK KALIP",
      "SENTETIK KALIP HATTI"
    ),
    Durum = c("Aktif", "Aktif", "Pasif", "Aktif", "Pasif"),
    Butce = c(100, 250, 50, 400, 700),
    Baslangic = as.Date(c("2024-03-01", "2024-07-15", "2023-05-10",
                          "2025-01-20", "2024-12-31")),
    stringsAsFactors = FALSE
  )
}

test_that("D1: AYNI sutundaki iki filtre VEYA'lanir, kesistirilmez", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  filtreler <- list(
    list(column = "ProjeAdi", value = "RADAR", operation = "contains"),
    list(column = "ProjeAdi", value = "ELEKTRONIK HARP", operation = "contains")
  )

  derleme <- env$pk_filter_compile(veri, filtreler)
  sonuc <- veri[derleme$mask, , drop = FALSE]

  # v1'de bu tam olarak 0 satir donduruyordu (bir proje adi HER IKI ifadeyi
  # birden icermek zorundaydi). Dogru anlam BIRLESIM'dir.
  expect_equal(nrow(sonuc), 2L)
  expect_setequal(
    sonuc$ProjeAdi,
    c("SENTETIK RADAR MODERNIZASYON", "SENTETIK ELEKTRONIK HARP MODERNIZASYON")
  )
})

test_that("D1: FARKLI sutunlar arasinda VE korunur", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  filtreler <- list(
    list(column = "ProjeAdi", value = "MODERNIZASYON", operation = "contains"),
    list(column = "Durum", value = "Aktif", operation = "exact_match")
  )

  derleme <- env$pk_filter_compile(veri, filtreler)
  sonuc <- veri[derleme$mask, , drop = FALSE]

  expect_equal(nrow(sonuc), 2L)
  expect_true(all(sonuc$Durum == "Aktif"))
})

test_that("D1: tamamlayici aralik sinirlari ayni sutunda VE kalir", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  filtreler <- list(
    list(column = "Baslangic", value = "2024-01-01", operation = "greater_or_equal"),
    list(column = "Baslangic", value = "2024-12-31", operation = "less_or_equal")
  )

  derleme <- env$pk_filter_compile(veri, filtreler)
  sonuc <- veri[derleme$mask, , drop = FALSE]

  # VEYA'lansaydi neredeyse evrensel bir predikat olur ve 5 satir donerdi.
  expect_equal(nrow(sonuc), 3L)
  expect_true(all(sonuc$Baslangic >= as.Date("2024-01-01")))
  expect_true(all(sonuc$Baslangic <= as.Date("2024-12-31")))

  # Sayisal sinirlar icin de ayni sozlesme gecerlidir.
  sayisal <- env$pk_filter_compile(veri, list(
    list(column = "Butce", value = "100", operation = "greater_or_equal"),
    list(column = "Butce", value = "400", operation = "less_or_equal")
  ))
  expect_equal(sum(sayisal$mask), 3L)
})

test_that("D2: cok degerli filtreler kirpilmadan uygulanir", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  # Karakter vektoru
  vektor <- env$pk_filter_compile(veri, list(
    list(column = "Durum", value = c("Aktif", "Pasif"), operation = "exact_match")
  ))
  expect_equal(sum(vektor$mask), 5L)

  # Liste (LLM'in yaygin JSON dizisi bicimi)
  liste <- env$pk_filter_compile(veri, list(
    list(column = "ProjeAdi",
         value = list("SENTETIK LOJISTIK DESTEK", "SENTETIK KALIP HATTI"),
         operation = "exact_match")
  ))
  # v1'de as.character(val)[1] nedeniyle yalnizca ILK deger uygulanirdi.
  expect_equal(sum(liste$mask), 2L)

  yaprak <- env$pk_filter_normalize_leaf(
    list(column = "A", value = list("x", "y", "z"), operation = "in")
  )
  expect_identical(yaprak$values, c("x", "y", "z"))
})

test_that("D3: karsilastirma Turkce katlamayla yapilir, ignore.case ile degil", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  # grepl("^istanbul...", "İSTANBUL...", ignore.case = TRUE) FALSE dondurur;
  # Turkce katlama ile TRUE olmalidir.
  turkce <- env$pk_filter_compile(veri, list(
    list(column = "ProjeAdi", value = "istanbul sentetik kalıp",
         operation = "exact_match")
  ))
  expect_equal(sum(turkce$mask), 1L)

  # "KALIP" Turkce kurallarla "kalıp" olur; ASCII "kalip" ile ESLESMEZ.
  kalip <- env$pk_filter_compile(veri, list(
    list(column = "ProjeAdi", value = "kalıp", operation = "contains")
  ))
  expect_equal(sum(kalip$mask), 2L)
})

test_that("dislama ve gecersiz yapraklar dogru ele alinir", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  dislama <- env$pk_filter_compile(veri, list(
    list(column = "Durum", value = "Pasif", operation = "not_equals")
  ))
  expect_equal(sum(dislama$mask), 3L)

  gecersiz <- env$pk_filter_compile(veri, list(
    list(column = "OlmayanSutun", value = "x", operation = "exact_match"),
    list(column = "", value = "y", operation = "exact_match"),
    list(column = "Butce", value = "sayi-degil", operation = "greater_than")
  ))
  # Hicbiri uygulanmadi -> maske degismedi, hepsi DUSURULDU olarak raporlandi.
  expect_equal(sum(gecersiz$mask), 5L)
  expect_equal(length(gecersiz$dropped), 3L)
})

test_that("etkisiz (no-op) filtre raporlanir", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  # Bes satirin dordunu koruyan (0.8) filtre 0.5 esiginin uzerindedir.
  dort_bes <- list(list(column = "ProjeAdi", value = "SENTETIK LOJISTIK DESTEK",
                        operation = "not_equals"))

  derleme <- env$pk_filter_compile(veri, dort_bes, noop_ratio = 0.5)
  expect_true("ProjeAdi" %in% derleme$noop_columns)

  # Ayni filtre 0.95 esiginde etkisiz SAYILMAZ.
  sika <- env$pk_filter_compile(veri, dort_bes, noop_ratio = 0.95)
  expect_length(sika$noop_columns, 0L)
})

test_that("sifir eslesen sutun grubu isaretlenir ve koken kaydi uretilir", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  derleme <- env$pk_filter_compile(veri, list(
    list(column = "ProjeAdi", value = "HIC OLMAYAN DEGER", operation = "exact_match")
  ))

  expect_equal(length(derleme$groups), 1L)
  expect_true(isTRUE(derleme$groups[[1]]$zero_match))
  expect_equal(derleme$groups[[1]]$rows_before, 5L)
  expect_equal(derleme$groups[[1]]$rows_after, 0L)
})

test_that("bos filtre listesi ve bos veri guvenli davranir", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  bos <- env$pk_filter_compile(veri, list())
  expect_true(all(bos$mask))

  bos_veri <- env$pk_filter_compile(veri[0, , drop = FALSE], list(
    list(column = "Durum", value = "Aktif", operation = "exact_match")
  ))
  expect_length(bos_veri$mask, 0L)
})

test_that("Turkce katlama otoritesi yoksa derleyici KAPALI BASARISIZ olur", {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = baseenv())
  env$`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
  env$exists <- function(...) FALSE
  source(file.path(repo_root, "R", "helpers_pk_filter_compile.R"),
         encoding = "UTF-8", local = env)

  # pk_tr_fold yoksa SESSIZCE tolower()'a DUSULMEZ; hata yukselir (D3).
  expect_error(
    env$.pk_filter_fold("ABC"),
    "pk_tr_fold",
    fixed = TRUE
  )
})
