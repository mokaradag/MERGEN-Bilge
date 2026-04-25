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

test_that("server.R canlı current_user_id_provider sözleşmesini korur", {
  server_text <- .read_repo_text_for_user_provider_contract("server.R")

  expected <- c(
    "resolve_current_user_id <- function()",
    "current_user_id_provider <- function()",
    "resolve_effective_user_id(",
    "session = session",
    "current_user_id = current_user_id"
  )

  found <- vapply(
    expected,
    function(item) grepl(item, server_text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_true(
    all(found),
    info = paste(
      "server.R canlı kullanıcı kimliği çözümleme sözleşmesi eksik:",
      paste(expected[!found], collapse = ", ")
    )
  )
})

test_that("kullanıcıya özel modüller current_user_id snapshot'ı yerine provider alır", {
  server_text <- .read_repo_text_for_user_provider_contract("server.R")

  expected_provider_calls <- c(
    "performanceStatsServer(\"perf_stats\", current_user_id_provider)",
    "destekServer(\"destek_module\", current_user_id = current_user_id_provider)",
    "current_user_id = current_user_id_provider",
    "user_id = current_user_id_provider",
    "imageGalleryServer(\"image_gallery_module\", current_user_id_provider)",
    "downloadOutputsInit(output, session, session_files, current_user_id_provider)"
  )

  found <- vapply(
    expected_provider_calls,
    function(item) grepl(item, server_text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_true(
    all(found),
    info = paste(
      "Bazı kullanıcıya özel server bağlantıları canlı provider kullanmıyor olabilir:",
      paste(expected_provider_calls[!found], collapse = ", ")
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