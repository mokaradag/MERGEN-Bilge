# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-turkish-decoding-behavior.R
# Açıklama: R/helpers_claude_code_workdir_snapshot.R içindeki Türkçe çözümleme
#           skorlayıcılarının DAVRANIŞSAL testleri. Bu fonksiyonlar doğrudan
#           çağrılarak test edilmiyordu:
#             - score_turkish_decoding_candidate: Türkçe karakter sayısı artı,
#               mojibake sekansı eksi 10 puan; NULL/NA/boş -> -1
#             - pick_best_turkish_decoding: ham baytları çeşitli kodlamalarla
#               çözüp en yüksek skorlu adayı seçer
#           Fikstürler parser-güvenli intToUtf8/iconv ile deterministik kurulur.
#           Shiny/DB/ağ GEREKMEZ; yalnızca base R.
# ==============================================================================

.ccdecode_source_once <- function() {
  # `repair_text_mojibake` DA ERKEN DÖNÜŞ KOŞULUNA DÂHİLDİR (PR #705, P2).
  #
  # Başka bir test yalnızca puanlayıcı/seçici ikilisini yükleyip
  # `R/utils_text_encoding.R` dosyasını yüklemezse bu koruma erken dönüyor ve
  # onarım testi `repair_text_mojibake` bulunamadığı için TEST SIRASINA BAĞLI
  # olarak düşüyordu.
  if (exists("score_turkish_decoding_candidate", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("pick_best_turkish_decoding", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("repair_text_mojibake", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  kok <- resolve_repo_root_for_tests()
  # `repair_text_mojibake()` MERKEZÎ onarım sınırıdır ve
  # `normalize_claude_code_text_file_to_utf8()` onu `exists()` ile arar.
  # Testte SKIP edilirse kaynak manifesti/yükleme sırası gerilemesi CI'da
  # sessizce yeşil kalır; bu yüzden bağımlılık burada AÇIKÇA yüklenir.
  source(file.path(kok, "R", "utils_text_encoding.R"),
         encoding = "UTF-8", local = globalenv())
  source(
    file.path(kok, "R", "helpers_claude_code_workdir_snapshot.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# Kod noktalarından parser-güvenli karakter dizisi üretir.
.ccd_cp <- function(...) intToUtf8(as.integer(c(...)))

# ------------------------------------------------------------------------------
# score_turkish_decoding_candidate
# ------------------------------------------------------------------------------
testthat::test_that("score_turkish_decoding_candidate NULL/NA/boş için -1 döner", {
  .ccdecode_source_once()
  testthat::expect_identical(score_turkish_decoding_candidate(NULL), -1L)
  testthat::expect_identical(score_turkish_decoding_candidate(NA), -1L)
  testthat::expect_identical(score_turkish_decoding_candidate(""), -1L)
})

testthat::test_that("score_turkish_decoding_candidate ASCII için 0, Türkçe karakter başına +1 verir", {
  .ccdecode_source_once()
  testthat::expect_identical(score_turkish_decoding_candidate("hello world"), 0L)
  # "Çağrı" -> Ç, ğ, ı ayırt edici karakterleri = 3 puan
  cagri <- .ccd_cp(0x00C7, 0x0061, 0x011F, 0x0072, 0x0131)
  testthat::expect_identical(score_turkish_decoding_candidate(cagri), 3L)
})

testthat::test_that("score_turkish_decoding_candidate mojibake sekansı başına -10 cezalandırır", {
  .ccdecode_source_once()
  # "Ã§" mojibake sekansı (U+00C3 U+00A7) -> 0 Türkçe - 10 = -10
  moji <- .ccd_cp(0x00C3, 0x00A7)
  testthat::expect_identical(score_turkish_decoding_candidate(moji), -10L)
  # "ÅŸ" mojibake (U+00C5 U+0178) -> -10
  moji2 <- .ccd_cp(0x00C5, 0x0178)
  testthat::expect_identical(score_turkish_decoding_candidate(moji2), -10L)
  # Karışık: "Çağrı" (3) + "Ã§" (-10) = -7
  karisik <- paste0(.ccd_cp(0x00C7, 0x0061, 0x011F, 0x0072, 0x0131), moji)
  testthat::expect_identical(score_turkish_decoding_candidate(karisik), -7L)
})

# ------------------------------------------------------------------------------
# pick_best_turkish_decoding
# ------------------------------------------------------------------------------
testthat::test_that("pick_best_turkish_decoding boş ham baytlar için NA döner", {
  .ccdecode_source_once()
  testthat::expect_true(is.na(pick_best_turkish_decoding(raw(0))))
})

testthat::test_that("pick_best_turkish_decoding WINDOWS-1254 baytlarını Türkçe metne çözer", {
  .ccdecode_source_once()
  # "Çağrı şehir" metnini WINDOWS-1254 baytlarına çevir, sonra en iyi çözümü iste
  metin <- .ccd_cp(
    0x00C7, 0x0061, 0x011F, 0x0072, 0x0131, 0x0020,  # Çağrı + boşluk
    0x015F, 0x0065, 0x0068, 0x0069, 0x0072            # şehir
  )
  ham <- iconv(metin, from = "UTF-8", to = "WINDOWS-1254", toRaw = TRUE)[[1]]
  testthat::expect_false(is.null(ham))

  best <- pick_best_turkish_decoding(ham)
  # En yüksek skorlu çözüm Türkçe karakterleri geri kazanır
  testthat::expect_true(grepl("[çğışÇ]", best, perl = TRUE))
  # Mojibake jetonu içermemeli
  testthat::expect_false(grepl("Ã", best, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# normalize_claude_code_text_file_to_utf8 - GEÇERLİ UTF-8 mojibake onarımı
# ------------------------------------------------------------------------------
# PR #705 inceleme bulgusu (P1): dosya GEÇERLİ UTF-8 olduğu hâlde mojibake
# içerdiğinde eski kod HAM BAYTLARI eski tek-baytlı kodlamalarla YENİDEN
# çözüyordu. Bu, zaten geçerli olan UTF-8'i bozup YENİ bir mojibake üretebilir
# ve dosyanın üzerine yazıldığı için kayıp geri alınamaz. Doğru davranış,
# çözülmüş metni merkezî `repair_text_mojibake()` ile ONARMAKTIR.
testthat::test_that("geçerli UTF-8 mojibake ham bayt çözümlemesiyle bozulmaz", {
  .ccdecode_source_once()
  # SKIP DEĞİL, İDDİA: bağımlılık kaybolursa bu regresyon testi DÜŞMELİDİR.
  testthat::expect_true(
    exists("repair_text_mojibake", mode = "function", inherits = TRUE)
  )

  # U+00C5 U+017E ikilisi GEÇERLİ UTF-8'dir ve U+015E karakterinin
  # WINDOWS-1254 olarak yanlış yorumlanmış hâlidir.
  bozuk <- .ccd_cp(0x00C5, 0x017E)
  dogru <- .ccd_cp(0x015E)
  testthat::expect_true(all(validUTF8(bozuk)))

  yol <- tempfile(fileext = ".txt")
  on.exit(unlink(yol), add = TRUE)
  con <- file(yol, open = "wb")
  # `writeBin()` hata verse de bağlantı kapanmalıdır. `after = FALSE` ile
  # kapatma, kayıtlı `unlink()`ten ÖNCE koşar (Windows'ta AÇIK dosya
  # silinemez). Dosya doğrulama çağrısından ÖNCE flush edilmek zorunda
  # olduğu için manuel `close()` KALIR; ikinci kapatma denemesi yutulur.
  on.exit(try(close(con), silent = TRUE), add = TRUE, after = FALSE)
  writeBin(charToRaw(enc2utf8(bozuk)), con)
  close(con)

  testthat::expect_true(normalize_claude_code_text_file_to_utf8(yol))

  ham <- readBin(yol, "raw", n = file.info(yol)$size)
  if (length(ham) >= 3 && identical(ham[1:3], as.raw(c(0xEF, 0xBB, 0xBF)))) {
    ham <- ham[-(1:3)]
  }
  sonuc <- rawToChar(ham)
  Encoding(sonuc) <- "UTF-8"

  testthat::expect_identical(sonuc, dogru)
  # YENİ mojibake üretilmemiş olmalı
  testthat::expect_gte(score_turkish_decoding_candidate(sonuc), 0L)
})

# U+009F mojibake sınıfı: C5 9F baytlarının latin1 çözümü CEZA almalıdır.
testthat::test_that("latin1 kaynakli C5 9F mojibake cezasi alir", {
  .ccdecode_source_once()
  aday <- .ccd_cp(0x00C5, 0x009F)
  testthat::expect_lt(score_turkish_decoding_candidate(aday), 0L)
})

# ------------------------------------------------------------------------------
# PR #705 inceleme bulgusu (P2): onarım, ZATEN GEÇERLİ UTF-8 olan metni yalnızca
# "onarılan aday daha yüksek puan aldı" gerekçesiyle YENİDEN YAZMAMALIDIR.
# 11+ geçerli Türkçe karakter içeren ve içinde LİTERAL "\u00C5\u017E" dizisi
# bulunan geçerli bir dosya POZİTİF puan alır; eski kod onu "\u015E" yapıp
# ORİJİNAL baytları yok ediyordu.
testthat::test_that("pozitif puanlı geçerli UTF-8 metin izin olmadan YENİDEN YAZILMAZ", {
  .ccdecode_source_once()

  turkce <- .ccd_cp(0x00C7, 0x0061, 0x011F, 0x0072, 0x0131, 0x015E, 0x00F6,
                    0x00FC, 0x0130, 0x011E, 0x00D6, 0x00DC, 0x015F)
  literal <- .ccd_cp(0x00C5, 0x017E)
  icerik <- paste0(turkce, literal)

  testthat::expect_true(all(validUTF8(icerik)))
  # Puan POZITIF: eski kapi (`mevcut_skor < 0`) bu icerikte onarimi calistirmaz.
  testthat::expect_gte(score_turkish_decoding_candidate(icerik), 0L)

  oku <- function(yol) {
    ham <- readBin(yol, "raw", n = file.info(yol)$size)
    if (length(ham) >= 3 && identical(ham[1:3], as.raw(c(0xEF, 0xBB, 0xBF)))) ham <- ham[-(1:3)]
    sonuc <- rawToChar(ham)
    Encoding(sonuc) <- "UTF-8"
    sonuc
  }
  yaz <- function(metin) {
    yol <- tempfile(fileext = ".txt")
    con <- file(yol, open = "wb")
    writeBin(charToRaw(enc2utf8(metin)), con)
    close(con)
    yol
  }

  yol <- yaz(icerik)
  on.exit(unlink(yol), add = TRUE)
  testthat::expect_true(normalize_claude_code_text_file_to_utf8(yol))
  # LITERAL dizi KORUNUR: gecerli baytlar tahrip edilmemistir.
  testthat::expect_identical(oku(yol), icerik)

  # ACIK OPERATOR IZNI ile karisik icerik onarimi YINE mumkundur.
  withr::with_envvar(c(MERGEN_CLAUDE_CODE_REPAIR_VALID_UTF8 = "true"), {
    yol2 <- yaz(icerik)
    on.exit(unlink(yol2), add = TRUE)
    testthat::expect_true(normalize_claude_code_text_file_to_utf8(yol2))
    testthat::expect_identical(oku(yol2), paste0(turkce, .ccd_cp(0x015E)))
  })
})
