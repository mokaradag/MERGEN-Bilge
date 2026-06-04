# ==============================================================================
# Dosya Yolu: tests/testthat/test-deep-thinking-model-resolution-behavior.R
# Açıklama: R/helpers_api_model_config.R resolve_deep_thinking_model DAVRANIŞSAL
#           testleri. Excel/Kodlama derin düşünme araç ailelerinin low/high model
#           kimliği çözümü test edilir. Sentetik bir config geçirilir; global
#           api_config/ağ/LLM GEREKMEZ. Saf çözüm fonksiyonu.
# ==============================================================================

.deepthink_source_once <- function() {
  if (exists("resolve_deep_thinking_model", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  # resolve_deep_thinking_model araç-runtime ayrımıyla
  # helpers_api_model_tool_runtime.R'a taşındı; olası bağımlılıklar için config
  # dosyası önce yüklenir.
  root <- resolve_repo_root_for_tests()
  source(
    file.path(root, "R", "helpers_api_model_config.R"),
    encoding = "UTF-8", local = globalenv()
  )
  source(
    file.path(root, "R", "helpers_api_model_tool_runtime.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

.deepthink_cfg <- function() {
  list(
    deep_thinking_models = list(
      excel  = list(low = "excel-low-model",  high = "excel-high-model"),
      coding = list(low = "coding-low-model", high = "coding-high-model"),
      only_low   = list(low = "only-low-model"),       # high tanımsız
      empty_high = list(low = "x", high = "")           # high boş dize
    )
  )
}

testthat::test_that("low/high seviyeleri doğru model kimliğine çözülür", {
  .deepthink_source_once()
  cfg <- .deepthink_cfg()
  testthat::expect_identical(resolve_deep_thinking_model("excel", "low", cfg), "excel-low-model")
  testthat::expect_identical(resolve_deep_thinking_model("excel", "high", cfg), "excel-high-model")
  testthat::expect_identical(resolve_deep_thinking_model("coding", "high", cfg), "coding-high-model")
})

testthat::test_that("deep_level büyük/küçük harf duyarsızdır; high dışı her şey low'a düşer", {
  .deepthink_source_once()
  cfg <- .deepthink_cfg()
  testthat::expect_identical(resolve_deep_thinking_model("excel", "HIGH", cfg), "excel-high-model")
  testthat::expect_identical(resolve_deep_thinking_model("excel", "High", cfg), "excel-high-model")
  # "high" dışı tüm değerler low seviyesine düşer.
  testthat::expect_identical(resolve_deep_thinking_model("excel", "low", cfg), "excel-low-model")
  testthat::expect_identical(resolve_deep_thinking_model("excel", "medium", cfg), "excel-low-model")
  testthat::expect_identical(resolve_deep_thinking_model("excel", "", cfg), "excel-low-model")
})

testthat::test_that("varsayılan deep_level 'low'dur", {
  .deepthink_source_once()
  cfg <- .deepthink_cfg()
  testthat::expect_identical(resolve_deep_thinking_model("excel", config = cfg), "excel-low-model")
})

testthat::test_that("geçersiz/eksik aile veya seviye NULL döndürür", {
  .deepthink_source_once()
  cfg <- .deepthink_cfg()
  # NULL / boş aile -> NULL.
  testthat::expect_null(resolve_deep_thinking_model(NULL, "low", cfg))
  testthat::expect_null(resolve_deep_thinking_model("", "low", cfg))
  # Bilinmeyen aile -> NULL.
  testthat::expect_null(resolve_deep_thinking_model("yok-aile", "low", cfg))
  # high seviyesi tanımlı değilse -> NULL.
  testthat::expect_null(resolve_deep_thinking_model("only_low", "high", cfg))
  # high boş dize ise -> NULL (nzchar başarısız).
  testthat::expect_null(resolve_deep_thinking_model("empty_high", "high", cfg))
})

testthat::test_that("deep_thinking_models tanımsız config'te NULL döner", {
  .deepthink_source_once()
  # deep_thinking_models alanı olmayan config.
  testthat::expect_null(resolve_deep_thinking_model("excel", "low", list()))
  testthat::expect_null(resolve_deep_thinking_model("excel", "low", list(other = 1)))
})

# NOT: Bilinçli olarak vektör (length > 1) model kimliği senaryosu test EDİLMEZ.
# resolve_deep_thinking_model içindeki
#   if (is.null(model_id) || !nzchar(as.character(model_id)))
# koruması length-1 varsayar; çok elemanlı model_id R >= 4.3'te '||' hatası,
# eski R'de uyarı üretir (sürüm bağımlı). Üretimde model kimlikleri daima
# skalardır; bu latent durum testle stabilize edilmez, raporda not edilir.
