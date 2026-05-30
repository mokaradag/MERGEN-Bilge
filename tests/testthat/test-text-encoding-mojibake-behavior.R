# ==============================================================================
# Dosya Yolu: tests/testthat/test-text-encoding-mojibake-behavior.R
# Açıklama: R/utils_text_encoding.R Türkçe mojibake onarımı ve ANSI temizleme
#           çekirdek yardımcılarının DAVRANIŞSAL testleri. Türkçe metin bütünlüğü
#           bu deponun 1 numaralı kuralıdır. Gerçek üretim fonksiyonları çağrılır;
#           ağ/DB/paket bağımlılığı gerekmez (yalnızca base iconv/utf8ToInt).
# ==============================================================================

.txtenc_source_once <- function() {
  if (exists("repair_text_mojibake", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "utils_text_encoding.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

testthat::test_that("unicode_to_win1252_byte ASCII/Latin1/özel eşlemeyi ve eşlenemezi doğru döndürür", {
  .txtenc_source_once()
  testthat::expect_identical(unicode_to_win1252_byte(utf8ToInt("A")), 65L)   # ASCII
  testthat::expect_identical(unicode_to_win1252_byte(0xE7L), 0xE7L)          # ç (Latin1 aralığı)
  testthat::expect_identical(unicode_to_win1252_byte(0x20ACL), 0x80L)        # € -> 0x80 (özel eşleme)
  testthat::expect_identical(unicode_to_win1252_byte(0x2019L), 0x92L)        # ' -> 0x92
  testthat::expect_identical(unicode_to_win1252_byte(0x1F680L), -1L)         # emoji eşlenemez
  testthat::expect_identical(unicode_to_win1252_byte(NA), -1L)
})

testthat::test_that("repair_text_mojibake bilinen Türkçe mojibake örneklerini onarır", {
  .txtenc_source_once()
  # CLAUDE.md'deki kanonik örnekler.
  testthat::expect_identical(repair_text_mojibake("NasÄ±l"), "Nasıl")
  testthat::expect_identical(repair_text_mojibake("TÃ¼rkiye"), "Türkiye")
  testthat::expect_identical(repair_text_mojibake("baÅŸkent"), "başkent")
  testthat::expect_identical(repair_text_mojibake("yardÄ±mcÄ±"), "yardımcı")
})

testthat::test_that("repair_text_mojibake doğru Türkçe metni bozmaz (idempotent)", {
  .txtenc_source_once()
  # Zaten doğru olan Türkçe metin değişmemeli.
  testthat::expect_identical(repair_text_mojibake("Türkiye'nin başkenti"), "Türkiye'nin başkenti")
  testthat::expect_identical(repair_text_mojibake("Merhaba dünya"), "Merhaba dünya")
  # Saf ASCII dokunulmaz.
  testthat::expect_identical(repair_text_mojibake("Hello world"), "Hello world")
})

testthat::test_that("repair_text_mojibake NA ve vektör/geçersiz girdiyi güvenle işler", {
  .txtenc_source_once()
  testthat::expect_identical(
    repair_text_mojibake(c("TÃ¼rkiye", NA, "NasÄ±l")),
    c("Türkiye", NA, "Nasıl")
  )
  testthat::expect_null(repair_text_mojibake(NULL))
  testthat::expect_identical(repair_text_mojibake(42L), 42L)  # karakter olmayan aynen döner
})

testthat::test_that("decode_win1252_mojibake_once tek geçişte çözer ve ASCII'ye dokunmaz", {
  .txtenc_source_once()
  testthat::expect_identical(decode_win1252_mojibake_once("TÃ¼rkiye"), "Türkiye")
  # 0x80 üstü bayt yoksa (saf ASCII) metin değişmez.
  testthat::expect_identical(decode_win1252_mojibake_once("duz ascii"), "duz ascii")
  testthat::expect_identical(decode_win1252_mojibake_once(""), "")
})

testthat::test_that("strip_ansi_sequences renk/biçim ve OSC dizilerini temizler", {
  .txtenc_source_once()
  # CSI renk dizisi.
  testthat::expect_identical(strip_ansi_sequences("\033[31mKırmızı\033[0m"), "Kırmızı")
  testthat::expect_identical(strip_ansi_sequences("\033[1;32mYeşil\033[0m metin"), "Yeşil metin")
  # OSC başlık dizisi (ESC ] ... BEL).
  testthat::expect_identical(strip_ansi_sequences("\033]0;başlık\007içerik"), "içerik")
  # ANSI içermeyen metin dokunulmaz.
  testthat::expect_identical(strip_ansi_sequences("düz metin"), "düz metin")
  # Vektör + NA.
  testthat::expect_identical(
    strip_ansi_sequences(c("\033[0mA", NA, "B")),
    c("A", NA, "B")
  )
})

testthat::test_that("normalize_text_utf8 repair_mojibake ve strip_ansi seçeneklerini uygular", {
  .txtenc_source_once()
  testthat::expect_identical(
    normalize_text_utf8("TÃ¼rkiye", repair_mojibake = TRUE),
    "Türkiye"
  )
  testthat::expect_identical(
    normalize_text_utf8("\033[31mUyarı\033[0m", strip_ansi = TRUE),
    "Uyarı"
  )
  # Varsayılan (her ikisi kapalı): mojibake onarılmaz.
  testthat::expect_identical(normalize_text_utf8("NasÄ±l"), "NasÄ±l")
  # NA korunur.
  testthat::expect_identical(
    normalize_text_utf8(c("A", NA), repair_mojibake = TRUE),
    c("A", NA)
  )
})

testthat::test_that("mark_text_utf8 karakterleri korur ve UTF-8 olarak işaretler", {
  .txtenc_source_once()
  out <- mark_text_utf8(c("Türkçe", NA, "metin"))
  testthat::expect_identical(out, c("Türkçe", NA, "metin"))
  testthat::expect_identical(Encoding(out[1]), "UTF-8")
})

testthat::test_that("normalize_text_tree_utf8 iç içe liste/dataframe yapısında onarım uygular", {
  .txtenc_source_once()
  tree <- list(
    baslik = "TÃ¼rkiye",
    alt = list(metin = "NasÄ±l", sayi = 5L)
  )
  out <- normalize_text_tree_utf8(tree, repair_mojibake = TRUE)
  testthat::expect_identical(out$baslik, "Türkiye")
  testthat::expect_identical(out$alt$metin, "Nasıl")
  testthat::expect_identical(out$alt$sayi, 5L)  # karakter olmayan korunur
})
