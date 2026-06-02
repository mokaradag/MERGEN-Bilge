# ==============================================================================
# Dosya Yolu: tests/testthat/test-log-redact-private-key-stt-behavior.R
# Açıklama: redact_sensitive_text() için iki ek sızıntı sınırını davranışsal
#           kapsar:
#           - PEM özel anahtar blokları (-----BEGIN ... PRIVATE KEY-----) maskelenir,
#             ancak public CERTIFICATE blokları (sır değil) korunur,
#           - LOCAL_STT_API_KEY env değeri maskelenir (LOCAL_TTS_API_KEY ile eş).
#           Sır-benzeri değerler kaynakta literal taşımamak için runtime üretilir.
# ==============================================================================

.find_redact_pk_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", "..")),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "R"))) {
      return(candidate)
    }
  }

  stop("PEM/STT redaksiyon testi repo kökünü bulamadı.", call. = FALSE)
}

repo_root_redact_pk <- .find_redact_pk_repo_root()

source(
  file.path(repo_root_redact_pk, "R", "utils_log_redact.R"),
  encoding = "UTF-8",
  local = globalenv()
)

test_that("PEM özel anahtar bloğu (çok satırlı) maskelenir", {
  body <- paste0("FAKEKEY", "BODYabc", "123def")
  for (label in c("RSA PRIVATE KEY", "PRIVATE KEY", "EC PRIVATE KEY")) {
    pem <- paste0("-----BEGIN ", label, "-----\n", body, "\n-----END ", label, "-----")
    out <- redact_sensitive_text(pem)
    expect_false(grepl(body, out, fixed = TRUE), info = label)
    expect_true(grepl("<private-key-redacted>", out, fixed = TRUE), info = label)
  }
})

test_that("public CERTIFICATE bloğu maskelenmez (sır değildir, debug için korunur)", {
  cert <- paste0(
    "-----BEGIN CERTIFICATE-----\n",
    "MIICpublicCertContent\n",
    "-----END CERTIFICATE-----"
  )
  expect_identical(redact_sensitive_text(cert), cert)
})

test_that("LOCAL_STT_API_KEY env değeri maskelenir ve listede tanımlıdır", {
  expect_true("LOCAL_STT_API_KEY" %in% .redact_env_var_names())

  fake <- paste0("stt-key-", "ZYXW98765432abcd")
  old <- Sys.getenv("LOCAL_STT_API_KEY", unset = NA)
  Sys.setenv(LOCAL_STT_API_KEY = fake)
  on.exit({
    if (is.na(old)) Sys.unsetenv("LOCAL_STT_API_KEY") else Sys.setenv(LOCAL_STT_API_KEY = old)
  }, add = TRUE)

  out <- redact_sensitive_text(paste0("STT cagrisi anahtar ile: ", fake))
  expect_false(grepl(fake, out, fixed = TRUE))
  expect_true(grepl("<LOCAL_STT_API_KEY:redacted>", out, fixed = TRUE))
})
