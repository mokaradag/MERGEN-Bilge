# ==============================================================================
# Dosya Yolu: tests/testthat/test-send-message-lifecycle-helpers-behavior.R
# Açıklama: send_message istek yaşam döngüsü yardımcılarının davranışını
#           doğrular: karşılama ekranı temizleme, sohbet hazırlama (erteleme),
#           ve MCP oturum dosyası hazırlama (mcp_excel olmayan dal).
#           Çevrimdışı/deterministik; gerçek DB/Shiny oturumu/LLM yok.
# ==============================================================================

repo_root_sml <- resolve_repo_root_for_tests()

.sml_env <- new.env(parent = globalenv())
.sml_env$`%||%` <- function(a, b) if (is.null(a)) b else a
.sml_env$log_info <- function(...) invisible(NULL)

# MCP oturum dosyası yardımcısı artık current_session_files kaydını
# session_user_data_get_list() üzerinden korur; izole test ortamında bu
# bağımlılık açıkça yüklenmelidir.
source(file.path(repo_root_sml, "R/utils_session_cleanup.R"),
       encoding = "UTF-8", local = .sml_env)

source(file.path(repo_root_sml, "R/helpers_send_message_request_lifecycle.R"),
       encoding = "UTF-8", local = .sml_env)
source(file.path(repo_root_sml, "R/helpers_send_message_core.R"),
       encoding = "UTF-8", local = .sml_env)

test_that("mergen_clear_welcome_for_send_message: karşılama gösterilmiyorsa no-op", {
  values <- new.env(parent = emptyenv())
  values$show_welcome <- FALSE
  res <- .sml_env$mergen_clear_welcome_for_send_message(list(), values)
  expect_false(res)
  expect_false(isTRUE(values$show_welcome))
})

test_that("mergen_clear_welcome_for_send_message: karşılama gösteriliyorsa kapatır", {
  ran_js <- 0L
  removed <- 0L
  testthat::local_mocked_bindings(runjs = function(...) ran_js <<- ran_js + 1L, .package = "shinyjs")
  # removeUI çağrısı niteliksizdir ve shiny attach edilmediği için yardımcının
  # ortamına doğrudan stub koyarız.
  .sml_env$removeUI <- function(...) removed <<- removed + 1L
  withr::defer(suppressWarnings(rm("removeUI", envir = .sml_env)))

  values <- new.env(parent = emptyenv())
  values$show_welcome <- TRUE
  res <- .sml_env$mergen_clear_welcome_for_send_message(list(), values)
  expect_true(res)
  expect_false(isTRUE(values$show_welcome))
  expect_gt(ran_js, 0L)
  expect_gt(removed, 0L)
})

test_that("mergen_prepare_send_message_chat: mevcut chat_id varsa başlık üretmez", {
  values <- new.env(parent = emptyenv())
  values$current_chat_id <- 42L
  called_title <- 0L
  res <- .sml_env$mergen_prepare_send_message_chat(
    session = list(),
    values = values,
    user_message_text = "merhaba",
    tool_family = "none",
    effective_user_id = 7L,
    request_start_time = Sys.time(),
    defer_chat_creation = FALSE,
    generate_title_from_prompt = function(p, max_len = 60) { called_title <<- called_title + 1L; "X" }
  )
  expect_true(res$ok)
  expect_null(res$pending_chat_title)
  expect_identical(called_title, 0L)  # başlık üretici çağrılmamalı
  expect_identical(values$current_chat_id, 42L)
})

test_that("mergen_prepare_send_message_chat: erteleme açıkken DB'ye yazmaz, pending başlık döner", {
  values <- new.env(parent = emptyenv())
  values$current_chat_id <- NULL
  created <- 0L
  .sml_env$create_new_chat_in_db <- function(...) { created <<- created + 1L; 99L }
  on.exit(suppressWarnings(rm("create_new_chat_in_db", envir = .sml_env)), add = TRUE)

  res <- .sml_env$mergen_prepare_send_message_chat(
    session = list(),
    values = values,
    user_message_text = "Türkçe başlık testi için uzun bir kullanıcı mesajı",
    tool_family = "none",
    effective_user_id = 7L,
    request_start_time = Sys.time(),
    defer_chat_creation = TRUE,
    generate_title_from_prompt = function(p, max_len = 60) substr(p, 1, max_len)
  )
  expect_true(res$ok)
  expect_true(is.character(res$pending_chat_title) && nzchar(res$pending_chat_title))
  expect_identical(created, 0L)        # erteleme: DB çağrısı yok
  expect_null(values$current_chat_id)  # erteleme: chat_id atanmaz
})

test_that("mergen_prepare_send_message_chat: erteleme kapalıyken DB'de oluşturur", {
  values <- new.env(parent = emptyenv())
  values$current_chat_id <- NULL
  .sml_env$create_new_chat_in_db <- function(user_id, initial_title = NULL) 123L
  on.exit(suppressWarnings(rm("create_new_chat_in_db", envir = .sml_env)), add = TRUE)

  res <- .sml_env$mergen_prepare_send_message_chat(
    session = list(),
    values = values,
    user_message_text = "soru",
    tool_family = "none",
    effective_user_id = 7L,
    request_start_time = Sys.time(),
    defer_chat_creation = FALSE,
    generate_title_from_prompt = function(p, max_len = 60) substr(p, 1, max_len)
  )
  expect_true(res$ok)
  expect_null(res$pending_chat_title)
  expect_identical(values$current_chat_id, 123L)
})

test_that("mergen_prepare_mcp_session_files: mcp_excel olmayan dal session dosyalarını korur", {
  session <- list(userData = new.env(parent = emptyenv()))
  mevcut_dosyalar <- list("eski.xlsx" = list(name = "eski.xlsx"))
  session$userData$current_session_files <- mevcut_dosyalar

  snapshot_arg <- NULL
  res <- .sml_env$mergen_prepare_mcp_session_files(
    session = session,
    file_manager_data = list(file_contents = function() list()),
    uploaded_names = c("a.txt"),
    effective_user_id = 7L,
    current_settings = list(),
    cache_mcp_file_locally_fn = function(...) NULL,
    update_mcp_registry_snapshot_fn = function(x) { snapshot_arg <<- x; list(snapshot = x) },
    tool_family = "none"
  )

  expect_identical(res$current_session_files, mevcut_dosyalar)
  expect_identical(session$userData$current_session_files, mevcut_dosyalar)
  expect_identical(snapshot_arg, list())  # MCP kayıt anlık görüntüsü boş kalır
})

test_that("mergen_prepare_mcp_session_files: mcp_excel ama dosya yoksa session dosyalarını korur", {
  session <- list(userData = new.env(parent = emptyenv()))
  mevcut_dosyalar <- list("x" = 1)
  session$userData$current_session_files <- mevcut_dosyalar

  snapshot_arg <- NULL
  res <- .sml_env$mergen_prepare_mcp_session_files(
    session = session,
    file_manager_data = list(file_contents = function() list()),
    uploaded_names = character(0),
    effective_user_id = 7L,
    current_settings = list(),
    cache_mcp_file_locally_fn = function(...) NULL,
    update_mcp_registry_snapshot_fn = function(x) { snapshot_arg <<- x; list(snapshot = x) },
    tool_family = "mcp_excel"
  )

  expect_identical(res$current_session_files, mevcut_dosyalar)
  expect_identical(session$userData$current_session_files, mevcut_dosyalar)
  expect_identical(snapshot_arg, list())  # MCP kayıt anlık görüntüsü boş kalır
})