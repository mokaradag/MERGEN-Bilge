# ==============================================================================
# Dosya Yolu: tests/testthat/test-vm-preflight-guard-contract.R
# Açıklama: run_vm_preflight_real.R betiğinin zorunlu ortam değişkenleri eksik
# olduğunda hızlı ve net biçimde durduğunu doğrular.
# Not: Bu kontrat özellikle child-process stdout/stderr ayrıştırmasına
# bağımlı bırakılmaz; Windows VM üzerinde en güvenilir doğrulama budur.
# ==============================================================================

test_that("run_vm_preflight_real eksik zorunlu ortam değişkenlerinde hızlı ve net fail verir", {
  withr::local_envvar(c(
    MERGEN_PREFLIGHT_REQUIRE_SSO = "FALSE",
    LOCAL_LLM_ENDPOINT = NA_character_,
    DB_DSN = NA_character_,
    AI_KEYS_MASTER = NA_character_
  ))

  expect_error(
    withr::with_dir(
      repo_root_for_tests,
      source("tests/scripts/run_vm_preflight_real.R", encoding = "UTF-8")
    ),
    "Eksik.*ortam değişkenleri"
  )
})