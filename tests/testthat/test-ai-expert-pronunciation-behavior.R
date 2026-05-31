# ==============================================================================
# Dosya Yolu: tests/testthat/test-ai-expert-pronunciation-behavior.R
# Açıklama: R/helpers_ai_expert.R içindeki sanitize_ai_expert_pronunciation
#           fonksiyonunun DAVRANIŞSAL testleri (mevcut testlerde çağrılmıyordu).
#           CLAUDE.md AI Uzman telaffuz sözleşmesi: yaygın "Bilge Yola" model
#           çıktısı, ardından harf gelmiyorsa "Bilge Yolaç" olarak düzeltilir;
#           "Yoladan" gibi gerçek kelimeler bozulmaz. Saf base R (gsub/perl);
#           TTS/LLM/DB/Shiny GEREKMEZ.
# ==============================================================================

.aepron_source_once <- function() {
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  if (!exists("sanitize_ai_expert_pronunciation",
              envir = globalenv(), mode = "function", inherits = TRUE)) {
    source(
      file.path(resolve_repo_root_for_tests(), "R", "helpers_ai_expert.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  invisible(TRUE)
}

testthat::test_that("sanitize_ai_expert_pronunciation NULL/NA/boş girdiyi değiştirmeden döndürür", {
  .aepron_source_once()
  testthat::expect_null(sanitize_ai_expert_pronunciation(NULL))
  testthat::expect_true(is.na(sanitize_ai_expert_pronunciation(NA_character_)))
  testthat::expect_identical(sanitize_ai_expert_pronunciation(""), "")
})

testthat::test_that("sanitize_ai_expert_pronunciation 'Bilge Yola'yı 'Bilge Yolaç' yapar", {
  .aepron_source_once()
  testthat::expect_identical(sanitize_ai_expert_pronunciation("Bilge Yola"), "Bilge Yolaç")
  # Noktalama harf sayılmaz -> düzeltilir.
  testthat::expect_identical(sanitize_ai_expert_pronunciation("Bilge Yola."), "Bilge Yolaç.")
  # Cümle içinde (boşluk takip ediyor).
  testthat::expect_identical(
    sanitize_ai_expert_pronunciation("Bu Bilge Yola gerçekten harika"),
    "Bu Bilge Yolaç gerçekten harika"
  )
  # Küçük harf varyantı.
  testthat::expect_identical(sanitize_ai_expert_pronunciation("bilge yola"), "bilge yolaç")
})

testthat::test_that("sanitize_ai_expert_pronunciation idempotenttir ve gerçek kelimeleri bozmaz", {
  .aepron_source_once()
  # Zaten doğru: 'Yola' ardından 'ç' (harf) geldiği için tekrar dokunulmaz.
  testthat::expect_identical(sanitize_ai_expert_pronunciation("Bilge Yolaç"), "Bilge Yolaç")
  # 'Yoladan' gerçek bir kelime: ardından 'd' (harf) var -> DEĞİŞTİRİLMEZ.
  testthat::expect_identical(
    sanitize_ai_expert_pronunciation("Bilge Yoladan bahset"),
    "Bilge Yoladan bahset"
  )
})

testthat::test_that("sanitize_ai_expert_pronunciation tüm geçişleri düzeltir ve vektörde ilk öğeyi alır", {
  .aepron_source_once()
  testthat::expect_identical(
    sanitize_ai_expert_pronunciation("Bilge Yola ve Bilge Yola"),
    "Bilge Yolaç ve Bilge Yolaç"
  )
  # Vektör girdi -> yalnızca ilk öğe işlenir.
  testthat::expect_identical(
    sanitize_ai_expert_pronunciation(c("Bilge Yola", "ikinci")),
    "Bilge Yolaç"
  )
})
