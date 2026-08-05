# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-entity-resolver-contract.R
# Açıklama: Faz 4 karar politikası sözleşme testleri (master plan §5.4).
#           Tamamen çevrimdışı ve belirlenimcidir: DB, LLM, tarayıcı, SSO, ağ
#           veya gizli değer GEREKMEZ.
#
# Kapsanan sözleşmeler:
#   - Kurallar SIRAYLA değerlendirilir (2 -> 3 -> 4); sıra güvenlik
#     mekanizmasıdır, puanlar değil.
#   - Her dal ÇÖZÜLMÜŞ yapılandırmayı okur; testler eşikleri EZER ve
#     politikanın hâlâ eksiksiz olduğunu kanıtlar.
#   - Geçersiz eşik ilişkisi çözümlemeden ÖNCE kapalı başarısız olur.
#   - Taşma adayları "Tümü" arkasına SAKLAYAMAZ.
#   - Kodlar ASLA bulanıklaştırılmaz.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()
  for (dosya in c("helpers_pk_config.R", "helpers_pk_text_turkish.R",
                  "helpers_pk_entity_normalize.R", "helpers_pk_entity_score.R",
                  "helpers_pk_entity_resolver.R")) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = globalenv())
  }
})

# Eşikleri ortam değişkeniyle ezip geri alan yardımcı. Testler ASLA gerçek
# `.Renviron` değerlerine bağlı kalmaz.
.pk_res_with_env <- function(vars, code) {
  eski <- Sys.getenv(names(vars), unset = NA_character_, names = TRUE)
  do.call(Sys.setenv, as.list(vars))
  on.exit({
    for (ad in names(eski)) {
      if (is.na(eski[[ad]])) Sys.unsetenv(ad) else do.call(Sys.setenv, setNames(list(eski[[ad]]), ad))
    }
  }, add = TRUE)
  force(code)
}

test_that("varsayılan eşikler §9 tablosuyla aynıdır ve geçerlidir", {
  esikler <- pk_resolve_thresholds()

  expect_true(esikler$valid)
  expect_equal(esikler$min_score, 40L)
  expect_equal(esikler$multi_score, 70L)
  expect_equal(esikler$auto_score, 85L)
  expect_equal(esikler$ambiguity_margin, 10L)
  expect_equal(esikler$max_candidates, 5L)
})

test_that("MIN=90 / AUTO=85 ilişkisi KAPALI BAŞARISIZ olur", {
  testthat::skip_if_not_installed("stringi")

  # Planın açıkça istediği sözleşme testi. Her iki değer TEK BAŞINA geçerlidir
  # (0..100), bu yüzden anahtar bazlı doğrulama bunu yakalayamaz; yakalayan
  # şey ilişki denetimidir.
  .pk_res_with_env(c(
    MERGEN_PK_RESOLVE_MIN_SCORE = "90",
    MERGEN_PK_RESOLVE_AUTO_SCORE = "85"
  ), {
    esikler <- pk_resolve_thresholds()
    expect_false(esikler$valid)
    expect_true(any(grepl("MIN_SCORE", esikler$errors, fixed = TRUE)))

    # Çözümleme kısmen sıralı dalları DEĞERLENDİRMEZ; tamamen devre dışı kalır.
    karar <- pk_entity_resolve("ANKA", c("ANKA"))
    expect_equal(karar$decision, "config_error")
    expect_equal(length(karar$values), 0L)
    expect_true(grepl("devre disi", karar$message_tr, fixed = TRUE))
  })
})

test_that("eşik altındaki hiçbir aday otomatik kabul EDİLEMEZ", {
  testthat::skip_if_not_installed("stringi")

  # Geçerli ama YÜKSEK eşikler: MIN = MULTI = AUTO = 95.
  .pk_res_with_env(c(
    MERGEN_PK_RESOLVE_MIN_SCORE = "95",
    MERGEN_PK_RESOLVE_MULTI_SCORE = "95",
    MERGEN_PK_RESOLVE_AUTO_SCORE = "95"
  ), {
    expect_true(pk_resolve_thresholds()$valid)

    # ASCII anahtarı 90 puandır; 95 eşiğinin ALTINDA kalır.
    karar <- pk_entity_resolve("kalip", c("KALIP"))
    expect_false(identical(karar$decision, "auto"))
    expect_equal(karar$top_score, 90L)
    expect_equal(karar$decision, "unresolved")
    expect_equal(karar$rule, 6L)
  })
})

test_that("kural 4: tekil, yüksek puanlı, net farklı aday otomatik filtrelenir", {
  testthat::skip_if_not_installed("stringi")

  karar <- pk_entity_resolve("ANKA", c("ANKA", "ZZZZ FARKLI DEGER"))

  expect_equal(karar$decision, "auto")
  expect_equal(karar$rule, 4L)
  expect_equal(karar$values, "ANKA")
})

test_that("kural 2 kural 4'ten ÖNCE gelir: 88/85 birleşmez, netleştirir", {
  testthat::skip_if_not_installed("stringi")

  # Planın açık örneği: iki aday 88 ve 85 puan alırsa otomatik BİRLEŞİM
  # yerine netleştirme yapılmalıdır (fark 3 < 10).
  esikler <- list(
    valid = TRUE, errors = character(0),
    min_score = 40L, multi_score = 70L, auto_score = 85L,
    ambiguity_margin = 10L, max_candidates = 5L
  )

  # "alfa" iki adayda da geçer; belirteç sayıları farklı olduğu için puanlar
  # 89 ve 85 çıkar (fark 4 < 10).
  karar <- pk_entity_resolve(
    "alfa",
    c("alfa", "alfa beta gama delta epsilon"),
    thresholds = esikler
  )

  # Not: "alfa" ilk adayla KESİN eşleşir (100). Bu yüzden gerçek 88/85
  # senaryosu için kesin eşleşmeyen bir sözlük gerekir.
  expect_equal(karar$decision, "auto")

  # Şimdi kesin eşleşme OLMAYAN, birbirine yakın iki aday:
  yakin <- pk_entity_resolve(
    "alfa beta",
    c("alfa beta gama", "alfa beta delta"),
    thresholds = esikler
  )
  expect_equal(yakin$decision, "clarify")
  expect_equal(yakin$rule, 2L)
  expect_equal(length(yakin$values), 0L)
  expect_true(length(yakin$chips) >= 2L)
})

test_that("kural 3 kural 4'ten ÖNCE gelir: çoğul istek 92'ye ÇÖKMEZ", {
  testthat::skip_if_not_installed("stringi")

  # Planın açık örneği: 92 / 81 / 76 puanlı çoğul bir istek, 92 otomatik
  # eşiği geçtiği için sessizce tek adaya çökemez.
  esikler <- list(
    valid = TRUE, errors = character(0),
    min_score = 40L, multi_score = 70L, auto_score = 85L,
    ambiguity_margin = 10L, max_candidates = 5L
  )

  # Puanlar 100 ve 87: fark 13 >= 10 olduğu için kural 2 DEVREYE GİRMEZ.
  # Tepe puan 100 >= AUTO 85 olduğundan, kural 3 kural 4'ten önce
  # denenmeseydi bu istek sessizce "hatlar projesi" adayına ÇÖKERDİ. Testin
  # yakaladığı regresyon tam olarak budur.
  sozluk <- c("hatlar projesi", "alfa beta hatlar projesi")

  karar <- pk_entity_resolve("hatlar projesi", sozluk, thresholds = esikler)

  expect_true(isTRUE(karar$plural))
  expect_equal(karar$top_score, 100L)
  expect_true(karar$margin >= esikler$ambiguity_margin)  # kural 2 elenmiştir
  expect_equal(karar$decision, "clarify")
  expect_equal(karar$rule, 3L)
  # Hiçbir değer OTOMATİK uygulanmaz.
  expect_equal(length(karar$values), 0L)
  expect_true(length(karar$chips) >= 2L)

  # Aynı ifade TEKİL bir sözlükte otomatik kabul edilir; farkı yaratan şey
  # çoğulluk sinyalidir, puan değil.
  tekil <- pk_entity_resolve("hatlar projesi", "hatlar projesi", thresholds = esikler)
  expect_equal(tekil$decision, "auto")
  expect_equal(tekil$rule, 4L)
})

test_that("kural 2 EŞİT adaylarda kural 3'ten önce gelir", {
  testthat::skip_if_not_installed("stringi")

  # Üç aday da AYNI puanı alırsa (fark 0 < 10) belirsizlik kuralı önce
  # devreye girer. Bu, kural sırasının diğer yönünü kanıtlar: çoğulluk
  # sinyali belirsizliği EZMEZ.
  sozluk <- c("alfa hatlar projesi", "beta hatlar projesi", "gama hatlar projesi")
  karar <- pk_entity_resolve("hatlar projesi", sozluk)

  expect_true(isTRUE(karar$plural))
  expect_equal(karar$margin, 0L)
  expect_equal(karar$decision, "clarify")
  expect_equal(karar$rule, 2L)
  expect_equal(length(karar$values), 0L)
})

test_that("kural 5: MIN <= tepe < AUTO ön seçimli ONAY ister, otomatik filtrelemez", {
  testthat::skip_if_not_installed("stringi")

  esikler <- list(
    valid = TRUE, errors = character(0),
    min_score = 40L, multi_score = 70L, auto_score = 85L,
    ambiguity_margin = 10L, max_candidates = 5L
  )

  # Katman 5 puanı (60) MIN ile AUTO arasındadır ve tek adaydır.
  karar <- pk_entity_resolve(
    "aaaa bbbb cccc xxxx",
    c("aaaa bbbb cccc yyyy"),
    thresholds = esikler
  )

  expect_equal(karar$top_score, 60L)
  expect_equal(karar$decision, "confirm")
  expect_equal(karar$rule, 5L)
  expect_equal(length(karar$values), 0L)

  # Tek çip ÖN SEÇİLİ gelir.
  expect_equal(length(karar$chips), 1L)
  expect_true(isTRUE(karar$chips[[1]]$preselected))
  expect_true(grepl("kastettiniz", karar$message_tr, fixed = TRUE))
})

test_that("kural 6: özne çözümlenemezse ANALİZ YAPILMAZ", {
  testthat::skip_if_not_installed("stringi")

  karar <- pk_entity_resolve("qqqqqqqqqq", c("wwwwwwwwww"), entity_role = "subject")

  expect_equal(karar$decision, "unresolved")
  expect_equal(karar$rule, 6L)
  expect_equal(length(karar$values), 0L)
  expect_true(grepl("analiz", karar$message_tr, fixed = TRUE))
})

test_that("kural 7: ikincil daraltma çözümlenemezse FİLTRESİZ sürer + açık uyarı", {
  testthat::skip_if_not_installed("stringi")

  karar <- pk_entity_resolve("qqqqqqqqqq", c("wwwwwwwwww"), entity_role = "refinement")

  expect_equal(karar$decision, "unfiltered")
  expect_equal(karar$rule, 7L)
  expect_true(isTRUE(karar$disclose))
  expect_true(grepl("UYGULANMADAN", karar$message_tr, fixed = TRUE))
})

test_that("kural 1: kod/kimlik sütunu ASLA bulanıklaştırılmaz", {
  testthat::skip_if_not_installed("stringi")

  kodlar <- c("PRJ-001", "PRJ-002", "PRJ-010")

  # Kesin eşleşme otomatik uygulanır.
  kesin <- pk_entity_resolve("PRJ-001", kodlar, role = "id")
  expect_equal(kesin$decision, "auto")
  expect_equal(kesin$rule, 1L)
  expect_equal(kesin$values, "PRJ-001")

  # Yakın ama kesin OLMAYAN kod bulanıklaştırılmaz.
  yakin <- pk_entity_resolve("PRJ-01", kodlar, role = "id")
  expect_equal(yakin$decision, "unresolved")
  expect_equal(length(yakin$values), 0L)

  # match = "exact" de aynı korumayı verir.
  expect_equal(
    pk_entity_resolve("PRJ-01", kodlar, match_mode = "exact")$decision,
    "unresolved"
  )

  # Aynı sözlük `resolve` kipinde bulanıklaşır — koruma role/match'e BAĞLIDIR.
  expect_true(pk_entity_resolve("PRJ-01", kodlar)$top_score > 0L)
})

test_that("belirsiz ASCII çakışması TAHMİN değil netleştirme üretir", {
  testthat::skip_if_not_installed("stringi")

  karar <- pk_entity_resolve("isci", c("İŞÇİ", "IŞÇI"))

  expect_equal(karar$decision, "clarify")
  expect_equal(karar$rule, 2L)
  expect_equal(karar$top_score, 90L)
  expect_equal(length(karar$values), 0L)
  expect_equal(length(karar$chips), 2L)
  expect_true(isTRUE(karar$offer_all))
})

test_that("taşma: tam olarak 2, tam sınır ve sınır+1 aday", {
  testthat::skip_if_not_installed("stringi")

  esikler_ile <- function(max_cand) {
    list(
      valid = TRUE, errors = character(0),
      min_score = 40L, multi_score = 70L, auto_score = 85L,
      ambiguity_margin = 10L, max_candidates = as.integer(max_cand)
    )
  }

  # Hepsi AYNI puanı alan (dolayısıyla eşit) adaylar üretir.
  sozluk_uret <- function(n) sprintf("ortak deger %s", letters[seq_len(n)])

  # --- tam olarak 2 aday: hepsi görünür, "Tümü" SUNULUR ---
  iki <- pk_entity_resolve("ortak deger", sozluk_uret(2), thresholds = esikler_ile(5))
  expect_equal(iki$decision, "clarify")
  expect_equal(iki$total_strong, 2L)
  expect_equal(length(iki$chips), 2L)
  expect_equal(iki$overflow_count, 0L)
  expect_true(isTRUE(iki$offer_all))

  # --- tam sınır kadar aday: hepsi görünür, "Tümü" hâlâ SUNULUR ---
  tam <- pk_entity_resolve("ortak deger", sozluk_uret(5), thresholds = esikler_ile(5))
  expect_equal(tam$total_strong, 5L)
  expect_equal(length(tam$chips), 5L)
  expect_equal(tam$overflow_count, 0L)
  expect_true(isTRUE(tam$offer_all))

  # --- sınır + 1: TAŞMA açıkça bildirilir, "Tümü" KAPATILIR ---
  tasma <- pk_entity_resolve("ortak deger", sozluk_uret(6), thresholds = esikler_ile(5))
  expect_equal(tasma$total_strong, 6L)
  expect_equal(length(tasma$chips), 5L)
  expect_equal(tasma$overflow_count, 1L)
  expect_false(isTRUE(tasma$offer_all))
  expect_true(grepl("aday daha var", tasma$overflow_note, fixed = TRUE))

  # Hiçbir taşma durumunda değer UYGULANMAZ.
  expect_equal(length(tasma$values), 0L)
})

test_that("taşma çipleri gizli adayları ASLA içermez", {
  testthat::skip_if_not_installed("stringi")

  esikler <- list(
    valid = TRUE, errors = character(0),
    min_score = 40L, multi_score = 70L, auto_score = 85L,
    ambiguity_margin = 10L, max_candidates = 2L
  )

  sozluk <- sprintf("ortak deger %s", letters[seq_len(5)])
  karar <- pk_entity_resolve("ortak deger", sozluk, thresholds = esikler)

  cip_degerleri <- vapply(karar$chips, function(c) c$value, character(1))
  expect_equal(length(cip_degerleri), 2L)
  expect_equal(karar$overflow_count, 3L)
  expect_false(isTRUE(karar$offer_all))

  # "Tümü" kapalı olduğu için görünmeyen 3 aday hiçbir yoldan seçilemez.
  expect_true(all(cip_degerleri %in% sozluk))
})

test_that("boş ifade GEÇERSİZ GİRDİDİR, çözümlenemedi değil", {
  testthat::skip_if_not_installed("stringi")

  karar <- pk_entity_resolve("   ", c("ANKA"))
  expect_equal(karar$decision, "invalid_input")
  expect_equal(length(karar$values), 0L)

  bos_sozluk <- pk_entity_resolve("ANKA", character(0))
  expect_equal(bos_sozluk$decision, "invalid_input")
})

test_that("karar kaydı her dalda AYNI alan setini taşır", {
  testthat::skip_if_not_installed("stringi")

  zorunlu <- c("decision", "rule", "values", "message_tr", "candidates",
               "top_score", "chips", "offer_all", "overflow_count",
               "total_strong", "thresholds", "inherited")

  kararlar <- list(
    pk_entity_resolve("ANKA", c("ANKA")),
    pk_entity_resolve("isci", c("İŞÇİ", "IŞÇI")),
    pk_entity_resolve("qqqqqqqqqq", c("wwwwwwwwww")),
    pk_entity_resolve("   ", c("ANKA"))
  )

  for (karar in kararlar) {
    expect_true(all(zorunlu %in% names(karar)),
                info = sprintf("Eksik alan: %s", karar$decision))
  }
})

# --- Yapısal sözleşmeler ------------------------------------------------------
# Windows/VM güvenli bayt okuma (CLAUDE.md kuralı): bu depoda bazı kaynak
# dosyalar Türkçe yorum taşır ve düz `readLines(encoding = "UTF-8")` VM'de
# geçersiz UTF-8 uyarısı üretebilir.
.pk_res_read <- function(path) {
  ham <- readBin(path, "raw", file.info(path)$size)
  iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")
}

.PK_RES_DOSYALAR <- c(
  "helpers_pk_entity_normalize.R",
  "helpers_pk_entity_score.R",
  "helpers_pk_entity_resolver.R",
  "helpers_pk_entity_history.R"
)

test_that("Faz 4 dosyaları SAFTIR: Shiny/reactive/DB/ağ bağımlılığı yoktur", {
  repo_root <- resolve_repo_root_for_tests()

  yasak <- c(
    "shiny::", "session$", "reactiveVal", "reactiveValues", "observeEvent",
    "DBI::", "dbGetQuery", "dbConnect", "httr::", "curl::",
    "tracked_future_promise", "future::"
  )

  for (dosya in .PK_RES_DOSYALAR) {
    yol <- file.path(repo_root, "R", dosya)
    expect_true(file.exists(yol), info = dosya)

    # Yorum satırları çıkarılır: açıklayıcı metin yanlış pozitif üretmemelidir.
    satirlar <- strsplit(.pk_res_read(yol), "\n", fixed = TRUE)[[1]]
    kod <- satirlar[!grepl("^\\s*#", satirlar)]
    govde <- paste(kod, collapse = "\n")

    for (token in yasak) {
      expect_false(
        grepl(token, govde, fixed = TRUE, useBytes = TRUE),
        info = sprintf("%s icinde yasak bagimlilik: %s", dosya, token)
      )
    }
  }
})

test_that("Faz 4 dosyaları motor bayrağını OKUMAZ", {
  repo_root <- resolve_repo_root_for_tests()

  # Motor sınırı sözleşmesi: v1/v2 dallanması YALNIZCA
  # `pk_build_analysis_result()` içinde olur. Saf Faz 4 dosyaları bayraktan
  # tamamen habersizdir; çağıran taraf onları v2 arkasında kullanır.
  for (dosya in .PK_RES_DOSYALAR) {
    govde <- .pk_res_read(file.path(repo_root, "R", dosya))
    expect_false(grepl("pk_engine_is_v2", govde, fixed = TRUE, useBytes = TRUE),
                 info = dosya)
    expect_false(grepl("pk_engine_mode", govde, fixed = TRUE, useBytes = TRUE),
                 info = dosya)
  }
})

test_that("Türkçe katlama KOPYALANMAZ; tek kaynak pk_tr_fold()'dur", {
  repo_root <- resolve_repo_root_for_tests()

  for (dosya in .PK_RES_DOSYALAR) {
    # Yorumlar çıkarılır: dosya başlıkları `chartr()`in NEDEN yasak olduğunu
    # bilerek anlatır ve bu bir ihlal değildir.
    satirlar <- strsplit(.pk_res_read(file.path(repo_root, "R", dosya)),
                         "\n", fixed = TRUE)[[1]]
    govde <- paste(satirlar[!grepl("^\\s*#", satirlar)], collapse = "\n")

    # Ölçülerek reddedilen iki yaklaşım geri GELMEMELİDİR.
    expect_false(grepl("chartr(", govde, fixed = TRUE, useBytes = TRUE), info = dosya)
    expect_false(grepl("utf8ToInt", govde, fixed = TRUE, useBytes = TRUE), info = dosya)

    # Katlama yeniden TANIMLANMAMALIDIR.
    expect_false(grepl("pk_tr_fold <- function", govde, fixed = TRUE, useBytes = TRUE),
                 info = dosya)
  }
})

test_that("karar dalları ÇÖZÜLMÜŞ yapılandırmayı okur, literal eşik taşımaz", {
  repo_root <- resolve_repo_root_for_tests()
  govde <- .pk_res_read(file.path(repo_root, "R", "helpers_pk_entity_resolver.R"))

  satirlar <- strsplit(govde, "\n", fixed = TRUE)[[1]]
  kod <- satirlar[!grepl("^\\s*#", satirlar)]

  # Tepe puan / fark KARŞILAŞTIRMALARI (atama değil: `<-` hariç tutulur)
  # YALNIZCA çözülmüş eşiklerle yapılır.
  karsilastirmalar <- grep(
    "\\b(tepe|fark)\\s*(>=|<=|>|<(?!-))",
    kod, value = TRUE, perl = TRUE
  )
  expect_true(length(karsilastirmalar) >= 4L,
              info = "Beklenen karar karsilastirmalari bulunamadi.")

  for (satir in karsilastirmalar) {
    expect_true(
      grepl("esikler\\$", satir),
      info = sprintf("Karar dali cozulmus esik okumuyor: %s", trimws(satir))
    )
    # Sağ tarafta çıplak sayı bulunmamalıdır.
    expect_false(
      grepl("(>=|<)\\s*[0-9]+L?\\b", satir),
      info = sprintf("Karar dalinda literal esik: %s", trimws(satir))
    )
  }
})

test_that("kaynak manifesti Faz 4 dosyalarını doğru sırada yükler", {
  expect_source_manifest_contains_for_tests(
    file.path("R", .PK_RES_DOSYALAR)
  )

  # Bağımlılık sırası: Türkçe katlama ve yapılandırma çözümleyicisi ÖNCE;
  # ardından normalize -> score -> resolver -> history; en sonda filtre
  # derlemesi (bulanıklık HANGİ DEĞERİN filtreleneceğini çözer, hangi
  # satırın değil).
  expect_source_manifest_order_for_tests(c(
    "R/helpers_pk_text_turkish.R",
    "R/helpers_pk_config.R",
    "R/helpers_pk_entity_normalize.R",
    "R/helpers_pk_entity_score.R",
    "R/helpers_pk_entity_resolver.R",
    "R/helpers_pk_entity_history.R",
    "R/helpers_pk_filter_compile.R"
  ))
})

test_that("beş çözümleme anahtarı yapılandırma sözleşmesinde kayıtlıdır", {
  beklenen <- c(
    "MERGEN_PK_RESOLVE_AUTO_SCORE",
    "MERGEN_PK_RESOLVE_MULTI_SCORE",
    "MERGEN_PK_RESOLVE_MIN_SCORE",
    "MERGEN_PK_RESOLVE_AMBIGUITY_MARGIN",
    "MERGEN_PK_RESOLVE_MAX_CANDIDATES"
  )

  for (anahtar in beklenen) {
    expect_true(anahtar %in% names(pk_config_spec), info = anahtar)
    expect_equal(pk_config_spec[[anahtar]]$type, "integer", info = anahtar)
  }

  # Bilinmeyen anahtar UYDURULMAZ; hata verir.
  expect_error(pk_config_resolve("MERGEN_PK_RESOLVE_YOK"))
})

test_that("çözümleme eşikleri sorgu metadatasıyla ezilebilir", {
  testthat::skip_if_not_installed("stringi")

  # §9 öncelik zinciri: sorgu metadata > ortam > options > varsayılan.
  esikler <- pk_resolve_thresholds(query_meta = list(resolve_auto_score = 95L))
  expect_true(esikler$valid)
  expect_equal(esikler$auto_score, 95L)

  # 90 puanlık ASCII eşleşmesi artık otomatik kabul EDİLMEZ.
  karar <- pk_entity_resolve("kalip", c("KALIP"),
                             query_meta = list(resolve_auto_score = 95L))
  expect_false(identical(karar$decision, "auto"))
})
