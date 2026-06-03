# ==============================================================================
# Dosya Yolu: tests/testthat/test-chat-search-db-guard-behavior.R
# Açıklama: R/module_chat_search.R search_chats_content_from_db() fonksiyonunun
#           boş-arama koruma (guard) davranışının testleri. Bu dosya daha önce
#           hiçbir test tarafından çağrılmıyordu.
#
#           Fonksiyon, boş/NULL/yalnızca-boşluk arama teriminde DB'ye HİÇ
#           bağlanmadan beklenen şemaya sahip boş bir data.frame döndürür. Bu
#           testler yalnızca o erken-dönüş yolunu kapsar; gerçek DB GEREKMEZ.
# ==============================================================================

.source_chat_search_for_test <- function() {
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  # get_connection çağrılırsa test kasıtlı olarak patlar; böylece guard'ın
  # gerçekten DB'ye gitmediği kanıtlanır.
  env$get_connection <- function(...) stop("guard ihlali: DB'ye bağlanılmamalıydı")
  env$release_connection <- function(...) invisible(NULL)
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_chat_search.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

.expected_empty_schema <- c(
  "chat_id", "chat_title", "message_content", "message_type", "message_timestamp"
)

testthat::test_that("search_chats_content_from_db NULL terimde DB'siz boş şema döndürür", {
  env <- .source_chat_search_for_test()
  out <- env$search_chats_content_from_db(user_id = 5L, search_term = NULL)
  testthat::expect_s3_class(out, "data.frame")
  testthat::expect_identical(nrow(out), 0L)
  testthat::expect_identical(names(out), .expected_empty_schema)
})

testthat::test_that("search_chats_content_from_db boş dizede boş sonuç döndürür", {
  env <- .source_chat_search_for_test()
  out <- env$search_chats_content_from_db(user_id = 5L, search_term = "")
  testthat::expect_identical(nrow(out), 0L)
  testthat::expect_identical(names(out), .expected_empty_schema)
})

testthat::test_that("search_chats_content_from_db yalnızca-boşluk terimde boş sonuç döndürür", {
  env <- .source_chat_search_for_test()
  out <- env$search_chats_content_from_db(user_id = 5L, search_term = "   \t  ")
  testthat::expect_identical(nrow(out), 0L)
  # Sütunların hepsi karakter tipinde olmalı.
  testthat::expect_true(all(vapply(out, is.character, logical(1))))
})

testthat::test_that("search_chats_content_from_db guard yolunda get_connection çağrılmaz", {
  env <- .source_chat_search_for_test()
  # get_connection hata fırlatacak şekilde stub'lı; guard düzgünse hata oluşmaz.
  testthat::expect_no_error(env$search_chats_content_from_db(1L, ""))
  testthat::expect_no_error(env$search_chats_content_from_db(1L, NULL))
})
