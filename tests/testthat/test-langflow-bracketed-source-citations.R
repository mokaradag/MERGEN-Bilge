# ==============================================================================
# Dosya Yolu: tests/testthat/test-langflow-bracketed-source-citations.R
# Açıklama: Langflow'un köşeli parantez içinde "dosya - açıklama" biçiminde
#           döndürdüğü düzyazı kaynakların tıklanabilir Kaynakça'ya yükseltilmesini
#           doğrular. Tüm örnekler yapay ve kurumsal veri içermeyen fixture'lardır.
# ==============================================================================

.source_langflow_bracketed_test_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  for (f in c(
    "R/utils_common.R",
    "R/helpers_langflow_sources.R",
    "R/helpers_langflow_inline_sources.R"
  )) {
    source(file.path(repo_root, f), encoding = "UTF-8", local = env)
  }

  env
}

test_that("köşeli parantezli dosya-açıklama kaynakları kanonik dosya yoluna ayrıştırılır", {
  env <- .source_langflow_bracketed_test_env()

  metin <- paste0(
    "Süreç riski düzenli izlenir.<sup>(4)</sup>\n\n",
    "Kaynak:\n",
    "(4) [Birim A&&Alt Süreç&&Risk Rehberi.pdf - İzleme yaklaşımının özeti]\n",
    "(7) [Birim A&&Alt Süreç&&Kontrol Listesi.docx - Kontrol adımları]\n"
  )

  parsed <- env$mergen_langflow_parse_prose_sources(metin)

  expect_false(is.null(parsed))
  expect_length(parsed$records, 2L)
  expect_identical(parsed$records[[1]]$path, "Birim A&&Alt Süreç&&Risk Rehberi.pdf")
  expect_identical(parsed$records[[1]]$title, "Risk Rehberi.pdf")
  expect_identical(parsed$records[[1]]$num, "4")
  expect_identical(parsed$records[[2]]$path, "Birim A&&Alt Süreç&&Kontrol Listesi.docx")
  expect_identical(parsed$records[[2]]$type, "docx")
})

test_that("köşeli parantezli kaynaklar üstsimge atıflarıyla aynı yoğun sıraya yükseltilir", {
  testthat::skip_if_not_installed("openssl")
  env <- .source_langflow_bracketed_test_env()

  metin <- paste0(
    "Birinci bulgu.<sup>(4)</sup>\n",
    "İkinci bulgu.<sup>(7)</sup>\n\n",
    "Kaynak:\n",
    "(4) [Birim A&&Alt Süreç&&Risk Rehberi.pdf - Birinci açıklama]\n",
    "(7) [Birim A&&Alt Süreç&&Kontrol Listesi.docx - İkinci açıklama]\n"
  )

  out <- env$mergen_langflow_finalize_answer(metin, list())
  split <- env$mergen_kaynakca_marker_split(out)

  expect_match(out, "Birinci bulgu.[1]", fixed = TRUE)
  expect_match(out, "İkinci bulgu.[2]", fixed = TRUE)
  expect_false(grepl("<sup>", out, fixed = TRUE))
  expect_false(grepl("[Birim A&&", out, fixed = TRUE))
  expect_false(is.null(split))
  expect_length(split$entries, 2L)
  expect_identical(split$entries[[1]]$path, "Birim A&&Alt Süreç&&Risk Rehberi.pdf")
  expect_identical(split$entries[[2]]$path, "Birim A&&Alt Süreç&&Kontrol Listesi.docx")
})

test_that("köşeli parantez biçimi mevcut yol güvenliği sınırlarını gevşetmez", {
  env <- .source_langflow_bracketed_test_env()
  parse <- env$mergen_langflow_parse_prose_sources

  expect_null(parse(
    "Metin.\n\nKaynak:\n(1) [https://ornek.gecersiz/belge.pdf - Açıklama]\n"
  ))
  expect_null(parse(
    "Metin.\n\nKaynak:\n(1) [Birim&&..&&belge.pdf - Açıklama]\n"
  ))
  expect_null(parse(
    "Metin.\n\nKaynak:\n(1) [C:/gizli/belge.docx - Açıklama]\n"
  ))
})
