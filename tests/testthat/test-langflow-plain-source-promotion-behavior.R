# ==============================================================================
# Dosya Yolu: tests/testthat/test-langflow-plain-source-promotion-behavior.R
# Açıklama: Süreç Yönetimi ve Uygulama Uzmanı Langflow yanıtlarında görülen
#           kaynak biçimlerinin, araçla eşleşen model köklerinde rekürsif olarak
#           doğrulanıp güvenli Kaynakça işaretleyicisine yükseltilmesini sınar.
# ==============================================================================

.source_langflow_plain_source_handler_for_test <- function(canned_result = NULL) {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  for (f in c(
    "R/utils_common.R",
    "R/utils_file_index.R",
    "R/helpers_api_model_config.R",
    "R/helpers_api_model_tool_runtime.R",
    "R/helpers_langflow_runtime.R",
    "R/helpers_langflow_sources.R"
  )) {
    source(file.path(repo_root, f), encoding = "UTF-8", local = env)
  }

  env$removeUI <- function(...) invisible(NULL)
  env$showToast <- function(...) invisible(NULL)
  env$log_debug <- function(...) invisible(NULL)
  env$log_info <- function(...) invisible(NULL)
  env$log_warn <- function(...) invisible(NULL)
  env$log_error <- function(...) invisible(NULL)
  env$path_exists_relaxed <- function(path) isTRUE(file.exists(path))
  env$mergen_is_current_request <- function(...) TRUE
  env$mergen_send_message_release_values_token <- function(values, req_id = NULL) {
    values$backpressure_token <- NULL
    values$backpressure_request_id <- NULL
    invisible(TRUE)
  }

  env$.canned_result <- canned_result
  env$tracked_future_promise <- function(task_fn, ...) {
    structure(list(), class = "fake_langflow_promise")
  }
  env$`%...>%` <- function(lhs, fn) {
    if (!is.null(env$.canned_result)) fn(env$.canned_result)
    lhs
  }
  env$`%...!%` <- function(lhs, fn) lhs

  source(
    file.path(repo_root, "R", "server_handler_langflow.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

.create_test_document <- function(root, relative_path) {
  full_path <- file.path(root, strsplit(relative_path, "/", fixed = TRUE)[[1]])
  dir.create(dirname(full_path), recursive = TRUE, showWarnings = FALSE)
  writeBin(charToRaw("test document"), full_path)
  full_path
}

test_that("üretimdeki köşeli parantez ve Genel Kaynak Listesi biçimi yükseltilir", {
  env <- .source_langflow_plain_source_handler_for_test()
  root <- tempfile("app-expert-root-")
  dir.create(root, recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)

  filename <- "p6_pro_user.pdf"
  .create_test_document(root, filename)

  original <- paste(
    "Uygulamanın temel özellikleri açıklanmıştır.",
    paste0("Kaynak: [", filename, "]"),
    "",
    "Genel Kaynak Listesi:",
    paste0("\u2022 ", filename),
    sep = "\n"
  )

  out <- env$mergen_langflow_promote_validated_sources(
    text = original,
    structured_sources = list(),
    local_model_paths = list(
      mergensurecyonetimi = tempfile("unused-process-root-"),
      mergenuygulamauzmani = root
    ),
    tool_family = "app_expert",
    tool_mode_config = list(app_expert = list(title = "Uygulama Uzmanı")),
    resolver = env$search_file_in_folder,
    path_exists_fn = file.exists
  )

  expect_identical(out$base_count, 1L)
  expect_length(out$sources, 1L)
  expect_identical(out$sources[[1]]$title, filename)
  expect_identical(out$sources[[1]]$path, filename)
  expect_false(grepl("Kaynak:", out$text, fixed = TRUE))
  expect_false(grepl("Genel Kaynak Listesi:", out$text, fixed = TRUE))
  expect_identical(out$text, "Uygulamanın temel özellikleri açıklanmıştır.")
})

test_that("Süreç Yönetimi kökü altındaki çok katmanlı klasörler rekürsif aranır", {
  env <- .source_langflow_plain_source_handler_for_test()
  process_root <- tempfile("process-root-")
  app_root <- tempfile("app-root-")
  dir.create(process_root, recursive = TRUE)
  dir.create(app_root, recursive = TRUE)
  on.exit(unlink(c(process_root, app_root), recursive = TRUE, force = TRUE), add = TRUE)

  filename <- "uretim-sureci-rehberi.pdf"
  .create_test_document(process_root, paste("birim", "alt-surec", filename, sep = "/"))
  .create_test_document(app_root, "baska-belge.pdf")

  out <- env$mergen_langflow_promote_validated_sources(
    text = paste("Yanıt", "Genel Kaynak Listesi:", paste0("- ", filename), sep = "\n"),
    structured_sources = list(),
    local_model_paths = list(
      mergensurecyonetimi = process_root,
      mergenuygulamauzmani = app_root
    ),
    tool_family = "process",
    tool_mode_config = list(process = list(title = "Süreç Yönetimi Sistemi")),
    resolver = env$search_file_in_folder,
    path_exists_fn = file.exists
  )

  expect_identical(out$base_count, 1L)
  expect_length(out$sources, 1L)
  expect_identical(out$sources[[1]]$title, filename)
  expect_identical(out$sources[[1]]$path, paste("birim", "alt-surec", filename, sep = "/"))
})

test_that("yapılandırılmış ve metinsel kaynaklar birlikte doğrulanır ve teklenir", {
  env <- .source_langflow_plain_source_handler_for_test()
  root <- tempfile("combined-root-")
  dir.create(root, recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)

  filename <- "kullanim-kilavuzu.pdf"
  .create_test_document(root, paste("kilavuzlar", filename, sep = "/"))

  out <- env$mergen_langflow_promote_validated_sources(
    text = paste("Yanıt", paste0("Kaynak: [", filename, "]"), sep = "\n"),
    structured_sources = list(list(title = filename, path = filename, type = "pdf")),
    local_model_paths = list(mergenuygulamauzmani = root),
    tool_family = "app_expert",
    resolver = env$search_file_in_folder,
    path_exists_fn = file.exists
  )

  expect_length(out$sources, 1L)
  expect_identical(out$sources[[1]]$path, paste("kilavuzlar", filename, sep = "/"))
  expect_identical(out$text, "Yanıt")
})

test_that("çözümlenemeyen kaynak satırları kapalı güvenlik davranışıyla korunur", {
  env <- .source_langflow_plain_source_handler_for_test()
  root <- tempfile("empty-root-")
  dir.create(root, recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)

  original <- paste(
    "Yanıt",
    "Kaynak: [bulunamayan.pdf]",
    "Genel Kaynak Listesi:",
    "- bulunamayan.pdf",
    sep = "\n"
  )
  out <- env$mergen_langflow_promote_validated_sources(
    text = original,
    structured_sources = list(),
    local_model_paths = list(mergenuygulamauzmani = root),
    tool_family = "app_expert",
    resolver = env$search_file_in_folder,
    path_exists_fn = file.exists
  )

  expect_identical(out$text, original)
  expect_length(out$sources, 0L)
})

test_that("Langflow handler gerçek kaynak biçimini kalıcı tıklanabilir işaretleyiciye çevirir", {
  skip_if_not_installed("openssl")

  root <- tempfile("handler-root-")
  dir.create(root, recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)

  filename <- "p6_pro_user.pdf"
  .create_test_document(root, filename)

  env <- .source_langflow_plain_source_handler_for_test(
    canned_result = list(
      success = TRUE,
      text = paste(
        "Uygulamanın temel özellikleri:",
        "- Planlama ve kontrol.",
        paste0("Kaynak: [", filename, "]"),
        "",
        "Genel Kaynak Listesi:",
        paste0("\u2022 ", filename),
        sep = "\n"
      ),
      error = NULL,
      status = 200L,
      sources = list()
    )
  )

  rec <- new.env()
  rec$messages <- list()
  rec$reset_calls <- 0L
  values <- new.env()
  values$typing <- TRUE
  values$current_chat_id <- "chat-1"
  values$backpressure_token <- "tok-1"
  values$backpressure_request_id <- "req-1"

  config <- list(
    local_model_paths = list(
      mergensurecyonetimi = tempfile("unused-root-"),
      mergenuygulamauzmani = root
    ),
    langflow = list(
      base_url = "https://lf.example.com",
      api_key = "fake-key",
      timeout_seconds = 300,
      flow_ids = list(app_expert = "app-flow-1")
    ),
    tool_mode_config = list(
      app_expert = list(family = "app_expert", runtime = "langflow", title = "Uygulama Uzmanı")
    )
  )

  ctx <- list(
    session = list(token = "tok-session"),
    values = values,
    tool_family = "app_expert",
    selected_process_flow = NULL,
    user_message_text = "Uygulamayı açıkla.",
    current_user_id = 7L,
    chat_id_val = "chat-1",
    stop_generation = function() FALSE,
    active_request_id = function() "req-1",
    add_message_fn = function(content, type, html = NULL) {
      rec$messages[[length(rec$messages) + 1L]] <- list(content = content, type = type)
      list(id = "m1")
    },
    reset_chat_state_fn = function() {
      rec$reset_calls <- rec$reset_calls + 1L
      invisible(NULL)
    },
    api_config = config
  )

  expect_true(env$handle_langflow_chat_mode(ctx))
  expect_length(rec$messages, 1L)

  content <- rec$messages[[1]]$content
  expect_false(grepl("Genel Kaynak Listesi:", content, fixed = TRUE))
  expect_match(content, "Kaynakça:", fixed = TRUE)
  expect_match(
    content,
    paste0("[KAYNAK 1] ", filename, " | yol=", filename),
    fixed = TRUE
  )
  expect_identical(rec$messages[[1]]$type, "ai")
  expect_equal(rec$reset_calls, 1L)
})
