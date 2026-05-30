# ==============================================================================
# Dosya Yolu: tests/testthat/test-followup-helpers-behavior.R
# Açıklama: Takip sorusu yardımcılarının davranışsal birim testleri. Bu testler
#           saf fonksiyon davranışını (giriş -> çıkış) doğrular; statik kaynak
#           denetimi değildir. DB, LLM, ağ veya tarayıcı gerektirmez.
# ==============================================================================

.followup_helpers_source_once <- function() {
  if (exists("coerce_followup_flag", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("normalize_followup_texts", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_followup_questions.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

testthat::test_that("coerce_followup_flag toleranslı doğruluk değerlerini çözer", {
  .followup_helpers_source_once()

  # Boş / NULL
  testthat::expect_false(coerce_followup_flag(NULL))

  # Mantıksal
  testthat::expect_true(coerce_followup_flag(TRUE))
  testthat::expect_false(coerce_followup_flag(FALSE))
  testthat::expect_true(coerce_followup_flag(c(TRUE, FALSE)))

  # Sayısal: yalnızca 1 doğrudur
  testthat::expect_true(coerce_followup_flag(1))
  testthat::expect_false(coerce_followup_flag(0))
  testthat::expect_false(coerce_followup_flag(2))
  testthat::expect_false(coerce_followup_flag(NA_real_))

  # Metinsel toleranslı kabuller (büyük/küçük harf ve boşluk duyarsız)
  for (truthy in c("true", "T", "1", "yes", "evet", "aktif", "on", " Evet ", "ON")) {
    testthat::expect_true(
      coerce_followup_flag(truthy),
      info = paste("truthy kabul edilmeli:", truthy)
    )
  }

  # Metinsel reddedilenler
  for (falsy in c("false", "0", "hayir", "kapali", "", "belki")) {
    testthat::expect_false(
      coerce_followup_flag(falsy),
      info = paste("falsy reddedilmeli:", falsy)
    )
  }

  # Desteklenmeyen tip
  testthat::expect_false(coerce_followup_flag(list(a = 1)))
})

testthat::test_that("normalize_followup_texts temizler, tekilleştirir ve soru işareti ekler", {
  .followup_helpers_source_once()

  # Boş giriş NULL döner
  testthat::expect_null(normalize_followup_texts(NULL))
  testthat::expect_null(normalize_followup_texts(character(0)))
  testthat::expect_null(normalize_followup_texts(c("", "   ")))

  # Tekilleştirme + soru işareti
  out <- normalize_followup_texts(c("Soru bir", "Soru bir", "Soru iki"))
  testthat::expect_identical(length(out), 2L)
  testthat::expect_true(all(grepl("\\?$", out)))

  # 3 karakter veya daha kısa metinler elenir (nchar > 3 koşulu)
  out_short <- normalize_followup_texts(c("ab", "abc", "abcd"))
  testthat::expect_identical(out_short, "abcd?")

  # Zaten soru işareti olan metne ikinci soru işareti eklenmez
  out_q <- normalize_followup_texts("Nasil yaparim?")
  testthat::expect_identical(out_q, "Nasil yaparim?")

  # limit uygulanır
  out_lim <- normalize_followup_texts(
    c("Birinci soru", "Ikinci soru", "Ucuncu soru", "Dorduncu soru"),
    limit = 2L
  )
  testthat::expect_identical(length(out_lim), 2L)
})

testthat::test_that("ensure_user_perspective kullanıcı bakışına çevirir", {
  .followup_helpers_source_once()

  out1 <- ensure_user_perspective("Bunu yapmak istiyor musunuz?")
  testthat::expect_true(grepl("istiyorum", enc2utf8(out1), fixed = TRUE))

  out2 <- ensure_user_perspective("Denemek ister misiniz?")
  testthat::expect_true(grepl("istiyorum", enc2utf8(out2), fixed = TRUE))

  # İlgisiz metin değişmez
  out3 <- ensure_user_perspective("Normal bir soru?")
  testthat::expect_identical(out3, "Normal bir soru?")
})

testthat::test_that("strip_code_fences markdown kod bloklarını temizler", {
  .followup_helpers_source_once()

  testthat::expect_identical(
    strip_code_fences("```json\n{\"a\":1}\n```"),
    "{\"a\":1}"
  )
  testthat::expect_identical(
    strip_code_fences("```\nkod\n```"),
    "kod"
  )
  # Çitsiz metin değişmez
  testthat::expect_identical(strip_code_fences("{\"a\":1}"), "{\"a\":1}")
})

testthat::test_that("parse_followup_payload çeşitli JSON şekillerini ayrıştırır", {
  .followup_helpers_source_once()

  testthat::expect_identical(
    parse_followup_payload("{\"followups\":[\"Soru 1\",\"Soru 2\"]}"),
    c("Soru 1", "Soru 2")
  )
  testthat::expect_identical(
    parse_followup_payload("{\"questions\":[\"Q1\"]}"),
    "Q1"
  )
  testthat::expect_identical(
    parse_followup_payload("{\"sorular\":[\"S1\",\"S2\"]}"),
    c("S1", "S2")
  )
  # Düz JSON dizisi
  testthat::expect_identical(
    parse_followup_payload("[\"A\",\"B\"]"),
    c("A", "B")
  )
  # Kod çitli payload
  testthat::expect_identical(
    parse_followup_payload("```json\n{\"followups\":[\"X\"]}\n```"),
    "X"
  )
  # Geçersiz / boş
  testthat::expect_null(parse_followup_payload("gecersiz metin"))
  testthat::expect_null(parse_followup_payload(""))
  testthat::expect_null(parse_followup_payload(character(0)))
})

testthat::test_that("truncate_followup_context limiti aşan metni kısaltır", {
  .followup_helpers_source_once()

  testthat::expect_identical(truncate_followup_context(NULL), "")
  testthat::expect_identical(truncate_followup_context(""), "")
  testthat::expect_identical(truncate_followup_context(123), "")

  # Limit altındaki metin değişmez
  testthat::expect_identical(
    truncate_followup_context("kisa metin", limit = 100L),
    "kisa metin"
  )

  # Limiti aşan metin kısaltılır ve üç nokta eklenir
  uzun <- paste(rep("a", 50), collapse = "")
  out <- truncate_followup_context(uzun, limit = 10L)
  testthat::expect_true(startsWith(out, paste(rep("a", 10), collapse = "")))
  testthat::expect_true(grepl("…$", enc2utf8(out)))
})

testthat::test_that("default_followup_suggestions her zaman geçerli öneriler döner", {
  .followup_helpers_source_once()

  out <- default_followup_suggestions()
  testthat::expect_identical(length(out), 3L)
  testthat::expect_true(all(grepl("\\?$", out)))
})

testthat::test_that("build_followup_suggestions kapalıyken NULL, açıkken güvenli öneri döner", {
  .followup_helpers_source_once()
  testthat::skip_if_not_installed("shiny")

  # generate_ai_followups ağ çağrısı yapmasın diye stub'lanır.
  had_ai <- exists("generate_ai_followups", envir = globalenv(), inherits = FALSE)
  old_ai <- if (had_ai) get("generate_ai_followups", envir = globalenv()) else NULL
  assign("generate_ai_followups", function(...) NULL, envir = globalenv())
  on.exit({
    if (had_ai) {
      assign("generate_ai_followups", old_ai, envir = globalenv())
    } else if (exists("generate_ai_followups", envir = globalenv(), inherits = FALSE)) {
      rm("generate_ai_followups", envir = globalenv())
    }
  }, add = TRUE)

  # enable_followups okuması isolate ile yapıldığından plain env yeterlidir.
  disabled_settings <- new.env()
  disabled_settings$enable_followups <- FALSE

  enabled_settings <- new.env()
  enabled_settings$enable_followups <- TRUE

  empty_tools <- list(generate = function(...) NULL)

  # Kapalıyken NULL döner.
  testthat::expect_null(
    build_followup_suggestions(
      user_text = "soru", ai_text = "yanit",
      settings_data = disabled_settings, session = NULL,
      api_config = list(), followup_tools = empty_tools,
      fallback_followup_tool = empty_tools
    )
  )

  # Açıkken üreticiler boş dönse bile garanti varsayılan öneriler gelir.
  out_default <- build_followup_suggestions(
    user_text = "soru", ai_text = "yanit",
    settings_data = enabled_settings, session = NULL,
    api_config = list(), followup_tools = empty_tools,
    fallback_followup_tool = empty_tools
  )
  testthat::expect_true(length(out_default) >= 2L)
  testthat::expect_true(all(grepl("\\?$", out_default)))

  # Yerel deterministik üretici geçerli öneri verirse o kullanılır.
  local_tools <- list(
    generate = function(user, ai, min_questions = 2L, max_questions = 3L) {
      c("Yerel oneri bir", "Yerel oneri iki")
    }
  )
  out_local <- build_followup_suggestions(
    user_text = "soru", ai_text = "yanit",
    settings_data = enabled_settings, session = NULL,
    api_config = list(), followup_tools = local_tools,
    fallback_followup_tool = empty_tools
  )
  testthat::expect_true(any(grepl("Yerel oneri", out_local)))
})
