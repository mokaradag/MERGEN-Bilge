# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-stream-slot-guard-behavior.R
# Açıklama: Çözülmemiş olgu yuvası (`{{fact:...}}`) canlı akışa, düşünce
#           paneline, kalıcı düşünce arşivine ve TTS metnine ULAŞMAZ; bekleyen
#           köken kaydı saklanamamış olsa bile (bayat istek, depo yok) ham yuva
#           ertelemeyi KENDİSİ tetikler. Yuva iki akış parçasına bölünebildiği
#           için yarım açıcı bir sonraki parçaya kadar tutulur.
#           Kaynak: R/helpers_pk_stream_slot_guard.R, R/helpers_pk_provenance_peek.R,
#           R/server_handler_true_streaming.R
# ==============================================================================

.pk_guard_env <- function() {
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  for (f in c("helpers_pk_fact_reference.R", "helpers_pk_provenance.R",
              "helpers_pk_provenance_peek.R", "helpers_pk_stream_slot_guard.R")) {
    source(file.path(kok, "R", f), encoding = "UTF-8", local = env)
  }
  env
}

.pk_guard_stream <- function(env, parcalar) {
  durum <- new.env(parent = emptyenv())
  durum$accumulated_text <- ""
  durum$defer_visible_text <- FALSE
  gonderilen <- character(0)
  for (p in parcalar) {
    durum$accumulated_text <- paste0(durum$accumulated_text, p)
    adim <- env$mergen_pk_stream_visible_step(durum)
    if (!is.null(adim)) gonderilen <- c(gonderilen, adim$delta)
  }
  list(sent = paste(gonderilen, collapse = ""), defer = durum$defer_visible_text)
}

test_that("ham yuva, kayıt olmasa da görünür akışı ertelemeye alır; yarım açıcı gönderilmez", {
  env <- .pk_guard_env()

  # Yuva iki parçaya bölünmüş: "{{fa" gönderilmeden tutulur, tamamlanınca akış ertelenir.
  s <- .pk_guard_stream(env, c("Toplam ", "{{fa", "ct:olcu.sum.overall.ab12cd}} saat ", "planlandi."))
  expect_identical(s$sent, "Toplam ")
  expect_true(s$defer)
  expect_false(grepl("{", s$sent, fixed = TRUE))

  # Tek parçada yuva: hiçbir yuva metni gönderilmez.
  s <- .pk_guard_stream(env, c("Ozet: {{fact:x.y}} kayit."))
  expect_identical(s$sent, "")
  expect_true(s$defer)

  # Yuva içermeyen metin ve tamamlanmayan açıcı: tutulan ek sonraki parçada serbest kalır.
  s <- .pk_guard_stream(env, c("Kod: {", "{ ad }} ve {x}", " bitti"))
  expect_identical(s$sent, "Kod: {{ ad }} ve {x} bitti")
  expect_false(s$defer)

  plan <- env$mergen_pk_stream_visible_plan("Sonuc {{ FACT : abc")
  expect_true(plan$defer)
  expect_identical(env$mergen_pk_stream_visible_plan("Metin {{f")$send_until, nchar("Metin "))
})

test_that("düşünce akışı yuvayı nötrler; bölünmüş yuva tamamlanana kadar tutulur", {
  env <- .pk_guard_env()
  durum <- new.env(parent = emptyenv())
  durum$accumulated_reasoning <- ""
  gonderilen <- character(0)
  for (p in c("Once ", "{{fact:olcu.s", "um.overall.ab12cd}} degerini ", "inceliyorum. {")) {
    durum$accumulated_reasoning <- paste0(durum$accumulated_reasoning, p)
    gonderilen <- c(gonderilen, env$mergen_pk_stream_reasoning_step(durum, FALSE))
  }
  gonderilen <- c(gonderilen, env$mergen_pk_stream_reasoning_step(durum, TRUE))
  canli <- paste(gonderilen, collapse = "")

  expect_false(grepl("{{", canli, fixed = TRUE))
  expect_false(grepl("fact:", canli, fixed = TRUE))
  expect_identical(canli, paste0("Once ", env$PK_FACT_REF_UNRESOLVED_TR, " degerini inceliyorum. {"))
  # Kalıcı arşiv metni de aynı nötrleyiciden geçer.
  expect_identical(env$mergen_pk_neutral_text(durum$accumulated_reasoning), canli)

  # Kapanmayan uzun açıcı süresiz tutulmaz; bozuk yuva olarak nötrlenir.
  uzun <- paste0("{{fact:", strrep("a", 250))
  r <- env$mergen_pk_stream_reasoning_release(uzun, 0L, FALSE)
  expect_identical(r$sent, nchar(uzun))
  expect_false(grepl("{{fact:", r$delta, fixed = TRUE))
})

test_that("köken kaydı yokken TTS ve benzetimli akış metni ham yuva taşımaz", {
  env <- .pk_guard_env()
  env$pk_provenance_blocks_streaming <- function(session, request_id = NULL) FALSE
  env$pk_provenance_defers_streaming <- function(session, request_id = NULL) FALSE

  metin <- "Toplam {{fact:olcu.sum.overall.ab12cd}} saat planlandi."
  out <- env$mergen_pk_block_mode_texts(metin, session = NULL, request_id = "req-1")
  expect_false(grepl("{{", out$tts, fixed = TRUE))
  expect_false(grepl("{{", out$display, fixed = TRUE))
  expect_true(grepl(env$PK_FACT_REF_UNRESOLVED_TR, out$tts, fixed = TRUE))

  # PK dışı sıradan metin değişmez.
  sade <- "Merhaba {{ ad }}, kod blogu {x} icerir."
  expect_identical(env$mergen_pk_block_mode_texts(sade, session = NULL)$tts, sade)
})

test_that("gerçek akış işleyicisi görünür ve düşünce metnini koruyucudan geçirir", {
  # Yorumlar ayıklanır: yorumda alıntılanan çağrı, silinmiş kodu gizleyemez.
  kaynak <- pk_test_strip_r_comments(paste(readLines(
    file.path(resolve_repo_root_for_tests(), "R", "server_handler_true_streaming.R"),
    warn = FALSE, encoding = "UTF-8"), collapse = "\n"))
  expect_true(grepl("gorunur <- mergen_pk_stream_visible_step(stream_env)", kaynak, fixed = TRUE))
  expect_true(grepl("delta = gorunur$delta", kaynak, fixed = TRUE))
  expect_true(grepl("mergen_pk_stream_reasoning_step(stream_env, FALSE)", kaynak, fixed = TRUE))
  expect_true(grepl("mergen_pk_stream_reasoning_step(stream_env, TRUE)", kaynak, fixed = TRUE))
  expect_true(grepl("mergen_pk_neutral_text(stream_env$accumulated_reasoning", kaynak, fixed = TRUE))
  # Ham parça doğrudan istemciye gitmez.
  expect_false(grepl("delta = batches$delta_text", kaynak, fixed = TRUE))
  expect_false(grepl("delta = batches$reasoning_text", kaynak, fixed = TRUE))
  expect_false(grepl("delta = recovery_plan$delta", kaynak, fixed = TRUE))
})
