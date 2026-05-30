# ==============================================================================
# Dosya Yolu: tests/testthat/test-summarization-prompt-builder-behavior.R
# Açıklama: build_summarization_system_prompt() davranışsal testleri. Ortak
#           rol/katı kurallar, detay seviyesine göre talimat farklılaşması,
#           çoklu dosya bölümü ve odak modu talimatlarının eklenmesi doğrulanır.
#           ASCII çapaları kullanılır. DB/LLM/tarayıcı gerekmez.
# ==============================================================================

.summarization_prompt_source_once <- function() {
  if (exists("build_summarization_system_prompt", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("build_mode_instructions", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  # build_summarization_system_prompt build_mode_instructions'a bağımlıdır.
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_summarization_modes.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_summarization_prompts.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

testthat::test_that("build_summarization_system_prompt ortak rol ve katı kuralları içerir", {
  .summarization_prompt_source_once()

  out <- build_summarization_system_prompt()
  testthat::expect_true(grepl("KATI KURALLAR", enc2utf8(out), fixed = TRUE))
  testthat::expect_true(grepl("MERGEN Bilge", enc2utf8(out), fixed = TRUE))
})

testthat::test_that("build_summarization_system_prompt detay seviyesine göre farklılaşır", {
  .summarization_prompt_source_once()

  out_brief <- enc2utf8(build_summarization_system_prompt(detail_level = "brief"))
  out_detailed <- enc2utf8(build_summarization_system_prompt(detail_level = "detailed"))

  # Kısa modda "3-5" sınırı; detaylı modda "KAPSAMLI" vurgusu.
  testthat::expect_true(grepl("3-5", out_brief, fixed = TRUE))
  testthat::expect_true(grepl("KAPSAMLI", out_detailed, fixed = TRUE))
})

testthat::test_that("build_summarization_system_prompt çoklu dosya bölümü ekler", {
  .summarization_prompt_source_once()

  out_single <- build_summarization_system_prompt(file_count = 1)
  out_multi <- build_summarization_system_prompt(file_count = 3)

  # Çoklu dosya bölümü tek dosya çıktısına göre ek metin getirir.
  testthat::expect_true(nchar(out_multi) > nchar(out_single))
  testthat::expect_true(grepl("3 DOSYA", enc2utf8(out_multi), fixed = TRUE))
})

testthat::test_that("build_summarization_system_prompt odak modu talimatlarını ekler", {
  .summarization_prompt_source_once()

  out_num <- enc2utf8(build_summarization_system_prompt(focus_mode = "numerical"))
  # build_mode_instructions üzerinden sayısal odak talimatı eklenmeli.
  testthat::expect_true(grepl("SAYISAL", out_num, fixed = TRUE))
})
