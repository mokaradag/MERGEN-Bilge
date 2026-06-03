# ==============================================================================
# Dosya Yolu: tests/testthat/test-message-search-behavior.R
# Açıklama: R/module_message_search.R messageSearchInit() arama gözlemcilerinin
#           DAVRANIŞSAL testleri. Bu dosya daha önce hiçbir test tarafından
#           çağrılmıyordu.
#
#           messageSearchInit moduleServer DEĞİLDİR; session doğrudan iletilir,
#           bu yüzden custom message'lar kök MockShinySession üzerinden yakalanır.
#           Gözlemciler prime-then-set deseniyle tetiklenir.
#
#           Ek olarak: gregexpr() çağrısından gereksiz 'ignore.case = TRUE'
#           argümanı kaldırıldığı için arama artık UYARI ÜRETMEZ. Bu testler
#           uyarısız çalışmayı ve eşleşme sayımını doğrular. Ağ/DB GEREKMEZ.
# ==============================================================================

.source_message_search_for_test <- function() {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  suppressMessages({ library(shiny); library(shinyjs) })
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_message_search.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# Verilen mesaj listesi + arama terimiyle gözlemciyi tetikler, yakalanan
# custom message'ları döndürür. prime-then-set ile tam bir gözlemci atışı sağlanır.
.run_message_search <- function(env, messages, term) {
  rec <- new.env(); rec$msgs <- list()
  shiny::testServer(function(input, output, session) {
    env$messageSearchInit(
      input = input,
      session = session,
      values = shiny::reactiveValues(),
      messages_reactive = function() messages
    )
  }, {
    session$sendCustomMessage <- function(type, message) {
      rec$msgs[[length(rec$msgs) + 1L]] <- list(type = type, message = message)
      invisible(TRUE)
    }
    session$setInputs(message_search = "__prime__")
    session$setInputs(message_search = term)
  })
  rec
}

.first_msg <- function(rec, type) {
  for (m in rec$msgs) if (identical(m$type, type)) return(m$message)
  NULL
}

.sample_messages <- function() {
  list(
    list(id = "a", content = "test foo test"),  # 2 eşleşme
    list(id = "b", content = "bar test baz"),   # 1 eşleşme
    list(id = "c", content = "alakasız metin")  # 0 eşleşme
  )
}

# ------------------------------------------------------------------------------
# Eşleşme bulma
# ------------------------------------------------------------------------------
testthat::test_that("messageSearchInit eşleşmeleri sayar ve highlightAllOccurrences gönderir", {
  env <- .source_message_search_for_test()
  rec <- .run_message_search(env, .sample_messages(), "test")

  msg <- .first_msg(rec, "highlightAllOccurrences")
  testthat::expect_false(is.null(msg))
  testthat::expect_identical(msg$searchTerm, "test")
  # "test foo test" (2) + "bar test baz" (1) = 3 toplam eşleşme.
  testthat::expect_identical(msg$totalCount, 3L)
  # currentIndex üretimde double literal (1) olarak atanır.
  testthat::expect_equal(msg$currentIndex, 1)
  # Eşleşen mesaj kimlikleri benzersiz: a, b.
  testthat::expect_setequal(msg$messageIds, c("a", "b"))
})

testthat::test_that("messageSearchInit eşleşme yoksa total 0 olur", {
  env <- .source_message_search_for_test()
  rec <- .run_message_search(env, .sample_messages(), "kesinlikleyok")
  msg <- .first_msg(rec, "highlightAllOccurrences")
  testthat::expect_identical(msg$totalCount, 0L)
  testthat::expect_equal(msg$currentIndex, 0)
})

testthat::test_that("messageSearchInit fixed eşleşme büyük/küçük harfe duyarlıdır", {
  env <- .source_message_search_for_test()
  # "TEST" araması küçük harfli "test" içeriğiyle eşleşmez (fixed, case-sensitive).
  rec <- .run_message_search(env, list(list(id = "a", content = "test test")), "TEST")
  msg <- .first_msg(rec, "highlightAllOccurrences")
  testthat::expect_identical(msg$totalCount, 0L)
})

testthat::test_that("messageSearchInit Türkçe terimi eşleştirir", {
  env <- .source_message_search_for_test()
  rec <- .run_message_search(env,
    list(list(id = "a", content = "İstanbul ve Çağrı raporu")), "Çağrı")
  msg <- .first_msg(rec, "highlightAllOccurrences")
  testthat::expect_identical(msg$totalCount, 1L)
})

# ------------------------------------------------------------------------------
# Boş terim
# ------------------------------------------------------------------------------
testthat::test_that("messageSearchInit boş terimde clearHighlights gönderir, eşleşme aramaz", {
  env <- .source_message_search_for_test()
  rec <- .run_message_search(env, .sample_messages(), "")

  tipler <- vapply(rec$msgs, function(m) m$type, character(1))
  testthat::expect_true("clearHighlights" %in% tipler)
  testthat::expect_false("highlightAllOccurrences" %in% tipler)
})

# ------------------------------------------------------------------------------
# Regresyon: arama uyarı üretmemeli (ignore.case kaldırıldı)
# ------------------------------------------------------------------------------
testthat::test_that("messageSearchInit araması gereksiz uyarı üretmez", {
  env <- .source_message_search_for_test()
  uyarildi <- FALSE
  withCallingHandlers(
    .run_message_search(env, .sample_messages(), "test"),
    warning = function(w) {
      if (grepl("ignore.case", conditionMessage(w), fixed = TRUE)) uyarildi <<- TRUE
      invokeRestart("muffleWarning")
    }
  )
  testthat::expect_false(uyarildi)
})
