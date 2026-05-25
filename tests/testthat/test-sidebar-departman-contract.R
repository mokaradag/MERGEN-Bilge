# ==============================================================================
# Dosya Yolu: tests/testthat/test-sidebar-departman-contract.R
# Açıklama: Sidebar kullanıcı panelinde Departman (MB_Users) gösterim
#           sözleşmesini korur. "Mudurluk" görünür alan olarak
#           gösterilmemeli; Departman tercih edilmeli ve uzun değerler
#           tooltip/ellipsis ile guvenli sekilde render edilmelidir.
#
# Test kapsamı (heavy Shiny runtime istemez):
#   1. mb_sidebar_user_department() Departman / departman / department
#      alanlarini sirasiyla tercih eder, mudurluk'u DEGIL.
#   2. Uzun Departman degeri title attribute olarak korunur ve render
#      sirasinda crash etmez.
#   3. Bos / NULL kullanici config'inde guvenli yedek dize doner.
# ==============================================================================

.repo_root_sidebar_dept <- function() {
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

.load_sidebar_user_panel <- function() {
  # Minimal bootstrap: yalnizca module_sidebar_user_panel.R'yi izole bir
  # ortamda yukle. tags/htmltools fonksiyonlarini paketten getir.
  repo_root <- .repo_root_sidebar_dept()
  module_path <- file.path(repo_root, "R", "module_sidebar_user_panel.R")
  if (!file.exists(module_path)) {
    stop("R/module_sidebar_user_panel.R yok: ", module_path, call. = FALSE)
  }

  env <- new.env(parent = globalenv())

  # `%||%` yardimcisi yoksa minimal sürüm
  if (!exists("%||%", envir = env, inherits = FALSE)) {
    assign("%||%", function(x, y) if (is.null(x)) y else x, envir = env)
  }

  # Shiny tags / htmltools tagList global olarak gelir
  if (requireNamespace("shiny", quietly = TRUE)) {
    env$tags    <- shiny::tags
    env$tagList <- shiny::tagList
    env$icon    <- shiny::icon
    env$uiOutput <- shiny::uiOutput
  } else if (requireNamespace("htmltools", quietly = TRUE)) {
    env$tags    <- htmltools::tags
    env$tagList <- htmltools::tagList
    env$uiOutput <- function(outputId, ...) {
      htmltools::div(id = outputId, class = "shiny-html-output")
    }
  } else {
    skip("Bu testte shiny veya htmltools yuklenemedi.")
  }

  # get_app_version_label() varsa ekle; yoksa fallback
  if (!exists("get_app_version_label", mode = "function", envir = env, inherits = FALSE)) {
    env$get_app_version_label <- function() "v?"
  }
  if (!exists("get_current_version", mode = "function", envir = env, inherits = FALSE)) {
    env$get_current_version <- function() "?"
  }

  source(module_path, local = env, encoding = "UTF-8")
  env
}

test_that("mb_sidebar_user_department() Departman alanini oncelikle secer", {
  env <- .load_sidebar_user_panel()
  fn <- get("mb_sidebar_user_department", envir = env, inherits = FALSE)

  # Tum alanlar dolu: Departman secilmeli
  cfg <- list(
    Departman = "Yazılım Geliştirme",
    departman = "yazilim",
    department = "software dev",
    mudurluk = "Bilgi Teknolojileri Müdürlüğü"
  )
  expect_equal(
    fn(cfg),
    "Yazılım Geliştirme",
    info = "Departman alani diger alternatiflere oncelikli secilmelidir."
  )
})

test_that("mb_sidebar_user_department() Departman bossa departman -> department sirasiyla secer", {
  env <- .load_sidebar_user_panel()
  fn <- get("mb_sidebar_user_department", envir = env, inherits = FALSE)

  cfg_lower <- list(
    Departman = "",
    departman = "AR-GE Birimi",
    department = "rd unit"
  )
  expect_equal(fn(cfg_lower), "AR-GE Birimi")

  cfg_english <- list(
    Departman = NA_character_,
    departman = "",
    department = "Operations"
  )
  expect_equal(fn(cfg_english), "Operations")
})

test_that("mb_sidebar_user_department() Mudurluk'u GORUNUR alan olarak secmez", {
  env <- .load_sidebar_user_panel()
  fn <- get("mb_sidebar_user_department", envir = env, inherits = FALSE)

  cfg_only_mud <- list(
    mudurluk = "Bilgi Teknolojileri Müdürlüğü"
  )
  expect_equal(
    fn(cfg_only_mud),
    "",
    info = paste(
      "Sidebar kullanici panelinde Mudurluk gorunur alan olarak",
      "DEGIL Departman gosterilmelidir. Boş Departman'da Mudurluk'a duşulmemeli."
    )
  )
})

test_that("mb_sidebar_user_department() NULL/bos config icin bos dize doner", {
  env <- .load_sidebar_user_panel()
  fn <- get("mb_sidebar_user_department", envir = env, inherits = FALSE)

  expect_equal(fn(NULL), "")
  expect_equal(fn(list()), "")
  expect_equal(fn("non-list-input"), "")
})

test_that("mb_sidebar_user_badge_ui() uzun Departman icin title tooltip ekler", {
  env <- .load_sidebar_user_panel()
  badge_fn <- get("mb_sidebar_user_badge_ui", envir = env, inherits = FALSE)

  long_department <- paste(
    "Çok Uzun Departman İsmi - Bilgi Sistemleri ve Uygulama Mühendisliği",
    "Müdürlüğü Bağlı Bilişim Hizmetleri Şube Müdürlüğü"
  )

  ui <- badge_fn(
    full_name = "Mustafa Karadağ",
    first_name = "Mustafa",
    user_id = 1L,
    department = long_department
  )

  html <- as.character(ui)
  expect_true(
    grepl(long_department, html, fixed = TRUE),
    info = "Uzun Departman degeri render edilmelidir."
  )

  expect_true(
    grepl(sprintf('title="%s"', long_department), html, fixed = TRUE),
    info = "Uzun Departman degeri title attribute olarak korunmalidir."
  )

  expect_true(
    grepl("mb-sidebar-user-department", html, fixed = TRUE),
    info = "Departman elemani mb-sidebar-user-department class'i kullanmalidir."
  )
})

test_that("mb_sidebar_user_badge_ui() bos Departman icin temiz Turkce yedek metin gosterir", {
  env <- .load_sidebar_user_panel()
  badge_fn <- get("mb_sidebar_user_badge_ui", envir = env, inherits = FALSE)

  ui <- badge_fn(
    full_name = "Yerel Kullanıcı",
    first_name = "Yerel",
    user_id = 0L,
    department = ""
  )

  html <- as.character(ui)
  expect_true(
    grepl("Departman bilgisi yok", html, fixed = TRUE),
    info = "Bos Departman icin temiz Turkce yedek metin gosterilmelidir."
  )
})

test_that("module_sidebar_user_panel.R Mudurluk'u GORUNUR alan olarak secmez", {
  repo_root <- .repo_root_sidebar_dept()
  module_path <- file.path(repo_root, "R", "module_sidebar_user_panel.R")
  txt <- paste(readLines(module_path, warn = FALSE, encoding = "UTF-8"),
               collapse = "\n")
  txt <- enc2utf8(txt)

  # mb_sidebar_user_department helper'i Departman/departman/department
  # alanlarini secmeli; mudurluk gorunur alan olarak DEGIL.
  expect_true(
    grepl('pick("Departman")', txt, fixed = TRUE),
    info = "mb_sidebar_user_department() Departman alanini okumalidir."
  )

  # Helper icinde mudurluk gorunur alan olarak tercih edilmemeli
  expect_false(
    grepl('pick("mudurluk")', txt, fixed = TRUE),
    info = paste(
      "Sidebar helper'inda mudurluk gorunur alan olarak DEGIL,",
      "Departman tercih edilmelidir."
    )
  )

  expect_false(
    grepl('pick("Mudurluk")', txt, fixed = TRUE),
    info = "Mudurluk gorunur alan olarak secilmemelidir."
  )
})
