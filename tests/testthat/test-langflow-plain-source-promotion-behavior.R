# ==============================================================================
# Dosya Yolu: tests/testthat/test-langflow-plain-source-promotion-behavior.R
# Açıklama: Süreç Yönetimi ve Uygulama Uzmanı Langflow yanıtlarının sonunda
#           düz "Kaynak: dosya.ext" olarak gelen, local_model_paths altında
#           gerçekten bulunan dosyaların güvenli tıklanabilir Kaynakça
#           işaretleyicisine yükseltilmesini doğrular.
# ==============================================================================

.source_langflow_plain_source_handler_for_test <- function(canned_result = NULL) {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  for (f in c(
    "R/utils_common.R",
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
  env$log_warn <- function(...) invisible(NULL)
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

test_that("sondaki exact Kaynak satırları doğrulanıp kaynak kaydına yükseltilir", {
  env <- .source_langflow_plain_source_handler_for_test()

  pdf_name <- paste0(
    "07 Program Yönetimi&AS-00-15-01 ASELSAN Proje Yönetim Süreci ",
    "İzleci&&EK-P İşçilik Girişi İş Talimatı.pdf"
  )
  docx_name <- sub("\\.pdf$", ".docx", pdf_name)

  resolver_calls <- list()
  resolver <- function(base_dir, target) {
    resolver_calls[[length(resolver_calls) + 1L]] <<- c(base_dir, target)
    if (target %in% c(pdf_name, docx_name)) {
      return(file.path(base_dir, target))
    }
    NULL
  }

  original <- paste(
    "İşçilik girişi adımları yukarıda açıklanmıştır.",
    paste0("Kaynak: ", pdf_name),
    paste0("Kaynak: ", docx_name),
    sep = "\n"
  )
  out <- env$mergen_langflow_promote_validated_text_sources(
    original,
    local_model_paths = list(
      "technical name 1" = "//main/repository/top-folder",
      "technical name 2" = "//main/repository/top-folder2"
    ),
    resolver = resolver,
    path_exists_fn = function(path) TRUE
  )

  expect_identical(out$text, "İşçilik girişi adımları yukarıda açıklanmıştır.")
  expect_length(out$sources, 2L)
  expect_identical(out$sources[[1]]$title, pdf_name)
  expect_identical(out$sources[[1]]$path, pdf_name)
  expect_identical(out$sources[[1]]$type, "pdf")
  expect_identical(out$sources[[2]]$title, docx_name)
  expect_identical(out$sources[[2]]$path, docx_name)
  expect_true(any(vapply(
    resolver_calls,
    function(call) identical(call[[2]], pdf_name),
    logical(1)
  )))
})

test_that("çözümlenemeyen veya sonda olmayan Kaynak satırları fail-closed kalır", {
  env <- .source_langflow_plain_source_handler_for_test()
  resolver <- function(base_dir, target) NULL

  unresolved <- "Yanıt\nKaynak: bulunamayan.pdf"
  out_unresolved <- env$mergen_langflow_promote_validated_text_sources(
    unresolved,
    local_model_paths = list(model = "//repo"),
    resolver = resolver,
    path_exists_fn = function(path) TRUE
  )
  expect_identical(out_unresolved$text, unresolved)
  expect_length(out_unresolved$sources, 0L)

  non_trailing <- "Kaynak: mevcut.pdf\nBu satır yanıtın devamıdır."
  out_non_trailing <- env$mergen_langflow_promote_validated_text_sources(
    non_trailing,
    local_model_paths = list(model = "//repo"),
    resolver = function(base_dir, target) file.path(base_dir, target),
    path_exists_fn = function(path) TRUE
  )
  expect_identical(out_non_trailing$text, non_trailing)
  expect_length(out_non_trailing$sources, 0L)
})

test_that("Langflow handler doğrulanmış düz kaynakları kalıcı Kaynakça işaretleyicisine çevirir", {
  skip_if_not_installed("openssl")

  pdf_name <- paste0(
    "07 Program Yönetimi&AS-00-15-01 ASELSAN Proje Yönetim Süreci ",
    "İzleci&&EK-P İşçilik Girişi İş Talimatı.pdf"
  )
  docx_name <- sub("\\.pdf$", ".docx", pdf_name)

  env <- .source_langflow_plain_source_handler_for_test(
    canned_result = list(
      success = TRUE,
      text = paste(
        "İşçilik girişi adımları:",
        "1. Team Member uygulamasına giriş yapılır.",
        paste0("Kaynak: ", pdf_name),
        paste0("Kaynak: ", docx_name),
        sep = "\n"
      ),
      error = NULL,
      status = 200L,
      sources = list()
    )
  )
  env$search_file_in_folder <- function(base_dir, target) {
    if (target %in% c(pdf_name, docx_name)) file.path(base_dir, target) else NULL
  }
  env$path_exists_relaxed <- function(path) TRUE

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
      "technical name 1" = "//main/repository/top-folder",
      "technical name 2" = "//main/repository/top-folder2"
    ),
    langflow = list(
      base_url = "https://lf.example.com",
      api_key = "fake-key",
      timeout_seconds = 300,
      process_flows = list(
        list(key = "flow_1", id = "pf-1", name = "Süreç Akışı 1")
      ),
      flow_ids = list()
    ),
    tool_mode_config = list(
      process = list(family = "process", runtime = "langflow")
    )
  )

  ctx <- list(
    session = list(token = "tok-session"),
    values = values,
    tool_family = "process",
    selected_process_flow = "flow_1",
    user_message_text = "İşçilik girişi nasıl yapılır?",
    current_user_id = 7L,
    chat_id_val = "chat-1",
    stop_generation = function() FALSE,
    active_request_id = function() "req-1",
    add_message_fn = function(content, type, html = NULL) {
      rec$messages[[length(rec$messages) + 1L]] <- list(
        content = content,
        type = type
      )
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
  expect_false(grepl(paste0("Kaynak: ", pdf_name), content, fixed = TRUE))
  expect_match(content, "Kaynakça:", fixed = TRUE)
  expect_match(
    content,
    paste0("[KAYNAK 1] ", pdf_name, " | yol=", pdf_name),
    fixed = TRUE
  )
  expect_match(
    content,
    paste0("[KAYNAK 2] ", docx_name, " | yol=", docx_name),
    fixed = TRUE
  )
  expect_identical(rec$messages[[1]]$type, "ai")
  expect_equal(rec$reset_calls, 1L)
})
