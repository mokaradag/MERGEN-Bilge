# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-document-download-link-encoding.R
# Açıklama: Bilge Yolaç doküman özeti çıktılarında Türkçe karakter kodlamasını
#           ve kullanıcı klasöründe oluşan özet dosyası için doğrudan
#           indirilebilir bağlantı kartı üretimini doğrular.
# ==============================================================================

test_that("Bilge Yolaç document summary text is written as UTF-8 with BOM", {
  tmp_file <- tempfile(fileext = ".txt")
  metin <- "Türkçe karakter testi: ç ğ ı İ ö ş ü Ç Ğ I İ Ö Ş Ü"

  expect_true(
    write_claude_code_utf8_bom_text_file(metin, tmp_file)
  )

  bytes <- readBin(tmp_file, what = "raw", n = 8)
  expect_true(length(bytes) >= 3)
  expect_identical(bytes[1:3], as.raw(c(0xEF, 0xBB, 0xBF)))

  okunan <- paste(
    readLines(tmp_file, encoding = "UTF-8", warn = FALSE),
    collapse = "\n"
  )
  okunan <- sub("^\ufeff", "", okunan)

  expect_match(okunan, "Türkçe karakter testi", fixed = TRUE)
  expect_match(okunan, "ç ğ ı İ ö ş ü", fixed = TRUE)
})

test_that("Bilge Yolaç existing summary file link uses the real created file", {
  tmp_dir <- tempfile("bilge_yolac_existing_")
  dir.create(tmp_dir, recursive = TRUE)

  tmp_file <- file.path(tmp_dir, "dosya_aciklamalari.txt")
  metin <- "Doğrudan indirilebilir dosya: ç ğ ı İ ö ş ü"

  expect_true(
    write_claude_code_utf8_bom_text_file(metin, tmp_file)
  )
  expect_true(file.exists(tmp_file))

  html <- format_claude_code_existing_file_link_html(
    file_path = tmp_file,
    user_id = 1L,
    session_token = paste0("test_", as.integer(Sys.time())),
    allowed_roots = tmp_dir,
    display_path = basename(tmp_file)
  )

  expect_true(nzchar(html))
  expect_match(html, "cc-generated-file-card", fixed = TRUE)
  expect_match(html, "Oluşturulan Dosyalar", fixed = TRUE)
  expect_match(html, "dosya_aciklamalari.txt", fixed = TRUE)
  expect_match(html, "İndir", fixed = TRUE)
  expect_false(grepl("İndirme kartı hazırlanamadı", html, fixed = TRUE))
})