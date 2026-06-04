# ==============================================================================
# Dosya Yolu: tests/testthat/test-config-logging-sanitize-behavior.R
# Açıklama: R/config_logging.R .sanitize_log_value() log değer temizleme/redaksiyon
#           sarmalayıcısının davranış testleri. Bu sarmalayıcı, log'a yazılmadan
#           önce metni normalize eder ve sır/secret içeren değerleri maskeler.
#           normalize_text_for_log/redact_sensitive_text global yardımcıları
#           helper_bootstrap.R tarafından yüklenir. Gerçek log dosyası GEREKMEZ.
# ==============================================================================

testthat::local_edition(3)

# config_logging.R kaynak anında bir kez logger INFO mesajı basabilir; sessizle.
.source_config_logging <- function() {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  suppressMessages(source(
    file.path(resolve_repo_root_for_tests(), "R", "config_logging.R"),
    encoding = "UTF-8", local = env
  ))
  env
}

testthat::test_that(".sanitize_log_value NULL girdiyi NULL döndürür", {
  env <- .source_config_logging()
  testthat::expect_null(env$.sanitize_log_value(NULL))
})

testthat::test_that(".sanitize_log_value sayısal/mantıksal değerleri değiştirmez", {
  env <- .source_config_logging()
  testthat::expect_identical(env$.sanitize_log_value(42L), 42L)
  testthat::expect_identical(env$.sanitize_log_value(TRUE), TRUE)
})

testthat::test_that(".sanitize_log_value sıradan Türkçe metni korur", {
  env <- .source_config_logging()
  out <- env$.sanitize_log_value("Kullanıcı oturum açtı: İstanbul şubesi")
  testthat::expect_type(out, "character")
  testthat::expect_true(grepl("İstanbul şubesi", out, fixed = TRUE))
})

testthat::test_that(".sanitize_log_value Bearer token içeren metni maskeler", {
  env <- .source_config_logging()
  # Sahte token (gerçek sır değil) — redaksiyon yardımcısı varsa maskelenmeli.
  sahte <- paste0("Authorization: Bearer ", paste(rep("x", 40), collapse = ""))
  out <- env$.sanitize_log_value(sahte)
  testthat::expect_type(out, "character")
  if (exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
    # Maskeleme aktifse ham 40-karakter token aynen kalmamalı.
    testthat::expect_false(identical(out, sahte))
  } else {
    testthat::succeed("redact_sensitive_text yüklü değil; sözleşme: girdiyi aynen döndür")
  }
})
