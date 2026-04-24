# ==============================================================================
# Dosya Yolu: tests/testthat/test-test-runner-safety-contract.R
# Açıklama: tests/testthat.R giriş noktasının kendi başına güvenli olduğunu
# doğrular. Test koşumu Shiny app'i veya future cluster'ı başlatmamalıdır.
# ==============================================================================

test_that("testthat.R app autorun ve future cluster bayraklarını kapatır", {
  repo_root <- resolve_repo_root_for_tests()
  runner_path <- file.path(repo_root, "tests", "testthat.R")

  txt <- paste(
    readLines(runner_path, warn = FALSE, encoding = "UTF-8"),
    collapse = "\n"
  )

  expect_true(
    grepl("MERGEN_RUN_APP\\s*=\\s*['\"]false['\"]", txt, perl = TRUE),
    info = "tests/testthat.R içinde MERGEN_RUN_APP='false' açıkça ayarlanmalı."
  )

  expect_true(
    grepl("MERGEN_DISABLE_FUTURES\\s*=\\s*['\"]true['\"]", txt, perl = TRUE),
    info = "tests/testthat.R içinde MERGEN_DISABLE_FUTURES='true' açıkça ayarlanmalı."
  )
})