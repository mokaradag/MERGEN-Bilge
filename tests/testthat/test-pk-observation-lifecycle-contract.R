# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-observation-lifecycle-contract.R
# Açıklama: Filtre gözlemi yaşam döngüsü sözleşmeleri: istek kapsamlı anahtar,
#           terk edilen gözlemlerin temizlenmesi ve tek seferlik tüketim.
# ==============================================================================

.pk_final_repo_root_path <- resolve_repo_root_for_tests()
.pk_final_repo_root <- function() .pk_final_repo_root_path

.pk_final_source_env <- function(files) {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a

  for (rel in files) {
    source(
      file.path(.pk_final_repo_root(), rel),
      encoding = "UTF-8",
      local = env
    )
  }

  env
}

test_that("split PK helpers source correctly outside the repository working directory", {
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(tempdir())

  filter_env <- .pk_final_source_env(c(
    "R/helpers_pk_analysis_core.R",
    "R/helpers_pk_analysis_filters.R"
  ))
  expect_true(exists("extract_filter_criteria_from_prompt", envir = filter_env, inherits = FALSE))
  expect_true(exists("apply_smart_filters", envir = filter_env, inherits = FALSE))

  telemetry_env <- .pk_final_source_env(c(
    "R/helpers_pk_config.R",
    "R/helpers_pk_provenance.R",
    "R/helpers_pk_telemetry_record.R",
    "R/helpers_pk_telemetry.R"
  ))
  expect_true(exists("pk_telemetry_log_analysis", envir = telemetry_env, inherits = FALSE))
  expect_true(exists("pk_analysis_observe", envir = telemetry_env, inherits = FALSE))
})

test_that("stateful filter expressions execute exactly once", {
  env <- .pk_final_source_env(c(
    "R/helpers_pk_analysis_core.R",
    "R/helpers_pk_analysis_filters.R"
  ))

  env$counter <- 0L
  result <- env$apply_smart_filters(
    data.frame(x = 1:4),
    list(
      filters = list(),
      filter_expression = "{counter <<- counter + 1L; x > 1}",
      aggregation = NULL,
      group_column = NULL
    ),
    "x birden büyük"
  )

  expect_identical(env$counter, 1L)
  expect_identical(nrow(result), 3L)

  observation <- env$pk_filter_observation_take(list(
    request_id = NULL,
    query_id = NULL,
    query_name = NULL,
    question = "x birden büyük"
  ))
  expect_identical(observation$matched_rows, 3L)
  expect_identical(observation$applied_filters[[1]]$operation, "expression")
})

test_that("pk_analysis_observe fills KullaniciID from the authenticated session", {
  env <- .pk_final_source_env(c(
    "R/helpers_pk_config.R",
    "R/helpers_pk_provenance.R",
    "R/helpers_pk_telemetry_record.R",
    "R/helpers_pk_telemetry.R"
  ))

  captured <- new.env(parent = emptyenv())
  env$pk_telemetry_log_analysis <- function(info, conn) {
    captured$info <- info
    invisible(TRUE)
  }
  env$pk_provenance_stash <- function(...) invisible(TRUE)

  user_data <- new.env(parent = emptyenv())
  user_data$user_id <- 314L
  session <- list(userData = user_data)

  env$pk_analysis_observe(session, NULL, list(
    request_id = "req-user",
    question = "soru",
    username = "test.user",
    query_name = "Test",
    filter_status = "not_reached",
    filters = list(),
    outcome = "Hata"
  ))

  expect_identical(captured$info$user_id, 314L)
})

test_that("direct single-analysis exits receive an observation exactly once", {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a

  env$pk_analiz_process_request <- function(user_prompt, chat_history, session,
                                            stop_check = NULL) {
    "⚠️ **Yetki Hatası:** kullanıcı bulunamadı."
  }

  captured <- new.env(parent = emptyenv())
  captured$count <- 0L
  env$pk_analysis_observe <- function(session, conn, info) {
    captured$count <- captured$count + 1L
    captured$info <- info
    invisible("footer")
  }
  env$pk_provenance_current_request_id <- function(session) "req-exit"
  env$get_connection <- function(...) list(conn = NULL)
  env$release_connection <- function(...) invisible(TRUE)

  source(
    file.path(.pk_final_repo_root(), "R", "server_init_chat_runtime.R"),
    encoding = "UTF-8",
    local = env
  )

  user_data <- new.env(parent = emptyenv())
  user_data$user_id <- 88L
  user_data$system_username <- "test.user"
  session <- list(userData = user_data)

  result <- env$pk_analiz_process_request("soru", list(), session)

  expect_true(grepl("Yetki Hatası", result, fixed = TRUE))
  expect_identical(captured$count, 1L)
  expect_identical(captured$info$user_id, 88L)
  expect_identical(captured$info$outcome, "Yetkisiz")
  expect_identical(captured$info$filter_status, "not_reached")

  user_data$pk_provenance_pending <- list(footer = "already observed")
  env$pk_analiz_process_request("soru", list(), session)
  expect_identical(captured$count, 1L)
})

test_that("unexpected single-analysis exceptions are observed before rethrow", {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  env$pk_analiz_process_request <- function(...) stop("beklenmeyen hata")

  captured <- new.env(parent = emptyenv())
  captured$count <- 0L
  env$pk_analysis_observe <- function(session, conn, info) {
    captured$count <- captured$count + 1L
    captured$info <- info
    invisible("footer")
  }
  env$pk_provenance_current_request_id <- function(session) "req-error"
  env$get_connection <- function(...) list(conn = NULL)
  env$release_connection <- function(...) invisible(TRUE)

  source(
    file.path(.pk_final_repo_root(), "R", "server_init_chat_runtime.R"),
    encoding = "UTF-8",
    local = env
  )

  user_data <- new.env(parent = emptyenv())
  user_data$user_id <- 99L
  user_data$system_username <- "test.user"
  session <- list(userData = user_data)

  expect_error(
    env$pk_analiz_process_request("soru", list(), session),
    "beklenmeyen hata"
  )
  expect_identical(captured$count, 1L)
  expect_identical(captured$info$outcome, "Hata")
  expect_identical(captured$info$filter_status, "not_reached")
})

test_that("pending SSO identity never opens a DB connection for telemetry", {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  env$pk_analiz_process_request <- function(...) {
    "⏳ **Kimlik Doğrulama Hazırlanıyor:** Lütfen tekrar deneyin."
  }

  captured <- new.env(parent = emptyenv())
  captured$db_calls <- 0L
  captured$observe_calls <- 0L
  env$get_connection <- function(...) {
    captured$db_calls <- captured$db_calls + 1L
    list(conn = "unexpected")
  }
  env$release_connection <- function(...) invisible(TRUE)
  env$pk_analysis_observe <- function(...) {
    captured$observe_calls <- captured$observe_calls + 1L
    invisible("")
  }

  source(
    file.path(.pk_final_repo_root(), "R", "server_init_chat_runtime.R"),
    encoding = "UTF-8",
    local = env
  )

  user_data <- new.env(parent = emptyenv())
  user_data$auth_initialized <- FALSE
  session <- list(userData = user_data)

  result <- env$pk_analiz_process_request("soru", list(), session)

  expect_true(grepl("Kimlik Doğrulama Hazırlanıyor", result, fixed = TRUE))
  expect_identical(captured$db_calls, 0L)
  expect_identical(captured$observe_calls, 0L)
})

test_that("stopped filter provenance is rendered as cancelled", {
  env <- .pk_final_source_env("R/helpers_pk_provenance.R")

  footer <- env$pk_build_provenance_footer(list(
    query_name = "Derin analiz",
    filter_status = "stopped",
    filters = list()
  ))

  expect_true(grepl("İptal edildi", footer, fixed = TRUE))
  expect_false(grepl("soru genel olarak yorumlandı", footer, fixed = TRUE))
})

test_that("entry-time deep-analysis cancellation is observed without delegation", {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a

  captured <- new.env(parent = emptyenv())
  captured$delegated <- 0L
  captured$db_calls <- 0L
  captured$release_calls <- 0L
  captured$observe_calls <- 0L

  env$pk_deep_analysis_process <- function(...) {
    captured$delegated <- captured$delegated + 1L
    "asıl motor çağrıldı"
  }
  env$get_connection <- function(...) {
    captured$db_calls <- captured$db_calls + 1L
    list(conn = "test-conn")
  }
  env$release_connection <- function(...) {
    captured$release_calls <- captured$release_calls + 1L
    invisible(TRUE)
  }
  env$pk_provenance_current_request_id <- function(session) "req-deep-stop"
  env$pk_analysis_observe <- function(session, conn, info) {
    captured$observe_calls <- captured$observe_calls + 1L
    captured$conn <- conn
    captured$info <- info
    invisible("footer")
  }

  source(
    file.path(.pk_final_repo_root(), "R", "server_init_chat_runtime.R"),
    encoding = "UTF-8",
    local = env
  )

  user_data <- new.env(parent = emptyenv())
  user_data$auth_initialized <- TRUE
  user_data$user_id <- 271L
  user_data$system_username <- "deep.user"
  session <- list(userData = user_data)

  result <- env$pk_deep_analysis_process(
    "soru",
    list(),
    session,
    stop_check = function() TRUE
  )

  expect_true(grepl("İşlem Durduruldu", result, fixed = TRUE))
  expect_identical(captured$delegated, 0L)
  expect_identical(captured$db_calls, 1L)
  expect_identical(captured$release_calls, 1L)
  expect_identical(captured$observe_calls, 1L)
  expect_identical(captured$conn, "test-conn")
  expect_identical(captured$info$request_id, "req-deep-stop")
  expect_identical(captured$info$user_id, 271L)
  expect_true(isTRUE(captured$info$deep_thinking))
  expect_identical(captured$info$filter_status, "stopped")
  expect_identical(captured$info$outcome, "Durduruldu")
})
