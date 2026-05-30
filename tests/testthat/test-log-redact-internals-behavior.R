# ==============================================================================
# Dosya Yolu: tests/testthat/test-log-redact-internals-behavior.R
# Açıklama: R/utils_log_redact.R sır redaksiyonu iç yardımcılarının DAVRANIŞSAL
#           testleri (güvenlik sınırı): .redact_env_var_names (sır env değişken
#           izin listesi) ve .redact_literal_values (log metnindeki sır değerleri
#           token'a çevirir). Sahte sır değerleri ÇALIŞMA ZAMANINDA üretilir;
#           depoya gerçekçi sır benzeri literal yazılmaz. Saf base R.
# ==============================================================================

.logredactint_source_once <- function() {
  if (exists(".redact_literal_values", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists(".redact_env_var_names", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "utils_log_redact.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# Çevre değişkenini kaydet, ayarla, fonksiyonu çalıştır ve eski haline döndür.
# Sonuç hesaplandıktan SONRA geri yükleme yapılır; böylece sızıntı olmaz.
.logredactint_with_env <- function(name, value, fn) {
  old <- Sys.getenv(name, unset = NA_character_)
  if (length(value) == 0 || is.na(value)) Sys.unsetenv(name) else do.call(Sys.setenv, stats::setNames(list(value), name))
  on.exit({
    if (is.na(old)) Sys.unsetenv(name) else do.call(Sys.setenv, stats::setNames(list(old), name))
  }, add = TRUE)
  fn()
}

# ------------------------------------------------------------------------------
# .redact_env_var_names
# ------------------------------------------------------------------------------
testthat::test_that(".redact_env_var_names bilinen sır env adlarını tekilsiz döndürür", {
  .logredactint_source_once()
  nm <- .redact_env_var_names()

  testthat::expect_type(nm, "character")
  testthat::expect_true(length(nm) > 10L)
  # Tekrarlanan ad olmamalı.
  testthat::expect_false(any(duplicated(nm)))
  # Tüm girişler boş olmayan metin.
  testthat::expect_true(all(nzchar(nm)))
  # Kritik sır adları listede.
  testthat::expect_true(all(c(
    "AI_KEYS_MASTER", "OPENAI_API_KEY", "ANTHROPIC_API_KEY",
    "CLAUDE_CODE_API_KEY", "DB_PASSWORD", "SSO_CLIENT_SECRET"
  ) %in% nm))
})

# ------------------------------------------------------------------------------
# .redact_literal_values
# ------------------------------------------------------------------------------
testthat::test_that(".redact_literal_values uzun sır değerini token ile maskeler", {
  .logredactint_source_once()
  # Sahte değer çalışma zamanında üretilir (>= 8 karakter), depoya literal yazılmaz.
  fake <- paste0("MERGENFAKE", strrep("9", 14))

  out <- .logredactint_with_env("OPENAI_API_KEY", fake, function() {
    .redact_literal_values(paste0("istek key=", fake, " bitti"))
  })

  testthat::expect_identical(out, "istek key=<OPENAI_API_KEY:redacted> bitti")
  # Ham sır değeri çıktıda kalmamalı.
  testthat::expect_false(grepl(fake, out, fixed = TRUE))
})

testthat::test_that(".redact_literal_values kısa (<8) değeri maskelemez", {
  .logredactint_source_once()
  # 'abc' yalnızca 3 karakter: maskelenmez (yanlış pozitif redaksiyonu önler).
  out <- .logredactint_with_env("DB_PASS", "abc", function() {
    .redact_literal_values("parola=abc end")
  })
  testthat::expect_identical(out, "parola=abc end")
})

testthat::test_that(".redact_literal_values tanımsız sır değişkenlerinde metni değiştirmez", {
  .logredactint_source_once()
  # İlgili sır env tanımsız (NA) iken metin aynen kalır.
  out <- .logredactint_with_env("ANTHROPIC_API_KEY", NA_character_, function() {
    .redact_literal_values("burada sır yok, sadece düz metin")
  })
  testthat::expect_identical(out, "burada sır yok, sadece düz metin")
})

testthat::test_that(".redact_literal_values birden çok sır değerini ayrı ayrı maskeler", {
  .logredactint_source_once()
  fake_a <- paste0("FAKEAAA", strrep("1", 10))
  fake_b <- paste0("FAKEBBB", strrep("2", 10))

  out <- .logredactint_with_env("OPENAI_API_KEY", fake_a, function() {
    .logredactint_with_env("CLAUDE_CODE_API_KEY", fake_b, function() {
      .redact_literal_values(paste0("a=", fake_a, " ve b=", fake_b))
    })
  })

  testthat::expect_true(grepl("<OPENAI_API_KEY:redacted>", out, fixed = TRUE))
  testthat::expect_true(grepl("<CLAUDE_CODE_API_KEY:redacted>", out, fixed = TRUE))
  testthat::expect_false(grepl(fake_a, out, fixed = TRUE))
  testthat::expect_false(grepl(fake_b, out, fixed = TRUE))
})
