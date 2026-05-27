# ==============================================================================
# Dosya Yolu: tests/testthat/test-smoke-probes-contract.R
# Açıklama: UX smoke probe dosyalarının streaming, navigation, audio ve
#           File Manager Türkçe görünen ad kapsamını korur.
# ==============================================================================

.smoke_probes_read_text <- function(...) {
  full_path <- file.path(resolve_repo_root_for_tests(), ...)

  if (!file.exists(full_path)) {
    stop(sprintf("Beklenen dosya bulunamadı: %s", full_path), call. = FALSE)
  }

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

.smoke_probes_expect_all <- function(text, tokens, label) {
  missing <- tokens[!vapply(
    tokens,
    function(token) grepl(token, text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  testthat::expect_equal(
    missing,
    character(0),
    info = paste(label, paste(missing, collapse = ", "))
  )
}

testthat::test_that("UX smoke probe script is loaded and called by browser harness", {
  smoke_html <- .smoke_probes_read_text("www", "smoke", "ux-smoke.html")

  .smoke_probes_expect_all(
    smoke_html,
    c(
      "ux-smoke-probes.js",
      "testNavigationAndFileManagerSmoke",
      "MergenUxSmokeProbes",
      "runNavigationAndFileManagerSmoke",
      "stream finalize follow-up pending state temizlenir",
      "tek background music source aktif kalır",
      "Audio lifecycle smoke API var",
      "await testNavigationAndFileManagerSmoke(app);"
    ),
    "ux-smoke.html probe entegrasyonu eksik:"
  )
})

testthat::test_that("UX smoke probes cover navigation, video lifecycle and file display names", {
  probes_js <- .smoke_probes_read_text("www", "smoke", "ux-smoke-probes.js")

  .smoke_probes_expect_all(
    probes_js,
    c(
      "window.MergenUxSmokeProbes",
      "snapshotTransientState",
      "renderSyntheticFileManagerListing",
      "runFileManagerDisplayNameSmoke",
      "runNavigationAndFileManagerSmoke",
      "snapshotToolState",
      "readToolSettingKeys",
      "clickDashboardTab(doc, \"claude_code\")",
      "clickDashboardTab(doc, \"chat\")",
      "Bilge Yolaç geçişinde doğru tool paneli aktif görünür",
      "Ana Söyleşi dönüşü stale Bilge Yolaç tool paneli aktif kalmaz",
      "Ana Söyleşi dönüşü URL hash stale Bilge Yolaç state taşımaz",
      "Ana Söyleşi dönüşü stale tool modal/backdrop kalmaz",
      "MergenWelcomeVideoSmoke",
      "MergenAudioLifecycleSmoke",
      "backgroundMusicSourceCount",
      "duckOwners.length === 0",
      "Türkçe_çalışma_özeti_İstanbul.pdf",
      "mojibakePattern",
      "data-filename",
      "File Manager synthetic refresh sonrası Türkçe adı korur"
    ),
    "ux-smoke-probes.js kapsamı eksik:"
  )
})

testthat::test_that("welcome video and audio lifecycle expose smoke-only state seams", {
  welcome_js <- .smoke_probes_read_text("www", "js", "welcome_video_player.js")
  audio_guard_js <- .smoke_probes_read_text("www", "js", "audio_lifecycle_guard.js")

  .smoke_probes_expect_all(
    welcome_js,
    c(
      "smokeInitCount",
      "smokeDestroyCount",
      "getSmokeState",
      "window.MergenWelcomeVideoSmoke",
      "initCount: smokeInitCount",
      "destroyCount: smokeDestroyCount",
      "hasContainer: !!(container && document.contains(container))"
    ),
    "WelcomeVideoPlayer smoke seam eksik:"
  )

  .smoke_probes_expect_all(
    audio_guard_js,
    c(
      "window.MergenAudioLifecycleSmoke",
      "activeDuckOwners: ownerList",
      "applyMusicDuckState: applyMusicDuckState",
      "releaseAll: releaseAll"
    ),
    "Audio lifecycle smoke seam eksik:"
  )
})

testthat::test_that("navigation and file-manager probes stay aligned with real UI anchors", {
  ui_text <- .smoke_probes_read_text("ui.R")
  file_table_text <- .smoke_probes_read_text("R", "helpers_file_manager_table.R")

  .smoke_probes_expect_all(
    ui_text,
    c(
      'menuItem("Ana Söyleşi", tabName = "chat"',
      'menuItem("Bilge Yolaç", tabName = "claude_code"',
      "tabItems(",
      "tabItem(",
      'tabName = "chat"',
      'tabItem(tabName = "claude_code", claudeCodeUI("claude_code_module"))',
      'tabItem(tabName = "files", fileManagerUI("file_manager_module"))'
    ),
    "Navigation smoke gerçek UI tab anchor'larıyla hizalı değil:"
  )

  .smoke_probes_expect_all(
    file_table_text,
    c(
      "fm_clean_file_display_name",
      "display_name <- fm_clean_file_display_name(file_name, file_info)",
      "Dosya_Adi = display_name",
      "fm_build_attach_cell_html(",
      "file_name = display_name"
    ),
    "File Manager görünen ad smoke gerçek tablo helper sözleşmesiyle hizalı değil:"
  )
})