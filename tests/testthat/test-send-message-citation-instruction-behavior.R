# ==============================================================================
# Dosya Yolu: tests/testthat/test-send-message-citation-instruction-behavior.R
# Açıklama: R/helpers_send_message_prompting.R içindeki saf
#           mergen_build_citation_instruction yardımcısının DAVRANIŞSAL testleri.
#           Bu fonksiyon doğrudan çağrılarak test edilmiyordu. İki dal:
#             - yüklenen dosya varsa (count > 0): zorunlu "Kaynakça:" kuralı
#             - yüklenen dosya yoksa (count = 0): koşullu "Kaynakça:" gereksinimi
#           Her iki dal da satır-içi [Source: ...] atıflarını yasaklar ve çıktı
#           iki yeni satırla başlar. Shiny/DB/LLM/ağ GEREKMEZ; yalnızca base R.
# ==============================================================================

.citation_source_once <- function() {
  if (exists("mergen_build_citation_instruction", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_send_message_prompting.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

testthat::test_that("mergen_build_citation_instruction yüklenen dosya varken zorunlu Kaynakça kuralı üretir", {
  .citation_source_once()
  out <- mergen_build_citation_instruction(2)

  testthat::expect_match(out, "MANDATORY CITATION RULE", fixed = TRUE)
  testthat::expect_match(out, "NON-NEGOTIABLE", fixed = TRUE)
  # "Kaynakça:" (ç parser-güvenli ç ile)
  testthat::expect_match(out, "Kaynakça:", fixed = TRUE)
  # Örnek bloğu numaralı kaynakları gösterir
  testthat::expect_match(out, "1) document.docx", fixed = TRUE)
  testthat::expect_match(out, "2) file.pdf", fixed = TRUE)
  # Satır-içi atıf yasağı korunur
  testthat::expect_match(out, "Do NOT use inline", fixed = TRUE)
  # Çıktı iki yeni satırla başlar
  testthat::expect_true(startsWith(out, "\n\n"))
})

testthat::test_that("mergen_build_citation_instruction yüklenen dosya yokken koşullu gereksinim üretir", {
  .citation_source_once()
  out <- mergen_build_citation_instruction(0)

  testthat::expect_match(out, "CRITICAL CITATION REQUIREMENT", fixed = TRUE)
  testthat::expect_match(out, "Kaynakça:", fixed = TRUE)
  testthat::expect_match(out, "Do NOT use inline", fixed = TRUE)
  # Bu dal zorunlu/NON-NEGOTIABLE ifadelerini içermez
  testthat::expect_false(grepl("MANDATORY", out, fixed = TRUE))
  testthat::expect_false(grepl("NON-NEGOTIABLE", out, fixed = TRUE))
  testthat::expect_true(startsWith(out, "\n\n"))
})

testthat::test_that("mergen_build_citation_instruction iki dalı farklı metin döndürür", {
  .citation_source_once()
  testthat::expect_false(
    identical(
      mergen_build_citation_instruction(1),
      mergen_build_citation_instruction(0)
    )
  )
})
