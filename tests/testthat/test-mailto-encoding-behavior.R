# ==============================================================================
# Dosya Yolu: tests/testthat/test-mailto-encoding-behavior.R
# Açıklama: R/helpers_mailto_encoding.R UTF-8 bayt-temelli mailto kodlama
#           yardımcılarının DAVRANIŞSAL testleri. CLAUDE.md §1B: mailto konu/gövde
#           değerleri Windows/VM yerel kod sayfası bozulmasına karşı UTF-8
#           baytlarından percent-encode edilmelidir (ör. Ü -> %C3%9C). Test edilen:
#             - mergen_mailto_normalize_text (NULL/NA/vektör/UTF-8 işareti)
#             - mergen_mailto_percent_encode (unreserved koruma + UTF-8 bayt %XX)
#             - mergen_mailto_href (mailto: + subject/body sorgu birleştirme)
#           Mevcut test-mailto-encoding.R odaklı regresyon içindir; bu dosya
#           doğrudan davranışsal birim kapsamı ekler. Ağ/DB/Shiny GEREKMEZ.
# ==============================================================================

.mailtoenc_source_once <- function() {
  root <- resolve_repo_root_for_tests()
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  # Türkçe için normalize_text_utf8 gerekir; yoksa fonksiyon enc2utf8'e düşer.
  if (!exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    source(file.path(root, "R", "utils_text_encoding.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("mergen_mailto_percent_encode",
              envir = globalenv(), mode = "function", inherits = TRUE)) {
    source(file.path(root, "R", "helpers_mailto_encoding.R"),
           encoding = "UTF-8", local = globalenv())
  }
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# mergen_mailto_normalize_text
# ------------------------------------------------------------------------------
testthat::test_that("mergen_mailto_normalize_text NULL/NA/vektörü güvenli işler", {
  .mailtoenc_source_once()
  testthat::expect_identical(mergen_mailto_normalize_text(NULL), "")
  testthat::expect_identical(mergen_mailto_normalize_text(character(0)), "")
  # NA -> "" ; çok öğe satır sonuyla birleşir.
  testthat::expect_identical(mergen_mailto_normalize_text(c("a", NA, "b")), "a\n\nb")
  # Türkçe metin UTF-8 işaretiyle korunur.
  donen <- mergen_mailto_normalize_text("Görüşme")
  testthat::expect_identical(enc2utf8(donen), enc2utf8("Görüşme"))
  testthat::expect_identical(Encoding(donen), "UTF-8")
})

# ------------------------------------------------------------------------------
# mergen_mailto_percent_encode
# ------------------------------------------------------------------------------
testthat::test_that("mergen_mailto_percent_encode unreserved karakterleri korur", {
  .mailtoenc_source_once()
  testthat::expect_identical(mergen_mailto_percent_encode(""), "")
  # A-Z a-z 0-9 - . _ ~ unreserved'dır, dokunulmaz.
  testthat::expect_identical(mergen_mailto_percent_encode("Test_1-2.3~"), "Test_1-2.3~")
})

testthat::test_that("mergen_mailto_percent_encode boşluk ve reserved ASCII'yi %XX yapar", {
  .mailtoenc_source_once()
  testthat::expect_identical(mergen_mailto_percent_encode("a b"), "a%20b")
  testthat::expect_identical(mergen_mailto_percent_encode("x&y"), "x%26y")
  testthat::expect_identical(mergen_mailto_percent_encode("p=q"), "p%3Dq")
})

testthat::test_that("mergen_mailto_percent_encode Türkçe karakterleri UTF-8 baytlarından kodlar", {
  .mailtoenc_source_once()
  # CLAUDE.md kanonik örneği: Ü (U+00DC) -> UTF-8 0xC3 0x9C -> %C3%9C
  testthat::expect_identical(mergen_mailto_percent_encode("Ü"), "%C3%9C")
  testthat::expect_identical(mergen_mailto_percent_encode("ç"), "%C3%A7")
  testthat::expect_identical(mergen_mailto_percent_encode("ü"), "%C3%BC")
  # Karışık kelime: "Dünya" -> D + %C3%BC + nya
  testthat::expect_identical(mergen_mailto_percent_encode("Dünya"), "D%C3%BCnya")
})

# ------------------------------------------------------------------------------
# mergen_mailto_href
# ------------------------------------------------------------------------------
testthat::test_that("mergen_mailto_href yalnızca alıcı ile mailto: üretir, alıcıyı encode ETMEZ", {
  .mailtoenc_source_once()
  testthat::expect_identical(mergen_mailto_href("a@b.com"), "mailto:a@b.com")
  # Alıcı trimlenir.
  testthat::expect_identical(mergen_mailto_href("  a@b.com  "), "mailto:a@b.com")
})

testthat::test_that("mergen_mailto_href subject/body sorgu parçalarını encode ederek ekler", {
  .mailtoenc_source_once()
  testthat::expect_identical(
    mergen_mailto_href("a@b.com", subject = "Test"),
    "mailto:a@b.com?subject=Test"
  )
  testthat::expect_identical(
    mergen_mailto_href("a@b.com", body = "Merhaba"),
    "mailto:a@b.com?body=Merhaba"
  )
  # subject + body & ile birleşir.
  testthat::expect_identical(
    mergen_mailto_href("a@b.com", subject = "A", body = "B"),
    "mailto:a@b.com?subject=A&body=B"
  )
  # Boşluk subject'te %20 olur.
  testthat::expect_identical(
    mergen_mailto_href("a@b.com", subject = "a b"),
    "mailto:a@b.com?subject=a%20b"
  )
})

testthat::test_that("mergen_mailto_href Türkçe subject'i UTF-8 percent-encode eder", {
  .mailtoenc_source_once()
  donen <- mergen_mailto_href("x@y.z", subject = "Görüşme")
  # href, percent-encode yardımcısıyla tutarlı olmalı.
  testthat::expect_identical(
    donen,
    paste0("mailto:x@y.z?subject=", mergen_mailto_percent_encode("Görüşme"))
  )
  # Türkçe karakter ham değil, UTF-8 bayt kodlu olmalı.
  testthat::expect_match(donen, "%C3%B6", fixed = TRUE)   # ö
  testthat::expect_false(grepl("ö", donen, fixed = TRUE))
})
