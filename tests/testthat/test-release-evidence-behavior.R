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

# Sahte post-deploy-smoke artifact ağacı kurar (eski + yeni); en yeniyi döndürür.
.makePostDeploySmokeFixture <- function(repo_root) {
  taban <- file.path(repo_root, "artifacts", "post-deploy-smoke")

  eski <- file.path(taban, "20260101-080000")
  yeni <- file.path(taban, "20260624-100000")
  dir.create(eski, recursive = TRUE, showWarnings = FALSE)
  dir.create(yeni, recursive = TRUE, showWarnings = FALSE)

  eski_icerik <- list(
    gate = "run_post_deploy_smoke",
    generated_at_utc = "2026-01-01T08:00:00Z",
    overall = "fail",
    should_fail = TRUE,
    total = 3L,
    counts = list(ok = 2L, critical = 1L),
    critical_failures = list("db.primary")
  )
  yeni_icerik <- list(
    gate = "run_post_deploy_smoke",
    generated_at_utc = "2026-06-24T10:00:00Z",
    validation_execution_status = "ran_by_post_deploy_smoke",
    overall = "degraded",
    should_fail = FALSE,
    reason = "ok",
    total = 4L,
    counts = list(ok = 3L, warning = 1L),
    failing = list(),
    critical_failures = list(),
    evaluated_at = "2026-06-24T13:00:00+0300",
    does_prove = "anlık sağlık",
    does_not_prove = "yük/eşzamanlılık değil"
  )

  writeLines(jsonlite::toJSON(eski_icerik, auto_unbox = TRUE),
             file.path(eski, "post-deploy-smoke.json"), useBytes = TRUE)
  writeLines(jsonlite::toJSON(yeni_icerik, auto_unbox = TRUE),
             file.path(yeni, "post-deploy-smoke.json"), useBytes = TRUE)

  file.path(yeni, "post-deploy-smoke.json")
}

testthat::test_that("release_evidence_post_deploy_smoke_summary en yeni artifact'i beyaz-listeli alanlarla okur", {
  env <- .releaseEvidenceEnv()
  kok <- withr::local_tempdir()
  .makePostDeploySmokeFixture(kok)

  ozet <- env$release_evidence_post_deploy_smoke_summary(repo_root = kok)

  testthat::expect_true(ozet$found)
  testthat::expect_identical(ozet$status, "degraded")
  testthat::expect_false(ozet$should_fail)
  testthat::expect_identical(ozet$total, 4L)
  testthat::expect_identical(ozet$pass_count, 3L)
  testthat::expect_identical(ozet$warn_count, 1L)
  testthat::expect_identical(ozet$critical_count, 0L)
  testthat::expect_identical(ozet$selected_run, "20260624-100000")
  testthat::expect_identical(ozet$generated_at_utc, "2026-06-24T10:00:00Z")
  testthat::expect_identical(ozet$critical_failures, character(0))

  # En yeniden eskiye iki koşu listelenir (operatör koşu görünürlüğü).
  testthat::expect_identical(ozet$available_runs,
                             c("20260624-100000", "20260101-080000"))
})

testthat::test_that("release_evidence_post_deploy_smoke_summary eski koşunun kritik bozulmasını da çözer", {
  env <- .releaseEvidenceEnv()
  kok <- withr::local_tempdir()
  .makePostDeploySmokeFixture(kok)

  ozet <- env$release_evidence_post_deploy_smoke_summary(
    repo_root = kok, run_id = "20260101-080000"
  )

  testthat::expect_true(ozet$found)
  testthat::expect_identical(ozet$status, "fail")
  testthat::expect_true(ozet$should_fail)
  testthat::expect_identical(ozet$critical_count, 1L)
  testthat::expect_true("db.primary" %in% ozet$critical_failures)
})

testthat::test_that("release_evidence_post_deploy_smoke_summary artifact yoksa dürüstçe not_found döner", {
  env <- .releaseEvidenceEnv()
  bos <- env$release_evidence_post_deploy_smoke_summary(repo_root = withr::local_tempdir())
  testthat::expect_false(bos$found)
  testthat::expect_identical(bos$status, "not_found")
  testthat::expect_identical(bos$available_runs, character(0))
  testthat::expect_identical(bos$critical_failures, character(0))
})

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

testthat::test_that("release_evidence_list_runs hedef dosyalı koşuları en yeniden eskiye listeler", {
  env <- .releaseEvidenceEnv()
  kok <- withr::local_tempdir()
  .makeVmEvidenceFixture(kok)
  taban <- file.path(kok, "artifacts", "vm-evidence")

  # Hedef dosyası olmayan daha yeni dizin listelenmemeli
  dir.create(file.path(taban, "20270101-000000"), showWarnings = FALSE)

  kosular <- env$release_evidence_list_runs(taban, "evidence.json")
  testthat::expect_identical(kosular, c("20260612-211836", "20260101-080000"))

  # Var olmayan/boş taban güvenli boş döner
  testthat::expect_identical(
    env$release_evidence_list_runs(file.path(kok, "yok"), "evidence.json"), character(0))
  testthat::expect_identical(env$release_evidence_list_runs(NULL, "evidence.json"), character(0))
})

testthat::test_that(".release_evidence_safe_run_id yalnızca güvenli zaman damgası adını kabul eder", {
  env <- .releaseEvidenceEnv()
  testthat::expect_identical(env$.release_evidence_safe_run_id("20260613-133648"), "20260613-133648")
  testthat::expect_identical(env$.release_evidence_safe_run_id("../gizli"), "")
  testthat::expect_identical(env$.release_evidence_safe_run_id("a/b"), "")
  testthat::expect_identical(env$.release_evidence_safe_run_id("x y"), "")
  testthat::expect_identical(env$.release_evidence_safe_run_id(NULL), "")
  testthat::expect_identical(env$.release_evidence_safe_run_id(NA_character_), "")
})

testthat::test_that("release_evidence_artifact_for_run run_id seçer, güvensiz/eksikte en yeniye düşer", {
  env <- .releaseEvidenceEnv()
  kok <- withr::local_tempdir()
  yeni <- .makeVmEvidenceFixture(kok)
  taban <- file.path(kok, "artifacts", "vm-evidence")
  eski <- file.path(taban, "20260101-080000", "evidence.json")

  # Geçerli run_id o koşuyu seçer
  testthat::expect_identical(
    env$release_evidence_artifact_for_run(taban, "20260101-080000", "evidence.json"), eski)
  # run_id NULL -> en yeni koşu
  testthat::expect_identical(
    env$release_evidence_artifact_for_run(taban, NULL, "evidence.json"), yeni)
  # Path traversal / güvensiz run_id reddedilir, en yeniye düşer
  testthat::expect_identical(
    env$release_evidence_artifact_for_run(taban, "../../etc", "evidence.json"), yeni)
  # Var olmayan run_id en yeniye düşer
  testthat::expect_identical(
    env$release_evidence_artifact_for_run(taban, "29991231-000000", "evidence.json"), yeni)
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

testthat::test_that("release_evidence_vm_summary koşu listesini verir ve run_id ile eski koşuyu seçer", {
  env <- .releaseEvidenceEnv()
  kok <- withr::local_tempdir()
  .makeVmEvidenceFixture(kok)

  # Varsayılan: en yeni koşu seçili; tüm koşular en yeniden eskiye
  ozet <- env$release_evidence_vm_summary(repo_root = kok)
  testthat::expect_identical(ozet$available_runs, c("20260612-211836", "20260101-080000"))
  testthat::expect_identical(ozet$selected_run, "20260612-211836")
  testthat::expect_identical(ozet$status, "passed")

  # Belirli (eski) koşu seçilince o koşunun özeti döner
  eski <- env$release_evidence_vm_summary(repo_root = kok, run_id = "20260101-080000")
  testthat::expect_true(eski$found)
  testthat::expect_identical(eski$selected_run, "20260101-080000")
  testthat::expect_identical(eski$status, "failed")
  testthat::expect_identical(eski$passed, 10L)
  testthat::expect_identical(eski$failed, 3L)

  # Güvensiz run_id en yeniye düşer (path traversal korunur)
  guvenli <- env$release_evidence_vm_summary(repo_root = kok, run_id = "../../escape")
  testthat::expect_identical(guvenli$selected_run, "20260612-211836")

  # Artifact yokken bile mevcut koşular boş listeyle güvenle döner
  bos_kok <- withr::local_tempdir()
  bos_ozet <- env$release_evidence_vm_summary(repo_root = bos_kok)
  testthat::expect_false(bos_ozet$found)
  testthat::expect_identical(bos_ozet$available_runs, character(0))
  testthat::expect_identical(bos_ozet$selected_run, "")
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

# Kök neden regresyonu: Windows VM logları ANSI/WINDOWS-1254 bayt içerebilir.
# Eski readLines(encoding="UTF-8") yolu geçersiz çok baytlı dizgede regexec ile
# "input string is invalid" hatası fırlatır ve TÜM Doğrulama Kanıtı sekmesini
# boşa düşürürdü. Byte-safe okuma bunu önlemeli; sayımlar yine doğru olmalı.
testthat::test_that("release_evidence_log_health geçersiz UTF-8 (ANSI) log içeriğinde durmaz", {
  env <- .releaseEvidenceEnv()
  log_dir <- withr::local_tempdir()
  log_yolu <- file.path(log_dir, sprintf("mergen_%s.log", format(Sys.Date(), "%Y%m%d")))

  # WINDOWS-1254 tek-bayt Türkçe karakterler (geçersiz UTF-8): 0xFD=ı, 0xFE=ş
  con <- file(log_yolu, open = "wb")
  satir1 <- c(
    charToRaw("ERROR [2026-06-13 18:19:56] [INDEX] Error in INDEX_RESTORE: yedek al"),
    as.raw(0xFD), charToRaw("nd"), as.raw(0xFD), charToRaw(" bo"), as.raw(0xFE),
    as.raw(0x0A)
  )
  satir2 <- c(charToRaw("WARN [2026-06-13 18:20:00] bir uyar"), as.raw(0xFD), as.raw(0x0A))
  writeBin(c(satir1, satir2), con)
  close(con)

  ozet <- env$release_evidence_log_health(log_dir = log_dir)
  testthat::expect_true(ozet$found)
  testthat::expect_identical(ozet$error_count, 1L)
  testthat::expect_identical(ozet$warn_count, 1L)
  testthat::expect_identical(ozet$last_error_at, "2026-06-13 18:19:56")
  # Güvenli bağlam etiketi yine de çıkarılır
  testthat::expect_identical(ozet$error_contexts[[1]]$context, "INDEX_RESTORE")

  # Ve birleşik overview da durmadan üretilir (VM kanıtı + log birlikte)
  kok <- withr::local_tempdir()
  .makeVmEvidenceFixture(kok)
  genel <- env$release_evidence_overview(repo_root = kok, log_dir = log_dir)
  testthat::expect_true(genel$vm_evidence$found)
  testthat::expect_true(genel$log_health$found)
  testthat::expect_identical(genel$log_health$error_count, 1L)
})

testthat::test_that("release_evidence_artifact_root repo kökü altındaki artifacts dizinini verir", {
  env <- .releaseEvidenceEnv()

  # "/repo/kok" gibi sabit yol Windows'ta MUTLAK değildir (sürücü harfi/UNC yok),
  # bu yüzden normalizePath onu çalışma dizinine göre çözer (UNC öneki eklenir).
  # OS-bağımsız gerçek mutlak yol için tempdir kullanılır; beklenen değer üretim
  # fonksiyonuyla aynı normalize edilmiş biçimde hesaplanır.
  kok <- withr::local_tempdir()
  beklenen <- file.path(normalizePath(kok, winslash = "/", mustWork = FALSE), "artifacts")
  testthat::expect_identical(env$release_evidence_artifact_root(kok), beklenen)
  testthat::expect_identical(basename(env$release_evidence_artifact_root(kok)), "artifacts")

  # Argümansız çağrı çözümlenen repo kökü altındaki artifacts dizinini döndürür
  testthat::expect_identical(
    env$release_evidence_artifact_root(),
    file.path(env$release_evidence_resolve_repo_root(), "artifacts")
  )
})

testthat::test_that("release_evidence_read_json geçerli JSON'u okur, bozuk/eksikte NULL döner", {
  env <- .releaseEvidenceEnv()
  dizin <- withr::local_tempdir()

  # Geçersiz/eksik yollar güvenle NULL döner (durmaz)
  testthat::expect_null(env$release_evidence_read_json(NULL))
  testthat::expect_null(env$release_evidence_read_json(""))
  testthat::expect_null(env$release_evidence_read_json(NA_character_))
  testthat::expect_null(env$release_evidence_read_json(file.path(dizin, "yok.json")))

  # Geçerli JSON liste olarak döner
  iyi <- file.path(dizin, "iyi.json")
  writeLines(jsonlite::toJSON(list(a = 1L, b = "iki"), auto_unbox = TRUE), iyi, useBytes = TRUE)
  veri <- env$release_evidence_read_json(iyi)
  testthat::expect_true(is.list(veri))
  testthat::expect_identical(veri$b, "iki")

  # Bozuk JSON NULL döner (başarı gibi gösterilmez)
  bozuk <- file.path(dizin, "bozuk.json")
  writeLines("{ bozuk", bozuk, useBytes = TRUE)
  testthat::expect_null(env$release_evidence_read_json(bozuk))
})

testthat::test_that(".release_evidence_scalar tek skaler çeker, eksikte varsayılana düşer", {
  env <- .releaseEvidenceEnv()

  x <- list(ad = "deger", sayi = 7L, bos = NULL, eksik_na = NA, vektor = c("ilk", "ikinci"))

  testthat::expect_identical(env$.release_evidence_scalar(x, "ad"), "deger")
  # Sayısal skaler karaktere çevrilir
  testthat::expect_identical(env$.release_evidence_scalar(x, "sayi"), "7")
  # Vektörde yalnızca ilk eleman alınır
  testthat::expect_identical(env$.release_evidence_scalar(x, "vektor"), "ilk")
  # Yok olan isim varsayılanı döndürür
  testthat::expect_identical(env$.release_evidence_scalar(x, "yok", default = "vars"), "vars")
  # NULL ve NA değerler varsayılana düşer
  testthat::expect_identical(env$.release_evidence_scalar(x, "bos", default = "vars"), "vars")
  testthat::expect_identical(env$.release_evidence_scalar(x, "eksik_na", default = "vars"), "vars")
  # Varsayılan belirtilmezse boş string
  testthat::expect_identical(env$.release_evidence_scalar(x, "yok2"), "")
})

testthat::test_that("release_evidence_overview alt özetleri ve kanıt sınırı notunu birleştirir", {
  env <- .releaseEvidenceEnv()
  kok <- withr::local_tempdir()
  .makeVmEvidenceFixture(kok)

  log_dir <- withr::local_tempdir()

  genel <- env$release_evidence_overview(repo_root = kok, log_dir = log_dir)

  testthat::expect_true(all(c("generated_at", "vm_evidence", "ai_validation",
                              "post_deploy_smoke", "log_health", "proof_note") %in% names(genel)))
  testthat::expect_true(genel$vm_evidence$found)
  testthat::expect_false(genel$ai_validation$found)
  testthat::expect_false(genel$post_deploy_smoke$found)
  testthat::expect_identical(genel$post_deploy_smoke$status, "not_found")
  testthat::expect_false(genel$log_health$found)

  # Kanıt sınırı dürüstlüğü: SKIP'in kanıt olmadığı notu her özette taşınır
  testthat::expect_true(grepl("kanıt değildir", genel$proof_note, fixed = TRUE))
})
