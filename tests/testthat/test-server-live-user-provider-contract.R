# ==============================================================================
# Dosya Yolu: tests/testthat/test-server-live-user-provider-contract.R
# Açıklama: SSO modunda kullanıcı kimliği 0L başlangıç snapshot'ına takılmasın diye
#           server.R içinde kullanıcıya özel modüllere canlı provider fonksiyonu
#           geçirildiğini statik olarak doğrular. Uygulamayı başlatmaz.
# ==============================================================================

.read_repo_text_for_user_provider_contract <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  if (length(raw_data) >= 3L &&
      identical(as.integer(raw_data[1:3]), c(239L, 187L, 191L))) {
    raw_data <- raw_data[-(1:3)]
  }

  raw_data <- raw_data[raw_data != as.raw(0)]

  txt <- rawToChar(raw_data, multiple = FALSE)
  Encoding(txt) <- "UTF-8"
  txt <- enc2utf8(txt)
  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)

  txt
}

test_that("server.R canlı current_user_id_provider sözleşmesini ServerRuntimeContext üzerinden korur", {
  server_text <- .read_repo_text_for_user_provider_contract("server.R")

  expected <- c(
    "user_session <- serverInitUserSession(",
    "runtime_ctx <- serverRuntimeContextInit(",
    "identity <- runtime_ctx$identity",
    "user_config_rv <- identity$user_config_rv",
    "resolve_current_user_id <- identity$resolve_current_user_id",
    "current_user_id_provider <- identity$current_user_id_provider"
  )

  found <- vapply(
    expected,
    function(item) grepl(item, server_text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_true(
    all(found),
    info = paste(
      "server.R ServerRuntimeContext canlı kullanıcı kimliği sözleşmesi eksik:",
      paste(expected[!found], collapse = ", ")
    )
  )
})

test_that("kullanıcıya özel modüller current_user_id snapshot'ı yerine provider alır", {
  server_text <- .read_repo_text_for_user_provider_contract("server.R")
  core_text <- .read_repo_text_for_user_provider_contract(
    "R/server_core_interaction_runtime.R"
  )
  wiring_text <- .read_repo_text_for_user_provider_contract("R/server_module_wiring.R")

  expected_server_provider_calls <- c(
    "service_modules <- serverBindServiceModules(",
    "current_user_id_provider = current_user_id_provider",
    "core_interaction <- serverBindCoreInteractionRuntime(",
    "user_config_provider = function(default = NULL)",
    "user_first_name_fn = function(default = \"\")"
  )

  server_found <- vapply(
    expected_server_provider_calls,
    function(item) grepl(item, server_text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_true(
    all(server_found),
    info = paste(
      "Bazı server.R kullanıcı provider delegasyonları eksik olabilir:",
      paste(expected_server_provider_calls[!server_found], collapse = ", ")
    )
  )

  expected_core_provider_calls <- c(
    "file_manager_runtime_fn = serverBindFileManagerRuntime",
    "chat_persistence_modules_fn = serverBindChatPersistenceModules",
    "user_id_provider = identity$current_user_id_provider",
    "current_user_id_provider = identity$current_user_id_provider",
    "user_config_provider = user_config_provider",
    "user_first_name_fn = user_first_name_fn"
  )

  core_found <- vapply(
    expected_core_provider_calls,
    function(item) grepl(item, core_text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_true(
    all(core_found),
    info = paste(
      "server_core_interaction_runtime.R kullanıcı provider delegasyonu eksik olabilir:",
      paste(expected_core_provider_calls[!core_found], collapse = ", ")
    )
  )

  expected_wiring_provider_calls <- c(
    "serverBindServiceModules <- function(current_user_id_provider,",
    "performance_stats_server_fn(",
    "\"perf_stats\",",
    "current_user_id_provider",
    "destek_server_fn(",
    "\"destek_module\",",
    "current_user_id = current_user_id_provider",
    "serverBindFileManagerRuntime <- function(",
    "user_id_provider",
    "user_id = user_id_provider",
    "serverBindImageGalleryRuntime <- function(",
    "image_gallery_server_fn(",
    "\"image_gallery_module\",",
    "current_user_id_provider",
    "serverBindChatPersistenceModules <- function(",
    "current_user_id_provider,",
    "user_config_provider,",
    "user_first_name_fn,",
    "current_user_id_provider = current_user_id_provider",
    "download_outputs_init_fn(",
    "history_server_fn(",
    "current_user_id = current_user_id_provider"
  )

  wiring_found <- vapply(
    expected_wiring_provider_calls,
    function(item) grepl(item, wiring_text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_true(
    all(wiring_found),
    info = paste(
      "server_module_wiring.R kullanıcı provider sözleşmesi eksik olabilir:",
      paste(expected_wiring_provider_calls[!wiring_found], collapse = ", ")
    )
  )
})

test_that("server.R içinde riskli current_user_id snapshot geçişleri yeniden ortaya çıkmaz", {
  server_text <- .read_repo_text_for_user_provider_contract("server.R")

  forbidden_patterns <- c(
    "current_user_id = current_user_id,",
    "current_user_id=current_user_id,",
    "user_id = current_user_id,",
    "user_id=current_user_id,"
  )

  matched <- forbidden_patterns[vapply(
    forbidden_patterns,
    function(item) grepl(item, server_text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    matched,
    character(0),
    info = paste(
      "SSO drift riski: canlı provider yerine current_user_id snapshot'ı geçirilmiş olabilir.",
      paste(matched, collapse = "\n"),
      sep = "\n"
    )
  )
})

test_that("server.R kimlik session$userData alanlarını doğrudan yazmaz", {
  server_text <- .read_repo_text_for_user_provider_contract("server.R")

  forbidden_identity_writes <- c(
    "session$userData$user_identity   <-",
    "session$userData$user_first_name <-",
    "session$userData$system_username  <-",
    "session$userData$user_id         <-",
    "session$userData$user_config <- list("
  )

  matched <- forbidden_identity_writes[vapply(
    forbidden_identity_writes,
    function(item) grepl(item, server_text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    matched,
    character(0),
    info = paste(
      "Kimlik oturum alanları server.R içine geri taşınmış olabilir:",
      paste(matched, collapse = "\n"),
      sep = "\n"
    )
  )
})