testthat::local_edition(3)

.worker_owner_env <- function() {
  env <- new.env(parent = globalenv())
  for (name in c("helpers_user_session_identity.R", "helpers_async_result_guard.R",
                 "helpers_send_message_request_lifecycle.R")) {
    source(file.path(resolve_repo_root_for_tests(), "R", name), encoding = "UTF-8", local = env)
  }
  env
}

test_that("aynı kullanıcının yetki değişimi eski sonuçları ve kancaları geçersiz kılar", {
  env <- .worker_owner_env()
  session <- list(userData = new.env())
  identity <- env$make_user_session_data_accessors(session)
  identity$write_identity(list(username = "a"), 7L, list(auth_level = "ADMIN"), TRUE, "keycloak")
  guard <- env$mergen_session_owner_guard(session)
  calls <- character()
  remove <- env$mergen_session_on_owner_change(session, function(reason) {
    remove()
    calls <<- c(calls, reason)
  })
  env$mergen_session_on_owner_change(session, function(reason) calls <<- c(calls, reason))
  expect_true(guard())
  identity$write_identity(list(username = "a"), 7L, list(auth_level = "USER"), TRUE, "keycloak")
  expect_false(guard())
  expect_identical(calls, rep("yetki_degisti", 2L))
  current <- env$mergen_session_owner_guard(session)
  identity$write_identity(list(username = "a"), 7L, list(auth_level = "USER"), TRUE, "keycloak")
  expect_true(current())
  expect_length(calls, 2L)
})

test_that("SSE sahip temizliği beklemeyen işin kancalarını bırakır ve kendi durumunu sıfırlar", {
  env <- .worker_owner_env()
  shiny::testServer(function(input, output, session) NULL, {
    session$userData$user_id <- session$userData$kimlik_sahibi <- 7L
    active <- shiny::reactiveVal("A")
    values <- shiny::reactiveValues(is_sending = TRUE, typing = TRUE)
    resets <- 0L
    ended <- 0L
    destroyed <- 0L
    stream <- new.env()
    stream$req_id <- "A"
    stream$settled <- FALSE
    stream$owner_guard <- env$mergen_session_owner_guard(session)
    stream$stream_file <- withr::local_tempfile()
    stream$stop_file <- withr::local_tempfile()
    file.create(stream$stream_file)
    stream$poll_observer <- list(destroy = function() destroyed <<- destroyed + 1L)
    ctx <- list(session = session, active_request_id = active, reset_chat_state_fn = function() {
      resets <<- resets + 1L
      values$is_sending <- values$typing <- FALSE
    })
    cleanup <- env$mergen_stream_bind_cleanup(ctx, stream)
    original_end <- stream$remove_end_hook
    stream$remove_end_hook <- function() { ended <<- ended + 1L; original_end() }
    session$userData$user_id <- 8L
    env$mergen_session_owner_transition(session$userData, 7L, 8L)
    expect_null(shiny::isolate(active()))
    expect_false(shiny::isolate(values$is_sending))
    expect_false(shiny::isolate(values$typing))
    expect_identical(resets, 1L)
    expect_identical(destroyed, 1L)
    expect_identical(ended, 1L)
    expect_length(ls(session$userData$kimlik_kancalari), 0L)
    expect_true(file.exists(stream$stop_file))
    expect_true(file.exists(stream$stream_file))
    active("B")
    values$is_sending <- TRUE
    stream$settled <- TRUE
    cleanup()
    expect_identical(shiny::isolate(active()), "B")
    expect_true(shiny::isolate(values$is_sending))
    expect_identical(resets, 1L)
    expect_false(file.exists(stream$stop_file))
    expect_false(file.exists(stream$stream_file))
  })
})

test_that("erken SSE iptali promise çözülmese de yaşam döngüsü kancalarını kaldırır", {
  env <- .worker_owner_env()
  ud <- new.env()
  ud$user_id <- ud$kimlik_sahibi <- 7L
  ended <- 0L
  session <- list(userData = ud, onSessionEnded = function(fn) function() ended <<- ended + 1L)
  stream <- new.env()
  stream$req_id <- "A"
  stream$owner_guard <- function() TRUE
  stream$stream_file <- withr::local_tempfile()
  stream$stop_file <- withr::local_tempfile()
  cleanup <- env$mergen_stream_bind_cleanup(list(session = session, active_request_id = function(...) "B"), stream)
  cleanup()
  expect_length(ls(ud$kimlik_kancalari), 0L)
  expect_identical(ended, 1L)
  expect_true(file.exists(stream$stop_file))
})

test_that("non-streaming sahip temizliği eski istek ile sınırlıdır", {
  env <- .worker_owner_env()
  for (current in c("A", "B")) {
    shiny::testServer(function(input, output, session) NULL, {
      session$userData$user_id <- session$userData$kimlik_sahibi <- 7L
      active <- shiny::reactiveVal(current)
      resets <- 0L
      remove <- env$mergen_bind_request_owner_cleanup(session, active, "A", function() resets <<- resets + 1L)
      session$userData$user_id <- 8L
      env$mergen_session_owner_transition(session$userData, 7L, 8L)
      expect_identical(resets, if (current == "A") 1L else 0L)
      expect_identical(shiny::isolate(active()), if (current == "A") NULL else "B")
      expect_length(ls(session$userData$kimlik_kancalari), 0L)
      remove()
    })
  }
})

test_that("Yolaç sahip temizliği SSO alanından çağrılsa da kendi kontrollerini günceller", {
  env <- .worker_owner_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_workbench_session_api.R"),
         encoding = "UTF-8", local = env)
  env$cc_reset_workbench_owner <- function(...) NULL
  domains <- character()
  testthat::local_mocked_bindings(
    enable = function(id, ...) domains <<- c(domains, shiny::getDefaultReactiveDomain()$ns(id)),
    hide = function(id, ...) domains <<- c(domains, shiny::getDefaultReactiveDomain()$ns(id)),
    .package = "shinyjs"
  )
  shiny::testServer(function(input, output, session) NULL, {
    session$userData$user_id <- session$userData$kimlik_sahibi <- 7L
    workbench <- session$makeScope("workbench")
    sso <- session$makeScope("sso")
    env$cc_bind_workbench_owner_lifecycle(workbench, workbench$ns, new.env(), list())
    shiny::withReactiveDomain(sso, env$mergen_session_owner_transition(session$userData, 7L, 8L))
    expect_identical(domains, c("workbench-run_command", "workbench-stop_command"))
  })
})

test_that("aynı sahip yetki kaybında hassas önbellekler temizlenir", {
  env <- .worker_owner_env()
  for (change in c("logout", "auth")) {
    ud <- new.env()
    ud$user_id <- ud$kimlik_sahibi <- 7L
    for (key in c("current_session_files", "file_summaries", "chart_store", "mcp_registry_snapshot"))
      ud[[key]] <- list(secret = "eski yetki")
    ud$ai_api_key <- "eski anahtar"
    env$mergen_session_owner_transition(ud, 7L, if (change == "logout") 0L else 7L,
      yetki_degisti = change == "auth")
    for (key in c("current_session_files", "file_summaries", "chart_store", "mcp_registry_snapshot"))
      expect_length(ud[[key]], 0L)
    expect_null(ud$ai_api_key)
    expect_identical(ud$kimlik_nesli, 1L)
  }
})


test_that("kapanmış SSE oturumu kabul jetonunu ve istek sahipliğini bir kez bırakır", {
  env <- .worker_owner_env()
  ud <- new.env(parent = emptyenv())
  ud$user_id <- 7L
  ud$llm_request_owner <- "A"
  closed <- FALSE
  end <- NULL
  removed <- releases <- 0L
  session <- list(userData = ud, isClosed = function() closed,
    onSessionEnded = function(callback) {
      end <<- callback
      function() removed <<- removed + 1L
    })
  active_value <- "A"
  active <- function(value) {
    if (missing(value)) return(active_value)
    active_value <<- value
  }
  values <- new.env(parent = emptyenv())
  values$is_sending <- values$typing <- TRUE
  env$mergen_send_message_release_values_token <- function(...) releases <<- releases + 1L
  stream <- new.env(parent = emptyenv())
  stream$req_id <- "A"
  stream$owner_guard <- env$mergen_session_owner_guard(session)
  stream$stream_file <- withr::local_tempfile()
  stream$stop_file <- withr::local_tempfile()
  env$mergen_stream_bind_cleanup(list(session = session, values = values,
    active_request_id = active, reset_chat_state_fn = function() stop("kapalı UI")), stream)
  closed <- TRUE
  for (i in 1:2) end()
  expect_null(active_value)
  expect_false(values$is_sending)
  expect_false(values$typing)
  expect_true(stream$finalized)
  expect_identical(releases, 1L)
  expect_identical(removed, 1L)
  expect_length(ls(ud$kimlik_kancalari), 0L)
  expect_true(file.exists(stream$stop_file))
})
