# ==============================================================================
# Dosya Yolu: tests/testthat/test-destek-hata-bildir-behavior.R
# Açıklama: R/module_destek_hata_bildir.R destekHataBildirServer() form
#           doğrulama ve gönderim mantığının DAVRANIŞSAL testleri. Bu dosya daha
#           önce hiçbir test tarafından çağrılmıyordu.
#
#           gonder_hata gözlemcisi zorunlu alanları (konular/kategoriler/
#           açıklama) doğrular, kimlik hazır değilse engeller ve geçerli durumda
#           destek_hata_bildir_kaydet() çağırıp başarı tetikleyicisini artırır.
#           Alan input'ları önce set edilir, sonra gonder_hata prime-then-set ile
#           tetiklenir. resolve_effective_user_id / showToast /
#           destek_hata_bildir_kaydet stub'lanır. Gerçek DB GEREKMEZ.
# ==============================================================================

.source_hata_bildir_for_test <- function(user_id = 5L) {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  suppressMessages({ library(shiny); library(shinyjs) })
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  rec <- new.env()
  rec$toasts <- list()
  rec$saves <- list()

  env$resolve_effective_user_id <- function(session, current_user_id) user_id
  env$showToast <- function(session, message, type = "info") {
    rec$toasts[[length(rec$toasts) + 1L]] <- list(message = message, type = type)
    invisible(NULL)
  }
  env$destek_hata_bildir_kaydet <- function(...) {
    rec$saves[[length(rec$saves) + 1L]] <- list(...)
    invisible(TRUE)
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_destek_hata_bildir.R"),
    encoding = "UTF-8",
    local = env
  )
  list(env = env, rec = rec)
}

.toast_msgs <- function(rec) vapply(rec$toasts, function(t) t$message, character(1))

# Alanları set eder ve gonder_hata'yı prime-then-set ile tetikler.
.submit_bug <- function(fix, fields) {
  env <- fix$env
  res <- new.env()
  shiny::testServer(env$destekHataBildirServer, args = list(current_user_id = 5L), {
    do.call(session$setInputs, fields)
    session$setInputs(gonder_hata = 1)
    session$setInputs(gonder_hata = 2)
    res$basarili <- session$returned$basarili()
  })
  res
}

.valid_fields <- function() {
  list(
    konular_birlesik = "Giriş yapılamıyor",
    secili_kategoriler = "cokme",
    hata_aciklama = "Uygulama açılışta çöküyor",
    secili_oncelik = "yuksek"
  )
}

# ------------------------------------------------------------------------------
# Zorunlu alan doğrulaması
# ------------------------------------------------------------------------------
testthat::test_that("gonder_hata tüm zorunlu alanlar boşken kaydetmez ve uyarı verir", {
  fix <- .source_hata_bildir_for_test()
  .submit_bug(fix, list(
    konular_birlesik = "", secili_kategoriler = "", hata_aciklama = "", secili_oncelik = ""
  ))
  testthat::expect_length(fix$rec$saves, 0L)
  testthat::expect_true(any(grepl("zorunlu alanları doldurun", .toast_msgs(fix$rec), fixed = TRUE)))
})

testthat::test_that("gonder_hata yalnızca açıklama eksikse kaydetmez", {
  fix <- .source_hata_bildir_for_test()
  f <- .valid_fields(); f$hata_aciklama <- "   "  # yalnızca boşluk
  .submit_bug(fix, f)
  testthat::expect_length(fix$rec$saves, 0L)
})

# ------------------------------------------------------------------------------
# Kimlik hazır değil
# ------------------------------------------------------------------------------
testthat::test_that("gonder_hata kimlik hazır değilken (uid<=0) kaydetmez ve uyarır", {
  fix <- .source_hata_bildir_for_test(user_id = 0L)
  .submit_bug(fix, .valid_fields())
  testthat::expect_length(fix$rec$saves, 0L)
  testthat::expect_true(any(grepl("Kimlik doğrulama tamamlanmadan",
                                  .toast_msgs(fix$rec), fixed = TRUE)))
})

# ------------------------------------------------------------------------------
# Başarılı gönderim
# ------------------------------------------------------------------------------
testthat::test_that("gonder_hata geçerli formda kaydeder ve başarı tetikleyicisini artırır", {
  fix <- .source_hata_bildir_for_test(user_id = 7L)
  res <- .submit_bug(fix, .valid_fields())

  testthat::expect_true(length(fix$rec$saves) >= 1L)
  son <- fix$rec$saves[[length(fix$rec$saves)]]
  testthat::expect_identical(son$user_id, 7L)
  testthat::expect_identical(son$konular, "Giriş yapılamıyor")
  testthat::expect_identical(son$kategoriler, "cokme")
  testthat::expect_identical(son$oncelik, "yuksek")
  # Ek dosya yok -> NULL.
  testthat::expect_null(son$ek_dosya_yollari)
  # Başarı tetikleyicisi artmış olmalı.
  testthat::expect_true(res$basarili >= 1)
})

testthat::test_that("gonder_hata öncelik verilmezse 'belirtilmedi' varsayılanını kullanır", {
  fix <- .source_hata_bildir_for_test(user_id = 7L)
  f <- .valid_fields(); f$secili_oncelik <- ""
  .submit_bug(fix, f)
  son <- fix$rec$saves[[length(fix$rec$saves)]]
  testthat::expect_identical(son$oncelik, "belirtilmedi")
})

# ------------------------------------------------------------------------------
# Dosya boyutu guard'ı
# ------------------------------------------------------------------------------
testthat::test_that("dosya_bilgisi 10MB üstü dosyada boyut uyarısı verir", {
  fix <- .source_hata_bildir_for_test()
  shiny::testServer(fix$env$destekHataBildirServer, args = list(current_user_id = 5L), {
    session$setInputs(dosya_bilgisi = list(name = "buyuk.zip", size = 11 * 1024 * 1024))
    session$setInputs(dosya_bilgisi = list(name = "buyuk2.zip", size = 12 * 1024 * 1024))
  })
  testthat::expect_true(any(grepl("10MB'dan büyük olamaz", .toast_msgs(fix$rec), fixed = TRUE)))
})

# ------------------------------------------------------------------------------
# Ek dosya yol güvenliği (istemciden gelen `path` alanına güvenilmez)
# ------------------------------------------------------------------------------
testthat::test_that("dosya_bilgisi istemciden gelen path alanını saklamaz", {
  fix <- .source_hata_bildir_for_test()
  kurban <- withr::local_tempfile(fileext = ".txt")
  writeLines("silinmemeli", kurban)

  shiny::testServer(fix$env$destekHataBildirServer, args = list(current_user_id = 5L), {
    session$setInputs(dosya_bilgisi = list(name = "rapor.txt", size = 10, path = kurban))
    session$setInputs(dosya_bilgisi = list(name = "rapor2.txt", size = 11, path = kurban))
    # Silme gözlemcisi istemci path'ini kullanamamalı: dosya yerinde kalmalı.
    session$setInputs(dosya_sil = 1)
    session$setInputs(dosya_sil = 2)
  })

  testthat::expect_true(file.exists(kurban))
})

testthat::test_that("ek yolu guard'ı destek_uploads kökü dışını reddeder", {
  fix <- .source_hata_bildir_for_test()

  shiny::testServer(fix$env$destekHataBildirServer, args = list(current_user_id = 5L), {
    guvenli <- destek_ek_yolu_guvenli
    temizle <- destek_ek_adi_temizle

    testthat::expect_true(guvenli(file.path("destek_uploads", "5", "a.txt")))
    testthat::expect_false(guvenli(file.path("destek_uploads", "..", "gizli.txt")))
    testthat::expect_false(guvenli(tempfile(fileext = ".txt")))
    testthat::expect_false(guvenli(""))
    testthat::expect_false(guvenli(NULL))

    testthat::expect_identical(temizle("../../etc/passwd"), "passwd")
    testthat::expect_identical(temizle("rapor.pdf"), "rapor.pdf")
    testthat::expect_identical(temizle(".."), "ek")
    testthat::expect_identical(temizle("Türkçe dosya.png"), "Türkçe dosya.png")
  })
})

# Regresyon: hedef dosya HENÜZ YOKKEN `normalizePath(..., mustWork = FALSE)`
# POSIX'te göreli girdiyi olduğu gibi döndürüyor; `destek_ek_koku()` ise
# `destek_uploads` GERÇEKTEN VAR olduğunda MUTLAK yol üretiyordu. Önek kıyası bu
# yüzden FALSE oluyor ve kimliği doğrulanmış HER yükleme reddediliyordu.
testthat::test_that("var olmayan yeni ek hedefi mutlak köke karşı doğrulanır", {
  fix <- .source_hata_bildir_for_test()

  calisma <- withr::local_tempdir()
  withr::local_dir(calisma)
  dir.create(file.path("destek_uploads", "5"), recursive = TRUE, showWarnings = FALSE)
  # Kök GERÇEKTEN vardır: normalizePath() artık mutlak yol döndürür.
  testthat::expect_true(dir.exists("destek_uploads"))

  shiny::testServer(fix$env$destekHataBildirServer, args = list(current_user_id = 5L), {
    guvenli <- destek_ek_yolu_guvenli

    # Henüz oluşturulmamış hedef KABUL edilmelidir (file.copy öncesi denetim).
    testthat::expect_true(guvenli(file.path("destek_uploads", "5", "yeni.txt"), 5L))
    # Var olan hedef de kabul edilir.
    writeLines("x", file.path("destek_uploads", "5", "var.txt"))
    testthat::expect_true(guvenli(file.path("destek_uploads", "5", "var.txt"), 5L))

    # BAŞKA kullanıcının alt klasörü reddedilir.
    dir.create(file.path("destek_uploads", "9"), recursive = TRUE, showWarnings = FALSE)
    testthat::expect_false(guvenli(file.path("destek_uploads", "9", "yeni.txt"), 5L))
    # Kök dışı yol reddedilir.
    testthat::expect_false(guvenli(file.path(calisma, "disarida.txt"), 5L))
    testthat::expect_false(guvenli(file.path("destek_uploads", "5", "..", "x.txt"), 5L))
  })
})
