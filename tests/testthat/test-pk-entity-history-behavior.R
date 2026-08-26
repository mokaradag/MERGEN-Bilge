# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-entity-history-behavior.R
# Açıklama: Faz 4 — D11 (`chat_history` okunmuyor) davranış testleri.
#           Tamamen çevrimdışı ve belirlenimcidir: DB, LLM, tarayıcı, SSO, ağ
#           veya gizli değer GEREKMEZ.
#
# D11 kanıtı: `pk_analiz_process_request()` ve `select_smart_query()`
# `chat_history` parametresini ALIR ama gövdelerinde HİÇ OKUMAZ. Bu dosya, o
# boşluğu dolduran SAF katmanın gerçekten geçmişi okuduğunu kanıtlar.
#
# Kapsanan sözleşmeler:
#   - İki mesaj biçimi de desteklenir: `role`/`content` ve `type`/`content`.
#   - Devralma YALNIZCA çözümleme başarısız olduğunda denenir.
#   - Devralma her zaman `inherited = TRUE` ile İŞARETLENİR (sessiz devralma yok).
#   - Devralınan ifade de çözümlenemezse ORİJİNAL karar korunur.
# ==============================================================================

pk_entity_source_chain_for_tests()

.PK_HIST_SOZLUK <- c(
  "Sentetik Elektronik Harp Şebekesi",
  "Sentetik Lojistik Destek Altyapısı"
)

test_that("D11 hâlâ geçerlidir: v1 yolu chat_history'yi OKUMAZ", {
  repo_root <- resolve_repo_root_for_tests()
  modul <- file.path(repo_root, "R", "module_proje_kaynak_analizi.R")
  testthat::skip_if_not(file.exists(modul))

  # Windows/VM güvenli bayt okuma (CLAUDE.md kuralı).
  ham <- readBin(modul, "raw", file.info(modul)$size)
  metin <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")

  # SAYMAK YETMEZ: `if (length(chat_history)) ...` eklemek de sayacı
  # ARTIRIRDI ve test yine geçerdi. Bu yüzden geçiş yerlerinin TAMAMI tek tek
  # doğrulanır: `chat_history` yalnızca İMZALARDA ve bir PASS-THROUGH
  # argümanında görünebilir; bir GÖVDE OKUMASI (koşul, indeksleme, uzunluk,
  # eleman erişimi) D11'in kapandığı anlamına gelir ve o zaman Faz 4'ün saf
  # katmanı ile v1 yolu ÇAKIŞIR.
  satirlar <- strsplit(metin, "\n", fixed = TRUE)[[1]]
  kod <- satirlar[!grepl("^\\s*#", satirlar)]

  # SATIR SONU YORUMLARI KIYASLAMADAN ÖNCE ATILIR.
  #
  # İzin listesi eskiden üretim satırındaki SATIR SONU YORUMUNU birebir
  # taşımak zorundaydı. O yorumun düzenlenmesi (örneğin Latinize yazımın
  # Türkçeye çevrilmesi) davranış HİÇ değişmediği hâlde bu testi kırıyor ve
  # `stop_on_failure = TRUE` yüzünden süiti düşürüyordu. Ayrıca test, düzeltilmesi
  # gereken Latinize metni kendi içinde SABİTLİYORDU. Yorum yalnızca tırnak
  # DIŞINDAKİ bir `#` işaretinden itibaren atılır; dize içindeki `#` korunur.
  yorumu_at <- function(satir) {
    karakterler <- strsplit(satir, "", fixed = TRUE)[[1]]
    tirnak <- ""
    for (i in seq_along(karakterler)) {
      k <- karakterler[i]
      onceki <- if (i > 1L) karakterler[i - 1L] else ""
      if (nzchar(tirnak)) {
        if (identical(k, tirnak) && !identical(onceki, "\\")) tirnak <- ""
      } else if (k %in% c("\"", "'")) {
        tirnak <- k
      } else if (identical(k, "#")) {
        return(substr(satir, 1L, i - 1L))
      }
    }
    satir
  }

  kod <- vapply(kod, yorumu_at, character(1), USE.NAMES = FALSE)
  gecisler <- trimws(kod[grepl("chat_history", kod, fixed = TRUE)])

  expect_true(length(gecisler) >= 2L,
              info = "chat_history parametresi beklenen yerlerde bulunamadı.")

  izinli <- c(
    "pk_analiz_process_request <- function(user_prompt, chat_history, session, stop_check = NULL) {",
    "user_prompt, query_library, chat_history,",
    "select_smart_query <- function(prompt, library, chat_history,",
    # Faz 5 (§5.2) BİLİNÇLİ güncelleme: v2 seçim hattı `chat_history`'yi
    # GERÇEKTEN okur (sınırlı takip bağlamı zarfı + eksiltili takip için
    # önceki kararlı sorgu kimliği). Bu, D11'in v2 tarafında KAPANMASIDIR.
    #
    # Testin ASIL iddiası korunur: aşağıdaki satır bir PASS-THROUGH'tur,
    # gövde okuması değildir — v1 dalı `chat_history`'yi hâlâ hiç incelemez
    # ve motor bayrağı v1 iken bu satır zaten çalışmaz. Koşul/indeksleme/
    # uzunluk/eleman erişimi eklenirse test yine kırmızıya döner.
    "prompt, library, chat_history,",
    # D11 KAPANIŞI (v2): geçmiş farkındalıklı varlık çözümleyicisine giden
    # bağlam artık ÜRETİM yolunda gerçekten bağlanıyor. Bu satır da bir
    # PASS-THROUGH'tur: `chat_history` burada okunmaz/incelenmez, yalnızca
    # `pk_filter_instructions_with_context()` üzerinden filtre talimatlarına
    # iliştirilir ve çözümleyici onu v2 dalında tüketir.
    paste0("if (exists(\"pk_filter_instructions_with_context\", mode = \"function\", ",
           "inherits = TRUE)) filter_criteria <- pk_filter_instructions_with_context(",
           "filter_criteria, chat_history, session)")
  )

  expect_equal(
    sort(gecisler), sort(izinli),
    info = paste0(
      "v1 yolunda beklenmeyen chat_history erişimi: ",
      paste(setdiff(gecisler, izinli), collapse = " | ")
    )
  )
})

test_that("iki mesaj biçimi de okunur: role/content ve type/content", {
  testthat::skip_if_not_installed("stringi")

  llm_bicimi <- list(
    list(role = "user", content = "birinci soru"),
    list(role = "assistant", content = "birinci yanıt"),
    list(role = "user", content = "ikinci soru")
  )
  expect_equal(
    pk_entity_prior_user_prompts(llm_bicimi),
    c("ikinci soru", "birinci soru")
  )

  sohbet_bicimi <- list(
    list(type = "user", content = "birinci soru"),
    list(type = "ai", content = "birinci yanıt"),
    list(type = "user", content = "ikinci soru")
  )
  expect_equal(
    pk_entity_prior_user_prompts(sohbet_bicimi),
    c("ikinci soru", "birinci soru")
  )

  # Asistan/sistem mesajları ASLA kullanıcı sorusu sayılmaz.
  yalniz_asistan <- list(list(role = "assistant", content = "yanıt"))
  expect_equal(length(pk_entity_prior_user_prompts(yalniz_asistan)), 0L)
})

test_that("boş / bozuk geçmiş güvenli biçimde ele alınır", {
  testthat::skip_if_not_installed("stringi")

  expect_equal(length(pk_entity_prior_user_prompts(NULL)), 0L)
  expect_equal(length(pk_entity_prior_user_prompts(list())), 0L)
  expect_equal(length(pk_entity_prior_user_prompts("metin degil liste")), 0L)
  expect_equal(length(pk_entity_prior_user_prompts(list(list(role = "user")))), 0L)
})

test_that("eksiltili devam soruları tespit edilir", {
  testthat::skip_if_not_installed("stringi")

  expect_true(pk_entity_is_followup("peki 2024 için?"))
  expect_true(pk_entity_is_followup("sadece aktif olanlar"))
  expect_true(pk_entity_is_followup("ya 2023?"))
  expect_true(pk_entity_is_followup("bir de 2022"))
  expect_true(pk_entity_is_followup("onun bütçesi ne kadar"))
  expect_true(pk_entity_is_followup("yalnızca tamamlananlar"))

  # Tam bir soru devam sorusu DEĞİLDİR.
  expect_false(pk_entity_is_followup("Elektronik Harp Şebekesi bütçesi nedir"))
  expect_false(pk_entity_is_followup("lojistik altyapısı"))
  expect_false(pk_entity_is_followup(""))
})

test_that("devam sorusu önceki soruyu DEVRALIR ve işaretler", {
  testthat::skip_if_not_installed("stringi")

  gecmis <- list(
    list(role = "user", content = "elektronik harp şebekesi bütçesi nedir"),
    list(role = "assistant", content = "... yanıt ...")
  )

  karar <- pk_entity_resolve_with_history(
    phrase = "peki 2024 için?",
    candidates = .PK_HIST_SOZLUK,
    chat_history = gecmis
  )

  expect_true(isTRUE(karar$inherited))
  expect_equal(karar$inherited_from, "elektronik harp şebekesi bütçesi nedir")
  expect_equal(karar$original_phrase, "peki 2024 için?")

  # Devralınan bağlam DOĞRU varlığı bulur, ama SESSİZCE filtrelemez: kural 5
  # tek tıklık onay ister. Devralma varsayımsaldır; otomatik uygulanması
  # kullanıcının hiç yazmadığı bir filtreyi gizlice eklemek olurdu.
  expect_equal(karar$decision, "confirm")
  expect_equal(karar$rule, 5L)
  expect_equal(karar$candidates[[1]]$value, "Sentetik Elektronik Harp Şebekesi")
  expect_true(isTRUE(karar$chips[[1]]$preselected))
  expect_equal(length(karar$values), 0L)
})

test_that("soru sözcükleri YALNIZCA devralınan mesajdan atılır (E4)", {
  testthat::skip_if_not_installed("stringi")

  # Soru sözcükleri atılmazsa J = 0.50 < 0.60 kalır ve HİÇBİR katman
  # eşleşmez; D11 örneği bu adım olmadan çalışmaz.
  expect_equal(
    pk_entity_strip_question_words("elektronik harp şebekesi bütçesi nedir"),
    "elektronik harp şebekesi bütçesi"
  )

  # Alan adları (bütçe) BİLEREK korunur: ayırt edici olabilirler.
  expect_true(grepl("bütçesi", pk_entity_strip_question_words("bütçesi nedir"), fixed = TRUE))

  # Tamamı soru sözcüğünden oluşan girdi BOŞ dönmez; orijinal korunur.
  expect_equal(pk_entity_strip_question_words("nedir ne kadar"), "nedir ne kadar")
  expect_true(is.na(pk_entity_strip_question_words("   ")))
})

test_that("devralma YALNIZCA çözümleme başarısız olduğunda denenir", {
  testthat::skip_if_not_installed("stringi")

  gecmis <- list(
    list(role = "user", content = "lojistik destek altyapısı")
  )

  # Mevcut ifade ZATEN çözümleniyor: geçmiş DEVREYE GİRMEMELİDİR, aksi hâlde
  # kullanıcının yeni sorusu sessizce eski bağlamla değiştirilirdi.
  karar <- pk_entity_resolve_with_history(
    phrase = "elektronik harp şebekesi",
    candidates = .PK_HIST_SOZLUK,
    chat_history = gecmis
  )

  expect_false(isTRUE(karar$inherited))
  expect_equal(karar$values, "Sentetik Elektronik Harp Şebekesi")
})

test_that("devam sorusu OLMAYAN çözümsüz ifade devralmaz", {
  testthat::skip_if_not_installed("stringi")

  gecmis <- list(list(role = "user", content = "elektronik harp şebekesi"))

  karar <- pk_entity_resolve_with_history(
    phrase = "qqqqqqqqqq",
    candidates = .PK_HIST_SOZLUK,
    chat_history = gecmis
  )

  expect_false(isTRUE(karar$inherited))
  expect_equal(karar$decision, "unresolved")
})

test_that("devralınan ifade de çözümlenemezse ORİJİNAL karar korunur", {
  testthat::skip_if_not_installed("stringi")

  gecmis <- list(list(role = "user", content = "zzzzzzzzzz ilgisiz soru"))

  karar <- pk_entity_resolve_with_history(
    phrase = "peki 2024 için?",
    candidates = .PK_HIST_SOZLUK,
    chat_history = gecmis
  )

  expect_false(isTRUE(karar$inherited))
  expect_equal(karar$decision, "unresolved")
  # Hata mesajı kullanıcının GERÇEKTEN yazdığı ifadeye aittir.
  expect_true(is.null(karar$inherited_from))
})

test_that("yapılandırma hatası devralmayla DÜZELMEZ", {
  testthat::skip_if_not_installed("stringi")

  esikler <- list(
    valid = FALSE, errors = "sentetik hata",
    min_score = 90L, multi_score = 70L, auto_score = 85L,
    ambiguity_margin = 10L, max_candidates = 5L
  )
  gecmis <- list(list(role = "user", content = "elektronik harp şebekesi"))

  karar <- pk_entity_resolve_with_history(
    phrase = "peki 2024 için?",
    candidates = .PK_HIST_SOZLUK,
    chat_history = gecmis,
    thresholds = esikler
  )

  expect_equal(karar$decision, "config_error")
  expect_false(isTRUE(karar$inherited))
})

test_that("devralma en YENİ kullanıcı sorusundan başlar", {
  testthat::skip_if_not_installed("stringi")

  gecmis <- list(
    list(role = "user", content = "lojistik destek altyapısı"),
    list(role = "assistant", content = "..."),
    list(role = "user", content = "elektronik harp şebekesi"),
    list(role = "assistant", content = "...")
  )

  karar <- pk_entity_resolve_with_history(
    phrase = "sadece aktif olanlar",
    candidates = .PK_HIST_SOZLUK,
    chat_history = gecmis
  )

  expect_true(isTRUE(karar$inherited))

  # DEVRALINAN SONUÇ OTOMATİK DEĞİLDİR: devralınan şey kullanıcının BU
  # mesajda yazmadığı bir filtredir. Karar onaya indirgenir ve `values`
  # BOŞALTILIR; kanonik değer yalnızca ön seçili çip olarak sunulur.
  expect_equal(karar$decision, "confirm")
  expect_length(karar$values, 0L)
  expect_equal(karar$chips[[1]]$value, "Sentetik Elektronik Harp Şebekesi")
  expect_true(isTRUE(karar$chips[[1]]$preselected))
})

test_that("devam sorusu planı saf ve incelenebilirdir", {
  testthat::skip_if_not_installed("stringi")

  gecmis <- list(
    list(role = "user", content = "birinci"),
    list(role = "user", content = "ikinci")
  )

  plan <- pk_entity_followup_plan(gecmis, "peki 2024 için?")
  expect_true(plan$is_followup)
  expect_equal(plan$inherited_phrase, "ikinci")
  expect_equal(plan$prior_prompts, c("ikinci", "birinci"))

  plan_yok <- pk_entity_followup_plan(NULL, "elektronik harp")
  expect_false(plan_yok$is_followup)
  expect_true(is.na(plan_yok$inherited_phrase))
})
