# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-query-selection-hardening-behavior.R
# Açıklama: Faz 5 (§5.2) iki geçişli sorgu seçiminin KATILIK (hardening)
#           sözleşmeleri — davranışsal regresyon kapısı.
#
#           Her test, kapatılan KUSURUN kendisini kanıtlar: katılık geri
#           alındığında test başarısız olmalıdır. Kapsanan sınırlar:
#             * KATI JSON (sarmalayıcı düzyazı, tekrar eden anahtar, tip katılığı),
#             * `requirements` sözleşmesi (zorunluluk, bilinmeyen alan, entity,
#               ifade edilemeyen ihtiyaç, gruplama rolü),
#             * karar durumlarının AYRIŞTIRILMASI (validator_error vs eksik yetenek),
#             * hata SINIFLANDIRMASI (zaman aşımı / kimlik / boş cevap),
#             * kapalı-başarısız yapılandırma (öncelik, şekil, taşma, tavanlar),
#             * bozulma kipinin ANLAMLILIĞI ve bağlam koruması,
#             * SÖYLEŞİ kapsamlı oturum durumu ve onaylı seçim yolu,
#             * v1'e sessiz düşüşün ENGELLENMESİ ve tanılama doğruluğu,
#             * sözlüksel beraberlik/`not_for` olumsuz kanıtı.
#
#           Tümü ÇEVRİMDIŞI ve deterministiktir: gerçek DB, LLM, tarayıcı, SSO,
#           ağ veya gerçek sır KULLANILMAZ; fixture'lar sentetiktir.
# ==============================================================================

pk_select_source_chain_for_tests()

.pk_selhard_cfg <- function(...) {
  ust <- list(...)
  taban <- list(
    timeout_sec = 20L, recall_n = 5L, min_confidence = 50L, min_margin = 15L,
    disagree_penalty = 15L, desc_chars = 220L, sample_chars = 120L,
    sample_n = 2L, history_turns = 2L, name_chars = 120L, keyword_chars = 160L,
    history_chars = 240L, pass_b_chars = 24000L, pass_a_chars = 60000L
  )
  if (length(ust)) taban[names(ust)] <- ust
  pk_select_normalize_config(taban)
}

.pk_selhard_req <- function(...) {
  alanlar <- list(
    entity = "null", measures = "[]", dates = "[]",
    dimensions = "[]", group_by = "[]", unsupported = "[]"
  )
  ust <- list(...)
  if (length(ust)) alanlar[names(ust)] <- ust
  paste0(
    "{",
    paste(sprintf("\"%s\":%s", names(alanlar), unlist(alanlar)), collapse = ","),
    "}"
  )
}

.pk_selhard_pass_b <- function(id = "q002", confidence = 85, alternates = NULL,
                          requirements = .pk_selhard_req(), missing_info = "null",
                          reason = "\"gerekce\"",
                          candidate_ids = c("q001", "q002", "q003", "q004")) {
  if (is.null(alternates)) {
    digerleri <- setdiff(candidate_ids, id)
    alternates <- paste0("[", paste(vapply(digerleri, function(k) {
      sprintf("{\"id\":\"%s\",\"confidence\":30}", k)
    }, character(1)), collapse = ","), "]")
  }
  sprintf(
    "{\"id\":\"%s\",\"confidence\":%s,\"reason\":%s,\"alternates\":%s,\"requirements\":%s,\"missing_info\":%s}",
    id, confidence, reason, alternates, requirements, missing_info
  )
}

# ------------------------------------------------------------------------------
# 1. KATI JSON ilkeleri
# ------------------------------------------------------------------------------

test_that("sarmalayıcı düzyazı içine gömülü JSON KABUL EDİLMEZ", {
  # "Karar veremiyorum; ornek cikti: {...}" cevabı, ilk `{` ile son `}` arası
  # kesildiğinde GERÇEK bir seçim gibi kabul ediliyor ve kapıları geçebiliyordu.
  gomulu <- "Karar veremiyorum; ornek cikti: {\"candidates\":[\"q001\"]} umarim yardimci olur"
  expect_null(pk_select_parse_json(gomulu))
  expect_false(pk_select_parse_pass_a(gomulu, c("q001"))$ok)

  # Metnin TAMAMINI saran tek bir kod bloğu çiti hâlâ soyulur.
  expect_false(is.null(pk_select_parse_json("```json\n{\"candidates\":[\"q001\"]}\n```")))
})

test_that("aynı nesnede TEKRAR EDEN anahtar cevabı bozar", {
  cift <- "{\"id\":\"q001\",\"confidence\":10,\"confidence\":95}"
  expect_true("confidence" %in% pk_select_json_duplicate_keys(cift))
  expect_null(pk_select_parse_json(cift))

  # Farklı nesnelerdeki aynı anahtar adı tekrar DEĞİLDİR.
  expect_equal(
    length(pk_select_json_duplicate_keys("{\"a\":{\"id\":\"x\"},\"b\":{\"id\":\"y\"}}")),
    0L
  )
})

test_that("güven değeri gerçek JSON TAM SAYISI olmalıdır", {
  gecersizler <- list(
    "metin" = "\"95\"", "mantiksal" = "true", "dizi" = "[95,10]", "kesirli" = "49.6"
  )
  for (ad in names(gecersizler)) {
    ayrisik <- pk_select_parse_pass_b(
      .pk_selhard_pass_b(confidence = gecersizler[[ad]]), c("q001", "q002", "q003", "q004")
    )
    expect_false(ayrisik$ok, info = sprintf("Senaryo '%s' kabul edilmemelidir.", ad))
  }

  expect_identical(pk_select_scalar_integer(49.6, 0L, 100L), NA_integer_)
  expect_identical(pk_select_scalar_integer(TRUE, 0L, 100L), NA_integer_)
  expect_identical(pk_select_scalar_integer("95", 0L, 100L), NA_integer_)
  expect_identical(pk_select_scalar_integer(95, 0L, 100L), 95L)
})

test_that("skaler olmayan `id` alanı seçim sayılmaz", {
  # SOZLESME IHLALI YALNIZCA `id` OLMALIDIR (PR #705 inceleme, P3).
  #
  # Yuk eskiden `"requirements":{}` tasiyordu; `pk_select_normalize_requirements()`
  # BOS nesneyi ZATEN reddettigi icin `pk_select_parse_pass_b()` sirf o alan
  # yuzunden `ok = FALSE` donuyordu. `id` katiligi geriye gitse bile bu iddia
  # GECERDI. Gecerli alti alanli bir `requirements` blogu kullanilir ve donen
  # hata metni de dogrulanir.
  ayrisik <- pk_select_parse_pass_b(
    sprintf(
      "{\"id\":[\"q002\",\"q001\"],\"confidence\":90,\"reason\":\"x\",\"alternates\":[],\"requirements\":%s,\"missing_info\":null}",
      .pk_selhard_req()
    ),
    c("q001", "q002")
  )
  expect_false(ayrisik$ok)
  expect_true(grepl("id", as.character(ayrisik$error %||% "")[1], fixed = TRUE))
  expect_identical(pk_select_scalar_string(list("a", "b")), NA_character_)
})

# ------------------------------------------------------------------------------
# 2. `requirements` sözleşmesi
# ------------------------------------------------------------------------------

test_that("`requirements` ve `missing_info` ZORUNLUDUR", {
  adaylar <- c("q001", "q002")

  eksik_req <- "{\"id\":\"q002\",\"confidence\":90,\"reason\":\"x\",\"alternates\":[{\"id\":\"q001\",\"confidence\":5}],\"missing_info\":null}"
  expect_false(pk_select_parse_pass_b(eksik_req, adaylar)$ok)

  eksik_mi <- .pk_selhard_pass_b(candidate_ids = adaylar)
  eksik_mi <- sub(",\"missing_info\":null", "", eksik_mi, fixed = TRUE)
  expect_false(pk_select_parse_pass_b(eksik_mi, adaylar)$ok)

  # Açık `null` GEÇERLİDİR: "alan yok" ile "eksik bilgi yok" aynı şey değildir.
  expect_true(pk_select_parse_pass_b(.pk_selhard_pass_b(candidate_ids = adaylar), adaylar)$ok)
})

test_that("bilinmeyen `requirements` alanı ve skaler olmayan entity reddedilir", {
  expect_false(pk_select_normalize_requirements(list(measure = "x"))$ok)
  expect_false(pk_select_normalize_requirements(list(entity = list("project", "resource")))$ok)
  expect_false(pk_select_normalize_requirements(list(measures = list(list("x"))))$ok)
  expect_false(pk_select_normalize_requirements(NULL)$ok)

  tam <- pk_select_normalize_requirements(list(
    entity = "project", measures = list("labor.planned_hours"),
    dates = list(), dimensions = list(), group_by = list(), unsupported = list()
  ))
  expect_true(tam$ok)
  expect_identical(tam$value$entity, "project")
  expect_identical(tam$value$measures, "labor.planned_hours")
})

test_that("boş olmayan `reason` alanı zorunludur", {
  adaylar <- c("q001", "q002")
  expect_false(pk_select_parse_pass_b(.pk_selhard_pass_b(reason = "\"\"", candidate_ids = adaylar), adaylar)$ok)
  expect_false(pk_select_parse_pass_b(.pk_selhard_pass_b(reason = "null", candidate_ids = adaylar), adaylar)$ok)
})

test_that("İFADE EDİLEMEYEN anlamsal ihtiyaç otomatik çalıştırmayı durdurur", {
  # Eskiden istem, modelden ifade edemediği ihtiyacı SİLMESİNİ istiyordu;
  # sonuç kanıtsız ama yüksek güvenli bir `auto` idi.
  adaylar <- c("q001", "q002")
  ayrisik <- pk_select_parse_pass_b(
    .pk_selhard_pass_b(
      requirements = .pk_selhard_req(unsupported = "[\"gecikme nedeni kirilimi\"]"),
      candidate_ids = adaylar
    ),
    adaylar
  )
  expect_true(ayrisik$ok)

  karar <- pk_select_decide(
    ayrisik, adaylar, pk_select_library_index(pk_select_test_library()), .pk_selhard_cfg()
  )
  expect_identical(karar$status, PK_SELECT_STATUS_UNSUPPORTED_REQ)
})

test_that("doğrulayıcı çökmesi `capability_missing` ile BİRLEŞTİRİLMEZ", {
  # Doğrulayıcının KENDİSİ global olarak değiştirilir; `pk_select_decide()`
  # onu çağrı anında çözer. Ortam geri yüklenir (suite sıra bağımsız kalmalı).
  hedef <- environment(pk_select_validate_requirements)
  onceki <- hedef$pk_meta_capability_check
  on.exit({
    if (is.null(onceki)) rm("pk_meta_capability_check", envir = hedef)
    else assign("pk_meta_capability_check", onceki, envir = hedef)
  }, add = TRUE)
  assign("pk_meta_capability_check", function(...) stop("dogrulayici coktu"), envir = hedef)

  adaylar <- c("q001", "q002")
  ayrisik <- pk_select_parse_pass_b(
    .pk_selhard_pass_b(id = "q002", requirements = .pk_selhard_req(
      measures = "[\"labor.remaining_hours\"]"
    ), candidate_ids = adaylar),
    adaylar
  )
  karar <- pk_select_decide(
    ayrisik, adaylar, pk_select_library_index(pk_select_test_library()),
    .pk_selhard_cfg(), capability_ids = pk_select_capability_ids(pk_select_test_registry())
  )
  expect_identical(karar$status, PK_SELECT_STATUS_VALIDATOR_ERROR)
  expect_false(identical(karar$status, PK_SELECT_STATUS_CAPABILITY_MISSING))
})

test_that("TARİH yeteneği gruplama anahtarı olarak kullanılabilir", {
  # `pk_meta_capability_check()` her `group_by` değerini `dimension` rolüne
  # katıyordu; geçerli bir tarih-gruplaması DETERMİNİSTİK olarak reddediliyordu.
  lib <- pk_select_test_library()
  kimlikler <- pk_select_capability_ids(pk_select_test_registry())

  sonuc <- pk_select_validate_requirements(
    lib[[1]],
    list(dates = "date.project_start", group_by = "date.project_start"),
    kimlikler
  )
  expect_identical(sonuc$status, "ok")
})

# ------------------------------------------------------------------------------
# 3. Hata sınıflandırması ve bozulma kipi
# ------------------------------------------------------------------------------

test_that("hata sınıflandırması teşhisi DOĞRU raporlar", {
  expect_identical(.pk_select_classify_error("API_HTTP_ERROR_504: Gateway Time-out"),
                   PK_SELECT_STATUS_TIMEOUT)
  expect_identical(.pk_select_classify_error("API_HTTP_ERROR_408"), PK_SELECT_STATUS_TIMEOUT)
  expect_identical(.pk_select_classify_error("AUTH_MISSING_KEY: anahtar yok"),
                   PK_SELECT_STATUS_AUTH_ERROR)
  expect_identical(.pk_select_classify_error("API_HTTP_ERROR_401: yetkisiz"),
                   PK_SELECT_STATUS_AUTH_ERROR)
  # Servis CEVAP VERDİ ama gövde boştu: kesinti değil, onarılabilir bozukluk.
  expect_identical(.pk_select_classify_error("EMPTY_RESPONSE: bos"),
                   PK_SELECT_STATUS_MALFORMED)
  # "connection refused" zaman aşımı DEĞİLDİR.
  expect_identical(.pk_select_classify_error("Failed to connect: connection refused"),
                   PK_SELECT_STATUS_LLM_UNAVAILABLE)
})

test_that("bozulma kipi ALAKASIZ sıfır skorlu sorguları seçenek olarak sunmaz", {
  lib <- pk_select_test_library()
  index <- pk_retrieval_build_index(lib)
  library_index <- pk_select_library_index(lib)

  karar <- pk_select_degraded_decision(
    PK_SELECT_STATUS_LLM_UNAVAILABLE, index, "zzzz qqqq xxxx", library_index
  )
  expect_equal(length(karar$chips), 0L)
  expect_true(grepl("bulunamadı", karar$message_tr, fixed = TRUE))

  # Örtüşme VARSA seçenekler sunulur.
  karar2 <- pk_select_degraded_decision(
    PK_SELECT_STATUS_LLM_UNAVAILABLE, index, "sentetik butce harcama", library_index
  )
  expect_true(length(karar2$chips) > 0L)
})

test_that("bozulma kipi ÖNCEKİ kararlı kimliği ve aday kümesini korur", {
  lib <- pk_select_test_library()
  index <- pk_retrieval_build_index(lib)
  library_index <- pk_select_library_index(lib)

  # Eksiltili soruda sorgu taşıyan tek kanıt önceki kimliktir.
  kimlikler <- pk_select_degraded_candidates(
    index, "peki 2024 icin?", library_index, prior_query_id = "q001"
  )
  expect_identical(kimlikler[1], "q001")

  # Geçiş A başarılıysa bozulma O KÜMENİN İÇİNDE kalır.
  sinirli <- pk_select_degraded_candidates(
    index, "sentetik butce", library_index, restrict_ids = c("q003", "q004")
  )
  # BOŞ KÜME İDDİAYI KENDİLİĞİNDEN GEÇİRİR: `all()` boş vektörde `TRUE` döner,
  # yani TÜM adayları düşüren bir regresyon da bu testten geçerdi.
  expect_true(length(sinirli) > 0L,
              info = "Kısıtlama kümesi TÜM adayları düşürmemelidir.")
  expect_true(all(sinirli %in% c("q003", "q004")))
})

test_that("MALFORMED çıktı 'servise ulaşılamıyor' diye raporlanmaz", {
  cfg <- .pk_selhard_cfg()
  stub <- pk_select_stub_llm(list("bu json degil", "bu da json degil"))
  karar <- pk_select_run("sentetik butce", pk_select_test_library(),
                         llm_fn = stub$fn, cfg = cfg)

  expect_identical(karar$status, PK_SELECT_STATUS_MALFORMED)
  expect_false(grepl("ulaşılamıyor", karar$message_tr, fixed = TRUE))
  expect_true(any(grepl("yanıt verdi", karar$disclosures, fixed = TRUE)))
})

# ------------------------------------------------------------------------------
# 4. Kapalı-başarısız yapılandırma
# ------------------------------------------------------------------------------

test_that("GÖLGELENMİŞ geçersiz kaynak seçimi kapatmaz", {
  # Geçerli bir ortam değeri, geçersiz bir `options()` değerini GÖLGELER;
  # eski davranış yine de `config_error` üretiyordu.
  pk_select_with_env(c(MERGEN_PK_SELECT_RECALL_N = "3"), {
    options(mergen.pk.select_recall_n = 1L)
    cfg <- pk_select_config()
    expect_true(cfg$valid, info = paste(cfg$errors, collapse = " "))
    expect_equal(cfg$recall_n, 3L)
  })
})

test_that("VAR ama şekli BOZUK kaynak sessizce varsayılana düşmez", {
  pk_select_with_env(character(0), {
    options(mergen.pk.select_min_confidence = c(90L, 95L))
    cfg <- pk_select_config()
    expect_false(cfg$valid)
    expect_true(any(grepl("MERGEN_PK_SELECT_MIN_CONFIDENCE", cfg$errors, fixed = TRUE)))
  })
})

test_that("tam sayı TAŞMASI hata fırlatmaz, kapalı başarısız olur", {
  cfg <- .pk_selhard_cfg(timeout_sec = 3e9)
  expect_false(cfg$valid)
  expect_true(any(grepl("MERGEN_PK_SELECT_TIMEOUT_SEC", cfg$errors, fixed = TRUE)))
})

test_that("bütçe/zarf anahtarları ÜST SINIRA sahiptir", {
  tavanlar <- list(
    MERGEN_PK_SELECT_TIMEOUT_SEC = 120L,
    MERGEN_PK_SELECT_DESC_CHARS = 600L,
    MERGEN_PK_SELECT_SAMPLE_CHARS = 400L,
    MERGEN_PK_SELECT_SAMPLE_N = 2L,
    MERGEN_PK_SELECT_HISTORY_TURNS = 2L
  )
  for (anahtar in names(tavanlar)) {
    expect_identical(
      as.integer(pk_config_spec[[anahtar]]$max), tavanlar[[anahtar]],
      info = sprintf("%s sınırsız bırakılamaz.", anahtar)
    )
  }
})

test_that("seçilen sorgunun metadata POLİTİKASI karar eşiklerini geçersiz kılar", {
  # §9 önceliği metadata -> ortam -> options -> varsayılandır; seçim eşikleri
  # HİÇ metadata görmeden çözülüyor ve daha KATI bir sorgu politikası
  # yok sayılıyordu.
  cfg <- .pk_selhard_cfg()
  sikilastirilmis <- pk_select_config_for_query(cfg, list(select_min_confidence = 90L))
  expect_equal(sikilastirilmis$min_confidence, 90L)
  # Getirim ayarları DEĞİŞMEZ (aday seçilmeden okunamazlar).
  expect_equal(sikilastirilmis$recall_n, cfg$recall_n)

  adaylar <- c("q001", "q002")
  ayrisik <- pk_select_parse_pass_b(
    .pk_selhard_pass_b(id = "q002", confidence = 85,
                  alternates = "[{\"id\":\"q001\",\"confidence\":10}]",
                  candidate_ids = adaylar),
    adaylar
  )
  lib <- pk_select_test_library()
  lib[[2]]$meta$select_min_confidence <- 90L

  expect_identical(
    pk_select_decide(ayrisik, adaylar, pk_select_library_index(lib), cfg)$status,
    PK_SELECT_STATUS_LOW_CONFIDENCE
  )
})

test_that("dışarıdan verilen `cfg` YENİDEN doğrulanır", {
  # Çağıranın `valid = TRUE` iddiasına güvenilmez.
  sahte <- list(
    valid = TRUE, errors = character(0),
    timeout_sec = 20L, recall_n = 1L, min_confidence = 50L, min_margin = 15L,
    disagree_penalty = 15L, desc_chars = 220L, sample_chars = 120L,
    sample_n = 2L, history_turns = 2L, name_chars = 120L, keyword_chars = 160L,
    history_chars = 240L, pass_b_chars = 24000L, pass_a_chars = 60000L
  )
  karar <- pk_select_run("soru", pk_select_test_library(),
                         llm_fn = function(...) stop("cagrilmamali"), cfg = sahte)
  expect_identical(karar$status, PK_SELECT_STATUS_CONFIG_ERROR)
})

# ------------------------------------------------------------------------------
# 5. Oturum durumu: SÖYLEŞİ kapsamı, onay yolu, kalıcılaştırma zamanı
# ------------------------------------------------------------------------------

test_that("önceki sorgu kimliği SÖYLEŞİYE göre izole edilir", {
  oturum <- list(userData = new.env(parent = emptyenv()))
  a <- pk_select_chat_key(list(list(role = "user", content = "ilk soru A")))
  b <- pk_select_chat_key(list(list(role = "user", content = "ilk soru B")))
  expect_false(identical(a, b))

  pk_select_remember_query_id(oturum, "q001", a)
  expect_identical(pk_select_prior_query_id(oturum, a), "q001")
  expect_null(pk_select_prior_query_id(oturum, b))

  pk_select_forget_query_id(oturum, a)
  expect_null(pk_select_prior_query_id(oturum, a))
})

test_that("SUNULAN seçenek deterministik olarak çözülür (LLM'siz devam)", {
  oturum <- list(userData = new.env(parent = emptyenv()))
  sohbet <- pk_select_chat_key(NULL)
  pk_select_remember_offer(oturum, list(
    list(id = "q001", name = "Sentetik Bütçe Özeti"),
    list(id = "q002", name = "Sentetik Kaynak Atama Listesi")
  ), sohbet)

  expect_identical(pk_select_resolve_user_choice(oturum, "q002", sohbet), "q002")
  expect_identical(pk_select_resolve_user_choice(oturum, "2", sohbet), "q002")
  expect_identical(
    pk_select_resolve_user_choice(oturum, "Sentetik Bütçe Özeti", sohbet), "q001"
  )
  # BULANIK eşleşme YOKTUR: belirsiz cevap sessizce yanlış analizi çalıştıramaz.
  expect_true(is.na(pk_select_resolve_user_choice(oturum, "sentetik", sohbet)))
})

test_that("onaylı seçim, erişilemeyen seçiciyi TEKRAR çalıştırmadan devam eder", {
  oturum <- list(userData = new.env(parent = emptyenv()))
  sohbet <- pk_select_chat_key(NULL)
  pk_select_remember_offer(oturum, list(list(id = "q002", name = "Sentetik Kaynak Atama Listesi")), sohbet)

  sonuc <- pk_select_query_v2(
    "q002", pk_select_test_library(), chat_history = NULL, session = oturum,
    llm_fn = function(...) stop("LLM cagrilmamaliydi"), cfg = .pk_selhard_cfg()
  )

  expect_identical(sonuc$id, "q002")
  expect_identical(sonuc$selection_method, "user_confirmed")
})

test_that("seçim, çağıran KABUL EDENE kadar kalıcılaştırılmaz", {
  oturum <- list(userData = new.env(parent = emptyenv()))
  stub <- pk_select_stub_llm(list(
    "{\"candidates\":[\"q001\",\"q002\",\"q003\",\"q004\"]}",
    .pk_selhard_pass_b(id = "q002")
  ))
  sonuc <- pk_select_query_v2("sentetik soru", pk_select_test_library(),
                              session = oturum, llm_fn = stub$fn, cfg = .pk_selhard_cfg())

  sohbet <- sonuc$pk_pending_chat_key
  expect_null(pk_select_prior_query_id(oturum, sohbet))
  pk_select_commit_selection(sonuc, oturum)
  expect_identical(pk_select_prior_query_id(oturum, sohbet), "q002")
})

# ------------------------------------------------------------------------------
# 6. v1'e sessiz düşüşün engellenmesi ve tanılama doğruluğu
# ------------------------------------------------------------------------------

test_that("v2 iç hatası v1 karar yoluna DÜŞMEZ; tipli ret döner", {
  # `NULL` dönmek, operatörün açıkça etkinleştirdiği kapıları sessizce
  # devre dışı bırakıyor ve kapısız v1 seçicisini devreye sokuyordu.
  sonuc <- pk_select_query_v2(
    "soru", pk_select_test_library(), chat_history = NULL, session = NULL,
    llm_fn = function(...) stop("beklenmeyen ic hata"),
    cfg = .pk_selhard_cfg()
  )
  expect_false(is.null(sonuc))
  expect_null(sonuc$id)
  expect_true(nzchar(sonuc$refusal_message))
})

test_that("v1 uyumlu tabloda ETKİN güven ve TÜM alternatif skorları görünür", {
  adaylar <- c("q001", "q002", "q003")
  ayrisik <- pk_select_parse_pass_b(
    .pk_selhard_pass_b(
      id = "q002", confidence = 90,
      alternates = "[{\"id\":\"q001\",\"confidence\":70},{\"id\":\"q003\",\"confidence\":60}]",
      candidate_ids = adaylar
    ),
    adaylar
  )
  karar <- pk_select_decide(
    ayrisik, adaylar, pk_select_library_index(pk_select_test_library()), .pk_selhard_cfg(),
    # `pk_retrieval_agreement()` BEŞ alan döndürür; vekil de aynı şekli taşımalı.
    lexical = list(available = TRUE, rank = 9L, score = 0.01, disagrees = TRUE,
                   excluded_by_not_for = FALSE)
  )

  tablo <- pk_select_scores_table(pk_select_test_library(), karar)
  satir <- function(k) tablo[tablo$query_id == k, , drop = FALSE]

  # Karar ETKİN güvenle verilir; "Final Skor" de o değeri göstermelidir.
  expect_equal(satir("q002")$ai_score, 90)
  expect_equal(satir("q002")$final_score, as.numeric(karar$effective_confidence))
  # Üçüncü aday da GERÇEK skorunu taşır; "model skor vermedi" görünmez.
  expect_equal(satir("q003")$ai_score, 60)
})

test_that("model kaynaklı gerekçe SATIR TABANLI günlüğü bozamaz", {
  cikti <- utils::capture.output(
    pk_select_log_selection(list(
      name = "Sentetik", relevance_score = 80, selection_method = "ai_two_pass",
      selection_reason = "x\n[PK_ANALIZ] SAHTE KAYIT"
    ))
  )
  expect_equal(length(grep("^\\[PK_ANALIZ\\]", cikti)), 2L)
  expect_true(any(grepl("SAHTE KAYIT", cikti, fixed = TRUE)))
  expect_false(any(grepl("^\\[PK_ANALIZ\\] SAHTE KAYIT", cikti)))
})

test_that("CEZA SIFIR iken bile sözlüksel uyuşmazlık RAPORLANIR", {
  adaylar <- c("q001", "q002")
  ayrisik <- pk_select_parse_pass_b(
    .pk_selhard_pass_b(id = "q002", confidence = 90,
                  alternates = "[{\"id\":\"q001\",\"confidence\":10}]",
                  candidate_ids = adaylar),
    adaylar
  )
  karar <- pk_select_decide(
    ayrisik, adaylar, pk_select_library_index(pk_select_test_library()),
    .pk_selhard_cfg(disagree_penalty = 0L),
    # `pk_retrieval_agreement()` BEŞ alan döndürür; vekil de aynı şekli taşımalı.
    lexical = list(available = TRUE, rank = 9L, score = 0.01, disagrees = TRUE,
                   excluded_by_not_for = FALSE)
  )
  expect_identical(karar$status, PK_SELECT_STATUS_AUTO)
  expect_equal(karar$effective_confidence, 90L)
  expect_true(any(grepl("Sözlüksel getirim", karar$disclosures, fixed = TRUE)))
})

# ------------------------------------------------------------------------------
# 7. Sözlüksel katman: beraberlik ve `not_for` olumsuz kanıtı
# ------------------------------------------------------------------------------

test_that("skor BERABERLİĞİ kimlik sırasına göre uyuşmazlık ÜRETMEZ", {
  lib <- list(
    list(id = "qa", name = "Ayni Metin", description = "ayni aciklama metni"),
    list(id = "qb", name = "Ayni Metin", description = "ayni aciklama metni"),
    list(id = "qc", name = "Baska", description = "tamamen farkli bir konu")
  )
  index <- pk_retrieval_build_index(lib)

  # `qa` ve `qb` skorları EŞİTTİR; `qb` yalnızca kimliği sonra geldiği için
  # ikinci sıradadır ve top_n = 1 penceresinin dışında kalır.
  uyum <- pk_retrieval_agreement(index, "ayni aciklama metni", "qb", top_n = 1L)
  expect_true(uyum$available)
  expect_false(uyum$disagrees, info = "Beraberlik uyuşmazlık DEĞİLDİR.")
})

test_that("`not_for` ile isteği DIŞLAYAN sorgular uyuşmazlık cezası üretmez", {
  lib <- list(
    list(id = "qx", name = "Butce Raporu", description = "butce harcama raporu",
         meta = list(not_for = c("kaynak atama sorulari"))),
    list(id = "qy", name = "Kaynak Atama", description = "kaynak atama listesi")
  )
  index <- pk_retrieval_build_index(lib)

  dislanan <- pk_retrieval_excluded_ids(lib, "kaynak atama sorulari icin liste")
  expect_true("qx" %in% dislanan)

  # `qy` doğru seçimdir; `qx` sözlüksel olarak öne geçse bile ceza almamalıdır.
  uyum <- pk_retrieval_agreement(index, "kaynak atama sorulari icin liste", "qy",
                                 top_n = 1L, library = lib)
  expect_false(uyum$disagrees)
})

# ------------------------------------------------------------------------------
# 8. İstem yükü: geri alınamaz kanıtlar ve anlamsal üst küme
# ------------------------------------------------------------------------------

test_that("Geçiş B bloğu Geçiş A'nın anlamsal ÜST KÜMESİDİR", {
  cfg <- .pk_selhard_cfg()
  sorgu <- list(
    id = "q100", name = "Tanecikli Rapor", description = "aciklama",
    disable_ai_filters = TRUE,
    meta = list(
      keywords = c("ayirt_edici_anahtar"),
      intents = c("gecikme_takibi"),
      not_for = c("butce sorulari"),
      entity = "project",
      grain = "aktivite_atama",
      grain_columns = c("AktiviteID", "KaynakID"),
      column_meta = list(
        KalanIscilik_sa = list(
          label = "Kalan İşçilik", role = "measure",
          capability = "labor.remaining_hours", unit = "saat",
          aggregate = "sum", additive = TRUE, filterable = TRUE, match = "exact"
        )
      )
    )
  )

  blok <- pk_select_pass_b_block(sorgu, cfg)
  for (kanit in c("ayirt_edici_anahtar", "gecikme_takibi", "butce sorulari",
                  "project", "aktivite_atama", "rol=measure", "toplama=sum",
                  "toplanabilir=evet", "filtrelenebilir=evet", "eslesme=exact",
                  "birim=saat")) {
    expect_true(grepl(kanit, blok, fixed = TRUE),
                info = sprintf("Geçiş B bloğu '%s' bilgisini taşımalıdır.", kanit))
  }

  # Filtrelemeyi KAPATAN sorgu bu çalışma zamanı anlamını AÇIKÇA bildirir.
  expect_true(grepl("istek bazli filtrelemeyi UYGULAMAZ", blok, fixed = TRUE))
})

test_that("Geçiş B yükü TOPLAM karakter bütçesiyle sınırlıdır", {
  # KİMLİK GÖVDESİ bile sığmıyorsa kapalı başarısızlık KORUNUR: burada tek
  # başına 5000 karakterlik bir açıklama 2000 karakterlik bütçeyi aşar ve bu
  # gerçekten bir yapılandırma sorunudur.
  cfg <- .pk_selhard_cfg(pass_b_chars = 2000L)
  dev <- list(
    id = "q100", name = "Dev", description = strrep("a", 5000L),
    meta = list(sample_questions = strrep("b", 5000L))
  )
  bloklar <- pk_select_pass_b_blocks(list(dev), cfg)
  expect_true(bloklar$truncated, info = "Sessiz kırpma yerine AÇIK bildirim.")

  # Kapalı başarısızlık: seçim durur, sessizce eksik adayla devam etmez.
  karar <- pk_select_run(
    "soru", list(dev), llm_fn = function(messages, settings) {
      list(content = "{\"candidates\":[\"q100\"]}")
    }, cfg = .pk_selhard_cfg(pass_b_chars = 2000L, recall_n = 2L)
  )
  expect_identical(karar$status, PK_SELECT_STATUS_LIBRARY_ERROR)
})

test_that("Geçiş B bütçesi aşılınca aday DÜŞÜRÜLMEZ, sütun payı daraltılır", {
  # ÖLÇÜLEN ÜRETİM ARIZASI: gerçek kütüphanede sorgu başına onlarca/yüzlerce
  # sütun tanımı vardır; 5 adaylık yük varsayılan bütçeyi HER ZAMAN aşıyor ve
  # `pk_select_pass_b_blocks()` TÜM isteği `library_error` ile reddediyordu.
  # Yani basit bir soruda Geçiş B hiç çalışmıyordu.
  sutunlar <- setNames(
    lapply(seq_len(150L), function(i) list(
      label = sprintf("Tamamlanan Aktivite Oranı %d", i),
      capability = sprintf("measure.oran_%d", i), role = "measure",
      entity = "project", aggregate = "median", additive = FALSE,
      unit = "yuzde", filterable = TRUE, match = "numeric"
    )),
    sprintf("Kolon_%d", seq_len(150L))
  )
  adaylar <- lapply(seq_len(5L), function(i) list(
    id = sprintf("q%03d", i), name = sprintf("Proje Özeti %d", i),
    description = "Bir satır bir proje özetidir.",
    meta = list(entity = "project", column_meta = sutunlar)
  ))

  cfg <- .pk_selhard_cfg(pass_b_chars = 24000L)
  bloklar <- pk_select_pass_b_blocks(adaylar, cfg)

  expect_false(isTRUE(bloklar$truncated))
  expect_true(isTRUE(bloklar$clipped))
  # HİÇBİR ADAY KAYBOLMAZ: geri alınamaz olan budur.
  expect_identical(bloklar$ids, sprintf("q%03d", seq_len(5L)))
  for (kimlik in bloklar$ids) {
    expect_true(grepl(sprintf("--- SORGU %s ---", kimlik), bloklar$text, fixed = TRUE))
  }
  # Kırpma AÇIKÇA işaretlenir; model kalan sütunların var olduğunu bilir.
  expect_true(grepl("sütun daha", bloklar$text, fixed = TRUE))
  expect_true(nchar(bloklar$text) <= 24000L)

  # Yük zaten sığıyorsa TAM AYRINTI yolu birebir korunur (kırpma yoktur).
  dar_sutun <- lapply(adaylar, function(aday) {
    aday$meta$column_meta <- sutunlar[seq_len(10L)]
    aday
  })
  genis <- pk_select_pass_b_blocks(dar_sutun, .pk_selhard_cfg(pass_b_chars = 120000L))
  expect_false(isTRUE(genis$clipped))
  expect_false(isTRUE(genis$truncated))
  expect_false(grepl("sütun daha", genis$text, fixed = TRUE))
})

test_that("UYDURULAN yetenek kimliği isteği öldürmez; kalan iddialar doğrulanır", {
  # ÖLÇÜLEN ÜRETİM ARIZASI: DOĞRU sorgu %95 güvenle seçiliyor, model
  # `dimension.project` gibi kayıt defterinde OLMAYAN bir kimlik yazıyor ve TÜM
  # istek reddediliyordu. Uydurulmuş kimlik, sorgunun soruyu cevaplayıp
  # cevaplayamadığı hakkında kanıt DEĞİLDİR; üstelik hiç `requirements` beyan
  # etmeyen bir model `not_asserted` ile ilerleyebiliyordu (asimetrik ceza).
  kayit <- pk_select_test_registry()
  kimlikler <- pk_select_capability_ids(kayit)
  sorgu <- pk_select_test_library()[[1]]
  yetenek <- .pk_select_query_capabilities(sorgu)
  expect_true(length(yetenek) > 0L)

  istek <- list(
    entity = "project", measures = list(yetenek[1]), dates = list(),
    dimensions = list("dimension.project"), group_by = list(), unsupported = list()
  )

  ham <- pk_select_validate_requirements(sorgu, istek, kimlikler)
  expect_identical(ham$status, "unknown_capability")
  expect_identical(ham$unknown, "dimension.project")

  temiz <- pk_select_drop_unknown_requirements(istek, ham$unknown)
  expect_false(is.null(temiz))
  expect_false("dimension.project" %in% temiz$dimensions)
  # DOĞRULANABİLİR iddia KORUNUR: düşürme yalnızca bilinmeyeni siler.
  expect_true(yetenek[1] %in% temiz$measures)

  yeniden <- pk_select_validate_requirements(sorgu, temiz, kimlikler)
  expect_false(identical(yeniden$status, "unknown_capability"))

  # Kalan iddia SORGUDA YOKSA kapı hâlâ kapanır (gevşetme değildir).
  eksik <- list(
    entity = NULL, measures = list(), dates = list(),
    dimensions = list(setdiff(kimlikler, yetenek)[1], "dimension.project"),
    group_by = list(), unsupported = list()
  )
  eksik_ham <- pk_select_validate_requirements(sorgu, eksik, kimlikler)
  expect_identical(eksik_ham$status, "unknown_capability")
  eksik_temiz <- pk_select_drop_unknown_requirements(eksik, eksik_ham$unknown)
  eksik_son <- pk_select_validate_requirements(sorgu, eksik_temiz, kimlikler)
  expect_identical(eksik_son$status, "capability_missing")
})

test_that("beyan edilmemiş yetenek VARSAYILAN olarak reddetmez, AÇIKLANIR", {
  # ÖLÇÜLEN ÜRETİM ARIZASI: `capability` beyanı gerçek kütüphanede kaçınılmaz
  # biçimde KISMİDİR (yüzlerce sorgu, binlerce sütun). Beyanın YOKLUĞU yeteneğin
  # yokluğunun kanıtı değildir; kapı yine de DOĞRU seçilmiş sorguyu durduruyordu.
  pk_test_pin_config("MERGEN_PK_REQUIRE_CAPABILITY_MATCH", FALSE)
  expect_false(pk_capability_match_required())
  Sys.setenv(MERGEN_PK_REQUIRE_CAPABILITY_MATCH = "TRUE")
  expect_true(pk_capability_match_required())
  Sys.unsetenv("MERGEN_PK_REQUIRE_CAPABILITY_MATCH")

  kimlikler <- pk_select_capability_ids(pk_select_test_registry())
  lib <- pk_select_test_library()
  yetenek <- .pk_select_query_capabilities(lib[[1]])
  disarida <- setdiff(kimlikler, yetenek)
  expect_true(length(disarida) > 0L)

  # Sorgunun BEYAN ETMEDİĞİ bir ölçü istenir; sorgu yine de yüksek güvenle seçilir.
  gecis_b <- list(
    ok = TRUE, id = "q001", confidence = 95L, reason = "gerekce",
    alternates = list(list(id = "q002", confidence = 20L)),
    requirements = list(
      entity = NULL, measures = disarida[1], dates = character(0),
      dimensions = character(0), group_by = character(0), unsupported = character(0)
    ),
    missing_info = NA_character_
  )
  indeks <- pk_select_library_index(lib)

  gevsek <- pk_select_decide(gecis_b, c("q001", "q002"), indeks, .pk_selhard_cfg(),
                             capability_ids = kimlikler)
  expect_identical(gevsek$status, PK_SELECT_STATUS_AUTO)
  expect_identical(gevsek$capability_status, "capability_missing")
  # Doğrulanamayan iddia SESSİZ KALMAZ.
  expect_true(any(grepl("doğrulanamadı", gevsek$disclosures, fixed = TRUE)))

  # KATI kip istendiğinde eski kapalı-başarısız davranış aynen geri gelir.
  Sys.setenv(MERGEN_PK_REQUIRE_CAPABILITY_MATCH = "TRUE")
  kati <- pk_select_decide(gecis_b, c("q001", "q002"), indeks, .pk_selhard_cfg(),
                           capability_ids = kimlikler)
  expect_identical(kati$status, PK_SELECT_STATUS_CAPABILITY_MISSING)
})

test_that("Geçiş B istemi izinli yetenekleri ADAYLARIN beyanına daraltır", {
  # Küresel kayıt defterinin tamamını ilan etmek, modeli o sorguda BULUNMAYAN
  # bir kimlik yazmaya davet ediyor ve doğru seçim `capability_missing` ile
  # reddediliyordu.
  cfg <- .pk_selhard_cfg()
  lib <- pk_select_test_library()
  adaylar <- list(lib[[1]])
  kimlikler <- pk_select_capability_ids(pk_select_test_registry())
  aday_yetenekleri <- .pk_select_query_capabilities(lib[[1]])
  disarida <- setdiff(kimlikler, aday_yetenekleri)
  expect_true(length(disarida) > 0L)

  mesajlar <- pk_select_pass_b_messages(
    "soru", adaylar,
    pk_select_follow_up_context(NULL, NULL, "q001", cfg),
    cfg, capability_ids = kimlikler
  )
  sistem <- mesajlar[[1]]$content

  for (kimlik in aday_yetenekleri) {
    expect_true(grepl(kimlik, sistem, fixed = TRUE))
  }
  for (kimlik in disarida) {
    expect_false(grepl(sprintf("\n%s (rol:", kimlik), sistem, fixed = TRUE))
  }
})

test_that("Geçiş B istemi varlık türlerini yetenek kimliğinden AYIRIR", {
  cfg <- .pk_selhard_cfg()
  lib <- pk_select_test_library()
  adaylar <- list(lib[[1]], lib[[2]])

  mesajlar <- pk_select_pass_b_messages(
    "soru", adaylar,
    pk_select_follow_up_context(NULL, NULL, c("q001", "q002"), cfg),
    cfg, capability_ids = pk_select_capability_ids(pk_select_test_registry())
  )
  sistem <- mesajlar[[1]]$content

  expect_true(grepl("IZINLI VARLIK TURLERI", sistem, fixed = TRUE))
  expect_true(grepl("yetenek kimligi\nDEGILDIR", sistem, fixed = TRUE) ||
                grepl("yetenek kimligi DEGILDIR", sistem, fixed = TRUE))
  # Yetenek kimlikleri ROLLERİYLE gönderilir (aksi hâlde model doğru alanı
  # seçemez ve geçerli aday `capability_missing` ile reddedilir).
  expect_true(grepl("labor.planned_hours (rol: measure)", sistem, fixed = TRUE))
  # ÖRNEK ASLA GERÇEK ADAY KİMLİĞİ TAŞIMAZ.
  #
  # Sıcaklık 0'da model zorunlu JSON bloğunu AYNEN kopyalayabilir. Gerçek
  # kimlikli bir kopya `pk_select_parse_pass_b()` kapısından GEÇER ve sorudan
  # BAĞIMSIZ olarak ilk geri getirme adayı otomatik çalışırdı. Yer tutucu
  # kimlik `id %in% candidate_ids` kapısında düşer ve onarım yoluna gider.
  expect_false(grepl("\"id\":\"q001\"", sistem, fixed = TRUE))
  expect_true(grepl("\"id\":\"ORNEK_KIMLIK_1\"", sistem, fixed = TRUE))
  # Alternatif SAYISI yine gerçek aday sayısını yansıtır (kural şekli korunur).
  expect_true(grepl("\"id\":\"ORNEK_KIMLIK_2\"", sistem, fixed = TRUE))
  expect_false(grepl("q042", sistem, fixed = TRUE))

  # Kopyalanan örnek AYRIŞTIRICIDAN GEÇMEZ.
  kopya <- paste0(
    "{\"id\":\"ORNEK_KIMLIK_1\",\"confidence\":78,\"reason\":\"Kisa gerekce\",",
    "\"alternates\":[{\"id\":\"ORNEK_KIMLIK_2\",\"confidence\":50}],",
    "\"requirements\":{\"entity\":null,\"measures\":[],\"dates\":[],",
    "\"dimensions\":[],\"group_by\":[],\"unsupported\":[]},",
    "\"missing_info\":null}"
  )
  ayrisik <- pk_select_parse_pass_b(kopya, c("q001", "q002"))
  expect_false(isTRUE(ayrisik$ok))
})

test_that("Geçiş A TOPLAM bütçesi aşılırsa kapalı başarısız olunur", {
  # KUSUR: alan başına kırpma sorgu SAYISINI sınırlamıyordu; daha büyük bir
  # kütüphane Geçiş A'yı seçici modelin bağlamının ötesine itebiliyor ve
  # satırlar sessizce düşüyordu. Görünmeyen bir sorgu asla seçilemez; bu
  # `skipped` ile aynı sınıf recall kaybıdır.
  # Gerçek kütüphane 169 sorguludur; sentetik kütüphane bilinçli olarak
  # BÜYÜTÜLÜR ki toplam bütçe kapısı anlamlı biçimde sınansın.
  taban <- pk_select_test_library()
  lib <- list()
  for (k in seq_len(40L)) {
    for (q in taban) {
      q$id <- sprintf("%s_kopya%02d", as.character(q$id %||% "q")[1], k)
      lib[[length(lib) + 1L]] <- q
    }
  }

  # SIĞAR VAKASI FİKSTÜR GENİŞLİĞİNDEN BAĞIMSIZDIR.
  #
  # Sabit `pass_a_chars` (60000) kullanmak, fikstür büyüdüğünde testi GERÇEK
  # bir gerileme olmadan kırmış olurdu. Önce yük ölçülür, sonra bütçe ölçülen
  # değerin ÜSTÜNE ayarlanır: "sığdığında kırpma YOK" sözleşmesi böylece
  # fikstür boyutundan bağımsız sınanır.
  # BÜTÇE GEÇERLİ ARALIKTA OLMALIDIR: `pk_select_normalize_config()` üst sınırı
  # 400000'dir. 10.000.000 REDDEDİLİYOR, alan yapılandırmadan DÜŞÜYOR ve ölçüm
  # sessizce 60000 varsayılanına dönüyordu; büyüyen bir fikstürde bu, ölçümün
  # kendisinin `truncated` raporlamasına yol açardı.
  olcum <- pk_select_pass_a_payload(lib, .pk_selhard_cfg(pass_a_chars = 400000L))
  expect_false(isTRUE(olcum$truncated))
  expect_true(olcum$chars > 0L)

  genis <- pk_select_pass_a_payload(
    lib, .pk_selhard_cfg(pass_a_chars = as.integer(olcum$chars) + 1000L)
  )
  expect_false(isTRUE(genis$truncated))
  expect_true(genis$chars > 0L)

  # EN DAR BASAMAK ölçülür (kimlik + isim + açıklama); merdivenin tabanı budur.
  # Bütçe ondan küçükse hiçbir seyreltme yetmez ve kapalı başarısızlık KORUNUR.
  taban <- pk_select_pass_a_payload(lib, .pk_selhard_cfg(pass_a_chars = 2000L))
  expect_identical(taban$compaction, "asgari")

  # Bütçe gerçek yükün ALTINDA ama tabanın ÜSTÜNDE: yük SEYRELTİLİR, satır
  # DÜŞÜRÜLMEZ. Eskiden burada TÜM istek reddediliyordu; oysa bütçe aşımı bir
  # kütüphane hatası değil, istem şekillendirme durumudur. Geri alınamaz olan
  # tek şey bir sorgunun GÖRÜNMEZ olmasıdır.
  orta_butce <- as.integer(taban$chars) + 500L
  orta <- pk_select_pass_a_payload(lib, .pk_selhard_cfg(pass_a_chars = orta_butce))
  expect_false(isTRUE(orta$truncated))
  expect_false(identical(orta$compaction, "tam"))
  expect_true(orta$chars <= orta_butce)
  expect_identical(orta$ids, genis$ids)

  # En dar basamak bile sığmıyorsa kapalı başarısızlık KORUNUR.
  dar_butce <- 2000L
  dar <- taban
  expect_true(isTRUE(dar$truncated))
  expect_identical(dar$budget, dar_butce)
  expect_true(dar$chars > dar$budget)

  # Satırlar SESSİZCE kırpılmaz: kimlikler korunur, karar katmanı reddeder.
  expect_identical(dar$ids, genis$ids)

  # KARAR KATMANININ GERÇEK ÇIKTISI DA DENETLENİR.
  #
  # Yükün `truncated = TRUE` raporlaması tek başına yetmez: asıl sözleşme
  # çalıştırıcının KAPALI BAŞARISIZ olmasıdır. Bu doğrulanmazsa, bayrağı yok
  # sayan bir gerileme (kırpılmış kütüphaneyle seçime devam etmek) bu dosyadan
  # sessizce gecerdi.
  karar <- pk_select_run(
    user_prompt = "sentetik soru",
    library = lib,
    cfg = .pk_selhard_cfg(pass_a_chars = dar_butce),
    llm_fn = function(...) stop("LLM CAGRILMAMALIYDI", call. = FALSE)
  )
  expect_identical(karar$status, PK_SELECT_STATUS_LIBRARY_ERROR)
  expect_true(grepl("secim", karar$message_tr, fixed = TRUE) ||
                grepl("seçim", karar$message_tr, fixed = TRUE))
})

test_that("uydurulan yetenek düşürülünce karar bunu AÇIKÇA bildirir", {
  # Kanıt yalnızca reddetme metnine iliştirilen `errors` alanında kalmamalıdır:
  # kapı GEÇİLDİĞİNDE de kullanıcı hangi iddianın yok sayıldığını görmelidir.
  pk_test_pin_config("MERGEN_PK_REQUIRE_CAPABILITY_MATCH", FALSE)
  kimlikler <- pk_select_capability_ids(pk_select_test_registry())
  lib <- pk_select_test_library()
  yetenek <- .pk_select_query_capabilities(lib[[1]])

  gecis_b <- list(
    ok = TRUE, id = "q001", confidence = 95L, reason = "gerekce",
    alternates = list(list(id = "q002", confidence = 20L)),
    requirements = list(
      entity = NULL, measures = yetenek[1], dates = character(0),
      dimensions = "dimension.project", group_by = character(0),
      unsupported = character(0)
    ),
    missing_info = NA_character_
  )

  karar <- pk_select_decide(gecis_b, c("q001", "q002"),
                            pk_select_library_index(lib), .pk_selhard_cfg(),
                            capability_ids = kimlikler)

  expect_identical(karar$status, PK_SELECT_STATUS_AUTO)
  expect_true(any(grepl("dimension.project", karar$disclosures, fixed = TRUE)))
})

test_that("Geçiş B daraltılmış yükü bildirilen bütçeyi AŞMAZ", {
  # `SUTUNLAR: ` öneki paya dâhil değilken aday başına sabit bir taşma kalıyordu.
  sutunlar <- setNames(
    lapply(seq_len(200L), function(i) list(
      label = sprintf("Ölçü %d", i), capability = sprintf("measure.m_%d", i),
      role = "measure", entity = "project", unit = "adet"
    )),
    sprintf("Kolon_%d", seq_len(200L))
  )
  adaylar <- lapply(seq_len(5L), function(i) list(
    id = sprintf("q%03d", i), name = sprintf("Sorgu %d", i),
    description = "Kısa açıklama.", meta = list(column_meta = sutunlar)
  ))

  for (butce in c(4000L, 8000L, 20000L)) {
    bloklar <- pk_select_pass_b_blocks(adaylar, .pk_selhard_cfg(pass_b_chars = butce))
    expect_false(isTRUE(bloklar$truncated))
    expect_length(bloklar$ids, 5L)
    expect_true(nchar(bloklar$text) <= butce,
                info = sprintf("bütçe %d aşıldı: %d", butce, nchar(bloklar$text)))
  }
})

test_that("sütun kırpması TEK tanım sığmadığında da bütçeyi AŞMAZ", {
  # Geri adım döngüsü `alinan > 1` iken durur; ilk tanım + işaret bütçeyi
  # aşınca fonksiyon taşan metni AYNEN döndürüyordu.
  tanimlar <- sprintf("Kolon_%d (yetenek=measure.m_%d)", 1:9, 1:9)
  for (butce in c(10L, 20L, 30L, 45L, 60L)) {
    metin <- pk_select_fit_column_defs(tanimlar, butce)
    expect_true(nchar(metin) <= butce,
                info = sprintf("bütçe %d aşıldı: %d", butce, nchar(metin)))
  }
})

test_that("blok toplamı ayraçları YALNIZCA bloklar arasında sayar", {
  # Her bloğa 2 karakter eklemek, tam bütçe boyundaki tek bloğu taşmış sayıp
  # gereksiz kırpma tetikliyordu.
  aday <- list(id = "q001", name = "Sorgu", description = "Kisa.")
  tek <- pk_select_pass_b_block(aday, .pk_selhard_cfg())
  bloklar <- pk_select_pass_b_blocks(
    list(aday), .pk_selhard_cfg(pass_b_chars = nchar(tek))
  )
  expect_false(isTRUE(bloklar$clipped))
  expect_identical(bloklar$text, tek)
})

test_that("kırpma önceliği ETİKET METNİNDEN değil metadata'dan okunur", {
  # `yetenek=` geçen bir ETİKET, gerçek yetenek sütununu payın dışına itiyordu.
  sutunlar <- list(
    Tuzak = list(label = "yetenek=measure.sahte olan alan", role = "dimension"),
    Gercek = list(label = "Kalan işçilik", capability = "measure.kalan",
                  role = "measure", entity = "project")
  )
  aday <- list(id = "q001", name = "Sorgu", description = "Kisa.",
               meta = list(column_meta = sutunlar))

  taban <- pk_select_pass_b_block(aday, .pk_selhard_cfg(), 0)
  tam <- pk_select_pass_b_block(aday, .pk_selhard_cfg())
  # Yalnızca tek tanıma yetecek bir pay: yetenek taşıyan sütun kalmalıdır.
  pay <- nchar(tam) - nchar(taban) - 30L
  daraltilmis <- pk_select_pass_b_block(aday, .pk_selhard_cfg(), pay)
  expect_true(grepl("measure.kalan", daraltilmis, fixed = TRUE))
})

test_that("ilan edilen yetenekler KAPININ okuduğu beyanla aynıdır", {
  # Ham `column_meta` taraması, iki sütunun tercihsiz paylaştığı yeteneği de
  # ilan ediyordu; kapı onu beyan edilmemiş sayıp doğru seçimi reddediyordu.
  sutunlar <- list(
    A = list(label = "A", capability = "measure.paylasilan", role = "measure"),
    B = list(label = "B", capability = "measure.paylasilan", role = "measure"),
    C = list(label = "C", capability = "measure.tekil", role = "measure")
  )
  aday <- list(id = "q001", name = "Sorgu", description = "Kisa.",
               meta = list(column_meta = sutunlar))

  izinli <- c("measure.paylasilan", "measure.tekil")
  ilan <- pk_select_candidate_capability_ids(list(aday), izinli)
  expect_identical(ilan, "measure.tekil")
  expect_identical(names(pk_meta_declared_capabilities(aday)), "measure.tekil")
})

test_that("kayıt defteri YOKKEN uydurma kimlik temizliği kapıyı AÇMAZ", {
  # İzinli liste boşken TÜM kimlikler bilinmeyen görünür; hepsi düşünce nesne
  # boşalır ve kanıtsız bir `auto` üretilirdi.
  pk_test_pin_config("MERGEN_PK_REQUIRE_CAPABILITY_MATCH", FALSE)
  lib <- pk_select_test_library()
  gecis_b <- list(
    ok = TRUE, id = "q001", confidence = 95L, reason = "gerekce",
    alternates = list(list(id = "q002", confidence = 20L)),
    requirements = list(
      entity = NULL, measures = "dimension.project", dates = character(0),
      dimensions = character(0), group_by = character(0), unsupported = character(0)
    ),
    missing_info = NA_character_
  )

  karar <- pk_select_decide(gecis_b, c("q001", "q002"),
                            pk_select_library_index(lib), .pk_selhard_cfg(),
                            capability_ids = character(0))
  expect_identical(karar$status, PK_SELECT_STATUS_UNKNOWN_CAPABILITY)
})

test_that("temizlenen gereksinim SAKLANAN nesneye de yazılır", {
  # Derin Düşünme ve rakip filtresi saklanan nesneyi yeniden doğrular;
  # uydurulmuş kimlik kalırsa geçerli alternatiflerin TAMAMI elenirdi.
  pk_test_pin_config("MERGEN_PK_REQUIRE_CAPABILITY_MATCH", FALSE)
  kimlikler <- pk_select_capability_ids(pk_select_test_registry())
  lib <- pk_select_test_library()
  yetenek <- .pk_select_query_capabilities(lib[[1]])

  gecis_b <- list(
    ok = TRUE, id = "q001", confidence = 95L, reason = "gerekce",
    alternates = list(list(id = "q002", confidence = 20L)),
    requirements = list(
      entity = NULL, measures = yetenek[1], dates = character(0),
      dimensions = "dimension.project", group_by = character(0),
      unsupported = character(0)
    ),
    missing_info = NA_character_
  )

  karar <- pk_select_decide(gecis_b, c("q001", "q002"),
                            pk_select_library_index(lib), .pk_selhard_cfg(),
                            capability_ids = kimlikler)
  saklanan <- unlist(karar$requirements[c("measures", "dates", "dimensions",
                                          "group_by")], use.names = FALSE)
  expect_false("dimension.project" %in% saklanan)
})

test_that("kütüphanede tek sorgu varken taban 2'ye ÇIKARILMAZ", {
  # "En az 2 aday" talimatı, listede tek sorgu varken modeli kimlik uydurmaya
  # itiyor ve cevap `malformed` sayılıyordu.
  cfg <- .pk_selhard_cfg()
  tekil <- list(list(id = "q001", name = "Sorgu", description = "Kisa."))
  yuk <- pk_select_pass_a_payload(tekil, cfg)
  mesajlar <- pk_select_pass_a_messages(
    "soru", yuk, pk_select_follow_up_context(NULL, NULL, NULL, cfg), cfg
  )
  expect_false(grepl("En az 2 aday", mesajlar[[1]]$content, fixed = TRUE))

  ayrisik <- pk_select_parse_pass_a(
    '{"candidates":["q001"]}', yuk$ids,
    expected_n = cfg$recall_n, min_n = min(2L, cfg$recall_n, length(yuk$ids))
  )
  expect_true(ayrisik$ok)
  expect_identical(ayrisik$ids, "q001")
})

test_that("Geçiş A SIFIR aday beklentisini REDDEDER", {
  # Alt sınır 0'a düşünce geçerli cevap `character(0)`e kırpılıp OK sayılıyordu.
  ayrisik <- pk_select_parse_pass_a('{"candidates":["q001"]}', c("q001"),
                                    expected_n = 0L)
  expect_false(ayrisik$ok)
})

test_that("MERGEN_PK_REQUIRE_CAPABILITY_MATCH ASCII katlama ile okunur", {
  # Türkçe yerelde `tolower("ACIK")` "acık" verir; katı kip sessizce kapanırdı.
  pk_test_pin_config("MERGEN_PK_REQUIRE_CAPABILITY_MATCH", FALSE)
  Sys.setenv(MERGEN_PK_REQUIRE_CAPABILITY_MATCH = "ACIK")
  expect_true(pk_capability_match_required())
})

test_that("merdiven basamağı yapılandırılmış bütçeyi GENİŞLETMEZ", {
  # Sabit değeri körlemesine yazmak, operatörün daha dar verdiği alanı büyütür;
  # en dar basamak bir öncekinden geniş olur ve sığacak yük reddedilirdi.
  dar <- list(name_chars = 20L, desc_chars = 40L, keyword_chars = 10L,
              sample_chars = 15L, sample_n = 1L, label_chars = 5L)
  for (basamak in PK_SELECT_PASS_A_LADDER) {
    cfg <- pk_select_pass_a_level_cfg(dar, basamak)
    for (alan in names(dar)) {
      expect_true(cfg[[alan]] <= dar[[alan]],
                  info = sprintf("%s / %s", basamak$id, alan))
    }
  }
})

test_that("kayıt defteri YÜKLÜ DEĞİLKEN varlık-yalnız nesne kapıyı AÇMAZ", {
  # Boş izinli listede TÜM kimlikler bilinmeyen görünür; `entity` hayatta kalsa
  # bile geriye doğrulanabilir bir yetenek iddiası KALMAZ.
  pk_test_pin_config("MERGEN_PK_REQUIRE_CAPABILITY_MATCH", FALSE)
  lib <- pk_select_test_library()
  gecis_b <- list(
    ok = TRUE, id = "q001", confidence = 95L, reason = "gerekce",
    alternates = list(list(id = "q002", confidence = 20L)),
    requirements = list(
      entity = "project", measures = "dimension.project", dates = character(0),
      dimensions = character(0), group_by = character(0), unsupported = character(0)
    ),
    missing_info = NA_character_
  )

  karar <- pk_select_decide(gecis_b, c("q001", "q002"),
                            pk_select_library_index(lib), .pk_selhard_cfg(),
                            capability_ids = character(0))
  expect_identical(karar$status, PK_SELECT_STATUS_UNKNOWN_CAPABILITY)
})

test_that("Geçiş B kırpma bilgisi HER başarısızlık yolunda taşınır", {
  # Zaman aşımı / LLM erişilemez dalları da metadata daraltılmışken oluşur;
  # kullanıcı seyreltme açıklamasını görmelidir.
  sutunlar <- setNames(
    lapply(seq_len(200L), function(i) list(
      label = sprintf("Ölçü %d", i), capability = sprintf("measure.m_%d", i),
      role = "measure", entity = "project", unit = "adet"
    )),
    sprintf("Kolon_%d", seq_len(200L))
  )
  adaylar <- lapply(seq_len(5L), function(i) list(
    id = sprintf("q%03d", i), name = sprintf("Sorgu %d", i),
    description = "Kısa açıklama.", meta = list(column_meta = sutunlar)
  ))
  cfg <- .pk_selhard_cfg(pass_b_chars = 4000L)

  for (durum in c(PK_SELECT_STATUS_TIMEOUT, PK_SELECT_STATUS_LLM_UNAVAILABLE)) {
    sonuc <- pk_select_run_pass_b(
      "soru", adaylar, vapply(adaylar, function(a) a$id, character(1)),
      pk_select_follow_up_context(NULL, NULL, NULL, cfg),
      cfg, pk_select_library_index(adaylar),
      llm_fn = local({
        d <- durum
        function(...) stop(if (identical(d, PK_SELECT_STATUS_TIMEOUT)) "timeout" else "connection refused",
                           call. = FALSE)
      })
    )
    expect_false(isTRUE(sonuc$ok))
    expect_true(isTRUE(sonuc$blocks_clipped), info = durum)
  }
})
