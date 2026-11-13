# ==============================================================================
# Dosya Yolu: tests/testthat/test-saved-chats-search-behavior.R
# Açıklama: Kayıtlı Söyleşiler araması çalışma zamanında doğrudan
#           input$search_chats ile süzer (kaldırılan 300 ms zamanlayıcı ve
#           debounce reaktifine kalan bir başvuru sayfayı düşürmez). Gerçek
#           modül sunucusu testServer ile çalıştırılır; DB gerekmez.
# ==============================================================================

testthat::test_that("Kayıtlı Söyleşiler araması hata vermeden başlıkta süzer ve ilk sayfaya döner", {
  testthat::skip_if_not_installed("shiny")
  paketler <- new.env(parent = globalenv())
  list2env(mget(getNamespaceExports("shiny"), envir = asNamespace("shiny"), inherits = TRUE), envir = paketler)
  env <- new.env(parent = paketler)
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  source(file.path(resolve_repo_root_for_tests(), "R", "module_saved_chats.R"), encoding = "UTF-8", local = env)
  zaman <- as.POSIXct("2026-07-01 10:00:00", tz = "UTC")
  sohbetler <- list(
    "1" = list(title = "Bütçe raporu çğış", timestamp = zaman, last_message_timestamp = zaman, message_count = 2L),
    "2" = list(title = "Toplantı notları", timestamp = zaman + 60, last_message_timestamp = zaman + 60, message_count = 1L)
  )
  shiny::testServer(env$savedChatsServer, args = list(saved_chats = shiny::reactive(sohbetler)), {
    session$flushReact()
    testthat::expect_identical(nrow(filtered_saved_chats()), 2L)
    session$setInputs(search_chats = "bütçe")
    testthat::expect_identical(nrow(filtered_saved_chats()), 1L)
    testthat::expect_match(filtered_saved_chats()$title, "Bütçe", fixed = TRUE)
    testthat::expect_identical(current_page(), 1)
    session$setInputs(search_chats = "")
    testthat::expect_identical(nrow(filtered_saved_chats()), 2L)
  })
})
