# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-text-turkish-behavior.R
# Açıklama: `pk_tr_fold()` davranış testleri. Tamamen çevrimdışı ve
#           belirlenimcidir: DB, LLM, tarayıcı, ağ veya gizli değer GEREKMEZ.
#
# Kapsanan sözleşmeler (master plan §7):
#   - İ / I / ı / i katlaması Türkçe kurallarına göre yapılır.
#   - Birleşik (composed) ve ayrışık (decomposed) NFC biçimleri AYNI anahtarı
#     üretir; aksi hâlde alias eşleşmesi sessizce kaçar.
#   - Katlama YERELDEN BAĞIMSIZDIR (C ve C.UTF-8 yerellerinde bayt özdeş).
#   - Faz 3a yükleme sırası: yardımcı, metadata katmanlarından ÖNCE gelir.
#
# NOT: Türkçe fikstürler bilerek `intToUtf8()` ile kurulur (birleşik nokta gibi
#      görünmez karakterler için). Bu, Windows VM konsol/kod sayfası
#      farklarında testin bayt kararlılığını korur (CLAUDE.md kuralı).
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()
  source(file.path(repo_root, "R", "helpers_pk_text_turkish.R"),
         encoding = "UTF-8", local = globalenv())
})

# Ayrışık biçimler: birleşik nokta U+0307.
.PK_TEST_DOT <- intToUtf8(0x0307L)

test_that("pk_tr_fold Türkçe büyük harfleri doğru katlar", {
  testthat::skip_if_not_installed("stringi")

  expect_equal(pk_tr_fold("İSTANBUL"), "istanbul")   # İSTANBUL
  expect_equal(pk_tr_fold("KALIP"), "kalıp")         # KALIP -> kalıp (noktasız ı)
  expect_equal(pk_tr_fold("ISIK"), "ısık")      # ISIK  -> ışık değil ısık: I -> ı
  expect_equal(pk_tr_fold("ŞGÜÖÇ"), "şgüöç") # ŞGÜÖÇ

  # Türkçe kural: I -> ı (i DEĞİL). Bu, İngilizce katlamadan ayrılan noktadır.
  expect_false(identical(pk_tr_fold("KALIP"), "kalip"))
})

test_that("birleşik ve ayrışık İ biçimleri aynı anahtarı üretir", {
  testthat::skip_if_not_installed("stringi")

  birlesik <- "İSTANBUL"                                  # İ (U+0130)
  ayrisik_buyuk <- paste0("I", .PK_TEST_DOT, "STANBUL")        # I + U+0307
  ayrisik_kucuk <- paste0("i", .PK_TEST_DOT, "stanbul")        # i + U+0307

  expect_equal(pk_tr_fold(birlesik), "istanbul")
  expect_equal(pk_tr_fold(ayrisik_buyuk), pk_tr_fold(birlesik))

  # Küçük `i` + birleşik noktanın önceden birleşmiş bir karşılığı yoktur; NFC
  # onu bırakır. Yardımcı bu işareti ayrıca temizlemezse alias sessizce kaçar.
  expect_equal(pk_tr_fold(ayrisik_kucuk), pk_tr_fold(birlesik))
})

test_that("boşluk sadeleştirme ve NA/boş girdi davranışı kararlıdır", {
  testthat::skip_if_not_installed("stringi")

  expect_equal(pk_tr_fold("  Elektronik   HARP  "), "elektronik harp")
  expect_equal(pk_tr_fold("\tRadar\nModernizasyon "), "radar modernizasyon")

  expect_equal(pk_tr_fold(character(0)), character(0))
  expect_equal(pk_tr_fold(NULL), character(0))
  expect_true(is.na(pk_tr_fold(NA_character_)))

  # NA girdiler konumlarını korur, diğer elemanları bozmaz.
  cikti <- pk_tr_fold(c("İZMİR", NA_character_, "ANKARA"))
  expect_equal(cikti[1], "izmir")
  expect_true(is.na(cikti[2]))
  expect_equal(cikti[3], "ankara")
})

test_that("pk_tr_fold_is_blank boş/NA anahtarları yakalar", {
  testthat::skip_if_not_installed("stringi")

  expect_true(all(pk_tr_fold_is_blank(c("", "   ", "\t"))))
  expect_true(pk_tr_fold_is_blank(NA_character_))
  expect_false(pk_tr_fold_is_blank("proje"))
})

# Katlanmış metnin UTF-8 bayt dizisi (büyük harf onaltılık).
.pk_test_bytes <- function(x) {
  paste(sprintf("%02X", as.integer(charToRaw(enc2utf8(x)))), collapse = "")
}

test_that("katlama ALTIN BAYT dizisini üretir (yerel kayması burada yakalanır)", {
  testthat::skip_if_not_installed("stringi")

  # Fikstürler bilerek kod noktalarından kurulur: testin kendisi konsol/kod
  # sayfası farkından etkilenmesin.
  istanbul <- intToUtf8(c(0x0130, 0x0053, 0x0054, 0x0041, 0x004E, 0x0042, 0x0055, 0x004C))
  kalip    <- intToUtf8(c(0x004B, 0x0041, 0x004C, 0x0049, 0x0050))
  sguoc    <- intToUtf8(c(0x015E, 0x0047, 0x00DC, 0x00D6, 0x00C7))

  # Beklenen çıktılar: istanbul / kalıp (U+0131) / şgüöç.
  expect_equal(.pk_test_bytes(pk_tr_fold(istanbul)), "697374616E62756C")
  expect_equal(.pk_test_bytes(pk_tr_fold(kalip)), "6B616CC4B170")
  expect_equal(.pk_test_bytes(pk_tr_fold(sguoc)), "C59F67C3BCC3B6C3A7")
})

test_that("katlama R oturum yerelinden BAĞIMSIZDIR", {
  testthat::skip_if_not_installed("stringi")

  fikstur <- c(
    intToUtf8(c(0x0130, 0x0053, 0x0054, 0x0041, 0x004E, 0x0042, 0x0055, 0x004C)),
    intToUtf8(c(0x004B, 0x0041, 0x004C, 0x0049, 0x0050)),
    intToUtf8(c(0x015E, 0x0047, 0x00DC, 0x00D6, 0x00C7))
  )

  baytlar <- function() vapply(pk_tr_fold(fikstur), .pk_test_bytes, character(1))

  referans <- baytlar()

  eski_collate <- Sys.getlocale("LC_COLLATE")
  eski_ctype <- Sys.getlocale("LC_CTYPE")
  on.exit({
    suppressWarnings(Sys.setlocale("LC_COLLATE", eski_collate))
    suppressWarnings(Sys.setlocale("LC_CTYPE", eski_ctype))
  }, add = TRUE)

  denendi <- FALSE

  for (yerel in c("C", "C.UTF-8", "C.utf8")) {
    if (!nzchar(suppressWarnings(Sys.setlocale("LC_COLLATE", yerel)))) next
    denendi <- TRUE
    expect_equal(baytlar(), referans,
                 info = sprintf("LC_COLLATE=%s altinda katlama degisti.", yerel))
  }

  testthat::skip_if(!denendi, "Alternatif yerel bu ortamda ayarlanamadi.")
})

test_that("ÖLÇÜLMÜŞ başarısız yollar yeniden getirilmemiştir", {
  repo_root <- resolve_repo_root_for_tests()
  yol <- file.path(repo_root, "R", "helpers_pk_text_turkish.R")

  # Windows/VM güvenli bayt okuma (CLAUDE.md kuralı).
  ham <- readBin(yol, what = "raw", n = file.info(yol)$size)
  tam_metin <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")

  # Yorum satırları taranmadan ÖNCE atılır: dosyanın kendi uyarı açıklaması
  # `chartr()` kelimesini içerir ve aksi hâlde sahte pozitif üretir.
  satirlar <- strsplit(tam_metin, "\n", fixed = TRUE)[[1]]
  metin <- paste(satirlar[!grepl("^\\s*#", satirlar)], collapse = "\n")

  # `chartr()` ve elle kod noktası eşlemesi bu depoda ÖLÇÜLEREK başarısız
  # bulundu (UTF-8 olmayan yerelde bayt bazlı mojibake). Geri gelmemelidir.
  expect_false(grepl("chartr(", metin, fixed = TRUE, useBytes = TRUE),
               info = "chartr() Turkce katlama icin yeniden kullanilmis.")

  # Doğrulanmış tek yol: ICU tabanlı Türkçe küçük harf.
  expect_true(grepl("stringi::stri_trans_tolower", metin, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("locale = \"tr\"", metin, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("stringi::stri_trans_nfc", metin, fixed = TRUE, useBytes = TRUE))
})

test_that("yükleme sırası: Türkçe katlama yardımcısı metadata katmanlarından ÖNCE", {
  repo_root <- resolve_repo_root_for_tests()

  bolum <- source_manifest_sections_for_tests()$pk_query_metadata
  expect_false(is.null(bolum), info = "pk_query_metadata bolumu manifestte yok.")

  sira <- function(dosya) match(dosya, bolum)

  expect_equal(sira("R/helpers_pk_text_turkish.R"), 1L,
               info = "Turkce katlama yardimcisi bolumun ilk dosyasi olmalidir.")

  # Master plan §6 zorunlu veri katmanı sırası.
  expect_true(sira("R/helpers_pk_text_turkish.R") < sira("R/library_query_meta_auto.R"))
  expect_true(sira("R/library_query_meta_auto.R") < sira("R/library_query_meta_local.R"))
  expect_true(sira("R/library_query_meta_local.R") < sira("R/library_query_meta.R"))
  expect_true(sira("R/library_query_meta.R") < sira("R/library_query_aliases_local.R"))

  # Tüm metadata katmanı SQL loader'dan önce yüklenmelidir.
  tum <- source_manifest_paths_for_tests()
  expect_true(
    max(match(bolum, tum), na.rm = TRUE) < match("R/config_sql_loader.R", tum),
    info = "Metadata katmani R/config_sql_loader.R sonrasina kaymis."
  )
})
