# ==============================================================================
# Dosya Yolu: tests/testthat/test-path-reservation-behavior.R
# Açıklama: R/utils_path_reservation.R sahiplik jetonlu rezervasyon
#           primitiflerinin davranış sözleşmesi: atomik edinme, dayanıklı
#           marker ön koşulu, sahiplik kanıtlı bırakma ve yaş + sahiplik
#           kanıtına dayalı devralma.
#
#           Çevrimdışı ve deterministiktir: gerçek dosya sistemi (tempdir)
#           kullanılır; DB, LLM, ağ, tarayıcı veya Shiny GEREKMEZ.
# ==============================================================================

local({
  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "utils_path_reservation.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
})

.rezerv_yolu <- function() {
  file.path(withr::local_tempdir(.local_envir = parent.frame()), "hedef.rsv")
}

test_that("rezervasyon atomiktir: ikinci çağrı alamaz", {
  rezerv <- .rezerv_yolu()

  jeton_a <- mergen_reservation_token("a")
  jeton_b <- mergen_reservation_token("b")
  expect_false(identical(jeton_a, jeton_b))

  expect_true(mergen_reservation_acquire(rezerv, jeton_a))
  # AYNI yol için ikinci edinme BAŞARISIZ olur; aksi hâlde iki çağrı aynı
  # hedefi terfi ettirebilirdi.
  expect_false(mergen_reservation_acquire(rezerv, jeton_b))
  expect_identical(mergen_reservation_owner(rezerv), jeton_a)
})

test_that("bırakma SAHİPLİK KANITI ister", {
  rezerv <- .rezerv_yolu()
  jeton <- mergen_reservation_token("sahip")
  expect_true(mergen_reservation_acquire(rezerv, jeton))

  # Başka bir jetonla bırakma YAPILMAZ: yeni sahibin rezervasyonu silinmemeli.
  expect_false(mergen_reservation_release(rezerv, "baska-jeton"))
  expect_true(dir.exists(rezerv))

  expect_true(mergen_reservation_release(rezerv, jeton))
  expect_false(dir.exists(rezerv))
})

test_that("boş/NA jeton edinme ve bırakma için reddedilir", {
  rezerv <- .rezerv_yolu()
  expect_false(mergen_reservation_acquire(rezerv, ""))
  expect_false(mergen_reservation_acquire(rezerv, NA_character_))
  expect_false(dir.exists(rezerv))

  jeton <- mergen_reservation_token()
  expect_true(mergen_reservation_acquire(rezerv, jeton))
  expect_false(mergen_reservation_release(rezerv, ""))
  expect_true(dir.exists(rezerv))
})

test_that("devralma YALNIZCA yaş eşiği aşıldığında yapılır", {
  rezerv <- .rezerv_yolu()
  eski <- mergen_reservation_token("eski")
  expect_true(mergen_reservation_acquire(rezerv, eski))

  yeni <- mergen_reservation_token("yeni")
  # TAZE rezervasyon devralınmaz: yalnızca yaşa bakan devralma CANLI sahibin
  # rezervasyonunu kırıp iki çağrının aynı hedefi terfi ettirmesine izin
  # veriyordu.
  expect_false(mergen_reservation_takeover(rezerv, yeni, stale_sec = 3600))
  expect_identical(mergen_reservation_owner(rezerv), eski)

  # Eşik 0 iken (her rezervasyon bayat) devralma yapılır ve JETON değişir.
  expect_true(mergen_reservation_takeover(rezerv, yeni, stale_sec = -1))
  expect_identical(mergen_reservation_owner(rezerv), yeni)
})

test_that("heartbeat sahibi doğrular; yabancı jeton tazelemez", {
  rezerv <- .rezerv_yolu()
  jeton <- mergen_reservation_token()
  expect_true(mergen_reservation_acquire(rezerv, jeton))

  expect_true(mergen_reservation_touch(rezerv, jeton))
  expect_false(mergen_reservation_touch(rezerv, "yabanci"))
  expect_identical(mergen_reservation_owner(rezerv), jeton)
})

test_that("var olmayan rezervasyon için sahip NA ve yaş NA döner", {
  rezerv <- .rezerv_yolu()
  expect_true(is.na(mergen_reservation_owner(rezerv)))
  expect_true(is.na(mergen_reservation_age_sec(rezerv)))
  # Sahip okunamıyorsa bırakma da YAPILMAZ (kanıt yok).
  expect_false(mergen_reservation_release(rezerv, mergen_reservation_token()))
})
