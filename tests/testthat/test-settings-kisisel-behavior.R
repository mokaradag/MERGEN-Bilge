# ==============================================================================
# Dosya Yolu: tests/testthat/test-settings-kisisel-behavior.R
# Açıklama: R/module_settings_kisisel.R settingsKisiselServer() karar mantığının
#           DAVRANIŞSAL testleri. Bu dosya daha önce hiçbir test tarafından
#           çağrılmıyordu.
#
#           Kapsananlar (shiny::testServer + kök session mesaj yakalama +
#           prime-then-set observer tetikleme):
#           - update_character_display(): persona aksanlarıyla üç custom message.
#           - experience_mode değişiklik doğrulaması (odak/denge/kesif).
#           - save/reset tetikleyici sayaçları.
#
#           get_character_video_data / characterVideoServer stub'lanır; persona
#           tek kaynağı (config_characters) helper_bootstrap.R ile yüklüdür.
#           Gerçek DB/LLM/video GEREKMEZ.
# ==============================================================================

.source_settings_kisisel_for_test <- function() {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  suppressMessages({ library(shiny); library(shinyjs) })
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  # Ağır video bağımlılıkları stub'lanır.
  env$get_character_video_data <- function(char_id) {
    list(character = char_id, image = "", videos = list(intro = list(), loop = list(), select = list()))
  }
  env$characterVideoServer <- function(id, trigger) invisible(NULL)
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_settings_kisisel.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# Kök session üzerinden mesaj yakalayan ve cat() yutan testServer sarmalayıcısı.
.run_kisisel <- function(env, body) {
  rec <- new.env(); rec$msgs <- list()
  invisible(utils::capture.output(
    shiny::testServer(
      env$settingsKisiselServer,
      args = list(settings = shiny::reactiveValues(selected_character = "emre", experience_mode = "odak")),
      {
        root <- .subset2(session, "parent")
        root$sendCustomMessage <- function(type, message) {
          rec$msgs[[length(rec$msgs) + 1L]] <- list(type = type, message = message)
          invisible(TRUE)
        }
        body(session, rec)
      }
    )
  ))
  rec
}

.msgs_of_type <- function(rec, type) {
  Filter(function(m) identical(m$type, type), rec$msgs)
}

# ------------------------------------------------------------------------------
# Dönen yapı
# ------------------------------------------------------------------------------
testthat::test_that("settingsKisiselServer beklenen koordinatör listesini döndürür", {
  env <- .source_settings_kisisel_for_test()
  captured <- NULL
  .run_kisisel(env, function(session, rec) {
    captured <<- session$returned
  })
  testthat::expect_true(is.list(captured))
  testthat::expect_true(all(c(
    "save_trigger", "reset_trigger", "temp_selected_character",
    "temp_experience_mode", "mode_was_clicked", "update_character_display"
  ) %in% names(captured)))
  testthat::expect_true(is.function(captured$update_character_display))
})

# ------------------------------------------------------------------------------
# update_character_display
# ------------------------------------------------------------------------------
testthat::test_that("update_character_display persona aksanlarıyla üç custom message gönderir", {
  env <- .source_settings_kisisel_for_test()
  rec <- .run_kisisel(env, function(session, rec) {
    session$returned$update_character_display("emre")
  })

  testthat::expect_true(length(.msgs_of_type(rec, "updateCharacterButtons")) >= 1L)
  testthat::expect_true(length(.msgs_of_type(rec, "transitionCharacterImage")) >= 1L)
  testthat::expect_true(length(.msgs_of_type(rec, "updateCharacterInfoTyping")) >= 1L)

  # updateCharacterButtons mesajı persona kimliğini ve aksan rengini içermeli.
  btn <- .msgs_of_type(rec, "updateCharacterButtons")
  son <- btn[[length(btn)]]$message
  testthat::expect_identical(son$character, "emre")
  testthat::expect_true(is.character(son$accent) && nzchar(son$accent))
})

testthat::test_that("update_character_display eski persona kimliğini normalize eder", {
  env <- .source_settings_kisisel_for_test()
  rec <- .run_kisisel(env, function(session, rec) {
    session$returned$update_character_display("erlik")  # eski kimlik
  })
  btn <- .msgs_of_type(rec, "updateCharacterButtons")
  son <- btn[[length(btn)]]$message
  # erlik -> can (göç sözleşmesi).
  testthat::expect_identical(son$character, "can")
})

# ------------------------------------------------------------------------------
# experience_mode doğrulaması
# ------------------------------------------------------------------------------
testthat::test_that("geçerli deneyim modu seçimi temp moda yazılır ve tıklandı işaretlenir", {
  env <- .source_settings_kisisel_for_test()
  sonuc <- new.env()
  .run_kisisel(env, function(session, rec) {
    # prime-then-set: gözlemci 'denge' değerini okur.
    session$setInputs(experience_mode_changed = list(mode = "__prime__"))
    session$setInputs(experience_mode_changed = list(mode = "denge"))
    sonuc$mode <- session$returned$temp_experience_mode()
    sonuc$clicked <- session$returned$mode_was_clicked()
  })
  testthat::expect_identical(sonuc$mode, "denge")
  testthat::expect_true(sonuc$clicked)
})

testthat::test_that("geçersiz deneyim modu reddedilir, varsayılan korunur", {
  env <- .source_settings_kisisel_for_test()
  sonuc <- new.env()
  .run_kisisel(env, function(session, rec) {
    session$setInputs(experience_mode_changed = list(mode = "odak"))
    session$setInputs(experience_mode_changed = list(mode = "gecersiz_mod"))
    sonuc$mode <- session$returned$temp_experience_mode()
    sonuc$clicked <- session$returned$mode_was_clicked()
  })
  # 'gecersiz_mod' beyaz listede yok -> temp varsayılan 'odak' kalır, clicked FALSE.
  testthat::expect_identical(sonuc$mode, "odak")
  testthat::expect_false(sonuc$clicked)
})

# ------------------------------------------------------------------------------
# save/reset tetikleyicileri
# ------------------------------------------------------------------------------
testthat::test_that("save_settings tetikleyici sayacını artırır", {
  env <- .source_settings_kisisel_for_test()
  sonuc <- new.env()
  .run_kisisel(env, function(session, rec) {
    onceki <- session$returned$save_trigger()
    session$setInputs(save_settings = 1)
    session$setInputs(save_settings = 2)
    sonuc$delta <- session$returned$save_trigger() - onceki
  })
  testthat::expect_true(sonuc$delta >= 1)
})

testthat::test_that("reset_settings tetikleyici sayacını artırır", {
  env <- .source_settings_kisisel_for_test()
  sonuc <- new.env()
  .run_kisisel(env, function(session, rec) {
    onceki <- session$returned$reset_trigger()
    session$setInputs(reset_settings = 1)
    session$setInputs(reset_settings = 2)
    sonuc$delta <- session$returned$reset_trigger() - onceki
  })
  testthat::expect_true(sonuc$delta >= 1)
})
