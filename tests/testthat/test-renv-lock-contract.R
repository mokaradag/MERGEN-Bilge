# ==============================================================================
# Dosya Yolu: tests/testthat/test-renv-lock-contract.R
# Aciklama: renv bagimlilik kilit mekanizmasi sozlesme testleri.
#   - renv altyapisi (.Rprofile, renv/activate.R, renv/.gitignore) mevcut.
#   - .Rprofile KOSULLU/offline-guvenli (renv.lock + renv yoksa no-op; cokmesiz).
#   - .gitignore politikasi: renv.lock COMMIT edilebilir; renv/library yok sayilir.
#   - ci_install_packages.R renv::restore() tercihini icerir.
#   - tools/renv_snapshot.R mevcut ve parse edilebilir.
#   - renv.lock VARSA: required_packages (base/recommended haric) kilitte yer alir.
#     renv.lock YOKSA (kilit Windows VM'de uretilir): tutarlilik kontrolu atlanir.
#   Gercek DB/LLM/ag/tarayici GEREKMEZ; deterministik ve offline.
# ==============================================================================

.renv_repo_root <- function() resolve_repo_root_for_tests()

.renv_read <- function(rel) {
  p <- file.path(.renv_repo_root(), rel)
  paste(readLines(p, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

# required_packages <- c(...) blogunu statik ayikla (config_packages.R'yi source
# ETMEDEN; eksik paket varsa source bilincli stop() uretir).
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
  # renv yalnizca kilit + renv varsa etkinlesir.
  testthat::expect_true(grepl("renv.lock", rp, fixed = TRUE))
  testthat::expect_true(grepl("requireNamespace", rp, fixed = TRUE))
  testthat::expect_true(grepl("activate.R", rp, fixed = TRUE))
  # Hata olsa bile cokmez.
  testthat::expect_true(grepl("tryCatch", rp, fixed = TRUE))
  # Kosulsuz standart aktivasyon satiri OLMAMALI (en ust seviyede ham source).
  has_unconditional <- any(grepl("^\\s*source\\([\"']renv/activate\\.R[\"']\\)\\s*$",
                                 strsplit(rp, "\n", fixed = TRUE)[[1]]))
  testthat::expect_false(has_unconditional)
})

testthat::test_that(".gitignore politikasi: renv.lock commit edilebilir, library yok sayilir", {
  gi <- .renv_read(".gitignore")
  lines <- trimws(strsplit(gi, "\n", fixed = TRUE)[[1]])
  # Blanket "renv/" OLMAMALI (activate.R'yi de yok sayardi).
  testthat::expect_false(any(lines == "renv/"))
  # Yerel kutuphane yok sayilmali.
  testthat::expect_true(any(grepl("renv/library", lines, fixed = TRUE)))
  # renv.lock acikca yok sayilmamali (commit edilir).
  testthat::expect_false(any(grepl("^renv\\.lock$", lines)))

  rgi <- .renv_read(file.path("renv", ".gitignore"))
  testthat::expect_true(grepl("library/", rgi, fixed = TRUE))
})

testthat::test_that("ci_install_packages.R renv::restore() tercihini icerir, fallback korunur", {
  ci <- .renv_read(file.path("tests", "scripts", "ci_install_packages.R"))
  testthat::expect_true(grepl("renv.lock", ci, fixed = TRUE))
  testthat::expect_true(grepl("renv::restore", ci, fixed = TRUE))
  # Klasik RSPM/CRAN akisi hala mevcut (fallback).
  testthat::expect_true(grepl("cloud.r-project.org", ci, fixed = TRUE))
})

testthat::test_that("tools/renv_snapshot.R parse edilebilir ve .Rprofile'a dokunmaz", {
  p <- file.path(.renv_repo_root(), "tools", "renv_snapshot.R")
  testthat::expect_silent(parse(p))
  body <- .renv_read(file.path("tools", "renv_snapshot.R"))
  testthat::expect_true(grepl("renv::snapshot", body, fixed = TRUE))
  # init() KULLANMAMALI (.Rprofile'i ezer). Yorum satirlari taranmaz; aciklama
  # amacli "renv::init" gecisleri yanlis pozitif uretmesin.
  code_lines <- strsplit(body, "\n", fixed = TRUE)[[1]]
  code_lines <- code_lines[!grepl("^\\s*#", code_lines)]
  testthat::expect_false(any(grepl("renv::init", code_lines, fixed = TRUE)))
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

  req <- setdiff(.renv_required_packages(), .renv_base_recommended)
  missing_in_lock <- setdiff(req, locked)
  testthat::expect_identical(
    missing_in_lock, character(0),
    info = paste("renv.lock'ta eksik required_packages:",
                 paste(missing_in_lock, collapse = ", "))
  )
})
