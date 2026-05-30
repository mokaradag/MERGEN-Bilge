# ==============================================================================
# Dosya Yolu: tests/testthat/test-summarization-modes-behavior.R
# Açıklama: Özetleme modu talimat üreticilerinin davranışsal testleri.
#           switch yönlendirmesi ve varsayılan (fallback) davranışı doğrulanır.
#           ASCII çapaları kullanılarak Windows/Türkçe yerel ayar baytı eşleşme
#           kırılganlığı önlenir. DB, LLM, tarayıcı gerektirmez.
# ==============================================================================

.summarization_modes_source_once <- function() {
  if (exists("build_mode_instructions", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_summarization_modes.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

.contains_ascii <- function(haystack, needle) {
  grepl(needle, enc2utf8(haystack), fixed = TRUE)
}

testthat::test_that("get_detail_level_instructions her seviye için doğru moda yönlenir", {
  .summarization_modes_source_once()

  testthat::expect_true(.contains_ascii(get_detail_level_instructions("brief"), "YASAKLAR"))
  testthat::expect_true(.contains_ascii(get_detail_level_instructions("detailed"), "DETAYLI"))
  testthat::expect_true(.contains_ascii(get_detail_level_instructions("standard"), "STANDART"))
})

testthat::test_that("get_detail_level_instructions bilinmeyen seviyede standart moda düşer", {
  .summarization_modes_source_once()

  out <- get_detail_level_instructions("gecersiz_seviye")
  testthat::expect_true(.contains_ascii(out, "STANDART"))
  # Varsayılan, kısa veya detaylı moda kaçmamalı.
  testthat::expect_false(.contains_ascii(out, "YASAKLAR"))
})

testthat::test_that("get_focus_mode_instructions her odak için doğru moda yönlenir", {
  .summarization_modes_source_once()

  testthat::expect_true(.contains_ascii(get_focus_mode_instructions("numerical"), "SAYISAL"))
  testthat::expect_true(.contains_ascii(get_focus_mode_instructions("decisions"), "KARAR"))
  testthat::expect_true(.contains_ascii(get_focus_mode_instructions("comparison"), "Sentez"))
})

testthat::test_that("get_focus_mode_instructions bilinmeyen odakta genel moda düşer", {
  .summarization_modes_source_once()

  out <- get_focus_mode_instructions("gecersiz_odak")
  testthat::expect_true(.contains_ascii(out, "ODAK: GENEL"))
  testthat::expect_false(.contains_ascii(out, "SAYISAL"))
})

testthat::test_that("build_mode_instructions detay ve odak talimatlarını birleştirir", {
  .summarization_modes_source_once()

  out <- build_mode_instructions("brief", "numerical")
  testthat::expect_true(.contains_ascii(out, "YASAKLAR"))
  testthat::expect_true(.contains_ascii(out, "SAYISAL"))

  # Varsayılan argümanlar standart + genel üretmeli.
  out_default <- build_mode_instructions()
  testthat::expect_true(.contains_ascii(out_default, "STANDART"))
  testthat::expect_true(.contains_ascii(out_default, "ODAK: GENEL"))
})
