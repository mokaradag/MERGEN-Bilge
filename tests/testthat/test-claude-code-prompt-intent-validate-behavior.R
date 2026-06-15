# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-prompt-intent-validate-behavior.R
# Açıklama: Bilge Yolaç güvenlik kapısı cc_policy_validate_prompt_file_intent()
#           ORKESTRATÖRÜNÜN davranışsal dal kapsaması. Bu fonksiyon Claude Code
#           CLI BAŞLAMADAN ÖNCE çalışan gerçek güvenlik kapısıdır: prompt içinde
#           çalışma dizini dışına açık yazma/düzenleme/silme isteklerini engeller.
#
#           Mevcut sözleşme testi (test-claude-code-security-policy-contract.R)
#           yalnızca DÖRT durumu ve HER ZAMAN açık `allowed_roots` argümanıyla
#           sınıyordu (kök içi/traversal/mutlak/düzyazı). run-streaming testi ise
#           bu fonksiyonu STUB'lıyor. Bu test, davranışsal olarak hiç sınanmamış
#           güvenlik-kritik dalları kilitler:
#             - yazma niyeti yoksa erken `ok=TRUE` (yalnızca yazma niyeti kapıyı tetikler),
#             - yazma niyeti var ama yol tokenı yoksa `ok=TRUE`,
#             - `allowed_roots` boşken köklerin cc_policy_allowed_output_roots ile
#               TÜRETİLMESİ (gerçek çalışma-zamanı yolu),
#             - göreli `../` token + BOŞ workdir -> engellenir (doğrulanamaz),
#             - engellenen yol dedup + hata mesajı sözleşmesi (ok=FALSE),
#             - uzantısız + var olmayan token -> atlanır (false-positive önleme).
#
#           Tamamen offline/deterministik: CLI, dosya sistemi yazımı (yalnızca
#           geçici dizin), ağ, DB GEREKMEZ.
# ==============================================================================

# Bağımlılıklar farklı dosyalarda yaşadığı için her dosyayı AYRI guard ile yükle.
# Kardeş test (test-claude-code-prompt-path-policy-behavior.R) yalnızca prompt
# politikasını globalenv'e source ediyor; bu yüzden orkestratör var olsa bile
# path_policy yardımcıları (cc_policy_normalize_path vb.) eksik olabilir. Tam
# suite'te hepsi global.R tarafından zaten yüklü olduğundan guard'lar atlar.
.ccintent_source_once <- function() {
  repo <- resolve_repo_root_for_tests()

  if (!exists("path_exists_relaxed", mode = "function", inherits = TRUE)) {
    source(file.path(repo, "R", "helpers_files_path.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("cc_policy_path_inside_roots", mode = "function", inherits = TRUE)) {
    source(file.path(repo, "R", "helpers_claude_code_path_policy.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("cc_policy_validate_prompt_file_intent", mode = "function",
              inherits = TRUE)) {
    source(file.path(repo, "R", "helpers_claude_code_prompt_security_policy.R"),
           encoding = "UTF-8", local = globalenv())
  }
  invisible(TRUE)
}

# Türetilen kökleri deterministik kılmak için konfigüre kök env değişkenlerini
# temizler ve gerçek, izole bir geçici çalışma dizini + dış dizin üretir. Dış
# dizin daima taze bir geçici kardeş olduğundan hiçbir varsayılan kök (workdir,
# indirme kökü, kullanıcı workspace) onu içermez -> "dışarısı engellenir" tam
# suite'te de güvenli kalır.
.ccintent_setup_dirs <- function(envir = parent.frame()) {
  withr::local_envvar(
    c(
      CLAUDE_CODE_ALLOWED_OUTPUT_ROOTS = "",
      CLAUDE_CODE_ALLOWED_WORKDIR_ROOTS = "",
      CLAUDE_CODE_DEFAULT_WORKDIR = ""
    ),
    .local_envir = envir
  )
  wd <- withr::local_tempdir(.local_envir = envir)
  out <- withr::local_tempdir(.local_envir = envir)
  list(
    wd = normalizePath(wd, winslash = "/", mustWork = FALSE),
    out = normalizePath(out, winslash = "/", mustWork = FALSE)
  )
}

# ------------------------------------------------------------------------------
# Yazma niyeti kapısı: salt-okuma istekleri yol tokenı içerse bile geçer.
# ------------------------------------------------------------------------------
testthat::test_that("yazma niyeti yoksa dış yol tokenı içeren istek engellenmez", {
  .ccintent_source_once()
  d <- .ccintent_setup_dirs()

  # "oku" / "incele" yazma fiili değildir; kapı tetiklenmemeli.
  res <- cc_policy_validate_prompt_file_intent(
    prompt = paste0(d$out, "/gizli.txt dosyasını oku ve incele"),
    workdir = d$wd,
    user_id = NULL
  )

  testthat::expect_true(isTRUE(res$ok))
  testthat::expect_identical(res$error, "")
  testthat::expect_identical(res$blocked_paths, character(0))
})

# ------------------------------------------------------------------------------
# Yazma niyeti var ama hiç yol tokenı yok -> ok.
# ------------------------------------------------------------------------------
testthat::test_that("yazma niyeti var ama yol tokenı yoksa istek geçer", {
  .ccintent_source_once()
  d <- .ccintent_setup_dirs()

  res <- cc_policy_validate_prompt_file_intent(
    prompt = "Kısa bir özet raporu oluştur lütfen",
    workdir = d$wd,
    user_id = NULL
  )

  testthat::expect_true(isTRUE(res$ok))
  testthat::expect_identical(res$blocked_paths, character(0))
})

# ------------------------------------------------------------------------------
# TÜRETİLEN kökler: allowed_roots verilmediğinde kökler workdir'den türetilir;
# çalışma dizini içine mutlak yazma izinli olmalı.
# ------------------------------------------------------------------------------
testthat::test_that("allowed_roots verilmezse çalışma dizini içine yazma türetilen köklerle izinlidir", {
  .ccintent_source_once()
  d <- .ccintent_setup_dirs()

  res <- cc_policy_validate_prompt_file_intent(
    prompt = paste0(d$wd, "/sonuc.txt oluştur"),
    workdir = d$wd,
    user_id = NULL
    # allowed_roots BİLİNÇLİ OLARAK verilmedi -> cc_policy_allowed_output_roots türetir.
  )

  testthat::expect_true(isTRUE(res$ok))
  testthat::expect_identical(res$blocked_paths, character(0))
})

# ------------------------------------------------------------------------------
# TÜRETİLEN kökler: çalışma dizini DIŞINA mutlak yazma engellenir; türetme
# güvenliği gevşetmez.
# ------------------------------------------------------------------------------
testthat::test_that("allowed_roots verilmezse dış mutlak yazma türetilen köklerle engellenir", {
  .ccintent_source_once()
  d <- .ccintent_setup_dirs()

  hedef <- paste0(d$out, "/sonuc.txt")
  res <- cc_policy_validate_prompt_file_intent(
    prompt = paste0("Şu dosyayı oluştur: ", hedef),
    workdir = d$wd,
    user_id = NULL
  )

  testthat::expect_false(isTRUE(res$ok))
  testthat::expect_true(length(res$blocked_paths) >= 1L)
  # Engellenen yol HAM token olarak raporlanır ve hata mesajında listelenir.
  testthat::expect_true(any(grepl("sonuc.txt", res$blocked_paths, fixed = TRUE)))
  testthat::expect_true(grepl("güvenlik ilkesi", res$error, fixed = TRUE))
  testthat::expect_true(grepl(hedef, res$error, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# Traversal: workdir altından ../ ile dışarı çıkan göreli yazma engellenir.
# ------------------------------------------------------------------------------
testthat::test_that("workdir altından ../ ile dışarı yazma engellenir", {
  .ccintent_source_once()
  d <- .ccintent_setup_dirs()

  res <- cc_policy_validate_prompt_file_intent(
    prompt = "../disarida/sonuc.txt dosyasını oluştur",
    workdir = d$wd,
    user_id = NULL
  )

  testthat::expect_false(isTRUE(res$ok))
  testthat::expect_true("../disarida/sonuc.txt" %in% res$blocked_paths)
})

# ------------------------------------------------------------------------------
# Göreli token + BOŞ workdir -> doğrulanamaz, bu yüzden engellenir.
# (Workdir olmadan göreli bir yazma hedefinin güvenli olduğu kanıtlanamaz.)
# ------------------------------------------------------------------------------
testthat::test_that("göreli yazma hedefi + boş workdir engellenir", {
  .ccintent_source_once()
  d <- .ccintent_setup_dirs()

  res <- cc_policy_validate_prompt_file_intent(
    prompt = "../disarida/sonuc.txt oluştur",
    workdir = "",
    allowed_roots = d$wd,
    user_id = NULL
  )

  testthat::expect_false(isTRUE(res$ok))
  testthat::expect_true("../disarida/sonuc.txt" %in% res$blocked_paths)
})

# ------------------------------------------------------------------------------
# False-positive önleme: uzantısız + var olmayan dış token engellenmez.
# (Düzyazı/proje konumu başvurusu olabilir; CLI'ın kendi izin sistemi gerçek
# hedefe göre değerlendirir. CLAUDE.md sözleşmesi: düzyazıyı aşırı engelleme.)
# ------------------------------------------------------------------------------
testthat::test_that("uzantısız + var olmayan dış token engellenmez (false-positive önleme)", {
  .ccintent_source_once()
  d <- .ccintent_setup_dirs()

  res <- cc_policy_validate_prompt_file_intent(
    prompt = paste0("Şu raporu oluştur: ", d$out, "/SadeceMetinGibiGorunenBirIfade"),
    workdir = d$wd,
    user_id = NULL
  )

  testthat::expect_true(isTRUE(res$ok))
  testthat::expect_identical(res$blocked_paths, character(0))
})

# ------------------------------------------------------------------------------
# Çoklu engellenen token: dedup + hata mesajı her ikisini de listeler.
# ------------------------------------------------------------------------------
testthat::test_that("birden fazla dış yazma hedefi ayrı ayrı engellenir ve listelenir", {
  .ccintent_source_once()
  d <- .ccintent_setup_dirs()

  hedef_a <- paste0(d$out, "/a.txt")
  hedef_b <- paste0(d$out, "/b.txt")
  res <- cc_policy_validate_prompt_file_intent(
    prompt = paste0("Şu iki dosyayı oluştur: ", hedef_a, " ve ", hedef_b),
    workdir = d$wd,
    user_id = NULL
  )

  testthat::expect_false(isTRUE(res$ok))
  testthat::expect_identical(length(res$blocked_paths), 2L)
  testthat::expect_true(all(c(hedef_a, hedef_b) %in% res$blocked_paths))
})
