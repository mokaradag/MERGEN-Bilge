# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-query-retrieval-behavior.R
# Açıklama: Faz 5 (§5.2) — sözlüksel getirim (karakter 3-gram + IDF kosinüs).
#           Tamamen çevrimdışı ve belirlenimcidir: DB, LLM, tarayıcı, SSO, ağ
#           veya gizli değer GEREKMEZ.
#
# Kapsanan sözleşmeler:
#   - Türkçe sondan eklemeli biçimler ortak 3-gram paylaşır (gövdeleyici YOK).
#   - IDF, kütüphane genelinde sık geçen kelimelerin skoru domine etmesini
#     engeller.
#   - Skor MUTLAK kosinüstür; max'a göre %100 normalize EDİLMEZ (D10).
#   - Sabit `grepl` alan bonusu YOKTUR (D10).
#   - Belirteçleme YERELDEN BAĞIMSIZDIR (ölçülmüş kusur: PCRE POSIX sınıfları
#     ASCII'dir ve Türkçe kelimeleri parçalar).
#   - Katman KARAR VERMEZ: yalnızca sıralama/uyuşmazlık sinyali üretir.
# ==============================================================================

pk_select_source_chain_for_tests()

.pk_ret_lib <- function() pk_select_test_library()

test_that("Türkçe çekim ekleri ortak 3-gram paylaşır (gövdeleyici gerekmez)", {
  taban <- pk_retrieval_trigrams("proje")
  for (bicim in c("projelerin", "projeye", "projedeki", "projelerinde")) {
    ortak <- intersect(taban, pk_retrieval_trigrams(bicim))
    expect_true(
      all(c("pro", "roj", "oje") %in% ortak),
      info = sprintf("'%s' biçimi 'proje' ile pro/roj/oje üçlülerini paylaşmalıdır.", bicim)
    )
  }
})

test_that("belirteçleme Türkçe harfleri PARÇALAMAZ (ölçülmüş PCRE kusuru)", {
  # Kaynak dosya ayrıştırma etkisini dışlamak için kod noktalarından kurulur:
  # i s-cedilla c-cedilla i l i k
  kelime <- intToUtf8(c(0x69, 0x15F, 0xE7, 0x69, 0x6C, 0x69, 0x6B))

  belirtecler <- .pk_retrieval_tokens(kelime)
  expect_equal(
    length(belirtecler), 1L,
    info = paste(
      "Türkçe kelime TEK belirteç olmalıdır.",
      "`strsplit(..., '[^[:alnum:]]+', perl = TRUE)` bu konteynerde",
      "'işçilik' -> 'i' + 'ilik' şeklinde parçalıyordu; ICU sınıfları",
      "(\\p{L}/\\p{N}) yerelden bağımsız doğru sonucu verir."
    )
  )
  expect_identical(belirtecler[1], kelime)

  # Parçalanma olsaydı 3-gram sayısı düşerdi; sayı ÖLÇÜLÜ olarak sabitlenir.
  expect_equal(length(pk_retrieval_trigrams(kelime)), 7L)
})

test_that("IDF sık geçen kelimenin skoru domine etmesini engeller", {
  # `sentetik` kütüphanenin TAMAMINDA geçer -> düşük IDF.
  # `takvim` yalnızca q003'te geçer -> yüksek IDF.
  index <- pk_retrieval_build_index(.pk_ret_lib())

  # `[[` EKSİK ADDA HATA YÜKSELTİR ("subscript out of bounds") ve aşağıdaki
  # `expect_true()` HİÇ çalışmazdı; tokenleştirici/indeks değişikliği bu
  # 3-gramlardan birini düşürürse anlamlı tanı yerine opak bir hata görülürdü.
  # Tek köşeli parantez eksik adda `NA` döner ve tanı iddiası ÇALIŞIR.
  idf_sentetik <- unname(index$idf["sen"])
  idf_takvim <- unname(index$idf["tak"])

  expect_true(
    is.finite(idf_sentetik) && is.finite(idf_takvim),
    info = "Her iki 3-gram da indekste bulunmalıdır."
  )
  expect_gt(idf_takvim, idf_sentetik)

  # Ayırt edici terim, jenerik terimden daha güçlü sıralama üretir.
  jenerik <- pk_retrieval_score(index, "sentetik")
  ayirtedici <- pk_retrieval_score(index, "takvim")
  expect_identical(ayirtedici$query_id[1], "q003")
  expect_gt(ayirtedici$score[1], jenerik$score[1])
})

test_that("skor MUTLAK kosinüstür; max'a göre %100 normalize EDİLMEZ (D10)", {
  index <- pk_retrieval_build_index(.pk_ret_lib())

  # v1 sezgiselinde en iyi aday HER ZAMAN 100 idi. Burada alakasız bir soru
  # düşük kalır ve hiçbir skor 1'e sabitlenmez.
  alakasiz <- pk_retrieval_score(index, "hava durumu nasil olacak")
  expect_lt(max(alakasiz$score), 0.5)

  alakali <- pk_retrieval_score(index, "sentetik kaynak atama listesi")
  expect_identical(alakali$query_id[1], "q002")
  # Tam olmayan bir eşleşme 1.0'a normalize EDİLMEMELİDİR.
  expect_lt(alakali$score[1], 1.0)

  # Tüm skorlar 0 olduğunda hiçbiri yapay olarak yükseltilmez.
  bos <- pk_retrieval_score(index, "zzzz")
  expect_true(all(bos$score == 0))
})

test_that("skorlama TÜM kütüphaneyi döndürür ve deterministik sıralanır", {
  index <- pk_retrieval_build_index(.pk_ret_lib())
  siralama <- pk_retrieval_score(index, "sentetik bütçe")

  expect_setequal(siralama$query_id, c("q001", "q002", "q003", "q004"))
  expect_true(all(diff(siralama$score) <= 0), info = "Azalan skor sırası bozulmamalıdır.")

  # Girdi sırası değişse de çıktı sırası AYNI olmalıdır (E8: radix, C-yerel).
  ters <- pk_retrieval_build_index(rev(.pk_ret_lib()))
  expect_identical(
    pk_retrieval_score(ters, "sentetik bütçe")$query_id,
    siralama$query_id
  )
})

test_that("belge metni ad/açıklama/anahtar kelime/örnek soru/sütun etiketini kapsar", {
  lib <- .pk_ret_lib()
  metin <- pk_retrieval_document_text(lib[[2]])

  expect_true(grepl("Sentetik Kaynak Atama Listesi", metin, fixed = TRUE))
  expect_true(grepl("kaynak", metin, fixed = TRUE))
  expect_true(grepl("kimler görevliydi", metin, fixed = TRUE))
  expect_true(
    grepl("Kalan İşçilik", metin, fixed = TRUE),
    info = "Sütun ETİKETİ dâhil olmalıdır: kullanıcı etiketi kullanır, sütun adını değil."
  )
  expect_false(
    grepl("KalanIscilik_sa", metin, fixed = TRUE),
    info = "Sütun ADI teknik tanımlayıcıdır; 3-gram gürültüsü yaratır."
  )
})

test_that("ayırt edici terim YALNIZCA örnek soruda olsa bile getirilebilir", {
  index <- pk_retrieval_build_index(.pk_ret_lib())

  # "ertelendi" ne isimde ne açıklamada ne de anahtar kelimelerde vardır;
  # yalnızca q003'ün sample_questions alanında geçer.
  siralama <- pk_retrieval_score(index, "hangi isler ertelendi")
  expect_identical(siralama$query_id[1], "q003")
  expect_gt(siralama$score[1], 0)
})

test_that("kararlı kimliği olmayan sorgu indekse KONUM kimliğiyle girmez (D13)", {
  lib <- list(
    list(id = "q001", name = "Var", description = "kararli kimlik"),
    list(name = "Kimliksiz", description = "kimligi yok")
  )
  index <- pk_retrieval_build_index(lib)

  expect_identical(index$ids, "q001")
  expect_equal(index$n, 1L)
  expect_false(
    any(c("1", "2") %in% index$ids),
    info = "Liste konumu kimlik olarak UYDURULMAMALIDIR."
  )
})

test_that("boş/bozuk girdiler çökmeden boş sonuç verir", {
  expect_equal(pk_retrieval_build_index(list())$n, 0L)
  expect_equal(nrow(pk_retrieval_score(pk_retrieval_build_index(list()), "x")), 0L)
  expect_equal(length(pk_retrieval_trigrams("")), 0L)
  expect_equal(length(pk_retrieval_trigrams(NULL)), 0L)
  # NA, "NA" METNİNE çevrilip sahte `na` belirteci üretmemelidir: eksik alan
  # içerik değil YOKLUK demektir (ölçülerek bulundu).
  expect_equal(length(.pk_retrieval_tokens(NA_character_)), 0L)
  expect_equal(length(pk_retrieval_trigrams(NA_character_)), 0L)
  expect_equal(length(.pk_retrieval_tokens(c(NA_character_, "proje"))), 1L)
})

test_that("uyuşmazlık sinyali KARAR DEĞİL, yalnızca sıra/bayrak üretir", {
  index <- pk_retrieval_build_index(.pk_ret_lib())

  # Sözlüksel olarak açık ara birinci olan sorgu seçildiyse uyuşmazlık yoktur.
  uyum <- pk_retrieval_agreement(index, "sentetik kaynak atama listesi", "q002", 2L)
  expect_true(uyum$available)
  expect_equal(uyum$rank, 1L)
  expect_false(uyum$disagrees)

  # Sözlüksel olarak çok gerideki bir sorgu seçildiyse uyuşmazlık raporlanır.
  uyumsuz <- pk_retrieval_agreement(index, "sentetik kaynak atama listesi", "q004", 1L)
  expect_true(uyumsuz$disagrees)
  expect_gt(uyumsuz$rank, 1L)

  # Dönen nesne yalnızca SİNYALDİR; hiçbir "seç/çalıştır" alanı taşımaz.
  # `excluded_by_not_for` de bir sinyaldir ve artık HER yolda döner: alanı
  # yalnızca dışlama dalında yazmak, `agreement$excluded_by_not_for` okuyan bir
  # tüketiciye diğer yollarda `NULL` verir ve `if (NULL)` HATA fırlatırdı.
  expect_setequal(names(uyum),
                  c("available", "rank", "score", "disagrees", "excluded_by_not_for"))
  expect_false(uyum$excluded_by_not_for)
  expect_false(uyumsuz$excluded_by_not_for)
})

test_that("seçilen sorgunun KENDİ `not_for` kaydı da bağlayıcıdır", {
  # `not_for` "bu istek bu sorguya UYGUN DEĞİL" diyen AÇIK olumsuz kanıttır.
  # Eski `setdiff(..., kimlik)` seçileni dışlama kümesinden çıkarıyordu; yani
  # sorgu tam da bu isteği reddetse bile kapı "uyuşmazlık yok" diyebiliyordu.
  lib <- .pk_ret_lib()
  lib[[2]]$meta$not_for <- "kaynak atama"

  index <- pk_retrieval_build_index(lib)
  istem <- "sentetik kaynak atama listesi"

  # Ölçüm: kütüphane VERİLMEZSE q002 sözlüksel BİRİNCİDİR ve uyuşmazlık yoktur.
  # Bu, aşağıdaki iddianın boş olmadığını (dışlama kapısının gerçekten iş
  # yaptığını) kanıtlar.
  kutuphanesiz <- pk_retrieval_agreement(index, istem, "q002", 2L)
  expect_equal(kutuphanesiz$rank, 1L)
  expect_false(kutuphanesiz$disagrees)

  dislandi <- pk_retrieval_agreement(index, istem, "q002", 2L, library = lib)
  expect_true(dislandi$available)
  expect_true(dislandi$disagrees)
  expect_true(isTRUE(dislandi$excluded_by_not_for))

  # Dışlama SIRALAMA İDDİASI DEĞİLDİR: sıra/skor bilinçli olarak yoktur, aksi
  # hâlde politika "birinciydi ama uyuşmuyor" gibi çelişkili bir sinyal görür.
  expect_true(is.na(dislandi$rank))
  expect_true(is.na(dislandi$score))
})

test_that("sözlüksel sinyal tamamen boşken uyuşmazlık İDDİA EDİLMEZ", {
  index <- pk_retrieval_build_index(.pk_ret_lib())

  # Hiçbir 3-gram eşleşmiyorsa tüm skorlar 0'dır; bu durumda "bu seçim
  # şüpheli" demek metadata'sı olmayan bir kütüphanede her seçimi cezalandırır.
  uyum <- pk_retrieval_agreement(index, "zzzz qqqq", "q001", 1L)
  expect_false(uyum$disagrees)
  expect_false(uyum$available)
})

test_that("getirim katmanı SABİT alan bonusu ve eşik İÇERMEZ (D10)", {
  yol <- file.path(resolve_repo_root_for_tests(), "R", "helpers_pk_query_retrieval.R")
  ham <- readBin(yol, "raw", file.info(yol)$size)
  txt <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")

  # v1'in yedi alan bonusu buraya TAŞINMAMALIDIR.
  for (desen in c("score + 8", "score <- score +", "THRESHOLD_RAW", "THRESHOLD_PCT")) {
    expect_false(
      grepl(desen, txt, fixed = TRUE, useBytes = TRUE),
      info = sprintf("Sözlüksel katman v1 sezgisel kalıbını içermemelidir: %s", desen)
    )
  }

  # max'a göre normalizasyon kalıbı da taşınmamalıdır.
  expect_false(
    grepl("max_heuristic", txt, fixed = TRUE, useBytes = TRUE),
    info = "max'a göre %100 normalizasyon (D10) yeniden getirilmemelidir."
  )

  # Katman karar/çalıştırma fonksiyonu çağırmamalıdır.
  for (desen in c("call_local_llm", "pk_select_decide", "pk_engine_is_v2")) {
    expect_false(
      grepl(desen, txt, fixed = TRUE, useBytes = TRUE),
      info = sprintf("Sözlüksel katman saf kalmalıdır: %s bulundu.", desen)
    )
  }
})
