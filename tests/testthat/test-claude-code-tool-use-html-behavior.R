# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-tool-use-html-behavior.R
# Açıklama: R/helpers_claude_code_formatters.R Bilge Yolaç araç-kullanımı HTML
#           biçimlendiricilerinin DAVRANIŞSAL testleri. Akış/araç HTML güvenlik
#           sınırının parçasıdır: araç adları, tool id, komut, yol, önizleme ve
#           sonuç metni tarayıcıya verilmeden önce KAÇIŞLANMALIDIR (XSS). Testler
#           get_tool_display_info, format_tool_result_snippet,
#           format_live_tool_use_html ve format_streaming_chunk_html'i gerçek
#           girdilerle çağırır. htmltools::htmlEscape üretim bağımlılığıdır.
# ==============================================================================

.cchtml_source_once <- function() {
  if (exists("format_live_tool_use_html", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_formatters.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# get_tool_display_info (saf eşleme)
# ------------------------------------------------------------------------------
testthat::test_that("get_tool_display_info bilinen türler için ikon/başlık döner", {
  .cchtml_source_once()
  testthat::expect_identical(get_tool_display_info("bash"), list(ikon = "terminal", baslik = "Kabuk Komutu"))
  testthat::expect_identical(get_tool_display_info("file_read"), list(ikon = "file-code", baslik = "Dosya Okuma"))
  testthat::expect_identical(get_tool_display_info("file_write"), list(ikon = "pen", baslik = "Dosya Yazma"))
  testthat::expect_identical(get_tool_display_info("search"), list(ikon = "search", baslik = "Arama"))
})

testthat::test_that("get_tool_display_info bilinmeyen tür için 'other'a düşer ve adı başlık yapar", {
  .cchtml_source_once()
  # other, ad yoksa "Araç".
  testthat::expect_identical(get_tool_display_info("other"), list(ikon = "cog", baslik = "Araç"))
  testthat::expect_identical(get_tool_display_info("other", "Foo"), list(ikon = "cog", baslik = "Foo"))
  # Bilinmeyen tür de other'a düşer; ad varsa başlık ad olur.
  testthat::expect_identical(get_tool_display_info("yok-tur", "Bar"), list(ikon = "cog", baslik = "Bar"))
  testthat::expect_identical(get_tool_display_info("yok-tur"), list(ikon = "cog", baslik = "Araç"))
})

# ------------------------------------------------------------------------------
# format_tool_result_snippet
# ------------------------------------------------------------------------------
testthat::test_that("format_tool_result_snippet boş girdide '' döner, doluyu kaçışlar", {
  .cchtml_source_once()
  testthat::expect_identical(format_tool_result_snippet(""), "")
  testthat::expect_identical(format_tool_result_snippet(NULL), "")

  out <- format_tool_result_snippet("hello <b>")
  testthat::expect_true(grepl("hello &lt;b&gt;", out, fixed = TRUE))   # kaçışlanmış
  testthat::expect_false(grepl("<b>", out, fixed = TRUE))              # ham etiket yok
  testthat::expect_true(grepl("cc-tool-result-pre", out, fixed = TRUE))
})

testthat::test_that("format_tool_result_snippet 1000 karakterden uzun sonucu kısaltır", {
  .cchtml_source_once()
  uzun <- paste(rep("x", 1100), collapse = "")
  out <- format_tool_result_snippet(uzun)
  testthat::expect_true(grepl("(kısaltıldı)", out, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# format_live_tool_use_html (XSS güvenlik sınırı)
# ------------------------------------------------------------------------------
testthat::test_that("format_live_tool_use_html bash komutunu ve tool id'yi kaçışlar (XSS atıl)", {
  .cchtml_source_once()
  h <- format_live_tool_use_html(list(
    arac_turu = "bash", arac_adi = "Bash",
    komut = "echo <script>alert(1)</script>",
    arac_id = "tool-<x>"
  ))
  testthat::expect_type(h, "character")
  testthat::expect_length(h, 1L)
  # Tehlikeli payload aktif HTML'e dönüşmez.
  testthat::expect_false(grepl("<script>", h, fixed = TRUE))
  testthat::expect_true(grepl("&lt;script&gt;alert(1)&lt;/script&gt;", h, fixed = TRUE))
  # Tool id öznitelik değeri kaçışlanır.
  testthat::expect_true(grepl('data-tool-id="tool-&lt;x&gt;"', h, fixed = TRUE))
  testthat::expect_true(grepl('data-tool-type="bash"', h, fixed = TRUE))
  testthat::expect_true(grepl("Kabuk Komutu", h, fixed = TRUE))
  testthat::expect_true(grepl("cc-shell-prompt", h, fixed = TRUE))
})

testthat::test_that("format_live_tool_use_html dosya yolu ve arama desenini kaçışlar", {
  .cchtml_source_once()
  # file_read: yol kaçışlanır.
  hr <- format_live_tool_use_html(list(arac_turu = "file_read", dosya_yolu = "/etc/<p>", arac_id = "r1"))
  testthat::expect_true(grepl("/etc/&lt;p&gt;", hr, fixed = TRUE))
  testthat::expect_false(grepl("<p>", hr, fixed = TRUE))
  testthat::expect_true(grepl("Dosya Okuma", hr, fixed = TRUE))

  # search: desen kaçışlanır (girdi$pattern).
  hs <- format_live_tool_use_html(list(arac_turu = "search", girdi = list(pattern = "<q>"), arac_id = "s1"))
  testthat::expect_true(grepl("&lt;q&gt;", hs, fixed = TRUE))
  testthat::expect_false(grepl("<q>", hs, fixed = TRUE))
  testthat::expect_true(grepl("Arama", hs, fixed = TRUE))
})

testthat::test_that("format_live_tool_use_html file_write önizlemesini 10 satırda kısaltır ve yolu kaçışlar", {
  .cchtml_source_once()
  icerik <- paste(paste0("satir", 1:12), collapse = "\n")
  h <- format_live_tool_use_html(list(
    arac_turu = "file_write", dosya_yolu = "/tmp/a<b>.txt",
    dosya_icerigi = icerik, arac_id = "w1"
  ))
  testthat::expect_true(grepl("Dosya Önizlemesi", h, fixed = TRUE))
  testthat::expect_true(grepl("/tmp/a&lt;b&gt;.txt", h, fixed = TRUE))
  # 12 satırın 10'u gösterilir, +2 satır daha notu eklenir.
  testthat::expect_true(grepl("+2 satır daha", h, fixed = TRUE))
  testthat::expect_true(grepl("Dosya Yazma", h, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# format_streaming_chunk_html (dağıtım)
# ------------------------------------------------------------------------------
testthat::test_that("format_streaming_chunk_html parça tipine göre doğru dağıtır", {
  .cchtml_source_once()
  # NULL parça ve bilinmeyen tip => NULL.
  testthat::expect_null(format_streaming_chunk_html(NULL))
  testthat::expect_null(format_streaming_chunk_html(list(tip = "yok-tip", icerik = "x")))

  # raw_text kaçışlanır.
  rt <- format_streaming_chunk_html(list(tip = "raw_text", icerik = "ham <b>"))
  testthat::expect_identical(rt$tip, "raw_text")
  testthat::expect_identical(rt$html, "ham &lt;b&gt;")

  # tool_use, format_live_tool_use_html'e devreder ve arac_id taşır.
  tu <- format_streaming_chunk_html(list(tip = "tool_use", arac_turu = "bash", komut = "ls", arac_id = "t1"))
  testthat::expect_identical(tu$tip, "tool_use")
  testthat::expect_identical(tu$arac_id, "t1")
  testthat::expect_true(grepl("cc-tool-block", tu$html, fixed = TRUE))

  # result, session_id taşır.
  rs <- format_streaming_chunk_html(list(tip = "result", icerik = "bitti", session_id = "s9"))
  testthat::expect_identical(rs$tip, "result")
  testthat::expect_identical(rs$session_id, "s9")
  testthat::expect_identical(rs$html, "bitti")
})

testthat::test_that("format_streaming_chunk_html 'text' parçasını ham içerikle geçirir (kaçışlama yok)", {
  .cchtml_source_once()
  # NOT: 'text' tipi ham içeriği döndürür; kaçışlama markdown/akış katmanında
  # yapılır. Bu davranış mevcut sözleşmedir ve burada belgelenir.
  tx <- format_streaming_chunk_html(list(tip = "text", icerik = "merhaba <b>"))
  testthat::expect_identical(tx$tip, "text")
  testthat::expect_identical(tx$html, "merhaba <b>")
})
