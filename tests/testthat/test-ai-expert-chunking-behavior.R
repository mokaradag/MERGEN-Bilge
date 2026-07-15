# ==============================================================================
# Dosya Yolu: tests/testthat/test-ai-expert-chunking-behavior.R
# Açıklama: split_text_for_ai_expert_tts() davranışsal testleri. AI Uzman TTS
#           metninin cümle sınırlarından kısa parçalara bölünmesini doğrular.
#           Saf, yan etkisiz metin yardımcısıdır; DB/LLM/tarayıcı gerekmez.
#           Girdiler ASCII tutularak yerel ayar kırılganlığı önlenir.
# ==============================================================================

.ai_expert_chunking_source_once <- function() {
  if (exists("split_text_for_ai_expert_tts", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_ai_expert_chunking.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

testthat::test_that("split_text_for_ai_expert_tts boş girdide boş liste döner", {
  .ai_expert_chunking_source_once()

  testthat::expect_identical(split_text_for_ai_expert_tts(""), list())
  testthat::expect_identical(split_text_for_ai_expert_tts(NULL), list())
  testthat::expect_identical(split_text_for_ai_expert_tts("   "), list())
})

testthat::test_that("split_text_for_ai_expert_tts kısa metni tek parça olarak döner", {
  .ai_expert_chunking_source_once()

  out <- split_text_for_ai_expert_tts("Merhaba dunya.")
  testthat::expect_true(is.list(out))
  testthat::expect_identical(length(out), 1L)
  testthat::expect_identical(out[[1]], "Merhaba dunya.")
})

testthat::test_that("split_text_for_ai_expert_tts kısa max_chunk ile çoklu parça üretir", {
  .ai_expert_chunking_source_once()

  # Her biri ~42 karakterlik 4 cümle; max=60 iken her cümle ayrı parça olur.
  cumle <- paste0(paste(rep("kelime", 6), collapse = " "), ".")
  metin <- paste(rep(cumle, 4), collapse = " ")

  out <- split_text_for_ai_expert_tts(metin, max_chunk_chars = 60, min_chunk_chars = 20)

  testthat::expect_true(is.list(out))
  testthat::expect_true(length(out) >= 2L)
  # Her parça (normal kelimelerden oluştuğu için) max sınırını aşmamalı.
  parca_uzunluklari <- vapply(out, nchar, integer(1))
  testthat::expect_true(all(parca_uzunluklari <= 60L))
})

testthat::test_that("split_text_for_ai_expert_tts cümleleri birleştirip parça döndürür", {
  .ai_expert_chunking_source_once()

  # Kısa cümleler büyük max altında tek parçada birleşir.
  out <- split_text_for_ai_expert_tts("Bir. Iki. Uc.", max_chunk_chars = 220, min_chunk_chars = 70)
  testthat::expect_identical(length(out), 1L)
  testthat::expect_true(grepl("Bir.", out[[1]], fixed = TRUE))
  testthat::expect_true(grepl("Uc.", out[[1]], fixed = TRUE))
})

# ------------------------------------------------------------------------------
# .ai_expert_split_long_piece (iç yardımcı: uzun parça bölme)
# split_text_for_ai_expert_tts'in çağırdığı düşük seviyeli bölücü.
# ------------------------------------------------------------------------------
testthat::test_that(".ai_expert_split_long_piece boş/kısa girdileri ele alır", {
  .ai_expert_chunking_source_once()
  # Boş/yalnızca boşluk => character(0).
  testthat::expect_identical(.ai_expert_split_long_piece(""), character(0))
  testthat::expect_identical(.ai_expert_split_long_piece("   "), character(0))
  # max'tan kısa => tek parça (aynen).
  testthat::expect_identical(.ai_expert_split_long_piece("kisa cumle"), "kisa cumle")
  testthat::expect_identical(.ai_expert_split_long_piece("kisa cumle", 220L), "kisa cumle")
})

testthat::test_that(".ai_expert_split_long_piece virgül/sınır noktalarında böler", {
  .ai_expert_chunking_source_once()
  giris <- "birinci bolum buraya, ikinci bolum biraz daha uzun, ucuncu bolum da var"
  res <- .ai_expert_split_long_piece(giris, 30L)
  testthat::expect_identical(
    res,
    c("birinci bolum buraya,", "ikinci bolum biraz daha uzun,", "ucuncu bolum da var")
  )
  # Her parça sınırı aşmaz.
  testthat::expect_true(all(nchar(res) <= 30L))
})

testthat::test_that(".ai_expert_split_long_piece virgül yoksa kelime kelime böler", {
  .ai_expert_chunking_source_once()
  giris <- paste(rep("kelime", 10), collapse = " ")
  res <- .ai_expert_split_long_piece(giris, 20L)
  testthat::expect_identical(
    res,
    c("kelime kelime kelime", "kelime kelime kelime", "kelime kelime kelime", "kelime")
  )
  testthat::expect_true(all(nchar(res) <= 20L))
})

testthat::test_that(".ai_expert_split_long_piece bölünemeyen tek uzun kelimeyi korur", {
  .ai_expert_chunking_source_once()
  # Tek kelime sınırı aşsa bile bölünemez; olduğu gibi döner.
  testthat::expect_identical(.ai_expert_split_long_piece("supercalifragilistic", 5L),
                             "supercalifragilistic")
  testthat::expect_type(.ai_expert_split_long_piece("a b c d e f g h", 5L), "character")
})