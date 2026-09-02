# ==============================================================================
# Dosya Yolu: tests/testthat/test-ai-expert-db-fetch-behavior.R
# Açıklama: AI Uzman veritabanı okuma yardımcılarının davranışını DBI taklit
#           ederek doğrular: fetch_user_last_login, fetch_recent_user_prompts,
#           fetch_user_work_context, fetch_user_full_name. Bu okuyucular
#           R/helpers_ai_expert_user_data.R dosyasında yaşar. Gerçek DB/ağ yok;
#           get_connection ve DBI::dbGetQuery taklit edilir.
# ==============================================================================

repo_root_aix <- resolve_repo_root_for_tests()

.aix_env <- new.env(parent = globalenv())
.aix_env$`%||%` <- function(a, b) if (is.null(a)) b else a
for (.fn in c("log_info", "log_warn", "log_error", "log_debug")) {
  .aix_env[[.fn]] <- function(...) invisible(NULL)
}
# DB bağlantı stub'ları (sorgu içeriğine göre yanıt veren mock dbGetQuery ile çalışır)
.aix_env$get_connection <- function() list(conn = "fake-conn")
.aix_env$release_connection <- function(...) invisible(NULL)
suppressWarnings(source(
  file.path(repo_root_aix, "R/helpers_ai_expert_user_data.R"),
  encoding = "UTF-8", local = .aix_env
))

test_that("fetch_user_last_login: satır varsa POSIXct, yoksa NULL döner", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      data.frame(LastLoginDate = "2026-06-01 09:30:00", stringsAsFactors = FALSE)
    },
    .package = "DBI"
  )
  res <- .aix_env$fetch_user_last_login(7L)
  expect_s3_class(res, "POSIXct")
  expect_equal(format(res, "%Y-%m-%d"), "2026-06-01")
})

test_that("fetch_user_last_login: boş sonuç NULL", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) data.frame(),
    .package = "DBI"
  )
  expect_null(.aix_env$fetch_user_last_login(7L))
})

test_that("fetch_user_last_login: DB hatası NULL'a güvenli düşer", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) stop("baglanti koptu"),
    .package = "DBI"
  )
  expect_null(.aix_env$fetch_user_last_login(7L))
})

test_that("fetch_recent_user_prompts: mesajları döndürür, yoksa NULL", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      data.frame(MessageContent = c("ilk soru", "ikinci soru"), stringsAsFactors = FALSE)
    },
    .package = "DBI"
  )
  res <- .aix_env$fetch_recent_user_prompts(7L, max_prompts = 5)
  expect_true(is.character(res))
  expect_length(res, 2L)
  expect_true("ilk soru" %in% res)

  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) data.frame(),
    .package = "DBI"
  )
  expect_null(.aix_env$fetch_recent_user_prompts(7L))
})

test_that("fetch_user_work_context: departman+müdürlük birleştirme", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      data.frame(Departman = "Fiyatlandırma", Mudurluk = "Proje Müdürlüğü", stringsAsFactors = FALSE)
    },
    .package = "DBI"
  )
  ctx <- .aix_env$fetch_user_work_context(7L)
  expect_identical(ctx$department, "Fiyatlandırma")
  expect_identical(ctx$mudurluk, "Proje Müdürlüğü")
  expect_identical(ctx$effective_unit, "Fiyatlandırma")  # departman varsa o
  expect_identical(ctx$display_text, "Fiyatlandırma (Proje Müdürlüğü)")
})

test_that("fetch_user_work_context: yalnız müdürlük varsa effective_unit müdürlük olur", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      data.frame(Departman = NA_character_, Mudurluk = "Bilgi Teknolojileri", stringsAsFactors = FALSE)
    },
    .package = "DBI"
  )
  ctx <- .aix_env$fetch_user_work_context(7L)
  expect_identical(ctx$department, "")
  expect_identical(ctx$effective_unit, "Bilgi Teknolojileri")
  expect_identical(ctx$display_text, "Bilgi Teknolojileri")
})

test_that("fetch_user_work_context: bağlantı yoksa boş bağlam döner", {
  old_get <- .aix_env$get_connection
  .aix_env$get_connection <- function() stop("no db")
  withr::defer(.aix_env$get_connection <- old_get)
  ctx <- .aix_env$fetch_user_work_context(7L)
  expect_identical(ctx$department, "")
  expect_identical(ctx$display_text, "")
})

# ------------------------------------------------------------------------------
# Okuma sınırı sözleşmesi: kullanıcıya görünen DB alanları kanonik profil
# okuyucusuyla aynı görünür-değer normalizasyonundan geçmelidir.
# ------------------------------------------------------------------------------

.aix_env_with_read_boundary <- function() {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  for (.fn in c("log_info", "log_warn", "log_error", "log_debug")) {
    env[[.fn]] <- function(...) invisible(NULL)
  }
  env$get_connection <- function() list(conn = "fake-conn")
  env$release_connection <- function(...) invisible(NULL)

  # Gerçek okuma sınırı yardımcıları: token geri açma + mojibake onarımı.
  suppressWarnings(source(
    file.path(repo_root_aix, "R/utils_text_encoding.R"),
    encoding = "UTF-8", local = env
  ))
  suppressWarnings(source(
    file.path(repo_root_aix, "R/helpers_db_unicode_escape.R"),
    encoding = "UTF-8", local = env
  ))
  suppressWarnings(source(
    file.path(repo_root_aix, "R/helpers_ai_expert_user_data.R"),
    encoding = "UTF-8", local = env
  ))

  env
}

test_that("fetch_user_full_name: eski mojibake ad okuma sinirinda onarilir", {
  env <- .aix_env_with_read_boundary()

  # Deterministik bayt-kurulumlu mojibake: "GÃ¼l" -> "Gül"
  mojibake_ad <- paste0("G", intToUtf8(c(0xC3L, 0xBCL)), "l Yilmaz")

  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      data.frame(KaynakAdi = mojibake_ad, stringsAsFactors = FALSE)
    },
    .package = "DBI"
  )

  ad <- env$fetch_user_full_name(7L)
  expect_identical(
    ad,
    "Gül Yilmaz",
    info = "KaynakAdi, TTS/altyazı metnine sızmadan önce onarılmalıdır."
  )
})

test_that("fetch_user_work_context: birim adlarinda kacis tokenlari geri acilir", {
  env <- .aix_env_with_read_boundary()

  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      data.frame(
        Departman = "Strateji [[MERGEN-U+2728]] Birimi",
        Mudurluk = NA_character_,
        stringsAsFactors = FALSE
      )
    },
    .package = "DBI"
  )

  ctx <- env$fetch_user_work_context(7L)
  expect_false(
    grepl("[[MERGEN-U+", ctx$department, fixed = TRUE),
    info = "Departman alanında ham kaçış token'ı görünmemelidir."
  )
  expect_true(
    grepl(intToUtf8(0x2728L), ctx$department, fixed = TRUE),
    info = "Token orijinal karaktere geri açılmalıdır."
  )
})
