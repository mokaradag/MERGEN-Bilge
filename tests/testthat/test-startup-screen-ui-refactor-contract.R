# ==============================================================================
# Dosya Yolu: tests/testthat/test-startup-screen-ui-refactor-contract.R
# Açıklama: Derin uzay giriş ekranı UI/sunucu ayrımı sözleşmesi ve veri-odaklı
#           deneyim-modu kartı davranışı. createStartupScreenUI() ve saf
#           .startup_*() yapıcıları R/module_startup_screen_ui.R içindedir;
#           sunucu gözlemcileri R/module_startup_screen.R'de kalır. Üç mod kartı
#           tek bir .startup_mode_card() üzerinden üretilir (tekrar yok).
#           Gerçek Three.js/tarayıcı/müzik gerektirmez.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.startup_repo_root <- resolve_repo_root_for_tests()
.startup_ui_path <- file.path(.startup_repo_root, "R", "module_startup_screen_ui.R")
.startup_srv_path <- file.path(.startup_repo_root, "R", "module_startup_screen.R")

# UI yapıcıları yalıtılmış ortama yüklenir.
.startup_ui_env <- new.env(parent = globalenv())
source(.startup_ui_path, encoding = "UTF-8", local = .startup_ui_env)
.startup_ui_env$get_current_version <- function() "1.0"

# ASCII çapaları için bayt-güvenli okuyucu (Windows VM'de geçersiz UTF-8'e dayanıklı).
.startup_read_bytes <- function(path) {
  raw <- readBin(path, what = "raw", n = file.info(path)$size)
  iconv(rawToChar(raw), from = "UTF-8", to = "UTF-8", sub = "byte")
}

# -----------------------------------------------------------------------------
# UI/sunucu ayrım sözleşmesi
# -----------------------------------------------------------------------------

test_that("createStartupScreenUI ve saf .startup_* yapıcıları UI dosyasındadır", {
  expect_true(file.exists(.startup_ui_path))

  expect_true(exists("createStartupScreenUI", envir = .startup_ui_env, inherits = FALSE))
  expect_true(exists(".startup_mode_card", envir = .startup_ui_env, inherits = FALSE))
  expect_true(exists(".startup_mode_card_defs", envir = .startup_ui_env, inherits = FALSE))
  expect_true(exists(".startup_mode_feature_defs", envir = .startup_ui_env, inherits = FALSE))
  expect_true(exists(".startup_mode_feature_icon", envir = .startup_ui_env, inherits = FALSE))
  expect_true(exists(".startup_mode_modal", envir = .startup_ui_env, inherits = FALSE))
  expect_true(exists(".startup_character_step", envir = .startup_ui_env, inherits = FALSE))
})

test_that("sunucu dosyası UI yapıcısını içermez, gözlemcileri içerir", {
  srv_env <- new.env(parent = globalenv())
  source(.startup_srv_path, encoding = "UTF-8", local = srv_env)

  expect_false(exists("createStartupScreenUI", envir = srv_env, inherits = FALSE))
  expect_true(exists("startupScreenObserversInit", envir = srv_env, inherits = FALSE))
  expect_true(exists("apply_experience_mode", envir = srv_env, inherits = FALSE))

  # Kaynak metninde de UI yapıcısı sunucu dosyasına geri taşınmamalı.
  srv_text <- .startup_read_bytes(.startup_srv_path)
  expect_false(grepl("createStartupScreenUI <- function", srv_text, fixed = TRUE, useBytes = TRUE))
})

test_that("manifest UI dosyasını sunucu dosyasından önce yükler", {
  expect_source_manifest_contains_for_tests(c(
    "R/module_startup_screen_ui.R",
    "R/module_startup_screen.R"
  ))
  expect_source_manifest_order_for_tests(c(
    "R/module_startup_screen_ui.R",
    "R/module_startup_screen.R"
  ))
})

test_that("üç mod kartı tek veri-odaklı yapıcı üzerinden üretilir (kopyalama yok)", {
  ui_text <- .startup_read_bytes(.startup_ui_path)

  # Kart kabuğu yalnızca .startup_mode_card içinde bir kez tanımlanmalı.
  card_shell_hits <- length(gregexpr("cinematic-mode-card spotlight-card", ui_text, fixed = TRUE)[[1]])
  expect_equal(card_shell_hits, 1L)

  # Kartlar listeden üretilmeli (3 kez elle yazılmamalı).
  expect_true(grepl("lapply(.startup_mode_card_defs(), .startup_mode_card)", ui_text, fixed = TRUE, useBytes = TRUE))
})

# -----------------------------------------------------------------------------
# Veri tabloları (saf)
# -----------------------------------------------------------------------------

test_that(".startup_mode_feature_defs beş özelliği doğru sırada tanımlar", {
  defs <- .startup_ui_env$.startup_mode_feature_defs()
  expect_equal(length(defs), 5L)
  expect_equal(
    vapply(defs, function(f) f$key, character(1)),
    c("tts", "followup", "music", "sound", "character")
  )
  # Türkçe etiketler kullanıcıya görünür ipuçlarını besler.
  expect_equal(defs[[1]]$label, "Sesli Yanıt")
  expect_equal(defs[[5]]$label, "Asistan Karakteri")
})

test_that(".startup_mode_card_defs üç modu doğru sırada ve durumlarla tanımlar", {
  defs <- .startup_ui_env$.startup_mode_card_defs()
  expect_equal(vapply(defs, function(d) d$mode, character(1)), c("odak", "denge", "kesif"))
  expect_equal(vapply(defs, function(d) d$title, character(1)), c("Odak", "Dinamik", "Bütünleşik"))

  odak <- defs[[1]]$states
  denge <- defs[[2]]$states
  kesif <- defs[[3]]$states

  expect_true(all(!odak))                       # Odak: tüm özellikler kapalı
  expect_true(all(kesif))                        # Bütünleşik: tüm özellikler açık
  expect_false(denge[["tts"]])
  expect_true(denge[["followup"]])
  expect_true(denge[["music"]])
  expect_true(denge[["sound"]])
  expect_false(denge[["character"]])
})

# -----------------------------------------------------------------------------
# .startup_mode_feature_icon (dedup çekirdeği)
# -----------------------------------------------------------------------------

test_that(".startup_mode_feature_icon açık/kapalı durum sınıfı, ikon ve ipucunu doğru üretir", {
  skip_if_not_installed("shiny")
  feat <- list(key = "tts", label = "Sesli Yanıt", icon_off = "fa-volume-mute", icon_on = "fa-volume-up")

  off_html <- as.character(.startup_ui_env$.startup_mode_feature_icon(feat, FALSE))
  on_html <- as.character(.startup_ui_env$.startup_mode_feature_icon(feat, TRUE))

  expect_true(grepl('class="cinematic-feature-icon off"', off_html, fixed = TRUE))
  expect_true(grepl('data-feature="tts"', off_html, fixed = TRUE))
  expect_true(grepl('data-tooltip="Sesli Yanıt: Kapalı"', off_html, fixed = TRUE))
  expect_true(grepl('class="fas fa-volume-mute"', off_html, fixed = TRUE))

  expect_true(grepl('class="cinematic-feature-icon on"', on_html, fixed = TRUE))
  expect_true(grepl('data-tooltip="Sesli Yanıt: Aktif"', on_html, fixed = TRUE))
  expect_true(grepl('class="fas fa-volume-up"', on_html, fixed = TRUE))
})

# -----------------------------------------------------------------------------
# .startup_mode_card (tüm modlar için özellik durumları)
# -----------------------------------------------------------------------------

# Belirli bir modun kartını HTML'e çevirir.
.startup_card_html <- function(mode) {
  defs <- .startup_ui_env$.startup_mode_card_defs()
  def <- Filter(function(d) d$mode == mode, defs)[[1]]
  as.character(.startup_ui_env$.startup_mode_card(def))
}

test_that("Odak kartı tüm özellikleri kapalı ikon/sınıf/ipucu ile üretir", {
  skip_if_not_installed("shiny")
  html <- .startup_card_html("odak")

  expect_true(grepl('data-mode="odak"', html, fixed = TRUE))
  expect_true(grepl("Maksimum hız, mutlak sadelik.", html, fixed = TRUE))
  expect_true(grepl('class="fas fa-bolt cinematic-card-icon"', html, fixed = TRUE))
  # Tüm özellikler kapalı: kapalı ikonlar ve ": Kapalı" ipuçları.
  expect_true(grepl('class="fas fa-volume-mute"', html, fixed = TRUE))   # tts off
  expect_true(grepl('class="fas fa-bell-slash"', html, fixed = TRUE))    # sound off
  expect_true(grepl('class="fas fa-user-slash"', html, fixed = TRUE))    # character off
  expect_true(grepl('data-tooltip="Sesli Yanıt: Kapalı"', html, fixed = TRUE))
  expect_false(grepl('cinematic-feature-icon on"', html, fixed = TRUE))  # hiç açık yok
})

test_that("Bütünleşik kartı tüm özellikleri açık ikon/ipucu ile üretir", {
  skip_if_not_installed("shiny")
  html <- .startup_card_html("kesif")

  expect_true(grepl('data-mode="kesif"', html, fixed = TRUE))
  expect_true(grepl("Tüm sistemlerin kilidini açın.", html, fixed = TRUE))
  expect_true(grepl('class="fas fa-microchip cinematic-card-icon"', html, fixed = TRUE))
  expect_true(grepl('class="fas fa-volume-up"', html, fixed = TRUE))         # tts on
  expect_true(grepl('class="fas fa-bell"', html, fixed = TRUE))              # sound on (bell-slash değil)
  expect_true(grepl('class="fas fa-user-astronaut"', html, fixed = TRUE))    # character on
  expect_true(grepl('data-tooltip="Asistan Karakteri: Aktif"', html, fixed = TRUE))
  expect_false(grepl('cinematic-feature-icon off"', html, fixed = TRUE))     # hiç kapalı yok
})

test_that("Dinamik kartı karışık durumları (takip/müzik/ses açık, tts/karakter kapalı) üretir", {
  skip_if_not_installed("shiny")
  html <- .startup_card_html("denge")

  expect_true(grepl('data-mode="denge"', html, fixed = TRUE))
  expect_true(grepl('class="fas fa-wand-magic-sparkles cinematic-card-icon"', html, fixed = TRUE))
  # tts ve karakter kapalı
  expect_true(grepl('data-tooltip="Sesli Yanıt: Kapalı"', html, fixed = TRUE))
  expect_true(grepl('class="fas fa-user-slash"', html, fixed = TRUE))
  expect_true(grepl('data-tooltip="Asistan Karakteri: Kapalı"', html, fixed = TRUE))
  # takip/müzik/ses açık
  expect_true(grepl('data-tooltip="Takip Soruları: Aktif"', html, fixed = TRUE))
  expect_true(grepl('data-tooltip="Arka Plan Müziği: Aktif"', html, fixed = TRUE))
  expect_true(grepl('class="fas fa-bell"', html, fixed = TRUE))  # ses açık
})
