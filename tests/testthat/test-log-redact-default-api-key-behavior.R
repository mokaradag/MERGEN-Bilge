# ==============================================================================
# Dosya Yolu: tests/testthat/test-log-redact-default-api-key-behavior.R
# Açıklama: redact_sensitive_text()'in kurumsal varsayılan API anahtarını
#           (MERGEN_DEFAULT_API_KEY) loglardan maskelediğini doğrular. CLAUDE.md
#           gereği bu değer asla loglanmamalıdır; prose içinde çıplak geçtiğinde
#           key-value deseni yakalamaz, bu yüzden env-değer redaksiyonuna açıkça
#           eklenmiştir. Env değişkeni kaydedilip geri yüklenir; sır-benzeri değer
#           kaynakta literal taşımamak için runtime üretilir.
# ==============================================================================

.find_redact_defkey_repo_root <- function() {
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

  stop("Varsayılan anahtar redaksiyon testi repo kökünü bulamadı.", call. = FALSE)
}

repo_root_redact_defkey <- .find_redact_defkey_repo_root()

source(
  file.path(repo_root_redact_defkey, "R", "utils_log_redact.R"),
  encoding = "UTF-8",
  local = globalenv()
)

# MERGEN_DEFAULT_API_KEY'i geçici ayarlayıp güvenle geri yükleyen yardımcı.
.with_default_api_key_env <- function(value, code) {
  old <- Sys.getenv("MERGEN_DEFAULT_API_KEY", unset = NA)
  Sys.setenv(MERGEN_DEFAULT_API_KEY = value)
  on.exit({
    if (is.na(old)) {
      Sys.unsetenv("MERGEN_DEFAULT_API_KEY")
    } else {
      Sys.setenv(MERGEN_DEFAULT_API_KEY = old)
    }
  }, add = TRUE)
  force(code)
}

test_that("kurumsal varsayılan API anahtarı çıplak prose içinde maskelenir", {
  fake <- paste0("corp-default-", "key-", "ABCDEFGH12345678")

  .with_default_api_key_env(fake, {
    line <- paste0("AI Uzman: varsayilan kurum anahtariyla devam: ", fake)
    out <- redact_sensitive_text(line)

    expect_false(grepl(fake, out, fixed = TRUE))
    expect_true(grepl("<MERGEN_DEFAULT_API_KEY:redacted>", out, fixed = TRUE))
  })
})

test_that("varsayılan anahtar adı redaksiyon env listesinde tanımlıdır", {
  # Sözleşme: liste, anahtarı açıkça içermelidir (gelecekte yanlışlıkla
  # çıkarılmasına karşı koruma).
  expect_true("MERGEN_DEFAULT_API_KEY" %in% .redact_env_var_names())
})

test_that("env değeri ayarlı değilken normal metin bozulmaz", {
  old <- Sys.getenv("MERGEN_DEFAULT_API_KEY", unset = NA)
  Sys.unsetenv("MERGEN_DEFAULT_API_KEY")
  on.exit({
    if (!is.na(old)) Sys.setenv(MERGEN_DEFAULT_API_KEY = old)
  }, add = TRUE)

  plain <- "Sıradan bir log satırı, sır yok."
  expect_identical(redact_sensitive_text(plain), plain)
})
