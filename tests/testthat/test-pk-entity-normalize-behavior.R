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

pk_entity_source_chain_for_tests()

# TABAN YALITIMI: bu dosyadaki SARILMAMIŞ varsayılan-eşik çağrıları da
# dağıtım `MERGEN_PK_RESOLVE_*` / `mergen.pk.*` değerlerinden etkilenmemelidir.
pk_entity_isolate_resolve_config()

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

  # ÇOKLUK KORUNUR. Tekilleştirme "BORA BORA" ile "BORA"yı ayırt edilemez
  # hâle getirir ve kapsama katmanı yanlış kanonik varlığı otomatik seçer.
  expect_equal(pk_entity_normalize("proje proje")$tokens, c("proje", "proje"))
})

test_that("tekrarlı belirteçli ad tekil adla ÇAKIŞMAZ", {
  testthat::skip_if_not_installed("stringi")

  # Çokluk farkındalı kapsama olmadan J = 1.0 ve katman 4 puanı 89 olurdu;
  # varsayılan AUTO 85 aşılır ve "BORA" sessizce seçilirdi.
  karar <- pk_entity_resolve("BORA BORA", c("BORA"))
  expect_false(identical(karar$decision, "auto"))
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

# Yerel bağımsızlığının KÖK NEDENİ: karşılaştırılan iki tarafın da UTF-8
# işaretli olması. Windows VM'de `source(..., encoding = "UTF-8")` sabitleri
# YEREL kodlamaya (WINDOWS-1254) çevirir; `identical()` böyle bir sabiti UTF-8
# metinle karşılaştırırken native tarafı GÜNCEL yerele göre çevirmek zorunda
# kalır ve yerel `C` iken bu çeviri başarısız olur. Bu sözleşme, sabitlerin
# yükleme anında UTF-8'e sabitlendiğini (yani sonraki yerel değişikliklerinden
# etkilenmediğini) DOĞRUDAN sınar; davranış testi yalnızca sonucu görür.
test_that("Türkçe ek/ünlü sabitleri UTF-8 işaretlidir", {
  sabitler <- c(
    .PK_ENTITY_SUFFIXES, .PK_MORPH_VOCAB_ONLY_SUFFIXES,
    .PK_MORPH_BACK_VOWELS, .PK_MORPH_FRONT_VOWELS,
    .PK_MORPH_SOFTENED, .PK_MORPH_TR_ONLY_CHARS,
    unlist(.PK_MORPH_HARDENED, use.names = FALSE),
    names(.PK_MORPH_HARDENED)
  )

  # Saf ASCII ögelerde `Encoding()` "unknown" kalır ve bu DOĞRUDUR; sınanması
  # gereken yalnızca Türkçe karakter taşıyan ögelerdir.
  turkce <- sabitler[grepl("[^ -~]", sabitler, useBytes = TRUE)]

  expect_gt(length(turkce), 0L)
  expect_true(
    all(Encoding(turkce) == "UTF-8"),
    info = paste(
      "Türkçe sabitler yükleme anında `enc2utf8()` ile sabitlenmelidir;",
      "aksi hâlde yerel değiştiğinde ek eşleşmesi sessizce kaybolur."
    )
  )
})

test_that("normalleştirme yerelden bağımsızdır", {
  testthat::skip_if_not_installed("stringi")

  ornekler <- c("KALIP", "İSTANBUL PROJESİ", "Şebeke Bakımı", "ANKA'nın")
  beklenen <- vapply(ornekler, function(x) pk_entity_normalize(x)$fold,
                     character(1), USE.NAMES = FALSE)

  # DOĞRU KATEGORİ `LC_CTYPE`'dır: Türkçe büyük/küçük harf dönüşümü ve
  # karakter sınıflandırması ona bağlıdır. Yalnızca `LC_COLLATE` (sıralama)
  # değiştirmek bu bağımlılığı HİÇ sınamaz; ileride kazara eklenen bir
  # `tolower()` yolu testten geçmeye devam ederdi.
  # GERİ YÜKLEME `on.exit` İLE GARANTİ EDİLİR.
  #
  # Bir `expect_*` başarısız olduğunda testthat testin geri kalanını atlar;
  # döngüden sonra yazılan bir geri yükleme satırına HİÇ ULAŞILMAZDI ve süreç
  # `LC_CTYPE = "C"` olarak kalırdı. testthat tüm dosyaları AYNI oturumda
  # çalıştırdığı için bu, sonraki dosyalarda Türkçe metin karşılaştırmalarını
  # ve `source(..., encoding = "UTF-8")` çevirilerini bozar: tek bir hata
  # ilgisiz dosyalarda ardıl hatalara dönüşür.
  eski <- Sys.getlocale("LC_CTYPE")
  on.exit(
    tryCatch(Sys.setlocale("LC_CTYPE", eski), warning = function(w) NULL),
    add = TRUE
  )

  for (yerel in c("C", "C.UTF-8", "tr_TR.UTF-8")) {
    denendi <- tryCatch({
      Sys.setlocale("LC_CTYPE", yerel)
      TRUE
    }, warning = function(w) FALSE, error = function(e) FALSE)
    if (!denendi) next

    simdiki <- vapply(ornekler, function(x) pk_entity_normalize(x)$fold,
                      character(1), USE.NAMES = FALSE)
    expect_equal(simdiki, beklenen,
                 info = sprintf("Yerel '%s' altında katlama değişti.", yerel))
  }

  # Geri yükleme `on.exit` ile yapılır; burada GERÇEKTEN geri alındığı sınanır.
  # Aksi hâlde sızan yerel sessizce sonraki dosyalara taşınır.
  tryCatch(Sys.setlocale("LC_CTYPE", eski), warning = function(w) NULL)
  expect_identical(Sys.getlocale("LC_CTYPE"), eski)
})

# ---------------------------------------------------------------------------
# NOKTALAMA SINIRI ve AYIRICI EK TARAMASI
# ---------------------------------------------------------------------------

test_that("virgül/noktalı virgül sınırları AYRI anım üretir", {
  skip_if_not_installed("stringi")

  # GERİLEME: `pk_entity_normalize()` noktalamayı boşluğa indirdiği için
  # bölme YALNIZCA bağlaç sözcükleri üzerinden yapılıyordu. `ANKA, AKINCI
  # projeleri` TEK bir `anka akinci` anımı üretiyor, anım geçişi iki kanonik
  # adayın HİÇBİRİNE ulaşamıyor ve geçerli çok-varlıklı istek reddedilebiliyordu.
  animlar <- pk_entity_mentions("ANKA, AKINCI projeleri")
  expect_true(length(animlar) >= 2L)

  for (ayirici in c(",", ";", "/", "|")) {
    a <- pk_entity_mentions(paste0("ALFA", ayirici, " BETA"))
    expect_true(length(a) >= 2L, info = ayirici)
  }

  # Bağlaçla bölme davranışı DEĞİŞMEZ.
  expect_true(length(pk_entity_mentions("ALFA ve BETA")) >= 2L)
})

test_that("ayırıcı ek taraması İLK eşleşmede DURMAZ", {
  skip_if_not_installed("stringi")

  # GERİLEME: `stri_match_first_regex()` en soldaki eşleşmeyi verir; tireli
  # kanonik bir adda (`HAVA-SAVUNMA-da`) bu `A-SAVUNMA`dır ve `savunma` ek
  # zinciri değildir. Döngü orada durunca sondaki gerçek `-da` eki hiç
  # soyulmuyor ve tam eşleşecek varlık kaçırılıyordu.
  expect_identical(.pk_entity_strip_separator_suffixes_one("HAVA-SAVUNMA-da"),
                   "HAVA-SAVUNMA")

  # Tek ayırıcılı durum ve ek TAŞIMAYAN ad davranışı DEĞİŞMEZ.
  expect_identical(.pk_entity_strip_separator_suffixes_one("ANKA-da"), "ANKA")
  expect_identical(.pk_entity_strip_separator_suffixes_one("HAVA-SAVUNMA"),
                   "HAVA-SAVUNMA")

  # Birden fazla belirtecte de SON ek soyulur.
  expect_identical(.pk_entity_strip_separator_suffixes_one("HAVA-SAVUNMA ANKA-da"),
                   "HAVA-SAVUNMA ANKA")
})
