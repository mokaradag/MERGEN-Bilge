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

test_that("v1 butce ALTINDA kalan yuk BIREBIR degismez", {
  env <- .pk_budget_env("v1")
  onizleme <- .pk_budget_frame(5L, 3L)

  yuk <- env$pk_build_analysis_payload(
    stat_summary = list(summary_text = "OZET", preview_data = onizleme, row_count = 5L),
    query = NULL,
    engine_is_v2 = FALSE
  )

  # Butcenin altinda: kirpilma YOK, butce notu YOK, sekil ayni.
  expect_false(grepl("İSTEM BÜTÇESİ", yuk, fixed = TRUE))
  expect_true(grepl("--- ORNEK SATIRLAR (JSON) ---", yuk, fixed = TRUE))
  expect_true(grepl("Sutun_1", yuk, fixed = TRUE))
})

test_that("v1 yolu da istek boyutu sinirini UYGULAR", {
  # KUSUR: `MERGEN_PK_ENGINE` varsayilani v1'ken bu dal ornek satirlarin
  # TAMAMINI serilestirip butceye hic bakmadan donuyordu; istem guvenligi
  # v2'ye gecmeye bagli kaliyordu.
  env <- .pk_budget_env("v1")
  onizleme <- .pk_budget_frame(200L, 12L)

  withr::with_envvar(list(MERGEN_PK_PROMPT_CHAR_BUDGET = "8000"), {
    yuk <- env$pk_build_analysis_payload(
      stat_summary = list(summary_text = "OZET", preview_data = onizleme, row_count = 200L),
      query = NULL,
      engine_is_v2 = FALSE
    )

    # Kirpma GERCEKLESIR ve ACIKCA ifsa edilir.
    expect_true(grepl("İSTEM BÜTÇESİ", yuk, fixed = TRUE))
    # Nihai yuk, butce + not payi mertebesinde kalir; eski davranista
    # 100.000+ karakterdi.
    expect_true(nchar(yuk) < 20000L)
  })
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

  # PR #714: BU BEKLENTININ GEREKCESI ARTIK GECERSIZDIR.
  #
  # Yorumun dayanagi "v1 ozyinelemesi kapsam argumanlarini DUSURUYOR" idi; PR
  # #705 o kusuru duzeltti ve v1 ozyinelemesi de mode/rls_total_rows/
  # user_filter_applied tasiyor. Geriye YALNIZCA terminal geri dusmedeki
  # `pk_v2 &&` kapisi kalmisti ve v1'de FILTRELENMIS bir yanit kapsam
  # uyarisini kaybediyordu: model, yalnizca filtreli alt kumeyi anlatan
  # sayilari TUM VERI gibi sunabilirdi. Uyari artik motor bayragindan
  # BAGIMSIZDIR; ana ozet yolunda da (kirpma olmadan) zaten oyleydi.
  expect_true(
    grepl("FİLTRELEME UYARISI", sonuc$summary_text, fixed = TRUE),
    info = "v1 terminal geri dusmesinde de kapsam uyarisi KORUNMALIDIR."
  )
  expect_true(grepl("5000", sonuc$summary_text, fixed = TRUE))
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

test_that("ACIK sifir butce TUKENMIS demektir, varsayilana DUSMEZ", {
  # KUSUR: `pk_build_analysis_payload()` ifsa blogu + not payi toplam butceyi
  # tukettiginde `fit_butcesi`'ni bilincli olarak 0'a kenetler. Eskiden bu
  # deger `budget <= 0L` dalina dusup 120.000 karakterlik TAZE bir izin
  # kazaniyordu; yani butce muhasebesi tamamen devre disi kaliyordu.
  env <- .pk_budget_env("v2")
  onizleme <- .pk_budget_frame(50L, 8L)

  fit <- env$pk_prompt_fit_payload(
    "OZET", onizleme,
    function(ozet, json, satir) paste0(ozet, json),
    budget = 0L
  )

  expect_identical(fit$budget, 0L)
  expect_identical(fit$preview_rows, 0L)
  expect_true(isTRUE(fit$over_budget))
  # Tukenmis butce ACIKCA ifsa edilir.
  expect_true(grepl(
    "İSTEM BÜTÇESİ AŞILDI",
    env$pk_prompt_budget_note(fit, 50L), fixed = TRUE
  ))

  # Negatif deger de tukenmis sayilir.
  fit_neg <- env$pk_prompt_fit_payload(
    "OZET", onizleme,
    function(ozet, json, satir) paste0(ozet, json),
    budget = -10L
  )
  expect_identical(fit_neg$budget, 0L)
  expect_identical(fit_neg$preview_rows, 0L)
})

test_that("AYARLANMAMIS/GECERSIZ butce varsayilan yolu KORUR", {
  env <- .pk_budget_env("v2")
  onizleme <- .pk_budget_frame(3L, 3L)

  # NULL -> yapilandirma/varsayilan.
  fit_null <- env$pk_prompt_fit_payload(
    "OZET", onizleme, function(ozet, json, satir) paste0(ozet, json), budget = NULL
  )
  expect_true(fit_null$budget > 0L)
  expect_identical(fit_null$preview_rows, 3L)

  # NA -> gecersiz girdi, varsayilana duser (tukenmis DEGIL).
  fit_na <- env$pk_prompt_fit_payload(
    "OZET", onizleme, function(ozet, json, satir) paste0(ozet, json),
    budget = NA_integer_
  )
  expect_identical(fit_na$budget, 120000L)
  expect_identical(fit_na$preview_rows, 3L)

  # Yapilandirma 0/negatif dondururse TOPLAM butce varsayilana duser; yalnizca
  # HESAPLANAN kalan sifir "tukenmis" anlamina gelir.
  withr::with_envvar(list(MERGEN_PK_PROMPT_CHAR_BUDGET = "0"), {
    expect_identical(env$pk_prompt_char_budget(), 120000L)
  })
})
