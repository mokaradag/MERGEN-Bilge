# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-text-bundle-behavior.R
# Açıklama: R/helpers_llm_response_postprocess.R içindeki extract_llm_text_bundle
#           fonksiyonunun DAVRANIŞSAL testleri (mevcut testlerde çağrılmıyordu).
#           Bu, NON-STREAMING tam yanıt nesnesinden görünür içerik ile reasoning'i
#           ayırır (extract_llm_delta_bundle'ın SSE-dışı muadili). Beklentiler
#           gerçek fonksiyon davranışına göre yazılmıştır: desteklenen yollar
#           message/delta/choices.text ve üst-düzey content/reasoning(_content)'tir;
#           output_text, üst-düzey 'text' ve message$thinking DESTEKLENMEZ
#           (karakterizasyon). Parse edilmiş R listeleri alınır; jsonlite/HTTP/DB
#           /Shiny GEREKMEZ.
# ==============================================================================

.llmbundle_source_once <- function() {
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  if (!exists("extract_llm_text_bundle",
              envir = globalenv(), mode = "function", inherits = TRUE)) {
    source(
      file.path(resolve_repo_root_for_tests(), "R", "helpers_llm_response_postprocess.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  invisible(TRUE)
}

testthat::test_that("extract_llm_text_bundle liste-olmayanı içerik, boşu boş paket yapar", {
  .llmbundle_source_once()
  b1 <- extract_llm_text_bundle("düz metin")
  testthat::expect_identical(enc2utf8(b1$content), enc2utf8("düz metin"))
  testthat::expect_identical(b1$reasoning, "")

  b2 <- extract_llm_text_bundle(list())
  testthat::expect_identical(b2$content, "")
  testthat::expect_identical(b2$reasoning, "")
})

testthat::test_that("extract_llm_text_bundle choices/message içerik ve reasoning'i ayırır", {
  .llmbundle_source_once()
  b <- extract_llm_text_bundle(list(choices = list(list(message = list(
    content = "cevap",
    reasoning_content = "dusunce"
  )))))
  testthat::expect_identical(b$content, "cevap")
  testthat::expect_identical(b$reasoning, "dusunce")

  # message$reasoning (reasoning_content yoksa) da yakalanır.
  b2 <- extract_llm_text_bundle(list(choices = list(list(message = list(reasoning = "r2")))))
  testthat::expect_identical(b2$content, "")
  testthat::expect_identical(b2$reasoning, "r2")
})

testthat::test_that("extract_llm_text_bundle delta content/text ve choices text yollarını kullanır", {
  .llmbundle_source_once()
  testthat::expect_identical(
    extract_llm_text_bundle(list(choices = list(list(delta = list(content = "dc")))))$content,
    "dc"
  )
  testthat::expect_identical(
    extract_llm_text_bundle(list(choices = list(list(delta = list(text = "dt")))))$content,
    "dt"
  )
  testthat::expect_identical(
    extract_llm_text_bundle(list(choices = list(list(text = "ct"))))$content,
    "ct"
  )
})

testthat::test_that("extract_llm_text_bundle üst-düzey content/reasoning fallback'lerini kullanır", {
  .llmbundle_source_once()
  # choices yok -> üst düzey content.
  testthat::expect_identical(extract_llm_text_bundle(list(content = "duz"))$content, "duz")
  # Üst düzey reasoning ve reasoning_content -> reasoning (content boş).
  testthat::expect_identical(extract_llm_text_bundle(list(reasoning = "ud"))$reasoning, "ud")
  testthat::expect_identical(
    extract_llm_text_bundle(list(reasoning_content = "urc"))$reasoning,
    "urc"
  )
})

testthat::test_that("extract_llm_text_bundle desteklenmeyen anahtarları yok sayar (karakterizasyon)", {
  .llmbundle_source_once()
  # output_text desteklenen bir alan DEĞİLDİR -> boş içerik.
  testthat::expect_identical(extract_llm_text_bundle(list(output_text = "ot"))$content, "")
  # Üst düzey 'text' (choices olmadan) da kullanılmaz.
  testthat::expect_identical(extract_llm_text_bundle(list(text = "tt"))$content, "")
  # message$thinking reasoning olarak alınmaz (yalnızca reasoning/reasoning_content).
  testthat::expect_identical(
    extract_llm_text_bundle(list(choices = list(list(message = list(thinking = "tk")))))$reasoning,
    ""
  )
})

testthat::test_that("extract_llm_text_bundle Türkçe içeriği UTF-8 olarak korur", {
  .llmbundle_source_once()
  b <- extract_llm_text_bundle(list(choices = list(list(message = list(
    content = "Görüşme özeti hazırlandı"
  )))))
  testthat::expect_identical(enc2utf8(b$content), enc2utf8("Görüşme özeti hazırlandı"))
})
