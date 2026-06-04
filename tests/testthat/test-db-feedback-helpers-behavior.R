# ==============================================================================
# Dosya Yolu: tests/testthat/test-db-feedback-helpers-behavior.R
# Açıklama: R/helpers_db_feedback.R geri bildirim/kullanım kaydı yardımcılarının
#           davranışsal testleri. load_feedback_from_db beğeni/beğenmeme ayrımı,
#           log_ai_usage INSERT yürütmesi ve load_feedback_details_from_db tekil
#           satır/NULL davranışı mock DB ile doğrulanır. Gerçek DB/ağ yoktur.
# ==============================================================================

testthat::local_edition(3)

# helpers_db_feedback.R bare get_connection/dbGetQuery/dbExecute kullanır; izole
# ortama kaynaklayıp DB fonksiyonlarını enjekte ederiz. normalize_db_* yardımcıları
# helper_bootstrap.R tarafından globalenv'e yüklenmiştir (parent zincirinden).
.fbh_make_env <- function() {
  env <- new.env(parent = globalenv())
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_db_feedback.R"),
    encoding = "UTF-8", local = env
  )
  env$get_connection <- function(...) list(conn = "FAKE")
  env$release_connection <- function(...) invisible(NULL)
  env
}

# -----------------------------------------------------------------------------
# load_feedback_from_db
# -----------------------------------------------------------------------------

test_that("load_feedback_from_db beğeni/beğenmeme mesaj kimliklerini ayırır", {
  env <- .fbh_make_env()
  yakalanan <- new.env()
  env$dbGetQuery <- function(conn, statement, ...) {
    yakalanan$q <- statement
    data.frame(MessageID = c(10, 11, 12), FeedbackType = c("like", "dislike", "like"),
               stringsAsFactors = FALSE)
  }

  r <- env$load_feedback_from_db(7)
  expect_identical(r$liked, c("10", "12"))
  expect_identical(r$disliked, c("11"))
  # Doğru tabloya UserID parametreli sorgu yapılır.
  expect_true(grepl("MB_Feedback", yakalanan$q, fixed = TRUE))
  expect_true(grepl("UserID = ?", yakalanan$q, fixed = TRUE))
})

test_that("load_feedback_from_db boş sonuçta boş liked/disliked vektörleri döner", {
  env <- .fbh_make_env()
  env$dbGetQuery <- function(conn, statement, ...) {
    data.frame(MessageID = integer(0), FeedbackType = character(0), stringsAsFactors = FALSE)
  }
  r <- env$load_feedback_from_db(7)
  expect_identical(r$liked, character(0))
  expect_identical(r$disliked, character(0))
})

# -----------------------------------------------------------------------------
# log_ai_usage
# -----------------------------------------------------------------------------

test_that("log_ai_usage MB_Usage_Log tablosuna INSERT yürütür", {
  env <- .fbh_make_env()
  yakalanan <- new.env()
  env$dbExecute <- function(conn, statement, params = NULL, ...) {
    yakalanan$q <- statement
    yakalanan$p <- params
    1L
  }

  sonuc <- env$log_ai_usage(chat_id = 1, message_id = 2, user_id = 3,
                            model_used = "model-x", duration = 4.5, success = TRUE)
  expect_equal(sonuc, 1L)
  expect_true(grepl("INSERT INTO MB_Usage_Log", yakalanan$q, fixed = TRUE))
  # Altı parametre bağlanır (ChatID..ResponseSuccess).
  expect_equal(length(yakalanan$p), 6L)
})

# -----------------------------------------------------------------------------
# load_feedback_details_from_db
# -----------------------------------------------------------------------------

test_that("load_feedback_details_from_db tek satırı liste olarak döner", {
  env <- .fbh_make_env()
  env$dbGetQuery <- function(conn, statement, ...) {
    data.frame(FeedbackType = "like", FeedbackTags = "iyi",
               FeedbackComment = "harika", FeedbackTimestamp = "2026-01-01",
               stringsAsFactors = FALSE)
  }
  d <- env$load_feedback_details_from_db(7, 10)
  expect_true(is.list(d))
  expect_identical(d$FeedbackType, "like")
  expect_identical(d$FeedbackComment, "harika")
})

test_that("load_feedback_details_from_db sonuç yoksa NULL döner", {
  env <- .fbh_make_env()
  env$dbGetQuery <- function(conn, statement, ...) data.frame()
  expect_null(env$load_feedback_details_from_db(7, 10))
})
