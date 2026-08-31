# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-analysis-packet-behavior.R
# Açıklama: Faz 2 — analiz paketi (§5.7). D17 (atılan istatistikler / yalnızca
#           ilk beş kategorik sütun), D18 (konumsal yanlı head(500) örneği),
#           D19 (bilimsel gösterim), seyrek/sonlu-olmayan ölçü sözleşmesi,
#           ağırlıklı ortalama geçersiz-ağırlık sözleşmesi, `latest` eşitlik
#           kuralı, olgu kimliği/anlamsal bağlamı, bütçe muhasebecisi ve
#           D7/D8 (FİLTRELEME UYARISI her düşürme yolunda hayatta kalır).
#
#           Tümü ÇEVRİMDIŞI ve DETERMİNİSTİKTİR: gerçek DB, LLM, tarayıcı, SSO,
#           ağ veya gerçek sır KULLANILMAZ. Fixture'lar sentetiktir; gerçek
#           proje/program adı geçmez.
# ==============================================================================

.pk_packet_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x

  for (dosya in c("helpers_pk_config.R", "helpers_pk_text_turkish.R",
                  "helpers_pk_prompt_budget.R", "helpers_pk_precision.R", "helpers_pk_packet_stats.R", "helpers_pk_packet_context_facts.R",
                  "helpers_pk_packet_keys.R", "helpers_pk_analysis_packet.R", "helpers_pk_packet_render.R")) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = env)
  }
  env
}

# Yalnızca kod taranır; açıklama satırları taranmaz.
.pk_packet_code_only <- function(rel_path) {
  full <- file.path(resolve_repo_root_for_tests(), rel_path)
  size <- suppressWarnings(file.info(full)$size[1])
  if (is.na(size) || size <= 0) {
    # BOŞ DOSYA DA VACUOUS GEÇİRİR: bu dosyalardaki taramaların çoğu
    # `expect_false(grepl(...))` biçimindedir ve boş dize hepsini karşılar.
    stop(sprintf("Kaynak dosya BOŞ ya da okunamıyor: %s", full), call. = FALSE)
  }
  con <- file(full, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]])
  if (is.na(txt)) return("")
  satirlar <- strsplit(enc2utf8(txt), "\n", fixed = TRUE)[[1]]
  satirlar <- satirlar[!grepl("^\\s*#", satirlar, perl = TRUE, useBytes = TRUE)]
  paste(satirlar, collapse = "\n")
}

.pk_packet_query <- function(column_meta = list(), extra = list()) {
  meta <- c(list(column_meta = column_meta), extra)
  list(id = "q_sentetik", name = "Sentetik Sorgu", meta = meta)
}

.pk_packet_fact <- function(olgular, sutun, agg) {
  bulunan <- Filter(function(o) identical(o$column, sutun) &&
                      identical(o$aggregation, agg), olgular)
  if (!length(bulunan)) return(NULL)
  bulunan[[1]]
}

# --- D19: sayı biçimi ---------------------------------------------------------

test_that("D19: sayilar bilimsel gosterime DUSMEZ ve yerelden bagimsizdir", {
  env <- .pk_packet_env()

  expect_equal(env$pk_fmt_number(1234567890, 0L), "1.234.567.890")
  expect_false(grepl("e", env$pk_fmt_number(1234567890, 0L), fixed = TRUE))
  expect_equal(env$pk_fmt_number(18420.5, 1L, "saat"), "18.420,5 saat")
  expect_equal(env$pk_fmt_number(-125.5, 2L), "-125,50")
  expect_equal(env$pk_fmt_number(0.613, 3L), "0,613")
  expect_equal(env$pk_fmt_number(NA), "?")
  expect_equal(env$pk_fmt_number(Inf), "?")

  eski <- getOption("OutDec")
  on.exit(options(OutDec = eski), add = TRUE)
  options(OutDec = ",")
  expect_equal(env$pk_fmt_number(1234.5, 1L), "1.234,5")
})

test_that("D19: paket metni capture.output/print kullanmaz", {
  for (dosya in c("R/helpers_pk_packet_stats.R", "R/helpers_pk_packet_context_facts.R", "R/helpers_pk_analysis_packet.R",
                  "R/helpers_pk_packet_render.R")) {
    kod <- .pk_packet_code_only(dosya)
    expect_false(grepl("capture.output", kod, fixed = TRUE, useBytes = TRUE),
                 info = sprintf("%s capture.output kullanmamalidir.", dosya))
    # Test ADI `print` de iddia ediyordu ama yalnız `capture.output` denetleniyordu;
    # paket metnini `print()` ile üreten bir regresyon bu testi GEÇİYORDU.
    expect_false(grepl("\\bprint\\s*\\(", kod, perl = TRUE, useBytes = TRUE),
                 info = sprintf("%s print() ile metin uretmemelidir.", dosya))
  }
})

# --- Seyrek / sonlu olmayan olcu sozlesmesi -----------------------------------

test_that("Tamami eksik olcu OLGUSAL SIFIRA donusmez", {
  env <- .pk_packet_env()
  olgular <- env$pk_measure_facts(c(NA_real_, NA_real_, NaN), "Butce",
                                  list(label = "Bütçe"), additive = TRUE)

  expect_length(olgular, 1L)
  expect_identical(olgular[[1]]$status, "unavailable_no_finite_values")
  expect_null(olgular[[1]]$value)
  expect_true(is.na(olgular[[1]]$display))
})

test_that("Tek gozlem: temel olgular uretilir, yayilim olgulari insufficient_data", {
  env <- .pk_packet_env()
  olgular <- env$pk_measure_facts(c(NA, 42, NA), "Butce", list(decimals = 0L),
                                  additive = TRUE)

  toplam <- .pk_packet_fact(olgular, "Butce", "sum")
  expect_identical(toplam$status, "single_observation")
  expect_equal(toplam$value, 42)
  expect_identical(toplam$n_finite, 1L)
  expect_identical(toplam$n_excluded, 2L)

  for (agg in c("sd", "p05", "p25", "p75", "p95", "iqr_outliers")) {
    olgu <- .pk_packet_fact(olgular, "Butce", agg)
    expect_identical(olgu$status, "insufficient_data")
    expect_null(olgu$value)
  }
})

test_that("Hicbir olgu NA / NaN / Inf deger tasimaz", {
  env <- .pk_packet_env()
  olgular <- c(
    env$pk_measure_facts(c(1, 2, 3, Inf, NaN), "A", list(), additive = TRUE),
    env$pk_measure_facts(rep(NA_real_, 5), "B", list(), additive = TRUE),
    env$pk_measure_facts(c(7), "C", list(), additive = TRUE)
  )

  for (olgu in olgular) {
    if (is.null(olgu$value)) next
    expect_true(is.finite(olgu$value),
                info = sprintf("%s olgusu sonlu olmayan deger tasiyor.", olgu$fact_id))
  }
})

test_that("additive dogrulanmadan TOPLAM ve ORTALAMA uretilmez (Tier-0 geri dususu)", {
  env <- .pk_packet_env()

  tier0 <- env$pk_measure_facts(c(10, 20, 30), "Yuzde", list(), additive = FALSE)
  expect_identical(.pk_packet_fact(tier0, "Yuzde", "sum")$status, "insufficient_data")
  expect_null(.pk_packet_fact(tier0, "Yuzde", "sum")$value)
  expect_identical(.pk_packet_fact(tier0, "Yuzde", "mean")$status, "insufficient_data")
  # Dagilim istatistikleri DONEN SATIRLARI betimler; Tier-0'da da uretilir.
  expect_equal(.pk_packet_fact(tier0, "Yuzde", "median")$value, 20)

  toplanabilir <- env$pk_measure_facts(c(10, 20, 30), "Saat", list(), additive = TRUE)
  expect_equal(.pk_packet_fact(toplanabilir, "Saat", "sum")$value, 60)
  expect_equal(.pk_packet_fact(toplanabilir, "Saat", "mean")$value, 20)
})

# --- Agirlikli ortalama sozlesmesi --------------------------------------------

test_that("Agirlikli ortalama: eksik ve SIFIR agirlikli ciftler ifsa edilerek dislanir", {
  env <- .pk_packet_env()
  olgu <- env$pk_weighted_mean_fact(
    values  = c(60, 80, 100, NA),
    weights = c(1,  3,  0,   5),
    "Tamamlanma", list(unit = "%", decimals = 1L), weight_column = "Plan"
  )

  expect_identical(olgu$status, "ok")
  expect_equal(olgu$value, (60 * 1 + 80 * 3) / 4)
  expect_identical(olgu$n_finite, 2L)
  expect_identical(olgu$n_excluded, 2L)
  expect_true(grepl("Disarida birakilan satir: 2", olgu$note, fixed = TRUE))
})

test_that("Agirlikli ortalama: negatif/sonlu olmayan agirlik TUM kumeyi gecersiz kilar", {
  env <- .pk_packet_env()

  negatif <- env$pk_weighted_mean_fact(c(10, 20), c(-1, 5), "X", list())
  expect_identical(negatif$status, "invalid_weight_set")
  expect_null(negatif$value)

  sonsuz <- env$pk_weighted_mean_fact(c(10, 20), c(Inf, 5), "X", list())
  expect_identical(sonsuz$status, "invalid_weight_set")
  expect_null(sonsuz$value)
})

test_that("Agirlikli ortalama: pozitif cift kalmazsa NaN/0/agirliksiz ortalamaya DUSULMEZ", {
  env <- .pk_packet_env()
  olgu <- env$pk_weighted_mean_fact(c(10, 20, 30), c(0, 0, 0), "X", list())

  expect_identical(olgu$status, "weighted_mean_unavailable")
  expect_null(olgu$value)
  expect_true(is.na(olgu$display))
})

# --- aggregate = "latest" -----------------------------------------------------

test_that("latest: latest_by + benzersiz latest_tie_by ile deger secilir", {
  env <- .pk_packet_env()
  veri <- data.frame(
    Deger = c(10, 20, 30),
    Damga = as.Date(c("2024-01-01", "2024-06-01", "2024-03-01")),
    Anahtar = c("a", "b", "c"),
    stringsAsFactors = FALSE
  )

  olgu <- env$pk_latest_fact(veri, "Deger",
                             list(latest_by = "Damga", latest_tie_by = "Anahtar"))
  expect_identical(olgu$status, "ok")
  expect_equal(olgu$value, 20)
})

test_that("latest: en yeni damgada mukerrer tie -> ambiguous_latest, deger SECILMEZ", {
  env <- .pk_packet_env()
  veri <- data.frame(
    Deger = c(10, 20, 30),
    Damga = as.Date(c("2024-06-01", "2024-06-01", "2024-03-01")),
    Anahtar = c("a", "a", "c"),
    stringsAsFactors = FALSE
  )

  olgu <- env$pk_latest_fact(veri, "Deger",
                             list(latest_by = "Damga", latest_tie_by = "Anahtar"))
  expect_identical(olgu$status, "ambiguous_latest")
  expect_null(olgu$value)
})

test_that("latest: latest_tie_by beyani olmadan latest CALISTIRILMAZ", {
  env <- .pk_packet_env()
  veri <- data.frame(Deger = c(1, 2), Damga = as.Date(c("2024-01-01", "2024-02-01")))

  olgu <- env$pk_latest_fact(veri, "Deger", list(latest_by = "Damga"))
  expect_identical(olgu$status, "ambiguous_latest")
  expect_null(olgu$value)
})

# --- Olgu kimligi ve anlamsal baglam ------------------------------------------

test_that("Her olgu kararli ASCII kimlik ve anlamsal baglam tasir", {
  env <- .pk_packet_env()
  olgular <- env$pk_measure_facts(
    c(1, 2, 3), "KalanIscilik_sa",
    list(label = "Kalan İşçilik", unit = "saat", decimals = 1L,
         capability = "labor.remaining_hours"),
    scope = env$pk_scope_signature(100L, 40L), additive = TRUE
  )

  toplam <- .pk_packet_fact(olgular, "KalanIscilik_sa", "sum")
  # inceleme bulgusu: kimliğe, KIRPILMAMIŞ özgün kimlikten türetilen kararlı
  # bir sağlama eklenir. `A-B` ile `A B` gibi normalleştirmede aynı slug'a
  # düşen iki ölçü artık AYNI kimliği alamaz (sessiz üzerine yazma yoktu).
  expect_true(startsWith(toplam$fact_id, "labor_remaining_hours.sum.overall."))
  expect_true(grepl("^labor_remaining_hours\\.sum\\.overall\\.[0-9a-f]{6}$",
                    toplam$fact_id))
  expect_true(grepl("^[A-Za-z0-9_.]+$", toplam$fact_id))
  # Aynı kimlik, aynı girdiden HER ZAMAN aynı üretilir.
  expect_identical(toplam$fact_id,
                   env$pk_fact_id("labor.remaining_hours", "sum", character(0)))
  expect_identical(toplam$measure_capability, "labor.remaining_hours")
  expect_identical(toplam$unit, "saat")
  expect_identical(toplam$label, "Kalan İşçilik")
  expect_identical(toplam$scope, "yetki=100|filtre=40")
  expect_identical(toplam$display, "6,0 saat")
})

test_that("Turkce sutun adindan uretilen olgu kimligi de ASCII kalir", {
  env <- .pk_packet_env()
  olgular <- env$pk_measure_facts(c(5), "ÇalışmaSüresi", list(), additive = TRUE)
  expect_true(grepl("^[A-Za-z0-9_.]+$", olgular[[1]]$fact_id))
  expect_true(grepl("calismasuresi", olgular[[1]]$fact_id, fixed = TRUE))
})

# --- D17: TUM kategorik sutunlar, adet VE pay ---------------------------------

test_that("D17: alti kategorik sutunun HEPSI ozetlenir ve ilk-K adet+pay tasir", {
  env <- .pk_packet_env()
  veri <- data.frame(
    K1 = rep(c("a", "b"), 10), K2 = rep(c("c", "d"), 10), K3 = rep(c("e", "f"), 10),
    K4 = rep(c("g", "h"), 10), K5 = rep(c("i", "j"), 10), K6 = rep(c("k", "l"), 10),
    stringsAsFactors = FALSE
  )

  paket <- env$pk_packet_build(veri, .pk_packet_query(),
                               list(authorized_rows = 20L, filtered_rows = 20L))

  expect_length(paket$categorical, 6L)
  sutunlar <- vapply(paket$categorical, function(k) k$column, character(1))
  expect_true("K6" %in% sutunlar)

  ilk <- paket$categorical[[1]]
  expect_equal(ilk$distinct, 2L)
  expect_equal(ilk$top[[1]]$count, 10L)
  expect_equal(ilk$top[[1]]$share, 0.5)

  metin <- env$pk_packet_render(paket, budget = 200000L)$text
  expect_true(grepl("K6", metin, fixed = TRUE))
  expect_true(grepl("%50,0", metin, fixed = TRUE))
})

test_that("D17: ilk-K disinda kalan degerler 'Diger' olarak toplanir", {
  env <- .pk_packet_env()
  veri <- data.frame(K = paste0("deger_", seq_len(25)), stringsAsFactors = FALSE)

  paket <- env$pk_packet_build(veri, .pk_packet_query(),
                               list(authorized_rows = 25L, filtered_rows = 25L))
  kat <- paket$categorical[[1]]

  expect_equal(kat$distinct, 25L)
  expect_length(kat$top, 10L)
  expect_equal(kat$other_values, 15L)
  # inceleme bulgusu: "Diğer" artık yalnızca kaç FARKLI değer kaldığını
  # değil, KAÇ SATIR tuttuğunu ve payını da söyler (uzun kuyruk sayısız bir
  # dipnot olarak görünemez).
  # Her sayı KENDİ `[fact:...]` işaretini taşır (dosya sözleşmesi): işaretsiz
  # basılan bir sayı `block` kipinde köksüz iddia sayılıp yanıtı düşürüyordu.
  metin <- env$pk_packet_render(paket, 200000L)$text
  expect_true(grepl("Diger (15 deger [fact:", metin, fixed = TRUE))
  expect_true(grepl("15 satir [fact:", metin, fixed = TRUE))
  expect_true(grepl("%60,0 [fact:", metin, fixed = TRUE))
})

# --- D18: konumsal yanli olmayan ornek ----------------------------------------

test_that("D18: ornek satirlar head() DEGILDIR; ilk-N/son-N/uc deger/tabakali karisimidir", {
  env <- .pk_packet_env()
  veri <- data.frame(
    Grup = rep(c("A", "B", "C", "D"), each = 100),
    Olcu = c(seq_len(100), seq_len(100) + 1000, seq_len(100) + 2000, seq_len(100) + 3000),
    stringsAsFactors = FALSE
  )

  ornek <- env$pk_packet_examples(veri, list(), "Olcu", "Grup", n = 30L, seed = 42L)

  expect_equal(nrow(ornek$rows), 30L)
  # head(400)[1:30] yalnizca A grubunu icerirdi; tabakali ornek dortunu de gorur.
  expect_true(length(unique(ornek$rows$Grup)) >= 3L)
  expect_false(identical(ornek$indices, seq_len(30L)))
  expect_true(grepl("en_yuksek", ornek$method, fixed = TRUE))
  expect_true(grepl("tabakali_ornek", ornek$method, fixed = TRUE))
})

test_that("D18: sabit tohum ayni ornegi uretir ve global RNG durumunu bozmaz", {
  env <- .pk_packet_env()
  veri <- data.frame(Grup = rep(c("A", "B"), each = 50), Olcu = seq_len(100),
                     stringsAsFactors = FALSE)

  set.seed(999)
  onceki <- runif(1)
  set.seed(999)
  invisible(runif(1))
  durum_once <- .Random.seed

  a <- env$pk_packet_examples(veri, list(), "Olcu", "Grup", n = 20L, seed = 42L)
  durum_sonra <- .Random.seed
  b <- env$pk_packet_examples(veri, list(), "Olcu", "Grup", n = 20L, seed = 42L)

  expect_identical(a$indices, b$indices)
  expect_identical(durum_once, durum_sonra)
  expect_true(is.numeric(onceki))
})

test_that("Satir sayisi ornek kotasinin altindaysa tum kume dondurulur", {
  env <- .pk_packet_env()
  veri <- data.frame(A = 1:5)
  ornek <- env$pk_packet_examples(veri, list(), "A", NULL, n = 30L, seed = 42L)
  expect_equal(nrow(ornek$rows), 5L)
  expect_identical(ornek$method, "tam_kume")
})

# --- D7 / D8: butce ve FILTRELEME UYARISI -------------------------------------

.pk_packet_big <- function() {
  data.frame(
    Proje = paste0("SENTETIK_", seq_len(400)),
    Aciklama = strrep("x", 200),
    Olcu = seq_len(400),
    stringsAsFactors = FALSE
  )
}

test_that("D7: butce TUM yuku olcer ve ornek satirlari once dusurur", {
  env <- .pk_packet_env()
  paket <- env$pk_packet_build(.pk_packet_big(), .pk_packet_query(),
                               list(authorized_rows = 1000L, filtered_rows = 400L))

  genis <- env$pk_packet_render(paket, budget = 200000L)
  dar <- env$pk_packet_render(paket, budget = 4000L)

  expect_true(genis$example_rows > 0L)
  expect_true(dar$chars < genis$chars)
  expect_true(dar$example_rows < genis$example_rows)
  expect_true(length(dar$omitted) > 0L)
})

test_that("D8: FILTRELEME UYARISI HER dusurme basamaginda hayatta kalir", {
  env <- .pk_packet_env()
  paket <- env$pk_packet_build(.pk_packet_big(), .pk_packet_query(),
                               list(authorized_rows = 1000L, filtered_rows = 400L))

  for (butce in c(200000L, 8000L, 3000L, 1500L, 1000L)) {
    metin <- env$pk_packet_render(paket, budget = butce)$text
    expect_true(grepl("FİLTRELEME UYARISI", metin, fixed = TRUE),
                info = sprintf("Butce %d icin uyari kayboldu.", butce))
    expect_true(grepl("Yetki dahilinde toplam satir", metin, fixed = TRUE))
  }
})

test_that("Bozulma (timeout) mesaji her butcede pakette kalir", {
  env <- .pk_packet_env()
  paket <- env$pk_packet_build(
    .pk_packet_big(), .pk_packet_query(),
    list(authorized_rows = 1000L, filtered_rows = 400L, filter_status = "timeout",
         degradations = list(list(code = "filter_timeout",
                                  message = "Filtre cikarimi zaman asimina ugradi.")))
  )

  for (butce in c(200000L, 1000L)) {
    metin <- env$pk_packet_render(paket, budget = butce)$text
    expect_true(grepl("BOZULMA", metin, fixed = TRUE))
  }
})

test_that("Dusurulen bolumler ACIKCA yazilir", {
  env <- .pk_packet_env()
  paket <- env$pk_packet_build(.pk_packet_big(), .pk_packet_query(),
                               list(authorized_rows = 1000L, filtered_rows = 400L))
  sonuc <- env$pk_packet_render(paket, budget = 1200L)

  expect_true(grepl("SINIRLILIKLAR", sonuc$text, fixed = TRUE))
  expect_true(any(grepl("DUSURULDU|GONDERILMEDI|dusuruldu", sonuc$omitted)))
})

# --- Modele giden pakette RLS ONCESI sayi YOKTUR ------------------------------

test_that("Paket YALNIZCA yetkili ve filtre sonrasi populasyonu tasir; RLS oncesi sayi YOK", {
  env <- .pk_packet_env()
  veri <- data.frame(A = seq_len(40))

  paket <- env$pk_packet_build(veri, .pk_packet_query(), list(
    authorized_rows = 12405L, filtered_rows = 40L,
    # Cagiran kazara RLS oncesi sayiyi gecirse bile pakete GIRMEMELIDIR.
    pre_rls_rows = 41930L
  ))
  metin <- env$pk_packet_render(paket, budget = 200000L)$text

  expect_true(grepl("12.405", metin, fixed = TRUE))
  expect_false(grepl("41930", metin, fixed = TRUE))
  expect_false(grepl("41.930", metin, fixed = TRUE))
  expect_null(paket$scope$pre_rls_rows)

  duz <- as.character(unlist(paket, use.names = FALSE))
  expect_false(any(duz == "41930", na.rm = TRUE))
})

test_that("Kaynak imzasi RLS oncesi sayi icermez", {
  env <- .pk_packet_env()
  imza <- env$pk_scope_signature(12405L, 312L)
  expect_identical(imza, "yetki=12405|filtre=312")
})

# --- Kapsama ------------------------------------------------------------------

test_that("Kapsama: bos oranlari ve beyan edilen tanecikte mukerrer satir raporlanir", {
  env <- .pk_packet_env()
  veri <- data.frame(
    Anahtar = c("a", "a", "b", "c"),
    Deger = c(1, NA, 3, 4),
    stringsAsFactors = FALSE
  )

  kapsama <- env$pk_packet_coverage(veri, list(grain_columns = "Anahtar"))
  expect_equal(kapsama$rows, 4L)
  expect_equal(kapsama$duplicate_rows_at_grain, 1L)
  eksik <- Filter(function(m) identical(m$column, "Deger"), kapsama$missing)[[1]]
  expect_equal(eksik$missing, 1L)
  expect_equal(eksik$share, 0.25)
})

test_that("grain_columns yoksa mukerrer iddiasi URETILMEZ (Tier-0 geri dususu)", {
  env <- .pk_packet_env()
  kapsama <- env$pk_packet_coverage(data.frame(A = c(1, 1, 2)), list())
  expect_true(is.na(kapsama$duplicate_rows_at_grain))
})

# --- Grup kirilimi ------------------------------------------------------------

test_that("Grup kirilimi default_group_by x default_measures ile calisir ve Diger toplar", {
  env <- .pk_packet_env()
  veri <- data.frame(
    Bolum = rep(paste0("B", seq_len(20)), each = 3),
    Saat = rep(c(1, 2, 3), 20),
    stringsAsFactors = FALSE
  )
  meta <- list(
    default_group_by = "Bolum", default_measures = "Saat",
    column_meta = list(Saat = list(label = "Saat", role = "measure", additive = TRUE))
  )

  gruplar <- env$pk_packet_groups(veri, meta, scope = "yetki=60|filtre=60", top_n = 15L)
  expect_length(gruplar$top, 15L)
  expect_equal(gruplar$other_groups, 5L)
  expect_equal(gruplar$other_rows, 15L)

  olgu <- Filter(function(o) identical(o$aggregation, "sum"), gruplar$top[[1]]$facts)[[1]]
  expect_equal(olgu$value, 6)
  # Grup etiketi sütun adıyla nitelenir ("Bolum=\"B1\""): düz birleştirme
  # `("A | B", "C")` ile `("A", "B | C")` gruplarını aynı gösterirdi.
  expect_identical(gruplar$top[[1]]$group, "Bolum=\"B1\"")
  expect_true(grepl("^saat\\.sum\\.bolum_b[0-9]+\\.[0-9a-f]{6}$", olgu$fact_id))
})

test_that("default_group_by yoksa grup kirilimi URETILMEZ", {
  env <- .pk_packet_env()
  expect_length(env$pk_packet_groups(data.frame(A = 1:3), list()), 0L)
})

# --- Tier-0 sinirliligi ifsa edilir -------------------------------------------

test_that("Metadata yoksa paket bunu SINIRLILIK olarak yazar", {
  env <- .pk_packet_env()
  paket <- env$pk_packet_build(data.frame(A = c(1, 2, 3)), .pk_packet_query(),
                               list(authorized_rows = 3L, filtered_rows = 3L))

  expect_true(any(grepl("Tier-0", paket$limitations, fixed = TRUE)))
  expect_true(grepl("Tier-0", env$pk_packet_render(paket, 200000L)$text, fixed = TRUE))
})

test_that("Agirlik sutunu sonucta yoksa bu SINIRLILIK olarak ifsa edilir", {
  env <- .pk_packet_env()
  q <- .pk_packet_query(list(
    Yuzde = list(label = "Yüzde", role = "measure", unit = "%", decimals = 1L,
                 percent_scale = "points", aggregate = "weighted_mean",
                 weight_by = "OlmayanSutun")
  ))

  paket <- env$pk_packet_build(data.frame(Yuzde = c(10, 20)), q,
                               list(authorized_rows = 2L, filtered_rows = 2L))
  expect_true(any(grepl("agirlik sutunu", paket$limitations, fixed = TRUE)))
})

test_that("Onceden toplulastirilmis sutunlar sayisal olgudan cikarilir ve ifsa edilir", {
  env <- .pk_packet_env()
  veri <- data.frame(Toplu = c(5, 5, 5), Normal = c(1, 2, 3))

  paket <- env$pk_packet_build(veri, .pk_packet_query(), list(
    authorized_rows = 3L, filtered_rows = 3L, pre_aggregated_columns = "Toplu"
  ))

  sutunlar <- unique(vapply(paket$facts, function(o) o$column, character(1)))
  expect_false("Toplu" %in% sutunlar)
  expect_true("Normal" %in% sutunlar)
  expect_true(any(grepl("Onceden toplulastirilmis", paket$limitations, fixed = TRUE)))
})

test_that("Sonlu gozlem / disarida birakilan sayilari ISARETLI basilir ve olgu kaydinda karsiligi vardir", {
  env <- .pk_packet_env()

  paket <- list(
    facts = list(list(
      kind = "measure", column = "Butce", aggregation = "sum",
      value = 1234567, status = "ok", display = "1.234.567", label = "Butce",
      fact_id = "butce.sum.overall.sentetik",
      n_finite = 15234L, n_excluded = 812L
    )),
    scope = list(authorized_rows = 20000L, filtered_rows = 16046L,
                 scope_signature = "sentetik-kapsam"),
    coverage = list(rows = 16046L, columns = 4L)
  )

  metin <- env$.pk_render_facts(paket)
  expect_true(grepl("Sonlu gozlem", metin, fixed = TRUE))

  # Yazicinin BASTIGI her isaret, olgu kaydinda GERCEKTEN bulunmalidir; aksi
  # halde dort haneli bir sayim `block` kipinde `missing_fact_marker` uretip
  # TUM yaniti determinist yedekle degistiriyordu.
  isaretler <- regmatches(metin, gregexpr("\\[fact:[^]]+\\]", metin))[[1]]
  isaretler <- gsub("^\\[fact:|\\]$", "", isaretler)
  expect_true(length(isaretler) >= 3L)

  olgular <- env$pk_packet_all_facts(paket)
  kimlikler <- vapply(olgular, function(o) o$fact_id, character(1))
  expect_identical(setdiff(isaretler, kimlikler), character(0))

  # Iki sayim da BAGLAM olgusu olarak uretilir ve degerleri korunur.
  bul <- function(agg) {
    hedef <- Filter(function(o) identical(o$aggregation, agg), olgular)
    if (!length(hedef)) return(NULL)
    hedef[[1]]$value
  }
  expect_equal(bul("finite_count"), 15234)
  expect_equal(bul("excluded_count"), 812)
})

test_that("ayni sutunun BIRDEN COK olgusunda sayim, yazicinin bastigi ILK olgudan gelir", {
  env <- .pk_packet_env()

  # Yazici sutun basligini `alt[[1]]` (ILK olgu) uzerinden basar. Baglam olgusu
  # kaydi kimlige gore tekillestirdigi icin SON yazan kazanirdi; ayni sutunun
  # ikinci olgusu farkli bir `n_finite` tasidiginda kayittaki deger ile basilan
  # deger AYRISIYOR ve dogru alintilanmis bir sayim `value_mismatch` sayiliyordu.
  paket <- list(
    facts = list(
      list(kind = "measure", column = "Butce", aggregation = "sum", value = 1,
           status = "ok", display = "1", label = "Butce", fact_id = "b.sum.sentetik",
           n_finite = 15234L, n_excluded = 812L),
      list(kind = "measure", column = "Butce", aggregation = "mean", value = 2,
           status = "ok", display = "2", label = "Butce", fact_id = "b.mean.sentetik",
           n_finite = 999L, n_excluded = 1L)
    ),
    scope = list(scope_signature = "sentetik-kapsam"),
    coverage = list(rows = 16046L, columns = 4L)
  )

  metin <- env$.pk_render_facts(paket)
  olgular <- env$pk_packet_all_facts(paket)
  kimlikler <- vapply(olgular, function(o) o$fact_id, character(1))

  isaretler <- gsub("^\\[fact:|\\]$", "",
                    regmatches(metin, gregexpr("\\[fact:[^]]+\\]", metin))[[1]])
  expect_identical(setdiff(isaretler, kimlikler), character(0))

  sayim <- Filter(function(o) identical(o$aggregation, "finite_count"), olgular)
  expect_length(sayim, 1L)
  expect_equal(sayim[[1]]$value, 15234)
})

# --- Pay olguları: birim ve ondalık sözleşmesi --------------------------------

test_that("pay olgulari `%` birimi ve BIR ondalik tasir", {
  env <- .pk_packet_env()

  # GERİLEME: `.pk_count_fact()` `decimals = 0L` sabitliyor ve birim BEYAN
  # ETMİYORDU. Yazıcı payı `%25,0` olarak basıyor, doğrulayıcı ise
  # `iddia$percent = TRUE` iken `olgu_birimi` boş olduğu için `unit_mismatch`
  # üretiyordu; `block` kipinde GEÇERLİ yanıt determinist yedekle değişiyordu.
  paket <- list(
    # URETIM ALAN ADI (PR #705 incelemesi, P3): `pk_packet_context_facts()`
    # `packet$categorical` okur. `categoricals` yalnizca R'nin `$` KISMI AD
    # eslesmesiyle cozuluyordu; ayni onekli ikinci bir alan eklendiginde
    # `olgular` bosalir, `sprintf()` `character(0)` doner ve testler HICBIR
    # SEYI dogrulamadan gecerdi.
    categorical = list(list(
      column = "Durum", label = "Durum", total = 20,
      distinct = 3L, other_rows = 5L, other_values = 1L,
      top = list(list(value = "Aktif", count = 5))
    ))
  )

  olgular <- env$pk_packet_context_facts(paket)

  kategori_payi <- .pk_packet_fact(olgular, "Durum", "category_share")
  diger_payi <- .pk_packet_fact(olgular, "Durum", "other_share")

  for (olgu in list(kategori_payi, diger_payi)) {
    expect_false(is.null(olgu))
    expect_identical(olgu$unit, "%")
    expect_identical(as.integer(olgu$decimals), 1L)
    expect_equal(olgu$value, 25, tolerance = 1e-9)
  }

  # SAYIM olguları birimsiz ve tam sayıdır; pay düzeltmesi onları BOZMAMALIDIR.
  sayim <- .pk_packet_fact(olgular, "Durum", "category_count")
  expect_false(is.null(sayim))
  expect_null(sayim$unit)
  expect_identical(as.integer(sayim$decimals), 0L)
})

test_that("dogru alintilanan bir pay iddiasi `unit_mismatch` uretmez", {
  env <- .pk_packet_env()
  kok <- resolve_repo_root_for_tests()
  for (dosya in c("helpers_pk_ascii_tokens.R", "helpers_pk_numeric_provenance.R",
                  "helpers_pk_numeric_provenance_claims.R")) {
    source(file.path(kok, "R", dosya), encoding = "UTF-8", local = env)
  }

  paket <- list(
    # URETIM ALAN ADI (PR #705 incelemesi, P3): `pk_packet_context_facts()`
    # `packet$categorical` okur. `categoricals` yalnizca R'nin `$` KISMI AD
    # eslesmesiyle cozuluyordu; ayni onekli ikinci bir alan eklendiginde
    # `olgular` bosalir, `sprintf()` `character(0)` doner ve testler HICBIR
    # SEYI dogrulamadan gecerdi.
    categorical = list(list(
      column = "Durum", label = "Durum", total = 20,
      distinct = 2L, other_rows = 0L, other_values = 0L,
      top = list(list(value = "Aktif", count = 5))
    ))
  )
  olgular <- env$pk_packet_context_facts(paket)
  pay <- .pk_packet_fact(olgular, "Durum", "category_share")

  # PAY OLGUSU VAR OLMALIDIR (PR #705 incelemesi, P3): olgu bulunamazsa
  # `pay$fact_id` `NULL` olur, `sprintf()` `character(0)` doner, dogrulayici
  # `NA` metin alir ve `nedenler` bosalir; `expect_false(... %in% ...)` bos
  # kumede KENDILIGINDEN gecerdi.
  expect_false(is.null(pay))
  expect_true(is.character(pay$fact_id) && nzchar(pay$fact_id))

  metin <- sprintf("Aktif orani %%25,0 [fact:%s] seviyesindedir.", pay$fact_id)
  expect_length(metin, 1L)
  sonuc <- env$pk_numeric_provenance_validate(metin, olgular)
  # IDDIA GERCEKTEN TARANDI: bos tarama sonucu da asagidaki olumsuz iddiayi
  # kendiliginden gecirirdi.
  expect_gte(sonuc$checked, 1L)

  nedenler <- vapply(sonuc$mismatches %||% list(),
                     function(m) as.character(m$reason)[1], character(1))
  expect_false("unit_mismatch" %in% nedenler)
})

# ---------------------------------------------------------------------------
# NA sayimlar ve TUKENMIS butce: yazici/olgu uretimi kapali basarisiz olur.
# ---------------------------------------------------------------------------

test_that("NA daraltma sayilari olgu uretimini DUSURMEZ", {
  env <- .pk_packet_env()
  veri <- data.frame(K = paste0("deger_", seq_len(25)), stringsAsFactors = FALSE)
  paket <- env$pk_packet_build(veri, .pk_packet_query(),
                               list(authorized_rows = 25L, filtered_rows = 25L))

  # `%||%` YALNIZCA `NULL` atlar; `NA` sayim `if (NA > 0L)` ile TUM olgu
  # uretimini "missing value where TRUE/FALSE needed" hatasiyla dusuruyordu.
  paket$categorical[[1]]$other_rows <- NA_integer_
  paket$categorical[[1]]$other_values <- NA_integer_

  olgular <- env$pk_packet_all_facts(paket)
  expect_true(is.list(olgular))
  expect_true(length(olgular) > 0L)
})

test_that("NA grup sayisi paket yazimini DUSURMEZ", {
  env <- .pk_packet_env()
  veri <- data.frame(G = rep(c("a", "b"), 10), S = seq_len(20),
                     stringsAsFactors = FALSE)
  paket <- env$pk_packet_build(veri, .pk_packet_query(),
                               list(authorized_rows = 20L, filtered_rows = 20L))

  paket$groups <- list(list(group_by = "G", other_groups = NA_integer_,
                            other_rows = NA_integer_, top = list()))
  yazi <- env$pk_packet_render(paket, budget = 200000L)
  expect_true(is.character(yazi$text))
  expect_true(nzchar(yazi$text))
})

test_that("SIFIR butce 'ayarlanmadi' sayilmaz; over_budget bildirilir", {
  env <- .pk_packet_env()
  veri <- data.frame(K = rep(c("a", "b"), 10), stringsAsFactors = FALSE)
  paket <- env$pk_packet_build(veri, .pk_packet_query(),
                               list(authorized_rows = 20L, filtered_rows = 20L))

  # `.pk_result_packet_budget()` sabit yuk butceyi astiginda bilerek `0L`
  # dondurur; varsayilana cevrilirse tukenmis durum silinir ve determinist
  # ozet yedegi HIC calismaz.
  sonuc <- env$pk_packet_render(paket, budget = 0L)
  expect_identical(sonuc$budget, 0L)
  expect_true(isTRUE(sonuc$over_budget))

  # NULL/NA hala varsayilana duser.
  expect_true(env$pk_packet_render(paket, budget = NA_integer_)$budget > 0L)
})
