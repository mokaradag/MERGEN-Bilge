# ==============================================================================
# Dosya Yolu: tests/testthat/test-release-evidence-ai-latency-behavior.R
# Açıklama: Release kanıt okuyucusunun YENİ secret-safe AI çağrı istek-süresi
#           (latency) özetini doğrular: release_evidence_summarize_ai_call_latency
#           (saf; "AI Call: ... duration=<sn>s ... success=<TRUE/FALSE>" satırından
#           yalnızca sayısal süre + başarı/başarısızlık sayar, kullanıcı/model
#           içeriği taşımaz), release_evidence_log_health entegrasyonu
#           (ai_call_latency alanı) ve module_health_release.R UI yüzeyi
#           (.health_release_ai_latency + health_release_ui). Çevrimdışı,
#           deterministik; gerçek artifact/DB/ağ yoktur.
# ==============================================================================

suppressMessages(library(shiny))

# Türkçe yorum: Saf okuyucu + sağlık biçimlendiriciler + release UI tek ortamda.
.aiLatencyEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "helpers_health_formatters.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_release_evidence.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "module_health_release.R"), encoding = "UTF-8", local = env)
  env
}

test_that("release_evidence_summarize_ai_call_latency boş/NULL girdide boş liste döner", {
  env <- .aiLatencyEnv()
  expect_identical(env$release_evidence_summarize_ai_call_latency(NULL), list())
  expect_identical(env$release_evidence_summarize_ai_call_latency(character(0)), list())
})

test_that("release_evidence_summarize_ai_call_latency süreleri ve başarı/başarısızlığı sayar", {
  env <- .aiLatencyEnv()
  satirlar <- c(
    "INFO [2026-06-14 10:00:00] AI Call: user=42, model=m1, duration=1s, success=TRUE, tokens=100",
    "INFO [2026-06-14 10:01:00] AI Call: user=42, model=m1, duration=3s, success=TRUE, tokens=200",
    "INFO [2026-06-14 10:02:00] AI Call: user=7, model=m2, duration=5s, success=FALSE, tokens=0"
  )
  res <- env$release_evidence_summarize_ai_call_latency(satirlar)
  expect_identical(res$count, 3L)
  expect_identical(res$min, 1)
  expect_identical(res$median, 3)
  expect_identical(res$mean, 3)
  expect_identical(res$max, 5)
  expect_identical(res$success_count, 2L)
  expect_identical(res$fail_count, 1L)
})

test_that("release_evidence_summarize_ai_call_latency ondalık süreleri yuvarlar", {
  env <- .aiLatencyEnv()
  satirlar <- c(
    "INFO [t] AI Call: user=1, model=m, duration=2.5s, success=TRUE",
    "INFO [t] AI Call: user=1, model=m, duration=3.7s, success=TRUE"
  )
  res <- env$release_evidence_summarize_ai_call_latency(satirlar)
  expect_identical(res$count, 2L)
  expect_identical(res$min, 2.5)
  expect_identical(res$max, 3.7)
  expect_identical(res$mean, 3.1)
})

test_that("release_evidence_summarize_ai_call_latency süre içermeyen AI Call satırlarını yok sayar", {
  env <- .aiLatencyEnv()
  satirlar <- c(
    "INFO [t] AI Call: user=1, model=m, success=TRUE",  # duration yok
    "INFO [t] başka bir log satırı"
  )
  expect_identical(env$release_evidence_summarize_ai_call_latency(satirlar), list())
})

test_that("release_evidence_summarize_ai_call_latency kullanıcı/model içeriğini taşımaz (secret-safe)", {
  env <- .aiLatencyEnv()
  satirlar <- c(
    "INFO [t] AI Call: user=gizli_kullanici_42, model=cok_gizli_model, duration=2s, success=TRUE"
  )
  res <- env$release_evidence_summarize_ai_call_latency(satirlar)
  duz <- paste(utils::capture.output(utils::str(res)), collapse = "\n")
  # Türkçe yorum: yalnızca sayısal özet; kullanıcı/model kimliği asla taşınmaz
  expect_false(grepl("gizli_kullanici_42", duz, fixed = TRUE))
  expect_false(grepl("cok_gizli_model", duz, fixed = TRUE))
  expect_identical(res$count, 1L)
})

test_that("release_evidence_log_health çıktısı ai_call_latency alanını içerir", {
  env <- .aiLatencyEnv()
  log_dir <- withr::local_tempdir()
  log_yolu <- file.path(log_dir, sprintf("mergen_%s.log", format(Sys.Date(), "%Y%m%d")))
  writeLines(c(
    "INFO [2026-06-14 09:00:00] normal",
    "INFO [2026-06-14 09:01:00] AI Call: user=1, model=m1, duration=2s, success=TRUE, tokens=50",
    "INFO [2026-06-14 09:02:00] AI Call: user=1, model=m1, duration=4s, success=TRUE, tokens=60"
  ), log_yolu, useBytes = TRUE)

  ozet <- env$release_evidence_log_health(log_dir = log_dir)
  expect_true(ozet$found)
  expect_true(is.list(ozet$ai_call_latency))
  expect_identical(ozet$ai_call_latency$count, 2L)
  expect_identical(ozet$ai_call_latency$median, 3)
  expect_identical(ozet$ai_call_latency$success_count, 2L)
})

test_that("release_evidence_log_health AI Call yoksa ai_call_latency boş kalır", {
  env <- .aiLatencyEnv()
  log_dir <- withr::local_tempdir()
  log_yolu <- file.path(log_dir, sprintf("mergen_%s.log", format(Sys.Date(), "%Y%m%d")))
  writeLines(c("INFO [t] normal", "WARN [t] uyarı"), log_yolu, useBytes = TRUE)
  ozet <- env$release_evidence_log_health(log_dir = log_dir)
  expect_identical(ozet$ai_call_latency, list())
})

test_that(".health_release_ai_latency boş alanda NULL, doluda özet listesi üretir", {
  env <- .aiLatencyEnv()
  expect_null(env$.health_release_ai_latency(NULL))
  expect_null(env$.health_release_ai_latency(list()))

  ui <- env$.health_release_ai_latency(list(
    count = 5L, min = 1, median = 2, mean = 2.4, max = 9,
    success_count = 4L, fail_count = 1L
  ))
  html <- paste(as.character(ui), collapse = "\n")
  expect_true(grepl("AI çağrı gecikmesi", html, fixed = TRUE))
  expect_true(grepl("health-release-ai-latency", html, fixed = TRUE))
  expect_true(grepl("Çağrı sayısı", html, fixed = TRUE))
})

test_that("health_release_ui log kartında AI latency özetini gösterir (alan varsa)", {
  env <- .aiLatencyEnv()
  overview <- list(
    generated_at = "2026-06-14 09:00:00",
    vm_evidence = list(found = FALSE, status = "not_found", steps = list(),
                       passed = 0L, failed = 0L, skipped = 0L),
    ai_validation = list(found = FALSE),
    log_health = list(
      found = TRUE, window_lines = 100L, error_count = 0L, warn_count = 0L,
      last_error_at = "",
      ai_call_latency = list(count = 8L, min = 0.5, median = 2, mean = 2.2,
                             max = 6, success_count = 7L, fail_count = 1L)
    ),
    proof_note = "SKIP kanıt değildir."
  )
  ui <- env$health_release_ui(overview)
  html <- paste(as.character(ui), collapse = "\n")
  expect_true(grepl("AI çağrı gecikmesi", html, fixed = TRUE))
  expect_true(grepl("health-release-ai-latency", html, fixed = TRUE))
})

test_that("health_release_ui AI latency yoksa eski davranışı korur (regresyon yok)", {
  env <- .aiLatencyEnv()
  overview <- list(
    generated_at = "2026-06-14 09:00:00",
    vm_evidence = list(found = FALSE, status = "not_found", steps = list(),
                       passed = 0L, failed = 0L, skipped = 0L),
    ai_validation = list(found = FALSE),
    log_health = list(found = TRUE, window_lines = 10L, error_count = 0L,
                      warn_count = 0L, last_error_at = ""),
    proof_note = "not"
  )
  ui <- env$health_release_ui(overview)
  html <- paste(as.character(ui), collapse = "\n")
  # Türkçe yorum: ai_call_latency alanı yok -> latency bloğu render edilmez
  expect_false(grepl("AI çağrı gecikmesi", html, fixed = TRUE))
  # Ama temel log kartı yine görünür
  expect_true(grepl("ERROR sayısı", html, fixed = TRUE))
})
