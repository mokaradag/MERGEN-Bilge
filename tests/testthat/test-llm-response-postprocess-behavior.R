# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-response-postprocess-behavior.R
# Açıklama: LLM yanıt sonradan-işleme yardımcılarının davranışsal testleri.
#           Metin düğümü normalizasyonu, ilk-dolu metin seçimi, içerik/akıl
#           yürütme ayrımı ve kaynak geçişi doğrulanır. Saf fonksiyonlardır;
#           DB/LLM/ağ/tarayıcı gerekmez.
# ==============================================================================

.llm_postprocess_source_once <- function() {
  if (exists("normalize_llm_text_node", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("extract_llm_text_bundle", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_llm_response_postprocess.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

testthat::test_that("normalize_llm_text_node çeşitli düğüm tiplerini güvenli metne indirir", {
  .llm_postprocess_source_once()

  testthat::expect_identical(normalize_llm_text_node(NULL), "")
  testthat::expect_identical(normalize_llm_text_node("merhaba"), "merhaba")
  # Karakter vektörü birleştirilir, NA atılır.
  testthat::expect_identical(normalize_llm_text_node(c("a", "b")), "ab")
  testthat::expect_identical(normalize_llm_text_node(c("a", NA, "b")), "ab")
  # Atomik sayısal -> karakter.
  testthat::expect_identical(normalize_llm_text_node(42), "42")
  # Liste düğümleri öncelik sırasıyla: text > content > reasoning.
  testthat::expect_identical(normalize_llm_text_node(list(text = "t", content = "c")), "t")
  testthat::expect_identical(normalize_llm_text_node(list(content = "c")), "c")
  testthat::expect_identical(normalize_llm_text_node(list(reasoning_content = "rc")), "rc")
  # İsimsiz iç içe liste -> parçalar birleştirilir.
  testthat::expect_identical(
    normalize_llm_text_node(list(list(text = "x"), list(text = "y"))),
    "xy"
  )
})

testthat::test_that("extract_first_nonempty_llm_text ilk dolu adayı döner", {
  .llm_postprocess_source_once()

  testthat::expect_identical(
    extract_first_nonempty_llm_text("", NULL, "bulundu", "sonraki"),
    "bulundu"
  )
  testthat::expect_identical(
    extract_first_nonempty_llm_text(NULL, "", list()),
    ""
  )
  testthat::expect_identical(
    extract_first_nonempty_llm_text("ilk", "ikinci"),
    "ilk"
  )
})

testthat::test_that("normalize_llm_scalar_content metni UTF-8 skalarına indirir", {
  .llm_postprocess_source_once()

  testthat::expect_identical(normalize_llm_scalar_content("metin"), "metin")
  testthat::expect_identical(normalize_llm_scalar_content(""), "")
  testthat::expect_identical(normalize_llm_scalar_content(NULL), "")
  testthat::expect_identical(normalize_llm_scalar_content(list(text = "x")), "x")
})

testthat::test_that("extract_llm_text_bundle içerik ve akıl yürütmeyi ayırır", {
  .llm_postprocess_source_once()

  # Düz metin -> content; reasoning boş.
  b_plain <- extract_llm_text_bundle("duz metin")
  testthat::expect_identical(b_plain$content, "duz metin")
  testthat::expect_identical(b_plain$reasoning, "")

  # OpenAI message şekli: content + reasoning_content.
  b_msg <- extract_llm_text_bundle(list(
    choices = list(list(message = list(content = "cevap", reasoning_content = "dusunce")))
  ))
  testthat::expect_identical(b_msg$content, "cevap")
  testthat::expect_identical(b_msg$reasoning, "dusunce")

  # Delta şekli: delta$content.
  b_delta <- extract_llm_text_bundle(list(
    choices = list(list(delta = list(content = "parca")))
  ))
  testthat::expect_identical(b_delta$content, "parca")

  # Üst düzey content fallback (choices yok).
  b_top <- extract_llm_text_bundle(list(content = "ust icerik"))
  testthat::expect_identical(b_top$content, "ust icerik")
})

testthat::test_that("extract_llm_content_and_sources içerik ve kaynakları çıkarır", {
  .llm_postprocess_source_once()

  # Düz (liste olmayan) girdi.
  r_plain <- extract_llm_content_and_sources("duz cevap")
  testthat::expect_identical(r_plain$content, "duz cevap")
  testthat::expect_null(r_plain$sources)

  # message içeriği + sources geçişi (içerik dolu olduğu için reasoning
  # fallback yolu tetiklenmez, dış bağımlılık çağrılmaz).
  resp <- list(choices = list(list(message = list(
    content = "cevap metni",
    sources = list(list(metadata = list(list(name = "dosya.pdf"))))
  ))))
  r_src <- extract_llm_content_and_sources(resp)
  testthat::expect_identical(r_src$content, "cevap metni")
  testthat::expect_false(is.null(r_src$sources))
})
