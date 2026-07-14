# ==============================================================================
# Dosya Yolu: tests/testthat/test-tts-queue-behavior.R
# Açıklama: Sınırlı eşzamanlılık TTS kuyruğu davranış testleri: en fazla N aktif,
#           FIFO başlatma, iptal, hata sonrası kilitlenmeme, tamamlanmada pompalama.
#           Elle çözülebilir promise'ler + later::run_now() ile deterministiktir.
# ==============================================================================

if (!exists("tts_fixture_source_helpers", mode = "function")) {
  source(file.path(resolve_repo_root_for_tests(), "tests", "testthat", "helper_tts_voice_fixtures.R"),
         encoding = "UTF-8", local = FALSE)
}
tts_fixture_source_helpers()

testthat::skip_if_not_installed("promises")
testthat::skip_if_not_installed("later")
suppressMessages({ library(promises); library(later) })

.drain <- function(n = 100) for (i in seq_len(n)) later::run_now()

# Elle çözülebilir promise fabrikaları üreten denetleyici
.make_controller <- function() {
  ctrl <- new.env(parent = emptyenv())
  ctrl$resolvers <- list()
  ctrl$rejecters <- list()
  ctrl$started <- character(0)
  ctrl$factory <- function(id) {
    force(id)
    function() {
      ctrl$started <- c(ctrl$started, id)
      promises::promise(function(resolve, reject) {
        ctrl$resolvers[[id]] <- resolve
        ctrl$rejecters[[id]] <- reject
      })
    }
  }
  ctrl
}

test_that("kuyruk en fazla max_concurrency işi aynı anda çalıştırır ve FIFO başlatır", {
  q <- mergen_tts_create_queue(2L)
  ctrl <- .make_controller()

  q$submit(ctrl$factory("a"))
  q$submit(ctrl$factory("b"))
  q$submit(ctrl$factory("c"))
  q$submit(ctrl$factory("d"))
  .drain()

  expect_identical(q$active_count(), 2L)
  expect_identical(q$pending_count(), 2L)
  expect_identical(ctrl$started, c("a", "b"))   # FIFO

  ctrl$resolvers[["a"]](list(success = TRUE))
  .drain()
  expect_identical(q$active_count(), 2L)         # c başladı
  expect_identical(ctrl$started, c("a", "b", "c"))

  ctrl$resolvers[["b"]](list(success = TRUE))
  ctrl$resolvers[["c"]](list(success = TRUE))
  .drain()
  expect_identical(ctrl$started, c("a", "b", "c", "d"))

  ctrl$resolvers[["d"]](list(success = TRUE))
  .drain()
  expect_identical(q$active_count(), 0L)
  expect_identical(q$pending_count(), 0L)
})

test_that("iptal edilen iş başlatılmaz ve iptal sonucu döner", {
  q <- mergen_tts_create_queue(1L)
  ctrl <- .make_controller()
  cancel_result <- NULL

  p <- q$submit(ctrl$factory("x"), should_cancel = function() TRUE)
  promises::then(p, function(v) cancel_result <<- v)
  .drain()

  expect_false("x" %in% ctrl$started)            # başlatılmadı
  expect_true(isTRUE(cancel_result$cancelled))
  expect_false(isTRUE(cancel_result$success))
  expect_identical(q$active_count(), 0L)
})

test_that("bir işin hatası kuyruğu kilitlemez; sıradaki başlar", {
  q <- mergen_tts_create_queue(1L)
  ctrl <- .make_controller()
  err_caught <- NULL

  p1 <- q$submit(ctrl$factory("a"))
  q$submit(ctrl$factory("b"))
  promises::then(p1, onFulfilled = function(v) NULL, onRejected = function(e) err_caught <<- conditionMessage(e))
  .drain()
  expect_identical(ctrl$started, "a")

  ctrl$rejecters[["a"]](simpleError("bilinçli hata"))
  .drain()
  expect_identical(err_caught, "bilinçli hata")
  expect_identical(ctrl$started, c("a", "b"))     # hataya rağmen b başladı
  expect_identical(q$active_count(), 1L)
})

test_that("submit edilen promise, işin sonucuyla çözülür", {
  q <- mergen_tts_create_queue(2L)
  ctrl <- .make_controller()
  got <- NULL
  p <- q$submit(ctrl$factory("a"))
  promises::then(p, function(v) got <<- v)
  .drain()
  ctrl$resolvers[["a"]](list(success = TRUE, audio_src = "data:x"))
  .drain()
  expect_true(isTRUE(got$success))
  expect_identical(got$audio_src, "data:x")
})

test_that("should_cancel hatası güvenli varsayılana (iptal etme) düşer", {
  q <- mergen_tts_create_queue(1L)
  ctrl <- .make_controller()
  q$submit(ctrl$factory("a"), should_cancel = function() stop("reaktif bağlam yok"))
  .drain()
  expect_identical(ctrl$started, "a")   # hata iptale yol açmaz -> iş başlar
})

test_that("stats sayaçları doğru raporlar", {
  q <- mergen_tts_create_queue(2L)
  ctrl <- .make_controller()
  q$submit(ctrl$factory("a"))
  q$submit(ctrl$factory("b"))
  q$submit(ctrl$factory("c"))
  .drain()
  s <- q$stats()
  expect_identical(s$max, 2L)
  expect_identical(s$submitted, 3L)
  expect_identical(s$started, 2L)
  expect_identical(s$active, 2L)
  expect_identical(s$pending, 1L)
})
