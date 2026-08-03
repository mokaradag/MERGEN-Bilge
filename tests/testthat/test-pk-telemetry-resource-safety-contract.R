# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-telemetry-resource-safety-contract.R
# Açıklama: Telemetri kaynak güvenliği sözleşmeleri: DB hatasında yeniden
#           bağlanmama, gözlem deposunun sızdırmaması ve köken alt bilgisinin
#           Ortak Oturum motorunda tek kez eklenmesi.
# ==============================================================================

.pk_fix_test_env <- function() {
  env <- new.env(parent = baseenv())
  env$`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
  # environment(f) <- env yapılan sahte fonksiyonların gövdesinde env$... okunur.
  # Arama zinciri env -> baseenv() olduğundan env kendini görebilmelidir.
  env$env <- env
  env
}

.source_pk_fix_layer <- function(env) {
  repo_root <- resolve_repo_root_for_tests()
  sys.source(
    file.path(repo_root, "R", "server_chat_engine_dependencies.R"),
    envir = env,
    keep.source = FALSE
  )
  sys.source(
    file.path(repo_root, "R", "server_init_session_state.R"),
    envir = env,
    keep.source = FALSE
  )
  sys.source(
    file.path(repo_root, "R", "server_init_chat_runtime.R"),
    envir = env,
    keep.source = FALSE
  )
  invisible(env)
}

test_that("abandoned filter observations are cleared by request scope", {
  env <- .pk_fix_test_env()
  env$.pk_filter_observation_state <- new.env(parent = emptyenv())
  .source_pk_fix_layer(env)

  key_1 <- paste("req-1", "q1", "Query 1", "same question", sep = "\u001f")
  key_2 <- paste("req-1", "q2", "Query 2", "same question", sep = "\u001f")
  key_3 <- paste("req-2", "q3", "Query 3", "other question", sep = "\u001f")
  assign(key_1, list(secret = "a"), envir = env$.pk_filter_observation_state)
  assign(key_2, list(secret = "b"), envir = env$.pk_filter_observation_state)
  assign(key_3, list(secret = "c"), envir = env$.pk_filter_observation_state)

  expect_true(env$pk_filter_observation_clear("req-1", "same question"))
  expect_false(exists(key_1, envir = env$.pk_filter_observation_state, inherits = FALSE))
  expect_false(exists(key_2, envir = env$.pk_filter_observation_state, inherits = FALSE))
  expect_true(exists(key_3, envir = env$.pk_filter_observation_state, inherits = FALSE))
})

test_that("single-analysis DB failures do not reconnect for telemetry", {
  env <- .pk_fix_test_env()
  env$connection_calls <- 0L
  env$observed_conn <- "not-called"
  env$.pk_filter_observation_state <- new.env(parent = emptyenv())

  core <- function(user_prompt, chat_history, session, stop_check = NULL) {
    "\U000026A0\U0000FE0F **Veritabanı Hatası:** SQLSTATE 08001"
  }
  environment(core) <- env
  env$pk_analiz_process_request <- core
  env$pk_provenance_current_request_id <- function(session) "req-db"
  env$get_connection <- function() {
    env$connection_calls <- env$connection_calls + 1L
    stop("telemetry must not reconnect")
  }
  env$release_connection <- function(conn_list) invisible(NULL)
  env$pk_analysis_observe <- function(session, conn, info) {
    env$observed_conn <- conn
    session$userData$pk_provenance_pending <- list(footer = "footer")
    invisible("footer")
  }

  key <- paste("req-db", "q1", "Query", "db question", sep = "\u001f")
  assign(key, list(raw = "sensitive"), envir = env$.pk_filter_observation_state)
  .source_pk_fix_layer(env)

  session <- list(userData = new.env(parent = emptyenv()))
  session$userData$auth_initialized <- TRUE
  session$userData$system_username <- "tester"

  result <- env$pk_analiz_process_request("db question", list(), session)

  expect_match(result, "Veritabanı Hatası", fixed = TRUE)
  expect_equal(env$connection_calls, 0L)
  expect_null(env$observed_conn)
  expect_false(exists(key, envir = env$.pk_filter_observation_state, inherits = FALSE))
  expect_false(is.null(session$userData$pk_provenance_pending))
})

test_that("deep analysis releases RLS connection before short-lived telemetry", {
  env <- .pk_fix_test_env()
  env$events <- character(0)
  env$connection_number <- 0L
  env$.pk_filter_observation_state <- new.env(parent = emptyenv())

  env$get_connection <- function() {
    env$connection_number <- env$connection_number + 1L
    conn <- paste0("conn-", env$connection_number)
    env$events <- c(env$events, paste0("get:", conn))
    list(conn = conn)
  }
  env$release_connection <- function(conn_list) {
    env$events <- c(env$events, paste0("release:", conn_list$conn))
    invisible(NULL)
  }
  env$get_user_rls_info <- function(username, conn) {
    env$events <- c(env$events, paste0("rls:", conn))
    list(authorized = TRUE)
  }
  env$pk_analysis_observe <- function(session, conn, info) {
    env$events <- c(env$events, paste0("observe:", conn))
    invisible("footer")
  }
  env$pk_provenance_current_request_id <- function(session) "req-deep"

  core <- function(user_prompt, chat_history, session,
                   detail_level = "standart", stop_check = NULL) {
    conn_list <- get_connection()
    conn <- conn_list$conn
    on.exit(release_connection(conn_list), add = TRUE)
    get_user_rls_info(session$userData$system_username, conn)
    pk_analysis_observe(session, conn, list(filter_status = "not_reached"))
    "ok"
  }
  environment(core) <- env
  env$pk_deep_analysis_process <- core

  .source_pk_fix_layer(env)

  session <- list(userData = new.env(parent = emptyenv()))
  session$userData$system_username <- "tester"
  result <- env$pk_deep_analysis_process("deep question", list(), session)

  expect_equal(result, "ok")
  expect_equal(
    env$events,
    c(
      "get:conn-1",
      "rls:conn-1",
      "release:conn-1",
      "get:conn-2",
      "observe:conn-2",
      "release:conn-2"
    )
  )
})

test_that("shared-room SQL provenance reaches direct and generated answers", {
  env <- .pk_fix_test_env()
  env$captured <- list()
  env$bridge_results <- list()

  env$pk_provenance_take <- function(session, request_id = NULL) {
    pending <- session$userData$pk_provenance_pending
    session$userData$pk_provenance_pending <- NULL
    if (is.list(pending)) pending$footer else pending
  }

  bridge <- function(soru, gecmis, oda_session, arac_meta) {
    footer <- paste0("\n\n---\n**Analiz Kaynağı**\n- **Sorgu:** ", soru, "\n")
    oda_session$userData$pk_provenance_pending <- list(footer = footer)
    if (identical(soru, "direct")) {
      list(dogrudan_yanit = "direct answer")
    } else {
      list(prompt_context = "system", user_context = "user")
    }
  }
  environment(bridge) <- env
  env$oo_arac_sql_baglami_kur <- bridge

  bind <- function(input, output, session, ctx, motor) {
    motor$tamamla <- function(oturum_id, soru_id, istek_id,
                             yanit_metni = NULL, hata_metni = NULL,
                             kuyruk_id = NULL, soran_id = NULL,
                             persona_id = NULL) {
      env$captured[[istek_id]] <- list(answer = yanit_metni, error = hata_metni)
      invisible(NULL)
    }

    motor$llm_uret <- function(oturum_id, soru_id, soran_id, istek_id,
                              kuyruk_id = NULL, persona_kimligi = NULL) {
      room_session <- list(userData = new.env(parent = emptyenv()))
      question <- if (identical(as.integer(soru_id), 1L)) "direct" else "generated"
      sql_result <- oo_arac_sql_baglami_kur(question, list(), room_session, list())
      env$bridge_results[[istek_id]] <- sql_result

      if (!is.null(sql_result$dogrudan_yanit)) {
        motor$tamamla(
          oturum_id, soru_id, istek_id,
          yanit_metni = sql_result$dogrudan_yanit,
          soran_id = soran_id
        )
      } else {
        motor$tamamla(
          oturum_id, soru_id, istek_id,
          yanit_metni = "generated answer",
          soran_id = soran_id
        )
      }
      invisible(NULL)
    }
    invisible(TRUE)
  }
  environment(bind) <- env
  env$ortakOturumYzBind <- bind

  .source_pk_fix_layer(env)

  motor <- new.env(parent = emptyenv())
  env$ortakOturumYzBind(NULL, NULL, NULL, NULL, motor)
  motor$llm_uret(10L, 1L, 7L, "req-direct")
  motor$llm_uret(10L, 2L, 7L, "req-generated")

  expect_match(env$captured[["req-direct"]]$answer, "Analiz Kaynağı", fixed = TRUE)
  expect_match(env$captured[["req-generated"]]$answer, "Analiz Kaynağı", fixed = TRUE)
  expect_match(
    env$bridge_results[["req-direct"]]$provenance_footer,
    "Analiz Kaynağı",
    fixed = TRUE
  )
  expect_match(
    env$bridge_results[["req-generated"]]$provenance_footer,
    "Analiz Kaynağı",
    fixed = TRUE
  )
})

test_that("veritabanı kaynaklı olmayan istisnalar telemetri için bağlantı açar", {
  env <- .pk_fix_test_env()
  env$connection_calls <- 0L
  env$observed_conn <- "not-called"
  env$observed_outcome <- NULL
  env$.pk_filter_observation_state <- new.env(parent = emptyenv())

  # DB ile ilgisi olmayan bir uygulama hatası (ör. ayrıştırma / sorgu seçimi).
  core <- function(user_prompt, chat_history, session, stop_check = NULL) {
    stop("beklenmeyen ayrıştırma hatası")
  }
  environment(core) <- env
  env$pk_analiz_process_request <- core
  env$pk_provenance_current_request_id <- function(session) "req-app-error"
  env$get_connection <- function() {
    env$connection_calls <- env$connection_calls + 1L
    list(conn = paste0("conn-", env$connection_calls))
  }
  env$release_connection <- function(conn_list) invisible(NULL)
  env$pk_analysis_observe <- function(session, conn, info) {
    env$observed_conn <- conn
    env$observed_outcome <- info$outcome
    session$userData$pk_provenance_pending <- list(footer = "footer")
    invisible("footer")
  }

  .source_pk_fix_layer(env)

  session <- list(userData = new.env(parent = emptyenv()))
  session$userData$auth_initialized <- TRUE
  session$userData$system_username <- "tester"

  expect_error(
    env$pk_analiz_process_request("soru", list(), session),
    "beklenmeyen ayrıştırma hatası"
  )

  # Yeniden bağlanmama yolu yalnızca gerçek DB hatalarına ayrılmıştır; aksi
  # halde conn = NULL ile gözlem yapılır ve MB_Analiz_Log yazımı atlanırdı.
  expect_equal(env$connection_calls, 1L)
  expect_equal(env$observed_conn, "conn-1")
  expect_identical(env$observed_outcome, "Hata")
})

test_that("veritabanı istisnaları hâlâ yeniden bağlanmaz", {
  env <- .pk_fix_test_env()
  env$connection_calls <- 0L
  env$observed_conn <- "not-called"
  env$.pk_filter_observation_state <- new.env(parent = emptyenv())

  core <- function(user_prompt, chat_history, session, stop_check = NULL) {
    stop("nanodbc/nanodbc.cpp:1021: 08001: Login timeout expired")
  }
  environment(core) <- env
  env$pk_analiz_process_request <- core
  env$pk_provenance_current_request_id <- function(session) "req-db-exc"
  env$get_connection <- function() {
    env$connection_calls <- env$connection_calls + 1L
    stop("telemetry must not reconnect")
  }
  env$release_connection <- function(conn_list) invisible(NULL)
  env$pk_analysis_observe <- function(session, conn, info) {
    env$observed_conn <- conn
    session$userData$pk_provenance_pending <- list(footer = "footer")
    invisible("footer")
  }

  .source_pk_fix_layer(env)

  session <- list(userData = new.env(parent = emptyenv()))
  session$userData$auth_initialized <- TRUE
  session$userData$system_username <- "tester"

  expect_error(
    env$pk_analiz_process_request("soru", list(), session),
    "Login timeout expired"
  )
  expect_equal(env$connection_calls, 0L)
  expect_null(env$observed_conn)
})

test_that("istisna sınıflandırması yalnızca DB desenlerine dayanır", {
  env <- .pk_fix_test_env()
  env$.pk_filter_observation_state <- new.env(parent = emptyenv())
  .source_pk_fix_layer(env)

  classify <- env$.pk_hook_database_failure_text

  expect_false(classify("beklenmeyen ayrıştırma hatası", is_exception = TRUE))
  expect_false(classify("object 'x' not found", is_exception = TRUE))
  expect_true(classify("nanodbc: Login failed", is_exception = TRUE))
  expect_true(classify("08S01 baglanti koptu", is_exception = TRUE))
  expect_true(classify("Error in dbGetQuery(...)", is_exception = TRUE))
  expect_true(classify("**Veritabanı Hatası:** SQLSTATE 08001"))
  expect_false(classify("normal bir yanit metni"))
  expect_false(classify(NULL))
})
