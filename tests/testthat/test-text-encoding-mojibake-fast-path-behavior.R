# ==============================================================================
# Dosya Yolu: tests/testthat/test-text-encoding-mojibake-fast-path-behavior.R
# Açıklama: Mojibake çözücüsünün hızlı yolunu korur. Olağan Türkçe metin
#           (Ç/ç/Ö/Ü öncü karakterleri ve "Öğ", "çü" gibi yan yana ASCII dışı
#           harfler) karakter karakter döngüye girmeden AYNEN dönmeli; gerçek
#           mojibake dizileri ise eskisi gibi çözülmelidir. Yavaş yol, geçmiş
#           tablosu gibi binlerce satırlık okumalarda olay döngüsünü saniyelerce
#           blokluyordu. Türkçe karakterler intToUtf8 ile deterministik üretilir.
# ==============================================================================

.tr <- function(...) intToUtf8(c(...))

testthat::test_that("olağan Türkçe metin her iki çözücüde de değişmeden döner", {
  ornekler <- c(
    paste0(.tr(0xC7), "al", .tr(0x131, 0x15F), "ma"),                  # Çalışma
    paste0(.tr(0xD6, 0x11F), "retmen ", .tr(0xFC, 0xE7, 0xFC), "nc", .tr(0xFC)),  # Öğretmen üçüncü
    paste0(.tr(0xC7, 0xF6), "p ", .tr(0x11E, 0xDC, 0x15E, 0x130, 0xD6, 0xC7)),     # Çöp ĞÜŞİÖÇ
    paste0("g", .tr(0xFC, 0xE7), " ", .tr(0xE7, 0xF6), "z", .tr(0xFC), "m")
  )
  for (s in ornekler) {
    testthat::expect_identical(decode_win1252_mojibake_once(s), s, info = s)
    testthat::expect_identical(decode_latin1_mojibake_once(s), s, info = s)
  }
})

testthat::test_that("gerçek mojibake dizileri çözülmeye devam eder", {
  # UTF-8 baytlarının Windows-1252/Latin-1 olarak okunmuş hâlleri (kod
  # noktalarıyla kurulur): "Çalışma", "güzel" ve sağ tek tırnak geri çözülmeli.
  bozuk <- paste0(.tr(0xC3, 0x2021), "al", .tr(0xC4, 0xB1, 0xC5, 0x178), "ma")
  testthat::expect_identical(decode_win1252_mojibake_once(bozuk),
                             paste0(.tr(0xC7), "al", .tr(0x131, 0x15F), "ma"))
  testthat::expect_identical(decode_latin1_mojibake_once(paste0("g", .tr(0xC3, 0xBC), "zel")),
                             paste0("g", .tr(0xFC), "zel"))
  testthat::expect_identical(decode_win1252_mojibake_once(.tr(0xE2, 0x20AC, 0x2122)), .tr(0x2019))
})

testthat::test_that("öncü karakter metnin sonunda veya tek başına olduğunda değişmez", {
  testthat::expect_identical(decode_latin1_mojibake_once(.tr(0xC3)), .tr(0xC3))
  testthat::expect_identical(decode_win1252_mojibake_once(paste0("abc", .tr(0xC7))), paste0("abc", .tr(0xC7)))
})
