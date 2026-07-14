# ==============================================================================
# Dosya Yolu: tests/testthat/test-ortak-oturum-yanit-icerik-behavior.R
# Açıklama: Ortak Oturum yapay zekâ yanıtı zengin içerik katmanının davranış
#           testleri: kod blokları tekil oturumla aynı .code-container yapısını
#           alır (çift kaçış YOK), ```chartlab blokları namespaceli grafik
#           konteynerine dönüşür ve wire_chart_output ile bağlanır, kaynakça
#           işaretleyici bloğu korunur, ham HTML inert kalır.
#           DB, LLM, tarayıcı veya ağ GEREKMEZ.
# ==============================================================================

testthat::skip_if_not_installed("shiny")
testthat::skip_if_not_installed("jsonlite")
testthat::skip_if_not_installed("commonmark")
testthat::skip_if_not_installed("stringr")

suppressPackageStartupMessages(library(shiny))

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  if (!exists("render_safe_markdown_html", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_markdown_safety.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("detect_language", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_language.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("process_message_content", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_messaging.R"),
           encoding = "UTF-8", local = globalenv())
  }

  source(file.path(repo_root, "R", "helpers_ortak_oturum_yanit_icerik.R"),
         encoding = "UTF-8", local = globalenv())
})

test_that("kod blokları .code-container yapısına dönüşür ve çift kaçış olmaz", {
  metin <- paste(
    "Merhaba! İşte kod:",
    "```cpp",
    "#include <iostream>",
    "int main() { return 0; }",
    "```",
    "Açıklama satırı.",
    sep = "\n"
  )

  sonuc <- oo_yanit_icerik_html(metin, mesaj_id = "42")
  html <- sonuc$html

  # Tekil oturumla aynı kod kabı: başlık, kopyalama, CodeMirror textarea.
  expect_true(grepl("code-container", html, fixed = TRUE))
  expect_true(grepl("codemirror-textarea", html, fixed = TRUE))
  expect_true(grepl("copyCodeFromCM", html, fixed = TRUE))

  # Çift kaçış regresyonu: kod içinde '&amp;lt;' ASLA üretilmez; '<' tek
  # kademe kaçışla '&lt;' olarak durur (tarayıcı '<' gösterir).
  expect_false(grepl("&amp;lt;", html, fixed = TRUE))
  expect_true(grepl("#include &lt;iostream&gt;", html, fixed = TRUE))

  # Düzyazı güvenli markdown yolundan geçer.
  expect_true(grepl("Açıklama satırı", html, fixed = TRUE))
  expect_identical(length(sonuc$grafikler), 0L)
})

test_that("ham HTML/script yükleri inert kalır (XSS sınırı)", {
  metin <- "Deneme <script>alert(1)</script> ve <img src=x onerror=alert(2)>"
  html <- oo_yanit_icerik_html(metin, mesaj_id = "7")$html

  expect_false(grepl("<script>alert(1)</script>", html, fixed = TRUE))
  expect_false(grepl("<img src=x", html, fixed = TRUE))
  expect_true(grepl("&lt;script&gt;", html, fixed = TRUE))
})

test_that("chartlab blokları namespaceli grafik konteynerine dönüşür ve bağlanır", {
  spec <- list(
    type = "bar",
    mapping = list(x = "kategori", y = "adet"),
    data = list(kategori = c("A", "B"), adet = c(3, 5))
  )
  metin <- paste0(
    "İşte analiz sonucu:\n\n```chartlab\n",
    as.character(jsonlite::toJSON(spec, auto_unbox = TRUE)),
    "\n```\n\nDeğerlendirme metni."
  )

  ns_fn <- shiny::NS("ortak_calismalar_module-oda")
  sonuc <- oo_yanit_icerik_html(metin, mesaj_id = "12", ns_fn = ns_fn)

  # Konteyner kimliği DOM'da namespaceli; bağlama listesi HAM kimliği taşır
  # (modül output ataması Shiny tarafından namespace'lenir).
  expect_identical(length(sonuc$grafikler), 1L)
  expect_identical(sonuc$grafikler[[1]]$output_id, "chart_oo12_1")
  expect_true(grepl(ns_fn("chart_oo12_1"), sonuc$html, fixed = TRUE))
  expect_true(grepl("oo-grafik-karti", sonuc$html, fixed = TRUE))

  # Metin parçaları korunur.
  expect_true(grepl("analiz sonucu", sonuc$html, fixed = TRUE))
  expect_true(grepl("Değerlendirme metni", sonuc$html, fixed = TRUE))

  # Bağlama: wire_chart_output sahte motorla çağrılır (tek motor sözleşmesi).
  # Önceki değer kaydedilir/geri yüklenir (kör rm cross-file pollution yapmasın).
  cagrilar <- new.env(parent = emptyenv()); cagrilar$n <- 0L; cagrilar$son_id <- ""
  .onceki_wire <- if (exists("wire_chart_output", envir = globalenv(), inherits = FALSE)) {
    get("wire_chart_output", envir = globalenv())
  } else {
    NULL
  }
  wire_chart_output <<- function(output, out_id, spec) {
    cagrilar$n <- cagrilar$n + 1L
    cagrilar$son_id <- out_id
    invisible(NULL)
  }
  withr::defer({
    if (is.null(.onceki_wire)) {
      suppressWarnings(rm("wire_chart_output", envir = globalenv()))
    } else {
      assign("wire_chart_output", .onceki_wire, envir = globalenv())
    }
  })

  sahte_output <- list()
  baglanan <- oo_yanit_grafikleri_bagla(sahte_output, sonuc$grafikler)
  expect_identical(baglanan, 1L)
  expect_identical(cagrilar$son_id, "chart_oo12_1")
})

test_that("verisi gömülü olmayan (yalnız ref) grafik dürüst uyarı kartına düşer", {
  metin <- "Önce\n\n```chartlab\n{\"type\":\"bar\",\"ref\":\"cl_123\"}\n```\n\nSonra"
  sonuc <- oo_yanit_icerik_html(metin, mesaj_id = "3")

  expect_identical(length(sonuc$grafikler), 0L)
  expect_true(grepl("oo-grafik-uyari", sonuc$html, fixed = TRUE))
  expect_true(grepl("çözümlenemedi", sonuc$html, fixed = TRUE))
})

test_that("kapanmamış chartlab bloğu güvenli düz metin olarak kalır", {
  metin <- "Metin\n\n```chartlab\n{\"type\":\"bar\""
  sonuc <- oo_yanit_icerik_html(metin, mesaj_id = "5")
  expect_identical(length(sonuc$grafikler), 0L)
  expect_true(nzchar(sonuc$html))
})

test_that("kaynakça işaretleyici bloğu zengin içerikte korunur", {
  # Marker yardımcıları bu izole bağlamda yüklü olmayabilir; sahteleriyle
  # sözleşme (split + scope=model_bases HTML) doğrulanır. Tam suite paylaşılan
  # oturumunda GERÇEK yardımcılar önceden yüklenmiş olabilir; bu yüzden önceki
  # değer KAYDEDİLİR ve geri yüklenir (kör rm, başka testlerin bağımlı olduğu
  # gerçek fonksiyonu silmesin — cross-file pollution koruması).
  .onceki_split <- if (exists("mergen_kaynakca_marker_split", envir = globalenv(), inherits = FALSE)) {
    get("mergen_kaynakca_marker_split", envir = globalenv())
  } else {
    NULL
  }
  .onceki_html <- if (exists("mergen_kaynakca_marker_html", envir = globalenv(), inherits = FALSE)) {
    get("mergen_kaynakca_marker_html", envir = globalenv())
  } else {
    NULL
  }
  mergen_kaynakca_marker_split <<- function(metin) {
    if (!grepl("[KAYNAK 1]", metin, fixed = TRUE)) {
      return(list(prose = metin, entries = list()))
    }
    list(
      prose = sub("\\n\\[KAYNAK 1\\].*$", "", metin),
      entries = list(list(n = 1L, ad = "belge.pdf"))
    )
  }
  mergen_kaynakca_marker_html <<- function(entries, scope = NULL) {
    sprintf('<div class="test-kaynakca" data-scope="%s">%d kaynak</div>',
            as.character(scope %||% ""), length(entries))
  }
  withr::defer({
    if (is.null(.onceki_split)) {
      suppressWarnings(rm("mergen_kaynakca_marker_split", envir = globalenv()))
    } else {
      assign("mergen_kaynakca_marker_split", .onceki_split, envir = globalenv())
    }
    if (is.null(.onceki_html)) {
      suppressWarnings(rm("mergen_kaynakca_marker_html", envir = globalenv()))
    } else {
      assign("mergen_kaynakca_marker_html", .onceki_html, envir = globalenv())
    }
  })

  metin <- "Yanıt gövdesi.\n[KAYNAK 1] belge.pdf | kod=abc"
  sonuc <- oo_mesaj_yz_icerigi(metin, mesaj_id = "9")

  expect_true(grepl("Yanıt gövdesi", sonuc$html, fixed = TRUE))
  expect_true(grepl('data-scope="model_bases"', sonuc$html, fixed = TRUE))
  expect_true(grepl("1 kaynak", sonuc$html, fixed = TRUE))
})

test_that("boş/NA metin güvenli boş çıktı üretir", {
  expect_identical(oo_yanit_icerik_html("", "1")$html, "")
  expect_identical(oo_yanit_icerik_html(NA_character_, "1")$html, "")
  expect_identical(length(oo_yanit_icerik_html(NULL, "1")$grafikler), 0L)
})
