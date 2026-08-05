# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-entity-normalize-behavior.R
# Açıklama: Faz 4 normalleştirme hattı davranış testleri (master plan §5.4).
#           Tamamen çevrimdışı ve belirlenimcidir: DB, LLM, tarayıcı, SSO, ağ
#           veya gizli değer GEREKMEZ.
#
# Kapsanan sözleşmeler:
#   - Kesme işareti ekleri atılır ("ANKA'nın" -> "anka").
#   - ASCII ikincil anahtar altı Türkçe harfi doğru eşler.
#   - Birleşik/ayrışık Türkçe biçimler AYNI anahtarı üretir.
#   - Sonek soyma YIKICI DEĞİLDİR: gövde alt sınırı korunur.
#   - `fold` anahtarı sonek SOYMAZ (tasarım kararı E2).
#   - Çoğulluk sezgiseli güvenli yönde çalışır.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()
  for (dosya in c("helpers_pk_text_turkish.R", "helpers_pk_entity_normalize.R")) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = globalenv())
  }
})

.PK_ENT_DOT <- intToUtf8(0x0307L)

test_that("kesme işareti ekleri atılır", {
  testthat::skip_if_not_installed("stringi")

  expect_equal(pk_entity_normalize("ANKA'nın")$fold, "anka")
  expect_equal(pk_entity_normalize("PGRM'deki")$fold, "pgrm")
  expect_equal(pk_entity_normalize("Ahmet Yılmaz'ın")$fold, "ahmet yılmaz")

  # Tipografik kesme (U+2019) düz kesmeyle AYNI sonucu vermelidir; aksi hâlde
  # kullanıcının klavyesine göre eşleşme sessizce kaçar.
  tipografik <- paste0("ANKA", intToUtf8(0x2019L), "nın")
  expect_equal(pk_entity_normalize(tipografik)$fold, "anka")
})

test_that("ASCII ikincil anahtar altı Türkçe harfi eşler", {
  testthat::skip_if_not_installed("stringi")

  expect_equal(pk_entity_ascii_key("kalıp"), "kalip")
  expect_equal(pk_entity_ascii_key("şgüöç"), "sguoc")

  # KALIP -> fold "kalıp" -> ascii "kalip"; kullanıcının yazdığı "kalip" ile
  # ÇAKIŞIR. Katman 3'ün (90 puan) var olma sebebi tam olarak budur.
  expect_equal(pk_entity_normalize("KALIP")$ascii, "kalip")
  expect_equal(pk_entity_normalize("kalip")$ascii, "kalip")

  # Ama katlanmış anahtarlar AYNI DEĞİLDİR: Türkçe I -> ı.
  expect_false(identical(
    pk_entity_normalize("KALIP")$fold,
    pk_entity_normalize("kalip")$fold
  ))
})

test_that("birleşik ve ayrışık Türkçe biçimler aynı anahtarı üretir", {
  testthat::skip_if_not_installed("stringi")

  birlesik <- "İSTANBUL"
  ayrisik <- paste0("I", .PK_ENT_DOT, "STANBUL")

  expect_equal(
    pk_entity_normalize(birlesik)$fold,
    pk_entity_normalize(ayrisik)$fold
  )
  expect_equal(
    pk_entity_normalize(birlesik)$ascii,
    pk_entity_normalize(ayrisik)$ascii
  )
})

test_that("noktalama sadeleştirilir ve belirteç kümesi üretilir", {
  testthat::skip_if_not_installed("stringi")

  normal <- pk_entity_normalize("Elektronik-Harp / Şebekesi (2024)")
  expect_true(all(c("elektronik", "harp") %in% normal$tokens))
  expect_true("2024" %in% normal$tokens)

  # Tekrarlı belirteçler kümede TEK kez görünür.
  expect_equal(pk_entity_normalize("proje proje")$tokens, "proje")
})

test_that("sonek soyma eşleştirme belirteçlerinde çalışır", {
  testthat::skip_if_not_installed("stringi")

  expect_equal(pk_entity_normalize("projesi")$tokens, "proje")
  expect_equal(pk_entity_normalize("projelerinde")$tokens, "proje")
  expect_equal(pk_entity_normalize("araçlar")$tokens, "araç")
  expect_equal(pk_entity_normalize("şebekesi")$tokens, "şebeke")
})

test_that("sonek soyma YIKICI DEĞİLDİR: gövde alt sınırı korunur", {
  testthat::skip_if_not_installed("stringi")

  # "hatta" -> "hat" (3 harf) olurdu; alt sınır bunu engeller.
  expect_equal(pk_entity_normalize("hatta")$tokens, "hatta")
  expect_equal(pk_entity_normalize("yolda")$tokens, "yolda")

  # İyelik -ım/-im BİLEREK listede yoktur: yaygın adlarla çakışır.
  expect_equal(pk_entity_normalize("bakım")$tokens, "bakım")
  expect_equal(pk_entity_normalize("onarım")$tokens, "onarım")
  expect_equal(pk_entity_normalize("tasarım")$tokens, "tasarım")

  # Tek harfli ekler listede yoktur: "proje" -> "proj" olmamalıdır.
  expect_equal(pk_entity_normalize("proje")$tokens, "proje")
})

test_that("fold anahtarı sonek SOYMAZ (tasarım kararı E2)", {
  testthat::skip_if_not_installed("stringi")

  # Sonek soyma sezgiseldir ve kayıplıdır; 100 puanlık otomatik kabul yolu
  # sezgisel bir adıma BAĞLANMAZ. Soyma yalnızca belirteç katmanlarında
  # (puan tavanı 89) çalışır.
  normal <- pk_entity_normalize("projelerinde")
  expect_equal(normal$fold, "projelerinde")
  expect_equal(normal$tokens, "proje")
})

test_that("boş ve NA girdiler blank olarak işaretlenir", {
  testthat::skip_if_not_installed("stringi")

  for (girdi in list("", "   ", NA_character_, NULL, "---")) {
    normal <- pk_entity_normalize(girdi)
    expect_true(isTRUE(normal$blank))
    expect_true(is.na(normal$fold))
    expect_equal(length(normal$tokens), 0L)
  }
})

test_that("çoğulluk sezgiseli çoğul ekleri ve belirteçleri yakalar", {
  testthat::skip_if_not_installed("stringi")

  expect_true(pk_entity_phrase_is_plural("tüm projeler"))
  expect_true(pk_entity_phrase_is_plural("kalıplar"))
  expect_true(pk_entity_phrase_is_plural("bütün hatlar"))
  expect_true(pk_entity_phrase_is_plural("hepsi"))

  expect_false(pk_entity_phrase_is_plural("ANKA projesi"))
  expect_false(pk_entity_phrase_is_plural("istanbul"))

  # Kısa sözcükler çoğul sayılmaz: "genel" -> "nel" son eki değildir.
  expect_false(pk_entity_phrase_is_plural("genel"))
  expect_false(pk_entity_phrase_is_plural("tünel"))
})

test_that("normalleştirme yerelden bağımsızdır", {
  testthat::skip_if_not_installed("stringi")

  ornekler <- c("KALIP", "İSTANBUL PROJESİ", "Şebeke Bakımı", "ANKA'nın")
  beklenen <- vapply(ornekler, function(x) pk_entity_normalize(x)$fold,
                     character(1), USE.NAMES = FALSE)

  eski <- Sys.getlocale("LC_COLLATE")
  for (yerel in c("C", "C.UTF-8")) {
    denendi <- tryCatch({
      Sys.setlocale("LC_COLLATE", yerel)
      TRUE
    }, warning = function(w) FALSE, error = function(e) FALSE)
    if (!denendi) next

    simdiki <- vapply(ornekler, function(x) pk_entity_normalize(x)$fold,
                      character(1), USE.NAMES = FALSE)
    expect_equal(simdiki, beklenen,
                 info = sprintf("Yerel '%s' altında katlama değişti.", yerel))
  }
  tryCatch(Sys.setlocale("LC_COLLATE", eski), warning = function(w) NULL)
})
