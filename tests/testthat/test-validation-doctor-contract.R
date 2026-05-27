# ==============================================================================
# Dosya Yolu: tests/testthat/test-validation-doctor-contract.R
# Açıklama: Validation doctor betiğinin doğrulama profili ayrımını, secret-safe
#           raporlamayı ve ai_repo_check davranışını zayıflatmadan quick kapsama
#           girmesini korur.
# ==============================================================================

.validation_doctor_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", "..")),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "scripts")) &&
        dir.exists(file.path(candidate, "tools"))) {
      return(candidate)
    }
  }

  stop("Validation doctor contract repo kökü bulunamadı.", call. = FALSE)
}

.validation_doctor_is_absolute_path <- function(path) {
  grepl("^([A-Za-z]:|/|\\\\\\\\)", as.character(path)[1])
}

.validation_doctor_read_text <- function(...) {
  parts <- c(...)
  path <- if (length(parts) == 1L &&
              .validation_doctor_is_absolute_path(parts[[1]])) {
    parts[[1]]
  } else {
    file.path(.validation_doctor_repo_root(), ...)
  }

  if (!file.exists(path)) {
    stop(sprintf("Beklenen dosya bulunamadı: %s", path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  enc2utf8(gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE))
}

.validation_doctor_expect_all <- function(text, tokens, label) {
  missing <- tokens[!vapply(
    tokens,
    function(token) grepl(token, text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  testthat::expect_equal(
    missing,
    character(0),
    info = paste(label, paste(missing, collapse = ", "))
  )
}

testthat::test_that("validation doctor script and wrapper exist with required commands", {
  doctor <- .validation_doctor_read_text("tests", "scripts", "validation_doctor.R")
  wrapper <- .validation_doctor_read_text("tools", "validation_doctor.sh")

  .validation_doctor_expect_all(
    doctor,
    c(
      "Dosya Yolu: tests/scripts/validation_doctor.R",
      "--profile",
      "cloud",
      "local",
      "vm",
      "all",
      "Browser detection without app launch",
      "Secret-safe environment summary",
      "Summary artifact:",
      "artifacts",
      "validation-doctor",
      "bash tools/ai_validate.sh cloud-quick",
      "bash tools/ai_validate.sh quick",
      "bash tools/ai_validate.sh full --boot-smoke",
      "MERGEN_REQUIRE_BROWSER_UX_SMOKE=true bash tools/ai_validate.sh full --boot-smoke",
      "source(\"tests/scripts/run_vm_preflight_real.R\", encoding = \"UTF-8\")",
      "Sys.setenv(MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=\"TRUE\"); source(\"tests/scripts/run_vm_encoding_preflight_real.R\", encoding = \"UTF-8\")",
      "source(\"tests/scripts/run_fragile_flow_manual_preflight.R\", encoding = \"UTF-8\")"
    ),
    "Validation doctor komut/kapsam sözleşmesi eksik:"
  )

  .validation_doctor_expect_all(
    wrapper,
    c(
      "Dosya Yolu: tools/validation_doctor.sh",
      "Rscript tests/scripts/validation_doctor.R",
      "set -- --profile"
    ),
    "Validation doctor wrapper sözleşmesi eksik:"
  )
})

testthat::test_that("validation doctor clearly marks cloud-quick as not runtime or VM validation", {
  doctor <- .validation_doctor_read_text("tests", "scripts", "validation_doctor.R")

  .validation_doctor_expect_all(
    doctor,
    c(
      "Cloud/AI lightweight validation",
      "KANITLAMAZ: app source smoke / full runtime / real browser / VM DB validation",
      "cloud-quick is not full runtime or VM validation",
      "Normal developer validation",
      "Runtime-sensitive validation",
      "Browser-required runtime gate",
      "Windows VM / SSO / SQL Server gate",
      "Windows VM Turkish encoding gate",
      "Manual fragile-flow evidence"
    ),
    "Validation doctor profil kanıt sınırlarını net ayırmıyor:"
  )
})

testthat::test_that("validation doctor includes blocking and warning-only guardrails", {
  doctor <- .validation_doctor_read_text("tests", "scripts", "validation_doctor.R")

  .validation_doctor_expect_all(
    doctor,
    c(
      "MERGEN_REQUIRE_BROWSER_UX_SMOKE=true",
      "fails if Chrome/Chromium/Edge is unavailable or UX_SMOKE_DONE:PASS is not produced",
      "MERGEN_PREFLIGHT_CHECK_FILE_STORE=TRUE",
      "DB_CLIENT_ENCODING=WINDOWS-1254",
      "DB_NAME_ENCODING=WINDOWS-1254",
      "MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=TRUE",
      "MERGEN_PREFLIGHT_FAIL_ON_LEGACY_MOJIBAKE=TRUE",
      "Historical mojibake scan remains warning-only",
      "run_vm_preflight_real.R",
      "run_vm_encoding_preflight_real.R",
      "run_fragile_flow_manual_preflight.R"
    ),
    "Validation doctor blocking/warning ayrımı eksik:"
  )
})

testthat::test_that("validation doctor does not call quit and keeps CLI termination safe", {
  doctor <- .validation_doctor_read_text("tests", "scripts", "validation_doctor.R")
  wrapper <- .validation_doctor_read_text("tools", "validation_doctor.sh")

  doctor_code <- gsub("(?m)^\\s*#.*$", "", doctor, perl = TRUE)
  wrapper_code <- gsub("(?m)^\\s*#.*$", "", wrapper, perl = TRUE)

  expect_false(
    grepl("quit\\s*\\(", doctor_code, perl = TRUE, useBytes = TRUE),
    info = "Validation doctor source() veya test koşullarında R oturumunu kapatmamalıdır."
  )

  expect_false(
    grepl("quit\\s*\\(", wrapper_code, perl = TRUE, useBytes = TRUE),
    info = "Validation doctor wrapper quit() çağırmamalıdır."
  )
})

testthat::test_that("validation doctor output and artifact do not leak raw secret values", {
  rscript <- Sys.which("Rscript")
  skip_if_not(nzchar(rscript))

  repo_root <- .validation_doctor_repo_root()
  artifact_root <- tempfile("validation-doctor-contract-")
  dir.create(artifact_root, recursive = TRUE, showWarnings = FALSE)

  secret_values <- c(
    "fake_master_key_abcdefghijklmnopqrstuvwxyz",
    "fake_llm_key_abcdefghijklmnopqrstuvwxyz",
    "fake_db_password_abcdefghijklmnopqrstuvwxyz",
    "fake_sso_secret_abcdefghijklmnopqrstuvwxyz",
    "Server=tcp;Uid=fake_user;Pwd=fake_pwd_abcdefghijklmnopqrstuvwxyz",
    "https://sso.example.invalid/realms/fake-sensitive-realm"
  )

  secret_env <- c(
    AI_KEYS_MASTER = secret_values[[1]],
    LOCAL_LLM_API_KEY = secret_values[[2]],
    DB_PASSWORD = secret_values[[3]],
    SSO_CLIENT_SECRET = secret_values[[4]],
    DB_DSN = secret_values[[5]],
    SSO_KEYCLOAK_URL = secret_values[[6]],
    LOCAL_LLM_ENDPOINT = "https://llm.example.invalid/v1",
    DB_CLIENT_ENCODING = "WINDOWS-1254",
    DB_NAME_ENCODING = "WINDOWS-1254"
  )

  output <- withr::with_dir(
    repo_root,
    withr::with_envvar(
      secret_env,
      system2(
        rscript,
        c(
          "tests/scripts/validation_doctor.R",
          "--profile",
          "cloud",
          "--artifact-root",
          artifact_root
        ),
        stdout = TRUE,
        stderr = TRUE
      )
    )
  )

  status <- attr(output, "status", exact = TRUE)
  expect_true(is.null(status) || identical(as.integer(status), 0L))

  artifact_files <- list.files(
    artifact_root,
    pattern = "^validation-doctor-.*\\.json$",
    full.names = TRUE
  )

  expect_length(artifact_files, 1L)

  artifact_text <- .validation_doctor_read_text(artifact_files[[1]])
  combined <- paste(c(output, artifact_text), collapse = "\n")

  leaked <- secret_values[vapply(
    secret_values,
    function(value) grepl(value, combined, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    leaked,
    character(0),
    info = paste("Validation doctor raw secret/env value sızdırdı:", paste(leaked, collapse = ", "))
  )

  .validation_doctor_expect_all(
    combined,
    c(
      "value=<hidden>",
      "\"nchar\"",
      "\"secret_like\"",
      "\"matches_windows_1254\"",
      "Summary artifact:"
    ),
    "Validation doctor secret-safe özet alanları eksik:"
  )
})

testthat::test_that("ai_repo_check behavior remains strong and includes validation doctor contract", {
  repo_check <- .validation_doctor_read_text("tests", "scripts", "ai_repo_check.R")

  .validation_doctor_expect_all(
    repo_check,
    c(
      "\"parse sanity\"",
      "\"app source smoke\"",
      "MERGEN_AI_SKIP_APP_SOURCE_SMOKE",
      "\"focused contract tests\"",
      "\"full testthat suite\"",
      "\"shiny boot smoke\"",
      "tests/scripts/ai_boot_smoke.R",
      "\"browser UX smoke\"",
      "tests/scripts/ai_browser_ux_smoke.R",
      "tests/testthat/test-validation-doctor-contract.R"
    ),
    "ai_repo_check davranışı veya validation doctor quick kapsamı eksik:"
  )

  browser_pos <- regexpr(
    "tests/scripts/ai_browser_ux_smoke.R",
    repo_check,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  boot_pos <- regexpr(
    "if (isTRUE(boot_smoke))",
    repo_check,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  expect_true(boot_pos > 0L)
  expect_true(
    browser_pos > boot_pos,
    info = "Browser UX smoke yalnızca --boot-smoke bloğunda kalmalıdır."
  )
})