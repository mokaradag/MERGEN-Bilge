# ==============================================================================
# Dosya Yolu: tests/testthat/test-startup-lane-pending-save-behavior.R
# Açıklama: Başlangıç Deneyimi (startup lane) ayarının BEKLEYEN-vs-KAYITLI
#           davranış sözleşmesi:
#             1) Yapılandırma radyosu yalnızca bekleyen (pending) durumu
#                günceller; settings$startup_lane DEĞİŞMEZ.
#             2) "Ayarları Kaydet" akışındaki mergen_apply_saved_startup_lane()
#                bekleyen değeri gerçek yapılandırmaya işler ve istemciye
#                applyStartupLane gönderir.
#             3) Kayıtlı şerit değiştiğinde (geri yükleme/kaydetme) radyo ve
#                bekleyen değer kayıtlı duruma hizalanır.
#             4) Geçersiz/boş bekleyen değer ve değişmeyen şerit no-op'tur.
#           Gerçek DB/LLM/tarayıcı GEREKMEZ.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.lane_pending_env <- function() {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "helpers_startup_lane.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "module_startup_lane.R"), encoding = "UTF-8", local = env)
  env
}

.lane_fake_session <- function() {
  rec <- new.env(parent = emptyenv())
  rec$msgs <- list()
  list(
    sendCustomMessage = function(type, message) {
      rec$msgs[[length(rec$msgs) + 1L]] <- list(type = type, message = message)
      invisible(TRUE)
    },
    rec = rec
  )
}

testthat::test_that("mergen_apply_saved_startup_lane bekleyen şeridi kaydeder ve istemciye uygular", {
  testthat::skip_if_not_installed("shiny")
  env <- .lane_pending_env()

  settings <- shiny::reactiveValues(startup_lane = "rich_lane")
  sess <- .lane_fake_session()

  sonuc <- NULL
  invisible(utils::capture.output(
    sonuc <- env$mergen_apply_saved_startup_lane(sess, settings, "fast_lane")
  ))

  testthat::expect_true(isTRUE(sonuc))
  testthat::expect_identical(shiny::isolate(settings$startup_lane), "fast_lane")

  tipler <- vapply(sess$rec$msgs, function(m) m$type, character(1))
  testthat::expect_true("applyStartupLane" %in% tipler)
  lane_msg <- sess$rec$msgs[[which(tipler == "applyStartupLane")[1]]]$message
  testthat::expect_identical(lane_msg$lane, "fast_lane")
})

testthat::test_that("geçersiz/boş bekleyen değer ve değişmeyen şerit no-op'tur", {
  testthat::skip_if_not_installed("shiny")
  env <- .lane_pending_env()

  settings <- shiny::reactiveValues(startup_lane = "rich_lane")
  sess <- .lane_fake_session()

  # NULL bekleyen değer: kullanıcı radyoya hiç dokunmadı.
  testthat::expect_false(isTRUE(env$mergen_apply_saved_startup_lane(sess, settings, NULL)))
  # Geçersiz değer.
  testthat::expect_false(isTRUE(env$mergen_apply_saved_startup_lane(sess, settings, "ask_once")))
  testthat::expect_false(isTRUE(env$mergen_apply_saved_startup_lane(sess, settings, "garip")))
  # Aynı şerit: değişiklik yok.
  testthat::expect_false(isTRUE(env$mergen_apply_saved_startup_lane(sess, settings, "rich_lane")))

  testthat::expect_identical(shiny::isolate(settings$startup_lane), "rich_lane")
  testthat::expect_length(sess$rec$msgs, 0L)
})

testthat::test_that("radyo seçimi yalnızca bekleyen durumu günceller; kayıt ancak kaydetmede olur", {
  testthat::skip_if_not_installed("shiny")

  ycfg_env <- new.env(parent = globalenv())
  ycfg_env$`%||%` <- function(a, b) if (is.null(a)) b else a
  ycfg_env$api_config <- list(local_models = c("model-a", "model-b"))
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "module_settings_yapilandirma.R"), encoding = "UTF-8", local = ycfg_env)

  lane_env <- .lane_pending_env()

  shiny::testServer(
    function(input, output, session) {
      settings <- shiny::reactiveValues(startup_lane = "rich_lane")
      out <- ycfg_env$settingsYapilandirmaServer("ycfg", settings, session)
      session$userData$.settings <- settings
      session$userData$.out <- out
    },
    {
      session$flushReact()
      settings <- session$userData$.settings
      out <- session$userData$.out

      # Kayıtlı şerit senkronu: modül açılışında bekleyen değer kayıtlıya eşitlenir.
      testthat::expect_identical(out$temp_startup_lane(), "rich_lane")

      # 1) Kullanıcı radyodan Hızlı Başlangıç seçer: yalnızca pending değişir.
      session$setInputs(`ycfg-startup_experience_lane` = "fast_lane")
      session$flushReact()
      testthat::expect_identical(out$temp_startup_lane(), "fast_lane")
      testthat::expect_identical(shiny::isolate(settings$startup_lane), "rich_lane")

      # 2) "Ayarları Kaydet" eşdeğeri: bekleyen değer kayda işlenir.
      sess2 <- .lane_fake_session()
      invisible(utils::capture.output(
        lane_env$mergen_apply_saved_startup_lane(sess2, settings, out$temp_startup_lane())
      ))
      session$flushReact()
      testthat::expect_identical(shiny::isolate(settings$startup_lane), "fast_lane")

      # 3) Kayıtlı şerit değişimi (geri yükleme senaryosu) pending'i hizalar.
      settings$startup_lane <- "rich_lane"
      session$flushReact()
      testthat::expect_identical(out$temp_startup_lane(), "rich_lane")
    }
  )
})

testthat::test_that("radyo değişikliği anında saveSettings/applyStartupLane GÖNDERMEZ (statik koruma)", {
  kok <- resolve_repo_root_for_tests()
  raw_data <- readBin(
    file.path(kok, "R", "module_settings_yapilandirma.R"),
    what = "raw",
    n = file.info(file.path(kok, "R", "module_settings_yapilandirma.R"))$size[1]
  )
  txt <- suppressWarnings(iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]])

  # startup_experience_lane gözlemcisinin gövdesini yakala ve içinde kalıcılaştırma
  # mesajı olmadığını doğrula (bekleyen-durum sözleşmesi).
  blok <- regmatches(
    txt,
    regexpr(
      "observeEvent\\(input\\$startup_experience_lane[\\s\\S]*?ignoreInit = TRUE\\)",
      txt,
      perl = TRUE
    )
  )
  testthat::expect_length(blok, 1L)
  testthat::expect_false(grepl("saveSettings", blok, fixed = TRUE))
  testthat::expect_false(grepl("applyStartupLane", blok, fixed = TRUE))
  testthat::expect_true(grepl("temp_startup_lane(lane)", blok, fixed = TRUE))

  # Kaydet akışı bekleyen şeridi uygular (koordinatör sözleşmesi).
  coord_raw <- readBin(
    file.path(kok, "R", "module_settings.R"),
    what = "raw",
    n = file.info(file.path(kok, "R", "module_settings.R"))$size[1]
  )
  coord_txt <- suppressWarnings(iconv(list(coord_raw), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]])
  testthat::expect_true(grepl(
    "mergen_apply_saved_startup_lane(session, settings, yapilandirma$temp_startup_lane())",
    coord_txt,
    fixed = TRUE
  ))
})
