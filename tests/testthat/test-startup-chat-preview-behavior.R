# ==============================================================================
# Dosya Yolu: tests/testthat/test-startup-chat-preview-behavior.R
# Açıklama: Hızlı Başlangıç "Son Konuşmalar" ön izleme worker katmanının
#           davranış testleri. Dar explicit worker-export sözleşmesini,
#           ana süreç biçimlendirmesinin okuyucu (load_chats_preview_from_db)
#           şekliyle hizasını ve gönderim sözleşmesini kilitler.
#           DB/LLM/tarayıcı gerekmez; tracked_future_promise stub'lanır.
# ==============================================================================

.startup_preview_source_once <- function() {
  needs <- !exists("mergen_startup_chat_preview_promise", mode = "function", inherits = TRUE) ||
           !exists("db_chat_preview_query_sql", mode = "function", inherits = TRUE) ||
           !exists("tracked_future_promise", mode = "function", inherits = TRUE)
  if (!needs) {
    return(invisible(TRUE))
  }

  repo_root <- if (exists("resolve_repo_root_for_tests", mode = "function")) {
    resolve_repo_root_for_tests()
  } else {
    Sys.getenv("MERGEN_REPO_ROOT", unset = getwd())
  }

  source(file.path(repo_root, "R", "utils_common.R"), encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_worker_monitor.R"), encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_db_chat_read_queries.R"), encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_startup_chat_preview.R"), encoding = "UTF-8", local = globalenv())

  invisible(TRUE)
}

.startup_preview_fixture_frame <- function() {
  data.frame(
    ChatID = c(11L, 12L),
    ChatTitle = c("Türkçe başlık çğış", "İkinci sohbet"),
    CreateTimestamp = as.POSIXct(c("2026-07-01 10:00:00", "2026-07-02 11:00:00"), tz = "UTC"),
    MessageCount = c(3L, NA_integer_),
    LastMessageTimestamp = as.POSIXct(c(NA, "2026-07-03 12:00:00"), tz = "UTC"),
    stringsAsFactors = FALSE
  )
}

testthat::test_that("db_chat_preview_format_frame okuyucu ile aynı liste şeklini üretir", {
  .startup_preview_source_once()

  out <- db_chat_preview_format_frame(.startup_preview_fixture_frame())

  testthat::expect_identical(names(out), c("11", "12"))

  # Öğe şekli load_chats_preview_from_db sözleşmesiyle birebir aynıdır.
  beklenen_alanlar <- c("title", "messages", "timestamp", "last_message_timestamp", "message_count")
  testthat::expect_identical(names(out[["11"]]), beklenen_alanlar)
  testthat::expect_identical(names(out[["12"]]), beklenen_alanlar)

  # NA LastMessageTimestamp -> CreateTimestamp'a düşer.
  testthat::expect_identical(out[["11"]]$last_message_timestamp, out[["11"]]$timestamp)
  # NA MessageCount -> 0L güvenli varsayılanı.
  testthat::expect_identical(out[["12"]]$message_count, 0L)
  testthat::expect_identical(out[["11"]]$message_count, 3L)
  testthat::expect_null(out[["11"]]$messages)
})

testthat::test_that("db_chat_preview_format_frame boş/geçersiz girdilerde boş liste döndürür", {
  .startup_preview_source_once()

  testthat::expect_identical(db_chat_preview_format_frame(NULL), list())
  testthat::expect_identical(db_chat_preview_format_frame(list()), list())
  bos_df <- .startup_preview_fixture_frame()[0, , drop = FALSE]
  testthat::expect_identical(db_chat_preview_format_frame(bos_df), list())
})

testthat::test_that("mergen_startup_chat_preview_globals dar export sözleşmesini korur", {
  .startup_preview_source_once()

  g <- mergen_startup_chat_preview_globals("42", limit = "6")

  # Sözleşme: yalnızca bu adlar worker'a taşınır; oturum/reaktif nesne yok.
  testthat::expect_setequal(
    names(g),
    c(
      "startup_preview_user_id",
      "startup_preview_limit",
      "startup_preview_dsn",
      "startup_preview_encoding",
      "startup_preview_name_encoding",
      "db_chat_preview_fetch_raw",
      "db_chat_preview_query_sql"
    )
  )
  testthat::expect_identical(g$startup_preview_user_id, 42L)
  testthat::expect_identical(g$startup_preview_limit, 6L)
  testthat::expect_true(is.function(g$db_chat_preview_fetch_raw))
  testthat::expect_true(is.function(g$db_chat_preview_query_sql))

  # Değer globalleri skalerdır; fonksiyon dışı hiçbir öğe ortam/bağlantı taşımaz.
  deger_adlari <- setdiff(names(g), c("db_chat_preview_fetch_raw", "db_chat_preview_query_sql"))
  for (nm in deger_adlari) {
    testthat::expect_true(is.atomic(g[[nm]]) && length(g[[nm]]) == 1L, label = nm)
  }
})

testthat::test_that("db_chat_preview_fetch_raw geçersiz kimlikte bağlantı açmadan NULL döndürür", {
  .startup_preview_source_once()

  testthat::expect_null(db_chat_preview_fetch_raw(0L, 6L, "dsn", "UTF-8", "UTF-8"))
  testthat::expect_null(db_chat_preview_fetch_raw(NA, 6L, "dsn", "UTF-8", "UTF-8"))
  testthat::expect_null(db_chat_preview_fetch_raw("bilinmiyor", 6L, "dsn", "UTF-8", "UTF-8"))

  # DSN yoksa bağlantı denenmeden net hata verilir.
  testthat::expect_error(
    db_chat_preview_fetch_raw(42L, 6L, "", "UTF-8", "UTF-8"),
    regexp = "DSN"
  )
})

testthat::test_that("mergen_startup_chat_preview_promise explicit modda dar sözleşmeyle gönderir", {
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_preview_source_once()

  helper_env <- environment(mergen_startup_chat_preview_promise)
  old_tracked <- get("tracked_future_promise", envir = helper_env, inherits = TRUE)
  old_fetch <- get("db_chat_preview_fetch_raw", envir = helper_env, inherits = TRUE)

  rec <- new.env(parent = emptyenv())

  assign("tracked_future_promise", function(task_fn,
                                            task_type = "generic",
                                            session_token = NULL,
                                            meta = list(),
                                            globals = NULL,
                                            dependency_mode = c("auto", "explicit"),
                                            packages = NULL) {
    rec$task_type <- task_type
    rec$session_token <- session_token
    rec$dependency_mode <- match.arg(dependency_mode)
    rec$global_names <- sort(names(globals %||% list()))
    rec$packages <- packages
    # Stub, task_fn'i ortam yeniden bağlama olmadan senkron çalıştırır; yerel
    # kopya değişkenler kapanışta görünür olmalıdır (stub uyumluluk sözleşmesi).
    promises::promise_resolve(task_fn())
  }, envir = helper_env)

  assign("db_chat_preview_fetch_raw", function(user_id, limit, dsn, encoding, name_encoding) {
    rec$fetch_user_id <- user_id
    rec$fetch_limit <- limit
    .startup_preview_fixture_frame()
  }, envir = helper_env)

  on.exit({
    assign("tracked_future_promise", old_tracked, envir = helper_env)
    assign("db_chat_preview_fetch_raw", old_fetch, envir = helper_env)
  }, add = TRUE)

  p <- mergen_startup_chat_preview_promise(42L, limit = 6L, session_token = "oturum-1")

  testthat::expect_identical(rec$task_type, "startup_saved_chats_preview")
  testthat::expect_identical(rec$session_token, "oturum-1")
  testthat::expect_identical(rec$dependency_mode, "explicit")
  testthat::expect_identical(rec$packages, "DBI")
  testthat::expect_identical(
    rec$global_names,
    sort(c(
      "startup_preview_user_id",
      "startup_preview_limit",
      "startup_preview_dsn",
      "startup_preview_encoding",
      "startup_preview_name_encoding",
      "db_chat_preview_fetch_raw",
      "db_chat_preview_query_sql"
    ))
  )
  testthat::expect_identical(rec$fetch_user_id, 42L)
  testthat::expect_identical(rec$fetch_limit, 6L)

  # Ham çerçeve ana süreçte biçimlendirilmiş listeye çevrilir.
  got <- new.env(parent = emptyenv())
  promises::then(
    p,
    onFulfilled = function(v) got$value <- v,
    onRejected = function(e) got$error <- conditionMessage(e)
  )
  deadline <- Sys.time() + 5
  while (is.null(got$value) && is.null(got$error) && Sys.time() < deadline) {
    later::run_now(timeoutSecs = 0.1)
  }

  testthat::expect_null(got$error)
  testthat::expect_identical(names(got$value), c("11", "12"))
  testthat::expect_identical(got$value[["11"]]$message_count, 3L)
})
