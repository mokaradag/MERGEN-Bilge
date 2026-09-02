# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-entity-score-behavior.R
# Açıklama: Faz 4 altı katmanlı puanlama şelalesi testleri (master plan §5.4).
#           Tamamen çevrimdışı ve belirlenimcidir: DB, LLM, tarayıcı, SSO, ağ
#           veya gizli değer GEREKMEZ.
#
# BU DOSYA FORMÜLLERİ SÖZLEŞME OLARAK SABİTLER. Master plan §5.4 açıkça
# "formüller sözleşmedir, örnek aralık değildir" der ve sınır fikstürleri
# ister; bir uygulama farklı bir ara değer seçip yine de uyumlu olduğunu
# İDDİA EDEMEZ:
#
#   J = 0.60            -> 60
#   J = 1'in hemen altı -> 84
#   d = 0.20            -> 50
#   katman 4            -> hem 85 hem 89 üretebilmeli
#   "kalip" -> "kalıp"  -> tam olarak 90
# ==============================================================================

pk_entity_source_chain_for_tests()

# TABAN YALITIMI: bu dosyadaki SARILMAMIŞ varsayılan-eşik çağrıları da
# dağıtım `MERGEN_PK_RESOLVE_*` / `mergen.pk.*` değerlerinden etkilenmemelidir.
pk_entity_isolate_resolve_config()

# En yüksek puanlı eşleşmeyi "katman/puan" biçiminde döndürür.
.pk_ent_top <- function(phrase, candidates, ...) {
  sonuc <- pk_entity_score_candidates(phrase, candidates, ...)
  if (!length(sonuc$matches)) return(NULL)
  sonuc$matches[[1]]
}

test_that("katman 1: kesin katlama eşleşmesi tam 100 puandır", {
  testthat::skip_if_not_installed("stringi")

  ust <- .pk_ent_top("ANKA", c("ANKA", "AKINCI"))
  expect_equal(ust$tier, "exact_fold")
  expect_equal(ust$score, 100L)

  # Büyük/küçük harf ve boşluk farkı katman 1'i BOZMAZ.
  expect_equal(.pk_ent_top("  anka  ", c("ANKA"))$score, 100L)
})

test_that("katman 2: doğrulanmış alias tam 95 puandır", {
  testthat::skip_if_not_installed("stringi")

  # Alias haritası pk_meta_fold_alias_map() biçimindedir: adlar KATLANMIŞ
  # alias anahtarı, değerler kanonik hedef.
  aliases <- c("anka" = "SENTETIK PROJE A")

  ust <- .pk_ent_top("ANKA", c("SENTETIK PROJE A", "SENTETIK PROJE B"),
                     aliases = aliases)
  expect_equal(ust$tier, "alias")
  expect_equal(ust$score, 95L)
  expect_equal(ust$value, "SENTETIK PROJE A")
})

test_that("alias katman 1'i EZMEZ: kesin eşleşme her zaman kazanır", {
  testthat::skip_if_not_installed("stringi")

  aliases <- c("anka" = "SENTETIK PROJE B")
  sonuc <- pk_entity_score_candidates("ANKA", c("ANKA", "SENTETIK PROJE B"),
                                      aliases = aliases)

  expect_equal(sonuc$matches[[1]]$value, "ANKA")
  expect_equal(sonuc$matches[[1]]$score, 100L)
  expect_equal(sonuc$matches[[2]]$score, 95L)
})

test_that("alias hedefi sözlükte yoksa açıkça raporlanır", {
  testthat::skip_if_not_installed("stringi")

  aliases <- c("anka" = "SOZLUKTE OLMAYAN DEGER")
  sonuc <- pk_entity_score_candidates("ANKA", c("BASKA DEGER"), aliases = aliases)

  expect_true(isTRUE(sonuc$alias_target_missing))
})

test_that("katman 3: ASCII ikincil anahtar tam 90 puandır (kalip -> kalıp)", {
  testthat::skip_if_not_installed("stringi")

  ust <- .pk_ent_top("kalip", c("KALIP"))
  expect_equal(ust$tier, "ascii_key")
  expect_equal(ust$score, 90L)
})

test_that("ASCII anahtarı çakışan tüm kanonik değerler 90'da EŞİT döner", {
  testthat::skip_if_not_installed("stringi")

  # "İŞÇİ" -> ascii "isci"; "IŞÇI" -> ascii "isci". Kullanıcının katlanmış
  # anahtarı ("isci") İKİSİYLE DE eşleşmez, ama ASCII anahtarı ikisiyle de
  # eşleşir. Plan: hepsi 90'da EŞİT dönmeli, biri yineleme sırasına göre
  # SEÇİLMEMELİ.
  sonuc <- pk_entity_score_candidates("isci", c("İŞÇİ", "IŞÇI"))

  expect_equal(length(sonuc$matches), 2L)
  expect_equal(vapply(sonuc$matches, function(m) m$score, integer(1)), c(90L, 90L))
  expect_true(all(vapply(sonuc$matches, function(m) m$tier, character(1)) == "ascii_key"))
})

test_that("katman 4 SINIR: J = 1 tam 89, düşük J tam 85 puandır", {
  testthat::skip_if_not_installed("stringi")

  # J = 1 -> min(89, 85 + floor(4*1)) = 89. Belirteç kümeleri AYNI, ama
  # katlanmış dizgiler farklı (sıra), bu yüzden katman 1 devreye girmez.
  ust <- .pk_ent_top("beta alfa", c("alfa beta"))
  expect_equal(ust$tier, "token_subset")
  expect_equal(ust$score, 89L)

  # J = 1/5 = 0.2 -> min(89, 85 + floor(0.8)) = 85.
  alt <- .pk_ent_top("alfa", c("alfa beta gama delta epsilon"))
  expect_equal(alt$tier, "token_subset")
  expect_equal(alt$score, 85L)
})

test_that("katman 5 SINIR: J = 0.60 tam 60 puandır", {
  testthat::skip_if_not_installed("stringi")

  # Kesişim 3, birleşim 5 -> J = 0.60. Kullanıcı belirteci "xxxx" adayda
  # OLMADIĞI için katman 4 devreye girmez.
  ust <- .pk_ent_top("aaaa bbbb cccc xxxx", c("aaaa bbbb cccc yyyy"))
  expect_equal(ust$tier, "token_jaccard")
  expect_equal(ust$score, 60L)
})

test_that("katman 5 SINIR: J = 1'in hemen altı tam 84 puandır", {
  testthat::skip_if_not_installed("stringi")

  # J = 62/63 = 0.98413 -> 60 + floor(25 * 0.38413 / 0.40) = 60 + 24 = 84.
  #
  # Fikstür, üretim ifade uzunluğu tavanını (MAX_PHRASE_CHARS) aşar; tavan
  # gerçek bir güvenlik sınırıdır (yapıştırılmış metin paylaşılan süreci
  # meşgul edemesin) ve BU test için bilerek yükseltilir.
  ortak <- paste0("t", seq_len(62), collapse = " ")
  ust <- pk_entity_with_resolve_env(
    c(MERGEN_PK_RESOLVE_MAX_PHRASE_CHARS = "4000"),
    .pk_ent_top(paste(ortak, "zzzz"), c(ortak))
  )

  expect_equal(ust$tier, "token_jaccard")
  expect_equal(ust$score, 84L)
})

test_that("katman 5 TAM SAYI sınırı kayan nokta tozuyla kaymaz", {
  testthat::skip_if_not_installed("stringi")

  # J = 123/125 = 0.984. Sözleşme 60 + floor(24) = 84 der. `floor(25 * (J -
  # 0.6) / 0.4)` ikili kayan noktada 23.999999999999996 verir ve 83 üretir;
  # geçerli bir 84 eşiğinde bu, "onaylanabilir" ile "çözümlenemedi" farkıdır.
  expect_equal(.pk_entity_tier5_score_counts(123L, 125L), 84L)
  expect_equal(.pk_entity_tier5_score_counts(62L, 63L), 84L)
})

test_that("katman 6 TAM SAYI sınırı otomatik eşiği AŞMAZ", {
  testthat::skip_if_not_installed("stringi")

  # 95 karakterlik iki dizgi, tek ikame: d = 1/95. Sözleşme 69 - floor(1) =
  # 68 der. `floor(19 * d / 0.20)` ikili kayan noktada 0.9999999999999999
  # verip 69 üretir; MIN=MULTI=AUTO=69 yapılandırmasında bu, çözümlenemeyen
  # bir eşleşmeyi kural-4 OTOMATİK filtresine çevirir.
  expect_equal(.pk_entity_tier6_score_counts(1L, 95L), 68L)
  expect_equal(.pk_entity_tier6_score_counts(1L, 5L), 50L)
})

test_that("katman 6 SINIR: d = 0.20 tam 50 puandır", {
  testthat::skip_if_not_installed("stringi")
  testthat::skip_if_not_installed("stringdist")

  # 10 karakterin 2'si farklı -> d = 0.20 -> max(50, 69 - floor(19)) = 50.
  ust <- .pk_ent_top("abcdefghij", c("abcdefghxy"))
  expect_equal(ust$tier, "edit_distance")
  expect_equal(ust$score, 50L)
})

test_that("katman 6 üst ucu 69'u AŞMAZ", {
  testthat::skip_if_not_installed("stringi")
  testthat::skip_if_not_installed("stringdist")

  # 69 puanı için floor(19*d/0.20) = 0, yani d < 1/19 * 0.20 = 0.010526
  # olmalıdır. 100 karakterde tek fark -> d = 0.01 -> tam 69.
  uzun_a <- paste0(rep("ab", 50), collapse = "")
  uzun_b <- paste0(substring(uzun_a, 1L, nchar(uzun_a) - 1L), "z")
  expect_equal(nchar(uzun_a), 100L)

  ust <- .pk_ent_top(uzun_a, c(uzun_b))
  expect_equal(ust$tier, "edit_distance")
  expect_equal(ust$score, 69L)

  # 80 karakterde tek fark -> d = 0.0125 -> floor(1.1875) = 1 -> 68.
  # Formül SÖZLEŞMEDİR; "yaklaşık 69" kabul edilmez.
  orta_a <- paste0(rep("ab", 40), collapse = "")
  orta_b <- paste0(substring(orta_a, 1L, nchar(orta_a) - 1L), "z")
  expect_equal(.pk_ent_top(orta_a, c(orta_b))$score, 68L)
})

test_that("d > 0.20 hiçbir puan üretmez", {
  testthat::skip_if_not_installed("stringi")
  testthat::skip_if_not_installed("stringdist")

  # Tamamen ilgisiz dizgiler: hiçbir katman eşleşmemeli.
  sonuc <- pk_entity_score_candidates("qqqqqqqqqq", c("wwwwwwwwww"))
  expect_equal(length(sonuc$matches), 0L)
})

test_that("katmanlar SIRAYLA denenir: ilk eşleşen kazanır", {
  testthat::skip_if_not_installed("stringi")

  # Tek bir aday için katman kimliği beklenen sırayı yansıtmalıdır.
  expect_equal(.pk_ent_top("ANKA", c("ANKA"))$tier, "exact_fold")
  expect_equal(.pk_ent_top("kalip", c("KALIP"))$tier, "ascii_key")
  expect_equal(.pk_ent_top("beta alfa", c("alfa beta"))$tier, "token_subset")
})

test_that("kodlar ve kimlikler ASLA bulanıklaştırılmaz", {
  testthat::skip_if_not_installed("stringi")

  # exact_only altında katman 3-6 KAPALIDIR.
  expect_null(.pk_ent_top("kalip", c("KALIP"), exact_only = TRUE))
  expect_null(.pk_ent_top("PRJ-001X", c("PRJ-0010"), exact_only = TRUE))

  # Katman 1 ve 2 ise çalışmaya devam eder.
  expect_equal(.pk_ent_top("PRJ-001", c("PRJ-001"), exact_only = TRUE)$score, 100L)
  expect_equal(
    .pk_ent_top("kısaltma", c("PRJ-001"),
                aliases = c("kısaltma" = "PRJ-001"), exact_only = TRUE)$score,
    95L
  )
})

test_that("boş ifade ve boş sözlük GEÇERSİZ GİRDİDİR, sıfır puan değil", {
  testthat::skip_if_not_installed("stringi")

  bos_ifade <- pk_entity_score_candidates("   ", c("ANKA"))
  expect_false(bos_ifade$valid)
  expect_equal(bos_ifade$reason, "bos_ifade")

  bos_sozluk <- pk_entity_score_candidates("ANKA", character(0))
  expect_false(bos_sozluk$valid)
  expect_equal(bos_sozluk$reason, "bos_sozluk")

  # Geçersiz girdi 0 puanlı bir eşleşme listesi ÜRETMEZ.
  expect_equal(length(bos_ifade$matches), 0L)
  expect_equal(length(bos_sozluk$matches), 0L)
})

test_that("sıralama belirlenimcidir ve yineleme sırasına bağlı DEĞİLDİR", {
  testthat::skip_if_not_installed("stringi")

  adaylar <- c("İŞÇİ", "IŞÇI")
  ileri <- pk_entity_score_candidates("isci", adaylar)
  geri  <- pk_entity_score_candidates("isci", rev(adaylar))

  expect_equal(
    vapply(ileri$matches, function(m) m$value, character(1)),
    vapply(geri$matches, function(m) m$value, character(1))
  )
})

test_that("uzun Türkçe proje adları kısmi ifadeden çözümlenir", {
  testthat::skip_if_not_installed("stringi")

  # Gerçekçi karışık büyük/küçük harfli TÜRKÇE karakterli adlar.
  sozluk <- c(
    "Sentetik Elektronik Harp Şebekesi Modernizasyonu",
    "Sentetik Lojistik Destek Altyapısı",
    "Sentetik Eğitim Simülatörü"
  )

  # Kullanıcı tam adı yazmaz; iki ayırt edici sözcük yeterli olmalıdır.
  ust <- .pk_ent_top("elektronik harp", sozluk)
  expect_equal(ust$value, "Sentetik Elektronik Harp Şebekesi Modernizasyonu")
  expect_equal(ust$tier, "token_subset")
  expect_true(ust$score >= 85L)

  # Sözcük SIRASI önemli değildir.
  expect_equal(.pk_ent_top("harp elektronik", sozluk)$value, ust$value)

  # Türkçe karakter YAZILMADAN da bulunmalıdır ("altyapisi" -> "Altyapısı").
  expect_equal(
    .pk_ent_top("lojistik altyapisi", sozluk)$value,
    "Sentetik Lojistik Destek Altyapısı"
  )

  # Ekli biçim de çalışır: "şebekesi" -> "şebeke" gövdesi.
  expect_equal(
    .pk_ent_top("elektronik harp şebekesi", sozluk)$value,
    "Sentetik Elektronik Harp Şebekesi Modernizasyonu"
  )
})

test_that("TAMAMI BÜYÜK HARF ASCII sözlük kısmi ifadeyle çözümlenir (E3)", {
  testthat::skip_if_not_installed("stringi")

  # Türkçe katlama ASCII `I` -> noktasız `ı` yapar; bu yüzden TAMAMI BÜYÜK
  # HARF ASCII bir sözlük değeri ("ELEKTRONIK" -> "elektronık") kullanıcının
  # yazdığı "elektronik" (noktalı i) ile belirteç düzeyinde ASLA eşleşmez.
  # Belirteç katmanları ASCII anahtarını da dikkate almazsa bu kabul ölçütü
  # sessizce başarısız olur.
  expect_false(identical(pk_tr_fold("ELEKTRONIK"), pk_tr_fold("elektronik")))

  sozluk <- c(
    "SENTETIK ELEKTRONIK HARP SEBEKESI MODERNIZASYONU",
    "SENTETIK LOJISTIK DESTEK ALTYAPISI",
    "SENTETIK EGITIM SIMULATORU"
  )

  ust <- .pk_ent_top("elektronik harp", sozluk)
  expect_equal(ust$value, "SENTETIK ELEKTRONIK HARP SEBEKESI MODERNIZASYONU")
  expect_equal(ust$tier, "token_subset")
  expect_true(ust$score >= 85L)

  # Sözcük SIRASI önemli değildir.
  expect_equal(.pk_ent_top("harp elektronik", sozluk)$value, ust$value)
})

test_that("ASCII belirteç desteği katman SIRASINI değiştirmez", {
  testthat::skip_if_not_installed("stringi")

  # Katman 3 (90) hâlâ katman 4'ten (tavan 89) ÖNCE gelir: tüm dizgi ASCII
  # eşleşmesi, belirteç kapsamasından DAHA YÜKSEK puan almalıdır.
  expect_equal(.pk_ent_top("kalip", c("KALIP"))$score, 90L)
  expect_equal(.pk_ent_top("kalip", c("KALIP"))$tier, "ascii_key")

  # ASCII desteği puanı yalnızca ARTIRABİLİR; sınır fikstürleri saf ASCII
  # olduğu için hiçbiri etkilenmez (yukarıdaki sınır testleri bunu kanıtlar).
  expect_equal(.pk_ent_top("beta alfa", c("alfa beta"))$score, 89L)
  expect_equal(.pk_ent_top("aaaa bbbb cccc xxxx", c("aaaa bbbb cccc yyyy"))$score, 60L)
})

test_that("Jaccard ve düzenleme oranı yardımcıları doğrudan doğrulanır", {
  # `pk_entity_edit_ratio()` normalizasyon yolundan `.pk_entity_require_stringi()`
  # çağırır; `stringi` yoksa bu blok ATLAMAK yerine HATA verirdi.
  testthat::skip_if_not_installed("stringi")
  testthat::skip_if_not_installed("stringdist")

  expect_equal(pk_entity_jaccard(c("a", "b"), c("a", "b")), 1)
  expect_equal(pk_entity_jaccard(c("a", "b", "c"), c("a", "b", "c", "d", "e")), 0.6)
  expect_equal(pk_entity_jaccard(character(0), c("a")), 0)

  expect_equal(pk_entity_edit_ratio("abcde", "abcde"), 0)
  expect_equal(pk_entity_edit_ratio("abcdefghij", "abcdefghxy"), 0.2)
  expect_equal(pk_entity_edit_ratio(NA_character_, "abc"), 1)
})

test_that("'stringdist' YOKKEN katman 6 istisna DEĞİL, eşleşmesizlik üretir", {
  # ÇALIŞMA ZAMANI VE TEST BEKLENTİSİ AYNI OLMALIDIR: paket testlerde
  # opsiyonel sayılırken üretimde koşulsuz zorunluydu. Kısa listeye giren ve
  # katman 1-5'te eşleşmeyen HER aday katman 6'ya ulaştığı için tek eksik
  # paket TÜM varlık çözümlemesini istisnaya çeviriyordu.
  skip_if_not_installed("stringi")

  # `requireNamespace` sourced ortamda leksik olarak taklit edilir; gerçek
  # kurulum DEĞİŞTİRİLMEZ.
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  pk_entity_source_chain_for_tests(env = env)
  env$requireNamespace <- function(package, ...) {
    if (identical(package, "stringdist")) FALSE else base::requireNamespace(package, ...)
  }
  env$.pk_entity_score_state$stringdist_warned <- TRUE  # uyari gurultusu YOK

  expect_null(env$.pk_entity_edit_counts("abcdefghij", "abcdefghxy"))
  # Oran 1 = "en uzak"; katman 6 eşiği (0.20) ASLA geçilmez.
  expect_equal(env$pk_entity_edit_ratio("abcdefghij", "abcdefghxy"), 1)

  sonuc <- env$pk_entity_score_candidates("abcdefghij", c("abcdefghxy"))
  expect_equal(length(sonuc$matches), 0L)
})
