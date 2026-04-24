# ==============================================================================
# Dosya Yolu: tests/testthat/test-health-check-formatters.R
# Açıklama: Sistem Durumu biçimlendirme yardımcılarının sözleşmesini test eder.
# ==============================================================================

.bootstrap_health_tests <- function() {
  helper_candidates <- c(
    "tests/testthat/helper_bootstrap.R",
    "testthat/helper_bootstrap.R",
    "helper_bootstrap.R"
  )
  helper_path <- helper_candidates[file.exists(helper_candidates)][1]
  if (!is.na(helper_path) && nzchar(helper_path)) {
    source(helper_path, encoding = "UTF-8", local = globalenv())
  }

  if (!exists("resolve_repo_root_for_tests", mode = "function", inherits = TRUE)) {
    resolve_repo_root_for_tests <<- function() {
      candidates <- c(".", "..", "../..")
      for (cand in candidates) {
        if (file.exists(file.path(cand, "app.R")) && dir.exists(file.path(cand, "R"))) {
          return(normalizePath(cand, winslash = "/", mustWork = TRUE))
        }
      }
      stop("Repo kökü bulunamadı.", call. = FALSE)
    }
  }

  repo_root <- resolve_repo_root_for_tests()
  source(file.path(repo_root, "R", "helpers_health_formatters.R"), encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_health_checks.R"), encoding = "UTF-8", local = globalenv())
  invisible(TRUE)
}

.bootstrap_health_tests()

test_that("durum normalizasyonu eş anlamlı değerleri destekler", {
  expect_identical(health_normalize_status("healthy"), "ok")
  expect_identical(health_normalize_status("warn"), "warning")
  expect_identical(health_normalize_status("failed"), "critical")
  expect_identical(health_normalize_status("disabled"), "not_configured")
  expect_identical(health_normalize_status("beklenmeyen"), "unknown")
  expect_identical(health_normalize_status(NA_character_), "unknown")
  expect_identical(health_status_class(NA_character_), "health-status-unknown")
})

test_that("severity sıralaması kritik değeri en yüksekte tutar", {
  expect_lt(health_status_severity("ok"), health_status_severity("warning"))
  expect_lt(health_status_severity("warning"), health_status_severity("critical"))
  expect_lte(health_status_severity("not_configured"), health_status_severity("unknown"))
})

test_that("gizli değerler maskelenir ve ham değer sızmaz", {
  masked <- health_env_display_value("AI_KEYS_MASTER", "super-secret-value")
  expect_match(masked, "configured")
  expect_false(grepl("super-secret-value", masked, fixed = TRUE))
  expect_identical(health_env_display_value("LOCAL_LLM_ENDPOINT", "http://127.0.0.1:8000/v1"), "configured")
})

test_that("health_result zorunlu alan sözleşmesini korur", {
  res <- health_result("x", "Test", "ok", "değer", "detay", 12, remediation = "öneri")
  expect_true(all(c("id", "label", "status", "severity", "value", "detail", "duration_ms", "checked_at", "remediation") %in% names(res)))
  expect_identical(res$status[1], "ok")
  expect_identical(res$severity[1], health_status_severity("ok"))
})

test_that("güvenli kontrol hata fırlatmak yerine unknown döndürür", {
  res <- health_safe_check("boom", "Patlayan Kontrol", stop("bilerek hata"))
  expect_identical(res$status[1], "unknown")
  expect_match(res$detail[1], "bilerek hata")
})
