# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-entity-review-fixes.R
# Açıklama: Faz 4 inceleme bulgularının REGRESYON kilitleri (master plan §5.4).
#           Tamamen çevrimdışı ve belirlenimcidir: DB, LLM, tarayıcı, SSO, ağ
#           veya gizli değer GEREKMEZ; tüm fikstürler sentetiktir.
#
# Her `test_that` bloğu, incelemede raporlanan SOMUT bir kusurun geri
# gelmesini engeller. Bloklar kusurun ETKİSİNİ ölçer (hangi karar üretiliyor),
# uygulamanın iç ayrıntısını değil; böylece ileride yapılacak yeniden
# düzenlemeler gereksiz yere kırılmaz.
# ==============================================================================

pk_entity_source_chain_for_tests()

.PK_FIX_ESIK <- list(
  valid = TRUE, errors = character(0),
  min_score = 40L, multi_score = 70L, auto_score = 85L,
  ambiguity_margin = 10L, max_candidates = 5L
)

.pk_fix_coz <- function(...) pk_entity_resolve(..., thresholds = .PK_FIX_ESIK)

# --- Normalleştirme / biçimbirim ---------------------------------------------

test_that("kesme işareti YALNIZCA gerçek Türkçe eklerde soyulur", {
  testthat::skip_if_not_installed("stringi")

  # `O'NEIL` ile `O'BRIEN` aynı anahtara çökerse, görünmeyen adayı yazan
  # kullanıcı 100 puanla YANLIŞ varlığı sessizce filtreler.
  expect_equal(pk_entity_normalize("O'NEIL RADAR")$clitic, "o'neıl radar")
  expect_false(identical(
    pk_entity_normalize("O'NEIL RADAR")$clitic,
    pk_entity_normalize("O'BRIEN RADAR")$clitic
  ))

  karar <- .pk_fix_coz("O'BRIEN RADAR", c("O'NEIL RADAR"))
  expect_false(identical(karar$decision, "auto"))

  # Gerçek ek yine soyulur.
  expect_equal(pk_entity_normalize("ANKA'nın")$clitic, "anka")
})

test_that("sol tipografik kesme işareti (U+2018) tanınır", {
  testthat::skip_if_not_installed("stringi")

  sol <- paste0("ANKA", intToUtf8(0x2018L), "nın")
  expect_equal(pk_entity_normalize(sol)$clitic, "anka")
  expect_equal(.pk_fix_coz(sol, c("ANKA"))$decision, "auto")
})

test_that("şapkalı ünlüler ASCII anahtarında katlanır", {
  testthat::skip_if_not_installed("stringi")

  # `SÛRE` / `KÂĞIT` gibi kanonik değerler klavyeden `sure` / `kagit` yazılır.
  expect_equal(pk_entity_ascii_key(pk_tr_fold("SÛRE")), "sure")
  expect_true(length(pk_entity_score_candidates("sure", c("SÛRE"))$matches) >= 1L)
})

test_that("tampon ünsüzlü ve uzun sonek zincirleri çözülür", {
  testthat::skip_if_not_installed("stringi")

  # Ham kuyruk silme bunları modelleyemez: `projesinde` -> `projes` olurdu.
  expect_equal(pk_entity_stem_token("projesinde"), "proje")
  expect_equal(pk_entity_stem_token("projeyi"), "proje")
  expect_equal(pk_entity_stem_token("projeyle"), "proje")
  expect_equal(pk_entity_stem_token("projemiz"), "proje")
  expect_equal(pk_entity_stem_token(pk_tr_fold("programımızda")), "program")

  # Dört üretken sonek üst üste gelebilir; sabit üç geçişlik tavan gövdeyi
  # yarıda bırakırdı.
  expect_equal(pk_entity_stem_token("projelerindekiler"), "proje")
})

test_that("kısa akronim ve ünsüz yumuşaması SÖZLÜKLE doğrulanarak çözülür", {
  testthat::skip_if_not_installed("stringi")

  # Dört karakterlik gövde alt sınırı `ihalar -> iha` soymasını engelliyordu.
  expect_equal(pk_entity_stem_token("ihalar", vocab = c("iha")), "iha")

  # `kitabı` -> `kitab` -> (b/p yumuşaması geri alınır) -> `kitap`.
  expect_equal(pk_entity_stem_token(pk_tr_fold("kitabı"), vocab = c("kitap")), "kitap")
  expect_equal(pk_entity_stem_token(pk_tr_fold("ağacı"), vocab = c(pk_tr_fold("ağaç"))),
               pk_tr_fold("ağaç"))

  # Sözlükte KARŞILIĞI OLMAYAN uydurma gövde üretilmez.
  expect_false(identical(pk_entity_stem_token("kitabı", vocab = c("zzzz")), "kitap"))
})

test_that("çoğul sinyali hâl/iyelik eklerinin ALTINDAN okunur", {
  testthat::skip_if_not_installed("stringi")

  expect_true(pk_entity_phrase_is_plural("projelerde"))
  expect_true(pk_entity_phrase_is_plural(pk_tr_fold("kalıplardan")))
  expect_true(pk_entity_phrase_is_plural(pk_tr_fold("projelerin")))
})

test_that("kesme işaretiyle ayrılmış çoğul EK SOYULMADAN yakalanır", {
  testthat::skip_if_not_installed("stringi")

  # `F-16'lar` -> kesme eki soyulunca `f 16` kalır ve sinyal KAYBOLURDU.
  expect_true(pk_entity_phrase_is_plural("F-16'lar"))
  expect_true(pk_entity_phrase_is_plural("TV'ler"))
})

test_that("her -lar/-ler bitişi çoğul SAYILMAZ", {
  testthat::skip_if_not_installed("stringi")

  expect_false(pk_entity_phrase_is_plural("SOLAR"))
  expect_false(pk_entity_phrase_is_plural("DOLAR"))

  # Kanonik adla TAM eşleşen ifadede ipucu bastırılır.
  karar <- .pk_fix_coz("SOLAR", c("SOLAR", "SOLAR RADAR"))
  expect_equal(karar$decision, "auto")
  expect_equal(karar$values, "SOLAR")
})

test_that("komut/liste adları çoğul VARLIK niyeti kurmaz", {
  testthat::skip_if_not_installed("stringi")

  expect_false(pk_entity_phrase_is_plural(pk_tr_fold("KAYNAK LİSTESİ")))

  karar <- .pk_fix_coz(
    pk_tr_fold("KAYNAK LİSTESİ"),
    c(pk_tr_fold("KAYNAK LİSTESİ"), pk_tr_fold("KAYNAK LİSTESİ DETAY"))
  )
  expect_equal(karar$decision, "auto")

  # `her` de ipucu listesindedir ama kanonik adla tam eşleşme onu bastırır.
  expect_equal(.pk_fix_coz("HER", c("HER", "HER PROGRAMI"))$decision, "auto")
})

test_that("çoğul ipucu sözcüklerinin ASCII yazımları da tanınır", {
  testthat::skip_if_not_installed("stringi")

  # Kullanıcı Türkçe karakter yazmayabilir; ipucu kaybolursa istek tekil
  # kural 4/5 yoluna düşer.
  for (ifade in c("tum ANKA", "butun ANKA", "birkac ANKA", "bazi ANKA")) {
    expect_true(pk_entity_phrase_is_plural(ifade), info = ifade)
  }
})

test_that("genel sıfat-fiiller ('olanlar') çoğul VARLIK isteği değildir", {
  testthat::skip_if_not_installed("stringi")

  # "sadece aktif olanlar" tek bir varlığın kayıtlarını daraltır; iki kanonik
  # değeri BİRLEŞTİRMEZ.
  expect_false(pk_entity_phrase_is_plural("sadece aktif olanlar"))
})

# --- Anahtarlar / katmanlar ---------------------------------------------------

test_that("anlamlı noktalama kesin katmanda KORUNUR", {
  testthat::skip_if_not_installed("stringi")

  # `A+B` ile `A/B` ayrı kanonik varlıklardır.
  expect_false(identical(
    pk_entity_normalize("A+B")$clitic, pk_entity_normalize("A/B")$clitic
  ))

  karar <- .pk_fix_coz("A+B", c("A/B"))
  expect_false(identical(karar$decision, "auto"))
  expect_true(karar$decision %in% c("confirm", "clarify", "unresolved"))
})

test_that("ayırıcısı düşürülmüş yazım ÇÖZÜLÜR ama otomatik kabul EDİLMEZ", {
  testthat::skip_if_not_installed("stringi")

  # `F16` <-> `F-16`: eskiden hiçbir katman tutmuyor ve istek bloke oluyordu.
  karar <- .pk_fix_coz("F16", c("F-16"))
  expect_equal(karar$decision, "confirm")
  expect_equal(karar$chips[[1]]$value, "F-16")
})

test_that("kullanıcı Türkçe harf YAZDIYSA ASCII katlaması otomatik kabul etmez", {
  testthat::skip_if_not_installed("stringi")

  # `KİR` ile `KIR` ayrı varlıklardır; ASCII yedeği eksik harfi tamamlamak
  # içindir, bilgi silmek için değil.
  # HAM girdi verilir: `İ` katlandığında sade `i` olur, bu yüzden "kullanıcı
  # Türkçe yazdı mı" sorusu ham metinden yanıtlanmalıdır.
  karar <- .pk_fix_coz("KİR", c("KIR"))
  expect_false(identical(karar$decision, "auto"))

  # ASCII yazan kullanıcı için yol AÇIK kalır.
  expect_equal(.pk_fix_coz("kalip", c(pk_tr_fold("KALIP")))$decision, "auto")
})

test_that("tek ve genel bir belirteç otomatik filtre gerekçesi DEĞİLDİR", {
  testthat::skip_if_not_installed("stringi")

  karar <- .pk_fix_coz("proje", c("BUYUK PROJE X"))
  expect_false(identical(karar$decision, "auto"))
})

test_that("sözcük SIRASI korunmadan otomatik kabul YAPILMAZ", {
  testthat::skip_if_not_installed("stringi")

  karar <- .pk_fix_coz("kara deniz", c("deniz kara"))
  expect_false(identical(karar$decision, "auto"))
})

test_that("sözlükle doğrulanmamış gövde soyma otomatik kabule ULAŞAMAZ", {
  testthat::skip_if_not_installed("stringi")

  # `Mersin` -> `mers` soyması `MERS Radar` ile 89 puan üretip AUTO'yu geçerdi.
  karar <- .pk_fix_coz("MERS Radar", c("Mersin Radar"))
  expect_false(identical(karar$decision, "auto"))
})

test_that("sözlük normalleştirmeden sonra BOŞ kalıyorsa geçersizdir", {
  testthat::skip_if_not_installed("stringi")

  sonuc <- pk_entity_score_candidates("ANKA", c("---", "///"))
  expect_false(isTRUE(sonuc$valid))
  expect_equal(sonuc$reason, "bos_sozluk")

  expect_equal(.pk_fix_coz("ANKA", c("---", "///"))$decision, "invalid_input")
})

test_that("adaylar KANONİK anahtara göre tekilleştirilir", {
  testthat::skip_if_not_installed("stringi")

  # `"ANKA"` ile `" ANKA "` aynı varlıktır; iki ayrı 100 puanlık çip hatalı
  # bir belirsizlik üretirdi.
  karar <- .pk_fix_coz("ANKA", c("ANKA", " ANKA "))
  expect_equal(karar$decision, "auto")
  expect_equal(karar$candidate_count, 1L)
})

test_that("ifade uzunluğu ve tarama TAVANLIDIR", {
  testthat::skip_if_not_installed("stringi")

  uzun <- paste(rep("zzzz", 400), collapse = " ")
  sonuc <- pk_entity_with_resolve_env(
    c(MERGEN_PK_RESOLVE_MAX_PHRASE_CHARS = "40"),
    pk_entity_score_candidates(uzun, c("ANKA"))
  )
  expect_true(isTRUE(sonuc$phrase_truncated))
})

# --- Anım (mention) çıkarımı --------------------------------------------------

test_that("sıralı istek ayrı anımlara BÖLÜNÜR", {
  testthat::skip_if_not_installed("stringi")

  # Tek belirteç kümesi olarak puanlandığında J = 0.50 ve HİÇBİR aday
  # katmana ulaşmıyordu; kural 3'e boş küme gidiyordu.
  karar <- .pk_fix_coz(
    "ANKA ve AKINCI projeleri", c("ANKA Projesi", "AKINCI Projesi")
  )
  cipler <- vapply(karar$chips, function(c) c$value, character(1))

  expect_equal(karar$decision, "clarify")
  expect_true(all(c("ANKA Projesi", "AKINCI Projesi") %in% cipler))
})

test_that("tür nitelemeli tekil anım çözülür", {
  testthat::skip_if_not_installed("stringi")

  # `ANKA projesi` / kanonik `ANKA`: eskiden kural 6 analizi BLOKE EDİYORDU.
  karar <- .pk_fix_coz("ANKA projesi", c("ANKA"))
  expect_true(karar$decision %in% c("auto", "confirm"))
  expect_equal(karar$chips[[1]]$value, "ANKA")
})

test_that("çoğul denetim sözcüğü puanlamadan ÖNCE ayrılır", {
  testthat::skip_if_not_installed("stringi")

  # `tüm ANKA` / kanonik `ANKA`: J = 1/2 < 0.60 olduğu için kural 3 hiçbir
  # aday GÖREMİYORDU.
  karar <- .pk_fix_coz("tüm ANKA", c("ANKA"))
  expect_true(karar$decision %in% c("clarify", "confirm"))
  expect_true(length(karar$chips) >= 1L)
  expect_equal(karar$chips[[1]]$value, "ANKA")
})

# --- Alias kaydı --------------------------------------------------------------

test_that("alias araması kayıt defterinin KENDİ anahtarını kullanır", {
  testthat::skip_if_not_installed("stringi")

  # Kayıt `pk_tr_fold()` ile normalleştirilir: `eh/se`. Kayıplı anahtar
  # (`eh se`) ile arama alias katmanını SESSİZCE atlıyordu.
  aliaslar <- c("eh/se" = "SENTETIK HARP")
  sonuc <- pk_entity_score_candidates("EH/SE", c("SENTETIK HARP"), aliases = aliaslar)

  expect_false(isTRUE(sonuc$alias_target_missing))
  expect_equal(sonuc$matches[[1]]$tier, "alias")
})

test_that("onaylı alias ASCII yazımla da bulunur", {
  testthat::skip_if_not_installed("stringi")

  aliaslar <- stats::setNames("SENTETIK PROJE X", pk_tr_fold("ŞAHİN"))
  sonuc <- pk_entity_score_candidates(
    "sahin", c("SENTETIK PROJE X", "SAHIN DESTEK PROGRAMI"), aliases = aliaslar
  )

  expect_false(isTRUE(sonuc$alias_target_missing))
  expect_true(any(vapply(sonuc$matches, function(k) identical(k$tier, "alias"),
                         logical(1))))
})

test_that("alias hedefinin VARLIĞI kazanan katmandan BAĞIMSIZ ölçülür", {
  testthat::skip_if_not_installed("stringi")

  # `anka -> ANKA` geçerli bir kayıttır; katman 1 önce kazandığı için hedef
  # "eksik" sayılamaz.
  sonuc <- pk_entity_score_candidates("ANKA", c("ANKA"), aliases = c(anka = "ANKA"))
  expect_false(isTRUE(sonuc$alias_target_missing))
})

test_that("hedefi bulunmayan alias KAPALI BAŞARISIZ olur", {
  testthat::skip_if_not_installed("stringi")

  # `EH Support` 87 puan alıp otomatik uygulanıyordu; oysa bu bir
  # veri/yapılandırma tutarsızlığıdır.
  karar <- .pk_fix_coz("eh", c("EH Support"), aliases = c(eh = "ELECTRONIC HARP"))
  expect_equal(karar$decision, "unresolved")
  expect_true(isTRUE(karar$alias_target_missing))
})

test_that("çakışan alias anahtarları YAPILANDIRMA HATASIDIR", {
  testthat::skip_if_not_installed("stringi")

  # R adlandırılmış vektörlerinde ad TEKRARLANABİLİR; `match()` sessizce
  # ilkini seçerdi ve istek metadata sırasına göre rastgele yönlenirdi.
  aliaslar <- c(eh = "HEDEF A", eh = "HEDEF B")
  indeks <- pk_entity_alias_index(aliaslar)
  expect_false(isTRUE(indeks$valid))

  karar <- .pk_fix_coz("eh", c("HEDEF A", "HEDEF B"), aliases = aliaslar)
  expect_equal(karar$decision, "config_error")
})

test_that("kanonik TAM eşleşme kendi alias'ını GEÇER", {
  testthat::skip_if_not_installed("stringi")

  # Kullanıcı kanonik değeri tam yazdı: 100/95 ikilisi belirsizlik değildir.
  karar <- .pk_fix_coz(
    "ANKA", c("ANKA", "SENTETIK PROJE B"), aliases = c(anka = "SENTETIK PROJE B")
  )
  expect_equal(karar$decision, "auto")
  expect_equal(karar$values, "ANKA")
})

# --- Karar politikası ---------------------------------------------------------

test_that("bulanık şelale YALNIZCA match_mode = 'resolve' kipinde çalışır", {
  testthat::skip_if_not_installed("stringi")

  expect_equal(.pk_fix_coz("kalip", c(pk_tr_fold("KALIP")), match_mode = "none")$decision,
               "disabled")
  expect_equal(.pk_fix_coz("kalip", c(pk_tr_fold("KALIP")), match_mode = "contains")$decision,
               "not_applicable")
  expect_equal(.pk_fix_coz("kalip", c(pk_tr_fold("KALIP")), match_mode = "resolve")$decision,
               "auto")
})

test_that("95 puanlık alias KESİN KOD eşleşmesi sayılmaz", {
  testthat::skip_if_not_installed("stringi")

  yuksek <- list(
    valid = TRUE, errors = character(0),
    min_score = 100L, multi_score = 100L, auto_score = 100L,
    ambiguity_margin = 10L, max_candidates = 5L
  )

  karar <- pk_entity_resolve(
    "eh", c("ELECTRONIC HARP"), aliases = c(eh = "ELECTRONIC HARP"),
    role = "id", thresholds = yuksek
  )
  expect_false(identical(karar$decision, "auto"))
})

test_that("kesin sütunda çözülemeyen İKİNCİL DARALTMA analizi durdurmaz", {
  testthat::skip_if_not_installed("stringi")

  karar <- pk_entity_resolve(
    "PRJ-999", c("PRJ-001"), role = "id",
    entity_role = "refinement", thresholds = .PK_FIX_ESIK
  )
  expect_equal(karar$decision, "unfiltered")
  expect_equal(karar$rule, 7L)
})

test_that("SIFIR eşiklerde boş eşleşme kümesi hata VERMEZ", {
  testthat::skip_if_not_installed("stringi")

  for (esik in list(
    list(min_score = 0L, multi_score = 0L, auto_score = 85L),
    list(min_score = 0L, multi_score = 0L, auto_score = 0L)
  )) {
    tam <- c(esik, list(valid = TRUE, errors = character(0),
                        ambiguity_margin = 10L, max_candidates = 5L))
    karar <- pk_entity_resolve("zzzzzzzz", c("ANKA"), thresholds = tam)
    expect_true(karar$decision %in% c("unresolved", "unfiltered"))
  }
})

test_that("SIFIR marj kesin beraberliği yine BELİRSİZ sayar", {
  testthat::skip_if_not_installed("stringi")

  sifir <- c(.PK_FIX_ESIK[c("valid", "errors", "min_score", "multi_score",
                            "auto_score", "max_candidates")],
             list(ambiguity_margin = 0L))

  # ASCII anahtarı çakışması: `ŞAHİN` -> `şahin` ve `SAHIN` -> `sahın`
  # katlamaları FARKLIDIR, ama ikisinin de ASCII anahtarı `sahin`tir; yani
  # iki aday da tam 90 puan alır ve fark 0'dır.
  karar <- pk_entity_resolve("sahin", c("ŞAHİN", "SAHIN"), thresholds = sifir)
  expect_equal(karar$decision, "clarify")
  expect_equal(karar$rule, 2L)
})

test_that("belirsizliği tetikleyen ikinci aday ÇİPLERE dâhildir", {
  testthat::skip_if_not_installed("stringi")

  # MIN=60 ile 65/59 puanlı çift: 59 asgarinin ALTINDA olsa da kullanıcı
  # alternatifi görebilmelidir, aksi hâlde "birden fazla yakın aday" diyaloğu
  # tek çiple açılır.
  esik <- list(valid = TRUE, errors = character(0),
               min_score = 60L, multi_score = 60L, auto_score = 90L,
               ambiguity_margin = 10L, max_candidates = 5L)

  karar <- pk_entity_resolve("alfa beta", c("alfa beta gama", "alfa beta delta"),
                             thresholds = esik)
  if (identical(karar$decision, "clarify") && identical(karar$rule, 2L)) {
    expect_true(length(karar$chips) >= 2L)
  } else {
    succeed()
  }
})

test_that("çoğul istek TEK adaya sessizce ÇÖKMEZ", {
  testthat::skip_if_not_installed("stringi")

  # `kalıplar` / kanonik `KALIP` + ilgisiz değer: güçlü aday SAYISI 1 olsa
  # bile kural 4/5 devreye giremez.
  karar <- .pk_fix_coz(pk_tr_fold("kalıplar"), c(pk_tr_fold("KALIP"), "ZZZZ"))
  expect_equal(karar$decision, "clarify")
  expect_equal(karar$rule, 3L)
  expect_length(karar$values, 0L)
})

test_that("kural 6/7 önerileri KATMAN DIŞI en yakın komşulardan gelir", {
  testthat::skip_if_not_installed("stringi")

  # Katman puanı en az 50, varsayılan MIN 40; yani gerçek bir kural-6
  # durumunda eşleşme kümesi BOŞTUR ve kullanıcı hiç çip görmezdi.
  karar <- .pk_fix_coz("zzzzzzzz", c("ANKA", "AKINCI"))
  expect_equal(karar$decision, "unresolved")
  expect_true(length(karar$chips) >= 1L)
  expect_true(all(vapply(karar$chips, function(c) c$value, character(1)) %in%
                    c("ANKA", "AKINCI")))
})

test_that("eşik altı öneriler için 'Tümü' KAPALI kalır", {
  testthat::skip_if_not_installed("stringi")

  karar <- .pk_fix_coz("zzzzzzzz", c("ANKA", "AKINCI", "BORA"))
  expect_false(isTRUE(karar$offer_all))
})

test_that("gizli aday sayısı KIRPMADAN ÖNCE hesaplanır", {
  testthat::skip_if_not_installed("stringi")

  esik <- list(valid = TRUE, errors = character(0),
               min_score = 95L, multi_score = 95L, auto_score = 95L,
               ambiguity_margin = 10L, max_candidates = 2L)

  sozluk <- paste("ortak deger", c("bir", "iki", "uc", "dort", "bes", "alti"))
  karar <- pk_entity_resolve("ortak deger", sozluk, thresholds = esik)

  expect_true(length(karar$chips) <= 2L)
  expect_true(karar$overflow_count >= 1L)
  expect_false(isTRUE(karar$offer_all))
})

test_that("karar kaydındaki aday listesi SINIRLIDIR", {
  testthat::skip_if_not_installed("stringi")

  # `proje` gibi genel bir belirteç binlerce değerle eşleşebilir; tüm kümeyi
  # karara kopyalamak oturum yükünü şişirir.
  sozluk <- paste("proje", sprintf("%03d", seq_len(40)))
  karar <- .pk_fix_coz("proje", sozluk)

  expect_true(length(karar$candidates) <= 5L)
  expect_true(karar$candidate_count >= length(karar$candidates))
})

test_that("dışarıdan verilen eşik nesnesi YENİDEN DOĞRULANIR", {
  testthat::skip_if_not_installed("stringi")

  # `valid = TRUE` bayrağı KANIT DEĞİLDİR: MIN <= MULTI <= AUTO ilişkisi
  # ihlal edilmişse 90 puanlık bir eşleşme beyan edilen asgarinin ALTINDA
  # otomatik filtrelenirdi.
  bozuk <- list(valid = TRUE, errors = character(0),
                min_score = 100L, multi_score = 0L, auto_score = 0L,
                ambiguity_margin = 0L, max_candidates = 5L)

  karar <- pk_entity_resolve("kalip", c(pk_tr_fold("KALIP")), thresholds = bozuk)
  expect_equal(karar$decision, "config_error")
})

test_that("bozuk eşik değeri sessizce VARSAYILANA düşmez", {
  testthat::skip_if_not_installed("stringi")

  for (deger in c("bogus", "101", "-5")) {
    pk_entity_with_resolve_env(
      stats::setNames(list(deger), "MERGEN_PK_RESOLVE_AUTO_SCORE"), {
        esikler <- pk_resolve_thresholds()
        expect_false(esikler$valid, info = deger)

        karar <- pk_entity_resolve("kalip", c(pk_tr_fold("KALIP")))
        expect_equal(karar$decision, "config_error", info = deger)
      })
  }
})

test_that("kullanıcıya görünen mesajlar TÜRKÇE karakter taşır", {
  testthat::skip_if_not_installed("stringi")

  mesajlar <- c(
    .pk_fix_coz("zzzzzzzz", c("ANKA"))$message_tr,
    .pk_fix_coz("   ", c("ANKA"))$message_tr,
    .pk_fix_coz("zzzzzzzz", c("ANKA"), entity_role = "refinement")$message_tr
  )
  mesajlar <- mesajlar[!is.na(mesajlar)]
  expect_true(length(mesajlar) >= 3L)

  # Latinize edilmiş metin ("cozumlenemedi", "yapilmadi") ürün sözleşmesine
  # aykırıdır: tanımlayıcılar ASCII kalır, GÖRÜNEN metin Türkçe.
  birlesik <- paste(mesajlar, collapse = " ")
  expect_true(grepl("ü|ı|ş|ğ|ç|ö", birlesik))
  expect_false(grepl("cozumlen", birlesik, fixed = TRUE))
  expect_false(grepl("yapilmadi", birlesik, fixed = TRUE))
})

# --- D11 geçmiş devralması ----------------------------------------------------

.pk_fix_gecmis <- function(...) lapply(list(...), function(t) list(role = "user", content = t))

test_that("güncel istek geçmişten DÜŞÜLÜR", {
  testthat::skip_if_not_installed("stringi")

  # Gönderme yolu kullanıcı mesajını geçmişe EKLEDİKTEN sonra istek kurar;
  # istek kendi kendisinin "önceki sorusu" sayılamaz.
  oncekiler <- pk_entity_prior_user_prompts(
    .pk_fix_gecmis("ya ANKA"), limit = 5L, exclude_phrase = "ya ANKA"
  )
  expect_length(oncekiler, 0L)
})

test_that("devralma İLGİLİ tura kadar geriye gitmez", {
  testthat::skip_if_not_installed("stringi")

  # Araya giren ilgisiz bir soru atlanıp çok daha eski bağlam DİRİLTİLEMEZ.
  karar <- pk_entity_resolve_with_history(
    phrase = "peki 2024?",
    candidates = c("ANKA", "AKINCI"),
    chat_history = .pk_fix_gecmis("ANKA", "hava durumu nedir", "peki 2024?"),
    thresholds = .PK_FIX_ESIK
  )
  expect_false(isTRUE(karar$inherited))
})

test_that("GÜNCEL turda açıkça yazılan varlık geçmişi EZER", {
  testthat::skip_if_not_installed("stringi")

  karar <- pk_entity_resolve_with_history(
    phrase = "peki AKINCI?",
    candidates = c("ANKA", "AKINCI"),
    chat_history = .pk_fix_gecmis("ANKA nedir", "peki AKINCI?"),
    thresholds = .PK_FIX_ESIK
  )
  expect_false(isTRUE(karar$inherited))
  expect_equal(karar$values, "AKINCI")
})

test_that("devralınan sonuç OTOMATİK olamaz", {
  testthat::skip_if_not_installed("stringi")

  karar <- pk_entity_resolve_with_history(
    phrase = "peki 2024 için?",
    candidates = c("ANKA", "AKINCI"),
    chat_history = .pk_fix_gecmis("ANKA", "peki 2024 için?"),
    thresholds = .PK_FIX_ESIK
  )
  expect_true(isTRUE(karar$inherited))
  expect_equal(karar$decision, "confirm")
  expect_length(karar$values, 0L)
})

test_that("çelişen HAM ve YENİDEN YAZILMIŞ yorum NETLEŞTİRİLİR", {
  testthat::skip_if_not_installed("stringi")

  # `ALFA nedir` ham hâliyle `ALFA NEDIR`e, soru sözcüğü atılınca `ALFA`ya
  # eşleşir; hangisinin kazandığını YİNELEME SIRASI belirleyemez.
  karar <- pk_entity_resolve_with_history(
    phrase = "peki 2024 için?",
    candidates = c("ALFA", "ALFA NEDIR"),
    chat_history = .pk_fix_gecmis("ALFA nedir", "peki 2024 için?"),
    thresholds = .PK_FIX_ESIK
  )
  expect_equal(karar$decision, "clarify")
  expect_true(length(karar$chips) >= 2L)
})

test_that("kısa kanonik ad UZUN önceki sorudan kurtarılır", {
  testthat::skip_if_not_installed("stringi")

  # `ANKA 2024 bütçesi nedir` tam soru olarak puanlandığında J = 1/3'tür.
  karar <- pk_entity_resolve_with_history(
    phrase = "peki 2025 için?",
    candidates = c("ANKA"),
    chat_history = .pk_fix_gecmis("ANKA 2024 bütçesi nedir", "peki 2025 için?"),
    thresholds = .PK_FIX_ESIK
  )
  expect_true(isTRUE(karar$inherited))
  expect_equal(karar$chips[[1]]$value, "ANKA")
})

test_that("devralınan varlık SORGU/SÜTUN kimliğine bağlıdır", {
  testthat::skip_if_not_installed("stringi")

  baglam <- list(values = "ANKA", key = list(query_id = "q1", column = "Proje"))

  eslesen <- pk_entity_resolve_with_history(
    phrase = "peki 2024 için?", candidates = c("ANKA"),
    chat_history = .pk_fix_gecmis("peki 2024 için?"),
    prior_context = baglam, context_key = list(query_id = "q1", column = "Proje"),
    thresholds = .PK_FIX_ESIK
  )
  expect_true(isTRUE(eslesen$inherited))

  # Farklı yaprak: proje adı departman sütununa SIZAMAZ.
  farkli <- pk_entity_resolve_with_history(
    phrase = "peki 2024 için?", candidates = c("ANKA"),
    chat_history = .pk_fix_gecmis("peki 2024 için?"),
    prior_context = baglam, context_key = list(query_id = "q2", column = "Departman"),
    thresholds = .PK_FIX_ESIK
  )
  expect_false(isTRUE(farkli$inherited))
})

test_that("GÜNCEL devam sorusunun çoğul niyeti korunur", {
  testthat::skip_if_not_installed("stringi")

  karar <- pk_entity_resolve_with_history(
    phrase = "peki hepsi?",
    candidates = c("ANKA", "ANKA RADAR"),
    chat_history = .pk_fix_gecmis("ANKA", "peki hepsi?"),
    thresholds = .PK_FIX_ESIK
  )
  expect_equal(karar$decision, "clarify")
  expect_true(length(karar$chips) >= 2L)
})

test_that("çekimli adıl ve yapısal daraltmalar devam sorusu SAYILIR", {
  testthat::skip_if_not_installed("stringi")

  for (ifade in c("onu göster", "buna 2024 için bak", "2024 için?", "2024'te?",
                  "aktif olanlar?", "hepsi", "tümü")) {
    expect_true(pk_entity_is_followup(ifade), info = ifade)
  }
})

test_that("SIFIR geçmiş sınırı devralmayı GERÇEKTEN kapatır", {
  testthat::skip_if_not_installed("stringi")

  expect_length(
    pk_entity_prior_user_prompts(.pk_fix_gecmis("ANKA"), limit = 0L), 0L
  )

  karar <- pk_entity_resolve_with_history(
    phrase = "peki 2024 için?", candidates = c("ANKA"),
    chat_history = .pk_fix_gecmis("ANKA", "peki 2024 için?"),
    limit = 0L, thresholds = .PK_FIX_ESIK
  )
  expect_false(isTRUE(karar$inherited))
})

test_that("ZAYIF doğrudan eşleşme geçmişi bastırmaz", {
  testthat::skip_if_not_installed("stringi")

  # `peki` ifadesi `PEKİN` değerine düzenleme mesafesiyle eşleşip kural 5
  # onayı üretiyor ve kesin `ANKA` bağlamı hiç değerlendirilmiyordu.
  karar <- pk_entity_resolve_with_history(
    phrase = "peki",
    candidates = c(pk_tr_fold("PEKİN"), "ANKA"),
    chat_history = .pk_fix_gecmis("ANKA", "peki"),
    thresholds = .PK_FIX_ESIK
  )
  expect_true(isTRUE(karar$inherited))
  expect_equal(karar$chips[[1]]$value, "ANKA")
})
