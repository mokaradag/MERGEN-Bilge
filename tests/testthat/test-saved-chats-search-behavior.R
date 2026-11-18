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
  # 40 eşleşen ek söyleşi: arama sonrası da ikinci sayfa geçerli kalır; böylece
  # sayfa kırpma gözlemcisi eksik bir arama sıfırlamasını maskeleyemez.
  for (i in seq_len(40L)) {
    sohbetler[[as.character(100L + i)]] <- list(title = sprintf("Bütçe ek %02d", i), timestamp = zaman - i,
                                                last_message_timestamp = zaman - i, message_count = 1L)
  }
  shiny::testServer(env$savedChatsServer, args = list(saved_chats = shiny::reactive(sohbetler)), {
    session$flushReact()
    testthat::expect_identical(nrow(filtered_saved_chats()), 42L)
    session$setInputs(next_page = 1)
    testthat::expect_identical(current_page(), 2)
    session$setInputs(search_chats = "bütçe")
    testthat::expect_identical(nrow(filtered_saved_chats()), 41L)
    testthat::expect_true(all(grepl("Bütçe", filtered_saved_chats()$title, fixed = TRUE)))
    testthat::expect_identical(current_page(), 1)
    session$setInputs(search_chats = "")
    testthat::expect_identical(nrow(filtered_saved_chats()), 42L)
  })
})

testthat::test_that("tek söyleşideki yeni mesaj tüm listenin zaman damgalarını yeniden ayrıştırmaz", {
  testthat::skip_if_not_installed("shiny")
  paketler <- new.env(parent = globalenv())
  list2env(mget(getNamespaceExports("shiny"), envir = asNamespace("shiny"), inherits = TRUE), envir = paketler)
  env <- new.env(parent = paketler)
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  # Ayrıştırma sayacı: modülün metin damgası ayrıştırması bu sarmalayıcıdan geçer.
  sayac <- new.env(parent = emptyenv())
  sayac$n <- 0L
  env$as.POSIXct <- function(x, ...) {
    if (is.character(x)) sayac$n <- sayac$n + 1L
    base::as.POSIXct(x, ...)
  }
  source(file.path(resolve_repo_root_for_tests(), "R", "module_saved_chats.R"), encoding = "UTF-8", local = env)
  sohbetler <- lapply(seq_len(200L), function(i) {
    list(title = sprintf("Söyleşi %03d", i), last_message_timestamp = sprintf("2026-07-01 10:%02d:00", i %% 60L),
         message_count = 1L)
  })
  names(sohbetler) <- as.character(seq_len(200L))
  kaynak <- shiny::reactiveVal(sohbetler)
  shiny::testServer(env$savedChatsServer, args = list(saved_chats = kaynak), {
    session$flushReact()
    testthat::expect_identical(nrow(cached_meta()), 200L)
    ilk <- sayac$n
    testthat::expect_gte(ilk, 200L)
    # Söyleşi 7'ye yeni mesaj: yalnızca onun damgası ayrıştırılır ve sıra güncellenir.
    guncel <- sohbetler
    guncel[["7"]]$last_message_timestamp <- "2026-07-02 09:00:00"
    guncel[["7"]]$message_count <- 2L
    kaynak(guncel)
    session$flushReact()
    testthat::expect_identical(sayac$n - ilk, 1L)
    testthat::expect_identical(cached_meta()$chat_id[[1]], "7")
    testthat::expect_identical(cached_meta()$message_count[[1]], 2L)
  })
})
