# ==============================================================================
# Dosya Yolu: tests/testthat/test-followup-enabled-behavior.R
# Açıklama: R/helpers_followup_questions.R resolve_followup_enabled() toleranslı
#           bayrak çözümleyicisinin davranışsal testleri. CLAUDE.md: mantıksal,
#           sayısal ve string-benzeri truthy değerler özellik sessizce
#           kapatmamalı. Oturum girdisi de OR mantığıyla dikkate alınır.
# ==============================================================================

testthat::local_edition(3)

.fe_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_followup_questions.R"),
  encoding = "UTF-8",
  local = .fe_env
)

test_that("resolve_followup_enabled mantıksal TRUE/FALSE'u doğru çözer", {
  expect_true(.fe_env$resolve_followup_enabled(list(enable_followups = TRUE)))
  expect_false(.fe_env$resolve_followup_enabled(list(enable_followups = FALSE)))
})

test_that("resolve_followup_enabled string ve sayısal truthy değerleri kabul eder", {
  expect_true(.fe_env$resolve_followup_enabled(list(enable_followups = "evet")))
  expect_true(.fe_env$resolve_followup_enabled(list(enable_followups = "true")))
  expect_true(.fe_env$resolve_followup_enabled(list(enable_followups = "aktif")))
  expect_true(.fe_env$resolve_followup_enabled(list(enable_followups = 1)))
})

test_that("resolve_followup_enabled falsy string/sayı ve eksik değerde FALSE döner", {
  expect_false(.fe_env$resolve_followup_enabled(list(enable_followups = "false")))
  expect_false(.fe_env$resolve_followup_enabled(list(enable_followups = 0)))
  expect_false(.fe_env$resolve_followup_enabled(list(enable_followups = NULL)))
})

test_that("resolve_followup_enabled oturum girdisi truthy ise ayar FALSE olsa bile TRUE döner", {
  sahte_session <- list(
    input = list(`settings_yapilandirma_module-enable_followups` = TRUE)
  )
  expect_true(.fe_env$resolve_followup_enabled(list(enable_followups = FALSE), session = sahte_session))
})
