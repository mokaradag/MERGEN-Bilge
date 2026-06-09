# ==============================================================================
# Dosya Yolu: tests/testthat/test-image-gallery-helpers-behavior.R
# Açıklama: R/helpers_image_gallery.R görsel galerisi yardımcılarının davranışsal
#           testleri. get_image_thumbnail_base64 (veri-URI), get_chat_title_for_image
#           (koruma + sorgu) ve update_message_after_image_deletion (GÖRSEL etiketi
#           değiştirme) mock DB ile doğrulanır. Gerçek DB yok.
# ==============================================================================

testthat::local_edition(3)

.ig_make_env <- function() {
  env <- new.env(parent = globalenv())
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_image_gallery.R"),
    encoding = "UTF-8", local = env
  )
  env$get_connection <- function(...) list(conn = "FAKE")
  env$release_connection <- function(...) invisible(NULL)
  env
}

# -----------------------------------------------------------------------------
# get_image_thumbnail_base64
# -----------------------------------------------------------------------------

test_that("get_image_thumbnail_base64 var olan dosyayı PNG veri-URI'sine çevirir", {
  env <- .ig_make_env()
  tf <- tempfile(fileext = ".png")
  writeBin(as.raw(c(137, 80, 78, 71, 13, 10)), tf)
  out <- env$get_image_thumbnail_base64(tf)
  expect_true(startsWith(out, "data:image/png;base64,"))
  expect_true(nchar(out) > nchar("data:image/png;base64,"))
})

test_that("get_image_thumbnail_base64 NULL veya olmayan dosyada NULL döner", {
  env <- .ig_make_env()
  expect_null(env$get_image_thumbnail_base64(NULL))
  expect_null(env$get_image_thumbnail_base64(file.path(tempdir(), "yok_olan.png")))
})

# -----------------------------------------------------------------------------
# get_chat_title_for_image
# -----------------------------------------------------------------------------

test_that("get_chat_title_for_image NA/NULL/integer olmayan chat_id'de NULL döner", {
  env <- .ig_make_env()
  expect_null(env$get_chat_title_for_image(NA, 1))
  expect_null(env$get_chat_title_for_image(NULL, 1))
  expect_null(env$get_chat_title_for_image("abc", 1))
})

test_that("get_chat_title_for_image geçerli chat_id'de başlık döner, boşta NULL", {
  env <- .ig_make_env()
  yakalanan <- new.env()
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      yakalanan$q <- statement
      data.frame(ChatTitle = "Söyleşi Başlığı", stringsAsFactors = FALSE)
    },
    .package = "DBI"
  )
  expect_identical(env$get_chat_title_for_image(5, 7), "Söyleşi Başlığı")
  # MB_Chats'e IsDeleted=0 koşuluyla sorgu yapılır.
  expect_true(grepl("MB_Chats", yakalanan$q, fixed = TRUE))
  expect_true(grepl("IsDeleted = 0", yakalanan$q, fixed = TRUE))

  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) data.frame(),
    .package = "DBI"
  )
  expect_null(env$get_chat_title_for_image(5, 7))
})


test_that("load_image_chat_titles_for_user başlıkları tek sorguda haritalar", {
  env <- .ig_make_env()
  yakalanan <- new.env()
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, params = NULL, ...) {
      yakalanan$q <- statement
      yakalanan$p <- params
      data.frame(
        ChatID = c(5L, 8L),
        ChatTitle = c("Görsel Söyleşi", "İkinci Söyleşi"),
        stringsAsFactors = FALSE
      )
    },
    .package = "DBI"
  )

  titles <- env$load_image_chat_titles_for_user(7L)

  expect_identical(titles[["5"]], "Görsel Söyleşi")
  expect_identical(titles[["8"]], "İkinci Söyleşi")
  expect_true(grepl("MB_Chats", yakalanan$q, fixed = TRUE))
  expect_true(grepl("IsDeleted = 0", yakalanan$q, fixed = TRUE))
  expect_identical(yakalanan$p, list(7L))
})

# -----------------------------------------------------------------------------
# update_message_after_image_deletion
# -----------------------------------------------------------------------------

test_that("update_message_after_image_deletion geçersiz chat_id'de DB'ye gitmeden çıkar", {
  env <- .ig_make_env()
  # NA/integer olmayan chat_id koruması: dbGetQuery çağrılırsa testi düşürür.
  cagrildi <- FALSE
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      cagrildi <<- TRUE
      data.frame()
    },
    .package = "DBI"
  )
  expect_null(env$update_message_after_image_deletion("x.png", NA))
  expect_null(env$update_message_after_image_deletion("x.png", "abc"))
  expect_false(cagrildi)
})

test_that("update_message_after_image_deletion GÖRSEL etiketini silinme mesajıyla değiştirip UPDATE eder", {
  env <- .ig_make_env()
  yakalanan <- new.env()
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      data.frame(MessageID = 99, MessageContent = "[GÖRSEL:foo.png] Açıklama metni",
                 stringsAsFactors = FALSE)
    },
    dbExecute = function(conn, statement, params = NULL, ...) {
      yakalanan$q <- statement
      yakalanan$p <- params
      1L
    },
    .package = "DBI"
  )
  invisible(utils::capture.output(env$update_message_after_image_deletion("/path/foo.png", 5)))
  expect_true(grepl("UPDATE MB_Messages", yakalanan$q, fixed = TRUE))
  # Yeni içerik silinme mesajını taşımalı, GÖRSEL etiketini değil.
  expect_true(grepl("silinmi", yakalanan$p[[1]], fixed = TRUE))
  expect_false(grepl("[GÖRSEL:foo.png]", yakalanan$p[[1]], fixed = TRUE))
})

test_that("galeri silme düğmesi submit davranışına düşmez", {
  full_path <- file.path(resolve_repo_root_for_tests(), "R", "module_image_gallery.R")
  size <- file.info(full_path)$size[1]
  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_txt <- readBin(con, what = "raw", n = size)
  module_txt <- iconv(list(raw_txt), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  module_txt <- enc2utf8(module_txt %||% "")

  expect_true(grepl('class = "gallery-delete-btn"', module_txt, fixed = TRUE))
  expect_true(grepl('type = "button"', module_txt, fixed = TRUE))
  expect_false(grepl("decodeURIComponent", module_txt, fixed = TRUE))
})
