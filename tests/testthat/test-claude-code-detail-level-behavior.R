# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-detail-level-behavior.R
# Açıklama: R/helpers_claude_code_documents.R içindeki
#           resolve_claude_code_document_detail_level fonksiyonunun DAVRANIŞSAL
#           testleri (mevcut testlerde çağrılmıyordu). Bilge Yolaç doküman özet
#           akışında kullanıcının istediği ayrıntı düzeyini ("kisa"/"orta"/
#           "detayli") prompt anahtar kelimelerinden çıkarır. Desenler gerçek
#           Türkçe karakterleri ALT-DİZE olarak kullanır (PCRE2 uyumlu).
#           Saf base R (tolower/grepl); LLM/DB/dosya GEREKMEZ.
# ==============================================================================

.ccdetail_source_once <- function() {
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  if (!exists("resolve_claude_code_document_detail_level",
              envir = globalenv(), mode = "function", inherits = TRUE)) {
    kok <- resolve_repo_root_for_tests()
    # Doküman BAĞLAM hazırlığı documents.R'de; özetleme orkestrasyonu
    # (resolve_detail_level dahil) document_summary.R'ye ayrıldı.
    source(
      file.path(kok, "R", "helpers_claude_code_documents.R"),
      encoding = "UTF-8", local = globalenv()
    )
    source(
      file.path(kok, "R", "helpers_claude_code_document_summary.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  invisible(TRUE)
}

testthat::test_that("resolve_claude_code_document_detail_level varsayılan/anahtarsız girdide 'orta' döner", {
  .ccdetail_source_once()
  testthat::expect_identical(resolve_claude_code_document_detail_level(""), "orta")
  testthat::expect_identical(resolve_claude_code_document_detail_level(NULL), "orta")
  testthat::expect_identical(resolve_claude_code_document_detail_level("bu dosyayı oku"), "orta")
})

testthat::test_that("resolve_claude_code_document_detail_level ayrıntı anahtarlarını 'detayli' yapar", {
  .ccdetail_source_once()
  testthat::expect_identical(resolve_claude_code_document_detail_level("detaylı açıkla"), "detayli")
  testthat::expect_identical(resolve_claude_code_document_detail_level("ayrıntılı incele"), "detayli")
  testthat::expect_identical(resolve_claude_code_document_detail_level("kapsamlı analiz yap"), "detayli")
  testthat::expect_identical(resolve_claude_code_document_detail_level("satır satır oku"), "detayli")
  # ASCII varyantı da yakalanır.
  testthat::expect_identical(resolve_claude_code_document_detail_level("detayli incele"), "detayli")
})

testthat::test_that("resolve_claude_code_document_detail_level kısa anahtarlarını 'kisa' yapar", {
  .ccdetail_source_once()
  testthat::expect_identical(resolve_claude_code_document_detail_level("kısa özet ver"), "kisa")
  testthat::expect_identical(resolve_claude_code_document_detail_level("özet geç"), "kisa")
  testthat::expect_identical(resolve_claude_code_document_detail_level("kısaca anlat"), "kisa")
  # ASCII varyantı.
  testthat::expect_identical(resolve_claude_code_document_detail_level("kisa ozet"), "kisa")
})

testthat::test_that("resolve_claude_code_document_detail_level ayrıntıya kısadan öncelik verir", {
  .ccdetail_source_once()
  # Her iki anahtar da varsa 'detayli' (önce kontrol edilir).
  testthat::expect_identical(
    resolve_claude_code_document_detail_level("kısa ama detaylı incele"),
    "detayli"
  )
})
