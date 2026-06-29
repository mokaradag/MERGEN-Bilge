# ==============================================================================
# Dosya Yolu: tests/testthat/test-stream-load-control-behavior.R
# Açıklama: R/helpers_stream_load_control.R yük denetimi yardımcılarının
#           davranışsal testleri: araç ailesi -> backpressure türü, takip
#           (follow-up) üretim kabul/kısma kararı ve kaydedilen sohbet yenileme
#           debounce'u (anında / coalesce / hata sayacı). Shiny/DB/LLM gerekmez.
# ==============================================================================

testthat::local_edition(3)

source("../../R/helpers_runtime_metrics.R")
source("../../R/helpers_request_backpressure.R")
source("../../R/helpers_streaming_io.R")
source("../../R/helpers_stream_load_control.R")

.fake_session <- function() list(userData = new.env(parent = emptyenv()))

# ------------------------------------------------------------------------------
# Backpressure türü çözümü
# ------------------------------------------------------------------------------

test_that("backpressure turu arac ailesinden cozulur", {
  expect_identical(mergen_send_message_backpressure_kind("sql_analysis"), "sql_analysis")
  expect_identical(mergen_send_message_backpressure_kind("mcp_excel"), "mcp_excel")
  expect_identical(mergen_send_message_backpressure_kind("summarization"), "summarization")
  expect_identical(mergen_send_message_backpressure_kind("none"), "llm")
  expect_identical(mergen_send_message_backpressure_kind("coding"), "llm")
  expect_identical(mergen_send_message_backpressure_kind("process"), "llm")
  expect_identical(mergen_send_message_backpressure_kind(NULL), "llm")
})

# ------------------------------------------------------------------------------
# Takip üretimi yük denetimi
# ------------------------------------------------------------------------------

test_that("takip plan varsayilanlari: etkin, gecikme 0", {
  withr::with_envvar(c(
    MERGEN_FOLLOWUPS_ENABLED = "", MERGEN_FOLLOWUP_DELAY_SECONDS = "",
    MERGEN_DISABLE_FOLLOWUPS_UNDER_BACKPRESSURE = ""
  ), {
    plan <- mergen_followup_dispatch_plan()
    expect_true(plan$enabled)
    expect_identical(plan$delay_seconds, 0)
    expect_true(plan$disable_under_backpressure)
  })

  withr::with_envvar(c(MERGEN_FOLLOWUP_DELAY_SECONDS = "2"), {
    expect_identical(mergen_followup_dispatch_plan()$delay_seconds, 2)
  })
})

test_that("MERGEN_FOLLOWUPS_ENABLED=false takip uretimini atlar", {
  withr::with_envvar(c(MERGEN_FOLLOWUPS_ENABLED = "false"), {
    mergen_runtime_metrics_reset()
    res <- mergen_followup_try_admit()
    expect_false(res$run)
    expect_identical(res$reason, "disabled")
    expect_equal(mergen_runtime_metric_get("followups_skipped_disabled"), 1)
  })
})

test_that("limit kapaliyken takip her zaman kabul edilir (token NULL)", {
  withr::with_envvar(c(MERGEN_FOLLOWUPS_ENABLED = "", MERGEN_MAX_CONCURRENT_FOLLOWUPS = ""), {
    mergen_backpressure_reset()
    res <- mergen_followup_try_admit()
    expect_true(res$run)
    expect_null(res$token)
    expect_identical(res$reason, "admitted")
  })
})

test_that("limit dolunca ve disable bayragi acikken takip atlanir", {
  withr::with_envvar(c(
    MERGEN_FOLLOWUPS_ENABLED = "", MERGEN_MAX_CONCURRENT_FOLLOWUPS = "1",
    MERGEN_DISABLE_FOLLOWUPS_UNDER_BACKPRESSURE = ""
  ), {
    mergen_backpressure_reset()
    a1 <- mergen_followup_try_admit()
    expect_true(a1$run)
    a2 <- mergen_followup_try_admit()
    expect_false(a2$run)
    expect_identical(a2$reason, "backpressure")
    mergen_backpressure_release(a1$token)
  })
})

test_that("disable bayragi kapaliyken slot yoksa en-iyi-caba calisir", {
  withr::with_envvar(c(
    MERGEN_FOLLOWUPS_ENABLED = "", MERGEN_MAX_CONCURRENT_FOLLOWUPS = "1",
    MERGEN_DISABLE_FOLLOWUPS_UNDER_BACKPRESSURE = "false"
  ), {
    mergen_backpressure_reset()
    a1 <- mergen_followup_try_admit()
    expect_true(a1$run)
    a2 <- mergen_followup_try_admit()
    expect_true(a2$run)
    expect_null(a2$token)
    expect_identical(a2$reason, "best_effort")
    mergen_backpressure_release(a1$token)
  })
})

# ------------------------------------------------------------------------------
# Kaydedilen sohbet yenileme debounce
# ------------------------------------------------------------------------------

test_that("debounce 0 (varsayilan) aninda yeniler", {
  withr::with_envvar(c(MERGEN_SAVED_CHATS_REFRESH_DEBOUNCE_MS = ""), {
    expect_identical(mergen_saved_chats_refresh_debounce_ms(), 0)
  })

  refreshed <- 0L
  scd <- list(refresh = function() refreshed <<- refreshed + 1L)
  mergen_runtime_metrics_reset()

  out <- mergen_schedule_saved_chats_refresh(.fake_session(), scd, debounce_ms = 0)
  expect_true(out)
  expect_identical(refreshed, 1L)
  expect_equal(mergen_runtime_metric_get("saved_chats_refresh_executed"), 1)
})

test_that("debounce penceresinde coklu cagri tek yenilemede birlestirilir", {
  calls <- list()
  fake_later <- function(fn, delay = 0) {
    calls[[length(calls) + 1L]] <<- fn
    invisible(NULL)
  }

  refreshed <- 0L
  scd <- list(refresh = function() refreshed <<- refreshed + 1L)
  sess <- .fake_session()
  mergen_runtime_metrics_reset()

  for (i in 1:3) {
    mergen_schedule_saved_chats_refresh(sess, scd, debounce_ms = 1000, later_fn = fake_later)
  }

  # Tek zamanlayici kuruldu (coalesce); henuz yenileme calismadi.
  expect_identical(length(calls), 1L)
  expect_identical(refreshed, 0L)
  expect_equal(mergen_runtime_metric_get("saved_chats_refresh_scheduled"), 1)
  expect_equal(mergen_runtime_metric_get("saved_chats_refresh_coalesced"), 2)

  # Zamanlayici atesleyince tek yenileme yapilir.
  calls[[1]]()
  expect_identical(refreshed, 1L)
  expect_equal(mergen_runtime_metric_get("saved_chats_refresh_executed"), 1)
})

test_that("debounce: yenileme hatasi sayaca yazilir, cokme olmaz", {
  calls <- list()
  fake_later <- function(fn, delay = 0) {
    calls[[length(calls) + 1L]] <<- fn
    invisible(NULL)
  }

  scd <- list(refresh = function() stop("boom"))
  mergen_runtime_metrics_reset()

  mergen_schedule_saved_chats_refresh(.fake_session(), scd, debounce_ms = 500, later_fn = fake_later)
  expect_silent(calls[[1]]())
  expect_equal(mergen_runtime_metric_get("saved_chats_refresh_failed"), 1)
})

test_that("oturum-yereldir: bir oturumun bekleyen durumu digerini etkilemez", {
  calls <- list()
  fake_later <- function(fn, delay = 0) {
    calls[[length(calls) + 1L]] <<- fn
    invisible(NULL)
  }
  scd <- list(refresh = function() invisible(NULL))

  s1 <- .fake_session()
  s2 <- .fake_session()
  mergen_schedule_saved_chats_refresh(s1, scd, debounce_ms = 1000, later_fn = fake_later)
  mergen_schedule_saved_chats_refresh(s2, scd, debounce_ms = 1000, later_fn = fake_later)

  # Iki ayri oturum -> iki ayri zamanlayici.
  expect_identical(length(calls), 2L)
})

test_that("refresh fonksiyonu yoksa guvenli no-op", {
  expect_false(mergen_schedule_saved_chats_refresh(.fake_session(), list(), debounce_ms = 0))
})
