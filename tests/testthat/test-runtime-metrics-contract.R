# ==============================================================================
# Dosya Yolu: tests/testthat/test-runtime-metrics-contract.R
# Açıklama: Süreç-içi, sır-güvenli çalışma-zamanı metrik yardımcılarının
#           (R/helpers_runtime_metrics.R) davranış/sözleşme testleri.
#
# Bu testler app.R'yi BAŞLATMAZ; saf yardımcı dosya tek başına source edilir.
# ==============================================================================

testthat::local_edition(3)

source("../../R/helpers_runtime_metrics.R")

test_that("sayaç artışı birikir ve okunur", {
  mergen_runtime_metrics_reset()
  expect_equal(mergen_runtime_metric_get("yok"), 0)

  mergen_runtime_metric_inc("a")
  mergen_runtime_metric_inc("a", 4)
  expect_equal(mergen_runtime_metric_get("a"), 5)

  snap <- mergen_runtime_metrics_snapshot()
  expect_equal(snap$counters$a, 5)
  expect_true(is.numeric(snap$uptime_sec))
  expect_gte(snap$uptime_sec, 0)
})

test_that("gauge ayarlanir ve son deger okunur", {
  mergen_runtime_metrics_reset()
  mergen_runtime_metric_set_gauge("active", 3)
  mergen_runtime_metric_set_gauge("active", 7)
  expect_equal(mergen_runtime_metric_get("active"), 7)
  expect_equal(mergen_runtime_metrics_snapshot()$gauges$active, 7)
})

test_that("gecersiz/NA artis veya gauge guvenli sekilde isleniyor", {
  mergen_runtime_metrics_reset()
  expect_silent(mergen_runtime_metric_inc("x", NA))
  expect_equal(mergen_runtime_metric_get("x"), 1)  # NA artis -> 1 varsayilir
  expect_silent(mergen_runtime_metric_set_gauge("g", NA))
  expect_equal(mergen_runtime_metric_get("g"), 0)
})

test_that("metrik adlari ASCII'ye sikistirilir (sir/log gurultusu onlemi)", {
  mergen_runtime_metrics_reset()
  mergen_runtime_metric_inc(" tehlikeli ad/with spaces;and=symbols ")
  keys <- names(mergen_runtime_metrics_snapshot()$counters)
  expect_length(keys, 1L)
  expect_false(grepl("[^A-Za-z0-9_.-]", keys[[1]]))
})

test_that("reset sayaclari/gauge'lari temizler", {
  mergen_runtime_metric_inc("z")
  mergen_runtime_metric_set_gauge("zg", 9)
  mergen_runtime_metrics_reset()
  snap <- mergen_runtime_metrics_snapshot()
  expect_length(snap$counters, 0L)
  expect_length(snap$gauges, 0L)
})

test_that("anlik goruntu yalnizca sayisal alan icerir (sir-guvenli)", {
  mergen_runtime_metrics_reset()
  mergen_runtime_metric_inc("api_key", 2)        # ad sir gibi gorunse bile deger sayisaldir
  snap <- mergen_runtime_metrics_snapshot()
  vals <- unlist(c(snap$counters, snap$gauges), use.names = FALSE)
  expect_true(all(is.numeric(vals)))
})
