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
      "startup_preview_login_timeout",
      "startup_preview_query_timeout",
      "startup_preview_name_encoding",
      "db_chat_preview_fetch_raw",
      "db_chat_preview_query_sql",
      "mergen_bounded_db_fetch_raw"
    )
  )
  testthat::expect_identical(g$startup_preview_user_id, 42L)
  testthat::expect_identical(g$startup_preview_limit, 6L)
  testthat::expect_true(is.function(g$db_chat_preview_fetch_raw))
  testthat::expect_true(is.function(g$db_chat_preview_query_sql))

  # Değer globalleri skalerdır; fonksiyon dışı hiçbir öğe ortam/bağlantı taşımaz.
  deger_adlari <- setdiff(names(g), c("db_chat_preview_fetch_raw", "db_chat_preview_query_sql",
                                      "mergen_bounded_db_fetch_raw"))
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

  assign("db_chat_preview_fetch_raw", function(user_id, limit, dsn, encoding, name_encoding,
                                               login_timeout = NA_integer_, query_timeout = NA_real_) {
    rec$fetch_user_id <- user_id
    rec$fetch_query_timeout <- query_timeout
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
      "startup_preview_login_timeout",
      "startup_preview_query_timeout",
      "startup_preview_name_encoding",
      "db_chat_preview_fetch_raw",
      "db_chat_preview_query_sql",
      "mergen_bounded_db_fetch_raw"
    ))
  )
  testthat::expect_identical(rec$fetch_user_id, 42L)
  testthat::expect_identical(rec$fetch_limit, 6L)
  # İşçi okuması her zaman sonlu bir sorgu süre bütçesi taşır.
  testthat::expect_true(is.finite(rec$fetch_query_timeout) && rec$fetch_query_timeout > 0)

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

testthat::test_that("tam liste modu (limit = NA) yalnızca özet SQL üreticisini ekler", {
  .startup_preview_source_once()
  if (!exists("db_chat_list_summary_query_sql", mode = "function", inherits = TRUE)) {
    source(file.path(resolve_repo_root_for_tests(), "R", "helpers_db_chat_read_queries.R"),
           encoding = "UTF-8", local = globalenv())
  }

  g <- mergen_startup_chat_preview_globals("42", limit = NA_integer_)
  testthat::expect_setequal(
    names(g),
    c("startup_preview_user_id", "startup_preview_limit", "startup_preview_dsn",
      "startup_preview_encoding", "startup_preview_login_timeout", "startup_preview_query_timeout",
      "startup_preview_name_encoding", "db_chat_preview_fetch_raw", "db_chat_preview_query_sql",
      "mergen_bounded_db_fetch_raw", "db_chat_list_summary_query_sql")
  )
  testthat::expect_true(is.na(g$startup_preview_limit))
  # Ön izleme sözleşmesi tam liste eklemesinden etkilenmez.
  testthat::expect_false("db_chat_list_summary_query_sql" %in%
                           names(mergen_startup_chat_preview_globals("42", limit = 6L)))
})

testthat::test_that("tam söyleşi listesi explicit modda 'startup_saved_chats' olarak gönderilir", {
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_preview_source_once()
  if (!exists("db_chat_list_summary_query_sql", mode = "function", inherits = TRUE)) {
    source(file.path(resolve_repo_root_for_tests(), "R", "helpers_db_chat_read_queries.R"),
           encoding = "UTF-8", local = globalenv())
  }

  helper_env <- environment(mergen_startup_chat_preview_promise)
  old_tracked <- get("tracked_future_promise", envir = helper_env, inherits = TRUE)
  old_fetch <- get("db_chat_preview_fetch_raw", envir = helper_env, inherits = TRUE)
  rec <- new.env(parent = emptyenv())
  assign("tracked_future_promise", function(task_fn, task_type = "generic", session_token = NULL,
                                            meta = list(), globals = NULL,
                                            dependency_mode = c("auto", "explicit"), packages = NULL) {
    rec$task_type <- task_type
    rec$dependency_mode <- match.arg(dependency_mode)
    rec$global_names <- names(globals %||% list())
    promises::promise_resolve(task_fn())
  }, envir = helper_env)
  assign("db_chat_preview_fetch_raw", function(user_id, limit, dsn, encoding, name_encoding,
                                               login_timeout = NA_integer_, query_timeout = NA_real_) {
    rec$fetch_limit <- limit
    .startup_preview_fixture_frame()
  }, envir = helper_env)
  on.exit({
    assign("tracked_future_promise", old_tracked, envir = helper_env)
    assign("db_chat_preview_fetch_raw", old_fetch, envir = helper_env)
  }, add = TRUE)

  p <- mergen_startup_chat_preview_promise(42L, limit = NA_integer_, session_token = "oturum-2")
  got <- new.env(parent = emptyenv())
  promises::then(p, onFulfilled = function(v) got$value <- v)
  deadline <- Sys.time() + 5
  while (is.null(got$value) && Sys.time() < deadline) later::run_now(timeoutSecs = 0.1)

  testthat::expect_identical(rec$task_type, "startup_saved_chats")
  testthat::expect_identical(rec$dependency_mode, "explicit")
  testthat::expect_true("db_chat_list_summary_query_sql" %in% rec$global_names)
  testthat::expect_true(is.na(rec$fetch_limit))
  # Biçim load_chats_from_db(include_messages = FALSE) ile aynıdır.
  testthat::expect_identical(names(got$value[["11"]]),
                             c("title", "messages", "timestamp", "last_message_timestamp", "message_count"))
})

# Gerçek db_chat_preview_fetch_raw çalıştırılır; yalnızca DB sınırı (DBI)
# taklit edilir. Böylece limit -> SQL seçimi dalı doğrudan sınanır.
.preview_fetch_sql <- function(limit) {
  .startup_preview_source_once()
  if (!exists("db_chat_list_summary_query_sql", mode = "function", inherits = TRUE)) {
    source(file.path(resolve_repo_root_for_tests(), "R", "helpers_db_chat_read_queries.R"),
           encoding = "UTF-8", local = globalenv())
  }
  yakalanan <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    dbConnect = function(drv, ...) structure(list(), class = "sahte_baglanti"),
    dbDisconnect = function(conn, ...) invisible(TRUE),
    dbGetQuery = function(conn, statement, ...) {
      yakalanan$sql <- statement
      .startup_preview_fixture_frame()
    },
    .package = "DBI"
  )
  db_chat_preview_fetch_raw(42L, limit = limit, dsn = "TestConnection",
                            encoding = "UTF-8", name_encoding = "UTF-8")
  yakalanan$sql
}

testthat::test_that("gerçek getirici açık NA sentinelinde özet SQL'i, diğerlerinde ön izleme SQL'ini seçer", {
  testthat::skip_if_not_installed("DBI")
  testthat::skip_if_not_installed("odbc")
  testthat::expect_identical(.preview_fetch_sql(NA_integer_), db_chat_list_summary_query_sql())
  testthat::expect_identical(.preview_fetch_sql(NA), db_chat_list_summary_query_sql())
  testthat::expect_identical(.preview_fetch_sql(6L), db_chat_preview_query_sql(6L))
  testthat::expect_identical(.preview_fetch_sql(10L), db_chat_preview_query_sql(10L))
  # Bozuk limitler sessizce sınırsız tam liste sorgusuna dönüşmez.
  for (bozuk in list("abc", Inf, NaN, 0L, -3L, NULL, NA_character_, c(1L, 2L))) {
    testthat::expect_identical(.preview_fetch_sql(bozuk), db_chat_preview_query_sql(
      if (identical(bozuk, c(1L, 2L))) 1L else 6L), info = paste(deparse(bozuk), collapse = ""))
  }
})

testthat::test_that("limit normalleştirici yalnızca açık NA'yı tam liste sayar", {
  .startup_preview_source_once()
  testthat::expect_true(is.na(mergen_startup_chat_preview_limit(NA_integer_)))
  testthat::expect_true(is.na(mergen_startup_chat_preview_limit(NA)))
  testthat::expect_identical(mergen_startup_chat_preview_limit(6L), 6L)
  for (bozuk in list("abc", Inf, NaN, 0L, -1L, NULL, NA_character_, "NA")) {
    testthat::expect_identical(mergen_startup_chat_preview_limit(bozuk), 6L,
                               info = paste(deparse(bozuk), collapse = ""))
  }
  # NULL limit gönderim öncesinde hata vermez; ön izleme sözleşmesiyle gider.
  g <- mergen_startup_chat_preview_globals("42", limit = NULL)
  testthat::expect_identical(g$startup_preview_limit, 6L)
  testthat::expect_false("db_chat_list_summary_query_sql" %in% names(g))
})

testthat::test_that("arka plan tam listesi gönderimden sonraki yerel değişiklikleri ezmez", {
  .startup_preview_source_once()
  db <- list("1" = list(title = "DB bir"), "2" = list(title = "DB iki"), "3" = list(title = "DB üç"))
  anlik <- list("1" = list(title = "Önizleme bir"), "2" = list(title = "Önizleme iki"))
  # Yerel durum değişmediyse DB sonucu aynen uygulanır.
  testthat::expect_identical(mergen_saved_chats_merge_newer(db, anlik, anlik), db)
  # Gönderimden sonra: "2" yeniden adlandırıldı, "9" yeni açıldı, "1" silindi.
  simdiki <- list("2" = list(title = "Yeni ad çğış"), "9" = list(title = "Yeni söyleşi"))
  birlesik <- mergen_saved_chats_merge_newer(db, anlik, simdiki)
  testthat::expect_identical(names(birlesik), c("9", "2", "3"))
  testthat::expect_identical(birlesik[["2"]]$title, "Yeni ad çğış")
  testthat::expect_identical(birlesik[["9"]]$title, "Yeni söyleşi")
  testthat::expect_null(birlesik[["1"]])
  testthat::expect_identical(birlesik[["3"]]$title, "DB üç")
})

testthat::test_that("işçi DB okuması yapılandırılmış login sınırını get_connection() ile aynı biçimde taşır", {
  eski <- Sys.getenv("MERGEN_DB_LOGIN_TIMEOUT_SEC", unset = NA)
  on.exit(if (is.na(eski)) Sys.unsetenv("MERGEN_DB_LOGIN_TIMEOUT_SEC") else Sys.setenv(MERGEN_DB_LOGIN_TIMEOUT_SEC = eski), add = TRUE)
  if (!exists(".db_login_timeout_plan", mode = "function")) {
    source(file.path(resolve_repo_root_for_tests(), "R", "helpers_db_connection.R"),
           encoding = "UTF-8", local = globalenv())
  }
  # Yapılandırılmamışsa sürücü varsayılanı korunur (NA: timeout geçilmez).
  Sys.unsetenv("MERGEN_DB_LOGIN_TIMEOUT_SEC")
  testthat::expect_true(is.na(mergen_startup_chat_preview_globals("42")$startup_preview_login_timeout))
  # Yapılandırılmışsa skaler tamsayı olarak işçi sözleşmesine girer.
  Sys.setenv(MERGEN_DB_LOGIN_TIMEOUT_SEC = "7")
  g <- mergen_startup_chat_preview_globals("42", limit = NA_integer_)
  testthat::expect_identical(g$startup_preview_login_timeout, 7L)

  # İşçi tarafı: sınır dbConnect'e timeout olarak iletilir; NA'da hiç geçilmez.
  testthat::skip_if_not_installed("DBI")
  testthat::skip_if_not_installed("odbc")
  yakalanan <- list()
  testthat::local_mocked_bindings(
    dbConnect = function(drv, ...) { yakalanan[[length(yakalanan) + 1L]] <<- list(...); stop("baglanti_kurulmadi_test") },
    .package = "DBI"
  )
  testthat::expect_error(db_chat_preview_fetch_raw(42L, 6L, "DSN", "UTF-8", "UTF-8", login_timeout = 7L),
                         "baglanti_kurulmadi_test")
  testthat::expect_error(db_chat_preview_fetch_raw(42L, 6L, "DSN", "UTF-8", "UTF-8"), "baglanti_kurulmadi_test")
  testthat::expect_identical(yakalanan[[1]]$timeout, 7L)
  testthat::expect_null(yakalanan[[2]]$timeout)
})

testthat::test_that("yerel ad değişimi DB'nin daha yeni etkinlik bilgisini ezmez; yerelde etkinleşen söyleşi başa geçer", {
  .startup_preview_source_once()
  t0 <- as.POSIXct("2026-07-01 10:00:00", tz = "UTC")
  t1 <- as.POSIXct("2026-07-01 11:00:00", tz = "UTC")
  t2 <- as.POSIXct("2026-07-01 12:00:00", tz = "UTC")
  anlik <- list(
    "1" = list(title = "Bir", last_message_timestamp = t0, message_count = 2L),
    "2" = list(title = "İki", last_message_timestamp = t0, message_count = 2L)
  )
  # Başka sekme "1"e mesaj ekledi: DB daha yeni sayı/zaman döndürür.
  db <- list(
    "1" = list(title = "Bir", last_message_timestamp = t1, message_count = 4L),
    "2" = list(title = "İki", last_message_timestamp = t0, message_count = 2L),
    "3" = list(title = "Üç", last_message_timestamp = t0, message_count = 1L)
  )
  # Bu sekmede "1" yeniden adlandırıldı, "2"ye yeni mesaj yazıldı.
  simdiki <- anlik
  simdiki[["1"]]$title <- "Yeni ad çğış"
  simdiki[["2"]]$last_message_timestamp <- t2
  simdiki[["2"]]$message_count <- 3L
  birlesik <- mergen_saved_chats_merge_newer(db, anlik, simdiki)
  testthat::expect_identical(birlesik[["1"]]$title, "Yeni ad çğış")
  testthat::expect_identical(birlesik[["1"]]$message_count, 4L)
  testthat::expect_identical(birlesik[["1"]]$last_message_timestamp, t1)
  # Etkinliği yerelde ilerleyen söyleşi başa taşınır; ad değişimi sırayı değiştirmez.
  testthat::expect_identical(names(birlesik), c("2", "1", "3"))
  testthat::expect_identical(birlesik[["2"]]$message_count, 3L)
})

testthat::test_that("gönderimde var olup DB sonucunda olmayan (başka oturumda silinen) söyleşi yerel değişiklikle geri gelmez", {
  .startup_preview_source_once()
  anlik <- list("1" = list(title = "Bir", messages = NULL), "2" = list(title = "İki", messages = NULL))
  # Bu sekmede "1" ısıtıldı (mesajlar yüklendi) ve "9" yeni açıldı; başka sekme "1"i sildi.
  simdiki <- anlik
  simdiki[["1"]]$messages <- list(list(type = "user", content = "çğış"))
  simdiki[["9"]] <- list(title = "Yeni söyleşi")
  db <- list("2" = list(title = "İki", messages = NULL))
  birlesik <- mergen_saved_chats_merge_newer(db, anlik, simdiki)
  testthat::expect_null(birlesik[["1"]])
  testthat::expect_identical(names(birlesik), c("9", "2"))
})

testthat::test_that("yerelde mesaj eklenen söyleşide başka oturumun daha yeni etkinliği DB'den korunur", {
  .startup_preview_source_once()
  t0 <- as.POSIXct("2026-07-01 10:00:00", tz = "UTC")
  t1 <- as.POSIXct("2026-07-01 11:00:00", tz = "UTC")
  t2 <- as.POSIXct("2026-07-01 12:00:00", tz = "UTC")
  anlik <- list("1" = list(title = "Bir", last_message_timestamp = t0, message_count = 2L))
  simdiki <- list("1" = list(title = "Bir yeni ad", last_message_timestamp = t1, message_count = 3L))
  # Başka sekme daha sonra bir mesaj daha ekledi: DB sayısı/zamanı daha yeni.
  db <- list("1" = list(title = "Bir", last_message_timestamp = t2, message_count = 4L))
  birlesik <- mergen_saved_chats_merge_newer(db, anlik, simdiki)
  testthat::expect_identical(birlesik[["1"]]$message_count, 4L)
  testthat::expect_identical(birlesik[["1"]]$last_message_timestamp, t2)
  # İlgisiz yerel değişiklik (ad) korunur.
  testthat::expect_identical(birlesik[["1"]]$title, "Bir yeni ad")
})

testthat::test_that("gönderimden sonra açılıp silinen söyleşi arka plan tam listesiyle geri gelmez", {
  .startup_preview_source_once()
  anlik <- list("1" = list(title = "Bir"), "2" = list(title = "İki"))
  # "7" gönderimden SONRA açıldı, işçi sonucuna girdi, sonuç uygulanmadan silindi
  # (yeniden okuma başarısız: yetkili sürüm artmadı). Yerel durum anlık görüntüyle aynı.
  db <- list("7" = list(title = "Silinen çğış"), "1" = list(title = "Bir"), "2" = list(title = "İki"))
  birlesik <- mergen_saved_chats_merge_newer(db, anlik, anlik, silinenler = "7")
  testthat::expect_null(birlesik[["7"]], info = "aynı yerel durum kısayolu silineni geri getirmemeli")
  testthat::expect_identical(names(birlesik), c("1", "2"))
  # Yerelde başka değişiklik de varsa (yeni "9", ad değişimi) silinen yine dönmez.
  simdiki <- list("9" = list(title = "Yeni söyleşi"), "1" = list(title = "Yeni ad"), "2" = list(title = "İki"))
  birlesik <- mergen_saved_chats_merge_newer(db, anlik, simdiki, silinenler = "7")
  testthat::expect_null(birlesik[["7"]], info = "anlık görüntüde olmayan silinen söyleşi geri gelmemeli")
  testthat::expect_identical(names(birlesik), c("9", "1", "2"))
  testthat::expect_identical(birlesik[["1"]]$title, "Yeni ad")
  # İşaret yoksa davranış değişmez (DB'deki söyleşi korunur).
  testthat::expect_identical(names(mergen_saved_chats_merge_newer(db, anlik, anlik)), c("7", "1", "2"))
})

testthat::test_that("büyük tam liste dilimlerle biçimlendirilir; sonuç tek seferlik biçimlendirmeyle aynıdır", {
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_preview_source_once()
  n <- 1203L
  cerceve <- data.frame(
    ChatID = seq_len(n), ChatTitle = paste("Söyleşi çğış", seq_len(n)),
    CreateTimestamp = as.POSIXct("2026-07-01", tz = "UTC") + seq_len(n),
    MessageCount = rep(2L, n),
    LastMessageTimestamp = as.POSIXct("2026-07-02", tz = "UTC") + seq_len(n),
    stringsAsFactors = FALSE
  )
  beklenen <- db_chat_preview_format_frame(cerceve)
  sonuc <- NULL
  tur <- 0L
  later::with_temp_loop({
    # Dilimler oluşturulduğu (geçici) döngüye planlanır.
    p <- mergen_startup_chat_preview_format_staged(cerceve, dilim = 500L)
    testthat::expect_true(promises::is.promise(p))
    promises::then(p, function(v) sonuc <<- v)
    son <- Sys.time() + 5
    while (is.null(sonuc) && Sys.time() < son) { tur <- tur + 1L; later::run_now(0.02, all = FALSE) }
  })
  testthat::expect_identical(sonuc, beklenen)
  # 3 dilim: ilki hemen, kalan ikisi ayrı döngü turlarında (olay döngüsü arada serbest).
  testthat::expect_gte(tur, 2L)
  # Küçük liste (ön izleme) doğrudan biçimlendirilir.
  testthat::expect_identical(mergen_startup_chat_preview_format_staged(cerceve[1:6, ]),
                             db_chat_preview_format_frame(cerceve[1:6, ]))
})

testthat::test_that("asılı kalan işçi sorgusu süre bütçesinde hata verir, bağlantı kapanır, kilit beklemesi sınırlanır", {
  testthat::skip_if_not_installed("DBI")
  testthat::skip_if_not_installed("odbc")
  .startup_preview_source_once()
  yakalanan <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    dbConnect = function(drv, ...) { yakalanan$args <- list(...); structure(list(), class = "sahte_baglanti") },
    dbDisconnect = function(conn, ...) { yakalanan$kapandi <- TRUE; invisible(TRUE) },
    dbExecute = function(conn, statement, ...) { yakalanan$execute <- statement; 0L },
    dbGetQuery = function(conn, statement, ...) {
      # Asılı sorgu benzetimi: R kesme denetim noktalarında ilerleyen meşgul bekleme.
      bas <- Sys.time()
      while (as.numeric(difftime(Sys.time(), bas, units = "secs")) < 10) sum(seq_len(10))
      data.frame()
    },
    .package = "DBI"
  )
  bas <- Sys.time()
  testthat::expect_error(
    mergen_bounded_db_fetch_raw("SELECT 1", list(), dsn = "DSN", encoding = "UTF-8",
                                name_encoding = "UTF-8", query_timeout = 0.5),
    "elapsed time limit"
  )
  testthat::expect_lt(as.numeric(difftime(Sys.time(), bas, units = "secs")), 5)
  testthat::expect_true(isTRUE(yakalanan$kapandi))
  testthat::expect_true(isTRUE(yakalanan$args$interruptible))
  testthat::expect_identical(yakalanan$execute, "SET LOCK_TIMEOUT 500")
  # Süre sınırı çağrı sonrasına sızmaz.
  testthat::expect_silent({ t <- Sys.time(); while (as.numeric(difftime(Sys.time(), t, units = "secs")) < 0.8) sum(1:10) })

  # Bütçe verilmezse (eski çağıranlar) kesilebilirlik/kilit sınırı eklenmez.
  yakalanan$execute <- NULL
  testthat::local_mocked_bindings(dbGetQuery = function(conn, statement, ...) data.frame(x = 1L), .package = "DBI")
  mergen_bounded_db_fetch_raw("SELECT 1", list(), dsn = "DSN", encoding = "UTF-8", name_encoding = "UTF-8")
  testthat::expect_null(yakalanan$args$interruptible)
  testthat::expect_null(yakalanan$execute)
})
