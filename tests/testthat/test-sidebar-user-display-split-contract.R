# ==============================================================================
# Dosya Yolu: tests/testthat/test-sidebar-user-display-split-contract.R
# Açıklama: Sidebar kullanıcı paneli saf görünüm yardımcılarının
#           (R/helpers_sidebar_user_display.R) modülden ayrıldığını, kaynak
#           sırasını ve modülün artık taşınan yardımcıları inline taşımadığını
#           doğrular. Modül UI kabuğu/logout/server orkestrasyonuna odaklanır.
# ==============================================================================

.read_repo_text_sidebar_split <- function(rel_path) {
  abs_path <- file.path(repo_root_for_tests, rel_path)

  if (!file.exists(abs_path)) {
    stop(sprintf("Dosya bulunamadı: %s", rel_path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(abs_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(abs_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.source_sidebar_display_env <- function() {
  display_env <- new.env(parent = globalenv())

  display_env$`%||%` <- function(x, y) {
    if (is.null(x) || length(x) == 0) y else x
  }

  if (requireNamespace("shiny", quietly = TRUE)) {
    display_env$tags    <- shiny::tags
    display_env$tagList <- shiny::tagList
  } else if (requireNamespace("htmltools", quietly = TRUE)) {
    display_env$tags    <- htmltools::tags
    display_env$tagList <- htmltools::tagList
  } else {
    testthat::skip("Bu testte shiny veya htmltools yuklenemedi.")
  }

  source(
    file.path(repo_root_for_tests, "R", "helpers_sidebar_user_display.R"),
    encoding = "UTF-8",
    local = display_env
  )

  display_env
}

test_that("helpers_sidebar_user_display.R exists and exposes pure display helpers", {
  helper_path <- file.path(
    repo_root_for_tests, "R", "helpers_sidebar_user_display.R"
  )

  expect_true(
    file.exists(helper_path),
    info = "R/helpers_sidebar_user_display.R dosyası eklenmelidir."
  )

  display_env <- .source_sidebar_display_env()

  expected_functions <- c(
    "mb_sidebar_user_initials",
    "mb_sidebar_user_avatar_url",
    "mb_sidebar_user_department",
    "mb_sidebar_theme_switch",
    "mb_sidebar_controls_row",
    "mb_sidebar_user_badge_ui"
  )

  for (fn in expected_functions) {
    expect_true(
      exists(fn, envir = display_env, mode = "function", inherits = FALSE),
      info = sprintf("Eksik sidebar görünüm helper'ı: %s", fn)
    )
  }
})

test_that("runtime manifest sources display helper before sidebar module", {
  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_sidebar_user_display.R",
      "R/module_sidebar_user_panel.R"
    ),
    label = "Kaynak sırası display helper -> sidebar module olmalıdır:"
  )
})

test_that("module_sidebar_user_panel.R no longer owns extracted display helpers", {
  module_txt <- .read_repo_text_sidebar_split("R/module_sidebar_user_panel.R")

  forbidden_inline_defs <- c(
    "mb_sidebar_user_initials <- function",
    "mb_sidebar_user_avatar_url <- function",
    "mb_sidebar_user_department <- function",
    "mb_sidebar_theme_switch <- function",
    "mb_sidebar_controls_row <- function",
    "mb_sidebar_user_badge_ui <- function"
  )

  for (pattern in forbidden_inline_defs) {
    expect_false(
      grepl(pattern, module_txt, fixed = TRUE),
      info = sprintf(
        "Bu helper artık R/helpers_sidebar_user_display.R içinde olmalıdır: %s",
        pattern
      )
    )
  }

  # Modül Shiny orkestrasyon sorumluluklarını korumalıdır.
  expected_module_defs <- c(
    "mb_sidebar_user_panel_ui <- function",
    "mb_sidebar_handle_logout_event <- function",
    "mb_sidebar_user_panel_server <- function",
    # İskelet kabuğu helper çağrılarıyla kurulmaya devam etmelidir.
    "mb_sidebar_controls_row(show_logout = FALSE)",
    "mb_sidebar_user_badge_ui("
  )

  for (pattern in expected_module_defs) {
    expect_true(
      grepl(pattern, module_txt, fixed = TRUE),
      info = sprintf("Modül şu sorumluluğu korumalıdır: %s", pattern)
    )
  }
})

test_that("helpers_sidebar_user_display.R remains free of Shiny runtime wiring", {
  txt <- .read_repo_text_sidebar_split("R/helpers_sidebar_user_display.R")

  expect_false(
    grepl("observeEvent\\s*\\(|renderUI\\s*\\(|outputOptions\\s*\\(|uiOutput\\s*\\(", txt, perl = TRUE),
    info = "Sidebar görünüm helper dosyası Shiny observer/render/output bağlamamalıdır."
  )

  expect_false(
    grepl("session\\$close|sendCustomMessage", txt, perl = TRUE),
    info = "Sidebar görünüm helper dosyası oturum yan etkisi içermemelidir."
  )

  expect_false(
    grepl("dbConnect\\s*\\(|odbc::", txt, perl = TRUE),
    info = "Sidebar görünüm helper dosyası DB bağlantısı açmamalıdır."
  )

  # Korunan Departman seçim sözleşmesi yeni sahibinde kalmalıdır.
  expect_true(
    grepl('pick("Departman")', txt, fixed = TRUE),
    info = "Departman -> departman -> department seçim sırası helper'da korunmalıdır."
  )
})

test_that("extracted helpers keep behavioral contracts (Turkish initials + department order)", {
  display_env <- .source_sidebar_display_env()

  initials_fn <- get("mb_sidebar_user_initials", envir = display_env)
  dept_fn <- get("mb_sidebar_user_department", envir = display_env)
  avatar_fn <- get("mb_sidebar_user_avatar_url", envir = display_env)

  # Türkçe baş harf davranışı (turkish_toupper yoksa toupper fallback).
  expect_identical(initials_fn("Mustafa Karadağ"), "MK")
  expect_identical(initials_fn(NULL, NULL), "MB")

  # Departman seçim sırası: Departman -> departman -> department; Mudurluk asla.
  expect_identical(
    dept_fn(list(Departman = "Bilgi Teknolojileri", department = "ikincil")),
    "Bilgi Teknolojileri"
  )
  expect_identical(dept_fn(list(department = "Yazılım Müdürlüğü")), "Yazılım Müdürlüğü")
  expect_identical(dept_fn(list(Mudurluk = "Görünmemeli")), "")

  # Placeholder kullanıcı kimlikleri avatar URL üretmez.
  expect_identical(avatar_fn("0"), "")
  expect_identical(avatar_fn("unknown"), "")
  expect_true(nzchar(avatar_fn("12345")))
})
