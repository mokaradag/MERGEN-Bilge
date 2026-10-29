# ==============================================================================
# Dosya Yolu: tests/testthat/test-ux-smoke-exposure-gate-behavior.R
# Açıklama: UX smoke harness'ı gerçek uygulama eylemleri tetikler; üretimde
#           kimliği doğrulanmamış bir eylem yüzeyi olmamalıdır.
#           - Harness www/ dışında (tests/smoke) tutulur: www alt dizinleri,
#             img -> www takma adı ve Windows harf varyantları onu sunamaz.
#           - /smoke statik yolu yalnızca MERGEN_ENABLE_UX_SMOKE ile kaydedilir.
#           - Sayfa yüklemesi tek başına eylem başlatmaz (açık başlatma gerekir).
# ==============================================================================

.smoke_gate_app_env <- function() {
  # app.R'deki saf kapı yardımcıları uygulamayı başlatmadan değerlendirilir.
  exprs <- parse_r_file_utf8(file.path(resolve_repo_root_for_tests(), "app.R"))
  env <- new.env(parent = globalenv())
  for (e in exprs) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) &&
        as.character(e[[2]]) %in% c("mergen_ux_smoke_prefix", "mergen_ux_smoke_enabled", "mergen_register_ux_smoke_resource",
                                    "safe_add_resource_path")) {
      eval(e, env)
    }
  }
  env
}

test_that("smoke harness www statik ağacında hiçbir adla bulunmaz", {
  root <- resolve_repo_root_for_tests()
  www_dosyalari <- list.files(file.path(root, "www"), recursive = TRUE, all.files = TRUE)
  # Büyük/küçük harf duyarsız: Windows/NTFS'te harf varyantı aynı dosyayı açar.
  expect_false(any(grepl("ux-smoke", www_dosyalari, ignore.case = TRUE)))
  expect_false(dir.exists(file.path(root, "www", "smoke")))
  expect_true(file.exists(file.path(root, "tests", "smoke", "ux-smoke.html")))
})

test_that("/smoke yolu yalnızca bakımcı kapısı açıkken kaydedilir", {
  env <- .smoke_gate_app_env()
  withr::local_dir(resolve_repo_root_for_tests())
  if ("smoke" %in% names(shiny::resourcePaths())) shiny::removeResourcePath("smoke")
  withr::defer(if ("smoke" %in% names(shiny::resourcePaths())) shiny::removeResourcePath("smoke"))

  withr::local_envvar(MERGEN_ENABLE_UX_SMOKE = NA, MERGEN_HOST = "127.0.0.1",
                     MERGEN_UX_SMOKE_PATH = NA, MERGEN_ALLOW_NETWORK_UX_SMOKE = NA)
  expect_false(env$mergen_ux_smoke_enabled())
  expect_false(isTRUE(env$mergen_register_ux_smoke_resource()))
  expect_false("smoke" %in% names(shiny::resourcePaths()))

  for (deger in c("false", "0", "", "hayir", "TRUE-ish")) {
    withr::local_envvar(MERGEN_ENABLE_UX_SMOKE = deger)
    expect_false(env$mergen_ux_smoke_enabled(), info = deger)
  }

  withr::local_envvar(MERGEN_ENABLE_UX_SMOKE = "true")
  expect_true(isTRUE(env$mergen_register_ux_smoke_resource()))
  kayit <- shiny::resourcePaths()[["smoke"]]
  expect_identical(normalizePath(kayit, winslash = "/"),
                   normalizePath(file.path("tests", "smoke"), winslash = "/"))
  for (deger in c("TRUE", "1", "evet")) {
    withr::local_envvar(MERGEN_ENABLE_UX_SMOKE = deger)
    expect_true(env$mergen_ux_smoke_enabled(), info = deger)
  }

  # Bayrak açık olsa da ağ arayüzünü dinleyen uygulamada /smoke sunulmaz.
  withr::local_envvar(MERGEN_ENABLE_UX_SMOKE = "true")
  for (adres in c("0.0.0.0", "10.0.0.5", "::", "", "127.0.0.1.example")) {
    expect_false(env$mergen_ux_smoke_enabled(adres), info = adres)
  }
  for (adres in c("127.0.0.1", "localhost", "::1", " LOCALHOST ")) {
    expect_true(env$mergen_ux_smoke_enabled(adres), info = adres)
  }
  withr::local_envvar(MERGEN_HOST = NA)
  expect_false(env$mergen_ux_smoke_enabled(), info = "varsayılan MERGEN_HOST 0.0.0.0")
  expect_false(isTRUE(env$mergen_register_ux_smoke_resource()))
  expect_false("smoke" %in% names(shiny::resourcePaths()))
  withr::local_envvar(MERGEN_HOST = "127.0.0.1")
  expect_true(isTRUE(env$mergen_register_ux_smoke_resource()))

  # Aynı süreçte kapı kapanınca önceki kayıt da kalkar.
  withr::local_envvar(MERGEN_ENABLE_UX_SMOKE = "false")
  expect_false(isTRUE(env$mergen_register_ux_smoke_resource()))
  expect_false("smoke" %in% names(shiny::resourcePaths()))
})

test_that("run_mergen_app /smoke kararını gerçek dinleme adresiyle yeniden verir", {
  exprs <- parse_r_file_utf8(file.path(resolve_repo_root_for_tests(), "app.R"))
  env <- .smoke_gate_app_env()
  tanim <- Filter(function(e) is.call(e) && identical(e[[1]], as.name("<-")) &&
                    identical(as.character(e[[2]]), "run_mergen_app"), exprs)
  expect_length(tanim, 1L)
  eval(tanim[[1]], env)
  baslatilan <- list()
  env$validate_boot_state <- function(...) invisible(TRUE)
  env$create_mergen_app <- function() "uygulama"
  env$.normalize_mergen_port <- function(port) as.integer(port)
  testthat::local_mocked_bindings(runApp = function(app, host, port, ...) {
    baslatilan[[length(baslatilan) + 1L]] <<- list(host = host, smoke = "smoke" %in% names(shiny::resourcePaths()))
    invisible(NULL)
  }, .package = "shiny")
  withr::local_dir(resolve_repo_root_for_tests())
  if ("smoke" %in% names(shiny::resourcePaths())) shiny::removeResourcePath("smoke")
  withr::defer(if ("smoke" %in% names(shiny::resourcePaths())) shiny::removeResourcePath("smoke"))
  withr::local_envvar(MERGEN_ENABLE_UX_SMOKE = "true", MERGEN_HOST = "127.0.0.1",
                     MERGEN_UX_SMOKE_PATH = NA, MERGEN_ALLOW_NETWORK_UX_SMOKE = NA)

  # Kaynak yüklemede açılmış eşleme, uygulama ağ adresinde başlatılınca kalkar.
  expect_true(isTRUE(env$mergen_register_ux_smoke_resource()))
  env$run_mergen_app(host = "0.0.0.0", port = 8009L, launch.browser = FALSE)
  # Koşucular gibi döngü adresinde başlatılınca sunulur.
  env$run_mergen_app(host = "127.0.0.1", port = 8009L, launch.browser = FALSE)
  expect_identical(baslatilan, list(list(host = "0.0.0.0", smoke = FALSE), list(host = "127.0.0.1", smoke = TRUE)))
  expect_false("smoke" %in% names(shiny::resourcePaths()), info = "runApp bitince kaynak kaldırılır")
})

test_that("tarayıcı koşucusu sonucu işlenmiş #status metninden okur, betikteki sabitten değil", {
  ifadeler <- parse_r_file_utf8(file.path(resolve_repo_root_for_tests(), "tests", "scripts", "ai_browser_ux_smoke.R"))
  tanim <- Filter(function(e) is.call(e) && identical(e[[1]], as.name("<-")) &&
                    identical(as.character(e[[2]]), "ux_smoke_rendered_status"), as.list(ifadeler))
  expect_length(tanim, 1L)
  ortam <- new.env(parent = baseenv())
  eval(tanim[[1]], ortam)
  betik <- '<script>statusEl.textContent = "UX_SMOKE_DONE:PASS";</script><div class="log">UX_SMOKE_DONE:PASS</div>'
  # Başlamamış (autostart düşmüş) sayfa ve FAIL sonucu PASS sayılmaz.
  expect_identical(ortam$ux_smoke_rendered_status(paste0('<div id="status">Hazır</div>', betik)), "Hazır")
  expect_identical(ortam$ux_smoke_rendered_status(paste0('<div id="status">UX_SMOKE_DONE:FAIL 2</div>', betik)),
                   "UX_SMOKE_DONE:FAIL 2")
  expect_identical(ortam$ux_smoke_rendered_status(paste0('<div id="status">UX_SMOKE_DONE:PASS</div>', betik)),
                   "UX_SMOKE_DONE:PASS")
  expect_identical(ortam$ux_smoke_rendered_status(betik), "")
  kosucu <- paste(readLines(file.path(resolve_repo_root_for_tests(), "tests", "scripts", "ai_browser_ux_smoke.R"),
                            encoding = "UTF-8", warn = FALSE), collapse = "\n")
  expect_match(kosucu, 'identical(smoke_status, "UX_SMOKE_DONE:PASS")', fixed = TRUE)
  expect_false(grepl('grepl("UX_SMOKE_DONE:PASS", combined_output', kosucu, fixed = TRUE))
})

test_that("app.R smoke kaydını yalnızca kapı yardımcısı üzerinden yapar", {
  app_txt <- paste(readLines(file.path(resolve_repo_root_for_tests(), "app.R"), encoding = "UTF-8", warn = FALSE),
                   collapse = "\n")
  expect_match(app_txt, "  mergen_register_ux_smoke_resource()\n", fixed = TRUE)
  expect_false(grepl("safe_add_resource_path(\"smoke\", \"", app_txt, fixed = TRUE))
})

test_that("smoke harness sayfa yüklemesiyle eylem başlatmaz", {
  node <- Sys.which("node")
  skip_if(!nzchar(node), "Node kullanılamıyor")
  script <- file.path(resolve_repo_root_for_tests(), "tests", "scripts", "ux_smoke_start_gate_regressions.js")
  sonuc <- system2(node, shQuote(script), stdout = TRUE, stderr = TRUE)
  expect_null(attr(sonuc, "status"), info = paste(sonuc, collapse = "\n"))
  expect_match(paste(sonuc, collapse = "\n"), "ux smoke start gate regressions passed")
})

test_that("otomatik tarayıcı koşucusu kapıyı açar ve açık başlatma ister", {
  oku <- function(yol) paste(readLines(file.path(resolve_repo_root_for_tests(), yol), encoding = "UTF-8",
                                       warn = FALSE), collapse = "\n")
  kosucu <- oku("tests/scripts/ai_browser_ux_smoke.R")
  expect_match(kosucu, "MERGEN_ENABLE_UX_SMOKE='true'", fixed = TRUE)
  expect_match(kosucu, 'smoke_prefix <- "smoke"', fixed = TRUE)
  expect_match(kosucu, '%s/%s/ux-smoke.html?autostart=1', fixed = TRUE)
  expect_match(oku("tests/scripts/run_browser_concurrency_lane.R"), "/smoke/ux-smoke.html?autostart=1", fixed = TRUE)
})

test_that("tarayıcı ön kontrolü ana sayfayı veya eksik harness'ı kabul etmez", {
  root <- resolve_repo_root_for_tests()
  ifadeler <- parse_r_file_utf8(file.path(root, "tests", "scripts", "ai_browser_ux_smoke.R"))
  ortam <- new.env(parent = baseenv())
  for (e in ifadeler) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) &&
        as.character(e[[2]]) %in% c("ux_smoke_check_harness", "ux_smoke_rendered_status")) {
      eval(e, ortam)
    }
  }
  ortam$preflight_smoke_url <- "http://127.0.0.1:28081/smoke/ux-smoke.html"
  ortam$display_smoke_url <- "<test-smoke-url>"
  yanit <- read_source_text_utf8(file.path(root, "tests", "smoke", "ux-smoke.html"))
  istenen <- character(0)
  ortam$read_url <- function(target) {
    istenen <<- c(istenen, target)
    yanit
  }
  expect_true(ortam$ux_smoke_check_harness())
  expect_identical(istenen, ortam$preflight_smoke_url)

  # 404/boş yanıt, SSO/ana sayfa ve yalnız betikteki PASS sabiti kanıt değildir.
  for (gecersiz in c("", "<html><title>Not Found</title></html>",
                    '<html><title>MERGEN Bilge</title><div id="status">Ready</div></html>',
                    '<title>MERGEN UX Smoke</title><script>var s="UX_SMOKE_DONE:PASS";</script>')) {
    yanit <- gecersiz
    expect_error(ortam$ux_smoke_check_harness(), "FAILED: UX smoke harness is unavailable", fixed = TRUE)
    expect_error(ortam$ux_smoke_check_harness(), "MERGEN_ENABLE_UX_SMOKE=true", fixed = TRUE)
    expect_error(ortam$ux_smoke_check_harness(), "already running app", fixed = TRUE)
  }

  # Ön kontrol tarayıcı süreci/profilinden önce bloklamalıdır.
  kontrol <- which(vapply(as.list(ifadeler), identical, logical(1), quote(ux_smoke_check_harness())))
  profil <- which(vapply(as.list(ifadeler), function(e) {
    is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name("profile_dir"))
  }, logical(1)))
  expect_length(kontrol, 1L)
  expect_length(profil, 1L)
  expect_lt(kontrol, profil)
})

test_that("koşucunun geçici uygulaması .Renviron kapalı değerinden sonra smoke bayrağını yeniler", {
  ifadeler <- parse_r_file_utf8(file.path(resolve_repo_root_for_tests(), "tests", "scripts", "ai_browser_ux_smoke.R"))
  dal <- Filter(function(e) is.call(e) && identical(e[[1]], as.name("if")) &&
                  identical(e[[2]], quote(!isTRUE(use_external_app))), as.list(ifadeler))
  expect_length(dal, 1L)
  ortam <- new.env(parent = baseenv())
  ortam$port <- 28081L
  eval(dal[[1]][[3]][[2]], ortam)
  withr::local_envvar(MERGEN_ENABLE_UX_SMOKE = NA, MERGEN_RUN_APP = NA,
                     MERGEN_DISABLE_FUTURES = NA, LOCAL_LLM_ENDPOINT = NA,
                     DB_DSN = NA, AI_KEYS_MASTER = NA, TZ = NA)
  ortam$source <- function(...) Sys.setenv(MERGEN_ENABLE_UX_SMOKE = "false")
  ortam$cat <- function(...) invisible(NULL)
  dinleme <- NULL
  ortam$run_mergen_app <- function(host, ...) {
    dinleme <<- list(host = host, enabled = Sys.getenv("MERGEN_ENABLE_UX_SMOKE"))
  }
  eval(parse(text = ortam$expr), ortam)
  expect_identical(dinleme, list(host = "127.0.0.1", enabled = "true"))
})

test_that("smoke koşucusu açık hazırlanmış profili korur, varsayılan geçici profili temizler", {
  ifadeler <- parse_r_file_utf8(file.path(resolve_repo_root_for_tests(), "tests", "scripts", "ai_browser_ux_smoke.R"))
  ortam <- new.env(parent = baseenv())
  for (e in ifadeler) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) &&
        as.character(e[[2]]) %in% c("ux_smoke_browser_profile", "ux_smoke_cleanup_profile")) eval(e, ortam)
  }
  source(file.path(resolve_repo_root_for_tests(), "tests/scripts/helpers_browser_ux_profile.R"), local = ortam)
  ortam$repo_root <- withr::local_tempdir()
  ortam$artifact_dir <- withr::local_tempdir()
  gecici <- ortam$ux_smoke_browser_profile()
  expect_true(gecici$temporary)
  expect_true(dir.exists(gecici$path))
  ortam$ux_smoke_cleanup_profile(gecici)
  expect_false(dir.exists(gecici$path))

  yol <- file.path(withr::local_tempdir(), "smoke profil")
  expect_error(ortam$ux_smoke_browser_profile(yol), "requires MERGEN_BROWSER_UX_BASE_URL", fixed = TRUE)
  expect_false(dir.exists(yol))
  hazir <- ortam$ux_smoke_browser_profile(yol, external_app = TRUE)
  expect_false(hazir$temporary)
  expect_identical(hazir$path, normalizePath(yol, winslash = "/"))
  for (root in c(ortam$repo_root, ortam$artifact_dir)) {
    for (blocked in c(root, file.path(root, "profile"))) {
      expect_error(ortam$ux_smoke_browser_profile(blocked, TRUE), "outside the repository and artifacts", fixed = TRUE)
    }
    expect_error(ortam$ux_smoke_browser_profile(file.path(root, "profile", "..", "profile"), TRUE),
                 "outside the repository and artifacts", fixed = TRUE)
  }
  # Benzer onekli kardes dizin ve normalizasyon sonrasi dis yol kabul edilir.
  sibling <- paste0(ortam$repo_root, "-external")
  withr::defer(unlink(sibling, recursive = TRUE))
  expect_false(ortam$ux_smoke_browser_profile(sibling, TRUE)$temporary)
  expect_identical(ortam$ux_smoke_browser_profile(file.path(ortam$repo_root, "..", basename(sibling)), TRUE)$path,
                   normalizePath(sibling, winslash = "/"))
  expect_true(ortam$ux_smoke_path_within("C:\\REPO\\profile", "c:/repo/", windows = TRUE))
  expect_true(ortam$ux_smoke_path_within("C:/Repo", "c:/repo", windows = TRUE))
  expect_false(ortam$ux_smoke_path_within("C:/repo-external/profile", "c:/repo", windows = TRUE))
  expect_false(ortam$ux_smoke_path_within("/Repo/profile", "/repo", windows = FALSE))
  isaret <- file.path(yol, "sentinel")
  writeLines("operator profile", isaret)
  ortam$ux_smoke_cleanup_profile(hazir)
  expect_true(file.exists(isaret))
  dosya <- tempfile()
  writeLines("not a directory", dosya)
  withr::defer(unlink(dosya))
  expect_error(ortam$ux_smoke_browser_profile(dosya, TRUE), "could not be created", fixed = TRUE)
})

test_that("ağ smoke yalnız iki opt-in ve geçerli koşu önekiyle sabit test dizinini sunar", {
  env <- .smoke_gate_app_env()
  withr::local_dir(resolve_repo_root_for_tests())
  withr::local_envvar(MERGEN_ENABLE_UX_SMOKE = NA, MERGEN_HOST = "0.0.0.0",
                     MERGEN_ALLOW_NETWORK_UX_SMOKE = NA, MERGEN_UX_SMOKE_PATH = NA)
  withr::defer(env$mergen_register_ux_smoke_resource(FALSE))
  prefix <- paste0("__mergen_ux_", paste(rep("ab", 24), collapse = ""))
  expect_false(env$mergen_ux_smoke_enabled())
  Sys.setenv(MERGEN_ENABLE_UX_SMOKE = "true")
  expect_false(env$mergen_ux_smoke_enabled())
  Sys.setenv(MERGEN_UX_SMOKE_PATH = prefix)
  expect_false(env$mergen_ux_smoke_enabled())
  Sys.setenv(MERGEN_ALLOW_NETWORK_UX_SMOKE = "true")
  expect_true(env$mergen_ux_smoke_enabled())
  expect_true(env$mergen_register_ux_smoke_resource())
  expect_false("smoke" %in% names(shiny::resourcePaths()))
  expect_identical(normalizePath(shiny::resourcePaths()[[prefix]], winslash = "/"),
                   normalizePath("tests/smoke", winslash = "/"))
  expect_false("directory" %in% names(formals(env$mergen_register_ux_smoke_resource)))
  for (bad in c("", "/", "smoke", "www", "../tests/smoke", "/tmp", "a/b", "..",
                paste0(prefix, "/"), paste0(prefix, "\n"), toupper(prefix),
                paste(rep("a", 1000), collapse = ""))) {
    Sys.setenv(MERGEN_UX_SMOKE_PATH = bad)
    expect_false(env$mergen_ux_smoke_enabled(), info = bad)
    expect_false(env$mergen_register_ux_smoke_resource())
    expect_false(any(startsWith(as.character(names(shiny::resourcePaths())), "__mergen_ux_")))
  }
  Sys.setenv(MERGEN_UX_SMOKE_PATH = prefix)
  expect_true(env$mergen_register_ux_smoke_resource())
  next_prefix <- sub("ab$", "cd", prefix)
  Sys.setenv(MERGEN_UX_SMOKE_PATH = next_prefix)
  expect_true(env$mergen_register_ux_smoke_resource())
  expect_false(prefix %in% names(shiny::resourcePaths()))
  Sys.setenv(MERGEN_ENABLE_UX_SMOKE = "false")
  expect_false(env$mergen_register_ux_smoke_resource())
  expect_false(next_prefix %in% names(shiny::resourcePaths()))
  expect_true(is.na(env$mergen_ux_smoke_prefix(c(prefix, prefix))))
  expect_true(is.na(env$mergen_ux_smoke_prefix(NA_character_)))
})
