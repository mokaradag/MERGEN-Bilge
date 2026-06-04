# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-worker-format-tool-result-behavior.R
# Açıklama: R/helpers_llm_worker_tool_results.R llm_worker_format_single_tool_result()
#           fonksiyonunun tüm dönüştürme dallarının davranış testleri. Bu deterministik
#           formatlayıcı ham MCP araç sonucunu LLM ikinci geçiş prompt metnine çevirir.
#           Shiny/DB/ağ GEREKMEZ; mergen_debug_cat no-op olarak stub'lanır.
# ==============================================================================

.source_tool_result_formatter <- function() {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  env$mergen_debug_cat <- function(...) invisible(NULL)
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_llm_worker_tool_results.R"),
    encoding = "UTF-8", local = env
  )
  env
}

testthat::test_that("dataframe önizlemesi markdown tablo ve gerçek-veri başlığı üretir", {
  env <- .source_tool_result_formatter()
  raw <- list(
    `sonuç_önizleme` = data.frame(
      sehir = c("Ankara", "İzmir"),
      adet = c(12L, 7L),
      stringsAsFactors = FALSE
    ),
    sql_effective = "SELECT sehir, adet FROM t"
  )
  out <- env$llm_worker_format_single_tool_result(raw, "sql_query_uploaded_file",
                                                  chart_summary_fn = function(x) "ÖZET")
  testthat::expect_identical(out$tool, "sql_query_uploaded_file")
  testthat::expect_true(grepl("VERİTABANINDAN GELEN GERÇEK VERİ", out$result, fixed = TRUE))
  testthat::expect_true(grepl("| sehir | adet |", out$result, fixed = TRUE))
  testthat::expect_true(grepl("Ankara", out$result, fixed = TRUE))
  testthat::expect_true(grepl("Dönen Toplam Satır: 2", out$result, fixed = TRUE))
})

testthat::test_that("source_table sütunu yoksa uyarı satırı eklenir", {
  env <- .source_tool_result_formatter()
  raw <- list(`sonuç_önizleme` = data.frame(x = 1:2, stringsAsFactors = FALSE))
  out <- env$llm_worker_format_single_tool_result(raw, "t", chart_summary_fn = function(x) "ÖZET")
  testthat::expect_true(grepl("source_table sütununu içermiyor", out$result, fixed = TRUE))
})

testthat::test_that("source_table değerleri varsa listelenir", {
  env <- .source_tool_result_formatter()
  raw <- list(`sonuç_önizleme` = data.frame(
    source_table = c("tabloA", "tabloA", "tabloB"),
    deger = c(1L, 2L, 3L),
    stringsAsFactors = FALSE
  ))
  out <- env$llm_worker_format_single_tool_result(raw, "t", chart_summary_fn = function(x) "ÖZET")
  testthat::expect_true(grepl("source_table değerleri:", out$result, fixed = TRUE))
  testthat::expect_true(grepl("tabloA", out$result, fixed = TRUE))
  testthat::expect_true(grepl("tabloB", out$result, fixed = TRUE))
})

testthat::test_that("boş dataframe için 'boş döndü' uyarısı verir", {
  env <- .source_tool_result_formatter()
  raw <- list(`sonuç_önizleme` = data.frame(x = integer(0), stringsAsFactors = FALSE))
  out <- env$llm_worker_format_single_tool_result(raw, "t", chart_summary_fn = function(x) "ÖZET")
  testthat::expect_true(grepl("Sorgu sonucu boş döndü", out$result, fixed = TRUE))
})

testthat::test_that("grafik sonucu chart_summary_fn çıktısını kullanır", {
  env <- .source_tool_result_formatter()
  cagrildi <- new.env(); cagrildi$n <- 0L
  raw <- list(chart = list(type = "bar"), preview = data.frame(x = 1:3))
  out <- env$llm_worker_format_single_tool_result(
    raw, "analyze_and_visualize",
    chart_summary_fn = function(x) { cagrildi$n <- cagrildi$n + 1L; "GRAFİK ÖZETİ" }
  )
  testthat::expect_identical(out$result, "GRAFİK ÖZETİ")
  testthat::expect_identical(cagrildi$n, 1L)
})

testthat::test_that("__mcp_plot bayrağı da grafik özetine yönlendirir", {
  env <- .source_tool_result_formatter()
  raw <- list(`__mcp_plot` = TRUE)
  out <- env$llm_worker_format_single_tool_result(raw, "t", chart_summary_fn = function(x) "PLOT")
  testthat::expect_identical(out$result, "PLOT")
})

testthat::test_that("liste içindeki result karakteri kullanılır", {
  env <- .source_tool_result_formatter()
  raw <- list(result = c("satır1", "satır2"))
  out <- env$llm_worker_format_single_tool_result(raw, "t", chart_summary_fn = function(x) "X")
  testthat::expect_true(grepl("satır1", out$result, fixed = TRUE))
  testthat::expect_true(grepl("satır2", out$result, fixed = TRUE))
})

testthat::test_that("ham karakter vektörü doğrudan birleştirilir", {
  env <- .source_tool_result_formatter()
  out <- env$llm_worker_format_single_tool_result(c("a", "b"), "t", chart_summary_fn = function(x) "X")
  testthat::expect_identical(out$result, "a\n\nb")
})

testthat::test_that("tanınmayan yapı JSON'a serileştirilir", {
  env <- .source_tool_result_formatter()
  out <- env$llm_worker_format_single_tool_result(list(a = 1, b = 2), "t", chart_summary_fn = function(x) "X")
  parsed <- jsonlite::fromJSON(out$result)
  testthat::expect_identical(parsed$a, 1L)
  testthat::expect_identical(parsed$b, 2L)
})
