# ==============================================================================
# Dosya Yolu: tests/testthat/test-files-read-content-behavior.R
# Açıklama: R/helpers_files.R readFileContentToString() metin okuma davranışının
#           testleri. UTF-8 metin dosyaları okunur, olmayan dosya için Türkçe
#           hata mesajı döner. Gerçek UNC/DB gerektirmez; resolve_readable_path
#           kimlik fonksiyonuyla stub'lanır, path_exists_relaxed global stub'tır.
# ==============================================================================

testthat::local_edition(3)

.hf_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_files.R"),
  encoding = "UTF-8",
  local = .hf_env
)
# UNC/Windows yol çözümünü kimlik fonksiyonuna indir (yerel test için yeterli).
.hf_env$resolve_readable_path <- function(p) p

test_that("readFileContentToString UTF-8 metin dosyasının içeriğini Türkçe karakterlerle okur", {
  tmp <- tempfile(fileext = ".txt")
  on.exit(unlink(tmp), add = TRUE)
  con <- file(tmp, open = "w", encoding = "UTF-8")
  writeLines(c("Merhaba dünya", "İkinci satır: çğışöü"), con)
  close(con)

  sonuc <- .hf_env$readFileContentToString(list(datapath = tmp, name = "ornek.txt"))

  expect_true(is.character(sonuc))
  expect_true(grepl("Merhaba dünya", sonuc, fixed = TRUE))
  expect_true(grepl("İkinci satır", sonuc, fixed = TRUE))
})

test_that("readFileContentToString CSV içeriğini de okur", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)
  con <- file(tmp, open = "w", encoding = "UTF-8")
  writeLines(c("ad,deger", "şehir,42"), con)
  close(con)

  sonuc <- .hf_env$readFileContentToString(list(datapath = tmp, name = "veri.csv"))
  expect_true(grepl("şehir", sonuc, fixed = TRUE))
  expect_true(grepl("42", sonuc, fixed = TRUE))
})

test_that("readFileContentToString olmayan dosya için Türkçe hata mesajı döner", {
  sonuc <- .hf_env$readFileContentToString(list(
    datapath = file.path(tempdir(), "kesinlikle_olmayan_dosya.txt"),
    name = "yok.txt"
  ))
  expect_true(grepl("bulunamad", sonuc))
})
