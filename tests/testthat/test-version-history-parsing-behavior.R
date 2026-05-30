# ==============================================================================
# Dosya Yolu: tests/testthat/test-version-history-parsing-behavior.R
# Açıklama: R/config_version_history.R get_version_history / get_app_version_full_label
#           DAVRANIŞSAL testleri. Sürüm başlığı, rozet, "Öne Çıkanlar", detay
#           bölümü (ikon dahil), madde ayrıştırma, HTML yorum atlama ve eksik
#           dosya (uyarı + varsayılan) davranışı doğrulanır. Test, getwd() altında
#           sentetik bir version_history.md oluşturur; ağ/DB GEREKMEZ.
# ==============================================================================

.verhist_source_once <- function() {
  if (exists("get_version_history", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "config_version_history.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# UTF-8 baytlarıyla sentetik version_history.md yazar (Türkçe karakter güvenli).
.verhist_write <- function(dir, lines) {
  con <- file(file.path(dir, "version_history.md"), open = "w", encoding = "UTF-8")
  on.exit(close(con))
  writeLines(lines, con)
}

.verhist_sample_lines <- function() {
  c(
    "<!-- ## v9.9 | 2099-01-01 | Sahte Sürüm -->",
    "## v2.5 | 2026-01-01 | Yeni Sürüm",
    "badge: Güncel",
    "### Öne Çıkanlar",
    "- İlk önemli madde",
    "- İkinci madde",
    "### Hata Düzeltmeleri | wrench",
    "- Bir hata giderildi",
    "",
    "---",
    "",
    "## v2.4 | 2025-12-01 | Eski Sürüm",
    "### Genel",
    "- Genel madde"
  )
}

# ------------------------------------------------------------------------------
# get_version_history: yapısal ayrıştırma
# ------------------------------------------------------------------------------
testthat::test_that("get_version_history sürüm başlığı/tarih/başlık/rozet alanlarını ayrıştırır", {
  .verhist_source_once()
  tmp <- tempfile("vh"); dir.create(tmp)
  .verhist_write(tmp, .verhist_sample_lines())

  old <- setwd(tmp)
  res <- get_version_history()
  setwd(old)

  testthat::expect_identical(res$current_version, "2.5")
  testthat::expect_length(res$versions, 2L)

  v1 <- res$versions[[1]]
  testthat::expect_identical(v1$version, "2.5")
  testthat::expect_identical(v1$id, "v2_5")
  testthat::expect_identical(v1$date, "2026-01-01")
  testthat::expect_identical(v1$title, "Yeni Sürüm")
  testthat::expect_identical(v1$badge, "Güncel")
})

testthat::test_that("get_version_history Öne Çıkanlar ve detay bölümünü (ikon dahil) ayrıştırır", {
  .verhist_source_once()
  tmp <- tempfile("vh"); dir.create(tmp)
  .verhist_write(tmp, .verhist_sample_lines())

  old <- setwd(tmp)
  res <- get_version_history()
  setwd(old)

  v1 <- res$versions[[1]]
  # Öne Çıkanlar maddeleri.
  testthat::expect_length(v1$highlights, 2L)
  testthat::expect_identical(v1$highlights[[1]], "İlk önemli madde")
  testthat::expect_identical(v1$highlights[[2]], "İkinci madde")

  # Detay bölümü: kategori + açık ikon + madde.
  testthat::expect_length(v1$details, 1L)
  testthat::expect_identical(v1$details[[1]]$category, "Hata Düzeltmeleri")
  testthat::expect_identical(v1$details[[1]]$icon, "wrench")
  testthat::expect_identical(v1$details[[1]]$items[[1]], "Bir hata giderildi")
})

testthat::test_that("get_version_history ikon belirtilmeyen detay bölümünde 'circle' varsayar", {
  .verhist_source_once()
  tmp <- tempfile("vh"); dir.create(tmp)
  .verhist_write(tmp, .verhist_sample_lines())

  old <- setwd(tmp)
  res <- get_version_history()
  setwd(old)

  v2 <- res$versions[[2]]
  testthat::expect_identical(v2$version, "2.4")
  testthat::expect_identical(v2$details[[1]]$category, "Genel")
  testthat::expect_identical(v2$details[[1]]$icon, "circle")  # varsayılan ikon
  testthat::expect_identical(v2$details[[1]]$items[[1]], "Genel madde")
})

testthat::test_that("get_version_history HTML yorum bloğundaki sahte sürümü atlar", {
  .verhist_source_once()
  tmp <- tempfile("vh"); dir.create(tmp)
  .verhist_write(tmp, .verhist_sample_lines())

  old <- setwd(tmp)
  res <- get_version_history()
  setwd(old)

  # Yorum içindeki "## v9.9" gerçek sürüm olarak ayrıştırılmamalı.
  testthat::expect_false(identical(res$current_version, "9.9"))
  versiyon_numaralari <- vapply(res$versions, function(v) v$version, character(1))
  testthat::expect_false("9.9" %in% versiyon_numaralari)
  testthat::expect_setequal(versiyon_numaralari, c("2.5", "2.4"))
})

testthat::test_that("get_version_history çok satırlı yorum bloğunu tamamen atlar", {
  .verhist_source_once()
  tmp <- tempfile("vh"); dir.create(tmp)
  .verhist_write(tmp, c(
    "<!--",
    "## v8.8 | 2098-01-01 | Gizli",
    "-->",
    "## v3.0 | 2026-05-05 | Gercek",
    "### Öne Çıkanlar",
    "- madde"
  ))

  old <- setwd(tmp)
  res <- get_version_history()
  setwd(old)

  testthat::expect_identical(res$current_version, "3.0")
  testthat::expect_length(res$versions, 1L)
})

# ------------------------------------------------------------------------------
# Eksik dosya: uyarı + varsayılan
# ------------------------------------------------------------------------------
testthat::test_that("get_version_history dosya yoksa uyarı verip varsayılana düşer", {
  .verhist_source_once()
  empty_dir <- tempfile("vh_empty"); dir.create(empty_dir)

  old <- setwd(empty_dir)
  res <- NULL
  testthat::expect_warning(res <- get_version_history(), "version_history")
  setwd(old)

  testthat::expect_identical(res$current_version, "0.0")
  testthat::expect_identical(res$versions, list())
})

# ------------------------------------------------------------------------------
# get_app_version_full_label
# ------------------------------------------------------------------------------
testthat::test_that("get_app_version_full_label ürün adı + v<sürüm> üretir", {
  .verhist_source_once()
  tmp <- tempfile("vh"); dir.create(tmp)
  .verhist_write(tmp, .verhist_sample_lines())

  old <- setwd(tmp)
  full <- get_app_version_full_label()
  setwd(old)

  testthat::expect_identical(full, "MERGEN Bilge v2.5")
})

# ------------------------------------------------------------------------------
# Gerçek depo dosyasına karşı değişmez (invariant) kontrol
# ------------------------------------------------------------------------------
testthat::test_that("gerçek version_history.md tutarlı current_version ve etiket üretir", {
  .verhist_source_once()
  old <- setwd(resolve_repo_root_for_tests())
  real <- get_version_history()
  full <- get_app_version_full_label()
  setwd(old)

  testthat::expect_true(nzchar(real$current_version))
  testthat::expect_true(length(real$versions) >= 1L)
  # Tam etiket daima "MERGEN Bilge v..." biçimindedir.
  testthat::expect_true(grepl("^MERGEN Bilge v", full))
})
