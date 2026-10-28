# ==============================================================================
# Dosya Yolu: tests/testthat/test-html-trust-boundary-behavior.R
# Açıklama: Model/kullanıcı metninin HTML işaretlemesine dönüşemeyeceğini
#           doğrular: DB'den geri yüklenen ChartLab mesajı sunucuda, Bilge
#           Yolaç akış metni / destek sohbet yanıtı / destek eki adı / bildirim
#           mesajı istemci sink'lerinde (tests/scripts/html_sink_regressions.js).
# ==============================================================================

.html_trust_env <- local({
  env <- NULL
  function() {
    if (!is.null(env)) return(env)
    env <<- new.env(parent = globalenv())
    root <- resolve_repo_root_for_tests()
    for (dosya in c("helpers_markdown_safety.R", "helpers_chartlab_spec.R", "helpers_chartlab.R")) {
      sys.source(file.path(root, "R", dosya), envir = env, keep.source = FALSE)
    }
    env
  }
})

.html_trust_hostile <- c(
  '<img src=x onerror="alert(1)">',
  "<script>alert(1)</script>",
  "<svg/onload=alert(1)>",
  '<a href="javascript:alert(1)">t</a>'
)

.html_trust_chart_json <- function() {
  as.character(jsonlite::toJSON(list(
    type = "line",
    data = data.frame(x = c("a", "b"), y = c(1, 2)),
    mapping = list(x = "x", y = "y"),
    params = list()
  ), auto_unbox = TRUE, dataframe = "rows"))
}

test_that("DB'den geri yüklenen ChartLab mesajında model HTML'i etkisiz kalır", {
  env <- .html_trust_env()

  for (kotu in .html_trust_hostile) {
    metin <- paste0(
      "Önce **kalın** ", kotu, "\n\n```chartlab\n", .html_trust_chart_json(),
      "\n```\n\nSonra ", kotu
    )
    sonuc <- env$build_chartlab_message_static(metin, message_id = "17")

    expect_true(isTRUE(sonuc$found))
    expect_length(sonuc$renderers, 1L)
    # Yalnızca GERÇEK etiketler taranır: kaçışlı metin '&lt;' ile başlar.
    etiketler <- regmatches(sonuc$html, gregexpr("<[A-Za-z][^>]*>", sonuc$html, perl = TRUE))[[1]]
    adlar <- tolower(sub("^<([A-Za-z0-9]+).*$", "\\1", etiketler))
    expect_true(all(adlar %in% c("p", "strong", "div", "br", "em")), info = sonuc$html)
    expect_false(any(grepl("\\son[a-z]+\\s*=", etiketler, perl = TRUE)), info = sonuc$html)
    expect_false(any(grepl("javascript:", etiketler, fixed = TRUE)), info = sonuc$html)
    # Meşru markdown ve Türkçe metin korunur; ham HTML metin olarak görünür.
    expect_match(sonuc$html, "<strong>kalın</strong>", fixed = TRUE)
    expect_match(sonuc$html, "&lt;", fixed = TRUE)
    expect_match(sonuc$html, 'id="chart_17_1"', fixed = TRUE)
  }
})

test_that("canlı ve geri yüklenen ChartLab yolları aynı güvenli metin HTML'ini üretir", {
  env <- .html_trust_env()
  metin <- paste0("Rapor <img src=x onerror=alert(1)> **özet**\n\n```chartlab\n",
                  .html_trust_chart_json(), "\n```")
  oturum <- list(userData = new.env())

  canli <- env$build_chartlab_message(metin, "9", oturum)
  statik <- env$build_chartlab_message_static(metin, "9")

  metin_html <- function(h) sub('<div class="chart-card">.*$', "", h)
  expect_identical(metin_html(statik$html), metin_html(canli$html))
})

test_that("Bilge Yolaç metin parçaları düz metin olarak iletilir (kaçış tek yerde, sink'te)", {
  env <- new.env(parent = globalenv())
  sys.source(file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_formatters.R"),
             envir = env, keep.source = FALSE)
  for (tip in c("text", "result", "raw_text")) {
    out <- env$format_streaming_chunk_html(list(tip = tip, icerik = "a < b <i>"))
    expect_identical(out$html, "a < b <i>", info = tip)
  }

  # Modülün gerçek text_delta yolu: istemciye giden yük kaçışsız düz metindir.
  akis_env <- new.env(parent = globalenv())
  akis_env$`%||%` <- function(x, y) if (is.null(x)) y else x
  sys.source(file.path(resolve_repo_root_for_tests(), "R", "module_claude_code_akis.R"),
             envir = akis_env, keep.source = FALSE)
  giden <- list()
  oturum <- list(sendCustomMessage = function(type, message) giden[[length(giden) + 1L]] <<- list(type = type, message = message))
  yardimci <- akis_env$create_akis_yardimcilari(oturum, function(x) paste0("cc-", x), new.env())
  yardimci$send_parca(list(tip = "text_delta", icerik = "a < b <i> &amp;"),
                      list(karakter_renk = "#000", karakter_adi = "Test", zaman_damgasi = "10:00"))
  expect_length(giden, 1L)
  expect_identical(giden[[1]]$type, "cc-stream-chunk")
  expect_identical(giden[[1]]$message$chunkType, "text_delta")
  expect_identical(giden[[1]]$message$html, "a < b <i> &amp;")
})

test_that("istemci HTML sink'leri model/kullanıcı metnini işaretleme olarak ayrıştırmaz", {
  node <- Sys.which("node")
  skip_if(!nzchar(node), "Node kullanılamıyor")
  script <- file.path(resolve_repo_root_for_tests(), "tests", "scripts", "html_sink_regressions.js")
  sonuc <- system2(node, shQuote(script), stdout = TRUE, stderr = TRUE)
  expect_null(attr(sonuc, "status"), info = paste(sonuc, collapse = "\n"))
  expect_match(paste(sonuc, collapse = "\n"), "html sink regressions passed")
})

test_that("güvenli markdown kod bölgesini tek kez kaçışlar; ham HTML yine oluşamaz", {
  env <- new.env(parent = globalenv())
  sys.source(file.path(resolve_repo_root_for_tests(), "R", "helpers_markdown_safety.R"),
             envir = env, keep.source = FALSE)
  r <- env$render_safe_markdown_html
  expect_match(r("`x <- 1`"), "<code>x &lt;- 1</code>", fixed = TRUE)
  cit <- r("```r\nx <- 1\nif (a > b) y\n```")
  expect_match(cit, "x &lt;- 1\nif (a &gt; b) y", fixed = TRUE)
  expect_false(grepl("&amp;lt;|&amp;gt;", paste(r("`x <- 1`"), cit)))
  # Kod içinde yazılmış varlık metni harfiyen görünür.
  expect_match(r("`&lt;`"), "<code>&amp;lt;</code>", fixed = TRUE)

  # Ham HTML ve işaret karakteri taklidi işaretleme üretmez.
  isaret <- paste0(intToUtf8(0xE000L), "script", intToUtf8(0xE001L), "alert(1)")
  for (girdi in c("<script>alert(1)</script>", "<img src=x onerror=alert(1)>", "`</code><b>x</b>`",
                  isaret, "<https://x.test>")) {
    html <- r(girdi)
    etiketler <- regmatches(html, gregexpr("<[A-Za-z/][^>]*>", html, perl = TRUE))[[1]]
    adlar <- unique(tolower(sub("^</?([A-Za-z0-9]+).*$", "\\1", etiketler)))
    expect_true(all(adlar %in% c("p", "code", "pre", "strong", "em", "br")), info = html)
    expect_false(grepl(intToUtf8(c(0xE000L)), html, fixed = TRUE))
    expect_false(grepl(intToUtf8(c(0xE001L)), html, fixed = TRUE))
  }
})
