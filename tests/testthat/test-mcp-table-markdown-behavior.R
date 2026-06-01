# ==============================================================================
# Dosya Yolu: tests/testthat/test-mcp-table-markdown-behavior.R
# Açıklama: R/helpers_mcp_table_readers.R içindeki helpers_mcp_tools$create_md_table
#           Markdown tablo üreticisinin DAVRANIŞSAL testleri. Excel/CSV okuyucular
#           readxl/data.table/fs gerektirir ve burada KAPSANMAZ; yalnızca saf
#           Markdown üretimi test edilir:
#             - NULL / 0-satır -> "_Veri yok_"
#             - sayısal Türkçe biçimlendirme (big.mark=".", decimal.mark=",")
#             - logical -> TRUE/FALSE, Date/POSIXt -> karakter
#             - Türkçe değerlerin UTF-8 korunması
#             - mevcut davranış: as.data.frame(check.names) başlıktaki boşlukları
#               noktaya çevirir (karakterizasyon)
#           Shiny/DB/ağ GEREKMEZ. Sadece normalize_excel_path stub'ı gerekir;
#           global helpers_mcp_tools bağı test sırasında izole edilip geri yüklenir.
# ==============================================================================

# Temiz helpers_mcp_tools stub'ı kurar, tablo okuyucularını yükler ve test
# bitince önceki global bağı geri yükler. Dönen değer stub ortamıdır.
.mcptable_install <- function() {
  root <- resolve_repo_root_for_tests()

  had <- exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)
  old <- if (had) get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE) else NULL

  env <- new.env(parent = globalenv())
  # Kaynak yüklemesinin tek katı zorunluluğu: normalize_excel_path mevcut olmalı.
  env$normalize_excel_path <- function(x) x
  assign("helpers_mcp_tools", env, envir = globalenv())

  source(
    file.path(root, "R", "helpers_mcp_table_readers.R"),
    encoding = "UTF-8", local = globalenv()
  )

  withr::defer(
    {
      if (had) {
        assign("helpers_mcp_tools", old, envir = globalenv())
      } else if (exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)) {
        rm("helpers_mcp_tools", envir = globalenv())
      }
    },
    envir = parent.frame()
  )

  get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)
}

# Tek sütun/satırı garanti boşluk-içeren başlıkla kuran yardımcı.
.mcptable_df_named <- function(value, name) {
  df <- data.frame(.tmp = value, stringsAsFactors = FALSE)
  names(df) <- name
  df
}

# ------------------------------------------------------------------------------
# Boş girdi
# ------------------------------------------------------------------------------
testthat::test_that("create_md_table NULL ve 0-satır veride '_Veri yok_' döner", {
  h <- .mcptable_install()
  testthat::expect_identical(h$create_md_table(NULL), "_Veri yok_")
  bos <- data.frame(A = integer(0), B = character(0), stringsAsFactors = FALSE)
  testthat::expect_identical(h$create_md_table(bos), "_Veri yok_")
})

# ------------------------------------------------------------------------------
# Karışık tip biçimlendirme
# ------------------------------------------------------------------------------
testthat::test_that("create_md_table karma tipleri Türkçe sayı biçimiyle Markdown'a çevirir", {
  h <- .mcptable_install()
  df <- data.frame(
    Ad = c("Çağrı", "Ömer"),
    Tutar = c(1234.5, 6),
    Aktif = c(TRUE, FALSE),
    stringsAsFactors = FALSE
  )
  out <- h$create_md_table(df)
  satirlar <- strsplit(out, "\n", fixed = TRUE)[[1]]

  testthat::expect_identical(satirlar[1], "| Ad | Tutar | Aktif |")
  testthat::expect_identical(satirlar[2], "| --- | --- | --- |")
  # Sayısal vektör ondalık hizalanır: 1234.5 -> "1.234,5", 6 -> "6,0"
  testthat::expect_identical(satirlar[3], "| Çağrı | 1.234,5 | TRUE |")
  testthat::expect_identical(satirlar[4], "| Ömer | 6,0 | FALSE |")
})

testthat::test_that("create_md_table büyük sayıları binlik ayraçla, NA'yı 'NA' olarak yazar", {
  h <- .mcptable_install()
  df <- data.frame(X = c(1000000, 2.5, NA))
  out <- h$create_md_table(df)
  satirlar <- strsplit(out, "\n", fixed = TRUE)[[1]]
  testthat::expect_identical(satirlar[3], "| 1.000.000,0 |")
  testthat::expect_identical(satirlar[4], "| 2,5 |")
  testthat::expect_identical(satirlar[5], "| NA |")

  # Tam sayı sütunu: binlik ayraç, ondalık yok
  df_int <- data.frame(N = c(5L, 12345L))
  out_int <- h$create_md_table(df_int)
  satirlar_int <- strsplit(out_int, "\n", fixed = TRUE)[[1]]
  testthat::expect_identical(satirlar_int[3], "| 5 |")
  testthat::expect_identical(satirlar_int[4], "| 12.345 |")
})

testthat::test_that("create_md_table Date/POSIXt sütunlarını karaktere çevirir", {
  h <- .mcptable_install()
  df <- data.frame(
    G = as.Date(c("2024-01-01", "2024-02-03")),
    Z = as.POSIXct(c("2024-03-01 10:00:00", "2024-03-02 11:30:00"), tz = "UTC")
  )
  out <- h$create_md_table(df)
  satirlar <- strsplit(out, "\n", fixed = TRUE)[[1]]
  testthat::expect_identical(satirlar[1], "| G | Z |")
  testthat::expect_identical(satirlar[3], "| 2024-01-01 | 2024-03-01 10:00:00 |")
  testthat::expect_identical(satirlar[4], "| 2024-02-03 | 2024-03-02 11:30:00 |")
})

testthat::test_that("create_md_table factor ve karakter-NA sütunlarını mevcut davranışla yazar", {
  h <- .mcptable_install()
  df_f <- data.frame(K = factor(c("a", "b")), stringsAsFactors = FALSE)
  out_f <- h$create_md_table(df_f)
  testthat::expect_match(out_f, "| a |", fixed = TRUE)
  testthat::expect_match(out_f, "| b |", fixed = TRUE)

  df_na <- data.frame(C = c(NA_character_, "x"), stringsAsFactors = FALSE)
  out_na <- h$create_md_table(df_na)
  satirlar <- strsplit(out_na, "\n", fixed = TRUE)[[1]]
  # as.character(NA) -> NA; paste içinde "NA" olarak görünür
  testthat::expect_identical(satirlar[3], "| NA |")
  testthat::expect_identical(satirlar[4], "| x |")
})

# ------------------------------------------------------------------------------
# Türkçe içerik ve başlık davranışı
# ------------------------------------------------------------------------------
testthat::test_that("create_md_table hücre değerlerinde Türkçe metni ve boşlukları korur", {
  h <- .mcptable_install()
  df <- data.frame(A = c("Çağrı", "Ömer Şule"), stringsAsFactors = FALSE)
  out <- h$create_md_table(df)
  testthat::expect_match(out, "| Çağrı |", fixed = TRUE)
  # Değerlerdeki boşluklar korunur (yalnızca başlıklar make.names ile değişir)
  testthat::expect_match(out, "| Ömer Şule |", fixed = TRUE)
  testthat::expect_identical(enc2utf8(out), out)
})

testthat::test_that("create_md_table ASCII başlıkları aynen, boşluklu başlıkları nokta ile yazar (mevcut davranış)", {
  h <- .mcptable_install()
  # ASCII başlıklar değişmeden kullanılır
  df_ascii <- data.frame(Ad = "x", Yas = 1L, stringsAsFactors = FALSE)
  out_ascii <- h$create_md_table(df_ascii)
  testthat::expect_identical(strsplit(out_ascii, "\n", fixed = TRUE)[[1]][1], "| Ad | Yas |")

  # Karakterizasyon: create_md_table, as.data.frame(lapply(...)) içinde varsayılan
  # check.names=TRUE uyguladığı için başlıktaki boşluk noktaya dönüşür. Bu mevcut
  # bir sınırlamadır; satır değerlerindeki boşluklar etkilenmez.
  df_space <- .mcptable_df_named("deger", "Order Date")
  out_space <- h$create_md_table(df_space)
  testthat::expect_identical(
    strsplit(out_space, "\n", fixed = TRUE)[[1]][1],
    "| Order.Date |"
  )
})
