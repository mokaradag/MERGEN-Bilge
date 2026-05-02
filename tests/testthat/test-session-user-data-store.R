# ==============================================================================
# Dosya Yolu: tests/testthat/test-session-user-data-store.R
# Açıklama: session$userData içindeki liste tabanlı oturum depolarının merkezi
#           yardımcılarla güvenli biçimde yönetildiğini doğrular.
# ==============================================================================

repo_root <- resolve_repo_root_for_tests()

source(
  file.path(repo_root, "R", "utils_common.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root, "R", "utils_session_cleanup.R"),
  encoding = "UTF-8",
  local = globalenv()
)

.fake_session_user_data_store <- function() {
  list(
    userData = new.env(parent = emptyenv()),
    token = "test-token"
  )
}

.read_session_store_contract_text <- function(rel_path) {
  path <- file.path(repo_root, rel_path)

  if (!file.exists(path)) {
    stop(sprintf("Dosya bulunamadı: %s", rel_path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  if (length(raw_data) >= 3L &&
      identical(as.integer(raw_data[1:3]), c(239L, 187L, 191L))) {
    raw_data <- raw_data[-(1:3)]
  }

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

test_that("session_user_data_get_list eksik listeyi güvenli şekilde oluşturur", {
  session <- .fake_session_user_data_store()

  out <- session_user_data_get_list(session, "file_summaries")

  expect_true(is.list(out))
  expect_identical(out, list())
  expect_true(is.list(session$userData$file_summaries))
})

test_that("session_user_data_set_list yalnızca liste değerleri kabul eder", {
  session <- .fake_session_user_data_store()

  session_user_data_set_list(
    session,
    "current_session_files",
    list("a.xlsx" = list(path = "a.xlsx"))
  )

  expect_true(is.list(session$userData$current_session_files))
  expect_equal(names(session$userData$current_session_files), "a.xlsx")

  expect_error(
    session_user_data_set_list(session, "broken", "liste değil"),
    "liste bekleniyor"
  )
})

test_that("session_user_data_put_list_item ve remove item adlandırılmış öğeleri yönetir", {
  session <- .fake_session_user_data_store()

  session_user_data_put_list_item(
    session,
    "current_session_files",
    "rapor.xlsx",
    list(name = "rapor.xlsx", path = "tmp/rapor.xlsx")
  )

  expect_equal(
    session$userData$current_session_files$rapor.xlsx$name,
    "rapor.xlsx"
  )

  session_user_data_remove_list_item(
    session,
    "current_session_files",
    "rapor.xlsx"
  )

  expect_null(session$userData$current_session_files$rapor.xlsx)
})

test_that("session_user_data_reset_lists birden fazla store alanını temizler", {
  session <- .fake_session_user_data_store()

  session_user_data_put_list_item(session, "file_summaries", "a.txt", "özet")
  session_user_data_put_list_item(session, "mcp_registry_snapshot", "a.txt", list(path = "a.txt"))

  session_user_data_reset_lists(
    session,
    c("file_summaries", "mcp_registry_snapshot")
  )

  expect_identical(session$userData$file_summaries, list())
  expect_identical(session$userData$mcp_registry_snapshot, list())
})

test_that("session_runtime_store_reset ortak dosya depolarını tek sözleşmeden kurar", {
  session <- .fake_session_user_data_store()

  session_user_data_put_list_item(
    session,
    "current_session_files",
    "rapor.xlsx",
    list(path = "rapor.xlsx")
  )
  session_user_data_put_list_item(session, "file_summaries", "rapor.xlsx", "özet")
  session_user_data_put_list_item(session, "chart_store", "grafik_1", list(type = "bar"))

  session_runtime_store_reset(session)

  expect_identical(session$userData$current_session_files, list())
  expect_identical(session$userData$file_summaries, list())
  expect_identical(session$userData$chart_store, list())
  expect_identical(session$userData$mcp_registry_snapshot, list())
})

test_that("session_runtime_store_snapshot_mcp mevcut oturum dosyalarını yansıtır", {
  session <- .fake_session_user_data_store()

  current_files <- list(
    "rapor.xlsx" = list(
      name = "rapor.xlsx",
      path = "tmp/rapor.xlsx"
    )
  )

  session_runtime_store_set(session, "current_session_files", current_files)
  session_runtime_store_snapshot_mcp(session)

  expect_identical(session$userData$mcp_registry_snapshot, current_files)

  explicit_snapshot <- list(
    "secili.docx" = list(
      name = "secili.docx",
      path = "tmp/secili.docx"
    )
  )

  session_runtime_store_snapshot_mcp(session, explicit_snapshot)

  expect_identical(session$userData$mcp_registry_snapshot, explicit_snapshot)
})

test_that("session_runtime_store_key yalnızca bilinen store adlarını kabul eder", {
  expect_identical(
    session_runtime_store_key("current_session_files"),
    "current_session_files"
  )

  expect_identical(
    session_runtime_store_key("mcp_registry_snapshot"),
    "mcp_registry_snapshot"
  )

  expect_error(
    session_runtime_store_key("rastgele_store"),
    "Bilinen store adı"
  )
})

test_that("session_user_data_get_list liste olmayan mevcut alanı erken yakalar", {
  session <- .fake_session_user_data_store()
  session$userData$file_summaries <- "yanlış tip"

  expect_error(
    session_user_data_get_list(session, "file_summaries"),
    "liste olmalıdır"
  )
})

test_that("boot dosyaları MCP store anahtarlarını doğrudan yönetmez", {
  boot_texts <- c(
    server_session_cache = .read_session_store_contract_text("R/server_session_cache.R"),
    server_init_session_state = .read_session_store_contract_text("R/server_init_session_state.R")
  )

  forbidden_patterns <- c(
    'session_user_data_set_list\\s*\\(\\s*session\\s*,\\s*"mcp_registry_snapshot"',
    'session_user_data_get_list\\s*\\(\\s*session\\s*,\\s*"current_session_files"',
    'session_user_data_reset_lists\\s*\\(\\s*session\\s*,\\s*c\\s*\\('
  )

  violations <- character(0)

  for (file_name in names(boot_texts)) {
    for (pattern in forbidden_patterns) {
      if (grepl(pattern, boot_texts[[file_name]], perl = TRUE)) {
        violations <- c(violations, paste(file_name, pattern, sep = " -> "))
      }
    }
  }

  expect_equal(
    violations,
    character(0),
    info = paste(
      "Boot dosyaları session_runtime_store_* yardımcılarını kullanmalıdır:",
      paste(violations, collapse = ", ")
    )
  )
})