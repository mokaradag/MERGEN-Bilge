# ==============================================================================
# Dosya Yolu: tests/testthat/test-vm-browser-ux-approved-origin-contract.R
# Açıklama: Windows VM UX smoke'ta Shiny bind adresi ile browser-facing SSO
#           origin'inin ayrılmasını ve gerçek URL'nin repoya yazılmamasını korur.
# ==============================================================================

test_that("VM browser UX belgesi loopback 8009 + runtime external URL sözleşmesini korur", {
  doc <- read_source_text_utf8(file.path(resolve_repo_root_for_tests(), "docs", "vm-browser-ux-smoke.md"))

  expect_true(grepl("run_mergen_app(host='127.0.0.1', port=8009L", doc, fixed = TRUE))
  expect_true(grepl("MERGEN_ENABLE_UX_SMOKE='true'", doc, fixed = TRUE))
  expect_true(grepl("MERGEN_BROWSER_UX_BASE_URL", doc, fixed = TRUE))
  expect_true(grepl("Read-Host", doc, fixed = TRUE))
  expect_true(grepl("app.example.invalid", doc, fixed = TRUE))
  expect_false(grepl('$env:MERGEN_BROWSER_UX_BASE_URL = "https://', doc, fixed = TRUE))
  expect_false(grepl("MERGEN_ALLOW_NETWORK_UX_SMOKE", doc, fixed = TRUE))
})

test_that("browser UX runner external URL'yi log ve artifact metninden redakte eder", {
  ifadeler <- parse_r_file_utf8(file.path(resolve_repo_root_for_tests(), "tests", "scripts", "ai_browser_ux_smoke.R"))
  tanim <- Filter(function(e) is.call(e) && identical(e[[1]], as.name("<-")) &&
                    identical(as.character(e[[2]]), "ux_smoke_redact_external_url"), as.list(ifadeler))
  expect_length(tanim, 1L)

  ortam <- new.env(parent = baseenv())
  eval(tanim[[1]], ortam)

  metin <- "iframe https://private.example.invalid/base#x ve https://private.example.invalid/base/smoke"
  sonuc <- ortam$ux_smoke_redact_external_url(metin, "https://private.example.invalid/base")
  expect_false(grepl("private.example.invalid", sonuc, fixed = TRUE))
  expect_true(grepl("<MERGEN_BROWSER_UX_BASE_URL>", sonuc, fixed = TRUE))
})

test_that("runner external-app açıklaması loopback app + reverse proxy ayrımını korur", {
  runner <- read_source_text_utf8(file.path(resolve_repo_root_for_tests(), "tests", "scripts", "ai_browser_ux_smoke.R"))

  expect_true(grepl("approved browser-facing URL may be a reverse-proxy URL", runner, fixed = TRUE))
  expect_true(grepl("smoke-enabled loopback instance", runner, fixed = TRUE))
  expect_false(grepl("MERGEN_ALLOW_NETWORK_UX_SMOKE", runner, fixed = TRUE))
})
