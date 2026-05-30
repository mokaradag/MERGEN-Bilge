# ==============================================================================
# Dosya Yolu: tests/testthat/test-markdown-raw-html-escape-behavior.R
# Açıklama: R/helpers_markdown_safety.R ham HTML kaçış ve javascript: link
#           etkisizleştirme yardımcılarının DAVRANIŞSAL testleri. Bu, LLM/kullanıcı
#           üretimi metnin innerHTML'e ham geçmesini engelleyen XSS sınırının
#           sunucu tarafıdır. commonmark gerektiren render_safe_markdown_html bu
#           dosyada test edilmez; saf yardımcılar doğrudan çağrılır.
# ==============================================================================

.mdsafe_source_once <- function() {
  if (exists("mergen_escape_raw_html_for_markdown", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_markdown_safety.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

testthat::test_that("mergen_escape_raw_html_for_markdown açı parantezlerini etkisizleştirir", {
  .mdsafe_source_once()
  testthat::expect_identical(
    mergen_escape_raw_html_for_markdown("<script>alert(1)</script>"),
    "&lt;script&gt;alert(1)&lt;/script&gt;"
  )
  testthat::expect_identical(
    mergen_escape_raw_html_for_markdown("a < b > c"),
    "a &lt; b &gt; c"
  )
  testthat::expect_identical(
    mergen_escape_raw_html_for_markdown("img onerror = x"),
    "img onerror = x"
  )
})

testthat::test_that("mergen_escape_raw_html_for_markdown NULL/NA/boş güvenle boş döndürür", {
  .mdsafe_source_once()
  testthat::expect_identical(mergen_escape_raw_html_for_markdown(NULL), "")
  testthat::expect_identical(mergen_escape_raw_html_for_markdown(NA), "")
  testthat::expect_identical(mergen_escape_raw_html_for_markdown(character(0)), "")
})

testthat::test_that("mergen_sanitize_markdown_links javascript: protokolünü etkisizleştirir", {
  .mdsafe_source_once()
  # Çift tırnaklı javascript: href tıklanamaz hale gelir.
  out_dq <- mergen_sanitize_markdown_links('<a href="javascript:alert(1)">x</a>')
  testthat::expect_false(grepl("javascript:", out_dq, ignore.case = TRUE))
  testthat::expect_true(grepl('data-mergen-unsafe-href="removed"', out_dq, fixed = TRUE))

  # Tek tırnaklı varyant da etkisizleştirilir.
  out_sq <- mergen_sanitize_markdown_links("<a href='javascript:evil()'>y</a>")
  testthat::expect_false(grepl("javascript:", out_sq, ignore.case = TRUE))

  # Büyük/küçük harf ve baştaki boşluk toleranslı yakalanır.
  out_ci <- mergen_sanitize_markdown_links('<a HREF="  JavaScript:steal()">z</a>')
  testthat::expect_false(grepl("javascript:", out_ci, ignore.case = TRUE))
})

testthat::test_that("mergen_sanitize_markdown_links güvenli https linklerine dokunmaz", {
  .mdsafe_source_once()
  safe <- '<a href="https://kurumsal.example/rapor">Rapor</a>'
  testthat::expect_identical(mergen_sanitize_markdown_links(safe), safe)
  testthat::expect_identical(mergen_sanitize_markdown_links(NULL), "")
})
