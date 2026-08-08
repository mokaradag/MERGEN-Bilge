# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-golden-set-behavior.R
# Açıklama: Faz 5 (§7) — TAAHHÜT EDİLEN altın küme koşum takımı (harness).
#           Tamamen çevrimdışı ve belirlenimcidir: LLM `llm_fn` ile ENJEKTE
#           edilir ve kaydedilmiş çıktıları döndürür (§7 "Offline (default
#           suite): stubbed LLM returning recorded outputs").
#
# ÖLÇÜLEN: recall@N — Geçiş A'ya giden yükün, beklenen sorguyu GÖRÜNÜR kılıp
#          kılmadığı. Bu, sözlüksel getirimin izin verilen üçüncü rolüdür
#          (altın küme tanılaması) ve KARAR VERMEZ.
#
# Bu dosya "modeli" ölçmez — model burada sahtedir. Ölçtüğü şey, doğru sorgunun
# Geçiş A penceresinde ULAŞILABİLİR olup olmadığıdır. Kaçırılan bir aday,
# Geçiş B'nin asla telafi edemeyeceği tek geri dönülmez kayıptır (§5.2).
#
# Gerçek trafikle çalışan puanlı koşum VM tarafındadır ve taahhüt EDİLMEZ.
# ==============================================================================

pk_select_source_chain_for_tests()

.pk_golden_path <- function() {
  file.path(resolve_repo_root_for_tests(), "tests", "fixtures", "pk_golden_set.json")
}

.pk_golden_load <- function() {
  jsonlite::fromJSON(.pk_golden_path(), simplifyVector = FALSE)
}

test_that("altın küme fixture'ı vardır ve YALNIZCA sentetik veri taşır", {
  expect_true(file.exists(.pk_golden_path()))

  golden <- .pk_golden_load()
  expect_true(length(golden$cases) >= 5L)

  ham <- readBin(.pk_golden_path(), "raw", file.info(.pk_golden_path())$size)
  txt <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")

  # §7: taahhüt edilen korpus gerçek satır sayısı taşımaz; şekil iddiası kullanır.
  expect_false(
    grepl("expected_row_count", txt, fixed = TRUE, useBytes = TRUE),
    info = "Gerçek satır sayısı taahhüt edilen fixture'a GİRMEZ (§7)."
  )

  # Her vakanın kimliği ve sorusu olmalıdır.
  for (vaka in golden$cases) {
    expect_true(nzchar(vaka$id %||% ""), info = "Her vakanın kimliği olmalıdır.")
    expect_true(nzchar(vaka$soru %||% ""), info = "Her vakanın sorusu olmalıdır.")
    expect_true("expected_selection" %in% names(vaka))
  }
})

test_that("fixture, ayırt edici terimi YALNIZCA sample_questions'ta taşıyan vaka içerir", {
  golden <- .pk_golden_load()
  ayirt <- Filter(function(v) identical(v$distinguishing_field, "sample_questions"), golden$cases)

  expect_true(
    length(ayirt) >= 1L,
    info = paste(
      "§8 Faz 5 kabul ölçütü: ayırt edici ifadesi YALNIZCA sample_questions'ta",
      "geçen en az bir vaka bulunmalıdır."
    )
  )

  # Ve bu iddia GERÇEKTEN doğru olmalıdır: terim başka alanda geçmemelidir.
  lib <- pk_select_library_index(pk_select_test_library())
  vaka <- ayirt[[1]]
  hedef <- lib[[vaka$expected_query_id]]

  expect_false(grepl("ertelen", hedef$name, fixed = TRUE))
  expect_false(grepl("ertelen", hedef$description, fixed = TRUE))
  expect_false(any(grepl("ertelen", unlist(hedef$meta$keywords), fixed = TRUE)))
  expect_true(any(grepl("ertelen", unlist(hedef$meta$sample_questions), fixed = TRUE)))
})

test_that("fixture, eksiltili takip vakası içerir", {
  golden <- .pk_golden_load()
  eksiltili <- Filter(function(v) isTRUE(v$elliptical), golden$cases)

  expect_true(length(eksiltili) >= 1L)
  for (vaka in eksiltili) {
    expect_true(
      nzchar(vaka$prior_query_id %||% ""),
      info = "Eksiltili vaka, korunması gereken ÖNCEKİ kararlı kimliği taşımalıdır."
    )
  }
})

test_that("recall@N: beklenen sorgu Geçiş A YÜKÜNDE görünür kalır", {
  golden <- .pk_golden_load()
  lib <- pk_select_test_library()
  cfg <- pk_select_normalize_config(list(
    timeout_sec = 20L, recall_n = 5L, min_confidence = 50L, min_margin = 15L,
    disagree_penalty = 15L, desc_chars = 220L, sample_chars = 120L,
    sample_n = 2L, history_turns = 2L
  ))

  payload <- pk_select_pass_a_payload(lib, cfg)
  satirlar <- strsplit(payload$text, "\n", fixed = TRUE)[[1]]
  names(satirlar) <- payload$ids

  kacirilan <- character(0)

  for (vaka in golden$cases) {
    beklenen <- vaka$expected_query_id
    if (is.null(beklenen)) next

    # Beklenen sorgunun satırı yükte OLMALI ve ayırt edici terimi TAŞIMALIDIR.
    if (!beklenen %in% payload$ids) {
      kacirilan <- c(kacirilan, vaka$id)
      next
    }
  }

  expect_equal(
    kacirilan, character(0),
    info = paste(
      "Geçiş A yükü, beklenen her sorguyu içermelidir. Kaçan vakalar:",
      paste(kacirilan, collapse = ", ")
    )
  )

  # Kırpma, ayırt edici terimi YOK ETMEMELİDİR.
  expect_true(
    grepl("ertelendi", satirlar[["q003"]], fixed = TRUE),
    info = paste(
      "Ayırt edici terim örnek sorudan kırpılırsa Geçiş A onu göremez ve",
      "Geçiş B geri getiremez (§5.2)."
    )
  )
})

test_that("sözlüksel getirim, altın kümede beklenen sorguyu ilk-3'e taşır", {
  golden <- .pk_golden_load()
  index <- pk_retrieval_build_index(pk_select_test_library())

  # Bu SADECE tanılamadır: bozulma kipi kalitesini ölçer, karar vermez.
  # Eksiltili vaka hariç tutulur — sözlüksel sinyal orada zaten yoktur ve
  # olmaması BEKLENİR (bağlam tohumlaması bu yüzden vardır).
  for (vaka in golden$cases) {
    beklenen <- vaka$expected_query_id
    if (is.null(beklenen) || isTRUE(vaka$elliptical)) next

    siralama <- pk_retrieval_score(index, vaka$soru)
    sira <- match(beklenen, siralama$query_id)

    expect_true(
      !is.na(sira) && sira <= 3L,
      info = sprintf(
        "Vaka %s ('%s'): beklenen %s sözlüksel ilk-3'te değil (sıra: %s).",
        vaka$id, vaka$soru, beklenen, sira
      )
    )
  }
})

test_that("kapsam dışı soru için sözlüksel sinyal ZAYIFTIR", {
  golden <- .pk_golden_load()
  index <- pk_retrieval_build_index(pk_select_test_library())

  disarida <- Filter(function(v) is.null(v$expected_query_id), golden$cases)
  expect_true(length(disarida) >= 1L, info = "Kapsam dışı en az bir vaka olmalıdır.")

  for (vaka in disarida) {
    siralama <- pk_retrieval_score(index, vaka$soru)
    expect_lt(max(siralama$score), 0.35)
  }
})

test_that("uçtan uca: altın küme vakaları kaydedilmiş LLM çıktısıyla çözülür", {
  golden <- .pk_golden_load()
  lib <- pk_select_test_library()
  cfg <- pk_select_normalize_config(list(
    timeout_sec = 20L, recall_n = 5L, min_confidence = 50L, min_margin = 15L,
    disagree_penalty = 15L, desc_chars = 220L, sample_chars = 120L,
    sample_n = 2L, history_turns = 2L
  ))

  dogru <- 0L
  toplam <- 0L

  for (vaka in golden$cases) {
    toplam <- toplam + 1L
    beklenen <- vaka$expected_query_id

    if (identical(vaka$expected_selection, "refuse")) {
      # Kapsam dışı: model düşük güven verir -> seçim REDDETMELİDİR.
      stub <- pk_select_stub_llm(list(
        "{\"candidates\":[\"q001\",\"q002\",\"q003\"]}",
        "{\"id\":\"q001\",\"confidence\":12,\"alternates\":[{\"id\":\"q002\",\"confidence\":8}]}"
      ))
      karar <- pk_select_run(vaka$soru, lib, llm_fn = stub$fn, cfg = cfg)

      expect_false(
        identical(karar$status, PK_SELECT_STATUS_AUTO),
        info = sprintf("Vaka %s kapsam dışıdır; otomatik çalıştırılmamalıdır.", vaka$id)
      )
      if (!identical(karar$status, PK_SELECT_STATUS_AUTO)) dogru <- dogru + 1L
      next
    }

    # Kaydedilmiş Geçiş A/B çıktıları: doğru adayı içeren bir aday kümesi ve
    # net bir kazanan. `requirements` fixture'dan gelir.
    gereksinim <- vaka$expected_requirements
    req_json <- if (is.null(gereksinim)) {
      "null"
    } else {
      jsonlite::toJSON(gereksinim, auto_unbox = FALSE)
    }

    rakip <- if (identical(beklenen, "q001")) "q002" else "q001"
    stub <- pk_select_stub_llm(list(
      sprintf("{\"candidates\":[\"%s\",\"%s\"]}", beklenen, rakip),
      sprintf(
        "{\"id\":\"%s\",\"confidence\":88,\"reason\":\"altin kume\",\"alternates\":[{\"id\":\"%s\",\"confidence\":30}],\"requirements\":%s}",
        beklenen, rakip, req_json
      )
    ))

    karar <- pk_select_run(
      vaka$soru, lib,
      prior_query_id = vaka$prior_query_id %||% NULL,
      llm_fn = stub$fn, cfg = cfg
    )

    expect_identical(
      karar$status, PK_SELECT_STATUS_AUTO,
      info = sprintf("Vaka %s ('%s') otomatik seçilmeliydi.", vaka$id, vaka$soru)
    )
    expect_identical(
      karar$query_id, beklenen,
      info = sprintf("Vaka %s beklenen sorguyu seçmelidir.", vaka$id)
    )
    if (identical(karar$query_id, beklenen)) dogru <- dogru + 1L
  }

  expect_equal(
    dogru, toplam,
    info = sprintf("Altın küme doğruluğu: %d/%d", dogru, toplam)
  )
})

test_that("eksiltili vaka, önceki kimlik OLMADAN aday kümesine giremez", {
  golden <- .pk_golden_load()
  eksiltili <- Filter(function(v) isTRUE(v$elliptical), golden$cases)[[1]]

  lib <- pk_select_test_library()
  cfg <- pk_select_normalize_config(list(
    timeout_sec = 20L, recall_n = 2L, min_confidence = 50L, min_margin = 15L,
    disagree_penalty = 15L, desc_chars = 220L, sample_chars = 120L,
    sample_n = 2L, history_turns = 2L
  ))

  # Geçiş A, eksiltili soruda beklenen sorguyu bulamaz (gerçekçi senaryo).
  gecis_a <- "{\"candidates\":[\"q003\",\"q004\"]}"

  # Önceki kimlik OLMADAN: beklenen sorgu aday kümesinde YOK.
  stub_yok <- pk_select_stub_llm(list(gecis_a, "{\"id\":\"q003\",\"confidence\":80,\"alternates\":[{\"id\":\"q004\",\"confidence\":20}]}"))
  karar_yok <- pk_select_run(eksiltili$soru, lib, llm_fn = stub_yok$fn, cfg = cfg)
  expect_false(eksiltili$expected_query_id %in% karar_yok$candidate_ids)

  # Önceki kimlik İLE: tohumlama kırpmadan önce yapılır, aday kümeye girer.
  stub_var <- pk_select_stub_llm(list(
    gecis_a,
    sprintf(
      "{\"id\":\"%s\",\"confidence\":85,\"alternates\":[{\"id\":\"q003\",\"confidence\":30}]}",
      eksiltili$expected_query_id
    )
  ))
  karar_var <- pk_select_run(
    eksiltili$soru, lib,
    prior_query_id = eksiltili$prior_query_id,
    llm_fn = stub_var$fn, cfg = cfg
  )

  expect_true(eksiltili$expected_query_id %in% karar_var$candidate_ids)
  expect_identical(karar_var$query_id, eksiltili$expected_query_id)
  expect_identical(karar_var$status, PK_SELECT_STATUS_AUTO)
  expect_lte(length(karar_var$candidate_ids), cfg$recall_n)
})
