# ==============================================================================
# Dosya Yolu: tests/testthat/test-health-release-ui-behavior.R
# Açıklama: module_health_release.R "Doğrulama Kanıtı" sekmesi UI yardımcıları için
#           davranış testleri. health_release_ui ve iç yardımcıların
#           (.health_release_pill, .health_release_steps_table) gerçek
#           girdi→çıktı davranışı, kanıt-yok dürüstlüğü ve secret-safe sınır
#           (artifact yolu / ham log içeriği render edilmemesi) doğrulanır.
#           Çevrimdışı ve deterministik; gerçek artifact/DB/ağ gerektirmez.
# ==============================================================================

suppressMessages(library(shiny))

.healthReleaseEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  # Sağlık biçimlendirme yardımcıları UI builder'ların bağımlılığıdır.
  source(file.path(kok, "R", "helpers_health_formatters.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "module_health_release.R"), encoding = "UTF-8", local = env)
  env
}

# release_evidence_overview() çıktısının şeklini taklit eden tam fixture.
.fullReleaseOverview <- function() {
  list(
    generated_at = "2026-06-13 09:00:00",
    vm_evidence = list(
      found = TRUE,
      status = "passed",
      artifact_path = "/cok/gizli/yol/artifacts/vm-evidence/x/evidence.json",
      generated_at_utc = "2026-06-12T21:18:36Z",
      profile_effective = "vm",
      passed = 13L,
      failed = 0L,
      skipped = 0L,
      steps = list(
        list(id = "env_config", status = "passed", required = TRUE),
        list(id = "browser_ux_smoke", status = "passed", required = FALSE),
        list(id = "renv_status", status = "skipped", required = FALSE)
      )
    ),
    ai_validation = list(
      found = TRUE,
      artifact_path = "/x/artifacts/ai-validation/y/summary.json",
      validation_execution_status = "ran_by_ai_repo_check",
      profile_requested = "cloud-quick",
      profile_effective = "quick",
      failed_steps = 0L,
      skipped_steps = 1L,
      app_source_smoke_status = "skipped",
      shiny_boot_smoke_status = "passed",
      browser_smoke_status = "not_requested"
    ),
    post_deploy_smoke = list(
      found = TRUE,
      status = "degraded",
      should_fail = FALSE,
      artifact_path = "/x/artifacts/post-deploy-smoke/z/post-deploy-smoke.json",
      available_runs = c("20260624-100000"),
      selected_run = "20260624-100000",
      generated_at_utc = "2026-06-24T10:00:00Z",
      evaluated_at = "2026-06-24T13:00:00+0300",
      total = 4L,
      pass_count = 3L,
      warn_count = 1L,
      critical_count = 0L,
      critical_failures = character(0)
    ),
    log_health = list(
      found = TRUE,
      log_path = "/var/log/mergen_20260613.log",
      window_lines = 1500L,
      error_count = 2L,
      warn_count = 5L,
      last_error_at = "2026-06-13 08:55:10"
    ),
    proof_note = "SKIP edilen adımlar kanıt değildir; cloud profili VM/SSO/DB kanıtı üretmez."
  )
}

testthat::test_that("health_release_ui NULL/liste-olmayan girdide nazikçe boş mesaj döner", {
  env <- .healthReleaseEnv()

  for (girdi in list(NULL, "metin", 42L)) {
    html <- paste(as.character(env$health_release_ui(girdi)), collapse = "\n")
    testthat::expect_true(grepl("health-empty", html, fixed = TRUE))
    testthat::expect_true(grepl("kullanılamıyor", html, fixed = TRUE))
  }
})

testthat::test_that("health_release_ui tam kanıt özetini gerçek alanlarla render eder", {
  env <- .healthReleaseEnv()
  html <- paste(as.character(env$health_release_ui(.fullReleaseOverview())), collapse = "\n")

  # Başlık ve okuma zamanı
  testthat::expect_true(grepl("Doğrulama Kanıtı", html, fixed = TRUE))
  testthat::expect_true(grepl("2026-06-13 09:00:00", html, fixed = TRUE))

  # VM evidence sayaçları metin olarak görünür
  testthat::expect_true(grepl("13 geçti / 0 başarısız / 0 atlandı", html, fixed = TRUE))
  testthat::expect_true(grepl("2026-06-12T21:18:36Z", html, fixed = TRUE))

  # Adım tablosu id'leri ve durum etiketleri
  testthat::expect_true(grepl("env_config", html, fixed = TRUE))
  testthat::expect_true(grepl("browser_ux_smoke", html, fixed = TRUE))
  testthat::expect_true(grepl("renv_status", html, fixed = TRUE))
  testthat::expect_true(grepl("Geçti", html, fixed = TRUE))
  testthat::expect_true(grepl("Atlandı", html, fixed = TRUE))

  # ai_validation alanları
  testthat::expect_true(grepl("ran_by_ai_repo_check", html, fixed = TRUE))
  testthat::expect_true(grepl("cloud-quick", html, fixed = TRUE))

  # Log sağlığı sayaçları
  testthat::expect_true(grepl("2026-06-13 08:55:10", html, fixed = TRUE))

  # Dağıtım sonrası duman testi kartı: başlık, sayaçlar ve metrik kutusu
  testthat::expect_true(grepl("Dağıtım Sonrası Duman Testi", html, fixed = TRUE))
  testthat::expect_true(grepl("Dağıtım Sonrası", html, fixed = TRUE))
  testthat::expect_true(grepl("3 ok / 1 uyarı / 0 kritik", html, fixed = TRUE))
  # Genel sonuç "degraded" → kart pill'inde de "Kısmi" + uyarı rengi olmalı
  # (nötr/ham "degraded" değil); hem metrik kutusu hem kart pill warning gösterir.
  testthat::expect_true(grepl("Kısmi", html, fixed = TRUE))
  testthat::expect_true(grepl("health-status-warning", html, fixed = TRUE))
  testthat::expect_false(grepl(">degraded<", html, fixed = TRUE))

  # Kanıt sınırı notu
  testthat::expect_true(grepl("kanıt değildir", html, fixed = TRUE))
})

testthat::test_that("health_release_ui secret-safe sınır: artifact yolu ve log dosya yolu render edilmez", {
  env <- .healthReleaseEnv()
  html <- paste(as.character(env$health_release_ui(.fullReleaseOverview())), collapse = "\n")

  # Artifact yolları yalnızca okunur, UI'ye taşınmaz (savunma derinliği)
  testthat::expect_false(grepl("cok/gizli/yol", html, fixed = TRUE))
  testthat::expect_false(grepl("artifacts/vm-evidence/x/evidence.json", html, fixed = TRUE))
  testthat::expect_false(grepl("artifacts/ai-validation/y/summary.json", html, fixed = TRUE))
  testthat::expect_false(grepl("artifacts/post-deploy-smoke/z/post-deploy-smoke.json", html, fixed = TRUE))
  testthat::expect_false(grepl("/var/log/mergen_20260613.log", html, fixed = TRUE))
})

testthat::test_that("health_release_ui kanıt bulunamadığında başarı gibi göstermez", {
  env <- .healthReleaseEnv()
  bos <- list(
    generated_at = "2026-06-13 09:00:00",
    vm_evidence = list(found = FALSE, status = "not_found"),
    ai_validation = list(found = FALSE),
    post_deploy_smoke = list(found = FALSE, status = "not_found"),
    log_health = list(found = FALSE),
    proof_note = "SKIP edilen adımlar kanıt değildir."
  )
  html <- paste(as.character(env$health_release_ui(bos)), collapse = "\n")

  testthat::expect_true(grepl("VM Kanıtı Yok", html, fixed = TRUE))
  testthat::expect_true(grepl("bulunamadı", html, fixed = TRUE))
  # Dağıtım sonrası kanıt yoksa kart açıkça "bulunamadı" der, başarı göstermez
  testthat::expect_true(grepl("Dağıtım sonrası duman testi artifact", html, fixed = TRUE))
  # Metrik kutularında VM sayısı yerine "—" gösterilir, sahte 0 başarı değil
  testthat::expect_true(grepl("—", html, fixed = TRUE))
})

testthat::test_that("health_release_ui post-deploy should_fail durumunu kritik gosterir (no_checks gizlenmez)", {
  env <- .healthReleaseEnv()
  ov <- .fullReleaseOverview()
  # Gate hiç kontrol toplayamadı: değerlendirici overall="unknown" ama
  # should_fail=TRUE döner (reason="no_checks"). Bu bloklayan kapı nötr
  # "Bilinmiyor" değil, kritik "Başarısız" gösterilmeli.
  ov$post_deploy_smoke <- list(
    found = TRUE, status = "unknown", should_fail = TRUE,
    available_runs = c("20260624-100000"), selected_run = "20260624-100000",
    generated_at_utc = "2026-06-24T10:00:00Z", evaluated_at = "",
    total = 0L, pass_count = 0L, warn_count = 0L, critical_count = 0L,
    critical_failures = character(0)
  )
  html <- paste(as.character(env$health_release_ui(ov)), collapse = "\n")

  # Bloklayan kapı "Başarısız" + kritik renkle gösterilmeli (kart pill + metrik kutusu).
  testthat::expect_true(grepl("Başarısız", html, fixed = TRUE))
  testthat::expect_true(grepl("health-status-critical", html, fixed = TRUE))
})

testthat::test_that(".health_release_pill kanıt durumunu doğru renk ve Türkçe etikete eşler", {
  env <- .healthReleaseEnv()

  gecti <- paste(as.character(env$.health_release_pill("passed")), collapse = "")
  testthat::expect_true(grepl("Geçti", gecti, fixed = TRUE))
  testthat::expect_true(grepl("health-status-ok", gecti, fixed = TRUE))

  basarisiz <- paste(as.character(env$.health_release_pill("failed")), collapse = "")
  testthat::expect_true(grepl("Başarısız", basarisiz, fixed = TRUE))
  testthat::expect_true(grepl("health-status-critical", basarisiz, fixed = TRUE))

  atlandi <- paste(as.character(env$.health_release_pill("skipped")), collapse = "")
  testthat::expect_true(grepl("Atlandı", atlandi, fixed = TRUE))
  testthat::expect_true(grepl("health-status-not_configured", atlandi, fixed = TRUE))

  yok <- paste(as.character(env$.health_release_pill("not_found")), collapse = "")
  testthat::expect_true(grepl("Bulunamadı", yok, fixed = TRUE))

  # Özel etiket geçilince renk korunur ama etiket override edilir
  ozel <- paste(as.character(env$.health_release_pill("passed", label = "Özel")), collapse = "")
  testthat::expect_true(grepl("Özel", ozel, fixed = TRUE))
  testthat::expect_true(grepl("health-status-ok", ozel, fixed = TRUE))
})

testthat::test_that(".health_release_steps_table adımları tabloya çevirir, boşta nazik mesaj döner", {
  env <- .healthReleaseEnv()

  bos <- paste(as.character(env$.health_release_steps_table(NULL)), collapse = "")
  testthat::expect_true(grepl("Adım kaydı yok", bos, fixed = TRUE))

  bos2 <- paste(as.character(env$.health_release_steps_table(list())), collapse = "")
  testthat::expect_true(grepl("Adım kaydı yok", bos2, fixed = TRUE))

  steps <- list(
    list(id = "env_config", status = "passed", required = TRUE),
    list(id = "vm_preflight_real", status = "failed", required = TRUE)
  )
  html <- paste(as.character(env$.health_release_steps_table(steps)), collapse = "")
  testthat::expect_true(grepl("<table", html, fixed = TRUE))
  testthat::expect_true(grepl("env_config", html, fixed = TRUE))
  testthat::expect_true(grepl("vm_preflight_real", html, fixed = TRUE))
  testthat::expect_true(grepl("Evet", html, fixed = TRUE))   # required = TRUE
  testthat::expect_true(grepl("Geçti", html, fixed = TRUE))
  testthat::expect_true(grepl("Başarısız", html, fixed = TRUE))
})

testthat::test_that("health_release_ui ns ve >=2 koşu varsa koşu seçici (dropdown) render eder", {
  env <- .healthReleaseEnv()
  ov <- .fullReleaseOverview()
  ov$vm_evidence$available_runs <- c("20260613-133648", "20260101-080000")
  ov$vm_evidence$selected_run <- "20260613-133648"

  ns <- function(x) paste0("health-", x)
  html <- paste(as.character(env$health_release_ui(ov, ns = ns)), collapse = "\n")

  # Koşu seçici input'u ns ile üretilmiş id'yi ve sarmalayıcı sınıfı taşır
  testthat::expect_true(grepl("health-release_run", html, fixed = TRUE))
  testthat::expect_true(grepl("health-release-run-picker", html, fixed = TRUE))
  # Her iki koşu zaman damgası da seçenek olarak görünür
  testthat::expect_true(grepl("20260613-133648", html, fixed = TRUE))
  testthat::expect_true(grepl("20260101-080000", html, fixed = TRUE))
  # Hero meta gösterilen koşuyu belirtir
  testthat::expect_true(grepl("Koşu:", html, fixed = TRUE))
})

testthat::test_that("health_release_ui ns yoksa veya tek koşu varsa dropdown render etmez", {
  env <- .healthReleaseEnv()

  # ns NULL: dropdown yok (izole/test bağlamı), koşular olsa bile
  ov <- .fullReleaseOverview()
  ov$vm_evidence$available_runs <- c("20260613-133648", "20260101-080000")
  ov$vm_evidence$selected_run <- "20260613-133648"
  html_ns_yok <- paste(as.character(env$health_release_ui(ov)), collapse = "\n")
  testthat::expect_false(grepl("health-release-run-picker", html_ns_yok, fixed = TRUE))

  # Tek koşu: seçilecek alternatif yok, dropdown gösterilmez
  ov2 <- .fullReleaseOverview()
  ov2$vm_evidence$available_runs <- c("20260613-133648")
  ov2$vm_evidence$selected_run <- "20260613-133648"
  ns <- function(x) paste0("health-", x)
  html_tek <- paste(as.character(env$health_release_ui(ov2, ns = ns)), collapse = "\n")
  testthat::expect_false(grepl("health-release-run-picker", html_tek, fixed = TRUE))
})

testthat::test_that("health_release_ui koşu seçici tam artifact yolunu sızdırmaz (secret-safe)", {
  env <- .healthReleaseEnv()
  ov <- .fullReleaseOverview()
  ov$vm_evidence$available_runs <- c("20260613-133648", "20260101-080000")
  ov$vm_evidence$selected_run <- "20260613-133648"
  ns <- function(x) paste0("health-", x)
  html <- paste(as.character(env$health_release_ui(ov, ns = ns)), collapse = "\n")
  # Yalnızca zaman damgası adı render edilir; tam yol asla taşınmaz
  testthat::expect_false(grepl("cok/gizli/yol", html, fixed = TRUE))
  testthat::expect_false(grepl("artifacts/vm-evidence/x/evidence.json", html, fixed = TRUE))
})

# healthServer'ın "release" sekmesini gerçekten health_release_ui'ye yönlendirdiğini
# kanıtlar. switch değerinde bir yazım hatası sessizce overview'a düşerdi; bu test
# o regresyonu yakalar. Ağır bağımlılıklar (health_collect_checks,
# release_evidence_overview) env içinde stub'lanır; gerçek DB/LLM/ağ çağrısı yoktur.
.healthModuleServerEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  # healthServer'ın switch'inin çağırdığı tüm sekme UI yardımcıları.
  for (dosya in c(
    "R/helpers_health_formatters.R",
    "R/helpers_health_table.R",
    "R/module_health_overview.R",
    "R/module_health_connectivity.R",
    "R/module_health_storage.R",
    "R/module_health_runtime.R",
    "R/module_health_security.R",
    "R/module_health_diagnostics.R",
    "R/module_health_release.R"
  )) {
    source(file.path(kok, dosya), encoding = "UTF-8", local = env)
  }

  # module_health.R üst düzeyde health_source_optional çağırır; healthServer'ı
  # izole env'e almak için yalnızca fonksiyon tanımını okuruz. safe_source
  # globalenv'e kaynar; bu yüzden health_source_optional'ı no-op'a çeviririz.
  env$safe_source <- function(...) invisible(TRUE)
  env$health_source_optional <- function(...) invisible(TRUE)
  source(file.path(kok, "R", "module_health.R"), encoding = "UTF-8", local = env)
  env
}

testthat::test_that("healthServer 'release' sekmesi health_release_ui çıktısını döndürür", {
  env <- .healthModuleServerEnv()

  # Ağır bağımlılıkları env içinde stub'la (healthServer kapanış env'i = env).
  env$health_collect_checks <- function(...) {
    data.frame(
      id = "app.version", label = "Sürüm", status = "ok", severity = 0L,
      value = "v1.0", detail = "", duration_ms = 1, checked_at = "",
      remediation = "", stringsAsFactors = FALSE
    )
  }
  env$release_evidence_overview <- function(...) .fullReleaseOverview()

  shiny::testServer(env$healthServer, args = list(perf_tracker = NULL), {
    session$setInputs(health_tabs = "release")
    cikti <- paste(as.character(output$health_tab_content), collapse = "\n")
    testthat::expect_true(grepl("Doğrulama Kanıtı", cikti, fixed = TRUE))
    testthat::expect_true(grepl("13 geçti / 0 başarısız / 0 atlandı", cikti, fixed = TRUE))

    # Kontrol amaçlı: overview sekmesi farklı içerik üretir (yanlış yönlenme yok)
    session$setInputs(health_tabs = "overview")
    overview_html <- paste(as.character(output$health_tab_content), collapse = "\n")
    testthat::expect_true(grepl("10 Saniyelik Özet", overview_html, fixed = TRUE))
    testthat::expect_false(grepl("13 geçti / 0 başarısız", overview_html, fixed = TRUE))
  })
})
