# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-p1-runtime-guards.R
# ==============================================================================

test_that("v2 Derin Dusunme kanonik paket ve olgulari kullanir", {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
  env$pk_async_run_analysis <- function(request) list(status = "ok")
  env$pk_engine_is_v2 <- function(meta = NULL) TRUE
  env$.legacy_calls <- 0L
  env$generate_statistical_summary <- function(data, ...) {
    env$.legacy_calls <- env$.legacy_calls + 1L
    list(row_count = nrow(data), summary_text = "LEGACY", preview_data = data)
  }
  env$execute_single_deep_query <- evalq(function(query, user_prompt, session, rls_info,
                                                   detail_config, stop_check = NULL,
                                                   chat_history = NULL) {
    summary <- generate_statistical_summary(data.frame(Proje = c("A", "B"), Tutar = c(10, 20)))
    list(
      success = TRUE,
      row_count = summary$row_count,
      summary_text = summary$summary_text,
      preview_json = "legacy-preview",
      pk_observation = list(
        filters = list(list(column = "Proje", value = "A")),
        filter_status = "ok_filtered",
        authorized_rows = 3L
      )
    )
  }, env)
  env$.pk_result_effective_filters <- function(policy, filter_criteria) filter_criteria$filters
  env$pk_packet_build <- function(data, query, context) {
    list(
      scope = list(grain = query$meta$grain, authorized_rows = context$authorized_rows,
                   filtered_rows = context$filtered_rows),
      aggregation = query$meta$aggregation,
      units = query$meta$units,
      context = context,
      fact_registry = list(list(id = "F1", value = 30, unit = "TRY"))
    )
  }
  env$pk_packet_render <- function(packet) list(text = "KANONIK F1 TRY", mode = "full")
  env$pk_packet_all_facts <- function(packet) packet$fact_registry

  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_pk_p1_runtime_guards.R"),
         encoding = "UTF-8", local = env)

  res <- env$execute_single_deep_query(
    query = list(
      id = "q1", name = "Q1", pre_aggregated_columns = character(0),
      meta = list(grain = "project", aggregation = "sum", units = "TRY")
    ),
    user_prompt = "A projesi", session = NULL, rls_info = list(),
    detail_config = list()
  )

  expect_true(res$success)
  expect_identical(env$.legacy_calls, 0L)
  expect_identical(res$summary_text, "KANONIK F1 TRY")
  expect_identical(res$preview_json, "{}")
  expect_identical(res$pk_packet$scope$grain, "project")
  expect_identical(res$pk_packet$aggregation, "sum")
  expect_identical(res$pk_packet$units, "TRY")
  expect_identical(res$pk_packet$context$authorized_rows, 3L)
  expect_length(res$pk_facts, 1L)
  expect_identical(res$pk_facts[[1]]$id, "F1")
})

test_that("dogrudan DB alt iscisi bloklanirken zorla sonlandirilabilir", {
  skip_if_not_installed("parallelly")
  skip_if_not_installed("future")

  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
  env$pk_async_run_analysis <- function(request) list(status = "ok")
  env$execute_single_deep_query <- function(...) list(success = FALSE)
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_pk_p1_runtime_guards.R"),
         encoding = "UTF-8", local = env)

  cluster <- parallelly::makeClusterPSOCK(1L)
  old_plan <- future::plan()
  on.exit(try(future::plan(old_plan), silent = TRUE), add = TRUE)
  on.exit(try(env$.pk_p1_kill_cluster(cluster), silent = TRUE), add = TRUE)
  future::plan(future::cluster, workers = cluster)

  blocked <- future::future({ Sys.sleep(60); TRUE })
  Sys.sleep(0.2)
  started <- Sys.time()
  env$.pk_p1_kill_cluster(cluster)
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))

  expect_lt(elapsed, 5)
  expect_error(future::value(blocked))
})

test_that("PSOCK baslatma BAGIMSIZ butce sarmalayicisindan gecer", {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
  env$pk_async_run_analysis <- function(request) list(status = "ok")
  env$execute_single_deep_query <- function(...) list(success = FALSE)
  for (dosya in c("helpers_pk_config.R", "helpers_pk_async_cancel.R",
                  "helpers_pk_p1_runtime_guards.R")) {
    source(file.path(resolve_repo_root_for_tests(), "R", dosya),
           encoding = "UTF-8", local = env)
  }

  # `connectTimeout`/`timeout` yalnizca SOKET HAREKETSIZLIGINI sinirlar; Unix ve
  # macOS'ta askida bir el sikisma bu iki degerin USTUNDE bloke kalabilir.
  # Baslatma bu yuzden repo genelindeki bagimsiz butce sarmalayicisindan gecer.
  cagrildi <- FALSE
  env$pk_async_bounded_fs <- function(fn, deadline_at = NULL) {
    cagrildi <<- TRUE
    list(ok = FALSE, value = NULL, error = "reached elapsed time limit")
  }
  env$parallelly <- NULL

  istek <- list(deadline_sec = 30, started_at = as.numeric(Sys.time()),
                cancel_token = NULL, repo_root = tempdir())
  sonuc <- env$.pk_p1_run_direct_disposable(istek)

  expect_true(cagrildi)
  # Sarmalayici butceyi asarsa kume KURULMAMIS sayilir; istek asili kalmaz.
  expect_identical(sonuc$status, "bootstrap_failed")
})
