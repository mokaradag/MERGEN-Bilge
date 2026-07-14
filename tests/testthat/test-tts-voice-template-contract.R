# ==============================================================================
# Dosya Yolu: tests/testthat/test-tts-voice-template-contract.R
# Açıklama: deployment/tts_voices_template/ yalnızca yer tutucu + örnek dosya
#           içerir. Gerçek biyometrik referans WAV, gerçek manifest veya gerçek
#           transcript ASLA depoda bulunmamalıdır.
# ==============================================================================

.tts_template_root <- resolve_repo_root_for_tests()
.tts_template_dir <- file.path(.tts_template_root, "deployment", "tts_voices_template")

test_that("şablon dizini ve beklenen yer tutucu/örnek dosyalar mevcuttur", {
  expect_true(dir.exists(.tts_template_dir))
  expect_true(file.exists(file.path(.tts_template_dir, "README.md")))
  expect_true(file.exists(file.path(.tts_template_dir, "manifest.example.json")))
  expect_true(file.exists(file.path(.tts_template_dir, "reference_transcript_tr_v1.txt.example")))
  for (id in c("emre", "selin", "deniz", "can", "ipek")) {
    expect_true(dir.exists(file.path(.tts_template_dir, id)),
                info = paste0("Persona klasörü eksik: ", id))
    expect_true(file.exists(file.path(.tts_template_dir, id, ".gitkeep")),
                info = paste0(".gitkeep eksik: ", id))
  }
})

test_that("şablon altında hiçbir gerçek .wav dosyası bulunmaz", {
  wavs <- list.files(.tts_template_dir, pattern = "\\.wav$", recursive = TRUE,
                     full.names = TRUE, ignore.case = TRUE)
  expect_length(wavs, 0L)
})

test_that("şablon altında gerçek manifest.json veya gerçek transcript bulunmaz", {
  expect_false(file.exists(file.path(.tts_template_dir, "manifest.json")))
  expect_false(file.exists(file.path(.tts_template_dir, "reference_transcript_tr_v1.txt")))
})

test_that(".gitignore şablon altındaki gerçek biyometrik verileri yok sayar", {
  gi <- readLines(file.path(.tts_template_root, ".gitignore"), warn = FALSE, encoding = "UTF-8")
  expect_true(any(grepl("deployment/tts_voices_template/\\*\\*/\\*\\.wav", gi)))
  expect_true(any(grepl("deployment/tts_voices_template/manifest\\.json", gi)))
  expect_true(any(grepl("deployment/tts_voices_template/reference_transcript_tr_v1\\.txt", gi)))
})

test_that("manifest.example.json geçerli şema ve beş bilinen profili taşır", {
  man <- jsonlite::fromJSON(file.path(.tts_template_dir, "manifest.example.json"), simplifyVector = FALSE)
  expect_identical(as.integer(man$schema_version), 1L)
  expect_true(!is.null(man$transcripts$tr_common_v1))
  expect_identical(sort(names(man$profiles)), sort(c("emre", "selin", "deniz", "can", "ipek")))
  for (p in man$profiles) {
    expect_identical(p$transcript_id, "tr_common_v1")
    expect_true(isTRUE(p$enabled))
  }
})
