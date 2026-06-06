# ==============================================================================
# Dosya Yolu: tests/testthat/test-renv-lock-contract.R
# Aciklama: renv bagimlilik kilit mekanizmasi sozlesme testleri.
#   - renv altyapisi (.Rprofile, renv/activate.R, renv/.gitignore) mevcut.
#   - .Rprofile KOSULLU/offline-guvenli: renv.lock + renv + DOLU renv/library
#     yoksa no-op (global kutuphane); cokmesiz.
#   - .gitignore politikasi: renv.lock COMMIT edilebilir; renv/library yok sayilir.
#   - ci_install_packages.R renv::restore() tercihini icerir.
#   - tools/renv_snapshot.R mevcut ve parse edilebilir.
#   - renv.lock VARSA: required_packages (base/recommended haric) kilitte yer alir.
#     renv.lock YOKSA (kilit Windows VM'de uretilir): tutarlilik kontrolu atlanir.
#   Gercek DB/LLM/ag/tarayici GEREKMEZ; deterministik ve offline.
#
#   ONEMLI (Windows VM): dosyalar BAYT-GUVENLI okunur (readBin + iconv sub="byte")
#   ve eslesmeler ASCII capalar uzerinde useBytes=TRUE ile yapilir. Turkce yorumlu
#   dosyalari readLines(encoding="UTF-8") + grepl ile taramak Windows/Turkce locale
#   altinda "input string 1 is invalid UTF-8" uretip testi kirar; bu yuzden repo
#   sozlesmesindeki bayt-guvenli desen kullanilir.
# ==============================================================================

.renv_repo_root <- function() resolve_repo_root_for_tests()

# Bayt-guvenli dosya okuyucu: sonuc her zaman gecerli UTF-8'dir (sub="byte"),
# boylece ASCII capalar uzerinde grepl(useBytes=TRUE) Windows'ta uyari/hata uretmez.
.renv_read <- function(rel) {
  p <- file.path(.renv_repo_root(), rel)
  size <- file.info(p)$size
  if (is.na(size) || size <= 0) return("")
  raw_bytes <- readBin(p, what = "raw", n = size)
  iconv(rawToChar(raw_bytes), from = "UTF-8", to = "UTF-8", sub = "byte")
}

.renv_has <- function(txt, pat) grepl(pat, txt, fixed = TRUE, useBytes = TRUE)

.renv_lines <- function(txt) trimws(strsplit(txt, "\n", fixed = TRUE)[[1]])

# required_packages <- c(...) blogunu statik ayikla (config_packages.R'yi source
# ETMEDEN; eksik paket varsa source bilincli stop() uretir). Paket adlari ASCII.
.renv_required_packages <- function() {
  txt <- .renv_read(file.path("R", "config_packages.R"))
  hit <- regexpr("(?s)required_packages\\s*<-\\s*c\\((.*?)\\)", txt, perl = TRUE)
  testthat::expect_true(hit[1] > 0)
  block <- regmatches(txt, hit)
  sh <- gregexpr("\"[^\"]+\"|'[^']+'", block, perl = TRUE)[[1]]
  vals <- regmatches(block, list(sh))[[1]]
  vals <- gsub("^['\"]|['\"]$", "", vals, perl = TRUE)
  unique(vals[nzchar(vals)])
}

# R temel + onerilen paketleri (kilitte bulunmasi gerekmez).
.renv_base_recommended <- c(
  "base", "compiler", "datasets", "graphics", "grDevices", "grid", "methods",
  "parallel", "splines", "stats", "stats4", "tcltk", "tools", "utils",
  "MASS", "Matrix", "boot", "class", "cluster", "codetools", "foreign",
  "KernSmooth", "lattice", "mgcv", "nlme", "nnet", "rpart", "spatial", "survival"
)

testthat::test_that("renv altyapi dosyalari mevcut", {
  root <- .renv_repo_root()
  testthat::expect_true(file.exists(file.path(root, ".Rprofile")))
  testthat::expect_true(file.exists(file.path(root, "renv", "activate.R")))
  testthat::expect_true(file.exists(file.path(root, "renv", ".gitignore")))
  testthat::expect_true(file.exists(file.path(root, "tools", "renv_snapshot.R")))
  testthat::expect_true(file.exists(file.path(root, "docs", "dependency-locking.md")))
})

testthat::test_that(".Rprofile kosullu/offline-guvenli (kosulsuz aktivasyon DEGIL)", {
  rp <- .renv_read(".Rprofile")
  # renv yalnizca kilit + renv + DOLU kutuphane varsa etkinlesir.
  testthat::expect_true(.renv_has(rp, "renv.lock"))
  testthat::expect_true(.renv_has(rp, "requireNamespace"))
  testthat::expect_true(.renv_has(rp, "activate.R"))
  # renv/library dolu mu kontrolu (uretim VM'inde bos kutuphaneyle aktivasyonu onler).
  testthat::expect_true(.renv_has(rp, "renv/library") || .renv_has(rp, "renv_library_ready"))
  # Hata olsa bile cokmez.
  testthat::expect_true(.renv_has(rp, "tryCatch"))
  # Kacis valfi mevcut.
  testthat::expect_true(.renv_has(rp, "MERGEN_DISABLE_RENV_AUTOLOAD"))
  # Kosulsuz standart aktivasyon satiri OLMAMALI (en ust seviyede ham source).
  has_unconditional <- any(grepl("^source\\([\"']renv/activate\\.R[\"']\\)$",
                                 .renv_lines(rp), useBytes = TRUE))
  testthat::expect_false(has_unconditional)
})

testthat::test_that(".gitignore politikasi: renv.lock commit edilebilir, library yok sayilir", {
  lines <- .renv_lines(.renv_read(".gitignore"))
  # Blanket "renv/" OLMAMALI (activate.R'yi de yok sayardi).
  testthat::expect_false(any(lines == "renv/"))
  # Yerel kutuphane yok sayilmali.
  testthat::expect_true(any(grepl("renv/library", lines, fixed = TRUE, useBytes = TRUE)))
  # renv.lock acikca yok sayilmamali (commit edilir).
  testthat::expect_false(any(grepl("^renv\\.lock$", lines, useBytes = TRUE)))

  rgi <- .renv_read(file.path("renv", ".gitignore"))
  testthat::expect_true(.renv_has(rgi, "library/"))
})

testthat::test_that("ci_install_packages.R renv::restore() tercihini icerir, fallback korunur", {
  ci <- .renv_read(file.path("tests", "scripts", "ci_install_packages.R"))
  testthat::expect_true(.renv_has(ci, "renv.lock"))
  testthat::expect_true(.renv_has(ci, "renv::restore"))
  # Klasik RSPM/CRAN akisi hala mevcut (fallback).
  testthat::expect_true(.renv_has(ci, "cloud.r-project.org"))
})

testthat::test_that("tools/renv_snapshot.R parse edilebilir ve init kullanmaz", {
  p <- file.path(.renv_repo_root(), "tools", "renv_snapshot.R")
  testthat::expect_silent(parse(p))
  body <- .renv_read(file.path("tools", "renv_snapshot.R"))
  testthat::expect_true(.renv_has(body, "renv::snapshot"))
  # init() KULLANMAMALI (.Rprofile'i ezer). Yorum satirlari taranmaz.
  code_lines <- .renv_lines(body)
  code_lines <- code_lines[!grepl("^#", code_lines, useBytes = TRUE)]
  testthat::expect_false(any(grepl("renv::init", code_lines, fixed = TRUE, useBytes = TRUE)))
})

testthat::test_that("renv.lock VARSA required_packages ile tutarli; YOKSA atlanir", {
  lock_path <- file.path(.renv_repo_root(), "renv.lock")
  if (!file.exists(lock_path)) {
    testthat::succeed("renv.lock yok (Windows VM'de uretilecek); tutarlilik kontrolu atlandi.")
    return(invisible(NULL))
  }
  testthat::skip_if_not_installed("jsonlite")
  lock <- jsonlite::fromJSON(lock_path, simplifyVector = FALSE)
  locked <- names(lock$Packages)
  testthat::expect_true(length(locked) > 0)

  # Paket adi karsilastirmasi BUYUK/kucuk harf duyarsiz yapilir: renv anlik
  # gorunum/normalizasyon farklari (or. shinyWidgets vs shinywidgets) yanlis
  # eksiklik raporlamasin.
  req <- setdiff(.renv_required_packages(), .renv_base_recommended)
  missing_in_lock <- req[!(tolower(req) %in% tolower(locked))]
  testthat::expect_identical(
    missing_in_lock, character(0),
    info = paste("renv.lock'ta eksik required_packages:",
                 paste(missing_in_lock, collapse = ", "))
  )
})
