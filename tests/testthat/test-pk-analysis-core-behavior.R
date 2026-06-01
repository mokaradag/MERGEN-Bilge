# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-analysis-core-behavior.R
# Açıklama: R/helpers_pk_analysis_core.R saf yardımcılarının DAVRANIŞSAL testleri.
#           Gerçek üretim fonksiyonları çağrılır ve dönen değerler doğrulanır:
#           summarize_columns_for_ai, convert_date_columns, normalize_pk_text_utf8,
#           normalize_pk_dataframe_utf8, normalize_sql_server_identifiers.
#           Mevcut sözleşme testi (test-pk-analysis-core-refactor-contract.R) yalnızca
#           tek bir mutlu yolu kapsadığı için burada kenar/sınır/hata durumları
#           genişletilir. Shiny/DBI/LLM/ağ GEREKMEZ; yalnızca base R.
#           Not: convert_date_columns cat() ile log basar; çıktı capture.output ile
#           yakalanarak strict runner uyarısız tutulur.
# ==============================================================================

.pkcore_source_once <- function() {
  if (exists("summarize_columns_for_ai", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_pk_analysis_core.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# convert_date_columns'ı cat çıktısını yutarak çağıran yardımcı
.pkcore_convert_quiet <- function(data, cols) {
  out <- NULL
  invisible(utils::capture.output(out <- convert_date_columns(data, cols)))
  out
}

# Bir ifadenin uyarı üretip üretmediğini sürüm-bağımsız ölçen yardımcı
.pkcore_warned <- function(expr) {
  warned <- FALSE
  withCallingHandlers(
    force(expr),
    warning = function(w) {
      warned <<- TRUE
      invokeRestart("muffleWarning")
    }
  )
  warned
}

# ------------------------------------------------------------------------------
# summarize_columns_for_ai
# ------------------------------------------------------------------------------
testthat::test_that("summarize_columns_for_ai boş/NULL veri için boş dize döndürür", {
  .pkcore_source_once()
  testthat::expect_identical(summarize_columns_for_ai(NULL), "")
  testthat::expect_identical(
    summarize_columns_for_ai(data.frame()),
    ""
  )
  bos <- data.frame(A = numeric(0), B = character(0), stringsAsFactors = FALSE)
  testthat::expect_identical(summarize_columns_for_ai(bos), "")
})

testthat::test_that("summarize_columns_for_ai sayısal sütun için min/maks/ort/kayıt verir", {
  .pkcore_source_once()
  df <- data.frame(Sayisal = c(1, 2, NA, 4), stringsAsFactors = FALSE)
  ozet <- summarize_columns_for_ai(df)
  testthat::expect_match(ozet, "Sayisal", fixed = TRUE)
  testthat::expect_match(ozet, "Min: 1", fixed = TRUE)
  testthat::expect_match(ozet, "Maks: 4", fixed = TRUE)
  testthat::expect_match(ozet, "Ort: 2.33", fixed = TRUE)   # mean(c(1,2,4)) = 2.333..
  testthat::expect_match(ozet, "Kayıt: 3", fixed = TRUE)
})

testthat::test_that("summarize_columns_for_ai tamamen NA sütunu (Hepsi NULL) olarak işaretler", {
  .pkcore_source_once()
  # Mevcut davranışın karakterizasyonu: all(is.na) önce kontrol edildiği için
  # sayısal-ama-tümü-NA bir sütun da '(Hepsi NULL)' döner; '(Sayısal, veri yok)'
  # dalı pratikte ULAŞILAMAZ koddur.
  df <- data.frame(
    BosKategori = c(NA_character_, NA_character_),
    BosSayi = c(NA_real_, NA_real_),
    stringsAsFactors = FALSE
  )
  ozet <- summarize_columns_for_ai(df)
  testthat::expect_match(ozet, "BosKategori: (Hepsi NULL)", fixed = TRUE)
  testthat::expect_match(ozet, "BosSayi: (Hepsi NULL)", fixed = TRUE)
  testthat::expect_false(grepl("veri yok", ozet, fixed = TRUE))
})

testthat::test_that("summarize_columns_for_ai Date ve POSIXt sütunları için aralık verir", {
  .pkcore_source_once()
  df_date <- data.frame(
    Tarih = as.Date(c("2024-01-01", "2024-01-02", NA, "2024-01-04")),
    stringsAsFactors = FALSE
  )
  ozet_date <- summarize_columns_for_ai(df_date)
  testthat::expect_match(ozet_date, "(Tarih, Aralık: 2024-01-01 - 2024-01-04)", fixed = TRUE)

  df_posix <- data.frame(
    Zaman = as.POSIXct(
      c("2024-03-01 10:00:00", "2024-03-05 12:30:00"),
      tz = "UTC"
    ),
    stringsAsFactors = FALSE
  )
  ozet_posix <- summarize_columns_for_ai(df_posix)
  testthat::expect_match(ozet_posix, "(Tarih, Aralık:", fixed = TRUE)
  testthat::expect_match(ozet_posix, "2024-03-01", fixed = TRUE)
  testthat::expect_match(ozet_posix, "2024-03-05", fixed = TRUE)
})

testthat::test_that("summarize_columns_for_ai metin sütununda 20'ye kadar benzersizi sıralar", {
  .pkcore_source_once()
  df <- data.frame(
    Kategori = c("B", "A", "B", NA, "A"),
    stringsAsFactors = FALSE
  )
  ozet <- summarize_columns_for_ai(df)
  # Benzersiz, NA'siz, sıralı: [A, B]
  testthat::expect_match(ozet, "Kategori: [A, B]", fixed = TRUE)
})

testthat::test_that("summarize_columns_for_ai 20'den fazla benzersizi kısaltır (+N deger daha)", {
  .pkcore_source_once()
  df <- data.frame(
    Kod = sprintf("v%02d", 1:25),
    stringsAsFactors = FALSE
  )
  ozet <- summarize_columns_for_ai(df)
  # İlk 15 gösterilir, kalan 10 = '+10 deger daha'
  testthat::expect_match(ozet, "(+10 deger daha)", fixed = TRUE)
  testthat::expect_true(grepl("v01", ozet, fixed = TRUE))
  testthat::expect_true(grepl("v15", ozet, fixed = TRUE))
  testthat::expect_false(grepl("v25", ozet, fixed = TRUE))  # kalanlar gizlenir
})

# ------------------------------------------------------------------------------
# convert_date_columns
# ------------------------------------------------------------------------------
testthat::test_that("convert_date_columns NULL/boş kolon listesi ve boş veri için değişmeden döner", {
  .pkcore_source_once()
  df <- data.frame(A = c("01.02.2024", "02.02.2024"), stringsAsFactors = FALSE)
  testthat::expect_identical(convert_date_columns(df, NULL), df)
  testthat::expect_identical(convert_date_columns(df, character(0)), df)
  testthat::expect_null(convert_date_columns(NULL, "A"))

  bos <- df[0, , drop = FALSE]
  testthat::expect_identical(convert_date_columns(bos, "A"), bos)
})

testthat::test_that("convert_date_columns üç formatı (dd.mm.yyyy / yyyy-mm-dd / dd/mm/yyyy) çözer", {
  .pkcore_source_once()

  df_dot <- data.frame(D = c("01.02.2024", "02.02.2024", "hatalı"),
                       stringsAsFactors = FALSE)
  r_dot <- .pkcore_convert_quiet(df_dot, "D")
  testthat::expect_s3_class(r_dot$D, "Date")
  testthat::expect_identical(as.character(r_dot$D[1]), "2024-02-01")
  testthat::expect_true(is.na(r_dot$D[3]))

  df_iso <- data.frame(D = c("2024-03-05", "2024-03-06"),
                       stringsAsFactors = FALSE)
  r_iso <- .pkcore_convert_quiet(df_iso, "D")
  testthat::expect_s3_class(r_iso$D, "Date")
  testthat::expect_identical(as.character(r_iso$D[1]), "2024-03-05")

  df_slash <- data.frame(D = c("05/03/2024", "06/03/2024"),
                         stringsAsFactors = FALSE)
  r_slash <- .pkcore_convert_quiet(df_slash, "D")
  testthat::expect_s3_class(r_slash$D, "Date")
  testthat::expect_identical(as.character(r_slash$D[1]), "2024-03-05")
})

testthat::test_that("convert_date_columns %50 eşiğinde çevirir, altında metin bırakır", {
  .pkcore_source_once()

  # 2/2 = %100 -> çevrilir (sınır üstü); 1/2 = %50 -> çevrilir (sınır dahil)
  df_sinir <- data.frame(D = c("01.02.2024", "bozuk"), stringsAsFactors = FALSE)
  r_sinir <- .pkcore_convert_quiet(df_sinir, "D")
  testthat::expect_s3_class(r_sinir$D, "Date")
  testthat::expect_identical(as.character(r_sinir$D[1]), "2024-02-01")
  testthat::expect_true(is.na(r_sinir$D[2]))

  # 1/3 = %33 -> eşiğin altında, sütun metin olarak korunur
  df_dusuk <- data.frame(D = c("01.02.2024", "bozuk1", "bozuk2"),
                         stringsAsFactors = FALSE)
  r_dusuk <- .pkcore_convert_quiet(df_dusuk, "D")
  testthat::expect_true(is.character(r_dusuk$D))
  testthat::expect_identical(r_dusuk$D, c("01.02.2024", "bozuk1", "bozuk2"))
})

testthat::test_that("convert_date_columns mevcut Date'i atlar ve olmayan kolonu yok sayar", {
  .pkcore_source_once()

  df_date <- data.frame(
    D = as.Date(c("2024-01-01", "2024-01-02")),
    stringsAsFactors = FALSE
  )
  r_date <- convert_date_columns(df_date, "D")  # Date dalı cat basmaz
  testthat::expect_s3_class(r_date$D, "Date")
  testthat::expect_identical(r_date$D, df_date$D)

  df_yok <- data.frame(X = c("a", "b"), stringsAsFactors = FALSE)
  testthat::expect_identical(convert_date_columns(df_yok, "OlmayanKolon"), df_yok)
})

# ------------------------------------------------------------------------------
# normalize_pk_text_utf8
# ------------------------------------------------------------------------------
testthat::test_that("normalize_pk_text_utf8 NULL ve karakter-olmayan girdiyi değiştirmeden döndürür", {
  .pkcore_source_once()
  testthat::expect_null(normalize_pk_text_utf8(NULL))
  testthat::expect_identical(normalize_pk_text_utf8(c(1, 2, 3)), c(1, 2, 3))
  testthat::expect_identical(normalize_pk_text_utf8(c(TRUE, FALSE)), c(TRUE, FALSE))
})

testthat::test_that("normalize_pk_text_utf8 factor'ü karaktere çevirir ve Türkçe metni korur", {
  .pkcore_source_once()
  fct <- factor(c("Çağrı", "Ömer", "Çağrı"))
  donen <- normalize_pk_text_utf8(fct)
  testthat::expect_true(is.character(donen))
  testthat::expect_identical(enc2utf8(donen), enc2utf8(c("Çağrı", "Ömer", "Çağrı")))

  metin <- "İş Dağılım Ağacı"
  testthat::expect_identical(enc2utf8(normalize_pk_text_utf8(metin)), enc2utf8(metin))
})

testthat::test_that("normalize_pk_text_utf8 NA'yı korur, UTF-8 işaretler ve uyarısızdır", {
  .pkcore_source_once()
  girdi <- c("abc", NA, "Türkçe")
  donen <- NULL
  uyarildi <- .pkcore_warned(donen <- normalize_pk_text_utf8(girdi))
  testthat::expect_false(uyarildi)
  testthat::expect_true(is.na(donen[2]))
  testthat::expect_identical(donen[1], "abc")
  testthat::expect_identical(enc2utf8(donen[3]), enc2utf8("Türkçe"))
  # ASCII dizeler R'de kodlama işareti almaz; bu yüzden UTF-8 işareti
  # ASCII-olmayan (Türkçe) öğede doğrulanır.
  testthat::expect_identical(Encoding(donen[3]), "UTF-8")
})

# ------------------------------------------------------------------------------
# normalize_pk_dataframe_utf8
# ------------------------------------------------------------------------------
testthat::test_that("normalize_pk_dataframe_utf8 NULL ve data.frame-olmayanı değiştirmez", {
  .pkcore_source_once()
  testthat::expect_null(normalize_pk_dataframe_utf8(NULL))
  liste <- list(a = 1, b = "x")
  testthat::expect_identical(normalize_pk_dataframe_utf8(liste), liste)
})

testthat::test_that("normalize_pk_dataframe_utf8 isim+metin sütununu normalize eder, sayısalı korur", {
  .pkcore_source_once()
  df <- data.frame(
    Sıra = c(1L, 2L),
    Ad = c("Çağrı", "Ömer"),
    stringsAsFactors = FALSE
  )
  donen <- normalize_pk_dataframe_utf8(df)
  testthat::expect_identical(enc2utf8(names(donen)), enc2utf8(c("Sıra", "Ad")))
  # Sayısal sütun (ilk sütun) içerik olarak korunur
  testthat::expect_identical(donen[[1]], c(1L, 2L))
  # Metin sütunu Türkçe değerlerini korur
  testthat::expect_identical(enc2utf8(donen[[2]]), enc2utf8(c("Çağrı", "Ömer")))
})

# ------------------------------------------------------------------------------
# normalize_sql_server_identifiers
# ------------------------------------------------------------------------------
testthat::test_that("normalize_sql_server_identifiers NULL/boş girdiyi değiştirmeden döndürür", {
  .pkcore_source_once()
  testthat::expect_null(normalize_sql_server_identifiers(NULL))
  testthat::expect_identical(normalize_sql_server_identifiers(""), "")
})

testthat::test_that("normalize_sql_server_identifiers köşeli paranteze QUOTED_IDENTIFIER ekler", {
  .pkcore_source_once()
  sql <- "SELECT [Adı Soyadı], [Aktivite Türü] FROM dbo.Test"
  donen <- normalize_sql_server_identifiers(sql)
  testthat::expect_match(donen, "SET QUOTED_IDENTIFIER ON;", fixed = TRUE)
  testthat::expect_match(donen, "\"Adı Soyadı\"", fixed = TRUE)
  testthat::expect_match(donen, "\"Aktivite Türü\"", fixed = TRUE)
})

testthat::test_that("normalize_sql_server_identifiers yalnızca boşluk/Türkçe içeren parantezi dönüştürür", {
  .pkcore_source_once()
  # Boşluk içeren parantez -> çift tırnağa çevrilir
  donen_bosluk <- normalize_sql_server_identifiers("SELECT [Order Date] FROM T")
  testthat::expect_match(donen_bosluk, "\"Order Date\"", fixed = TRUE)

  # Ne boşluk ne Türkçe içeren parantez -> mevcut davranış: olduğu gibi kalır
  donen_duz <- normalize_sql_server_identifiers("SELECT [PlainCol] FROM T")
  testthat::expect_true(grepl("[PlainCol]", donen_duz, fixed = TRUE))
  testthat::expect_false(grepl("\"PlainCol\"", donen_duz, fixed = TRUE))

  # Parantezsiz sorgu -> yalnızca prefix eklenir
  testthat::expect_identical(
    normalize_sql_server_identifiers("SELECT 1"),
    "SET QUOTED_IDENTIFIER ON;\nSELECT 1"
  )
})
