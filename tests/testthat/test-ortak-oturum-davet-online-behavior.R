# ==============================================================================
# Dosya Yolu: tests/testthat/test-ortak-oturum-davet-online-behavior.R
# Açıklama: "Katılımcı Çağır" davet panelinin çevrim içi kullanıcı listeleme
#           regresyon testleri. Kritik hata: çevrim içi kullanıcılar varken
#           "Çevrim İçi Kullanıcılar" filtresinde liste boş kalıyordu. Bu dosya
#           (a) canlı durum sınıflandırmasının POSIXct/kesirli-saniye biçimlerine
#           dayanıklılığını, (b) saf aday süzme kararının doğruluğunu doğrular.
#           Çevrimdışı ve deterministiktir; DB, LLM, tarayıcı veya ağ GEREKMEZ.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  if (!exists("ortak_sunum_durumu", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_ortak_oturum_permissions.R"),
           encoding = "UTF-8", local = globalenv())
  }

  # ortak_davet_aday_kullanicilar sunum katmanındadır (permissions'tan sonra).
  if (!exists("ortak_davet_aday_kullanicilar", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_ortak_oturum_sunum.R"),
           encoding = "UTF-8", local = globalenv())
  }
})

# Parser-güvenli Türkçe sabitler (Windows VM kod sayfası riskine karşı).
.ood_tr <- function(...) {
  paste0(vapply(list(...), function(p) {
    if (is.numeric(p)) intToUtf8(as.integer(p)) else as.character(p)
  }, character(1)), collapse = "")
}

.ood_cevrimici <- .ood_tr(0xC7, "evrim", 0x130, "çi")
.ood_bosta <- .ood_tr("Bo", 0x15F, "ta")
.ood_cevrimdisi <- .ood_tr(0xC7, "evrimD", 0x131, 0x15F, 0x131)
.ood_katildi <- .ood_tr("Kat", 0x131, "ld", 0x131)
.ood_filtre_cevrimici <- .ood_tr(0xC7, "evrim ", 0x130, "çi Kullan", 0x131, "c", 0x131, "lar")

test_that("canlı durum sınıflandırması POSIXct ve kesirli-saniye biçimlerine dayanıklıdır", {
  simdi <- as.POSIXct("2026-07-05 12:00:00", tz = "UTC")

  # POSIXct girdi (ODBC/SQL Server DATETIME2 çoğu sürücüde POSIXct döner).
  taze_posix <- simdi - 30
  expect_identical(ortak_sunum_durumu(taze_posix, simdi = simdi), .ood_cevrimici)

  # Kesirli saniyeli metin (DATETIME2(7) / bazı sürücü biçimleri).
  taze_kesirli <- "2026-07-05 11:59:30.0000000"
  expect_identical(ortak_sunum_durumu(taze_kesirli, simdi = simdi), .ood_cevrimici)

  # ISO 'T' ayraçlı metin.
  taze_iso <- "2026-07-05T11:59:30"
  expect_identical(ortak_sunum_durumu(taze_iso, simdi = simdi), .ood_cevrimici)

  # Eski kalp atışı hâlâ ÇevrimDışı; geçersiz zaman fail-safe ÇevrimDışı.
  expect_identical(
    ortak_sunum_durumu(format(simdi - 3600, "%Y-%m-%d %H:%M:%S"), simdi = simdi),
    .ood_cevrimdisi
  )
  expect_identical(ortak_sunum_durumu("gecersiz", simdi = simdi), .ood_cevrimdisi)
})

test_that("aday süzme: çevrim içi kullanıcılar listelenir, çevrim dışı/kendisi elenir", {
  kullanicilar <- data.frame(
    UserID = c(1L, 2L, 3L, 4L),
    KaynakAdi = c("Ben", "Ayşe", "Mehmet", "Zeynep"),
    stringsAsFactors = FALSE
  )
  canli <- data.frame(
    KullaniciID = c(2L, 3L, 4L),
    CanliDurum = c(.ood_cevrimici, .ood_bosta, .ood_cevrimdisi),
    stringsAsFactors = FALSE
  )

  adaylar <- ortak_davet_aday_kullanicilar(
    kullanicilar = kullanicilar,
    canli_durum_df = canli,
    mevcut_katilimcilar = data.frame(),
    benim_id = 1L,
    filtre = .ood_filtre_cevrimici
  )

  # Çevrimİçi (Ayşe) ve Boşta (Mehmet) görünür; çevrim dışı (Zeynep) ve
  # kendisi (Ben) elenir.
  expect_identical(sort(as.integer(adaylar$UserID)), c(2L, 3L))
  expect_true(all(c("OoCanliDurum", "OoMevcutDurum") %in% names(adaylar)))
  ayse <- adaylar[adaylar$UserID == 2L, , drop = FALSE]
  expect_identical(as.character(ayse$OoCanliDurum[1]), .ood_cevrimici)
})

test_that("aday süzme: zaten katılmış kullanıcı çevrim içi olsa da listelenmez", {
  kullanicilar <- data.frame(
    UserID = c(2L, 3L),
    KaynakAdi = c("Ayşe", "Mehmet"),
    stringsAsFactors = FALSE
  )
  canli <- data.frame(
    KullaniciID = c(2L, 3L),
    CanliDurum = c(.ood_cevrimici, .ood_cevrimici),
    stringsAsFactors = FALSE
  )
  mevcut <- data.frame(
    KullaniciID = 2L,
    KatilimDurumu = .ood_katildi,
    stringsAsFactors = FALSE
  )

  adaylar <- ortak_davet_aday_kullanicilar(
    kullanicilar = kullanicilar,
    canli_durum_df = canli,
    mevcut_katilimcilar = mevcut,
    benim_id = 99L,
    filtre = .ood_filtre_cevrimici
  )

  # Katılmış Ayşe elenir; çevrim içi Mehmet listelenir.
  expect_identical(as.integer(adaylar$UserID), 3L)
})

test_that("aday süzme: Davet Edilenler yalnızca DavetEdildi satırlarını gösterir", {
  kullanicilar <- data.frame(
    UserID = c(2L, 3L, 4L),
    KaynakAdi = c("Ayşe", "Mehmet", "Zeynep"),
    stringsAsFactors = FALSE
  )
  mevcut <- data.frame(
    KullaniciID = c(2L, 4L),
    KatilimDurumu = c("DavetEdildi", .ood_katildi),
    stringsAsFactors = FALSE
  )

  adaylar <- ortak_davet_aday_kullanicilar(
    kullanicilar = kullanicilar,
    canli_durum_df = data.frame(),
    mevcut_katilimcilar = mevcut,
    benim_id = 99L,
    filtre = "Davet Edilenler"
  )

  expect_identical(as.integer(adaylar$UserID), 2L)
})

test_that("aday süzme: Tüm Kullanıcılar çevrim dışı dahil katılmamış herkesi gösterir", {
  kullanicilar <- data.frame(
    UserID = c(1L, 2L, 3L),
    KaynakAdi = c("Ben", "Ayşe", "Mehmet"),
    stringsAsFactors = FALSE
  )
  canli <- data.frame(
    KullaniciID = c(2L, 3L),
    CanliDurum = c(.ood_cevrimdisi, .ood_cevrimdisi),
    stringsAsFactors = FALSE
  )

  adaylar <- ortak_davet_aday_kullanicilar(
    kullanicilar = kullanicilar,
    canli_durum_df = canli,
    mevcut_katilimcilar = data.frame(),
    benim_id = 1L,
    filtre = "Tüm Kullanıcılar"
  )

  # Kendisi (Ben) elenir; çevrim dışı olsalar da diğerleri görünür.
  expect_identical(sort(as.integer(adaylar$UserID)), c(2L, 3L))
})

test_that("aday süzme boş/geçersiz girdide güvenli boş çerçeve döner", {
  expect_equal(nrow(ortak_davet_aday_kullanicilar(data.frame())), 0L)
  expect_equal(nrow(ortak_davet_aday_kullanicilar(NULL)), 0L)
})
