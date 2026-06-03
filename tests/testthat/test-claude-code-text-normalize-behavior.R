# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-text-normalize-behavior.R
# Açıklama: R/helpers_claude_code_workdir_snapshot.R
#           normalize_claude_code_text_file_to_utf8() davranışsal testleri.
#           Koruma yolları (NULL/boş/olmayan/dizin/boş dosya -> FALSE) ve geçerli
#           UTF-8 dosyada TRUE + içeriğin geçerli UTF-8 olarak kalması doğrulanır.
# ==============================================================================

testthat::local_edition(3)

.nrm_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_workdir_snapshot.R"),
  encoding = "UTF-8",
  local = .nrm_env
)

.normalize <- function(p) .nrm_env$normalize_claude_code_text_file_to_utf8(p)

test_that("normalize_claude_code_text_file_to_utf8 geçersiz girdiler için FALSE döner", {
  expect_false(.normalize(NULL))
  expect_false(.normalize(""))
  expect_false(.normalize(file.path(tempdir(), "kesinlikle_olmayan.txt")))
  expect_false(.normalize(tempdir()))  # dizin
})

test_that("normalize_claude_code_text_file_to_utf8 boş (0 bayt) dosya için FALSE döner", {
  tmp <- tempfile(fileext = ".txt")
  file.create(tmp)
  on.exit(unlink(tmp), add = TRUE)
  expect_equal(file.info(tmp)$size, 0)
  expect_false(.normalize(tmp))
})

test_that("normalize_claude_code_text_file_to_utf8 geçerli UTF-8 dosyada TRUE döner ve içerik geçerli UTF-8 kalır", {
  tmp <- tempfile(fileext = ".txt")
  on.exit(unlink(tmp), add = TRUE)
  # ASCII + Türkçe içerik (geçerli UTF-8, BOM yok).
  writeBin(charToRaw(enc2utf8("Merhaba dünya çğışöü")), tmp)

  sonuc <- .normalize(tmp)
  expect_true(isTRUE(sonuc))

  # Normalize sonrası dosya hâlâ okunabilir, geçerli UTF-8 ve ASCII kısmı korunmuş.
  icerik <- rawToChar(readBin(tmp, "raw", n = 1000))
  Encoding(icerik) <- "UTF-8"
  expect_true(all(validUTF8(icerik)))
  expect_true(grepl("Merhaba", icerik, fixed = TRUE))
})
