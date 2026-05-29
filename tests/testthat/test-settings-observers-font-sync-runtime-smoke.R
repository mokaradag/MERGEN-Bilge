# ==============================================================================
# Dosya Yolu: tests/testthat/test-settings-observers-font-sync-runtime-smoke.R
# Açıklama: settingsObserversInit() davranışsal runtime smoke testi.
#           Ayarlar modülündeki yazı boyutu değişikliğinin ana sohbet reaktif
#           durumuna (values$current_font_size) gerçek bir reaktif tur içinde
#           yansıtılmasını doğrular. Bu, statik sözleşme testlerinin
#           kanıtlayamadığı modüller arası reaktif senkronizasyon davranışıdır.
#           Tam uygulama, DB, LLM veya tarayıcı gerektirmez.
# ==============================================================================

.settings_observers_source_once <- function() {
  if (exists("settingsObserversInit", envir = globalenv(),
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

testthat::test_that("settingsObserversInit yazı boyutunu ana sohbet durumuna senkronize eder", {
  testthat::skip_if_not_installed("shiny")
  # settingsObserversInit shinyjs::toggleClass çağırdığı için shinyjs gerekir.
  testthat::skip_if_not_installed("shinyjs")
  .settings_observers_source_once()

  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(
      current_font_size = NULL,
      show_welcome = TRUE
    )

    settings_data <- shiny::reactiveValues(
      font_size = 14,
      enable_timestamps = TRUE,
      enable_widescreen = FALSE,
      enable_animations = TRUE
    )

    settingsObserversInit(
      input = input,
      session = session,
      values = values,
      settings_data = settings_data
    )

    session$userData$.values <- values
    session$userData$.settings_data <- settings_data
  }, {
    # Observer'ların ilk turunu tamamlat; font_size observer ignoreInit
    # kullanmadığı için başlangıç değerini durum nesnesine yazar.
    session$flushReact()

    values <- session$userData$.values
    settings_data <- session$userData$.settings_data

    testthat::expect_identical(values$current_font_size, 14)

    # Ayarlardan yazı boyutu değişince ana sohbet durumu güncellenmeli.
    settings_data$font_size <- 18
    session$flushReact()
    testthat::expect_identical(values$current_font_size, 18)

    # İkinci bir değişiklik de en güncel değeri yansıtmalı (bayat durum kalmamalı).
    settings_data$font_size <- 12
    session$flushReact()
    testthat::expect_identical(values$current_font_size, 12)
  })
})
