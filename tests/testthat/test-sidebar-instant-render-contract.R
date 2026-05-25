# ==============================================================================
# Dosya Yolu: tests/testthat/test-sidebar-instant-render-contract.R
# Açıklama: Sidebar alt panelinde tema butonu, kullanici detayi ve cikis
#           kontrollerinin oturum acilir acilmaz (sidebar tiklama gerekmeden)
#           gorunur olmasi sözleşmesini korur.
#
# Yaklasim:
#   1. mb_sidebar_user_panel_ui() statik bir kullanici iskelet (.mb-sidebar-user)
#      ve statik tema butonu (.mb-theme-switch-btn) icermelidir; uiOutput
#      sunucu cevabini beklemeden ilk renderda gorunur olmalidir.
#   2. CSS, server renderUI cikti geldiginde iskelet kapatilmalidir; bu
#      "shiny-html-output ... :not(:empty)" karsidasilarinda saglanir.
# ==============================================================================

.find_repo_root_sidebar_instant <- function() {
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

.read_repo_bytes_sidebar_instant <- function(rel_path) {
  repo_root <- .find_repo_root_sidebar_instant()
  full_path <- file.path(repo_root, rel_path)
  if (!file.exists(full_path)) return("")

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) return("")

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )
  if (is.na(txt)) txt <- ""
  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

test_that("mb_sidebar_user_panel_ui() statik iskelet ve tema butonunu ilk renderda hazirlar", {
  txt <- .read_repo_bytes_sidebar_instant("R/module_sidebar_user_panel.R")
  expect_true(nzchar(txt), info = "R/module_sidebar_user_panel.R okunamadi.")

  # Statik kullanici iskeleti
  expect_true(
    grepl('class = "mb-sidebar-user-skeleton"', txt, fixed = TRUE, useBytes = TRUE),
    info = paste(
      ".mb-sidebar-user-skeleton ilk renderda statik olarak yer almalidir;",
      "uiOutput sunucu render cikti gelene kadar bu iskelet gorunur kalmalidir."
    )
  )

  # Statik kontrol iskeleti (tema butonu icindeki)
  expect_true(
    grepl('class = "mb-sidebar-controls-skeleton"', txt, fixed = TRUE, useBytes = TRUE),
    info = paste(
      ".mb-sidebar-controls-skeleton ilk renderda statik olarak yer almalidir;",
      "tema butonu sidebar tiklamasini beklemeden gorunmelidir."
    )
  )

  # uiOutput container ile slot-output sinifi atanmali
  expect_true(
    grepl("mb-sidebar-user-slot-output", txt, fixed = TRUE, useBytes = TRUE),
    info = "uiOutput container .mb-sidebar-user-slot-output sinifini atamalidir."
  )

  expect_true(
    grepl("mb-sidebar-controls-slot-output", txt, fixed = TRUE, useBytes = TRUE),
    info = "uiOutput container .mb-sidebar-controls-slot-output sinifini atamalidir."
  )

  # Statik tema butonu mb_sidebar_controls_row(show_logout = FALSE) ile gelir
  expect_true(
    grepl("mb_sidebar_controls_row(show_logout = FALSE)", txt,
          fixed = TRUE, useBytes = TRUE),
    info = paste(
      "Sidebar iskelet kontrol satiri show_logout=FALSE ile baslar;",
      "logout butonu ancak server SSO durumunu cozdugunde eklenir."
    )
  )
})

test_that("sidebar_user_panel.css iskelet/slot CSS kurallari icerir", {
  txt <- .read_repo_bytes_sidebar_instant("www/css/sidebar_user_panel.css")
  expect_true(nzchar(txt), info = "www/css/sidebar_user_panel.css okunamadi.")

  expect_true(
    grepl(".mb-sidebar-user-slot", txt, fixed = TRUE, useBytes = TRUE),
    info = ".mb-sidebar-user-slot CSS kuralları olmalidir."
  )

  expect_true(
    grepl(".mb-sidebar-controls-slot", txt, fixed = TRUE, useBytes = TRUE),
    info = ".mb-sidebar-controls-slot CSS kuralları olmalidir."
  )

  # Slot output dolduğunda iskelet gizlenmelidir
  expect_true(
    grepl(".mb-sidebar-user-slot-output:not(:empty)", txt,
          fixed = TRUE, useBytes = TRUE),
    info = paste(
      "Slot output icerigi geldiginde iskelet gizlenmeli;",
      "CSS :not(:empty) selektoru bu davranisi saglar."
    )
  )

  expect_true(
    grepl(".mb-sidebar-controls-slot-output:not(:empty)", txt,
          fixed = TRUE, useBytes = TRUE),
    info = paste(
      "Kontrol slot output icerigi geldiginde iskelet gizlenmeli;",
      "CSS :not(:empty) selektoru bu davranisi saglar."
    )
  )
})
