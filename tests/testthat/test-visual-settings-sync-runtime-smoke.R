# ==============================================================================
# Dosya Yolu: tests/testthat/test-visual-settings-sync-runtime-smoke.R
# Açıklama: visualSettingsSyncInit() davranışsal runtime smoke testi.
#           Statik sözleşme testlerinden farklı olarak, sohbet arayüzü
#           girdilerinin ayar reaktif durumuna gerçek reaktif tur içinde
#           senkronize edilmesini ve geçersiz değerlerin reddedilmesini
#           doğrular. Tam uygulama, DB, LLM veya tarayıcı gerektirmez.
# ==============================================================================

# server_observers_settings.R bootstrap tarafından source edilmediği için,
# kayıtlı sohbet smoke testindeki savunmacı "source-once" desenini izleriz.
.visual_settings_sync_source_once <- function() {
  if (exists("visualSettingsSyncInit", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_observers_settings.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

testthat::test_that("visualSettingsSyncInit sohbet girdilerini ayar durumuna senkronize eder", {
  testthat::skip_if_not_installed("shiny")
  .visual_settings_sync_source_once()

  shiny::testServer(function(input, output, session) {
    settings_data <- shiny::reactiveValues(
      image_size = "512x512",
      image_quality_hd = FALSE,
      summary_detail_level = "kisa",
      analysis_deep_thinking = FALSE,
      excel_deep_level = "low",
      coding_deep_level = "low"
    )

    visualSettingsSyncInit(input = input, settings_data = settings_data)

    session$userData$.settings_data <- settings_data
  }, {
    # ignoreInit = TRUE observer'ların ilk turu yutmaması için önce flush.
    session$flushReact()
    settings_data <- session$userData$.settings_data

    # Görsel boyut sohbet -> ayar senkronizasyonu.
    session$setInputs(chat_image_size = "1024x1024")
    session$flushReact()
    testthat::expect_identical(settings_data$image_size, "1024x1024")

    # HD kalite bayrağı isTRUE ile boolean'a zorlanır. isTRUE yalnızca
    # uzunluğu 1 olan mantıksal TRUE'yu kabul ettiği için girdi de mantıksal
    # TRUE olmalıdır (örn. "true" metni isTRUE altında FALSE üretir).
    session$setInputs(chat_image_quality_hd = TRUE)
    session$flushReact()
    testthat::expect_true(isTRUE(settings_data$image_quality_hd))

    # Özet detay seviyesi NULL olmadığında güncellenir.
    session$setInputs(chat_summary_detail = "detayli")
    session$flushReact()
    testthat::expect_identical(settings_data$summary_detail_level, "detayli")
  })
})

testthat::test_that("visualSettingsSyncInit derin düşünme seviyesinde yalnızca low/high kabul eder", {
  testthat::skip_if_not_installed("shiny")
  .visual_settings_sync_source_once()

  shiny::testServer(function(input, output, session) {
    settings_data <- shiny::reactiveValues(
      excel_deep_level = "low",
      coding_deep_level = "low",
      analysis_deep_thinking = FALSE
    )

    visualSettingsSyncInit(input = input, settings_data = settings_data)
    session$userData$.settings_data <- settings_data
  }, {
    session$flushReact()
    settings_data <- session$userData$.settings_data

    # Geçerli "high" değeri kabul edilmeli.
    session$setInputs(chat_excel_deep_level = "high")
    session$flushReact()
    testthat::expect_identical(settings_data$excel_deep_level, "high")

    # Geçersiz değer reddedilmeli; önceki geçerli değer korunmalı.
    session$setInputs(chat_excel_deep_level = "ultra")
    session$flushReact()
    testthat::expect_identical(settings_data$excel_deep_level, "high")

    # Kodlama seviyesi de aynı low/high kapısını kullanır.
    session$setInputs(chat_coding_deep_level = "bogus")
    session$flushReact()
    testthat::expect_identical(settings_data$coding_deep_level, "low")

    session$setInputs(chat_coding_deep_level = "high")
    session$flushReact()
    testthat::expect_identical(settings_data$coding_deep_level, "high")

    # Derin düşünme bayrağı isTRUE ile zorlanır (truthy -> TRUE, falsy -> FALSE).
    session$setInputs(chat_deep_thinking = TRUE)
    session$flushReact()
    testthat::expect_true(isTRUE(settings_data$analysis_deep_thinking))

    session$setInputs(chat_deep_thinking = FALSE)
    session$flushReact()
    testthat::expect_false(isTRUE(settings_data$analysis_deep_thinking))
  })
})
