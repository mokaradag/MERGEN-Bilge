# ==============================================================================
# Dosya Yolu: tests/testthat/test-upload-validator-internals-behavior.R
# Açıklama: R/utils_upload_validator.R iç güvenlik yardımcılarının DAVRANIŞSAL
#           testleri. Public validate_uploaded_file() yoğun test edilir; ancak
#           altındaki saf iç guard'lar doğrudan ÇAĞRILMIYORDU:
#             - .upload_mb_to_bytes (MB -> bayt)
#             - .upload_has_control_bytes (ham bayt denetim karakteri tespiti)
#             - .upload_has_traversal (path traversal / mutlak yol / kaçış)
#             - .upload_filename_is_utf8 (geçerli UTF-8 dosya adı)
#             - .upload_extract_ext (uzantı çıkarımı, küçük harf)
#           Türkçe dosya adları (çok-baytlı UTF-8) güvensiz SAYILMAMALIDIR.
#           Saf base R (charToRaw/iconv/grepl); ağ/DB/Shiny GEREKMEZ.
# ==============================================================================

.uploadint_source_once <- function() {
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  if (!exists(".upload_has_traversal",
              envir = globalenv(), mode = "function", inherits = TRUE)) {
    source(
      file.path(resolve_repo_root_for_tests(), "R", "utils_upload_validator.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# .upload_mb_to_bytes
# ------------------------------------------------------------------------------
testthat::test_that(".upload_mb_to_bytes MB değerini bayta çevirir", {
  .uploadint_source_once()
  testthat::expect_identical(.upload_mb_to_bytes(1), 1048576)
  testthat::expect_identical(.upload_mb_to_bytes(25), 26214400)
  testthat::expect_identical(.upload_mb_to_bytes(0), 0)
  testthat::expect_identical(.upload_mb_to_bytes(0.5), 524288)
  # Karakter girdi de sayısala çevrilir.
  testthat::expect_identical(.upload_mb_to_bytes("10"), 10485760)
})

# ------------------------------------------------------------------------------
# .upload_has_control_bytes
# ------------------------------------------------------------------------------
testthat::test_that(".upload_has_control_bytes denetim baytlarını yakalar, Türkçeyi yakalamaz", {
  .uploadint_source_once()
  testthat::expect_false(.upload_has_control_bytes("normal.txt"))
  # Türkçe çok-baytlı UTF-8 (>127) denetim baytı DEĞİLDİR.
  testthat::expect_false(.upload_has_control_bytes("Türkçe_çalışma.pdf"))
  # TAB (9) ve DEL (127) denetim baytıdır.
  testthat::expect_true(.upload_has_control_bytes(paste0("a", intToUtf8(9), "b")))
  testthat::expect_true(.upload_has_control_bytes(paste0("a", intToUtf8(127))))
})

# ------------------------------------------------------------------------------
# .upload_has_traversal
# ------------------------------------------------------------------------------
testthat::test_that(".upload_has_traversal güvenli adlarda FALSE döner", {
  .uploadint_source_once()
  testthat::expect_false(.upload_has_traversal("rapor.pdf"))
  testthat::expect_false(.upload_has_traversal("Türkçe_çalışma_özeti.pdf"))
})

testthat::test_that(".upload_has_traversal kaçış/mutlak yol/boş/denetim baytında TRUE döner", {
  .uploadint_source_once()
  testthat::expect_true(.upload_has_traversal(""))                  # boş
  testthat::expect_true(.upload_has_traversal("../etc/passwd"))     # ..
  testthat::expect_true(.upload_has_traversal("alt/dosya.txt"))     # /
  testthat::expect_true(.upload_has_traversal("alt\\dosya.txt"))    # \
  testthat::expect_true(.upload_has_traversal("C:\\Users\\x.txt"))  # sürücü harfi
  testthat::expect_true(.upload_has_traversal("/mutlak/yol.txt"))   # POSIX mutlak
  testthat::expect_true(.upload_has_traversal(paste0("a", intToUtf8(9), ".txt")))  # denetim baytı
})

# ------------------------------------------------------------------------------
# .upload_filename_is_utf8
# ------------------------------------------------------------------------------
testthat::test_that(".upload_filename_is_utf8 geçerli UTF-8'i kabul, geçersizi reddeder", {
  .uploadint_source_once()
  testthat::expect_true(.upload_filename_is_utf8("Türkçe.pdf"))
  testthat::expect_true(.upload_filename_is_utf8("normal.txt"))
  # Geçersiz UTF-8 bayt dizisi (0xFF) -> FALSE.
  gecersiz <- rawToChar(as.raw(c(0x61L, 0xFFL, 0x62L)))
  testthat::expect_false(.upload_filename_is_utf8(gecersiz))
})

# ------------------------------------------------------------------------------
# .upload_extract_ext
# ------------------------------------------------------------------------------
testthat::test_that(".upload_extract_ext uzantıyı küçük harfle çıkarır", {
  .uploadint_source_once()
  testthat::expect_identical(.upload_extract_ext("rapor.pdf"), "pdf")
  testthat::expect_identical(.upload_extract_ext("data.CSV"), "csv")
  # Çok noktalı: son uzantı alınır.
  testthat::expect_identical(.upload_extract_ext("ARSIV.TAR.GZ"), "gz")
  testthat::expect_identical(.upload_extract_ext("a.b.c.xlsx"), "xlsx")
})

testthat::test_that(".upload_extract_ext uzantısız/kenar durumlarını mevcut davranışla döndürür", {
  .uploadint_source_once()
  # Nokta yok -> "".
  testthat::expect_identical(.upload_extract_ext("noext"), "")
  # Sonda nokta -> strsplit sondaki boşu attığı için "" döner (karakterizasyon).
  testthat::expect_identical(.upload_extract_ext("dosya."), "")
  # Baştaki nokta (gizli dosya) -> kalan kısım uzantı sayılır (karakterizasyon).
  testthat::expect_identical(.upload_extract_ext(".hidden"), "hidden")
})
