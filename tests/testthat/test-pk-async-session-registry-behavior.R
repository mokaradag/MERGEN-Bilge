# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-async-session-registry-behavior.R
# Açıklama: Faz 6 (§5.10) — OTURUM KAPSAMLI aktif PK istek kayıt defteri.
#
# Kanıtlanan sözleşmeler:
#   - `onSessionEnded` kancası OTURUM BAŞINA BİR KEZ kurulur (istek başına bir
#     kapanış kaydetmek, tamamlanan HER isteğin gönderim çerçevesini oturum
#     ömrü boyunca canlı tutuyordu).
#   - Terk etme VARSAYILAN olarak serbest bırakma kapanışını ÇALIŞTIRMAZ:
#     gezinme/yeni sohbet yolunda taze durum ezilmemelidir. Oturum kapanışı
#     `release = TRUE` geçer.
#   - Kaydedilmemiş sohbetler `NULL` kimliği PAYLAŞIR; nesil sayacı olmadan
#     "kaydedilmemiş sohbet A" ile Yeni Söyleşi sonrası "kaydedilmemiş sohbet B"
#     ayırt edilemez ve tamamlanan bir işçinin sonucu TAZE sohbete düşerdi.
#
# Tamamen çevrimdışı: gerçek Shiny oturumu, DB, LLM veya ağ YOKTUR.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  source(file.path(repo_root, "R", "helpers_pk_async_cancel.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_pk_async_session_registry.R"),
         encoding = "UTF-8", local = globalenv())
})

# Sahte oturum: `userData` bir ortamdır (gerçek Shiny davranışı) ve
# `onSessionEnded` kayıtlı kapanışları saklar.
.pk_kayit_oturumu <- function() {
  oturum <- new.env(parent = emptyenv())
  oturum$userData <- new.env(parent = emptyenv())
  oturum$.kancalar <- list()
  oturum$onSessionEnded <- function(fn) {
    oturum$.kancalar <- c(oturum$.kancalar, list(fn))
    invisible(TRUE)
  }
  oturum
}

.pk_kayit_jetonu <- function(ad) {
  dizin <- file.path(tempdir(), "pk_kayit_testi")
  dir.create(dizin, recursive = TRUE, showWarnings = FALSE)
  yol <- pk_cancel_token_path(ad, base_dir = dizin)
  pk_cancel_token_clear(yol)
  yol
}

test_that("oturum-sonu kancası OTURUM BAŞINA BİR KEZ kurulur", {
  oturum <- .pk_kayit_oturumu()
  j1 <- .pk_kayit_jetonu("kayit_a")
  j2 <- .pk_kayit_jetonu("kayit_b")

  mergen_pk_register_active_request(oturum, "req-1", j1)
  mergen_pk_register_active_request(oturum, "req-2", j2)
  mergen_pk_register_active_request(oturum, "req-3", j1)

  expect_length(oturum$.kancalar, 1L)
})

test_that("terk etme jetonu SİNYALLER ama varsayılan olarak SERBEST BIRAKMAZ", {
  oturum <- .pk_kayit_oturumu()
  jeton <- .pk_kayit_jetonu("kayit_c")
  birakildi <- 0L

  mergen_pk_register_active_request(
    oturum, "req-1", jeton,
    release_fn = function() birakildi <<- birakildi + 1L
  )

  # Gezinme/yeni sohbet yolu: iptal EVET, serbest bırakma HAYIR.
  mergen_pk_abandon_active_requests(oturum)
  expect_true(pk_cancel_token_is_signalled(jeton))
  expect_equal(birakildi, 0L)

  # Oturum kapanışı: serbest bırakma kapanışı DA çalışmalıdır.
  mergen_pk_abandon_active_requests(oturum, release = TRUE)
  expect_equal(birakildi, 1L)

  pk_cancel_token_clear(jeton)
})

test_that("oturum-sonu kancası oturumu KAPALI işaretler ve serbest bırakır", {
  oturum <- .pk_kayit_oturumu()
  jeton <- .pk_kayit_jetonu("kayit_d")
  birakildi <- 0L

  expect_true(mergen_pk_session_open(oturum))
  mergen_pk_register_active_request(
    oturum, "req-1", jeton,
    release_fn = function() birakildi <<- birakildi + 1L
  )

  oturum$.kancalar[[1]]()

  # Geç gelen bir geri çağrı KAPALI oturuma yazmamalıdır.
  expect_false(mergen_pk_session_open(oturum))
  expect_true(pk_cancel_token_is_signalled(jeton))
  expect_equal(birakildi, 1L)

  pk_cancel_token_clear(jeton)
})

test_that("kayıt silme yalnızca ilgili isteği düşürür", {
  oturum <- .pk_kayit_oturumu()
  j1 <- .pk_kayit_jetonu("kayit_e1")
  j2 <- .pk_kayit_jetonu("kayit_e2")

  mergen_pk_register_active_request(oturum, "req-1", j1)
  mergen_pk_register_active_request(oturum, "req-2", j2)
  mergen_pk_unregister_active_request(oturum, "req-1")

  mergen_pk_abandon_active_requests(oturum)
  expect_false(pk_cancel_token_is_signalled(j1))
  expect_true(pk_cancel_token_is_signalled(j2))

  pk_cancel_token_clear(j2)
})

test_that("kaydedilmemiş sohbetler NESİL sayacıyla ayrışır", {
  oturum <- .pk_kayit_oturumu()
  degerler <- list(current_chat_id = NULL)

  kimlik_1 <- mergen_pk_chat_identity(oturum, degerler)
  kimlik_1b <- mergen_pk_chat_identity(oturum, degerler)
  expect_identical(kimlik_1, kimlik_1b)

  # Yeni Söyleşi: nesil ilerler; AYNI `NULL` sohbet kimliği artık FARKLI
  # bir kaydedilmemiş sohbeti temsil eder.
  mergen_pk_bump_chat_epoch(oturum)
  kimlik_2 <- mergen_pk_chat_identity(oturum, degerler)
  expect_false(identical(kimlik_1, kimlik_2))

  # Kaydedilmiş sohbet kimliği nesilden BAĞIMSIZDIR (gerçek kimliği vardır).
  kayitli <- mergen_pk_chat_identity(oturum, list(current_chat_id = 42L))
  mergen_pk_bump_chat_epoch(oturum)
  expect_identical(kayitli, mergen_pk_chat_identity(oturum, list(current_chat_id = 42L)))
})

test_that("kayıt defteri bozuk oturumda SESSİZCE güvenli davranır", {
  bozuk <- list()  # `userData` yok
  expect_silent(mergen_pk_register_active_request(bozuk, "req-1", NULL))
  expect_silent(mergen_pk_abandon_active_requests(bozuk))
  expect_silent(mergen_pk_unregister_active_request(bozuk, "req-1"))
})
