# ==============================================================================
# Dosya Yolu: tests/testthat/test-deep-analysis-context-builder-behavior.R
# Açıklama: build_deep_analysis_context saf kurucusunun davranışını doğrular:
#           başarısız-yalnız hata mesajı, başarılı data_analysis bağlamı,
#           çoklu sorgu max_tokens ölçeklemesi (8192 tavanı) ve başarısız notu.
#           Çevrimdışı/deterministik; gerçek DB/LLM yok.
# ==============================================================================

repo_root_dac <- resolve_repo_root_for_tests()

.dac_env <- new.env(parent = globalenv())
.dac_env$`%||%` <- function(a, b) if (is.null(a)) b else a
# Türkçe yorum: build_deep_analysis_context artık saf bağlam kurucu dosyasında
# yaşıyor; orkestratör dosyası yalnızca sıra/bağlam bütünlüğü için yüklenir.
suppressWarnings(source(
  file.path(repo_root_dac, "R/helpers_deep_analysis_context.R"),
  encoding = "UTF-8", local = .dac_env
))
suppressWarnings(source(
  file.path(repo_root_dac, "R/helpers_deep_analysis.R"),
  encoding = "UTF-8", local = .dac_env
))

.dac_ok <- function(nm) {
  list(success = TRUE, query_name = nm, query_desc = "açıklama",
       row_count = 5L, relevance = 50, summary_text = "özet metni", preview_json = "[]")
}

test_that("başarılı sorgu yoksa error_message döner ve başarısızları listeler", {
  qr <- list(
    list(success = FALSE, query_name = "Sorgu1", error_msg = "hata-bir"),
    list(success = FALSE, query_name = "Sorgu2", error_msg = "hata-iki")
  )
  out <- .dac_env$build_deep_analysis_context(qr, "soru", list(instruction = "X", max_tokens = 3000))
  expect_identical(out$type, "error_message")
  expect_true(grepl("Hiçbir sorgu başarılı", out$content, fixed = TRUE))
  expect_true(grepl("Sorgu1", out$content, fixed = TRUE))
  expect_true(grepl("hata-bir", out$content, fixed = TRUE))
})

test_that("tek başarılı sorgu data_analysis döner, max_tokens=base", {
  qr <- list(.dac_ok("Maliyet"))
  out <- .dac_env$build_deep_analysis_context(qr, "soru", list(instruction = "DETAY-YONERGE", max_tokens = 3000))
  expect_identical(out$type, "data_analysis")
  expect_equal(out$query_count, 1L)
  expect_equal(out$max_tokens, 3000)   # tek sorgu: ölçekleme yok
  expect_true(grepl("Maliyet", out$user_context, fixed = TRUE))
  expect_true(grepl("DETAY-YONERGE", out$prompt_context, fixed = TRUE))
})

test_that("çoklu sorgu max_tokens'ı ölçekler", {
  qr <- list(.dac_ok("A"), .dac_ok("B"), .dac_ok("C"))  # 3 sorgu -> 1 + 2*0.3 = 1.6
  out <- .dac_env$build_deep_analysis_context(qr, "soru", list(instruction = "", max_tokens = 3000))
  expect_equal(out$query_count, 3L)
  expect_equal(out$max_tokens, as.integer(3000 * 1.6))  # 4800
})

test_that("çok sayıda sorguda max_tokens 8192 tavanını aşmaz", {
  qr <- lapply(1:10, function(i) .dac_ok(paste0("Q", i)))  # 1 + 9*0.3 = 3.7 -> 11100 -> tavan
  out <- .dac_env$build_deep_analysis_context(qr, "soru", list(instruction = "", max_tokens = 3000))
  expect_equal(out$max_tokens, 8192)
})

test_that("başarılı + başarısız karışımı başarısız notu ekler", {
  qr <- list(
    .dac_ok("OK"),
    list(success = FALSE, query_name = "FAIL", error_msg = "neden-x")
  )
  out <- .dac_env$build_deep_analysis_context(qr, "soru", list(instruction = "", max_tokens = 3000))
  expect_identical(out$type, "data_analysis")
  expect_equal(out$query_count, 1L)
  expect_true(grepl("BAŞARISIZ SORGULAR", out$user_context, fixed = TRUE))
  expect_true(grepl("FAIL", out$user_context, fixed = TRUE))
  expect_true(grepl("neden-x", out$user_context, fixed = TRUE))
})

test_that("v2 bağlamı reconciled kanonik packet metnini kullanır, legacy özete düşmez", {
  qr <- list(list(
    success = TRUE,
    query_name = "V2",
    query_desc = "kanonik",
    row_count = 3L,
    relevance = 90,
    pk_engine_mode = "v2",
    pk_packet_text = "KANONIK-V2-DEGER %60,0 [fact:progress.weighted.weighted_mean.overall.abc123]",
    summary_text = "LEGACY-OZET-YASAK",
    preview_json = "LEGACY-JSON-YASAK"
  ))

  out <- .dac_env$build_deep_analysis_context(
    qr, "soru", list(instruction = "", max_tokens = 3000)
  )

  expect_identical(out$type, "data_analysis")
  expect_true(grepl("KANONIK-V2-DEGER", out$user_context, fixed = TRUE))
  expect_true(grepl("[fact:", out$user_context, fixed = TRUE))
  expect_false(grepl("LEGACY-OZET-YASAK", out$user_context, fixed = TRUE))
  expect_false(grepl("LEGACY-JSON-YASAK", out$user_context, fixed = TRUE))
  expect_true(grepl("v2 SAYISAL KÖKEN KURALI", out$prompt_context, fixed = TRUE))
})

test_that("v2 başarılı kayıt kanonik packet metni yoksa legacy summary fail-closed kullanılmaz", {
  qr <- list(list(
    success = TRUE,
    query_name = "V2-Eksik",
    query_desc = "kanonik yok",
    row_count = 2L,
    relevance = 80,
    pk_engine_mode = "v2",
    pk_packet_text = "",
    summary_text = "LEGACY-SAYI-99999",
    preview_json = "[]"
  ))

  out <- .dac_env$build_deep_analysis_context(
    qr, "soru", list(instruction = "", max_tokens = 3000)
  )

  expect_identical(out$type, "error_message")
  expect_true(grepl("Kanonik v2 analiz paketi", out$content, fixed = TRUE))
  expect_false(grepl("LEGACY-SAYI-99999", out$content, fixed = TRUE))
})

# --- İSTEM BÜTÇESİ: ÖNİZLEME SONRASI İKİNCİ DETERMİNİSTİK BOZULMA -------------
#
# KUSUR: `pk_deep_fit_context_budget()` YALNIZCA önizleme JSON bloklarını
# düşürüyordu. Sabit sistem metni + istatistiksel özetler tek başına bütçeyi
# aşıyorsa (ya da hiç önizleme bloğu yoksa) döngü sona eriyor ve fonksiyon
# bütçe ÜSTÜ yükü SESSİZCE değişmeden döndürüyordu.

# Bütçe uygulayıcısı `pk_prompt_char_budget()`/`pk_config_resolve()` gerektirir;
# dosya başındaki ortam bunları taşımaz.
# İSTEM BÜTÇESİ R SEÇENEĞİ DE YALITILIR (PR incelemesi).
#
# `pk_config_resolve()` `MERGEN_PK_PROMPT_CHAR_BUDGET` ORTAM DEĞİŞKENİNE EK
# OLARAK `options(mergen.pk.prompt_char_budget)` okur. Testler yalnızca ortam
# değişkenini sabitliyordu; paylaşılan test oturumunda kalmış bir seçenek
# değeri etkin bütçeyi belirleyip iddiaları oturum durumuna bağımlı kılardı.
local({
  if (requireNamespace("withr", quietly = TRUE)) {
    eski_secenekler <- options(mergen.pk.prompt_char_budget = NULL)
    withr::defer(options(eski_secenekler), envir = testthat::teardown_env())
  }
})

.dac_butce_env <- local({
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  for (f in c("R/helpers_pk_config.R", "R/helpers_pk_prompt_budget.R",
              "R/helpers_deep_analysis_context.R")) {
    suppressWarnings(source(file.path(repo_root_dac, f),
                            encoding = "UTF-8", local = env))
  }
  env
})

.dac_blok <- function(i, ozet_uzunluk = 2000L, onizleme = TRUE) {
  paste0(
    "\n\n==========================================\n",
    sprintf("\U0001F4CA SORGU %d/3: SENTETIK %d\n", i, i),
    "==========================================\n",
    strrep("OZET ", ozet_uzunluk),
    # ÖNİZLEME ÇOK SATIRLIDIR. Gerçek `preview_json` (jsonlite çıktısı) satır
    # sonu taşır; tek satırlık bir fixture, kırpma deseni ilk `\n` karakterinde
    # dursa bile testi geçirirdi ve üretimde JSON gövdesi bağlamda KALIRDI.
    if (isTRUE(onizleme)) paste0("\n\n--- ÖRNEK VERİ (JSON) ---\n",
                                 "[\n",
                                 strrep("  {\"a\":1},\n", 300L),
                                 "  {\"a\":2}\n]") else "",
    sprintf("\n(Bu sorgu %d satirlik veri icermektedir)\n", i)
  )
}

.dac_baglam <- function(n = 3L, ozet_uzunluk = 2000L, onizleme = TRUE) {
  paste0(
    "KULLANICI SORUSU:\nsentetik soru\n",
    "\n\n--- R TARAFINDAN HAZIRLANAN ÇOKLU SORGU SONUÇLARI ---\n",
    paste(vapply(seq_len(n), function(i) .dac_blok(i, ozet_uzunluk, onizleme),
                 character(1)), collapse = "\n"),
    "\n\n--- SONUÇLAR SONU ---\n\nTalimat: analiz et."
  )
}

test_that("önizlemeler yetmezse SORGU BLOKLARI düşürülür ve bütçe UYGULANIR", {
  testthat::skip_if_not_installed("withr")
  sistem <- strrep("S", 500L)
  baglam <- .dac_baglam()

  withr::with_envvar(list(MERGEN_PK_PROMPT_CHAR_BUDGET = "12000"), {
    sonuc <- .dac_butce_env$pk_deep_fit_context_budget(sistem, baglam, NULL)

    # Butce GERCEKTEN uygulanir.
    expect_false(isTRUE(sonuc$over_budget))
    expect_true(sonuc$chars <= sonuc$budget)

    # Onizlemeler once, ardindan blok duserek; ikisi de ACIKCA ifsa edilir.
    expect_true(sonuc$dropped_previews > 0L)
    expect_true(sonuc$dropped_blocks > 0L)
    expect_true(grepl("sonuç bloğu", sonuc$user_context, fixed = TRUE))
    expect_true(grepl("EKSİKTİR", sonuc$user_context, fixed = TRUE))

    # ÖNİZLEME GÖVDESİ GERÇEKTEN GİDER: yalnızca başlık satırını silen bir
    # desen "düşürüldü" der ama JSON satırlarını bırakırdı.
    expect_false(grepl("--- ÖRNEK VERİ (JSON) ---", sonuc$user_context, fixed = TRUE))
    expect_false(grepl("{\"a\":1},", sonuc$user_context, fixed = TRUE))
  })
})

test_that("hiç önizleme bloğu olmayan aşım da bloklarla çözülür", {
  testthat::skip_if_not_installed("withr")
  sistem <- strrep("S", 500L)
  baglam <- .dac_baglam(onizleme = FALSE)

  withr::with_envvar(list(MERGEN_PK_PROMPT_CHAR_BUDGET = "8000"), {
    sonuc <- .dac_butce_env$pk_deep_fit_context_budget(sistem, baglam, NULL)
    expect_identical(sonuc$dropped_previews, 0L)
    expect_true(sonuc$dropped_blocks > 0L)
    expect_true(sonuc$chars <= sonuc$budget)
  })
})

test_that("bütçeye sığan bağlam DEĞİŞMEDEN döner", {
  testthat::skip_if_not_installed("withr")
  sistem <- strrep("S", 100L)
  baglam <- .dac_baglam(n = 1L, ozet_uzunluk = 5L)

  withr::with_envvar(list(MERGEN_PK_PROMPT_CHAR_BUDGET = "120000"), {
    sonuc <- .dac_butce_env$pk_deep_fit_context_budget(sistem, baglam, NULL)
    expect_false(isTRUE(sonuc$trimmed))
    expect_identical(sonuc$user_context, baglam)
  })
})

test_that("sabit sistem metni tek başına aşıyorsa SONSUZ DÖNGÜ olmaz", {
  testthat::skip_if_not_installed("withr")
  # Daha fazla deterministik kirpma mumkun degildir; durum sessiz gecmez.
  sistem <- strrep("S", 5000L)
  baglam <- .dac_baglam(n = 2L, ozet_uzunluk = 200L)

  withr::with_envvar(list(MERGEN_PK_PROMPT_CHAR_BUDGET = "1000"), {
    sonuc <- .dac_butce_env$pk_deep_fit_context_budget(sistem, baglam, NULL)
    expect_true(isTRUE(sonuc$over_budget))
    expect_true(sonuc$dropped_blocks > 0L)
  })
})
