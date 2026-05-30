# ==============================================================================
# Dosya Yolu: tests/testthat/test-markdown-safety-behavior.R
# Açıklama: Markdown/HTML güvenlik yardımcılarının davranışsal testleri.
#           Ham HTML kaçışı, javascript: link nötrleştirme ve güvenli markdown
#           render davranışı doğrulanır. Bu, XSS sınırını koruyan güvenlik-
#           duyarlı bir kontroldür. DB/LLM/tarayıcı gerekmez.
# ==============================================================================

.markdown_safety_source_once <- function() {
  if (exists("mergen_escape_raw_html_for_markdown", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("render_safe_markdown_html", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_markdown_safety.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

testthat::test_that("mergen_escape_raw_html_for_markdown açılı parantezleri kaçışlar", {
  .markdown_safety_source_once()

  testthat::expect_identical(mergen_escape_raw_html_for_markdown(NULL), "")
  testthat::expect_identical(mergen_escape_raw_html_for_markdown(character(0)), "")
  testthat::expect_identical(mergen_escape_raw_html_for_markdown(NA_character_), "")

  testthat::expect_identical(
    mergen_escape_raw_html_for_markdown("<script>alert(1)</script>"),
    "&lt;script&gt;alert(1)&lt;/script&gt;"
  )
  testthat::expect_identical(
    mergen_escape_raw_html_for_markdown("a < b > c"),
    "a &lt; b &gt; c"
  )
  testthat::expect_identical(
    mergen_escape_raw_html_for_markdown("normal metin"),
    "normal metin"
  )
  # Çok elemanlı girdide yalnızca ilk eleman kullanılır.
  testthat::expect_identical(
    mergen_escape_raw_html_for_markdown(c("<x>", "<y>")),
    "&lt;x&gt;"
  )
})

testthat::test_that("mergen_sanitize_markdown_links javascript: protokolünü nötrleştirir", {
  .markdown_safety_source_once()

  testthat::expect_identical(mergen_sanitize_markdown_links(NULL), "")

  # Çift tırnaklı javascript: href nötrleştirilmeli.
  out1 <- mergen_sanitize_markdown_links("<a href=\"javascript:alert(1)\">x</a>")
  testthat::expect_false(grepl("javascript:", out1, ignore.case = TRUE))
  testthat::expect_true(grepl("data-mergen-unsafe-href", out1, fixed = TRUE))

  # Tek tırnaklı javascript: href de nötrleştirilmeli.
  out2 <- mergen_sanitize_markdown_links("<a href='javascript:evil()'>x</a>")
  testthat::expect_false(grepl("javascript:", out2, ignore.case = TRUE))

  # Büyük/küçük harf duyarsız olmalı.
  out3 <- mergen_sanitize_markdown_links("<a href=\"JavaScript:evil()\">x</a>")
  testthat::expect_false(grepl("javascript:", out3, ignore.case = TRUE))

  # Normal https linki korunmalı.
  out4 <- mergen_sanitize_markdown_links("<a href=\"https://ornek.local/sayfa\">x</a>")
  testthat::expect_true(grepl("https://ornek.local/sayfa", out4, fixed = TRUE))
})

testthat::test_that("render_safe_markdown_html güvenli markdown üretir ve ham script geçirmez", {
  .markdown_safety_source_once()
  testthat::skip_if_not_installed("commonmark")

  # Kalın ve başlık markdown'ı HTML'e çevrilmeli.
  out_bold <- render_safe_markdown_html("**kalin**")
  testthat::expect_true(grepl("<strong>", out_bold, fixed = TRUE))

  out_head <- render_safe_markdown_html("# Baslik")
  testthat::expect_true(grepl("<h1", out_head, fixed = TRUE))

  # Ham <script> markdown'a kaçışlanarak girer; çıktıda aktif script olmamalı.
  out_xss <- render_safe_markdown_html("<script>alert(1)</script>")
  testthat::expect_false(grepl("<script", out_xss, ignore.case = TRUE))
  testthat::expect_true(grepl("alert", out_xss, fixed = TRUE))
})
