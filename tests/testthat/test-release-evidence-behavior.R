# ==============================================================================
# Dosya Yolu: tests/testthat/test-release-evidence-behavior.R
# Açıklama: helpers_release_evidence.R için davranış testleri. VM evidence ve
#           ai-validation artifact'larının en-yeni seçim kuralı, beyaz-listeli
#           alan çıkarımı, bozuk/eksik artifact'larda dürüst not_found dönüşü,
#           log sağlık sayaçları ve secret-safe sınır (ham değer taşınmaması)
#           doğrulanır. Çevrimdışı ve deterministik; gerçek artifact üretilmez.
# ==============================================================================

.releaseEvidenceEnv <- function() {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_release_evidence.R"),
         encoding = "UTF-8", local = env)
  env
}

# Sahte vm-evidence artifact ağacı kurar; en yeni timestamp'ı döndürür
.makeVmEvidenceFixture <- function(repo_root) {
  taban <- file.path(repo_root, "artifacts", "vm-evidence")

  eski <- file.path(taban, "20260101-080000")
  yeni <- file.path(taban, "20260612-211836")
  dir.create(eski, recursive = TRUE, showWarnings = FALSE)
  dir.create(yeni, recursive = TRUE, showWarnings = FALSE)

  eski_icerik <- list(
    gate = "run_vm_evidence_gate",
    generated_at_utc = "2026-01-01T08:00:00Z",
    overall_status = "failed",
    profile_effective = "vm",
    counts = list(passed = 10L, failed = 3L, skipped = 0L),
    steps = list(list(id = "env_config", status = "failed", required = TRUE))
  )
  yeni_icerik <- list(
    gate = "run_vm_evidence_gate",
    generated_at_utc = "2026-06-12T21:18:36Z",
    validation_execution_status = "ran_by_vm_evidence_gate",
    overall_status = "passed",
    profile_effective = "vm",
    secret_policy = "Ham ortam degeri yazilmaz.",
    counts = list(passed = 13L, failed = 0L, skipped = 0L),
    steps = list(
      list(id = "env_config", status = "passed", required = TRUE,
           log_file = "/gizli/yol/olmamali.log",
           notes = list("ham not disari tasinmamali")),
      list(id = "browser_ux_smoke", status = "passed", required = FALSE)
    )
  )

  writeLines(jsonlite::toJSON(eski_icerik, auto_unbox = TRUE),
             file.path(eski, "evidence.json"), useBytes = TRUE)
  writeLines(jsonlite::toJSON(yeni_icerik, auto_unbox = TRUE),
             file.path(yeni, "evidence.json"), useBytes = TRUE)

  file.path(yeni, "evidence.json")
}

testthat::test_that("release_evidence_latest_artifact en yeni timestamp dizinindeki dosyayı seçer", {
  env <- .releaseEvidenceEnv()
  kok <- withr::local_tempdir()

  beklenen <- .makeVmEvidenceFixture(kok)
  taban <- file.path(kok, "artifacts", "vm-evidence")

  testthat::expect_identical(
    env$release_evidence_latest_artifact(taban, "evidence.json"),
    beklenen
  )

  # Hedef dosyası olmayan daha yeni dizin atlanır; dosyalı en yeni dizin kazanır
  bos_yeni <- file.path(taban, "20270101-000000")
  dir.create(bos_yeni, showWarnings = FALSE)
  testthat::expect_identical(
    env$release_evidence_latest_artifact(taban, "evidence.json"),
    beklenen
  )

  # Var olmayan taban dizin güvenli boş döner
  testthat::expect_identical(
    env$release_evidence_latest_artifact(file.path(kok, "yok"), "evidence.json"),
    ""
  )
  testthat::expect_identical(env$release_evidence_latest_artifact(NULL, "x"), "")
})

testthat::test_that("release_evidence_vm_summary geçen kapıyı beyaz-listeli alanlarla özetler", {
  env <- .releaseEvidenceEnv()
  kok <- withr::local_tempdir()
  .makeVmEvidenceFixture(kok)

  ozet <- env$release_evidence_vm_summary(repo_root = kok)

  testthat::expect_true(ozet$found)
  testthat::expect_identical(ozet$status, "passed")
  testthat::expect_identical(ozet$generated_at_utc, "2026-06-12T21:18:36Z")
  testthat::expect_identical(ozet$profile_effective, "vm")
  testthat::expect_identical(ozet$passed, 13L)
  testthat::expect_identical(ozet$failed, 0L)
  testthat::expect_identical(ozet$skipped, 0L)

  # Adımlar yalnızca id/status/required üçlüsüne indirgenir
  testthat::expect_length(ozet$steps, 2L)
  testthat::expect_identical(ozet$steps[[1]]$id, "env_config")
  testthat::expect_identical(ozet$steps[[1]]$status, "passed")
  testthat::expect_true(ozet$steps[[1]]$required)
  testthat::expect_false(ozet$steps[[2]]$required)

  # Secret-safe sınır: log yolu ve ham notlar özet adımlarına TAŞINMAZ
  duz_metin <- paste(utils::capture.output(utils::str(ozet)), collapse = "\n")
  testthat::expect_false(grepl("gizli/yol/olmamali", duz_metin, fixed = TRUE))
  testthat::expect_false(grepl("ham not disari", duz_metin, fixed = TRUE))
})

testthat::test_that("release_evidence_vm_summary artifact yokken veya bozukken dürüst not_found döner", {
  env <- .releaseEvidenceEnv()

  # Artifact dizini hiç yok
  bos_kok <- withr::local_tempdir()
  ozet <- env$release_evidence_vm_summary(repo_root = bos_kok)
  testthat::expect_false(ozet$found)
  testthat::expect_identical(ozet$status, "not_found")
  testthat::expect_identical(ozet$passed, 0L)

  # Bozuk JSON: yine not_found (başarı gibi gösterilmez)
  bozuk_kok <- withr::local_tempdir()
  bozuk_dizin <- file.path(bozuk_kok, "artifacts", "vm-evidence", "20260612-000000")
  dir.create(bozuk_dizin, recursive = TRUE)
  writeLines("{ bozuk json", file.path(bozuk_dizin, "evidence.json"), useBytes = TRUE)

  ozet2 <- env$release_evidence_vm_summary(repo_root = bozuk_kok)
  testthat::expect_false(ozet2$found)
  testthat::expect_identical(ozet2$status, "not_found")
})

testthat::test_that("release_evidence_ai_validation_summary kanıt alanlarını seçer ve sayıları çevirir", {
  env <- .releaseEvidenceEnv()
  kok <- withr::local_tempdir()

  dizin <- file.path(kok, "artifacts", "ai-validation", "20260612-120000")
  dir.create(dizin, recursive = TRUE)
  icerik <- list(
    validation_execution_status = "ran_by_ai_repo_check",
    profile_requested = "cloud-quick",
    profile_effective = "quick",
    failed_steps = 0L,
    skipped_steps = 1L,
    app_source_smoke_status = "skipped",
    shiny_boot_smoke_status = "not_requested",
    browser_smoke_status = "not_requested",
    fazladan_ham_alan = "asla taşınmamalı"
  )
  writeLines(jsonlite::toJSON(icerik, auto_unbox = TRUE),
             file.path(dizin, "summary.json"), useBytes = TRUE)

  ozet <- env$release_evidence_ai_validation_summary(repo_root = kok)

  testthat::expect_true(ozet$found)
  testthat::expect_identical(ozet$validation_execution_status, "ran_by_ai_repo_check")
  testthat::expect_identical(ozet$profile_requested, "cloud-quick")
  testthat::expect_identical(ozet$profile_effective, "quick")
  testthat::expect_identical(ozet$failed_steps, 0L)
  testthat::expect_identical(ozet$skipped_steps, 1L)
  testthat::expect_identical(ozet$app_source_smoke_status, "skipped")

  # Beyaz-liste dışındaki alan özet yapısında bulunmaz
  testthat::expect_false("fazladan_ham_alan" %in% names(ozet))

  # Artifact yoksa not_found + NA sayılar
  bos <- env$release_evidence_ai_validation_summary(repo_root = withr::local_tempdir())
  testthat::expect_false(bos$found)
  testthat::expect_identical(bos$validation_execution_status, "not_found")
  testthat::expect_true(is.na(bos$failed_steps))
})

testthat::test_that("release_evidence_log_health sınırlı pencerede ERROR/WARN sayar, içerik taşımaz", {
  env <- .releaseEvidenceEnv()
  log_dir <- withr::local_tempdir()
  log_yolu <- file.path(log_dir, sprintf("mergen_%s.log", format(Sys.Date(), "%Y%m%d")))

  satirlar <- c(
    "INFO [2026-06-12 10:00:00] normal akış",
    "WARN [2026-06-12 10:01:00] uyarı bir",
    "ERROR [2026-06-12 10:02:00] hata bir gizli_ipucu_tasinmamali",
    "INFO [2026-06-12 10:03:00] normal akış iki",
    "ERROR [2026-06-12 10:04:30] hata iki",
    "WARN [2026-06-12 10:05:00] uyarı iki"
  )
  writeLines(satirlar, log_yolu, useBytes = TRUE)

  ozet <- env$release_evidence_log_health(log_dir = log_dir)

  testthat::expect_true(ozet$found)
  testthat::expect_identical(ozet$error_count, 2L)
  testthat::expect_identical(ozet$warn_count, 2L)
  testthat::expect_identical(ozet$window_lines, 6L)
  # Son hatanın yalnızca zaman öneki raporlanır
  testthat::expect_identical(ozet$last_error_at, "2026-06-12 10:04:30")

  # Log satır içeriği özet üzerinden dışarı taşınmaz
  duz_metin <- paste(utils::capture.output(utils::str(ozet)), collapse = "\n")
  testthat::expect_false(grepl("gizli_ipucu_tasinmamali", duz_metin, fixed = TRUE))

  # Pencere sınırı: yalnızca son N satır incelenir
  dar <- env$release_evidence_log_health(log_dir = log_dir, max_lines = 2L)
  testthat::expect_identical(dar$window_lines, 2L)
  testthat::expect_identical(dar$error_count, 1L)

  # Bugünün dosyası yoksa güvenli sıfır özeti
  bos <- env$release_evidence_log_health(log_dir = withr::local_tempdir())
  testthat::expect_false(bos$found)
  testthat::expect_identical(bos$error_count, 0L)
})

testthat::test_that("release_evidence_overview alt özetleri ve kanıt sınırı notunu birleştirir", {
  env <- .releaseEvidenceEnv()
  kok <- withr::local_tempdir()
  .makeVmEvidenceFixture(kok)

  log_dir <- withr::local_tempdir()

  genel <- env$release_evidence_overview(repo_root = kok, log_dir = log_dir)

  testthat::expect_true(all(c("generated_at", "vm_evidence", "ai_validation",
                              "log_health", "proof_note") %in% names(genel)))
  testthat::expect_true(genel$vm_evidence$found)
  testthat::expect_false(genel$ai_validation$found)
  testthat::expect_false(genel$log_health$found)

  # Kanıt sınırı dürüstlüğü: SKIP'in kanıt olmadığı notu her özette taşınır
  testthat::expect_true(grepl("kanıt değildir", genel$proof_note, fixed = TRUE))
})
