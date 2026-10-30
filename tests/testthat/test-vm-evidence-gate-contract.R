# ==============================================================================
# Dosya Yolu: tests/testthat/test-vm-evidence-gate-contract.R
# Açıklama: tests/scripts/run_vm_evidence_gate.R tek tekrarlanabilir preflight
#           doğrulama yolunun yapısal sözleşmesini dondurur. Ağır adımları
#           ÇALIŞTIRMAZ: kapı betiğini parse/statik düzeyde ve hafif yardımcı
#           davranış düzeyinde doğrular. Gerçek DB, LLM, tarayıcı, SSO yok.
#
#           Korunan sözleşmeler:
#             - Betik parse edilir, quit() çağırmaz (source-safe).
#             - Dondurulmuş kanıt adım listesi bilinçli güncelleme gerektirir.
#             - VM-yalnız kapılar (vm_preflight_real, db_encoding_preflight,
#               renv_status) yalnızca vm profilinde zorunludur.
#             - Secret-güvenlik: metadata yardımcı + redaksiyon yardımcı +
#               secret_policy alanı mevcuttur; evidence.json ham değer taşımaz.
#             - Adımlar temiz çocuk R oturumlarında koşulur (Rscript --vanilla).
#             - Artifact yolu artifacts/vm-evidence altındadır.
#             - DB kodlama adımı transactional write-probe bayrağını açar.
# ==============================================================================

.evg_repo_root <- resolve_repo_root_for_tests()
.evg_script_path <- file.path(.evg_repo_root, "tests", "scripts", "run_vm_evidence_gate.R")
.evg_wrapper_path <- file.path(.evg_repo_root, "tools", "vm_evidence_gate.sh")

# Windows-güvenli bayt okuyucu: Türkçe yorumlu dosyalar için byte-safe tarama.
.evg_read_text <- function(path) {
  raw_bytes <- readBin(path, what = "raw", n = file.info(path)$size)
  text <- rawToChar(raw_bytes)
  Encoding(text) <- "UTF-8"
  iconv(text, from = "UTF-8", to = "UTF-8", sub = "byte")
}

test_that("kanit kapisi betigi mevcuttur ve parse edilir", {
  expect_true(file.exists(.evg_script_path))
  expect_true(file.exists(.evg_wrapper_path))

  parsed <- tryCatch(
    parse(file = .evg_script_path, encoding = "UTF-8"),
    error = function(e) NULL
  )
  expect_false(is.null(parsed), info = "run_vm_evidence_gate.R parse edilebilir olmalıdır.")
})

test_that("kanit kapisi quit() cagirmaz ve stop() ile biter (source-safe)", {
  text <- .evg_read_text(.evg_script_path)

  # Yorum satırları taramadan önce çıkarılır; açıklayıcı yorumlar yanlış
  # pozitif üretmemelidir (repo kuralı).
  code_lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  code_lines <- code_lines[!grepl("^\\s*#", code_lines, perl = TRUE)]
  code_text <- paste(code_lines, collapse = "\n")

  expect_false(
    grepl("\\bquit\\s*\\(", code_text, perl = TRUE),
    info = "Kapı betiği quit() çağırmamalıdır; source(...) ile güvenli kalmalıdır."
  )
  expect_true(
    grepl("stop(", code_text, fixed = TRUE),
    info = "Zorunlu adım başarısızlığı stop() ile bildirilmelidir."
  )
})

# Dondurulmuş kanıt adımları: ekleme/çıkarma bilinçli güncelleme gerektirir ve
# docs ile birlikte yapılmalıdır.
.evg_expected_steps <- c(
  "env_config",
  "parse_sanity",
  "app_boot_smoke",
  "full_testthat",
  "maintainability_report",
  "frontend_ratchet",
  "seam_doctor",
  "source_manifest_contracts",
  "ui_asset_manifest_contracts",
  "browser_ux_smoke",
  "vm_preflight_real",
  "db_encoding_preflight",
  "renv_status"
)

test_that("dondurulmus kanit adim listesi betikte tanimlidir", {
  text <- .evg_read_text(.evg_script_path)

  for (step_id in .evg_expected_steps) {
    expect_true(
      grepl(sprintf('id = "%s"', step_id), text, fixed = TRUE),
      info = sprintf("Kanıt adımı betikte tanımlı olmalıdır: %s", step_id)
    )
  }
})

test_that("VM-yalniz kapilar yalnizca vm profilinde zorunludur", {
  text <- .evg_read_text(.evg_script_path)

  # vm_preflight_real, db_encoding_preflight ve renv_status adımları
  # required_in = c("vm") taşımalıdır; cloud bunları gerekçeli SKIP eder.
  vm_only_count <- length(gregexpr('required_in = c("vm")', text, fixed = TRUE)[[1]])
  expect_gte(vm_only_count, 3L)

  expect_true(
    grepl("VM-yalniz kapi; cloud profilinde gerekceli SKIP", text, fixed = TRUE),
    info = "Cloud profili VM-yalnız adımları gerekçeli SKIP olarak raporlamalıdır."
  )
})

test_that("secret-guvenlik sozlesmesi: metadata + redaksiyon + policy alani", {
  text <- .evg_read_text(.evg_script_path)

  expect_true(
    grepl("evidence_value_metadata", text, fixed = TRUE),
    info = "Ortam değişkenleri yalnızca metadata olarak raporlanmalıdır."
  )
  expect_true(
    grepl('value = "<hidden>"', text, fixed = TRUE),
    info = "Metadata value alanı daima <hidden> olmalıdır."
  )
  expect_true(
    grepl("evidence_redact_text", text, fixed = TRUE),
    info = "Adım logları ve JSON çıktı redaksiyon yardımcısından geçmelidir."
  )
  expect_true(
    grepl("secret_policy", text, fixed = TRUE),
    info = "evidence.json secret_policy alanı taşımalıdır."
  )
})

test_that("adimlar temiz cocuk R oturumlarinda kosulur", {
  text <- .evg_read_text(.evg_script_path)

  expect_true(
    grepl("--vanilla", text, fixed = TRUE),
    info = "Çocuk oturumlar Rscript --vanilla ile koşulmalıdır."
  )
  expect_true(
    grepl("system2(", text, fixed = TRUE),
    info = "Adım izolasyonu system2 çocuk süreciyle sağlanmalıdır."
  )
})

test_that("full_testthat adimi dosya izolasyonlu crash-locator kosucusunu kullanir", {
  text <- .evg_read_text(.evg_script_path)
  isolated_runner_path <- file.path(
    .evg_repo_root,
    "tests",
    "scripts",
    "run_full_testthat_isolated.R"
  )

  expect_true(
    file.exists(isolated_runner_path),
    info = "full_testthat crash-locator betigi mevcut olmalıdır."
  )

  expect_true(
    grepl("run_full_testthat_isolated.R", text, fixed = TRUE),
    info = "VM kanıt kapısı full_testthat için dosya izolasyonlu koşucuyu kullanmalıdır."
  )

  expect_true(
    grepl("MERGEN_EVIDENCE_ARTIFACT_DIR", text, fixed = TRUE),
    info = "Çocuk adımlar artifact dizinini alt koşuculara aktarmalıdır."
  )

  isolated_text <- .evg_read_text(isolated_runner_path)

  expect_true(
    grepl("testthat::test_file", isolated_text, fixed = TRUE),
    info = "İzole koşucu testleri dosya dosya çalıştırmalıdır."
  )

  expect_true(
    grepl("RUNNING_TEST_FILE.txt", isolated_text, fixed = TRUE),
    info = "Native crash anında son çalışan test dosyası marker dosyasına yazılmalıdır."
  )
  
	expect_false(
	  grepl("normalizePath(artifact_dir", isolated_text, fixed = TRUE),
	  info = paste(
		"İzole full_testthat koşucusu artifact_dir için normalizePath kullanmamalıdır;",
		"VM UNC repo yolu non-ASCII karakter taşıyabilir."
	  )
	)

	expect_false(
	  grepl("normalizePath(path", isolated_text, fixed = TRUE),
	  info = paste(
		"İzole full_testthat koşucusu test dosyası yollarını mutlaklaştırmamalıdır;",
		"çocuk runner içine Geliştirme gibi non-ASCII mutlak repo yolu yazılmamalıdır."
	  )
	)

	expect_true(
	  grepl("r_string <- function", isolated_text, fixed = TRUE),
	  info = "Generated runner path değerleri güvenli R string quoting yardımcısından geçmelidir."
	)
})

test_that("artifact yolu ve dogrulama-kanit alanlari sabittir", {
  text <- .evg_read_text(.evg_script_path)

  expect_true(
    grepl('file.path("artifacts", "vm-evidence"', text, fixed = TRUE),
    info = "Kanıt artifact'ı artifacts/vm-evidence altına yazılmalıdır."
  )
  expect_true(
    grepl("ran_by_vm_evidence_gate", text, fixed = TRUE),
    info = "validation_execution_status alanı kapıya özgü olmalıdır."
  )
  expect_true(
    grepl("proof_boundary_notes", text, fixed = TRUE),
    info = "Kanıt sınırı notları evidence.json içinde olmalıdır."
  )
  expect_true(
    grepl("does_not_prove", text, fixed = TRUE),
    info = "Her adım neyi KANITLAMADIĞINI da bildirmelidir."
  )
})

test_that("tarayici smoke adimi yalnizca UX_SMOKE_DONE:PASS kanitiyla passed sayilir", {
  text <- .evg_read_text(.evg_script_path)

  expect_true(
    grepl("UX_SMOKE_DONE:PASS", text, fixed = TRUE),
    info = "Tarayıcı smoke adımı gerçek PASS işaretini aramalıdır; exit 0 tek başına kanıt değildir."
  )
  expect_true(
    grepl("ux_smoke_pass_marker", text, fixed = TRUE),
    info = "PASS işareti gözlemi evidence.json detail alanına yazılmalıdır."
  )
})

test_that("db kodlama adimi transactional write-probe bayragini acar", {
  text <- .evg_read_text(.evg_script_path)

  expect_true(
    grepl('MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST = "TRUE"', text, fixed = TRUE),
    info = "DB kodlama preflight adımı yazma probunu açmalıdır."
  )
  expect_true(
    grepl("run_vm_encoding_preflight_real.R", text, fixed = TRUE),
    info = "DB kodlama adımı mevcut kodlama preflight betiğini kullanmalıdır."
  )
  expect_true(
    grepl("run_vm_preflight_real.R", text, fixed = TRUE),
    info = "VM preflight adımı mevcut gerçek preflight betiğini kullanmalıdır."
  )
})

test_that("sarmalayici betik repo kokunden Rscript ile kapiyi cagirir", {
  text <- .evg_read_text(.evg_wrapper_path)

  expect_true(grepl("set -euo pipefail", text, fixed = TRUE))
  expect_true(grepl("run_vm_evidence_gate.R", text, fixed = TRUE))
  expect_true(
    grepl("command -v Rscript", text, fixed = TRUE),
    info = "Sarmalayıcı Rscript yokluğunda açık hata vermelidir."
  )
})

test_that("kanit kapisi betigi ascii-guvenli kalir (sessiz kirpilma korumasi)", {
  # Operasyonel giriş noktası betikleri POSIX/C veya Windows/Türkçe locale
  # altında source(...) edilirken non-ASCII içerik sessizce kırpılabilir ve
  # kapı HİÇ ÇALIŞMADAN exit 0 verebilir (.Rprofile / tools/renv_snapshot.R
  # ile aynı kural). Bu test kısıtı çalıştırılabilir kılar: kapı betiğine
  # Türkçe özel karakter eklemek yerine diakritiksiz Türkçe yorum kullanın.
  raw_bytes <- readBin(.evg_script_path, what = "raw", n = file.info(.evg_script_path)$size)
  non_ascii_count <- sum(as.integer(raw_bytes) > 127L)

  expect_identical(
    non_ascii_count,
    0L,
    info = paste(
      "run_vm_evidence_gate.R ASCII-güvenli kalmalıdır;",
      non_ascii_count,
      "non-ASCII bayt bulundu. POSIX/C locale altında source() bu dosyayı",
      "sessizce kırpar ve kapı hiç çalışmadan exit 0 verebilir.",
      "Diakritiksiz Türkçe yorum kullanın (orn. 'dogrulama', 'kanit')."
    )
  )
})

test_that("gecersiz profil degeri acik hata uretir (hafif davranis kontrolu)", {
  # Yalnızca profil doğrulama dalını tetikler; hiçbir adım koşulmaz.
  rscript_bin <- file.path(R.home("bin"), "Rscript")
  if (.Platform$OS.type == "windows") rscript_bin <- paste0(rscript_bin, ".exe")
  skip_if_not(file.exists(rscript_bin), "Rscript bulunamadı.")

  # Çocuk süreç parent R oturumunun çalışma dizinini miras alır.
  # Bu nedenle repo köküne parent süreçte geçilir; çocuk runner içine
  # "Geliştirme" gibi non-ASCII karakter içeren mutlak repo yolu yazılmaz.
  old_wd <- getwd()
  setwd(.evg_repo_root)
  on.exit(setwd(old_wd), add = TRUE)

  path_for_r <- function(path) {
    gsub("\\", "/", path, fixed = TRUE)
  }

  out_stdout_log <- tempfile(fileext = ".stdout.log")
  out_stderr_log <- tempfile(fileext = ".stderr.log")
  out_message_log <- tempfile(fileext = ".message.log")
  runner_file <- tempfile(pattern = "evg_invalid_profile_", fileext = ".R")

  runner_lines <- c(
    'Sys.setenv(MERGEN_EVIDENCE_PROFILE = "bozuk_profil")',
    sprintf(
      '.evg_message_log <- "%s"',
      path_for_r(out_message_log)
    ),
    "tryCatch(",
    '  source("tests/scripts/run_vm_evidence_gate.R", encoding = "UTF-8"),',
    "  error = function(e) {",
    "    writeLines(conditionMessage(e), .evg_message_log, useBytes = TRUE)",
    "    stop(e)",
    "  }",
    ")"
  )
  writeLines(runner_lines, runner_file, useBytes = TRUE)

  status <- suppressWarnings(system2(
    rscript_bin,
    args = c("--vanilla", runner_file),
    stdout = out_stdout_log,
    stderr = out_stderr_log
  ))

  expect_false(identical(status, 0L), info = "Geçersiz profil sıfır-dışı çıkış üretmelidir.")

  log_text <- paste(
    vapply(
      c(out_message_log, out_stdout_log, out_stderr_log),
      function(path) {
        if (!file.exists(path) || isTRUE(file.info(path)$size == 0)) {
          ""
        } else {
          .evg_read_text(path)
        }
      },
      character(1)
    ),
    collapse = "\n"
  )

  expect_true(
    grepl("MERGEN_EVIDENCE_PROFILE", log_text, fixed = TRUE, useBytes = TRUE),
    info = paste(
      "Hata mesajı geçersiz profil değişkenini açıkça adlandırmalıdır.",
      "Çocuk süreç logu:",
      log_text
    )
  )

  unlink(c(out_stdout_log, out_stderr_log, out_message_log, runner_file), force = TRUE)
})
test_that("browser adimi external ortamda VM kosucusunu secer, kaynak PASS sabiti kanit degildir", {
  env <- new.env(parent = globalenv())
  expressions <- parse(file = .evg_script_path, encoding = "UTF-8")
  for (e in expressions) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) &&
        as.character(e[[2]]) %in% c("run_step_browser_ux_smoke", "evidence_env_flag_true", "evidence_browser_required")) eval(e, env)
  }
  withr::local_envvar(MERGEN_BROWSER_UX_BASE_URL = NA, MERGEN_BROWSER_BIN = NA,
                     MERGEN_REQUIRE_BROWSER_UX_SMOKE = NA)
  log <- tempfile()
  withr::defer(unlink(log))
  selected <- NULL
  env$run_step_simple_child <- function(step_id, body_lines, ...) {
    selected <<- body_lines
    list(ok = TRUE, log_file = log, detail = list())
  }
  env$evidence_read_text_file_safe <- function(path) paste(readLines(path, warn = FALSE), collapse = "\n")
  writeLines("OK: rendered #status is UX_SMOKE_DONE:PASS.", log)
  expect_true(env$run_step_browser_ux_smoke()$ok)
  expect_match(selected, "tests/scripts/ai_browser_ux_smoke.R", fixed = TRUE)
  Sys.setenv(MERGEN_BROWSER_UX_BASE_URL = "https://app.example.invalid/base")
  expect_true(env$run_step_browser_ux_smoke()$ok)
  expect_match(selected, "tests/scripts/run_vm_browser_ux_smoke.R", fixed = TRUE)
  for (wrong in c("", "HTTP 200", "UX_SMOKE_DONE:PASS", "SKIP",
                  "FAILED: rendered #status did not reach UX_SMOKE_DONE:PASS", "<script>UX_SMOKE_DONE:PASS</script>")) {
    writeLines(wrong, log)
    result <- env$run_step_browser_ux_smoke()
    expect_false(result$ok)
    expect_false(isTRUE(result$skipped))
  }
  Sys.unsetenv("MERGEN_BROWSER_UX_BASE_URL")
  writeLines("SKIP: no browser", log)
  expect_true(env$run_step_browser_ux_smoke()$skipped)
})

test_that("zorunlu browser basarisizligi veya atlanmasi ust kapiyi dusurur", {
  expressions <- parse(file = .evg_script_path, encoding = "UTF-8")
  loop <- Filter(function(e) is.call(e) && identical(e[[1]], as.name("for")) &&
                   identical(e[[2]], as.name("spec")), as.list(expressions))
  expect_length(loop, 1L)
  stop_branch <- Filter(function(e) is.call(e) && identical(e[[1]], as.name("if")) &&
                          identical(e[[2]], quote(identical(overall_status, "failed"))), as.list(expressions))
  expect_length(stop_branch, 1L)
  withr::local_envvar(MERGEN_BROWSER_UX_BASE_URL = NA, MERGEN_BROWSER_BIN = NA,
                     MERGEN_REQUIRE_BROWSER_UX_SMOKE = NA)
  env <- new.env(parent = globalenv())
  definitions <- c("%||%", "evidence_env_flag_true", "evidence_browser_required", "evidence_step_specs")
  for (e in expressions) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) &&
        as.character(e[[2]]) %in% definitions) eval(e, env)
  }
  env$profile_effective <- "cloud"
  env$full_evidence <- FALSE
  env$cat <- function(...) invisible(NULL)
  env$evidence_redact_text <- identity
  env$evidence_json_path <- "test-evidence.json"
  result <- list(ok = FALSE, detail = list(ux_smoke_pass_marker = FALSE))
  env$evidence_step_runners <- setNames(lapply(env$evidence_step_specs, function(spec) {
    if (identical(spec$id, "browser_ux_smoke")) function() result else function() list(ok = TRUE)
  }), vapply(env$evidence_step_specs, function(spec) spec$id, character(1)))
  aggregate <- function(filter = character(0)) {
    env$step_results <- list()
    env$steps_filter <- filter
    eval(loop[[1]], env)
    for (e in expressions) {
      if (is.call(e) && identical(e[[1]], as.name("<-")) &&
          as.character(e[[2]]) %in% c("failed_required", "failed_optional", "overall_status")) eval(e, env)
    }
    expect_length(env$step_results, 13L)
    env$overall_status
  }
  # Tarayici acikca istenmemisse opsiyonel davranis korunur.
  expect_identical(aggregate(), "passed")
  expect_false(env$step_results$browser_ux_smoke$required)
  for (settings in list(c(MERGEN_REQUIRE_BROWSER_UX_SMOKE = "true"),
                        c(MERGEN_BROWSER_BIN = "missing-browser"),
                        c(MERGEN_BROWSER_UX_BASE_URL = "https://app.example.invalid/base"))) {
    withr::with_envvar(settings, {
      expect_identical(aggregate(), "failed")
      expect_true(env$step_results$browser_ux_smoke$required)
      expect_error(eval(stop_branch[[1]], env), "VM kanit kapisi basarisiz: browser_ux_smoke", fixed = TRUE)
    })
  }
  Sys.setenv(MERGEN_REQUIRE_BROWSER_UX_SMOKE = "true")
  result <- list(ok = FALSE, skipped = TRUE)
  expect_identical(aggregate(), "failed")
  expect_identical(aggregate("env_config"), "failed")
  expect_identical(env$step_results$browser_ux_smoke$status, "skipped")
  result <- list(ok = TRUE, detail = list(ux_smoke_pass_marker = TRUE))
  expect_identical(aggregate(), "passed")
  expect_no_error(eval(stop_branch[[1]], env))
  env$full_evidence <- TRUE
  expect_identical(aggregate(), "failed") # Cloud VM-only SKIP tam kanit olamaz.
  env$profile_effective <- "vm"
  expect_identical(aggregate(), "passed")
  expect_true(all(vapply(env$step_results, function(r) r$required, logical(1))))
  expect_true(all(vapply(env$step_results, function(r) identical(r$status, "passed"), logical(1))))
  result <- list(ok = FALSE, skipped = TRUE)
  expect_identical(aggregate(), "failed")
})


test_that("acik tam workflow kalici filtreyi yok sayar, gelistirici filtresi korunur", {
  expressions <- parse(file = .evg_script_path, encoding = "UTF-8")
  env <- new.env(parent = globalenv())
  for (e in expressions) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) &&
        identical(e[[2]], as.name("evidence_load_repo_renviron"))) eval(e, env)
  }
  path <- withr::local_tempfile()
  writeLines("MERGEN_EVIDENCE_STEPS=browser_ux_smoke", path)
  withr::local_envvar(MERGEN_EVIDENCE_STEPS = NA)
  expect_true(env$evidence_load_repo_renviron(path))
  expect_identical(Sys.getenv("MERGEN_EVIDENCE_STEPS"), "browser_ux_smoke")
  args <- character()
  env$commandArgs <- function(...) args
  select <- function() {
    for (e in expressions) {
      if (is.call(e) && identical(e[[1]], as.name("<-")) &&
          as.character(e[[2]]) %in% c("full_evidence", "steps_filter_raw", "steps_filter")) eval(e, env)
    }
    env$steps_filter
  }
  expect_identical(select(), "browser_ux_smoke")
  args <- "--full"
  expect_identical(select(), character())
  expect_true(env$full_evidence)
  expect_identical(readLines(path), "MERGEN_EVIDENCE_STEPS=browser_ux_smoke")
})

test_that("tam kanit cocuklarinda test araligi kalkar ve File Store zorunludur", {
  expressions <- parse(file = .evg_script_path, encoding = "UTF-8")
  env <- new.env(parent = globalenv())
  env$run_step_env_config <- env$run_step_browser_ux_smoke <- env$run_step_renv_status <- function() NULL
  observed <- NULL
  env$run_step_simple_child <- function(step_id, body_lines, extra_env = character()) {
    observed <<- extra_env
  }
  for (e in expressions) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) &&
        identical(e[[2]], as.name("evidence_step_runners"))) eval(e, env)
  }
  withr::local_envvar(MERGEN_TESTTHAT_START_INDEX = NA, MERGEN_TESTTHAT_END_INDEX = NA,
                     MERGEN_PREFLIGHT_CHECK_FILE_STORE = NA)
  config <- withr::local_tempfile()
  writeLines(c("MERGEN_TESTTHAT_START_INDEX=2", "MERGEN_TESTTHAT_END_INDEX=3",
               "MERGEN_PREFLIGHT_CHECK_FILE_STORE=FALSE"), config)
  readRenviron(config)
  for (full in c(FALSE, TRUE)) {
    env$full_evidence <- full
    env$evidence_step_runners$full_testthat()
    if (full) {
      expect_identical(observed[["MERGEN_TESTTHAT_START_INDEX"]], "")
      expect_identical(observed[["MERGEN_TESTTHAT_END_INDEX"]], "")
    } else expect_identical(observed, c(TZ = "UTC"))
    env$evidence_step_runners$vm_preflight_real()
    expect_identical(observed, if (full) c(MERGEN_PREFLIGHT_CHECK_FILE_STORE = "TRUE") else character())
  }
  expect_identical(Sys.getenv("MERGEN_TESTTHAT_START_INDEX"), "2")
  expect_identical(Sys.getenv("MERGEN_TESTTHAT_END_INDEX"), "3")
  expect_identical(Sys.getenv("MERGEN_PREFLIGHT_CHECK_FILE_STORE"), "FALSE")
})

test_that("istenen browser uzun testlerden once, 13 adim korunarak kosulur", {
  expressions <- parse(file = .evg_script_path, encoding = "UTF-8")
  env <- new.env(parent = globalenv())
  env$evidence_browser_required <- function() TRUE
  for (e in expressions) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) &&
        identical(e[[2]], as.name("evidence_step_specs"))) eval(e, env)
    if (is.call(e) && identical(e[[1]], as.name("if")) &&
        identical(e[[2]], quote(evidence_browser_required()))) eval(e, env)
  }
  ids <- vapply(env$evidence_step_specs, function(spec) spec$id, character(1))
  expect_length(ids, 13L)
  expect_setequal(ids, .evg_expected_steps)
  expect_identical(ids[[1]], "browser_ux_smoke")
  expect_lt(match("browser_ux_smoke", ids), match("full_testthat", ids))
})

test_that("bosluk redaksiyonu PASS satirini veya JSON yapisini bozmaz", {
  env <- new.env(parent = globalenv())
  for (e in parse(file = .evg_script_path, encoding = "UTF-8")) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) &&
        as.character(e[[2]]) %in% c("%||%", "evidence_redact_text")) eval(e, env)
  }
  withr::local_envvar(MERGEN_BROWSER_UX_BASE_URL = " \t ", MERGEN_UX_SMOKE_PATH = "\n",
                     MERGEN_BROWSER_UX_PROFILE_DIR = "C:\\Users\\operator\\SmokeProfile")
  marker <- "OK: rendered #status is UX_SMOKE_DONE:PASS."
  expect_identical(env$evidence_redact_text(marker), marker)
  json <- jsonlite::toJSON(list(status = marker, path = Sys.getenv("MERGEN_BROWSER_UX_PROFILE_DIR")), auto_unbox = TRUE, pretty = TRUE)
  clean <- env$evidence_redact_text(json)
  expect_true(jsonlite::validate(clean))
  expect_identical(jsonlite::fromJSON(clean)$status, marker)
  expect_false(grepl("operator|SmokeProfile", clean))
})
