# ==============================================================================
# Dosya Yolu: tests/testthat/test-logout-url-contract.R
# Açıklama: Sidebar çıkış (logout) butonu URL sözleşmesini korur.
#           Hedef URL .Renviron'dan (MERGEN_LOGOUT_URL) öncelikli okunur;
#           geçersiz/boş değer kırık butonu engellemek için boş döner.
#
# Kapsam (heavy Shiny runtime istemez):
#   1. mergen_validate_logout_url() http(s)://, /relative ve yasak şemalar.
#   2. mergen_resolve_logout_url() MERGEN_LOGOUT_URL'i SSO endpoint'in
#      ÜZERİNDE tercih eder; URL geçersizse boş döner.
#   3. mergen_logout_button_available() boş URL'de FALSE döner.
#   4. R/module_sidebar_user_panel.R helper'ı kullanır; sabit URL gömülmez.
#   5. R/config_source_manifest.R helpers_logout_url.R'yi yükler.
# ==============================================================================

.repo_root_logout_url <- function() {
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

.read_repo_text_logout_url <- function(rel_path) {
  repo_root <- .repo_root_logout_url()
  full_path <- file.path(repo_root, rel_path)
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

.load_logout_url_helper <- function() {
  env <- new.env(parent = globalenv())
  source(
    file.path(.repo_root_logout_url(), "R", "helpers_logout_url.R"),
    local = env,
    encoding = "UTF-8"
  )
  env
}

# Helper'a güvenli ortam değişkeni ayarı yapan küçük yardımcı.
.with_env_vars_logout_url <- function(values, expr) {
  # Eski değerleri sakla, sonra geri yükle.
  keys <- names(values)
  previous <- vapply(keys, function(k) Sys.getenv(k, unset = NA_character_), character(1))
  on.exit({
    for (i in seq_along(keys)) {
      k <- keys[i]
      prev <- previous[i]
      if (is.na(prev)) {
        Sys.unsetenv(k)
      } else {
        do.call(Sys.setenv, stats::setNames(list(prev), k))
      }
    }
  }, add = TRUE)
  for (i in seq_along(keys)) {
    do.call(Sys.setenv, stats::setNames(list(values[[i]]), keys[i]))
  }
  expr
}

test_that("mergen_validate_logout_url() http(s) ve göreli kök kabul eder, yasaklıları reddeder", {
  env <- .load_logout_url_helper()
  fn <- get("mergen_validate_logout_url", envir = env, inherits = FALSE)

  expect_equal(fn("https://example.com/logout"), "https://example.com/logout")
  expect_equal(fn("http://intranet.local/sso/logout"), "http://intranet.local/sso/logout")
  expect_equal(fn("/sso/logout"), "/sso/logout")
  expect_equal(fn("  https://example.com/x  "), "https://example.com/x")

  # Yasaklı şemalar
  expect_equal(fn("javascript:alert(1)"), "")
  expect_equal(fn("data:text/html,<script>alert(1)</script>"), "")
  expect_equal(fn("vbscript:msgbox"), "")
  expect_equal(fn("file:///etc/passwd"), "")

  # Boş / NA / NULL
  expect_equal(fn(""), "")
  expect_equal(fn("   "), "")
  expect_equal(fn(NA), "")
  expect_equal(fn(NA_character_), "")
  expect_equal(fn(NULL), "")

  # Şemasız ve göreli olmayan değerler reddedilir
  expect_equal(fn("example.com/x"), "")
  expect_equal(fn("ftp://example.com/"), "")
})

test_that("mergen_resolve_logout_url() MERGEN_LOGOUT_URL'i öncelikli alır", {
  env <- .load_logout_url_helper()
  fn <- get("mergen_resolve_logout_url", envir = env, inherits = FALSE)

  .with_env_vars_logout_url(
    list(
      MERGEN_LOGOUT_URL = "https://example.com/main",
      SSO_LOGOUT_URL = "https://example.com/sso",
      KEYCLOAK_LOGOUT_URL = "https://example.com/keycloak"
    ),
    {
      expect_equal(fn(sso_enabled = FALSE), "https://example.com/main")
      expect_equal(fn(sso_enabled = TRUE), "https://example.com/main")
    }
  )
})

test_that("mergen_resolve_logout_url() SSO_LOGOUT_URL'e geri düşer", {
  env <- .load_logout_url_helper()
  fn <- get("mergen_resolve_logout_url", envir = env, inherits = FALSE)

  .with_env_vars_logout_url(
    list(
      MERGEN_LOGOUT_URL = "",
      SSO_LOGOUT_URL = "https://sso.example/logout",
      KEYCLOAK_LOGOUT_URL = ""
    ),
    {
      expect_equal(fn(sso_enabled = FALSE), "https://sso.example/logout")
    }
  )
})

test_that("mergen_resolve_logout_url() boş ve geçersiz URL'lerde boş döner", {
  env <- .load_logout_url_helper()
  fn <- get("mergen_resolve_logout_url", envir = env, inherits = FALSE)

  .with_env_vars_logout_url(
    list(
      MERGEN_LOGOUT_URL = "",
      SSO_LOGOUT_URL = "",
      KEYCLOAK_LOGOUT_URL = ""
    ),
    {
      # SSO_CONFIG yok, sso_enabled = FALSE - boş URL
      expect_equal(fn(sso_enabled = FALSE), "")
    }
  )

  .with_env_vars_logout_url(
    list(
      MERGEN_LOGOUT_URL = "javascript:alert(1)",
      SSO_LOGOUT_URL = "data:text/html",
      KEYCLOAK_LOGOUT_URL = "vbscript:foo"
    ),
    {
      expect_equal(fn(sso_enabled = FALSE), "")
    }
  )
})

test_that("mergen_logout_button_available() boş URL'de FALSE döner", {
  env <- .load_logout_url_helper()
  available_fn <- get("mergen_logout_button_available", envir = env, inherits = FALSE)

  .with_env_vars_logout_url(
    list(
      MERGEN_LOGOUT_URL = "",
      SSO_LOGOUT_URL = "",
      KEYCLOAK_LOGOUT_URL = ""
    ),
    {
      expect_false(available_fn(sso_enabled = FALSE))
    }
  )

  .with_env_vars_logout_url(
    list(
      MERGEN_LOGOUT_URL = "https://logout.example/x",
      SSO_LOGOUT_URL = "",
      KEYCLOAK_LOGOUT_URL = ""
    ),
    {
      expect_true(available_fn(sso_enabled = FALSE))
    }
  )
})

test_that("R/module_sidebar_user_panel.R mergen_resolve_logout_url() helper'ını kullanır", {
  txt <- .read_repo_text_logout_url("R/module_sidebar_user_panel.R")
  expect_true(nzchar(txt), info = "R/module_sidebar_user_panel.R okunamadı.")

  expect_true(
    grepl("mergen_resolve_logout_url", txt, fixed = TRUE),
    info = paste(
      "Sidebar çıkış butonu URL'sini merkezi mergen_resolve_logout_url()",
      "helper'ından okumalıdır; sabit URL gömülmemelidir."
    )
  )

  # Sabit/üretim URL gömülmemiş olmalı (Keycloak/sso prod adresi açıkça
  # yazılmamalı).
  expect_false(
    grepl("logout\\?client_id=", txt, perl = TRUE, useBytes = TRUE),
    info = "Sidebar modülünde production logout query'si gömülü olmamalıdır."
  )
})

test_that("R/config_source_manifest.R helpers_logout_url.R'yi yükler", {
  txt <- .read_repo_text_logout_url("R/config_source_manifest.R")
  expect_true(nzchar(txt), info = "R/config_source_manifest.R okunamadı.")
  expect_true(
    grepl('"R/helpers_logout_url.R"', txt, fixed = TRUE),
    info = "helpers_logout_url.R kaynak manifestine eklenmelidir."
  )
})

test_that(".Renviron MERGEN_LOGOUT_URL anahtarını içerir (boş olabilir)", {
  txt <- .read_repo_text_logout_url(".Renviron")
  expect_true(nzchar(txt), info = ".Renviron okunamadı.")
  expect_true(
    grepl("MERGEN_LOGOUT_URL", txt, fixed = TRUE),
    info = ".Renviron MERGEN_LOGOUT_URL anahtarını içermelidir."
  )
})
