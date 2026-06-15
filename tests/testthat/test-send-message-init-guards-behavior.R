# ==============================================================================
# Dosya Yolu: tests/testthat/test-send-message-init-guards-behavior.R
# Açıklama: sendMessageInit (R/server_send_message.R) fabrikasının döndürdüğü
#           send_message kapanışının ERKEN-DÖNÜŞ koruma sınırlarını davranışsal
#           olarak sınar. Ağır LLM/araç/akış makinesine GİRMEDEN, kapanışın ilk
#           dört korumasını kilitler:
#             * SSO açıkken kimlik doğrulanmadıysa mesaj gönderilmez (kimlik sınırı;
#               kullanıcı-id ÇÖZÜLMEDEN önce reddedilir),
#             * etkin kullanıcı kimliği <= 0 ise reddedilir (NA -> 0 dönüşümü dahil),
#             * önceki istek hâlâ gönderiliyorsa (is_sending) reddedilir (çift-gönderim
#               yarış koruması),
#             * boş mesaj + yükleme yoksa reddedilir (girdi doğrulama).
#           sendMessageInit gözlemci kaydetmeyen, send_message'i döndüren saf bir
#           fabrika olduğundan testServer GEREKMEZ; doğrudan çağrılır. Gerçek
#           LLM/DB/ağ/oturum sunucusu YOK; bağımlılıklar deterministik stub'lanır.
# ==============================================================================

testthat::local_edition(3)

# showToast çağrılarını toplayan kayıt defteri (toast = kullanıcıya görünen uyarı).
.smi_rec <- new.env()
.smi_rec$toasts <- list()

.smi_env <- new.env(parent = globalenv())
.smi_env$showToast <- function(session, message, type = NULL) {
  .smi_rec$toasts[[length(.smi_rec$toasts) + 1L]] <- list(message = message, type = type)
  invisible(NULL)
}
.smi_env$mergen_clear_welcome_for_send_message <- function(session, values) invisible(NULL)
.smi_env$log_info <- function(...) invisible(NULL)
.smi_env$`%||%` <- function(a, b) if (is.null(a)) b else a

source(
  file.path(resolve_repo_root_for_tests(), "R", "server_send_message.R"),
  encoding = "UTF-8",
  local = .smi_env
)

# 24 bağımlılığı NULL/stub geçerek fabrikayı kurar ve send_message'i döndürür.
# Erken-dönüş yolu bunların çoğuna dokunmaz; tembel değerlendirme nedeniyle
# NULL argümanlar fabrika çağrısında zorlanmaz.
.smi_make_send <- function(session, values) {
  .smi_rec$toasts <- list()
  factory <- .smi_env$sendMessageInit(
    session = session, input = NULL, output = NULL, values = values,
    settings_data = NULL, session_files = function() list(),
    file_manager_data = NULL, current_user_id = 0L, stop_generation = NULL,
    active_request_id = NULL, quick_action_skip_mcp = function(...) FALSE,
    perf_tracker = NULL, ai_processor = NULL, tts_processor = NULL,
    followup_tools = NULL, fallback_followup_tool = NULL, api_config = NULL,
    add_message_fn = NULL, reset_chat_state_fn = NULL,
    simulate_streaming_stoppable_fn = NULL, cache_mcp_file_locally_fn = NULL,
    update_mcp_registry_snapshot_fn = NULL, saved_chats_data = NULL,
    generate_non_streaming_stoppable_fn = NULL
  )
  factory$send_message
}

.smi_session <- function(auth_initialized = TRUE) {
  list(userData = list(auth_initialized = auth_initialized))
}
.smi_values <- function(is_sending = FALSE, last_request_time = NULL) {
  v <- new.env()
  v$is_sending <- is_sending
  v$last_request_time <- last_request_time
  v
}

test_that("SSO açık + kimlik doğrulanmamışsa mesaj reddedilir (kullanıcı-id çözülmeden)", {
  .smi_env$SSO_ENABLED <- TRUE
  # Kimlik doğrulama korumasının kullanıcı-id çözümünden ÖNCE geldiğini kanıtlar:
  # bu stub çağrılırsa hata fırlatır, çağrılmamalı.
  .smi_env$resolve_effective_user_id <- function(session, current_user_id) {
    stop("kimlik korumasından önce kullanıcı-id çözülmemeli")
  }

  sm <- .smi_make_send(.smi_session(auth_initialized = FALSE), .smi_values())
  res <- sm("merhaba")

  expect_null(res)
  expect_length(.smi_rec$toasts, 1L)
  expect_match(.smi_rec$toasts[[1]]$message, "Kimlik doğrulama")
  expect_identical(.smi_rec$toasts[[1]]$type, "warning")
})

test_that("etkin kullanıcı kimliği NA/0 ise mesaj reddedilir (kimlik sınırı)", {
  .smi_env$SSO_ENABLED <- FALSE
  # NA döndürerek resolve_current_user_id içindeki is.na -> 0L dönüşümünü de sınar.
  .smi_env$resolve_effective_user_id <- function(session, current_user_id) NA_integer_

  sm <- .smi_make_send(.smi_session(auth_initialized = TRUE), .smi_values())
  res <- sm("merhaba")

  expect_null(res)
  expect_length(.smi_rec$toasts, 1L)
  expect_match(.smi_rec$toasts[[1]]$message, "Kullanıcı kimliği alınamadı")
  expect_identical(.smi_rec$toasts[[1]]$type, "error")
})

test_that("önceki istek hâlâ gönderiliyorsa yeni mesaj reddedilir (çift-gönderim koruması)", {
  .smi_env$SSO_ENABLED <- FALSE
  .smi_env$resolve_effective_user_id <- function(session, current_user_id) 5L

  sm <- .smi_make_send(.smi_session(auth_initialized = TRUE), .smi_values(is_sending = TRUE))
  res <- sm("merhaba")

  expect_null(res)
  expect_length(.smi_rec$toasts, 1L)
  expect_match(.smi_rec$toasts[[1]]$message, "önceki isteğin tamamlanmasını")
})

test_that("boş mesaj + yükleme yoksa reddedilir (girdi doğrulama)", {
  .smi_env$SSO_ENABLED <- FALSE
  .smi_env$resolve_effective_user_id <- function(session, current_user_id) 5L
  .smi_env$mergen_build_send_message_prompt_snapshot <- function(prompt_text, session_files) {
    list(
      user_message_text = "",
      current_session_files = list(),
      uploaded_names = character(0),
      uploaded_count = 0L
    )
  }

  sm <- .smi_make_send(.smi_session(auth_initialized = TRUE), .smi_values())
  res <- sm("")

  expect_null(res)
  expect_length(.smi_rec$toasts, 1L)
  expect_match(.smi_rec$toasts[[1]]$message, "Lütfen bir mesaj yazın")
})
