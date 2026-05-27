# ==============================================================================
# Dosya Yolu: tests/testthat/test-validation-doctor-proof-status-contract.R
# Açıklama: Validation doctor çıktısının gerçek doğrulama kanıtı gibi
#           yorumlanmamasını korur. Doctor ağır gate'leri çalıştırmaz; yalnızca
#           hangi komutun neyi kanıtladığını ve neyi kanıtlamadığını açıklar.
# ==============================================================================

.validation_doctor_proof_repo_root <- function() {
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

  stop("Validation doctor proof-status contract repo kökü bulunamadı.", call. = FALSE)
}

.validation_doctor_proof_is_absolute_path <- function(path) {
  grepl("^([A-Za-z]:|/|\\\\\\\\)", as.character(path)[1])
}

.validation_doctor_proof_read_text <- function(...) {
  parts <- c(...)

  path <- if (length(parts) == 1L &&
              .validation_doctor_proof_is_absolute_path(parts[[1]])) {
    parts[[1]]
  } else {
    file.path(.validation_doctor_proof_repo_root(), ...)
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

.validation_doctor_proof_expect_all <- function(text, tokens, label) {
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

testthat::test_that("validation doctor explicitly says its own artifact is not validation evidence", {
  doctor <- .validation_doctor_proof_read_text(
    "tests",
    "scripts",
    "validation_doctor.R"
  )

  .validation_doctor_proof_expect_all(
    doctor,
    c(
      "Doctor execution status:",
      "doctor_execution_notes <- c(",
      "NOT RUN: This doctor did not run bash tools/ai_validate.sh cloud-quick.",
      "NOT RUN: This doctor did not run bash tools/ai_validate.sh quick.",
      "NOT RUN: This doctor did not run bash tools/ai_validate.sh full --boot-smoke.",
      "NOT RUN: This doctor did not run MERGEN_REQUIRE_BROWSER_UX_SMOKE=true bash tools/ai_validate.sh full --boot-smoke.",
      "NOT RUN: This doctor did not source tests/scripts/run_vm_preflight_real.R.",
      "NOT RUN: This doctor did not source tests/scripts/run_vm_encoding_preflight_real.R.",
      "NOT RUN: This doctor did not source tests/scripts/run_fragile_flow_manual_preflight.R.",
      "Use the listed commands as separate evidence gates; the doctor artifact is guidance, not validation evidence.",
      "\"doctor_runs_heavy_checks\"",
      "\"validation_execution_status\"",
      "not_run_by_validation_doctor",
      "\"doctor_execution_notes\""
    ),
    "Validation doctor kendi çıktı/artifact sınırını açıkça belirtmiyor:"
  )
})

testthat::test_that("validation doctor proof-status artifact is emitted and remains secret-safe", {
  rscript <- Sys.which("Rscript")
  skip_if_not(nzchar(rscript))

  repo_root <- .validation_doctor_proof_repo_root()
  artifact_root <- tempfile("validation-doctor-proof-status-")
  dir.create(artifact_root, recursive = TRUE, showWarnings = FALSE)

  secret_values <- c(
    "fake_master_key_for_doctor_contract_abcdefghijklmnopqrstuvwxyz",
    "fake_llm_key_for_doctor_contract_abcdefghijklmnopqrstuvwxyz",
    "fake_db_password_for_doctor_contract_abcdefghijklmnopqrstuvwxyz",
    "fake_sso_secret_for_doctor_contract_abcdefghijklmnopqrstuvwxyz",
    "Server=tcp;Uid=fake_user;Pwd=fake_pwd_for_doctor_contract_abcdefghijklmnopqrstuvwxyz",
    "https://sso.example.invalid/realms/fake-sensitive-realm-contract",
    "https://llm.example.invalid/v1/fake-sensitive-endpoint-contract",
    "C:/Sensitive/Browser/bin/fake-chrome.exe"
  )

  secret_env <- c(
    AI_KEYS_MASTER = secret_values[[1]],
    LOCAL_LLM_API_KEY = secret_values[[2]],
    DB_PASSWORD = secret_values[[3]],
    SSO_CLIENT_SECRET = secret_values[[4]],
    DB_DSN = secret_values[[5]],
    SSO_KEYCLOAK_URL = secret_values[[6]],
    LOCAL_LLM_ENDPOINT = secret_values[[7]],
    MERGEN_BROWSER_BIN = secret_values[[8]],
    DB_CLIENT_ENCODING = "WINDOWS-1254",
    DB_NAME_ENCODING = "WINDOWS-1254",
    SSO_ENABLED = "TRUE",
    MERGEN_REQUIRE_BROWSER_UX_SMOKE = "TRUE",
    MERGEN_PREFLIGHT_CHECK_FILE_STORE = "TRUE",
    MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST = "TRUE"
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
          "all",
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

  artifact_text <- .validation_doctor_proof_read_text(artifact_files[[1]])
  combined <- paste(c(output, artifact_text), collapse = "\n")

  leaked <- secret_values[vapply(
    secret_values,
    function(value) grepl(value, combined, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    leaked,
    character(0),
    info = paste(
      "Validation doctor proof-status çıktısı raw secret/env değeri sızdırdı:",
      paste(leaked, collapse = ", ")
    )
  )

  .validation_doctor_proof_expect_all(
    combined,
    c(
      "Summary artifact:",
      "Doctor execution status:",
      "doctor_runs_heavy_checks",
      "validation_execution_status",
      "not_run_by_validation_doctor",
      "doctor_execution_notes",
      "value=<hidden>",
      "bash tools/ai_validate.sh cloud-quick",
      "bash tools/ai_validate.sh quick",
      "bash tools/ai_validate.sh full --boot-smoke",
      "MERGEN_REQUIRE_BROWSER_UX_SMOKE=true bash tools/ai_validate.sh full --boot-smoke",
      "source(\"tests/scripts/run_vm_preflight_real.R\", encoding = \"UTF-8\")",
      "Sys.setenv(MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=\"TRUE\"); source(\"tests/scripts/run_vm_encoding_preflight_real.R\", encoding = \"UTF-8\")",
      "source(\"tests/scripts/run_fragile_flow_manual_preflight.R\", encoding = \"UTF-8\")"
    ),
    "Validation doctor proof-status runtime çıktısı/artifact alanları eksik:"
  )
})

testthat::test_that("ai_repo_check quick profile includes validation doctor proof-status contract", {
  repo_check <- .validation_doctor_proof_read_text(
    "tests",
    "scripts",
    "ai_repo_check.R"
  )

  .validation_doctor_proof_expect_all(
    repo_check,
    c(
      "tests/testthat/test-validation-doctor-contract.R",
      "tests/testthat/test-validation-doctor-proof-status-contract.R",
      "\"focused contract tests\""
    ),
    "ai_repo_check quick kapsamı validation doctor proof-status sözleşmesini içermiyor:"
  )
})