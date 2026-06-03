# ==============================================================================
# Dosya Yolu: tests/testthat/test-health-runtime-ui-behavior.R
# Açıklama: R/module_health_runtime.R Çalışma Zamanı sekmesi yardımcılarının
#           DAVRANIŞSAL testleri. Bu dosya daha önce hiçbir test tarafından
#           çağrılmıyordu.
#
#           Kapsananlar:
#           - health_pick_int(): vektörden güvenli tamsayı seçimi + fallback.
#           - health_parse_worker_counts(): worker metnindeki sayıları
#             (toplam/aktif/kuyruk) güvenli ayrıştırma ve sınırlama.
#           - health_worker_core_visual(): çekirdek görselleştirme yapısı.
#           - health_runtime_ui(): çalışma zamanı sekmesi UI yapısı.
#
#           Yardımcılar helpers_health_formatters.R'ye bağımlı olduğundan o dosya
#           da izole ortama yüklenir. Ağ/DB/LLM GEREKMEZ.
# ==============================================================================

.source_health_runtime_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  source(file.path(repo_root, "R", "helpers_health_formatters.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "module_health_runtime.R"), encoding = "UTF-8", local = env)
  env
}

# Test için örnek checks data.frame'i üretir (health_result satırlarını birleştirir).
.health_runtime_checks <- function(env, worker_value = "4 / 2 / 1") {
  do.call(rbind, list(
    env$health_result("runtime.workers", "İşçi Havuzu", "ok", worker_value),
    env$health_result("runtime.memory", "Bellek", "ok", "512 MB"),
    env$health_result("runtime.sessions", "Oturum", "ok", "3"),
    env$health_result("runtime.r_version", "R Sürümü", "ok", "4.6.0"),
    env$health_result("runtime.packages", "Paketler", "warning", "12/13"),
    env$health_result("runtime.uptime", "Çalışma Süresi", "ok", "2s 10dk"),
    env$health_result("runtime.os", "İşletim Sistemi", "ok", "Linux")
  ))
}

# ------------------------------------------------------------------------------
# health_pick_int
# ------------------------------------------------------------------------------
testthat::test_that("health_pick_int geçerli indeksten tamsayı seçer", {
  env <- .source_health_runtime_for_test()
  testthat::expect_identical(env$health_pick_int(c(4, 2, 1), 1L, 99L), 4L)
  testthat::expect_identical(env$health_pick_int(c(4, 2, 1), 3L, 99L), 1L)
})

testthat::test_that("health_pick_int eksik/NA/sayısal-olmayan için fallback döndürür", {
  env <- .source_health_runtime_for_test()
  testthat::expect_identical(env$health_pick_int(integer(0), 1L, 99L), 99L)
  testthat::expect_identical(env$health_pick_int(c(NA), 1L, 7L), 7L)
  # "x" -> as.integer NA -> fallback (uyarı bastırılır)
  testthat::expect_identical(env$health_pick_int(c("x"), 1L, 5L), 5L)
})

# ------------------------------------------------------------------------------
# health_parse_worker_counts
# ------------------------------------------------------------------------------
testthat::test_that("health_parse_worker_counts üç sayıyı toplam/aktif/kuyruk olarak ayrıştırır", {
  env <- .source_health_runtime_for_test()
  r <- env$health_parse_worker_counts("4 / 2 / 1")
  testthat::expect_identical(r$total, 4L)
  testthat::expect_identical(r$active, 2L)
  testthat::expect_identical(r$queued, 1L)
})

testthat::test_that("health_parse_worker_counts Türkçe açıklamalı metinden sayıları çıkarır", {
  env <- .source_health_runtime_for_test()
  r <- env$health_parse_worker_counts("8 işçi, 3 aktif, 0 kuyruk")
  testthat::expect_identical(r$total, 8L)
  testthat::expect_identical(r$active, 3L)
  testthat::expect_identical(r$queued, 0L)
})

testthat::test_that("health_parse_worker_counts aktif değeri toplamla sınırlar", {
  env <- .source_health_runtime_for_test()
  # aktif (10) toplamdan (4) büyük olamaz; min(active, total) = 4.
  r <- env$health_parse_worker_counts("4 / 10 / 0")
  testthat::expect_identical(r$total, 4L)
  testthat::expect_identical(r$active, 4L)
})

testthat::test_that("health_parse_worker_counts boş/NULL metinde güvenli varsayılanlar üretir", {
  env <- .source_health_runtime_for_test()
  r_bos <- env$health_parse_worker_counts("")
  # total en az 1 (çekirdek sayısı fallback'i), aktif 0, kuyruk 0.
  testthat::expect_true(r_bos$total >= 1L)
  testthat::expect_identical(r_bos$active, 0L)
  testthat::expect_identical(r_bos$queued, 0L)

  r_null <- env$health_parse_worker_counts(NULL)
  testthat::expect_true(r_null$total >= 1L)
  testthat::expect_identical(r_null$active, 0L)
})

testthat::test_that("health_parse_worker_counts tek sayıyı toplam kabul eder", {
  env <- .source_health_runtime_for_test()
  r <- env$health_parse_worker_counts("5")
  testthat::expect_identical(r$total, 5L)
  testthat::expect_identical(r$active, 0L)
  testthat::expect_identical(r$queued, 0L)
})

# ------------------------------------------------------------------------------
# health_worker_core_visual
# ------------------------------------------------------------------------------
testthat::test_that("health_worker_core_visual kullanım yüzdesini ve çekirdek düğümlerini üretir", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .source_health_runtime_for_test()

  html <- paste(as.character(env$health_worker_core_visual("4 / 2 / 1")), collapse = "\n")
  testthat::expect_true(grepl("health-worker-visual-card", html, fixed = TRUE))
  # 2/4 = %50 kullanım.
  testthat::expect_true(grepl("50%", html, fixed = TRUE))
  # Lejant: Aktif 2, Boşta 2 (4-2), Kuyruk 1.
  testthat::expect_true(grepl("Aktif: 2", html, fixed = TRUE))
  testthat::expect_true(grepl("Boşta: 2", html, fixed = TRUE))
  testthat::expect_true(grepl("Kuyruk: 1", html, fixed = TRUE))
  # 4 çekirdek düğümü; 2'si aktif olmalı.
  testthat::expect_identical(length(gregexpr("health-core-node", html, fixed = TRUE)[[1]]), 4L)
  testthat::expect_identical(length(gregexpr("health-core-node active", html, fixed = TRUE)[[1]]), 2L)
})

# ------------------------------------------------------------------------------
# health_runtime_ui
# ------------------------------------------------------------------------------
testthat::test_that("health_runtime_ui çalışma zamanı metriklerini ve işçi izleyici kartını üretir", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .source_health_runtime_for_test()

  checks <- .health_runtime_checks(env)
  html <- paste(as.character(env$health_runtime_ui(checks)), collapse = "\n")

  testthat::expect_true(grepl("İşçi İzleyici", html, fixed = TRUE))
  testthat::expect_true(grepl("Çalışma Zamanı Detayları", html, fixed = TRUE))
  # Bellek metrik değeri tablodan gelir.
  testthat::expect_true(grepl("512 MB", html, fixed = TRUE))
  # Worker görselleştirme yüzdesi runtime.workers değerinden (2/4=%50) üretilmeli.
  testthat::expect_true(grepl("50%", html, fixed = TRUE))
})

testthat::test_that("health_runtime_ui worker_html sağlanmazsa güvenli yer tutucu gösterir", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .source_health_runtime_for_test()

  checks <- .health_runtime_checks(env)
  html <- paste(as.character(env$health_runtime_ui(checks, worker_html = NULL)), collapse = "\n")
  testthat::expect_true(grepl("Worker HTML bilgisi alınamadı.", html, fixed = TRUE))
})
