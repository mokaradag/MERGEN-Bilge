# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-documentation-behavior.R
# Açıklama: Yönetici paneli "Dokümantasyon" sayfasının DAVRANIŞ testleri.
#            Kapsam:
#              - İzin listeli (allowlist) belge kayıt defteri içeriği
#              - CLAUDE.md / AGENTS.md'nin kayıt defterinde OLMADIĞI
#              - Yol güvenliği: izinli çözüm, bilinmeyen reddi, traversal reddi
#              - UTF-8 Türkçe içerik bütünlüğü
#              - Markdown -> güvenli HTML (kod blokları, tablo, liste)
#              - Tehlikeli HTML/script/olay-yakalayıcı etkisizleştirme sınırı
#              - Başlıklardan ASCII-güvenli çapa + İçindekiler (TOC)
#              - UI üreticileri (kart listesi, TOC, içerik)
#              - adminDokumantasyonServer (testServer ile gerçek davranış)
#            Tümüyle çevrimdışı ve deterministiktir: DB/SSO/ağ/tarayıcı gerekmez.
# ==============================================================================

# İzole ortama saf yardımcı + modülü yükler.
.source_admin_doc_env <- function() {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("commonmark")
  suppressMessages(library(shiny))
  root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  source(file.path(root, "R", "utils_text_encoding.R"), encoding = "UTF-8", local = env)
  source(file.path(root, "R", "helpers_admin_documentation.R"), encoding = "UTF-8", local = env)
  source(file.path(root, "R", "module_admin_documentation.R"), encoding = "UTF-8", local = env)
  env
}

# renderUI çıktısını metne çevirir (testServer hem liste hem karakter dönebilir).
.admin_doc_read_ui <- function(x) {
  if (is.list(x) && !is.null(x$html)) return(as.character(x$html))
  paste(as.character(x), collapse = "")
}

# ------------------------------------------------------------------------------
# Kayıt defteri (allowlist) içeriği
# ------------------------------------------------------------------------------
testthat::test_that("kayıt defteri beklenen 10 belgeyi ve 4 grubu içerir", {
  env <- .source_admin_doc_env()
  groups <- env$admin_doc_registry()
  testthat::expect_equal(length(groups), 4L)
  testthat::expect_equal(
    vapply(groups, function(g) g$id, character(1)),
    c("baslangic", "mimari", "operasyon", "urun")
  )

  docs <- env$admin_doc_all_docs()
  testthat::expect_equal(length(docs), 10L)

  files <- vapply(docs, function(d) d$file, character(1))
  beklenen <- c(
    "README.md", "docs/README.md", "docs/architecture-map.md",
    "docs/database-schema.md", "docs/technical-reference.md",
    "RUNBOOK.md", "docs/dependency-locking.md", "RENV_LOCK_STATUS.md",
    "ai_rehber.md", "docs/release-notes.md"
  )
  testthat::expect_true(all(beklenen %in% files))
})

testthat::test_that("CLAUDE.md ve AGENTS.md kayıt defterinde gösterilmez", {
  env <- .source_admin_doc_env()
  files <- vapply(env$admin_doc_all_docs(), function(d) d$file, character(1))
  testthat::expect_false("CLAUDE.md" %in% files)
  testthat::expect_false("AGENTS.md" %in% files)
  # Belge kimliği olarak da bilinmezler
  testthat::expect_false(env$admin_doc_is_known("claude"))
  testthat::expect_false(env$admin_doc_is_known("agents"))
})

testthat::test_that("varsayılan grup/belge ve grup üyeliği doğrudur", {
  env <- .source_admin_doc_env()
  testthat::expect_identical(env$admin_doc_default_group_id(), "baslangic")
  testthat::expect_identical(env$admin_doc_default_doc_id(), "readme")

  op_docs <- env$admin_doc_docs_in_group("operasyon")
  op_ids <- vapply(op_docs, function(d) d$id, character(1))
  testthat::expect_true("runbook" %in% op_ids)
  testthat::expect_true("renv_status" %in% op_ids)
  testthat::expect_equal(length(env$admin_doc_docs_in_group("olmayan_grup")), 0L)
})

# ------------------------------------------------------------------------------
# Yol güvenliği
# ------------------------------------------------------------------------------
testthat::test_that("izinli belge kimliği gerçek dosyaya çözülür", {
  env <- .source_admin_doc_env()
  root <- resolve_repo_root_for_tests()
  p <- env$admin_doc_resolve_path("readme", root)
  testthat::expect_true(nzchar(p))
  testthat::expect_true(file.exists(p))
  testthat::expect_true(endsWith(p, "README.md"))
})

testthat::test_that("bilinmeyen kimlik ve yol kaçışı reddedilir", {
  env <- .source_admin_doc_env()
  root <- resolve_repo_root_for_tests()
  # Bilinmeyen kimlik
  testthat::expect_identical(env$admin_doc_resolve_path("bilinmeyen_id", root), "")
  testthat::expect_identical(env$admin_doc_resolve_path("claude", root), "")
  # Traversal benzeri kimlik (kayıt defterinde yok -> "")
  testthat::expect_identical(env$admin_doc_resolve_path("../../etc/passwd", root), "")
  testthat::expect_identical(env$admin_doc_resolve_path("..\\..\\windows", root), "")
  # NULL / boş
  testthat::expect_identical(env$admin_doc_resolve_path(NULL, root), "")
  testthat::expect_identical(env$admin_doc_resolve_path("", root), "")
})

# ------------------------------------------------------------------------------
# UTF-8 Türkçe içerik
# ------------------------------------------------------------------------------
testthat::test_that("Türkçe belge içeriği UTF-8 bütünlüğünü korur", {
  env <- .source_admin_doc_env()
  root <- resolve_repo_root_for_tests()
  content <- env$admin_doc_read_markdown(env$admin_doc_resolve_path("readme", root))
  testthat::expect_true(nzchar(content))
  testthat::expect_identical(Encoding(content), "UTF-8")
  # README Türkçe metin içerir
  testthat::expect_true(grepl("Türkçe", content, fixed = TRUE))
  # Mojibake işareti olmamalı
  testthat::expect_false(grepl("Ã§|Ä±|Ã¶|ÅŸ", content, perl = TRUE))
})

# ------------------------------------------------------------------------------
# Markdown render: kod blokları, tablo, liste
# ------------------------------------------------------------------------------
testthat::test_that("kod blokları R atamasını (<-) bozmadan render eder", {
  env <- .source_admin_doc_env()
  md <- "```r\nx <- f(a, b)\nif (a < b) y <- 1\n```\n"
  out <- env$admin_doc_render_markdown(md)
  testthat::expect_true(grepl("<pre>", out$html, fixed = TRUE))
  testthat::expect_true(grepl("x &lt;- f(a, b)", out$html, fixed = TRUE))
  # Çift escape (mojibake) olmamalı
  testthat::expect_false(grepl("&amp;lt;", out$html, fixed = TRUE))
})

testthat::test_that("tablo ve liste render yolu kararlıdır", {
  env <- .source_admin_doc_env()
  md <- paste0(
    "| K | V |\n|---|---|\n| a | b |\n\n",
    "- madde bir\n- madde iki\n"
  )
  out <- env$admin_doc_render_markdown(md)
  testthat::expect_true(grepl("<table>", out$html, fixed = TRUE))
  testthat::expect_true(grepl("<th>", out$html, fixed = TRUE))
  testthat::expect_true(grepl("<ul>", out$html, fixed = TRUE))
  testthat::expect_true(grepl("<li>madde bir</li>", out$html, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# Güvenlik: tehlikeli HTML/script/olay-yakalayıcı etkisizleştirme
# ------------------------------------------------------------------------------
testthat::test_that("script/iframe/olay-yakalayıcı/javascript: etkisizleştirilir", {
  env <- .source_admin_doc_env()
  md <- paste0(
    "Metin\n\n",
    "<script>alert(1)</script>\n\n",
    "<img src=x onerror=\"alert(2)\">\n\n",
    "<a href=\"javascript:evil()\" onclick=\"bad()\">link</a>\n\n",
    "<iframe src=\"http://x\"></iframe>\n\n",
    "[md link](javascript:alsoBad())\n"
  )
  out <- env$admin_doc_render_markdown(md)
  html <- out$html

  # Aktif script/iframe olmamalı; escape edilmiş biçimi olmalı
  testthat::expect_false(grepl("<script>", html, fixed = TRUE))
  testthat::expect_true(grepl("&lt;script&gt;", html, fixed = TRUE))
  testthat::expect_false(grepl("<iframe", html, fixed = TRUE))

  # Olay yakalayıcılar ve tehlikeli protokoller kaldırılmalı
  testthat::expect_false(grepl("onerror", html, fixed = TRUE))
  testthat::expect_false(grepl("onclick", html, fixed = TRUE))
  testthat::expect_false(grepl("javascript:", html, fixed = TRUE))
})

testthat::test_that("güvenli yapısal HTML (p, a, code) korunur", {
  env <- .source_admin_doc_env()
  out <- env$admin_doc_render_markdown("Bu **kalın** ve `kod` ve [bağ](https://ornek.test).\n")
  html <- out$html
  testthat::expect_true(grepl("<strong>kalın</strong>", html, fixed = TRUE))
  testthat::expect_true(grepl("<code>kod</code>", html, fixed = TRUE))
  testthat::expect_true(grepl("href=\"https://ornek.test\"", html, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# TOC + çapa üretimi
# ------------------------------------------------------------------------------
testthat::test_that("başlıklar ASCII-güvenli çapa ve İçindekiler üretir", {
  env <- .source_admin_doc_env()
  md <- "# Başlık Bir\n\nmetin\n\n## İkinci Bölüm\n\nmetin\n"
  out <- env$admin_doc_render_markdown(md)

  testthat::expect_equal(length(out$toc), 2L)
  testthat::expect_identical(out$toc[[1]]$text, "Başlık Bir")
  testthat::expect_identical(out$toc[[1]]$level, 1L)
  # Çapa ASCII-güvenli (Türkçe çevrilmiş), mbdoc- önekli
  testthat::expect_identical(out$toc[[1]]$id, "mbdoc-baslik-bir")
  testthat::expect_identical(out$toc[[2]]$id, "mbdoc-ikinci-bolum")
  # HTML içinde id enjekte edilmiş
  testthat::expect_true(grepl("id=\"mbdoc-baslik-bir\"", out$html, fixed = TRUE))
  # Çapa yalnızca ASCII içerir (Türkçe locale güvenli)
  testthat::expect_false(grepl("[^\\x20-\\x7e]", out$toc[[1]]$id, perl = TRUE))
})

testthat::test_that("çakışan başlıklar benzersiz çapa alır", {
  env <- .source_admin_doc_env()
  md <- "## Notlar\n\na\n\n## Notlar\n\nb\n"
  out <- env$admin_doc_render_markdown(md)
  ids <- vapply(out$toc, function(t) t$id, character(1))
  testthat::expect_equal(length(unique(ids)), length(ids))
  testthat::expect_identical(ids[1], "mbdoc-notlar")
  testthat::expect_identical(ids[2], "mbdoc-notlar-2")
})

testthat::test_that("slugify Türkçe karakterleri ASCII'ye çevirir (locale-bağımsız)", {
  env <- .source_admin_doc_env()
  testthat::expect_identical(env$admin_doc_slugify("Çğıİöşü ALANI"), "cgiiosu-alani")
  testthat::expect_identical(env$admin_doc_slugify("   "), "bolum")
  testthat::expect_identical(env$admin_doc_slugify("API Anahtarı"), "api-anahtari")
})

# ------------------------------------------------------------------------------
# Tüm gerçek belgeler render edilebilir
# ------------------------------------------------------------------------------
testthat::test_that("kayıt defterindeki tüm belgeler hatasız render edilir", {
  env <- .source_admin_doc_env()
  root <- resolve_repo_root_for_tests()
  for (d in env$admin_doc_all_docs()) {
    res <- env$admin_doc_render_document(d$id, root)
    testthat::expect_true(isTRUE(res$ok),
                          info = paste("render başarısız:", d$id))
    testthat::expect_true(nzchar(res$html), info = d$id)
    testthat::expect_false(grepl("<script>", res$html, fixed = TRUE), info = d$id)
  }
})

testthat::test_that("bilinmeyen belge güvenli hata sonucu döndürür", {
  env <- .source_admin_doc_env()
  res <- env$admin_doc_render_document("yok_boyle_belge", resolve_repo_root_for_tests())
  testthat::expect_false(isTRUE(res$ok))
  testthat::expect_identical(res$html, "")
  testthat::expect_true(nzchar(res$message))
})

# ------------------------------------------------------------------------------
# UI üreticileri
# ------------------------------------------------------------------------------
testthat::test_that("admin_doc_card_list_ui kart ve namespaced girdi üretir", {
  env <- .source_admin_doc_env()
  docs <- env$admin_doc_docs_in_group("baslangic")
  html <- paste(as.character(env$admin_doc_card_list_ui(NS("doc"), docs, "readme")),
                collapse = "\n")
  testthat::expect_true(grepl("data-doc-input=\"doc-doc_select\"", html, fixed = TRUE))
  testthat::expect_true(grepl("data-doc-id=\"readme\"", html, fixed = TRUE))
  testthat::expect_true(grepl("mb-doc-card-active", html, fixed = TRUE))
  testthat::expect_true(grepl("aria-pressed=\"true\"", html, fixed = TRUE))
})

testthat::test_that("admin_doc_toc_ui İçindekiler bağlantılarını üretir", {
  env <- .source_admin_doc_env()
  toc <- list(
    list(level = 1L, text = "Birinci", id = "mbdoc-birinci"),
    list(level = 2L, text = "İkinci", id = "mbdoc-ikinci"),
    list(level = 4L, text = "Derin", id = "mbdoc-derin")
  )
  html <- paste(as.character(env$admin_doc_toc_ui(NS("doc"), toc)), collapse = "\n")
  testthat::expect_true(grepl("data-target-id=\"mbdoc-birinci\"", html, fixed = TRUE))
  testthat::expect_true(grepl("mb-doc-toc-link", html, fixed = TRUE))
  # 4. seviye gösterilmez (1-3 ile sınırlı)
  testthat::expect_false(grepl("mbdoc-derin", html, fixed = TRUE))

  bos <- paste(as.character(env$admin_doc_toc_ui(NS("doc"), list())), collapse = "\n")
  testthat::expect_true(grepl("Bu belgede başlık bulunamadı", bos, fixed = TRUE))
})

testthat::test_that("admin_doc_build_content_ui içerik + salt okunur not üretir", {
  env <- .source_admin_doc_env()
  render <- list(ok = TRUE, source = "README.md",
                 html = "<h2>Test</h2><p>içerik</p>",
                 toc = list(list(level = 2L, text = "Test", id = "mbdoc-test")),
                 message = "")
  html <- paste(as.character(
    env$admin_doc_build_content_ui(NS("doc"), "baslangic", "readme", render)
  ), collapse = "\n")
  testthat::expect_true(grepl("Kaynak dosya:", html, fixed = TRUE))
  testthat::expect_true(grepl("README.md", html, fixed = TRUE))
  testthat::expect_true(grepl("salt okunur", html, fixed = TRUE))
  testthat::expect_true(grepl("<h2>Test</h2>", html, fixed = TRUE))
  testthat::expect_true(grepl("mb-doc-toc-toggle", html, fixed = TRUE))
})

testthat::test_that("admin_doc_build_content_ui hata durumunda mesaj gösterir", {
  env <- .source_admin_doc_env()
  render <- list(ok = FALSE, source = "yok.md", html = "", toc = list(),
                 message = "Belge dosyası bulunamadı.")
  html <- paste(as.character(
    env$admin_doc_build_content_ui(NS("doc"), "operasyon", "runbook", render)
  ), collapse = "\n")
  testthat::expect_true(grepl("Belge dosyası bulunamadı.", html, fixed = TRUE))
  testthat::expect_true(grepl("mb-doc-empty", html, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# Güvenlik yardımcıları (doğrudan)
# ------------------------------------------------------------------------------
testthat::test_that("admin_doc_html_has_risk riskli/temiz HTML'i ayırt eder", {
  env <- .source_admin_doc_env()
  testthat::expect_false(env$admin_doc_html_has_risk("<p>güvenli metin</p><a href=\"https://x\">b</a>"))
  testthat::expect_true(env$admin_doc_html_has_risk("<p>x</p><script>e()</script>"))
  testthat::expect_true(env$admin_doc_html_has_risk("<a onclick=\"x()\">y</a>"))
  testthat::expect_true(env$admin_doc_html_has_risk("<a href=\"javascript:x()\">y</a>"))
  testthat::expect_true(env$admin_doc_html_has_risk("<iframe src=\"http://x\"></iframe>"))
})

testthat::test_that("admin_doc_sanitize_html hızlı yolda temiz HTML'i değiştirmez", {
  env <- .source_admin_doc_env()
  safe <- "<h2>Başlık</h2>\n<p>İçerik <code>x &lt;- 1</code></p>\n<ul>\n<li>a</li>\n</ul>"
  testthat::expect_identical(env$admin_doc_sanitize_html(safe), safe)
})

testthat::test_that("admin_doc_sanitize_html riskli etiket/öznitelikleri etkisizleştirir", {
  env <- .source_admin_doc_env()
  out <- env$admin_doc_sanitize_html(
    "<p>iyi</p><script>bad()</script><img src=x onerror=\"e()\"><a href=\"javascript:z()\">l</a>"
  )
  testthat::expect_true(grepl("<p>iyi</p>", out, fixed = TRUE))
  testthat::expect_false(grepl("<script>", out, fixed = TRUE))
  testthat::expect_true(grepl("&lt;script&gt;", out, fixed = TRUE))
  testthat::expect_false(grepl("onerror", out, fixed = TRUE))
  testthat::expect_false(grepl("javascript:", out, fixed = TRUE))
})

testthat::test_that("admin_doc_clean_attributes olay/style/protokolleri temizler, sınıfı korur", {
  env <- .source_admin_doc_env()
  cleaned <- env$admin_doc_clean_attributes(
    " class=\"ok\" onclick=\"x()\" style=\"color:red\" href=\"javascript:y()\""
  )
  testthat::expect_true(grepl("class=\"ok\"", cleaned, fixed = TRUE))
  testthat::expect_false(grepl("onclick", cleaned, fixed = TRUE))
  testthat::expect_false(grepl("style=", cleaned, fixed = TRUE))
  testthat::expect_true(grepl("href=\"#\"", cleaned, fixed = TRUE))
})

testthat::test_that("admin_doc_clean_one_tag izinli/izinsiz/yorum etiketleri doğru işler", {
  env <- .source_admin_doc_env()
  testthat::expect_identical(env$admin_doc_clean_one_tag("<p>"), "<p>")
  testthat::expect_identical(env$admin_doc_clean_one_tag("</p>"), "</p>")
  testthat::expect_identical(env$admin_doc_clean_one_tag("<!-- yorum -->"), "")
  testthat::expect_true(grepl("&lt;script&gt;",
                              env$admin_doc_clean_one_tag("<script>"), fixed = TRUE))
  img <- env$admin_doc_clean_one_tag("<img src=x onerror=alert(1)>")
  testthat::expect_false(grepl("onerror", img, fixed = TRUE))
})

testthat::test_that("admin_doc_extract_toc id enjekte eder ve benzersizlik sağlar", {
  env <- .source_admin_doc_env()
  res <- env$admin_doc_extract_toc("<h2>Aynı</h2>\n<h3>Aynı</h3>")
  testthat::expect_equal(length(res$toc), 2L)
  ids <- vapply(res$toc, function(t) t$id, character(1))
  testthat::expect_equal(length(unique(ids)), 2L)
  testthat::expect_true(grepl(paste0("id=\"", ids[1], "\""), res$html, fixed = TRUE))
  # Başlık yoksa toc boş, html değişmez
  bos <- env$admin_doc_extract_toc("<p>yok</p>")
  testthat::expect_equal(length(bos$toc), 0L)
  testthat::expect_identical(bos$html, "<p>yok</p>")
})

# ------------------------------------------------------------------------------
# Sunucu davranışı (testServer)
# ------------------------------------------------------------------------------
testthat::test_that("adminDokumantasyonServer belge seçimi ve grup geçişini yönetir", {
  env <- .source_admin_doc_env()
  env$showToast <- function(...) invisible(NULL)

  shiny::testServer(env$adminDokumantasyonServer, {
    # Başlangıç: README (baslangic grubu)
    out0 <- .admin_doc_read_ui(output$tab_content_area)
    testthat::expect_true(grepl("README.md", out0, fixed = TRUE))

    # Grup geçişi -> operasyon: ilk belge RUNBOOK
    session$setInputs(admin_tabs = "operasyon")
    out1 <- .admin_doc_read_ui(output$tab_content_area)
    testthat::expect_true(grepl("RUNBOOK.md", out1, fixed = TRUE))

    # Belge kartı seçimi -> dependency-locking
    session$setInputs(doc_select = "dependency")
    out2 <- .admin_doc_read_ui(output$tab_content_area)
    testthat::expect_true(grepl("docs/dependency-locking.md", out2, fixed = TRUE))

    # Bilinmeyen kimlik reddedilir: seçim değişmez (hâlâ dependency)
    session$setInputs(doc_select = "claude")
    out3 <- .admin_doc_read_ui(output$tab_content_area)
    testthat::expect_true(grepl("docs/dependency-locking.md", out3, fixed = TRUE))
    testthat::expect_false(grepl("CLAUDE.md", out3, fixed = TRUE))
  })
})

testthat::test_that("adminDokumantasyonServer yenile butonu önbelleği temizler ve toast gönderir", {
  env <- .source_admin_doc_env()
  toast_recorder <- new.env(parent = emptyenv())
  toast_recorder$count <- 0L
  env$showToast <- function(session, message, ...) {
    toast_recorder$count <- toast_recorder$count + 1L
    toast_recorder$last <- message
    invisible(NULL)
  }
  testthat::local_mocked_bindings(runjs = function(...) invisible(NULL), .package = "shinyjs")

  shiny::testServer(env$adminDokumantasyonServer, {
    # observeEvent(ignoreInit = TRUE): ilk set init olarak tüketilir, ikinci set tetikler
    session$setInputs(refresh_analytics = 1)
    session$setInputs(refresh_analytics = 2)
    testthat::expect_equal(toast_recorder$count, 1L)
    testthat::expect_true(grepl("yenilendi", toast_recorder$last, fixed = TRUE))
  })
})
