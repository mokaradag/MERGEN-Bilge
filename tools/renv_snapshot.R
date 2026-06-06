#!/usr/bin/env Rscript

# ==============================================================================
# Dosya Yolu: tools/renv_snapshot.R
# Aciklama:
#   MERGEN Bilge icin renv.lock kilit dosyasini uretir/gunceller.
#   CALISAN Windows VM (R 4.6.0 + guncel paket kutuphanesi) uzerinde calistirin.
#
#   ASCII-only: bu betik testlerce parse()/okunur ve Windows VM (Turkce locale)
#   uzerinde Turkce ozel karakterler "invalid UTF-8" sorunlari uretebildigi icin
#   bilincli olarak ASCII tutulmustur.
#
#   Bu betik:
#     - R/config_packages.R icindeki required_packages listesini STATIK okur
#       (source ETMEZ; eksik paket varsa config_packages.R bilincli stop() uretir),
#     - CI/test icin gereken birkac ekstra paketi (testthat, withr, processx,
#       callr) ve renv'in kendisini ekler,
#     - mevcut (global/aktif) kutuphanedeki SURUMLERLE renv.lock yazar,
#     - .Rprofile dosyasina DOKUNMAZ (kosullu/offline-guvenli profil korunur).
#
#   NOT: renv init fonksiyonunu CAGIRMAYIN. O fonksiyon .Rprofile'i kosulsuz
#   surumle ezer ve repo'nun offline/bulut guvenli davranisini bozar. Kilit
#   uretmek icin yalnizca bu betigi (veya dogrudan renv::snapshot) kullanin.
#
#   Onemli: bu betik yalnizca renv.lock'u KAYDEDER; renv/library'yi DOLDURMAZ.
#   Temiz bir ortamda kilitten kurulum icin: renv::restore(prompt = FALSE).
#
#   Kullanim (repo kokunden):
#       Rscript tools/renv_snapshot.R
#
#   Ayrintili rehber: docs/dependency-locking.md
# ==============================================================================

options(warn = 1)
cat("== MERGEN renv snapshot (renv.lock uretici) ==\n")

find_repo_root <- function() {
  candidates <- c(".", "..", "../..")
  for (cand in candidates) {
    if (file.exists(file.path(cand, "app.R")) &&
        dir.exists(file.path(cand, "R"))) {
      return(normalizePath(cand, winslash = "/", mustWork = TRUE))
    }
  }
  stop("Repo koku bulunamadi. Bu betigi repo icinde calistirin.", call. = FALSE)
}

repo_root <- find_repo_root()
setwd(repo_root)
cat(sprintf("Repo koku: %s\n", repo_root))

if (!requireNamespace("renv", quietly = TRUE)) {
  stop(
    paste(
      "renv paketi kurulu degil.",
      "Once kurun:  install.packages(\"renv\")",
      "Sonra tekrar calistirin:  Rscript tools/renv_snapshot.R",
      sep = "\n"
    ),
    call. = FALSE
  )
}

config_path <- file.path(repo_root, "R", "config_packages.R")
if (!file.exists(config_path)) {
  stop("R/config_packages.R bulunamadi.", call. = FALSE)
}

# required_packages <- c(...) blogunu statik olarak ayikla (source etmeden).
extract_required_packages <- function(path) {
  txt <- paste(enc2utf8(readLines(path, warn = FALSE, encoding = "UTF-8")), collapse = "\n")
  hit <- regexpr("(?s)required_packages\\s*<-\\s*c\\((.*?)\\)", txt, perl = TRUE)
  if (hit[1] < 0) {
    stop("required_packages <- c(...) blogu bulunamadi.", call. = FALSE)
  }
  block <- regmatches(txt, hit)
  string_hits <- gregexpr("\"[^\"]+\"|'[^']+'", block, perl = TRUE)[[1]]
  if (identical(string_hits[1], -1L)) {
    return(character(0))
  }
  values <- regmatches(block, list(string_hits))[[1]]
  values <- gsub("^['\"]|['\"]$", "", values, perl = TRUE)
  unique(values[nzchar(values)])
}

repo_packages <- extract_required_packages(config_path)

# CI / test akisi icin gereken ekstralar (tests/scripts/ci_install_packages.R ile
# hizali) ve renv'in kendisi. Boylece renv::restore() ile temiz bir ortamda hem
# uygulama hem de testler calisabilir.
extra_packages <- c("testthat", "withr", "processx", "callr", "renv")

requested <- sort(unique(c(repo_packages, extra_packages)))
cat(sprintf("Kilit kapsamina alinacak paket sayisi (recursive bagimliliklar haric): %d\n",
            length(requested)))

# Hangi istenen paketler aktif kutuphanede kurulu degil? (uyari amacli)
not_installed <- requested[!vapply(requested, function(p) requireNamespace(p, quietly = TRUE), logical(1))]
if (length(not_installed) > 0L) {
  cat("UYARI: Asagidaki istenen paketler aktif kutuphanede KURULU DEGIL ve\n")
  cat("kilit dosyasina eklenemeyecek. Once bunlari kurun:\n")
  cat(paste(not_installed, collapse = ", "), "\n\n")
}

snapshot_packages <- setdiff(requested, not_installed)
if (length(snapshot_packages) == 0L) {
  stop("Kilitlenecek kurulu paket bulunamadi. Once paketleri kurun.", call. = FALSE)
}

cat("renv::snapshot() calistiriliyor (mevcut kutuphane surumleriyle)...\n")
renv::snapshot(
  project  = repo_root,
  packages = snapshot_packages,
  prompt   = FALSE,
  lockfile = file.path(repo_root, "renv.lock")
)

lock_path <- file.path(repo_root, "renv.lock")
if (file.exists(lock_path)) {
  locked <- tryCatch(names(jsonlite::fromJSON(lock_path)$Packages), error = function(e) character(0))
  cat(sprintf("\nOK: renv.lock yazildi (%s).\n", lock_path))
  cat(sprintf("Kilitlenen toplam paket (recursive bagimliliklar dahil): %d\n", length(locked)))
  cat("\nSonraki adimlar:\n")
  cat("  1) Temiz bir ortamda dogrula:  Rscript -e 'renv::restore(prompt = FALSE)'\n")
  cat("  2) Testleri calistir:          Rscript tests/testthat.R\n")
  cat("  3) renv.lock'u commit edin (renv/library COMMIT EDILMEZ).\n")
} else {
  stop("renv.lock uretilemedi.", call. = FALSE)
}
