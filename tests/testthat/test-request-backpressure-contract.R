# ==============================================================================
# Dosya Yolu: tests/testthat/test-request-backpressure-contract.R
# Açıklama: Süreç-geneli kabul-denetimi (backpressure) yardımcısının
#           (R/helpers_request_backpressure.R) davranış/sözleşme testleri.
#
# Doğrulananlar:
#   - VARSAYILAN KAPALI (limit 0) iken acquire her zaman başarılı, token NULL ve
#     hiç slot/istatistik birikmez (davranış bayt-bayt korunur).
#   - Limit > 0 iken eşzamanlı slotlar üst-sınıra bağlanır; aşıldığında reddedilir.
#   - release IDEMPOTENT'tir ve slot serbest bırakınca kapasite geri gelir.
#   - TTL ile kendi-iyileşme: bırakılmayan slot TTL sonrası geri toplanır
#     (kapasite kalıcı azalmaz) -> stop/iptal yolları atlansa bile sızıntı yok.
#   - Anlık görüntü sır-güvenli sayısaldır.
#
# Bu testler app.R'yi BAŞLATMAZ; saf yardımcı dosya tek başına source edilir ve
# `now` enjekte edildiği için deterministiktir.
# ==============================================================================

testthat::local_edition(3)

source("../../R/helpers_runtime_metrics.R")
source("../../R/helpers_request_backpressure.R")

test_that("varsayilan KAPALI (limit 0): acquire her zaman basarili, slot birikmez", {
  withr::with_envvar(c(MERGEN_MAX_CONCURRENT_LLM = ""), {
    mergen_backpressure_reset()
    expect_equal(mergen_backpressure_limit("llm"), 0L)

    a <- mergen_backpressure_try_acquire("llm")
    expect_true(a$acquired)
    expect_null(a$token)
    expect_equal(a$limit, 0L)

    # Slot/istatistik birikmemeli (kapaliyken sifir ek durum).
    snap <- mergen_backpressure_snapshot()
    expect_equal(snap$total_active_slots, 0L)
  })
})

test_that("limit > 0: eszamanli slot ust-sinira baglanir, asilinca reddedilir", {
  withr::with_envvar(c(MERGEN_MAX_CONCURRENT_LLM = "2"), {
    mergen_backpressure_reset()
    expect_equal(mergen_backpressure_limit("llm"), 2L)

    r1 <- mergen_backpressure_try_acquire("llm", now = 1000)
    r2 <- mergen_backpressure_try_acquire("llm", now = 1000)
    r3 <- mergen_backpressure_try_acquire("llm", now = 1000)

    expect_true(r1$acquired)
    expect_true(r2$acquired)
    expect_false(r3$acquired)
    expect_null(r3$token)
    expect_equal(r3$active, 2L)
    expect_equal(r3$limit, 2L)
    expect_gt(r3$retry_after_sec, 0L)

    # Bir slot birakilinca kapasite geri gelir.
    expect_true(mergen_backpressure_release(r1$token))
    r4 <- mergen_backpressure_try_acquire("llm", now = 1000)
    expect_true(r4$acquired)
  })
})

test_that("release IDEMPOTENT'tir (cift birakma kapasiteyi bozmaz)", {
  withr::with_envvar(c(MERGEN_MAX_CONCURRENT_LLM = "1"), {
    mergen_backpressure_reset()
    a <- mergen_backpressure_try_acquire("llm", now = 1000)
    expect_true(mergen_backpressure_release(a$token))   # ilk birakma
    expect_false(mergen_backpressure_release(a$token))  # tekrar -> no-op
    expect_false(mergen_backpressure_release(NULL))     # NULL -> no-op
    expect_false(mergen_backpressure_release("bilinmeyen-token"))
  })
})

test_that("TTL ile kendi-iyilesme: birakilmayan slot TTL sonrasi geri toplanir", {
  withr::with_envvar(c(MERGEN_MAX_CONCURRENT_LLM = "1",
                       MERGEN_BACKPRESSURE_TTL_SECONDS = "10"), {
    mergen_backpressure_reset()
    s1 <- mergen_backpressure_try_acquire("llm", now = 2000)   # hic birakilmaz
    expect_true(s1$acquired)

    # TTL icinde -> reddedilir (slot hala canli).
    s2 <- mergen_backpressure_try_acquire("llm", now = 2005)
    expect_false(s2$acquired)

    # TTL sonrasi -> bayat slot geri toplanir -> kabul.
    s3 <- mergen_backpressure_try_acquire("llm", now = 2020)
    expect_true(s3$acquired)
  })
})

test_that("acquire/reject calisma-zamani metriklerini sayar", {
  withr::with_envvar(c(MERGEN_MAX_CONCURRENT_LLM = "1"), {
    mergen_backpressure_reset()
    mergen_runtime_metrics_reset()
    a <- mergen_backpressure_try_acquire("llm", now = 3000)
    b <- mergen_backpressure_try_acquire("llm", now = 3000)  # reddedilir
    expect_true(a$acquired)
    expect_false(b$acquired)
    expect_gte(mergen_runtime_metric_get("backpressure_admit_llm"), 1)
    expect_gte(mergen_runtime_metric_get("backpressure_reject_llm"), 1)
  })
})

test_that("anlik goruntu sir-guvenli sayisaldir", {
  withr::with_envvar(c(MERGEN_MAX_CONCURRENT_LLM = "2"), {
    mergen_backpressure_reset()
    mergen_backpressure_try_acquire("llm", now = 4000)
    snap <- mergen_backpressure_snapshot()
    expect_true(is.numeric(snap$ttl_sec))
    expect_true(is.numeric(snap$total_active_slots))
    expect_true(all(c("active", "limit", "admitted", "rejected", "expired") %in%
                      names(snap$kinds$llm)))
    expect_true(all(vapply(snap$kinds$llm, is.numeric, logical(1))))
  })
})
