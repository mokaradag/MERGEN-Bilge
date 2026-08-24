# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-statistical-summary-regression-behavior.R
# Açıklama: PR #705 incelemesinde tespit edilen istatistiksel özet ve tarih
#           dönüşümü kusurlarının davranışsal regresyon kapsamı.
#
#           Kapsanan bulgular:
#             * U44 - `convert_date_columns()` KARIŞIK biçimli sütunlarda yedek
#               biçimleri denemiyordu; kalan gerçek tarihler sessizce NA oluyordu.
#             * U45 - `generate_statistical_summary()` her sayısal sütunu ÖLÇÜ
#               sayıyordu; kimlik/kod/yıl alanlarına toplam-ortalama üretiyordu.
#             * v1 kırpma özyinelemesi `mode`/`rls_total_rows`/
#               `user_filter_applied` kapsam argümanlarını düşürüyordu.
#
#           Testler ÇEVRİMDIŞI ve DETERMİNİSTİKtir: gerçek DB/LLM/ağ/SSO yoktur
#           ve üretim SQL'i, proje adı veya VM veri kümesi KULLANILMAZ.
# ==============================================================================

.pk_summary_test_env <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  env$MAX_ANALYSIS_PROMPT_CHARS <- 100000L
  source(file.path(kok, "R", "helpers_pk_statistical_summary.R"), encoding = "UTF-8", local = env)
  env
}

.pk_core_test_env <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "helpers_pk_analysis_core_impl.R"), encoding = "UTF-8", local = env)
  env
}

.pk_ozet_kaydi <- function(env, ...) {
  invisible(utils::capture.output(sonuc <- env$generate_statistical_summary(...)))
  sonuc
}

# ------------------------------------------------------------------ U44 ------

test_that("convert_date_columns KARIŞIK biçimli sütunda kalan değerleri de çevirir", {
  env <- .pk_core_test_env()
  veri <- data.frame(
    Tarih = c("01.02.2024", "2024-03-15", "16/04/2024", NA, ""),
    stringsAsFactors = FALSE
  )

  invisible(utils::capture.output(sonuc <- env$convert_date_columns(veri, "Tarih")))

  expect_s3_class(sonuc$Tarih, "Date")
  expect_equal(as.character(sonuc$Tarih[1]), "2024-02-01")
  # Regresyon: ilk biçim bazılarını çevirdiği için yedekler ATLANIYORDU.
  expect_equal(as.character(sonuc$Tarih[2]), "2024-03-15")
  expect_equal(as.character(sonuc$Tarih[3]), "2024-04-16")
  expect_true(is.na(sonuc$Tarih[4]))
  expect_true(is.na(sonuc$Tarih[5]))
})

test_that("convert_date_columns tek biçimli sütunda davranışını korur", {
  env <- .pk_core_test_env()
  veri <- data.frame(Tarih = c("01.02.2024", "02.02.2024"), stringsAsFactors = FALSE)

  invisible(utils::capture.output(sonuc <- env$convert_date_columns(veri, "Tarih")))

  expect_s3_class(sonuc$Tarih, "Date")
  expect_equal(as.character(sonuc$Tarih), c("2024-02-01", "2024-02-02"))
})

test_that("convert_date_columns çözülemeyen sütunu Date'e ZORLAMAZ", {
  env <- .pk_core_test_env()
  veri <- data.frame(Tarih = c("abc", "def", "ghi"), stringsAsFactors = FALSE)

  invisible(utils::capture.output(sonuc <- env$convert_date_columns(veri, "Tarih")))

  expect_type(sonuc$Tarih, "character")
  expect_equal(sonuc$Tarih, c("abc", "def", "ghi"))
})

# ------------------------------------------------------------------ U45 ------

test_that("küratörlü metadata 'dimension' diyen sayısal sütuna ÖLÇÜ muamelesi yapılmaz", {
  env <- .pk_summary_test_env()
  veri <- data.frame(
    KayitKodu = c(10L, 10L, 20L, 20L),
    Tutar     = c(1.5, 2.5, 3.5, 4.5),
    stringsAsFactors = FALSE
  )
  meta <- list(
    KayitKodu = list(role = "dimension"),
    Tutar     = list(role = "measure", additive = TRUE)
  )

  sonuc <- .pk_ozet_kaydi(env, veri, column_meta = meta)

  expect_true(grepl("ÖLÇÜ OLMAYAN SAYISAL SÜTUNLAR", sonuc$summary_text, fixed = TRUE))
  expect_true(grepl("SAYISAL SUTUNLAR OZETI", sonuc$summary_text, fixed = TRUE))

  olcu_blok <- strsplit(sonuc$summary_text, "SAYISAL SUTUNLAR OZETI", fixed = TRUE)[[1]][2]
  expect_true(grepl("Tutar", olcu_blok, fixed = TRUE))
  # Regresyon: kod sütunu için toplam/ortalama üretiliyordu.
  expect_false(grepl("Kayit Kodu", olcu_blok, fixed = TRUE))
})

test_that("metadata additive=FALSE diyen ölçüye toplam üretilmez", {
  env <- .pk_summary_test_env()
  veri <- data.frame(
    Oran  = c(0.1, 0.2, 0.3, 0.4),
    Tutar = c(1, 2, 3, 4),
    stringsAsFactors = FALSE
  )
  meta <- list(
    Oran  = list(role = "measure", additive = FALSE),
    Tutar = list(role = "measure", additive = TRUE)
  )

  sonuc <- .pk_ozet_kaydi(env, veri, column_meta = meta)
  olcu_blok <- strsplit(sonuc$summary_text, "SAYISAL SUTUNLAR OZETI", fixed = TRUE)[[1]][2]

  expect_true(grepl("Tutar", olcu_blok, fixed = TRUE))
  expect_false(grepl("Oran", olcu_blok, fixed = TRUE))
})

test_that("metadata YOKKEN küçük örneklemde ölçü sütunu kimlik sanılmaz", {
  env <- .pk_summary_test_env()
  # Regresyon: 3 satırlık gerçek bir ölçü de benzersizdir; benzersizlik TEK
  # BAŞINA kimlik kanıtı değildir.
  veri <- data.frame(Saat = c(10, 20, 30), Proje = c("A", "B", "A"), stringsAsFactors = FALSE)

  sonuc <- .pk_ozet_kaydi(env, veri)

  expect_true(grepl("SAYISAL SUTUNLAR OZETI", sonuc$summary_text, fixed = TRUE))
  expect_false(grepl("ÖLÇÜ OLMAYAN SAYISAL SÜTUNLAR", sonuc$summary_text, fixed = TRUE))
})

test_that("metadata YOKKEN yalnızca kanıtlanabilir kimlik sütunu dışlanır", {
  env <- .pk_summary_test_env()
  # Kimlik çıkarımı için YETERLİ örneklem gerekir (bkz. .PK_STAT_ID_MIN_ROWS);
  # 24 satır eşiğin üzerindedir.
  n <- 24L
  veri <- data.frame(
    SatirKimligi = seq_len(n),                             # benzersiz tamsayı
    Donem        = rep(c(2021L, 2022L, 2023L), length.out = n),
    Tutar        = as.numeric(seq_len(n)) + 0.5,
    stringsAsFactors = FALSE
  )

  sonuc <- .pk_ozet_kaydi(env, veri)
  olcu_blok <- strsplit(sonuc$summary_text, "SAYISAL SUTUNLAR OZETI", fixed = TRUE)[[1]][2]

  expect_false(grepl("Satir Kimligi", olcu_blok, fixed = TRUE))
  # Metadata yokken ANLAM ÜRETİLMEZ: tekrar eden tamsayı ve ondalıklı ölçü kalır.
  expect_true(grepl("Donem", olcu_blok, fixed = TRUE))
  expect_true(grepl("Tutar", olcu_blok, fixed = TRUE))
})

test_that("ölçü olmayan sayısal sütunlar GİZLENMEZ, açıkça bildirilir", {
  env <- .pk_summary_test_env()
  veri <- data.frame(
    DurumKodu = c(1L, 1L, 2L, 2L),
    Tutar     = c(5, 6, 7, 8),
    stringsAsFactors = FALSE
  )
  meta <- list(DurumKodu = list(role = "dimension"), Tutar = list(role = "measure"))

  sonuc <- .pk_ozet_kaydi(env, veri, column_meta = meta)

  expect_true(grepl("Durum Kodu", sonuc$summary_text, fixed = TRUE))
  expect_true(grepl("ASLA toplam, ortalama", sonuc$summary_text, fixed = TRUE))
})

test_that("tüm sayısal sütunlar ölçü değilse sayısal özet bloğu üretilmez", {
  env <- .pk_summary_test_env()
  veri <- data.frame(Kod = c(1L, 1L, 2L), Ad = c("a", "b", "c"), stringsAsFactors = FALSE)
  meta <- list(Kod = list(role = "dimension"))

  sonuc <- .pk_ozet_kaydi(env, veri, column_meta = meta)

  expect_false(grepl("SAYISAL SUTUNLAR OZETI", sonuc$summary_text, fixed = TRUE))
  expect_true(grepl("ÖLÇÜ OLMAYAN SAYISAL SÜTUNLAR", sonuc$summary_text, fixed = TRUE))
})

# ------------------------------------------------------ kapsam özyinelemesi ---

test_that("v1 kırpma özyinelemesi FİLTRELEME UYARISINI düşürmez", {
  env <- .pk_summary_test_env()
  env$pk_engine_is_v2 <- function(...) FALSE
  veri <- data.frame(
    Ad    = paste0("kayit_", sprintf("%03d", 1:60)),
    Tutar = as.numeric(1:60),
    stringsAsFactors = FALSE
  )

  sonuc <- .pk_ozet_kaydi(
    env, veri,
    max_preview_rows = 40,
    # Kırpma özyinelemesini TETİKLER ama "temel özet" dibine DÜŞMEZ; böylece
    # asıl regresyon (kapsam argümanlarının düşmesi) ölçülebilir kalır.
    max_total_chars = 1400,
    mode = "full",
    rls_total_rows = 500,
    user_filter_applied = TRUE
  )

  # Regresyon: özyinelemede `user_filter_applied` düşünce uyarı kayboluyordu.
  expect_true(grepl("FİLTRELEME UYARISI", sonuc$summary_text, fixed = TRUE))
  expect_true(grepl("500", sonuc$summary_text, fixed = TRUE))
})

# ------------------------------------------------- inceleme takibi: ölçüler ---

test_that("benzersiz tam sayılı ÖLÇÜ kimlik sanılıp istatistikten dışlanmaz", {
  env <- .pk_summary_test_env()

  # 24 satırlık gerçek bir tutar sütunu: tam sayı, birbirinden farklı ama
  # vekil anahtarın YOĞUN ARTAN dizisi DEĞİL. Eski kural yalnızca
  # "tamsayı + benzersiz" aradığı için bunu kimlik sayıp toplam/ortalama
  # üretmiyor ve modele "bu değerleri ASLA toplama" diyordu.
  tutarlar <- c(1250, 4300, 990, 15600, 2075, 8320, 640, 11500,
                3380, 7215, 950, 20450, 1875, 6640, 12300, 480,
                5290, 9150, 2740, 17800, 1360, 4025, 8880, 13470)
  expect_length(unique(tutarlar), length(tutarlar))
  expect_true(all(tutarlar == round(tutarlar)))

  metin <- paste(.pk_ozet_kaydi(
    env,
    data.frame(Tutar = tutarlar, stringsAsFactors = FALSE),
    mode = "summary"
  ), collapse = "\n")

  expect_true(grepl("Tutar", metin, fixed = TRUE))
  expect_false(grepl("ÖLÇÜ DEĞİLDİR", metin, fixed = TRUE))
  expect_true(grepl("Toplam", metin, fixed = TRUE))
})

test_that("yoğun artan vekil anahtar dizisi ÖLÇÜ sayılmaz", {
  env <- .pk_summary_test_env()

  metin <- paste(.pk_ozet_kaydi(
    env,
    data.frame(KayitID = 1:24, stringsAsFactors = FALSE),
    mode = "summary"
  ), collapse = "\n")

  expect_true(grepl("ÖLÇÜ DEĞİLDİR", metin, fixed = TRUE))
  expect_true(grepl("KayitID", metin, fixed = TRUE))
})
