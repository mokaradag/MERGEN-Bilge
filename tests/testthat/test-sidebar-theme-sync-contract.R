# ==============================================================================
# Dosya Yolu: tests/testthat/test-sidebar-theme-sync-contract.R
# Açıklama: Sidebar tema butonu ve sunucu/istemci tema senkronizasyon
#           sözleşmelerini korur. Bu testler tam Shiny çalıştırması
#           gerektirmez; ilgili R/JS kaynak dosyalarını parse ederek
#           anchor/text doğrulaması yapar.
#
# Korunan sözleşmeler:
#   1. R/module_settings.R hem input$mergen_theme_changed hem de
#      input$mergen_theme_initial observer'larını içermelidir; aksi halde
#      save_all_settings() ile stale tema değeri persistlenebilir.
#   2. www/js/theme_manager.js delegated click/touchend/keydown handler'ı
#      kullanmalıdır; tek seferlik direct binding regresyonları yakalanır.
#   3. theme_manager.js Shiny.setInputValue('mergen_theme_changed', ...)
#      gönderir.
#   4. Etiket metni "Koyu Tema" / "Açık Tema" formunu içerir.
# ==============================================================================

.find_repo_root_sidebar_theme_sync <- function() {
  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "R")) &&
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.read_repo_text_sidebar_theme_sync <- function(rel_path) {
  repo_root <- .find_repo_root_sidebar_theme_sync()
  full_path <- file.path(repo_root, rel_path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

test_that("module_settings.R input$mergen_theme_changed ve mergen_theme_initial observer'larini icerir", {
  txt <- .read_repo_text_sidebar_theme_sync("R/module_settings.R")
  expect_true(nzchar(txt), info = "R/module_settings.R okunamadi.")

  expect_true(
    grepl("observeEvent(session$input$mergen_theme_changed", txt, fixed = TRUE),
    info = paste(
      "module_settings.R mergen_theme_changed observer'i icermelidir.",
      "Aksi halde istemci tarafi tema degisikligi sunucuya yansimaz ve",
      "save_all_settings() ile stale tema localStorage'a yazilabilir."
    )
  )

  expect_true(
    grepl("observeEvent(session$input$mergen_theme_initial", txt, fixed = TRUE),
    info = paste(
      "module_settings.R mergen_theme_initial observer'i icermelidir.",
      "Tarayici baglantisinda baslangic temasi sunucu tarafi settings$theme",
      "ile esitlenmelidir."
    )
  )
})

test_that("module_settings.R settings$theme'i save oncesinde dogrular", {
  txt <- .read_repo_text_sidebar_theme_sync("R/module_settings.R")
  expect_true(nzchar(txt), info = "R/module_settings.R okunamadi.")

  # save_all_settings() icindeki tema validasyonu: settings$theme yalnizca
  # "dark"/"light" oldugunda to_save$theme'e yazilir; aksi halde NULL'a
  # cekilerek stale tema persistinin onune gecilir.
  expect_true(
    grepl("current_theme <- isolate(settings$theme)", txt, fixed = TRUE),
    info = "save_all_settings() icinde current_theme dogrulamasi olmali."
  )

  expect_true(
    grepl('current_theme %in% c("dark", "light")', txt, fixed = TRUE),
    info = "save_all_settings() yalnizca onaylanmis tema degerlerini saveSettings'e yazmali."
  )
})

test_that("theme_manager.js delegated click handler kullanir", {
  txt <- .read_repo_text_sidebar_theme_sync("www/js/theme_manager.js")
  expect_true(nzchar(txt), info = "www/js/theme_manager.js okunamadi.")

  # Yeni delegated handler anchor'i
  expect_true(
    grepl("function handleToggleEvent(", txt, fixed = TRUE),
    info = paste(
      "theme_manager.js handleToggleEvent delegated handler'ini tanimlamali;",
      "tek seferlik direct binding sidebar yeniden render edildiginde calismaz."
    )
  )

  expect_true(
    grepl("document.addEventListener('click', handleToggleEvent, true);", txt, fixed = TRUE),
    info = paste(
      "theme_manager.js document seviyesinde capture-phase click handler'i",
      "kaydetmelidir (delegated). Bu sidebar dinamik render edilse bile",
      "tikla calismaya devam eder."
    )
  )

  expect_true(
    grepl("[data-mergen-theme-toggle]", txt, fixed = TRUE),
    info = "theme_manager.js [data-mergen-theme-toggle] selektorunu kullanmali."
  )
})

test_that("theme_manager.js Shiny.setInputValue mergen_theme_changed gonderir", {
  txt <- .read_repo_text_sidebar_theme_sync("www/js/theme_manager.js")
  expect_true(nzchar(txt), info = "www/js/theme_manager.js okunamadi.")

  expect_true(
    grepl("'mergen_theme_changed'", txt, fixed = TRUE),
    info = "theme_manager.js sunucuya mergen_theme_changed input'unu gondermeli."
  )

  expect_true(
    grepl("'mergen_theme_initial'", txt, fixed = TRUE),
    info = "theme_manager.js baglantida mergen_theme_initial input'unu gondermeli."
  )
})

test_that("theme_manager.js etiket metni Koyu Tema/Acik Tema kullanir", {
  txt <- .read_repo_text_sidebar_theme_sync("www/js/theme_manager.js")
  expect_true(nzchar(txt), info = "www/js/theme_manager.js okunamadi.")

  expect_true(
    grepl("'Koyu Tema'", txt, fixed = TRUE),
    info = "theme_manager.js 'Koyu Tema' etiketini icermeli."
  )

  expect_true(
    grepl("'Acik Tema'", txt, fixed = TRUE) ||
      grepl("'Açık Tema'", txt, fixed = TRUE),
    info = "theme_manager.js 'Acik Tema' / 'Acik Tema' etiketini icermeli."
  )
})

test_that("module_sidebar_user_panel.R tema butonu data attribute'unu tasir", {
  txt <- .read_repo_text_sidebar_theme_sync("R/module_sidebar_user_panel.R")
  expect_true(nzchar(txt), info = "R/module_sidebar_user_panel.R okunamadi.")

  expect_true(
    grepl("`data-mergen-theme-toggle` = \"true\"", txt, fixed = TRUE),
    info = paste(
      "Sidebar tema butonu data-mergen-theme-toggle attribute'unu tasimalidir;",
      "theme_manager.js delegated handler bunu selektor olarak kullanir."
    )
  )

  expect_true(
    grepl('class = "theme-switch-label"', txt, fixed = TRUE),
    info = "Sidebar tema butonu .theme-switch-label icermelidir."
  )
})
