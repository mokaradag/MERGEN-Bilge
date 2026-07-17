# ==============================================================================
# Dosya Yolu: tests/testthat/test-speech-asset-tree-contract.R
# Açıklama: Depoya commit edilmiş GERÇEK www/speech metin ağacının sözleşmesi:
#           5 persona, 14 rehberli sayfa, 10 karşılama + sayfa başına 10 çeşit,
#           toplam 150 ortak metin, kararlı _01.._10 adlandırma, sessiz
#           sayfalara metin YOK, boş/geçersiz UTF-8 metin YOK ve persona ses
#           klasörü iskeleti. Sayılar tek yetkili yapılandırmadan türetilir.
# ==============================================================================

testthat::test_that("konuşma yapılandırması beklenen sayıları türetir", {
  speech_tests_source_chain()

  testthat::expect_identical(length(mergen_speech_personas()), 5L)
  testthat::expect_setequal(
    mergen_speech_personas(),
    c("emre", "selin", "deniz", "can", "ipek")
  )
  testthat::expect_identical(length(mergen_speech_guided_pages()), 14L)
  testthat::expect_identical(mergen_speech_variant_count(), 10L)
  testthat::expect_identical(mergen_speech_expected_script_count(), 150L)
  testthat::expect_identical(mergen_speech_expected_audio_per_persona(), 150L)
  testthat::expect_identical(mergen_speech_expected_audio_total(), 750L)
})

testthat::test_that("rehberli sayfa kimlikleri gerçek sekme kimlikleriyle eşleşir", {
  speech_tests_source_chain()
  repo_root <- resolve_repo_root_for_tests()

  ui_bytes <- readBin(file.path(repo_root, "ui.R"), "raw",
                      n = file.info(file.path(repo_root, "ui.R"))$size)
  ui_txt <- iconv(rawToChar(ui_bytes), from = "UTF-8", to = "UTF-8", sub = "byte")

  for (page in names(mergen_speech_guided_pages())) {
    testthat::expect_true(
      grepl(sprintf('tabName = "%s"', page), ui_txt, fixed = TRUE, useBytes = TRUE),
      info = sprintf("Rehberli sayfa kimliği ui.R'de yok: %s", page)
    )
  }
  for (page in mergen_speech_silent_pages()) {
    testthat::expect_true(
      grepl(sprintf('tabName = "%s"', page), ui_txt, fixed = TRUE, useBytes = TRUE),
      info = sprintf("Sessiz sayfa kimliği ui.R'de yok: %s", page)
    )
  }
})

testthat::test_that("rehberli ve sessiz sayfa kümeleri ayrıktır", {
  speech_tests_source_chain()

  testthat::expect_length(
    intersect(names(mergen_speech_guided_pages()), mergen_speech_silent_pages()), 0L
  )
  # Boşta konuşma sessiz kümesi rehberlikten bağımsızdır ama chat İÇERMEZ
  testthat::expect_false("chat" %in% mergen_speech_idle_muted_pages())
  testthat::expect_true("settings_kisisel" %in% mergen_speech_idle_muted_pages())
  testthat::expect_true(all(
    c("ortak_calismalar", "ortak_sohbetler", "ortak_bilge_yolac") %in%
      mergen_speech_idle_muted_pages()
  ))
})

testthat::test_that("gerçek metin ağacı 150 dosyayı doğru adlarla içerir", {
  speech_tests_source_chain()
  repo_root <- resolve_repo_root_for_tests()
  root <- file.path(repo_root, "www", "speech")

  expected <- mergen_speech_expected_assets(root)
  testthat::expect_identical(nrow(expected), 150L)

  missing <- expected$script_path[!file.exists(expected$script_path)]
  testthat::expect_length(missing, 0L)

  # Fazla/sahipsiz metin dosyası olmamalı; adlandırma _01.._10 kalıbında olmalı
  on_disk <- list.files(file.path(root, "scripts"), pattern = "\\.txt$",
                        recursive = TRUE, full.names = TRUE)
  testthat::expect_identical(length(on_disk), 150L)
  testthat::expect_true(all(grepl("_(0[1-9]|10)\\.txt$", basename(on_disk))))

  # Sessiz sayfalar için metin klasörü OLMAMALI
  page_dirs <- basename(list.dirs(file.path(root, "scripts", "pages"),
                                  recursive = FALSE))
  testthat::expect_setequal(page_dirs, names(mergen_speech_guided_pages()))
  testthat::expect_length(intersect(page_dirs, mergen_speech_silent_pages()), 0L)
})

testthat::test_that("gerçek metinler boş değildir ve geçerli UTF-8 Türkçe içerir", {
  speech_tests_source_chain()
  repo_root <- resolve_repo_root_for_tests()
  root <- file.path(repo_root, "www", "speech")

  expected <- mergen_speech_expected_assets(root)
  has_turkish <- FALSE

  for (i in seq_len(nrow(expected))) {
    txt <- .speech_read_utf8_text(expected$script_path[i])
    testthat::expect_false(
      is.null(txt) || !nzchar(txt),
      info = sprintf("Metin boş/geçersiz UTF-8: %s", expected$script_path[i])
    )
    if (!is.null(txt) && grepl("[çğıöşü]", txt)) {
      has_turkish <- TRUE
    }
  }

  testthat::expect_true(has_turkish)
})

testthat::test_that("persona ses klasörü iskeleti ve referans metinleri tamdır", {
  speech_tests_source_chain()
  repo_root <- resolve_repo_root_for_tests()
  root <- file.path(repo_root, "www", "speech")

  for (persona in mergen_speech_personas()) {
    ref_path <- mergen_speech_reference_text_path(persona, root)
    testthat::expect_true(file.exists(ref_path),
                          info = sprintf("reference.txt yok: %s", persona))

    txt <- .speech_read_utf8_text(ref_path)
    testthat::expect_true(!is.null(txt) && nchar(txt) > 40,
                          info = sprintf("reference.txt kısa/geçersiz: %s", persona))

    # Ses klasörü iskeleti: her persona için audio/<persona>/welcome ve pages
    testthat::expect_true(dir.exists(file.path(root, "audio", persona, "welcome")))
    testthat::expect_true(dir.exists(file.path(root, "audio", persona, "pages")))
  }
})

testthat::test_that("üretilmiş varlıklar GitHub'da tutulmaz (.gitignore sözleşmesi)", {
  repo_root <- resolve_repo_root_for_tests()
  gitignore <- readLines(file.path(repo_root, ".gitignore"), warn = FALSE)

  for (rule in c(
    "www/speech/voices/*/reference.wav",
    "www/speech/voices/*/voice-lock.json",
    "www/speech/audio/**/*.wav",
    "www/speech/generated/speech_manifest.json",
    "www/speech/generated/*state*",
    "www/speech/generated/*lock*",
    "www/speech/generated/*progress*"
  )) {
    testthat::expect_true(rule %in% gitignore,
                          info = sprintf(".gitignore kuralı eksik: %s", rule))
  }
})
