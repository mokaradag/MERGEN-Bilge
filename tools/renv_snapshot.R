#!/usr/bin/env Rscript

# ==============================================================================
# Dosya Yolu: tools/renv_snapshot.R
# Açıklama:
#   MERGEN Bilge için renv.lock kilit dosyasını üretir/günceller.
#   ÇALIŞAN Windows VM (R 4.6.0 + güncel paket kütüphanesi) üzerinde çalıştırın.
#
#   Bu betik:
#     - R/config_packages.R içindeki required_packages listesini STATİK okur
#       (source ETMEZ; eksik paket varsa config_packages.R bilinçli stop() üretir),
#     - CI/test için gereken birkaç ekstra paketi (testthat, withr, processx,
#       callr) ve renv'in kendisini ekler,
#     - mevcut (global/aktif) kütüphanedeki SÜRÜMLERLE renv.lock yazar,
#     - .Rprofile dosyasına DOKUNMAZ (koşullu/offline-güvenli profil korunur).
#
#   NOT: `renv::init()` ÇAĞIRMAYIN. init(), .Rprofile'ı koşulsuz sürümle ezer ve
#   repo'nun offline/bulut güvenli davranışını bozar. Kilit üretmek için yalnızca
#   bu betiği (veya doğrudan renv::snapshot) kullanın.
#
#   Kullanım (repo kökünden):
#       Rscript tools/renv_snapshot.R
#
#   Ayrıntılı rehber: docs/dependency-locking.md
# ==============================================================================

options(warn = 1)
cat("== MERGEN renv snapshot (renv.lock üretici) ==\n")

find_repo_root <- function() {
  candidates <- c(".", "..", "../..")
  for (cand in candidates) {
    if (file.exists(file.path(cand, "app.R")) &&
        dir.exists(file.path(cand, "R"))) {
      return(normalizePath(cand, winslash = "/", mustWork = TRUE))
    }
  }
  stop("Repo kökü bulunamadı. Bu betiği repo içinde çalıştırın.", call. = FALSE)
}

repo_root <- find_repo_root()
setwd(repo_root)
cat(sprintf("Repo kökü: %s\n", repo_root))

if (!requireNamespace("renv", quietly = TRUE)) {
  stop(
    paste(
      "renv paketi kurulu değil.",
      "Önce kurun:  install.packages(\"renv\")",
      "Sonra tekrar çalıştırın:  Rscript tools/renv_snapshot.R",
      sep = "\n"
    ),
    call. = FALSE
  )
}

config_path <- file.path(repo_root, "R", "config_packages.R")
if (!file.exists(config_path)) {
  stop("R/config_packages.R bulunamadı.", call. = FALSE)
}

# required_packages <- c(...) bloğunu statik olarak ayıkla (source etmeden).
extract_required_packages <- function(path) {
  txt <- paste(enc2utf8(readLines(path, warn = FALSE, encoding = "UTF-8")), collapse = "\n")
  hit <- regexpr("(?s)required_packages\\s*<-\\s*c\\((.*?)\\)", txt, perl = TRUE)
  if (hit[1] < 0) {
    stop("required_packages <- c(...) bloğu bulunamadı.", call. = FALSE)
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

# CI / test akışı için gereken ekstralar (tests/scripts/ci_install_packages.R ile
# hizalı) ve renv'in kendisi. Böylece renv::restore() ile temiz bir ortamda hem
# uygulama hem de testler çalışabilir.
extra_packages <- c("testthat", "withr", "processx", "callr", "renv")

requested <- sort(unique(c(repo_packages, extra_packages)))
cat(sprintf("Kilit kapsamına alınacak paket sayısı (recursive bağımlılıklar hariç): %d\n",
            length(requested)))

# Hangi istenen paketler aktif kütüphanede kurulu değil? (uyarı amaçlı)
not_installed <- requested[!vapply(requested, function(p) requireNamespace(p, quietly = TRUE), logical(1))]
if (length(not_installed) > 0L) {
  cat("UYARI: Aşağıdaki istenen paketler aktif kütüphanede KURULU DEĞİL ve\n")
  cat("kilit dosyasına eklenemeyecek. Önce bunları kurun:\n")
  cat(paste(not_installed, collapse = ", "), "\n\n")
}

snapshot_packages <- setdiff(requested, not_installed)
if (length(snapshot_packages) == 0L) {
  stop("Kilitlenecek kurulu paket bulunamadı. Önce paketleri kurun.", call. = FALSE)
}

cat("renv::snapshot() çalıştırılıyor (mevcut kütüphane sürümleriyle)...\n")
renv::snapshot(
  project  = repo_root,
  packages = snapshot_packages,
  prompt   = FALSE,
  lockfile = file.path(repo_root, "renv.lock")
)

lock_path <- file.path(repo_root, "renv.lock")
if (file.exists(lock_path)) {
  locked <- tryCatch(names(jsonlite::fromJSON(lock_path)$Packages), error = function(e) character(0))
  cat(sprintf("\nOK: renv.lock yazıldı (%s).\n", lock_path))
  cat(sprintf("Kilitlenen toplam paket (recursive bağımlılıklar dahil): %d\n", length(locked)))
  cat("\nSonraki adımlar:\n")
  cat("  1) Temiz bir ortamda doğrula:  Rscript -e 'renv::restore(prompt = FALSE)'\n")
  cat("  2) Testleri çalıştır:          Rscript tests/testthat.R\n")
  cat("  3) renv.lock'u commit edin (renv/library COMMIT EDİLMEZ).\n")
} else {
  stop("renv.lock üretilemedi.", call. = FALSE)
}
