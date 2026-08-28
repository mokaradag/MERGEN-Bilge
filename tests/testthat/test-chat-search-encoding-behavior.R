# ==============================================================================
# Dosya Yolu: tests/testthat/test-chat-search-encoding-behavior.R
# Açıklama: Söyleşi içerik aramasının (module_chat_search.R) DB kodlama sınırı
#           davranış sözleşmesi.
#           - Yazım/bağlama sınırı: kullanıcı arama terimi LIKE parametresine
#             bağlanmadan önce görünür-değer kodlama yolundan geçer; joker
#             karakterler normalizasyondan SONRA eklenir.
#           - Okuma sınırı: sonuç satırları kullanıcıya dönmeden önce
#             [[MERGEN-U+...]] kaçış token'ları geri açılır ve eski mojibake
#             onarılır.
#           Gerçek DB/ağ yok; get_connection ve DBI::dbGetQuery taklit edilir.
# ==============================================================================

repo_root_cs <- resolve_repo_root_for_tests()

.cs_make_env <- function() {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  for (.fn in c("log_info", "log_warn", "log_error", "log_debug")) {
    env[[.fn]] <- function(...) invisible(NULL)
  }
  env$get_connection <- function() list(conn = "fake-conn")
  env$release_connection <- function(...) invisible(NULL)

  # Okuma sınırı için GERÇEK yardımcılar yüklenir: token geri açma davranışı
  # modül üzerinden uçtan uca kanıtlanır.
  suppressWarnings(source(
    file.path(repo_root_cs, "R/utils_text_encoding.R"),
    encoding = "UTF-8", local = env
  ))
  suppressWarnings(source(
    file.path(repo_root_cs, "R/helpers_db_unicode_escape.R"),
    encoding = "UTF-8", local = env
  ))
  suppressWarnings(source(
    file.path(repo_root_cs, "R/module_chat_search.R"),
    encoding = "UTF-8", local = env
  ))

  env
}

test_that("arama terimi LIKE baglamadan once gorunur-deger sinirindan gecer", {
  env <- .cs_make_env()

  # Bağlama sınırı sözleşmesi: modül terimi normalize_db_visible_value'dan
  # geçirmelidir. İç dönüşüm ayrıntısı değil, sınırdan geçiş test edilir.
  env$normalize_db_visible_value <- function(x) paste0("NDV(", x, ")")

  captured_params <- NULL

  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, params = NULL, ...) {
      captured_params <<- params
      data.frame()
    },
    .package = "DBI"
  )

  sonuc <- env$search_chats_content_from_db(7L, "Türkiye")

  expect_true(is.data.frame(sonuc))
  expect_identical(nrow(sonuc), 0L)
  expect_identical(
    captured_params[[2]],
    "%NDV(Türkiye)%",
    info = "Joker karakterler normalizasyondan SONRA eklenmeli, terim sınırdan geçmelidir."
  )
})

test_that("sonuc satirlari okuma sinirindan gecer: token geri acilir, mojibake onarilir", {
  env <- .cs_make_env()

  # Bağlama tarafını nötrle: bu test okuma sınırına odaklanır.
  env$normalize_db_visible_value <- function(x) x

  roket <- intToUtf8(0x1F680L)
  token_iceren <- "Analiz tamam [[MERGEN-U+1F680]] sonuc hazir"
  # Deterministik bayt-kurulumlu mojibake: "TÃ¼rkiye" -> "Türkiye"
  mojibake_baslik <- paste0("T", intToUtf8(c(0xC3L, 0xBCL)), "rkiye raporu")

  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, params = NULL, ...) {
      data.frame(
        ChatID = 11L,
        ChatTitle = mojibake_baslik,
        MessageContent = token_iceren,
        MessageType = "ai",
        MessageTimestamp = "2026-06-11 09:00:00",
        stringsAsFactors = FALSE
      )
    },
    .package = "DBI"
  )

  sonuc <- env$search_chats_content_from_db(7L, "rapor")

  expect_identical(nrow(sonuc), 1L)
  expect_false(
    grepl("[[MERGEN-U+", sonuc$message_content[1], fixed = TRUE),
    info = "Kaçış token'ları arama sonucunda ham olarak görünmemelidir."
  )
  expect_true(
    grepl(roket, sonuc$message_content[1], fixed = TRUE),
    info = "Token, orijinal karaktere geri açılmalıdır."
  )
  expect_true(
    grepl("Türkiye", sonuc$chat_title[1], fixed = TRUE),
    info = "Eski mojibake başlık görüntü için onarılmalıdır."
  )
})

test_that("bos arama terimi DB cagrisi yapmadan bos cerceve dondurur", {
  env <- .cs_make_env()

  db_called <- FALSE

  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, params = NULL, ...) {
      db_called <<- TRUE
      data.frame()
    },
    .package = "DBI"
  )

  sonuc_bos <- env$search_chats_content_from_db(7L, "   ")
  sonuc_null <- env$search_chats_content_from_db(7L, NULL)

  expect_identical(nrow(sonuc_bos), 0L)
  expect_identical(nrow(sonuc_null), 0L)
  expect_false(db_called, info = "Boş terim DB sorgusu tetiklememelidir.")
})

test_that("DB hatasi guvenli bos cerceveye duser", {
  env <- .cs_make_env()
  env$normalize_db_visible_value <- function(x) x

  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, params = NULL, ...) stop("baglanti koptu"),
    .package = "DBI"
  )

  expect_warning(
    sonuc <- env$search_chats_content_from_db(7L, "deneme"),
    regexp = "CHAT_SEARCH"
  )
  expect_true(is.data.frame(sonuc))
  expect_identical(nrow(sonuc), 0L)
})
