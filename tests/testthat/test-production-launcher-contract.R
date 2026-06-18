test_that("production launcher tees console output into daily runtime log", {
  bat_path <- test_path("..", "..", "run_mergen_prod.bat")
  bat <- paste(readLines(bat_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  expect_match(bat, "set \\\"MERGEN_LOG_DIR=%CD%\\\\logs\\\"", fixed = FALSE)
  expect_match(bat, "set \\\"MERGEN_LOG_FILE=%MERGEN_LOG_DIR%\\\\mergen_%MERGEN_LOG_STAMP%\\.log\\\"")
  expect_match(bat, "Tee-Object -FilePath \\$env:MERGEN_LOG_FILE -Append", fixed = FALSE)
  expect_match(bat, "& \\$env:RSCRIPT_EXE 'run_mergen_prod\\.R' 2>&1 \\| Tee-Object")
})
