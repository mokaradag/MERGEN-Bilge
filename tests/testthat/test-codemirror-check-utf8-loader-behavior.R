# ==============================================================================
# Dosya Yolu: tests/testthat/test-codemirror-check-utf8-loader-behavior.R
# Açıklama: CodeMirror çizim denetiminin kaynak yükleyicisi yerel kod
#           sayfasından ve options(encoding) değerinden bağımsız GEÇERLİ UTF-8
#           üretmelidir. Windows VM'nin CP1254 oturumunda options(encoding =
#           "UTF-8") varken readLines(encoding = "UTF-8") baytları CP1254'e
#           çevirip UTF-8 diye işaretliyordu; fikstür JSON'u gsub() içinde
#           "input string 1 is invalid UTF-8" ile düşüyordu. Test seçeneği
#           AÇIKÇA "UTF-8" yapar (VM'de eski kod bu testte düşer). Tarayıcı
#           gerekmez: sayfa üretimi (düşen satır) doğrudan çalışır.
# ==============================================================================

.cm_loader_runner <- function() {
  root <- resolve_repo_root_for_tests()
  runner <- new.env(parent = globalenv())
  for (expr in parse_r_file_utf8(file.path(root, "tests", "scripts", "codemirror_rendering_check.R"))) {
    eval(expr, runner)
  }
  runner
}

test_that("denetim yükleyicisi Türkçe dize sabitlerini geçerli UTF-8 olarak yükler", {
  withr::local_options(encoding = "UTF-8")
  runner <- .cm_loader_runner()
  beklenen <- intToUtf8(c(71L, 101L, 110L, 105L, 0x015FL, 108L, 101L, 116L))
  yorum <- intToUtf8(c(35L, 32L, 0x00C7L, 0x0131L, 107L, 0x0131L, 0x015FL))
  kaynak <- paste0(yorum, "\nornek_dize <- \"", beklenen, "\"\n")
  yol <- withr::local_tempfile(fileext = ".R")
  con <- file(yol, open = "wb")
  writeBin(charToRaw(enc2utf8(kaynak)), con)
  close(con)

  env <- new.env(parent = globalenv())
  runner$cm_render_check_source(yol, env)
  expect_true(validUTF8(env$ornek_dize))
  expect_identical(Encoding(env$ornek_dize), "UTF-8")
  expect_identical(env$ornek_dize, beklenen)
})

test_that("fikstür sayfası geçerli UTF-8 üretir ve betik kapanışı kaçırılır", {
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("htmltools")
  skip_if_not_installed("stringr")
  withr::local_options(encoding = "UTF-8")
  runner <- .cm_loader_runner()
  root <- resolve_repo_root_for_tests()

  fixtures <- runner$cm_render_check_fixtures(root)
  expect_true(all(vapply(fixtures, function(f) validUTF8(f$html) && validUTF8(f$code), logical(1))))

  sayfa <- runner$cm_render_check_page(root, fixtures)
  expect_true(validUTF8(sayfa))
  expect_true(grepl(intToUtf8(c(0x0130L, 108L, 107L)), sayfa, fixed = TRUE))
  fikstur_blogu <- regmatches(sayfa, regexpr("window.__CM_FIXTURES = [^\n]*", sayfa))
  expect_length(fikstur_blogu, 1L)
  fikstur_json <- sub(";</script>$", "", fikstur_blogu)
  expect_true(grepl("<\\/", fikstur_json, fixed = TRUE))
  expect_false(grepl("</", fikstur_json, fixed = TRUE))
})

test_that("denetim betiği ve tarayıcı testi kaynakları readLines/parse(text=) ile yüklemez", {
  root <- resolve_repo_root_for_tests()
  for (rel in c("tests/scripts/codemirror_rendering_check.R",
                "tests/testthat/test-codemirror-rendering-browser-behavior.R")) {
    kod <- readLines(file.path(root, rel), warn = FALSE, encoding = "UTF-8")
    kod <- kod[!grepl("^\\s*#", kod)]
    expect_false(any(grepl("parse\\(\\s*text\\s*=", kod)), info = rel)
    expect_false(any(grepl("readLines(", kod, fixed = TRUE)), info = rel)
  }
})
