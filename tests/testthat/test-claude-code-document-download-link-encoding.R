# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-document-download-link-encoding.R
# Açıklama: Bilge Yolaç doküman özeti çıktılarında Türkçe karakter kodlamasını
#           ve kullanıcı klasöründe oluşan özet dosyası için doğrudan
#           indirilebilir bağlantı kartı üretimini doğrular.
# ==============================================================================

.source_cc_document_download_helpers_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  env$CLAUDE_CODE_LOG_PREFIX <- "[CLAUDE_CODE_TEST]"
  env$log_warn <- function(...) invisible(NULL)

  source(file.path(repo_root, "R", "utils_common.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_claude_code_downloads.R"), encoding = "UTF-8", local = env)

  # helpers_claude_code_documents.R üst bölümünde extractor fonksiyonlarını arar.
  # Önceden aynı test ortamına yükleyerek globalenv yan etkisini önlüyoruz.
  source(
    file.path(repo_root, "R", "helpers_claude_code_document_extractors.R"),
    encoding = "UTF-8",
    local = env
  )

  source(
    file.path(repo_root, "R", "helpers_claude_code_documents.R"),
    encoding = "UTF-8",
    local = env
  )

  source(
    file.path(repo_root, "R", "helpers_claude_code_existing_file_link.R"),
    encoding = "UTF-8",
    local = env
  )

  env
}

.read_utf8_bom_text_for_test <- function(file_path) {
  raw_data <- readBin(file_path, what = "raw", n = file.info(file_path)$size)

  expect_true(length(raw_data) >= 3)
  expect_identical(raw_data[1:3], as.raw(c(0xEF, 0xBB, 0xBF)))

  text_raw <- raw_data[-seq_len(3)]
  text <- rawToChar(text_raw)

  decoded <- iconv(text, from = "UTF-8", to = "UTF-8", sub = "byte")
  expect_false(is.na(decoded))

  enc2utf8(decoded)
}

test_that("Bilge Yolaç document summary text is written as UTF-8 with BOM", {
  env <- .source_cc_document_download_helpers_for_test()

  tmp_file <- tempfile(fileext = ".txt")

  turkce_karakterler <- paste(
    "\u00e7", "\u011f", "\u0131", "\u0130", "\u00f6", "\u015f", "\u00fc",
    "\u00c7", "\u011e", "I", "\u0130", "\u00d6", "\u015e", "\u00dc"
  )

  metin <- paste0("T\u00fcrk\u00e7e karakter testi: ", turkce_karakterler)

  expect_true(
    env$write_claude_code_utf8_bom_text_file(metin, tmp_file)
  )

  okunan <- .read_utf8_bom_text_for_test(tmp_file)

  expect_match(okunan, "T\u00fcrk\u00e7e karakter testi", fixed = TRUE)
  expect_match(
    okunan,
    paste("\u00e7", "\u011f", "\u0131", "\u0130", "\u00f6", "\u015f", "\u00fc"),
    fixed = TRUE
  )
})

test_that("Bilge Yolaç existing summary file link uses the real created file", {
  env <- .source_cc_document_download_helpers_for_test()

  tmp_dir <- tempfile("bilge_yolac_existing_")
  dir.create(tmp_dir, recursive = TRUE)

  tmp_file <- file.path(tmp_dir, "dosya_aciklamalari.txt")
  metin <- paste0(
    "Do\u011frudan indirilebilir dosya: ",
    paste("\u00e7", "\u011f", "\u0131", "\u0130", "\u00f6", "\u015f", "\u00fc")
  )

  expect_true(
    env$write_claude_code_utf8_bom_text_file(metin, tmp_file)
  )
  expect_true(file.exists(tmp_file))

  html <- env$format_claude_code_existing_file_link_html(
    file_path = tmp_file,
    user_id = 1L,
    session_token = paste0("test_", as.integer(Sys.time())),
    allowed_roots = tmp_dir,
    display_path = basename(tmp_file)
  )

  expect_true(nzchar(html))
  expect_match(html, "cc-generated-file-card", fixed = TRUE)
  expect_match(html, "Olu\u015fturulan Dosyalar", fixed = TRUE)
  expect_match(html, "dosya_aciklamalari.txt", fixed = TRUE)
  expect_match(html, "\\u0130ndir", fixed = TRUE)
  expect_false(grepl("\\u0130ndirme kart\\u0131 haz\\u0131rlanamad\\u0131", html, fixed = TRUE))
})

test_that("Bilge Yolaç existing summary file link requires explicit allowed roots", {
  env <- .source_cc_document_download_helpers_for_test()

  tmp_dir <- tempfile("bilge_yolac_existing_guard_")
  dir.create(tmp_dir, recursive = TRUE)

  tmp_file <- file.path(tmp_dir, "dosya_aciklamalari.txt")

  expect_true(
    env$write_claude_code_utf8_bom_text_file("güvenli özet", tmp_file)
  )
  expect_true(file.exists(tmp_file))

  html <- env$format_claude_code_existing_file_link_html(
    file_path = tmp_file,
    user_id = 1L,
    session_token = paste0("test_", as.integer(Sys.time())),
    allowed_roots = character(0),
    display_path = basename(tmp_file)
  )

  expect_identical(html, "")
})