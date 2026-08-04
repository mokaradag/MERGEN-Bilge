# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-prompt-budget-behavior.R
# Açıklama: D7 / D8 — istem bütçesinin TÜM yükü (özet + örnek satır JSON'u)
#           kapsaması ve bütçe aşımı özyinelemesinde FİLTRELEME UYARISI'nın
#           kaybolmaması. Tümü çevrimdışı ve deterministiktir: gerçek DB, LLM,
#           tarayıcı, SSO, ağ veya gerçek sır KULLANILMAZ.
# ==============================================================================

.pk_budget_env <- function(engine = "v1") {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
  source(file.path(repo_root, "R", "helpers_pk_config.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_pk_prompt_budget.R"), encoding = "UTF-8", local = env)
  env$MAX_ANALYSIS_PROMPT_CHARS <- 150000
  env$pk_engine_is_v2 <- function(query_meta = NULL) identical(engine, "v2")
  source(file.path(repo_root, "R", "helpers_pk_statistical_summary.R"),
         encoding = "UTF-8", local = env)
  env
}

.pk_budget_frame <- function(n = 200L, genislik = 12L) {
  sutunlar <- lapply(seq_len(genislik), function(i) {
    rep(paste0("SENTETIK_DEGER_", i, "_", strrep("x", 40L)), n)
  })
  names(sutunlar) <- paste0("Sutun_", seq_len(genislik))
  as.data.frame(sutunlar, stringsAsFactors = FALSE)
}

test_that("D7: butce TUM yuku kapsar, yalnizca ozet metnini degil", {
  env <- .pk_budget_env("v2")
  onizleme <- .pk_budget_frame(200L, 12L)

  # Ozet KISA; buyuk olan ornek satir JSON'udur. v1'de bu JSON butce
  # kontrolunun TAMAMEN disindaydi.
  ozet <- "TOPLAM SATIR: 200 | TOPLAM SUTUN: 12"
  butce <- 5000L

  fit <- env$pk_prompt_fit_payload(
    ozet, onizleme,
    function(s, j, n) paste0(s, "\n---\n", j),
    budget = butce
  )

  expect_true(fit$chars <= butce)
  expect_true(isTRUE(fit$trimmed))
  expect_true(fit$preview_rows < nrow(onizleme))
  expect_false(isTRUE(fit$over_budget))
})

test_that("ozet tek basina butceyi asarsa ornek satir hic gonderilmez ve ifsa edilir", {
  env <- .pk_budget_env("v2")

  kocaman_ozet <- strrep("A", 12000L)
  fit <- env$pk_prompt_fit_payload(
    kocaman_ozet, .pk_budget_frame(10L, 3L),
    function(s, j, n) paste0(s, "\n---\n", j),
    budget = 1000L
  )

  expect_equal(fit$preview_rows, 0L)
  expect_true(isTRUE(fit$over_budget))

  not <- env$pk_prompt_budget_note(fit, 10L)
  expect_true(nzchar(not))
  expect_true(grepl("BÜTÇESİ AŞILDI", not, fixed = TRUE))
})

test_that("butceye zaten sigan yuk kirpilmaz", {
  env <- .pk_budget_env("v2")
  onizleme <- .pk_budget_frame(3L, 2L)

  fit <- env$pk_prompt_fit_payload(
    "kisa ozet", onizleme,
    function(s, j, n) paste0(s, j),
    budget = 100000L
  )

  expect_equal(fit$preview_rows, 3L)
  expect_false(isTRUE(fit$trimmed))
  expect_null(env$pk_prompt_budget_note(fit, 3L))
})

test_that("v1 yuk kurucusu DEGISMEZ: butce muhasebesi uygulanmaz", {
  env <- .pk_budget_env("v1")
  onizleme <- .pk_budget_frame(200L, 12L)

  yuk <- env$pk_build_analysis_payload(
    stat_summary = list(summary_text = "OZET", preview_data = onizleme, row_count = 200L),
    query = NULL,
    engine_is_v2 = FALSE
  )

  # Tum satirlar JSON'a girdi; kirpilma YOK ve butce notu YOK.
  expect_true(nchar(yuk) > 100000L)
  expect_false(grepl("İSTEM BÜTÇESİ", yuk, fixed = TRUE))
  expect_true(grepl("--- ORNEK SATIRLAR (JSON) ---", yuk, fixed = TRUE))
})

test_that("v2 yuk kurucusu butceyi uygular ve notu ekler", {
  env <- .pk_budget_env("v2")
  onizleme <- .pk_budget_frame(200L, 12L)

  withr::with_envvar(list(MERGEN_PK_PROMPT_CHAR_BUDGET = "8000"), {
    yuk <- env$pk_build_analysis_payload(
      stat_summary = list(summary_text = "OZET", preview_data = onizleme, row_count = 200L),
      query = NULL,
      engine_is_v2 = TRUE
    )
    expect_true(grepl("İSTEM BÜTÇESİ", yuk, fixed = TRUE))
  })
})

test_that("D8: v2 butce ozyinelemesi FILTRELEME UYARISI blogunu KAYBETMEZ", {
  env <- .pk_budget_env("v2")

  # Ozyinelemeyi tetikleyecek kadar buyuk veri.
  veri <- .pk_budget_frame(400L, 8L)

  sonuc <- env$generate_statistical_summary(
    veri,
    max_preview_rows = 400L,
    max_total_chars = 300L,
    mode = "summary",
    rls_total_rows = 5000L,
    user_filter_applied = TRUE
  )

  expect_true(
    grepl("FİLTRELEME UYARISI", sonuc$summary_text, fixed = TRUE),
    info = "Butce asiminda filtreleme uyarisi kaybolmamalidir (D8)."
  )
  expect_true(grepl("5000", sonuc$summary_text, fixed = TRUE))
})

test_that("D8: v1 ozyineleme davranisi DEGISMEDEN korunur", {
  env <- .pk_budget_env("v1")
  veri <- .pk_budget_frame(400L, 8L)

  sonuc <- env$generate_statistical_summary(
    veri,
    max_preview_rows = 400L,
    max_total_chars = 300L,
    mode = "summary",
    rls_total_rows = 5000L,
    user_filter_applied = TRUE
  )

  # v1'de ozyineleme mode/rls_total_rows/user_filter_applied parametrelerini
  # DUSURUYOR; uyari bu yuzden kayboluyor. Motor siniri sozlesmesi geregi bu
  # davranis v1'de AYNEN korunur.
  expect_false(grepl("FİLTRELEME UYARISI", sonuc$summary_text, fixed = TRUE))
})

test_that("butce anahtari yapilandirma oncelik zincirini izler", {
  env <- .pk_budget_env("v2")

  withr::with_envvar(list(MERGEN_PK_PROMPT_CHAR_BUDGET = NA_character_), {
    expect_identical(env$pk_prompt_char_budget(), 120000L)

    # Sorgu metadatasi global degeri EZER.
    expect_identical(env$pk_prompt_char_budget(list(prompt_char_budget = 9000L)), 9000L)
  })

  withr::with_envvar(list(MERGEN_PK_PROMPT_CHAR_BUDGET = "7000"), {
    expect_identical(env$pk_prompt_char_budget(), 7000L)
  })

  # Gecersiz deger sessizce varsayilana duser.
  withr::with_envvar(list(MERGEN_PK_PROMPT_CHAR_BUDGET = "sayi-degil"), {
    expect_identical(env$pk_prompt_char_budget(), 120000L)
  })
})
