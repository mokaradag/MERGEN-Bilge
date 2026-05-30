# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-tool-formatters-behavior.R
# Açıklama: LLM araç biçimlendirici saf yardımcılarının davranışsal testleri.
#           get_list_value_any (anahtar öncelikli liste erişimi) ve fast_profile
#           (veri çerçevesi hızlı profili) doğrulanır. DB/LLM/tarayıcı gerekmez.
# ==============================================================================

.llm_tool_formatters_source_once <- function() {
  if (exists("get_list_value_any", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("fast_profile", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_llm_tool_formatters.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

testthat::test_that("get_list_value_any ilk dolu anahtarı döner", {
  .llm_tool_formatters_source_once()

  # İlk eşleşen (dolu) anahtarın değeri.
  testthat::expect_identical(
    get_list_value_any(list(a = 1, b = 2), c("x", "b")),
    2
  )
  testthat::expect_identical(
    get_list_value_any(list(a = "ilk", b = "ikinci"), c("a", "b")),
    "ilk"
  )

  # Eşleşme yoksa NULL.
  testthat::expect_null(get_list_value_any(list(a = 1), c("x", "y")))

  # Güvenli sınır durumları.
  testthat::expect_null(get_list_value_any(NULL, "a"))
  testthat::expect_null(get_list_value_any(list(a = 1), character(0)))
  testthat::expect_null(get_list_value_any("liste degil", "a"))
})

testthat::test_that("fast_profile veri çerçevesinin şekil/tip/eksik/istatistik profilini çıkarır", {
  .llm_tool_formatters_source_once()
  testthat::skip_if_not_installed("data.table")

  df <- data.frame(
    x = c(1, 2, 3, NA),
    g = c("a", "a", "b", "b"),
    stringsAsFactors = FALSE
  )

  prof <- fast_profile(df)

  # Şekil.
  testthat::expect_identical(prof$shape$rows, 4L)
  testthat::expect_identical(prof$shape$cols, 2L)

  # Kolon tipleri.
  testthat::expect_identical(prof$col_types$x, "numeric")
  testthat::expect_identical(prof$col_types$g, "character")

  # Eksik oranı: x sütununda 1/4.
  testthat::expect_equal(prof$missing$x, 0.25)
  testthat::expect_equal(prof$missing$g, 0)

  # Sayısal istatistik: tek sayısal kolon (x), ortalama = mean(1,2,3) = 2.
  testthat::expect_identical(nrow(prof$numeric), 1L)
  testthat::expect_equal(as.numeric(prof$numeric$mean[1]), 2)

  # Kategorik özet: g'nin iki seviyesi, toplam frekans 4.
  testthat::expect_identical(nrow(prof$categories), 2L)
  testthat::expect_identical(sum(prof$categories$n), 4L)
})

# ------------------------------------------------------------------------------
# format_answer_from_tool_results: MCP araç sonucundan kısa Türkçe yanıt üretir
# ------------------------------------------------------------------------------
testthat::test_that("format_answer_from_tool_results boş/eşleşmeyen sonuçlarda NULL döner", {
  .llm_tool_formatters_source_once()
  testthat::expect_null(format_answer_from_tool_results(list()))
  testthat::expect_null(format_answer_from_tool_results(list(NULL)))
  testthat::expect_null(format_answer_from_tool_results(list(list(foo = "bar"))))
})

testthat::test_that("format_answer_from_tool_results sonuc önizlemesindeki sayısal hücreyi kolon adına göre etiketler", {
  .llm_tool_formatters_source_once()
  # avg/mean/average kolonu -> Ortalama.
  testthat::expect_identical(
    format_answer_from_tool_results(list(list(sonuc_onizleme = data.frame(avg_x = 3.14159)))),
    "Ortalama: 3.14"
  )
  # max -> En yuksek deger.
  testthat::expect_identical(
    format_answer_from_tool_results(list(list(result_preview = data.frame(max_x = 99.5)))),
    "En yuksek deger: 99.50"
  )
  # min -> En dusuk deger.
  testthat::expect_identical(
    format_answer_from_tool_results(list(list(result_preview = data.frame(min_x = 1)))),
    "En dusuk deger: 1.00"
  )
  # count/distinct -> Sayi (tam sayı).
  testthat::expect_identical(
    format_answer_from_tool_results(list(list(result_preview = data.frame(count_distinct = 42)))),
    "Sayi: 42"
  )
  # Diğer sayısal kolon -> "kolon: deger".
  testthat::expect_identical(
    format_answer_from_tool_results(list(list(result_preview = data.frame(toplam = 100)))),
    "toplam: 100"
  )
  # Sayısal olmayan ilk hücre -> "kolon: deger".
  testthat::expect_identical(
    format_answer_from_tool_results(list(list(result_preview = data.frame(ad = "Ali", stringsAsFactors = FALSE)))),
    "ad: Ali"
  )
})

testthat::test_that("format_answer_from_tool_results numeric istatistik ve satır/sütun özetini biçimlendirir", {
  .llm_tool_formatters_source_once()
  # tur=numeric -> kolon istatistik özeti.
  testthat::expect_identical(
    format_answer_from_tool_results(list(list(
      tur = "numeric", sutun = "yas",
      ortalama = 30.5, medyan = 29, minimum = 18, maksimum = 65
    ))),
    "yas sutunu — Ortalama: 30.50, Medyan: 29.00, Min: 18.00, Max: 65.00"
  )
  # satir/sutun sayısı -> dosya özeti.
  testthat::expect_identical(
    format_answer_from_tool_results(list(list(satir_sayisi = 10L, sutun_sayisi = 3L))),
    "Dosyada 10 satir ve 3 sutun var."
  )
})
