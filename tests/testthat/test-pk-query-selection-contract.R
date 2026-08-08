# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-query-selection-contract.R
# Açıklama: Faz 5 (§5.2) — iki geçişli sorgu seçimi sözleşmesi.
#           Tamamen çevrimdışı ve belirlenimcidir: DB, LLM, tarayıcı, SSO, ağ
#           veya gizli değer GEREKMEZ. LLM `llm_fn` ile ENJEKTE edilir.
#
# §7'nin bu dosyadan istedikleri:
#   - çözümlenmiş `MERGEN_PK_SELECT_RECALL_N` (asgari 2) HER İKİ geçişi de
#     kontrol eder; varsayılan olmayan 3 değeri onurlandırılır;
#   - ikiden az doğrulanmış güven -> `no_runner_up`;
#   - hiçbir yerde literal beş yok;
#   - kararlı kimlikler ve KENDİ güvenli alternatifler;
#   - sınırlı takip bağlamı + önceki kararlı sorgu kimliği Geçiş A'ya girer ve
#     eksiltili takipte KIRPMADAN ÖNCE korunur.
#
# Ek olarak Faz 4 incelemesinin "ölü kod" bulgusunu tekrarlamamak için hattın
# GERÇEKTEN çağrıldığı hem statik hem davranışsal olarak kanıtlanır.
# ==============================================================================

pk_select_source_chain_for_tests()

.pk_sel_lib <- function() pk_select_test_library()

# Yetenek kayıt defteri testte AÇIKÇA kurulur; checkout'taki gerçek defter
# değişse bile bu dosyanın kararları sabit kalır.
.pk_sel_registry <- function() pk_select_test_registry()

.pk_sel_cfg <- function(...) {
  ust <- list(...)
  taban <- list(
    timeout_sec = 20L, recall_n = 5L, min_confidence = 50L, min_margin = 15L,
    disagree_penalty = 15L, desc_chars = 220L, sample_chars = 120L,
    sample_n = 2L, history_turns = 2L
  )
  if (length(ust)) taban[names(ust)] <- ust
  pk_select_normalize_config(taban)
}

.PK_SEL_PASS_A <- "{\"candidates\":[\"q001\",\"q002\",\"q003\"]}"

.pk_sel_pass_b <- function(id = "q002", confidence = 85, alternates = "[{\"id\":\"q001\",\"confidence\":40}]",
                           requirements = "null", missing_info = "null") {
  sprintf(
    "{\"id\":\"%s\",\"confidence\":%s,\"reason\":\"gerekce\",\"alternates\":%s,\"requirements\":%s,\"missing_info\":%s}",
    id, confidence, alternates, requirements, missing_info
  )
}

# ------------------------------------------------------------------------------
# 1. Çözümlenmiş RECALL_N her iki geçişi de kontrol eder
# ------------------------------------------------------------------------------

test_that("MERGEN_PK_SELECT_RECALL_N asgari 2'dir ve 1 KABUL EDİLMEZ", {
  pk_select_with_env(c(MERGEN_PK_SELECT_RECALL_N = "1"), {
    cfg <- pk_select_config()
    expect_false(
      cfg$valid,
      info = paste(
        "Tek adaylık getirim, ikinci adayın güvenini üretemez ve",
        "MERGEN_PK_SELECT_MIN_MARGIN kapısı uygulanamaz hâle gelir;",
        "bu yüzden 1 sessizce varsayılana DÜŞMEMELİ, hata olmalıdır."
      )
    )
    expect_true(any(grepl("MERGEN_PK_SELECT_RECALL_N", cfg$errors, fixed = TRUE)))
  })

  # Geçersiz yapılandırma otomatik seçimi KAPATIR (kapalı başarısızlık).
  karar <- pk_select_decide(NULL, c("q001"), list(), .pk_sel_cfg(recall_n = 1L))
  expect_identical(karar$status, PK_SELECT_STATUS_CONFIG_ERROR)
})

test_that("çözümlenen RECALL_N değeri Geçiş A'nın İSTEDİĞİ sayıyı belirler", {
  for (n in c(2L, 3L, 4L)) {
    cfg <- .pk_sel_cfg(recall_n = n)
    payload <- pk_select_pass_a_payload(.pk_sel_lib(), cfg)
    mesajlar <- pk_select_pass_a_messages(
      "soru", payload,
      pk_select_follow_up_context(NULL, NULL, payload$ids, cfg), cfg
    )
    sistem <- mesajlar[[1]]$content

    expect_true(
      grepl(sprintf("Tam olarak %d adet aday", n), sistem, fixed = TRUE),
      info = sprintf("Geçiş A istemi çözümlenen %d değerini taşımalıdır.", n)
    )
  }
})

test_that("varsayılan OLMAYAN değer 3 her iki geçişte de onurlandırılır", {
  cfg <- .pk_sel_cfg(recall_n = 3L)
  stub <- pk_select_stub_llm(list(
    # Model DÖRT aday döndürse bile Geçiş B'ye yalnızca 3 tanesi gider.
    "{\"candidates\":[\"q001\",\"q002\",\"q003\",\"q004\"]}",
    .pk_sel_pass_b()
  ))

  karar <- pk_select_run("sentetik soru", .pk_sel_lib(), llm_fn = stub$fn, cfg = cfg)

  expect_equal(length(karar$candidate_ids), 3L)
  expect_identical(karar$candidate_ids, c("q001", "q002", "q003"))

  # Geçiş B istemi YALNIZCA bu üç adayı içermelidir.
  gecis_b_sistem <- stub$log$calls[[2]]$system
  expect_true(grepl("--- SORGU q001 ---", gecis_b_sistem, fixed = TRUE))
  expect_true(grepl("--- SORGU q003 ---", gecis_b_sistem, fixed = TRUE))
  expect_false(
    grepl("--- SORGU q004 ---", gecis_b_sistem, fixed = TRUE),
    info = "Kırpılan aday Geçiş B yüküne SIZMAMALIDIR."
  )
  expect_true(grepl("Tam olarak 3 adet aday", stub$log$calls[[1]]$system, fixed = TRUE))
})

test_that("eksik alan Geçiş A satırına düz 'NA' olarak SIZMAZ", {
  # Ölçülerek bulundu: `paste(NA_character_)` ve `as.character(character(0))[1]`
  # düz "NA" üretiyordu; bu değer modele sorgunun ADI gibi görünürdü.
  cfg <- .pk_sel_cfg()
  bozuk <- list(
    id = "qX", name = NA_character_, description = character(0),
    meta = list(keywords = NA_character_, sample_questions = NULL)
  )

  satir <- pk_select_pass_a_line(bozuk, cfg)
  expect_false(
    grepl("NA", satir, fixed = TRUE),
    info = sprintf("Eksik alan yokluk olmalıdır, 'NA' metni değil. Satır: %s", satir)
  )
  expect_true(startsWith(satir, "qX | "))

  expect_identical(.pk_select_clip(NA_character_, 50L), "")
  expect_identical(.pk_select_inline(character(0)), "")
  expect_identical(.pk_select_inline(NA_character_), "")
})

test_that("hiçbir geçişte LİTERAL BEŞ yoktur (§5.2)", {
  kok <- resolve_repo_root_for_tests()
  for (dosya in PK_SELECT_RUNTIME_FILES) {
    yol <- file.path(kok, "R", dosya)
    ham <- readBin(yol, "raw", file.info(yol)$size)
    txt <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")

    # Yorum satırları hariç tutulur: açıklama metninde "5" geçebilir.
    satirlar <- unlist(strsplit(txt, "\n", fixed = TRUE))
    satirlar <- satirlar[!grepl("^\\s*#", satirlar)]
    kod <- paste(satirlar, collapse = "\n")

    for (desen in c("recall_n = 5", "recall_n <- 5", "n = 5L", "head(aday, 5")) {
      expect_false(
        grepl(desen, kod, fixed = TRUE, useBytes = TRUE),
        info = sprintf("%s içinde sabit aday sayısı bulundu: %s", dosya, desen)
      )
    }
  }
})

# ------------------------------------------------------------------------------
# 2. Kararlı kimlikler (D13)
# ------------------------------------------------------------------------------

test_that("her iki geçiş de KARARLI kimlik taşır; liste KONUMU asla kullanılmaz", {
  cfg <- .pk_sel_cfg()
  payload <- pk_select_pass_a_payload(.pk_sel_lib(), cfg)

  # Geçiş A satırları `q001` ile başlar, `ID: 1` ile değil.
  expect_true(grepl("^q001 \\| ", payload$text))
  expect_false(grepl("ID: 1", payload$text, fixed = TRUE))
  expect_identical(payload$ids, c("q001", "q002", "q003", "q004"))

  # Geçiş A çıktısında KONUM numarası verilirse kabul EDİLMEZ.
  ayrisik <- pk_select_parse_pass_a("{\"candidates\":[\"1\",\"2\"]}", payload$ids)
  expect_equal(length(ayrisik$ids), 0L)
  expect_setequal(ayrisik$unknown, c("1", "2"))
})

test_that("kütüphane YENİDEN SIRALANDIĞINDA seçim değişmez (D13)", {
  cfg <- .pk_sel_cfg()
  lib <- .pk_sel_lib()

  sec <- function(kutuphane) {
    stub <- pk_select_stub_llm(list(.PK_SEL_PASS_A, .pk_sel_pass_b(id = "q002")))
    pk_select_run("sentetik soru", kutuphane, llm_fn = stub$fn, cfg = cfg)
  }

  duz <- sec(lib)
  ters <- sec(rev(lib))

  expect_identical(duz$status, PK_SELECT_STATUS_AUTO)
  expect_identical(duz$query_id, "q002")
  expect_identical(ters$query_id, duz$query_id)
  expect_identical(ters$confidence, duz$confidence)
})

test_that("aday kümesinde OLMAYAN kimlik reddedilir", {
  ayrisik <- pk_select_parse_pass_b(
    .pk_sel_pass_b(id = "q999"), c("q001", "q002")
  )
  expect_false(ayrisik$ok)
  expect_true(grepl("q999", ayrisik$error, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# 3. Alternatifler KENDİ güvenlerini taşır / no_runner_up
# ------------------------------------------------------------------------------

test_that("ikiden az DOĞRULANMIŞ güven -> no_runner_up (otomatik çalıştırma YOK)", {
  cfg <- .pk_sel_cfg()
  lib <- .pk_sel_lib()

  senaryolar <- list(
    "alternatif yok"          = "[]",
    "güvensiz alternatif"     = "[{\"id\":\"q001\"}]",
    "aralık dışı güven"       = "[{\"id\":\"q001\",\"confidence\":150}]",
    "metin güven"             = "[{\"id\":\"q001\",\"confidence\":\"yuksek\"}]",
    "aday dışı alternatif"    = "[{\"id\":\"q999\",\"confidence\":40}]"
  )

  for (ad in names(senaryolar)) {
    stub <- pk_select_stub_llm(list(
      .PK_SEL_PASS_A,
      .pk_sel_pass_b(confidence = 95, alternates = senaryolar[[ad]])
    ))
    karar <- pk_select_run("sentetik soru", lib, llm_fn = stub$fn, cfg = cfg)

    expect_identical(
      karar$status, PK_SELECT_STATUS_NO_RUNNER_UP,
      info = sprintf("Senaryo '%s': doğrulanmış ikinci aday olmadan marj kapısı atlanamaz.", ad)
    )
    expect_false(identical(karar$status, PK_SELECT_STATUS_AUTO))
    expect_true(length(karar$chips) > 0L, info = "Kullanıcıya seçenek sunulmalıdır.")
  }
})

test_that("alternatifler kendi güvenleriyle okunur ve marj ONLARDAN hesaplanır", {
  ayrisik <- pk_select_parse_pass_b(
    .pk_sel_pass_b(
      confidence = 80,
      alternates = "[{\"id\":\"q003\",\"confidence\":41},{\"id\":\"q001\",\"confidence\":62}]"
    ),
    c("q001", "q002", "q003")
  )

  expect_true(ayrisik$ok)
  # Alternatifler azalan güvene göre KARARLI biçimde sıralanır.
  expect_identical(vapply(ayrisik$alternates, function(a) a$id, character(1)), c("q001", "q003"))
  expect_identical(vapply(ayrisik$alternates, function(a) a$confidence, integer(1)), c(62L, 41L))

  karar <- pk_select_decide(
    ayrisik, c("q001", "q002", "q003"),
    pk_select_library_index(.pk_sel_lib()), .pk_sel_cfg()
  )
  expect_identical(karar$runner_up_id, "q001")
  expect_equal(karar$margin, 18L)
  expect_identical(karar$status, PK_SELECT_STATUS_AUTO)
})

test_that("güven eşiği ve marj eşiği AYRI kapılardır", {
  lib_index <- pk_select_library_index(.pk_sel_lib())
  adaylar <- c("q001", "q002")

  dusuk <- pk_select_parse_pass_b(
    .pk_sel_pass_b(confidence = 45, alternates = "[{\"id\":\"q001\",\"confidence\":10}]"), adaylar
  )
  expect_identical(
    pk_select_decide(dusuk, adaylar, lib_index, .pk_sel_cfg())$status,
    PK_SELECT_STATUS_LOW_CONFIDENCE
  )

  yakin <- pk_select_parse_pass_b(
    .pk_sel_pass_b(confidence = 80, alternates = "[{\"id\":\"q001\",\"confidence\":72}]"), adaylar
  )
  expect_identical(
    pk_select_decide(yakin, adaylar, lib_index, .pk_sel_cfg())$status,
    PK_SELECT_STATUS_CLOSE_MARGIN
  )

  # Eşikler yapılandırılabilir: marj 5'e düşürülünce aynı girdi otomatikleşir.
  expect_identical(
    pk_select_decide(yakin, adaylar, lib_index, .pk_sel_cfg(min_margin = 5L))$status,
    PK_SELECT_STATUS_AUTO
  )
})

test_that("MIN_CONFIDENCE + MIN_MARGIN > 100 yapılandırması KAPALI başarısız olur", {
  cfg <- .pk_sel_cfg(min_confidence = 90L, min_margin = 20L)
  expect_false(
    cfg$valid,
    info = "Bu yapılandırmada hiçbir aday çifti kapıyı geçemez; sessiz 'hep sor' yerine açık hata."
  )
})

# ------------------------------------------------------------------------------
# 4. Yetenek doğrulaması (kesin kimlik, SQL'den ÖNCE)
# ------------------------------------------------------------------------------

test_that("planlanan vs kalan işçilik KESİN yetenek kimliğiyle ayrılır", {
  lib <- .pk_sel_lib()
  kayit <- .pk_sel_registry()

  # q001 planlanan işçiliği sunar, q002 kalanı. Kimlikler ayırt eder.
  planlanan <- pk_select_validate_requirements(
    lib[[1]], list(measures = "labor.planned_hours"), pk_select_capability_ids(kayit)
  )
  expect_identical(planlanan$status, "ok")

  # Aynı sorgudan KALAN işçilik istenirse reddedilir: sözlüksel olarak ikisi de
  # "işçilik"tir, ama kimlikler farklıdır.
  kalan_yanlis <- pk_select_validate_requirements(
    lib[[1]], list(measures = "labor.remaining_hours"), pk_select_capability_ids(kayit)
  )
  expect_identical(kalan_yanlis$status, "capability_missing")
  expect_true("labor.remaining_hours" %in% kalan_yanlis$missing)
})

test_that("başlangıç vs bitiş tarihi jenerik bir tarih boolean'ı ile karşılanamaz", {
  lib <- .pk_sel_lib()
  kimlikler <- pk_select_capability_ids(.pk_sel_registry())

  expect_identical(
    pk_select_validate_requirements(lib[[1]], list(dates = "date.project_start"), kimlikler)$status,
    "ok"
  )
  # q001 yalnızca BaslangicTarihi sunar; "2024'te BİTEN" sorusu karşılanamaz.
  expect_identical(
    pk_select_validate_requirements(lib[[1]], list(dates = "date.project_finish"), kimlikler)$status,
    "capability_missing"
  )
})

test_that("kişi/kaynak çıktı boyutu talebi ÖZNE varlığıyla karşılanamaz", {
  lib <- .pk_sel_lib()
  kimlikler <- pk_select_capability_ids(.pk_sel_registry())

  # q001 `entity = project` beyan eder ama kaynak boyutu SUNMAZ.
  sonuc <- pk_select_validate_requirements(
    lib[[1]], list(entity = "project", dimensions = "dimension.resource"), kimlikler
  )
  expect_identical(sonuc$status, "capability_missing")
  expect_true("dimension.resource" %in% sonuc$missing)

  # q002 kaynak boyutunu sunar.
  expect_identical(
    pk_select_validate_requirements(lib[[2]], list(dimensions = "dimension.resource"), kimlikler)$status,
    "ok"
  )
})

test_that("kayıt defterinde OLMAYAN yetenek kimliği uydurulamaz", {
  lib <- .pk_sel_lib()
  kimlikler <- pk_select_capability_ids(.pk_sel_registry())

  sonuc <- pk_select_validate_requirements(
    lib[[2]], list(measures = "iscilik"), kimlikler
  )
  expect_identical(
    sonuc$status, "unknown_capability",
    info = paste(
      "Uydurulmuş kimlik, 'sorgu bu yeteneği sunmuyor' ile AYNI KOVAYA",
      "konmamalıdır: ilki model hatasıdır (onarım anlamlı), ikincisi",
      "yetenek eksikliğidir (başka sorgu gerekir)."
    )
  )
  expect_true("iscilik" %in% sonuc$unknown)
})

test_that("sütun ADI veya ETİKETİ yetenek kimliği olarak kabul edilmez", {
  lib <- .pk_sel_lib()
  kimlikler <- pk_select_capability_ids(.pk_sel_registry())

  for (sahte in c("KalanIscilik_sa", "Kalan İşçilik", "kalan_iscilik")) {
    sonuc <- pk_select_validate_requirements(lib[[2]], list(measures = sahte), kimlikler)
    expect_identical(
      sonuc$status, "unknown_capability",
      info = sprintf("Sütun adı/etiketi anlamsal kimlik yerine geçmemelidir: %s", sahte)
    )
  }
})

test_that("METADATA'SIZ anlamsal gereksinim SQL'den ÖNCE reddedilir", {
  metadatasiz <- list(id = "qX", name = "Metadatasiz", description = "meta yok")
  kimlikler <- pk_select_capability_ids(.pk_sel_registry())

  sonuc <- pk_select_validate_requirements(
    metadatasiz, list(measures = "labor.planned_hours"), kimlikler
  )
  expect_identical(sonuc$status, "capability_missing")
})

test_that("gereksinim BEYAN EDİLMEMİŞSE yetenek kapısı devreye girmez", {
  metadatasiz <- list(id = "qX", name = "Metadatasiz", description = "meta yok")
  kimlikler <- pk_select_capability_ids(.pk_sel_registry())

  for (bos in list(NULL, list(), list(measures = character(0), dates = character(0)))) {
    sonuc <- pk_select_validate_requirements(metadatasiz, bos, kimlikler)
    expect_identical(
      sonuc$status, "not_asserted",
      info = "Doğrulanacak bir iddia yoksa kapı, metadata yokluğunu cezalandırmamalıdır."
    )
    expect_false(sonuc$asserted)
  }
})

test_that("yetenek kapısı GÜVENDEN ÖNCE gelir", {
  lib_index <- pk_select_library_index(.pk_sel_lib())
  adaylar <- c("q001", "q002")

  # %98 güven + net marj: güven kapıları geçilirdi. Yetenek eksikliği yine de
  # SQL'den önce durdurur.
  pass_b <- pk_select_parse_pass_b(
    .pk_sel_pass_b(
      id = "q001", confidence = 98,
      alternates = "[{\"id\":\"q002\",\"confidence\":10}]",
      requirements = "{\"measures\":[\"labor.remaining_hours\"]}"
    ),
    adaylar
  )

  karar <- pk_select_decide(
    pass_b, adaylar, lib_index, .pk_sel_cfg(),
    capability_ids = pk_select_capability_ids(.pk_sel_registry())
  )
  expect_identical(karar$status, PK_SELECT_STATUS_CAPABILITY_MISSING)
})

test_that("yetenek DOĞRULAYICISININ çökmesi 'metadata eksik' gibi raporlanmaz", {
  # Ölçülerek bulundu: doğrulayıcı yüklenmediğinde tryCatch onu sessizce
  # `capability_missing`e çeviriyordu; operatör metadata doldurmaya çalışırken
  # gerçek kusur YÜKLEMEDE kalıyordu.
  ortam <- new.env(parent = globalenv())
  ortam$pk_meta_capability_check <- function(...) stop("dogrulayici coktu")
  environment(pk_select_validate_requirements) <- ortam

  sonuc <- pk_select_validate_requirements(
    .pk_sel_lib()[[2]], list(measures = "labor.remaining_hours"),
    pk_select_capability_ids(.pk_sel_registry())
  )
  expect_identical(sonuc$status, "validator_error")
  expect_true(any(grepl("dogrulayici coktu", sonuc$errors, fixed = TRUE)))
})

# ------------------------------------------------------------------------------
# 5. Sınırlı takip bağlamı + önceki kararlı sorgu kimliği
# ------------------------------------------------------------------------------

test_that("sınırlı takip bağlamı ve önceki kararlı kimlik Geçiş A'ya GİRER", {
  cfg <- .pk_sel_cfg()
  lib <- .pk_sel_lib()
  gecmis <- list(
    list(role = "user", content = "sentetik projelerin butcesi nedir"),
    list(role = "assistant", content = "Butce ozeti asagidadir."),
    list(role = "user", content = "peki 2024 icin?")
  )

  stub <- pk_select_stub_llm(list(.PK_SEL_PASS_A, .pk_sel_pass_b()))
  pk_select_run("peki 2024 icin?", lib, chat_history = gecmis,
                prior_query_id = "q001", llm_fn = stub$fn, cfg = cfg)

  sistem <- stub$log$calls[[1]]$system
  expect_true(grepl("ONCEKI SECILEN SORGU KIMLIGI: q001", sistem, fixed = TRUE))
  expect_true(grepl("ONCEKI KONUSMA", sistem, fixed = TRUE))

  # Zarf SINIRLIDIR: yalnızca son `history_turns` tur girer.
  expect_true(grepl("peki 2024 icin?", sistem, fixed = TRUE))
  expect_false(
    grepl("sentetik projelerin butcesi nedir", sistem, fixed = TRUE),
    info = "Bağlam zarfı sınırlı olmalıdır; tüm geçmiş gönderilmez."
  )
})

test_that("eksiltili takipte önceki kimlik KIRPMADAN ÖNCE tohumlanır", {
  cfg <- .pk_sel_cfg(recall_n = 3L)

  # Geçiş A önceki sorguyu (q001) hiç döndürmedi ve tam 3 aday verdi.
  # Tohumlama KIRPMADAN ÖNCE yapıldığı için q001 kümede kalmalıdır.
  adaylar <- pk_select_seed_candidates(c("q002", "q003", "q004"), "q001", cfg)

  expect_identical(adaylar[1], "q001")
  expect_equal(length(adaylar), 3L)
  expect_true(
    "q001" %in% adaylar,
    info = paste(
      "Geçiş A, Geçiş B konuşmayı inceleyemeden TEK sorgu-taşıyıcı bağlamı",
      "atmamalıdır (§5.2). Kırpma tohumlamadan ÖNCE yapılsaydı q001 düşerdi."
    )
  )
  # Kırpma yine de uygulanır: küme recall_n'i AŞMAZ.
  expect_lte(length(adaylar), cfg$recall_n)
})

test_that("tohumlanan kimlik TEKİLLEŞTİRİLİR ve uçtan uca Geçiş B'ye taşınır", {
  cfg <- .pk_sel_cfg(recall_n = 3L)

  # Zaten getirilmişse ikinci kez eklenmez.
  expect_identical(
    pk_select_seed_candidates(c("q001", "q002", "q003"), "q001", cfg),
    c("q001", "q002", "q003")
  )

  stub <- pk_select_stub_llm(list(
    "{\"candidates\":[\"q002\",\"q003\",\"q004\"]}",
    .pk_sel_pass_b(id = "q001", alternates = "[{\"id\":\"q002\",\"confidence\":40}]")
  ))
  karar <- pk_select_run("peki 2024 icin?", .pk_sel_lib(),
                         prior_query_id = "q001", llm_fn = stub$fn, cfg = cfg)

  expect_true("q001" %in% karar$candidate_ids)
  expect_true(grepl("--- SORGU q001 ---", stub$log$calls[[2]]$system, fixed = TRUE))
  expect_identical(karar$status, PK_SELECT_STATUS_AUTO)
})

test_that("kütüphanede ARTIK OLMAYAN önceki kimlik taşınmaz", {
  cfg <- .pk_sel_cfg()
  payload <- pk_select_pass_a_payload(.pk_sel_lib(), cfg)

  baglam <- pk_select_follow_up_context(NULL, "q999_silinmis", payload$ids, cfg)
  expect_true(is.na(baglam$prior_query_id))

  sistem <- pk_select_pass_a_messages("soru", payload, baglam, cfg)[[1]]$content
  expect_false(grepl("q999_silinmis", sistem, fixed = TRUE))
})

test_that("Geçiş A alanları KÜRESEL olarak düşürülmez; yalnızca kırpılır", {
  cfg <- .pk_sel_cfg(desc_chars = 40L, sample_chars = 30L)
  satir <- pk_select_pass_a_line(.pk_sel_lib()[[3]], cfg)

  # Beş alanın hepsi (id | isim | aciklama | anahtar | ornek) korunur.
  parcalar <- strsplit(satir, " | ", fixed = TRUE)[[1]]
  expect_equal(length(parcalar), 5L)
  expect_identical(parcalar[1], "q003")
  expect_true(nzchar(parcalar[4]), info = "Anahtar kelime alanı düşürülmemelidir.")
  expect_true(nzchar(parcalar[5]), info = "Örnek soru alanı düşürülmemelidir.")

  # Kırpma karakter bütçesine uyar ve AÇIKÇA işaretlenir.
  expect_lte(nchar(parcalar[3]), 40L)
  expect_true(grepl("…", satir, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# 6. Zaman aşımı ve ONARIM denemesi (D14)
# ------------------------------------------------------------------------------

test_that("her iki geçiş de request_timeout_sec ile çağrılır (D14)", {
  cfg <- .pk_sel_cfg(timeout_sec = 7L)
  stub <- pk_select_stub_llm(list(.PK_SEL_PASS_A, .pk_sel_pass_b()))
  pk_select_run("soru", .pk_sel_lib(), llm_fn = stub$fn, cfg = cfg)

  expect_equal(length(stub$log$calls), 2L)
  for (i in seq_len(2L)) {
    expect_equal(
      stub$log$calls[[i]]$settings$request_timeout_sec, 7L,
      info = sprintf("Geçiş %d zaman aşımı taşımalıdır; v1'de bu alan HİÇ YOKTU.", i)
    )
  }
})

test_that("yeniden deneme AYNI istemi tekrarlamaz; doğrulama hatasını EKLER (D14)", {
  cfg <- .pk_sel_cfg()
  stub <- pk_select_stub_llm(list(
    "bu json degil",             # Geçiş A - bozuk
    .PK_SEL_PASS_A,              # Geçiş A - onarım denemesi başarılı
    .pk_sel_pass_b()
  ))
  karar <- pk_select_run("soru", .pk_sel_lib(), llm_fn = stub$fn, cfg = cfg)

  expect_identical(karar$status, PK_SELECT_STATUS_AUTO)
  expect_equal(length(stub$log$calls), 3L)

  ilk <- stub$log$calls[[1]]$system
  onarim <- stub$log$calls[[2]]$system
  expect_false(
    identical(ilk, onarim),
    info = "v1, temperature 0.0 ile BİREBİR aynı çağrıyı tekrarlıyordu (D14)."
  )
  expect_true(grepl("ONCEKI DENEMEN GECERSIZDI", onarim, fixed = TRUE))
})

test_that("ZAMAN AŞIMI ikinci kez DENENMEZ ve bozulma kipine düşülür", {
  cfg <- .pk_sel_cfg()
  stub <- pk_select_stub_llm(list("__TIMEOUT__", "__TIMEOUT__"))
  karar <- pk_select_run("sentetik butce", .pk_sel_lib(), llm_fn = stub$fn, cfg = cfg)

  expect_equal(
    length(stub$log$calls), 1L,
    info = "Asılı bir uç noktayı ikinci kez beklemek olay döngüsünü iki katı bloke eder."
  )
  expect_identical(karar$status, PK_SELECT_STATUS_TIMEOUT)
})

test_that("onarım denemesi de başarısızsa OTOMATİK çalıştırma yapılmaz", {
  cfg <- .pk_sel_cfg()
  stub <- pk_select_stub_llm(list(
    .PK_SEL_PASS_A,
    "bozuk", "yine bozuk"
  ))
  karar <- pk_select_run("soru", .pk_sel_lib(), llm_fn = stub$fn, cfg = cfg)

  expect_identical(karar$status, PK_SELECT_STATUS_MALFORMED)
  expect_true(length(karar$chips) > 0L)
})

# ------------------------------------------------------------------------------
# 7. Sözlüksel katman KARAR VERMEZ (D10)
# ------------------------------------------------------------------------------

test_that("LLM erişilemezken ilk 3 aday SEÇENEK olarak sunulur, çalıştırılmaz", {
  cfg <- .pk_sel_cfg()
  stub <- pk_select_stub_llm(list(simpleError("connection refused")))
  karar <- pk_select_run("sentetik kaynak atama", .pk_sel_lib(), llm_fn = stub$fn, cfg = cfg)

  expect_identical(karar$status, PK_SELECT_STATUS_LLM_UNAVAILABLE)
  expect_false(identical(karar$status, PK_SELECT_STATUS_AUTO))

  # "connection refused" ZAMAN AŞIMI DEĞİLDİR (ölçülerek bulundu: yalın
  # "connect" deseni bunu timeout'a sınıflıyordu ve telemetriyi bozuyordu).
  expect_identical(
    .pk_select_classify_error("Failed to connect: connection refused"),
    PK_SELECT_STATUS_LLM_UNAVAILABLE
  )
  expect_identical(
    .pk_select_classify_error("Connection timed out after 20000 ms"),
    PK_SELECT_STATUS_TIMEOUT
  )
  expect_true(is.na(karar$query_id), info = "Bozulma kipinde sorgu SEÇİLMEZ.")
  expect_lte(length(karar$chips), 3L)
  expect_true(length(karar$chips) > 0L)
})

test_that("sözlüksel uyuşmazlık güveni DÜŞÜRÜR ama tek başına karar vermez", {
  lib_index <- pk_select_library_index(.pk_sel_lib())
  adaylar <- c("q001", "q002")
  pass_b <- pk_select_parse_pass_b(
    .pk_sel_pass_b(confidence = 60, alternates = "[{\"id\":\"q001\",\"confidence\":20}]"),
    adaylar
  )

  uyumlu <- list(available = TRUE, rank = 1L, score = 0.7, disagrees = FALSE)
  uyumsuz <- list(available = TRUE, rank = 4L, score = 0.01, disagrees = TRUE)

  a <- pk_select_decide(pass_b, adaylar, lib_index, .pk_sel_cfg(), lexical = uyumlu)
  b <- pk_select_decide(pass_b, adaylar, lib_index, .pk_sel_cfg(), lexical = uyumsuz)

  expect_identical(a$status, PK_SELECT_STATUS_AUTO)
  expect_equal(a$effective_confidence, 60L)

  # 60 - 15 = 45 < 50 -> netleştirmeye düşer.
  expect_equal(b$effective_confidence, 45L)
  expect_identical(b$status, PK_SELECT_STATUS_LOW_CONFIDENCE)
  expect_true(any(grepl("Sözlüksel getirim", b$disclosures, fixed = TRUE)))

  # Ceza 0 iken sinyal yalnızca RAPORLANIR, kararı değiştirmez.
  c0 <- pk_select_decide(pass_b, adaylar, lib_index, .pk_sel_cfg(disagree_penalty = 0L),
                         lexical = uyumsuz)
  expect_identical(c0$status, PK_SELECT_STATUS_AUTO)
})

test_that("v2 yolu v1 SEZGİSEL skorlayıcısını KARAR için çağırmaz (D10)", {
  kok <- resolve_repo_root_for_tests()
  for (dosya in PK_SELECT_RUNTIME_FILES) {
    yol <- file.path(kok, "R", dosya)
    ham <- readBin(yol, "raw", file.info(yol)$size)
    txt <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")

    for (desen in c("pk_compute_heuristic_query_scores", "pk_score_query_relevance")) {
      expect_false(
        grepl(desen, txt, fixed = TRUE, useBytes = TRUE),
        info = sprintf(
          "%s içinde v1 sezgisel skorlayıcısı çağrılıyor; v2'de KARAR VERİCİ olmamalıdır: %s",
          dosya, desen
        )
      )
    }
  }
})

# ------------------------------------------------------------------------------
# 8. Hat GERÇEKTEN çağrılıyor mu (Faz 4'ün "ölü kod" bulgusu)
# ------------------------------------------------------------------------------

test_that("select_smart_query içinde v2 dalı VARDIR ve motor bayrağına bağlıdır", {
  yol <- file.path(resolve_repo_root_for_tests(), "R", "module_proje_kaynak_analizi.R")
  ham <- readBin(yol, "raw", file.info(yol)$size)
  txt <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")

  expect_true(
    grepl("pk_select_query_v2(prompt, library, chat_history", txt, fixed = TRUE, useBytes = TRUE),
    info = paste(
      "Faz 4 incelemesinin en ağır bulgusu, çözümleyicinin hiç ÇAĞRILMAMASIYDI.",
      "Seçim hattı gerçek istek yolunda çağrılmalıdır."
    )
  )
  expect_true(grepl("pk_engine_is_v2()", txt, fixed = TRUE, useBytes = TRUE))

  # Reddetme mesajı v1'in düşük eşik geri dönüşünü BASTIRMALIDIR.
  expect_true(
    grepl("selected_query$refusal_message", txt, fixed = TRUE, useBytes = TRUE),
    info = "v2 açıkça reddettiyse v1'in fallback'i devreye girmemelidir."
  )
})

test_that("v2 dalının KAPISI motor bayrağıdır (v1 davranışı değişmez, §10)", {
  # Modüldeki dal `pk_engine_is_v2()` ile korunur. Kapının kendisi burada
  # DAVRANIŞSAL olarak doğrulanır: varsayılan/v1 iken kapalı, v2 iken açık.
  pk_select_with_env(character(0), {
    expect_false(
      isTRUE(pk_engine_is_v2()),
      info = "Varsayılan motor v1'dir; Faz 5 hattı KAPALI olmalıdır."
    )
  })

  pk_select_with_env(c(MERGEN_PK_ENGINE = "v1"), {
    expect_false(isTRUE(pk_engine_is_v2()))
  })

  pk_select_with_env(c(MERGEN_PK_ENGINE = "v2"), {
    expect_true(isTRUE(pk_engine_is_v2()))
  })

  # Modüldeki çağrı GERÇEKTEN bu kapının içinde olmalıdır: kapı satırı ile
  # çağrı satırı arasında kapatan bir `}` bulunmamalıdır.
  yol <- file.path(resolve_repo_root_for_tests(), "R", "module_proje_kaynak_analizi.R")
  ham <- readBin(yol, "raw", file.info(yol)$size)
  satirlar <- strsplit(
    iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte"),
    "\n", fixed = TRUE
  )[[1]]

  kapi <- grep("isTRUE(pk_engine_is_v2())", satirlar, fixed = TRUE)
  cagri <- grep("pk_select_query_v2(prompt, library, chat_history", satirlar, fixed = TRUE)

  expect_true(length(kapi) >= 1L && length(cagri) == 1L)
  expect_true(
    any(kapi < cagri) && (min(cagri) - max(kapi[kapi < cagri])) <= 4L,
    info = "v2 çağrısı motor kapısının HEMEN içinde olmalıdır."
  )
})

test_that("v2 seçimi v1 UYUMLU şekli döndürür ve oturuma kimliği yazar", {
  cfg <- .pk_sel_cfg()
  oturum <- list(userData = new.env(parent = emptyenv()))
  stub <- pk_select_stub_llm(list(.PK_SEL_PASS_A, .pk_sel_pass_b(id = "q002")))

  sonuc <- pk_select_query_v2(
    "sentetik soru", .pk_sel_lib(), chat_history = NULL,
    session = oturum, llm_fn = stub$fn, cfg = cfg
  )

  # v1 uyumlu alanlar korunur; modülün aşağı akış kodu değişmeden çalışır.
  expect_identical(sonuc$id, "q002")
  expect_identical(sonuc$selection_method, "ai_two_pass")
  expect_true(is.numeric(sonuc$relevance_score))
  expect_true(is.data.frame(sonuc$all_scores))
  expect_setequal(
    names(sonuc$all_scores),
    c("query_id", "query_name", "ai_score", "heuristic_score", "final_score")
  )
  # Sezgisel sütun v2'de bilinçli olarak 0 kalır (D10).
  expect_true(all(sonuc$all_scores$heuristic_score == 0))
  expect_equal(sonuc$all_scores$ai_score[sonuc$all_scores$query_id == "q002"], 85)

  # Sonraki eksiltili takip için kararlı kimlik hatırlanır.
  expect_identical(pk_select_prior_query_id(oturum), "q002")
})

test_that("reddetme kararı çalıştırılabilir sorgu DEĞİL, mesaj döndürür", {
  cfg <- .pk_sel_cfg()
  stub <- pk_select_stub_llm(list(
    .PK_SEL_PASS_A,
    .pk_sel_pass_b(confidence = 20, alternates = "[{\"id\":\"q001\",\"confidence\":15}]")
  ))
  oturum <- list(userData = new.env(parent = emptyenv()))

  sonuc <- pk_select_query_v2("belirsiz soru", .pk_sel_lib(), session = oturum,
                              llm_fn = stub$fn, cfg = cfg)

  expect_null(sonuc$id, info = "Reddetme sonucunda çalıştırılacak bir sorgu OLMAMALIDIR.")
  expect_true(nzchar(sonuc$refusal_message))
  expect_true(grepl("Analiz Seçimi Netleştirilmeli", sonuc$refusal_message, fixed = TRUE))
  expect_identical(sonuc$pk_selection$status, PK_SELECT_STATUS_LOW_CONFIDENCE)

  # Reddedilen seçim oturuma "önceki sorgu" olarak YAZILMAZ.
  expect_null(pk_select_prior_query_id(oturum))
})

test_that("seçim hattı SAF kalır: motor bayrağını kendisi okumaz", {
  kok <- resolve_repo_root_for_tests()
  # Yalnızca bağlama katmanı motor sınırıyla ilgilenebilir; karar/getirim
  # katmanları bayraktan BAĞIMSIZ olmalıdır (Faz 4 deseni).
  saf_dosyalar <- setdiff(PK_SELECT_RUNTIME_FILES, "helpers_pk_query_selection_apply.R")

  for (dosya in saf_dosyalar) {
    yol <- file.path(kok, "R", dosya)
    ham <- readBin(yol, "raw", file.info(yol)$size)
    txt <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")

    for (desen in c("pk_engine_is_v2", "MERGEN_PK_ENGINE", "mergen.pk.engine")) {
      expect_false(
        grepl(desen, txt, fixed = TRUE, useBytes = TRUE),
        info = sprintf("%s motor bayrağını okumamalıdır: %s", dosya, desen)
      )
    }
  }
})

test_that("Faz 5 dosyaları manifestte DOĞRU SIRADA kayıtlıdır", {
  yol <- file.path(resolve_repo_root_for_tests(), "R", "config_source_manifest.R")
  ham <- readBin(yol, "raw", file.info(yol)$size)
  txt <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")

  konumlar <- vapply(PK_SELECT_RUNTIME_FILES, function(d) {
    regexpr(paste0("R/", d), txt, fixed = TRUE, useBytes = TRUE)[1]
  }, numeric(1))

  expect_true(all(konumlar > 0), info = "Her Faz 5 dosyası manifestte olmalıdır.")
  expect_true(
    all(diff(konumlar) > 0),
    info = "Bağımlılık sırası: getirim -> istem -> ayrıştırma -> LLM -> bağlama."
  )

  # v1 sezgiseli, bağlama katmanından ÖNCE yüklenmelidir
  # (`pk_init_query_score_table()` oradan gelir).
  expect_lt(
    regexpr("R/helpers_pk_analysis_query_selection.R", txt, fixed = TRUE, useBytes = TRUE)[1],
    konumlar[["helpers_pk_query_selection_apply.R"]]
  )
})

test_that("dokuz seçim anahtarı da yapılandırma sözleşmesinde kayıtlıdır", {
  for (anahtar in PK_SELECT_ENV_KEYS) {
    if (identical(anahtar, "MERGEN_PK_ENGINE")) next
    expect_true(
      !is.null(pk_config_spec[[anahtar]]),
      info = sprintf("%s pk_config_spec içinde kayıtlı olmalıdır (§9).", anahtar)
    )
  }
  expect_equal(pk_config_spec$MERGEN_PK_SELECT_RECALL_N$min, 2L)
  expect_equal(pk_config_spec$MERGEN_PK_SELECT_RECALL_N$default, 5L)
  expect_equal(pk_config_spec$MERGEN_PK_SELECT_TIMEOUT_SEC$default, 20L)
  expect_equal(pk_config_spec$MERGEN_PK_SELECT_MIN_CONFIDENCE$default, 50L)
  expect_equal(pk_config_spec$MERGEN_PK_SELECT_MIN_MARGIN$default, 15L)
})
