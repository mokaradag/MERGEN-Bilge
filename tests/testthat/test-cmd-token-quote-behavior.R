# ==============================================================================
# Dosya Yolu: tests/testthat/test-cmd-token-quote-behavior.R
# Açıklama: R/helpers_claude_code_process.R Windows cmd.exe argüman tırnaklama ve
#           çalışma dizini normalizasyonu DAVRANIŞSAL testleri. Bu, Bilge Yolaç
#           CLI çağrısında komut enjeksiyonu/ayrıştırma güvenliği sınırıdır.
#           Fonksiyonlar OS-bağımsız saf dize dönüşümleridir; gerçek üretim kodu
#           çağrılır. processx/CLI/ağ gerekmez.
# ==============================================================================

.cmdquote_source_once <- function() {
  if (exists("quote_windows_cmd_token", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_process.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

testthat::test_that("quote_windows_cmd_token tek satırlık çift tırnaklı argüman üretir", {
  .cmdquote_source_once()
  # Boşluklu yol çift tırnağa alınır (R değeri: "C:\Tools\claude.cmd").
  testthat::expect_identical(
    quote_windows_cmd_token("C:\\Program Files\\claude.cmd"),
    "\"C:\\Program Files\\claude.cmd\""
  )
})

testthat::test_that("quote_windows_cmd_token iç çift tırnakları ikiye katlar", {
  .cmdquote_source_once()
  # 'say "hi"' -> "say ""hi"""
  testthat::expect_identical(
    quote_windows_cmd_token('say "hi"'),
    "\"say \"\"hi\"\"\""
  )
})

testthat::test_that("quote_windows_cmd_token satır kırılmalarını boşluğa çevirir", {
  .cmdquote_source_once()
  testthat::expect_identical(quote_windows_cmd_token("a\nb"), "\"a b\"")
  testthat::expect_identical(quote_windows_cmd_token("a\r\nb"), "\"a b\"")
  testthat::expect_identical(quote_windows_cmd_token("a\rb"), "\"a b\"")
})

testthat::test_that("quote_windows_cmd_token NA/boş/NULL güvenle boş tırnak üretir", {
  .cmdquote_source_once()
  testthat::expect_identical(quote_windows_cmd_token(NA), "\"\"")
  testthat::expect_identical(quote_windows_cmd_token(""), "\"\"")
  testthat::expect_identical(quote_windows_cmd_token(NULL), "\"\"")
})

# KARAKTERİZASYON: normalize_cmd_workdir() şu anda gsub(..., fixed = TRUE)
# kullandığından her "/" ayıracını ÇİFT ters slash'a çevirir (ör. C:/Temp/x ->
# C:\\Temp\\x). Bu testler MEVCUT davranışı belgeler; ayıraç ikilenmesi ileride
# kasıtlı olarak değiştirilirse bilinçli bir karar gerektirsin diye kilitlenir.
testthat::test_that("normalize_cmd_workdir boş girdide boş döner ve ayıracı çiftler (mevcut davranış)", {
  .cmdquote_source_once()
  testthat::expect_identical(normalize_cmd_workdir(""), "")
  # Her "/" çift ters slash olur: gerçek değer C:\\Temp\\x
  testthat::expect_identical(normalize_cmd_workdir("C:/Temp/x"), "C:\\\\Temp\\\\x")
})

testthat::test_that("normalize_cmd_workdir tek-slash ağ yolunu UNC'ye getirir (mevcut davranış)", {
  .cmdquote_source_once()
  # "/rehisds/proje" -> gerçek değer \\rehisds\\proje
  testthat::expect_identical(normalize_cmd_workdir("/rehisds/proje"), "\\\\rehisds\\\\proje")
  # "//server/share" -> gerçek değer \\\\server\\share
  testthat::expect_identical(normalize_cmd_workdir("//server/share"), "\\\\\\\\server\\\\share")
})
