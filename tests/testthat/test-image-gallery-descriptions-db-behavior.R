# ==============================================================================
# Dosya Yolu: tests/testthat/test-image-gallery-descriptions-db-behavior.R
# Açıklama: R/helpers_image_gallery.R load_image_descriptions_for_user()
#           fonksiyonunun davranış testleri. Gerçek SQL Server GEREKMEZ;
#           get_connection/release_connection stub'lanır ve DBI::dbGetQuery
#           sorgu içeriğine göre kontrollü çerçeveler döndürür.
#
#           Sözleşme: her [GÖRSEL:...] mesajı için dosya adı çıkarılır; açıklama
#           olarak ÖNCE bir sonraki AI yanıtı, yoksa inline açıklama kullanılır.
#           Performans sözleşmesi: sonraki AI yanıtı, görsel başına ayrı sorgu
#           (N+1) yerine TEK sorgudaki korelasyonlu SonrakiYanit sütunundan
#           okunur; dbGetQuery tam olarak BİR kez çağrılır.
# ==============================================================================

testthat::local_edition(3)

.source_image_gallery <- function() {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  env$get_connection <- function() list(conn = "FAKE_CONN")
  env$release_connection <- function(...) invisible(NULL)
  env$normalize_db_params <- function(x) x
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_image_gallery.R"),
    encoding = "UTF-8", local = env
  )
  env
}

testthat::test_that("sonraki AI yanıtı varsa açıklama olarak o kullanılır (tek sorgu)", {
  env <- .source_image_gallery()
  sorgu_sayaci <- 0L
  main_rows <- data.frame(
    MessageContent = "[GÖRSEL:/veri/user_images/kedi.png] satır içi açıklama",
    ChatID = 1L,
    MessageOrder = 2L,
    SonrakiYanit = "Bu bir kedi fotoğrafıdır",
    stringsAsFactors = FALSE
  )
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      sorgu_sayaci <<- sorgu_sayaci + 1L
      testthat::expect_true(grepl("INNER JOIN MB_Chats", statement, fixed = TRUE))
      testthat::expect_true(grepl("SonrakiYanit", statement, fixed = TRUE))
      main_rows
    },
    .package = "DBI"
  )

  out <- env$load_image_descriptions_for_user(1L)
  testthat::expect_true("kedi.png" %in% names(out))
  testthat::expect_identical(out[["kedi.png"]], "Bu bir kedi fotoğrafıdır")
  # N+1 koruması: görsel başına ikinci bir sorgu ÇALIŞTIRILMAZ.
  testthat::expect_identical(sorgu_sayaci, 1L)
})

testthat::test_that("sonraki AI yanıtı yoksa satır içi açıklamaya düşer", {
  env <- .source_image_gallery()
  main_rows <- data.frame(
    MessageContent = "[GÖRSEL:/veri/user_images/kopek.png] köpek açıklaması",
    ChatID = 1L,
    MessageOrder = 2L,
    SonrakiYanit = NA_character_,
    stringsAsFactors = FALSE
  )
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) main_rows,
    .package = "DBI"
  )

  out <- env$load_image_descriptions_for_user(1L)
  testthat::expect_identical(out[["kopek.png"]], "köpek açıklaması")
})

testthat::test_that("çok görselde de tek sorgu ile açıklamalar eşlenir", {
  env <- .source_image_gallery()
  sorgu_sayaci <- 0L
  main_rows <- data.frame(
    MessageContent = c(
      "[GÖRSEL:/veri/user_images/istanbul.png] İstanbul görseli",
      "[GÖRSEL:/veri/user_images/ankara.png]"
    ),
    ChatID = c(1L, 2L),
    MessageOrder = c(2L, 4L),
    SonrakiYanit = c(NA_character_, "Ankara için oluşturulan görsel"),
    stringsAsFactors = FALSE
  )
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      sorgu_sayaci <<- sorgu_sayaci + 1L
      main_rows
    },
    .package = "DBI"
  )

  out <- env$load_image_descriptions_for_user(1L)
  testthat::expect_identical(out[["istanbul.png"]], "İstanbul görseli")
  testthat::expect_identical(out[["ankara.png"]], "Ankara için oluşturulan görsel")
  testthat::expect_identical(sorgu_sayaci, 1L)
})

testthat::test_that("görsel mesajı yoksa boş liste döner", {
  env <- .source_image_gallery()
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      data.frame(
        MessageContent = character(0), ChatID = integer(0),
        MessageOrder = integer(0), SonrakiYanit = character(0)
      )
    },
    .package = "DBI"
  )

  out <- env$load_image_descriptions_for_user(1L)
  testthat::expect_type(out, "list")
  testthat::expect_length(out, 0L)
})

testthat::test_that("DB bağlantı hatası güvenle yakalanır ve boş liste döner", {
  env <- .source_image_gallery()
  env$get_connection <- function() stop("bağlantı yok")
  # Hata yolundaki tanılama cat() çıktısını yakalayıp test çıktısını temiz tut.
  invisible(utils::capture.output(
    out <- suppressWarnings(env$load_image_descriptions_for_user(1L))
  ))
  testthat::expect_type(out, "list")
  testthat::expect_length(out, 0L)
})
