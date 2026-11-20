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
  # SQL ana süreçte seçilir; tek fonksiyon global'i sınırlı okumadır.
  testthat::expect_setequal(
    names(g),
    c(
      "startup_preview_user_id",
      "startup_preview_limit",
      "startup_preview_sql",
      "startup_preview_dsn",
      "startup_preview_encoding",
      "startup_preview_login_timeout",
      "startup_preview_query_timeout",
      "startup_preview_name_encoding",
      "mergen_bounded_db_fetch_raw"
    )
  )
  testthat::expect_identical(g$startup_preview_user_id, 42L)
  testthat::expect_identical(g$startup_preview_limit, 6L)
  testthat::expect_identical(g$startup_preview_sql, db_chat_preview_query_sql(6L))
  testthat::expect_true(is.function(g$mergen_bounded_db_fetch_raw))

  # Değer globalleri skalerdır; fonksiyon dışı hiçbir öğe ortam/bağlantı taşımaz.
  deger_adlari <- setdiff(names(g), "mergen_bounded_db_fetch_raw")
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
  old_fetch <- get("mergen_bounded_db_fetch_raw", envir = helper_env, inherits = TRUE)

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

  assign("mergen_bounded_db_fetch_raw", function(sql, params, dsn, encoding, name_encoding,
                                                 login_timeout = NA_integer_, query_timeout = NA_real_) {
    rec$fetch_sql <- sql
    rec$fetch_params <- params
    rec$fetch_query_timeout <- query_timeout
    .startup_preview_fixture_frame()
  }, envir = helper_env)

  on.exit({
    assign("tracked_future_promise", old_tracked, envir = helper_env)
    assign("mergen_bounded_db_fetch_raw", old_fetch, envir = helper_env)
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
      "startup_preview_sql",
      "startup_preview_dsn",
      "startup_preview_encoding",
      "startup_preview_login_timeout",
      "startup_preview_query_timeout",
      "startup_preview_name_encoding",
      "mergen_bounded_db_fetch_raw"
    ))
  )
  testthat::expect_identical(rec$fetch_sql, db_chat_preview_query_sql(6L))
  testthat::expect_identical(rec$fetch_params, list(42L))
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

  # Geçersiz kullanıcıda görev bağlantı açmadan NULL döner (boş liste).
  rec$fetch_sql <- NULL
  p0 <- mergen_startup_chat_preview_promise(0L, limit = 6L, session_token = "oturum-1")
  got0 <- new.env(parent = emptyenv())
  promises::then(p0, onFulfilled = function(v) got0$value <- list(v))
  deadline <- Sys.time() + 5
  while (is.null(got0$value) && Sys.time() < deadline) later::run_now(timeoutSecs = 0.1)
  testthat::expect_null(rec$fetch_sql)
  testthat::expect_identical(got0$value[[1]], list())
})

testthat::test_that("tam liste modu (limit = NA) aynı dar sözleşmeyle özet SQL'i gönderir", {
  .startup_preview_source_once()

  g <- mergen_startup_chat_preview_globals("42", limit = NA_integer_)
  testthat::expect_setequal(names(g), names(mergen_startup_chat_preview_globals("42", limit = 6L)))
  testthat::expect_true(is.na(g$startup_preview_limit))
  testthat::expect_identical(g$startup_preview_sql, db_chat_list_summary_query_sql())
  # Ön izleme sözleşmesi tam liste SQL'ini taşımaz.
  testthat::expect_identical(mergen_startup_chat_preview_globals("42", limit = 6L)$startup_preview_sql,
                             db_chat_preview_query_sql(6L))
})

testthat::test_that("tam söyleşi listesi explicit modda 'startup_saved_chats' olarak gönderilir", {
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_preview_source_once()

  helper_env <- environment(mergen_startup_chat_preview_promise)
  old_tracked <- get("tracked_future_promise", envir = helper_env, inherits = TRUE)
  old_fetch <- get("mergen_bounded_db_fetch_raw", envir = helper_env, inherits = TRUE)
  rec <- new.env(parent = emptyenv())
  assign("tracked_future_promise", function(task_fn, task_type = "generic", session_token = NULL,
                                            meta = list(), globals = NULL,
                                            dependency_mode = c("auto", "explicit"), packages = NULL) {
    rec$task_type <- task_type
    rec$dependency_mode <- match.arg(dependency_mode)
    rec$global_names <- names(globals %||% list())
    promises::promise_resolve(task_fn())
  }, envir = helper_env)
  assign("mergen_bounded_db_fetch_raw", function(sql, params, dsn, encoding, name_encoding,
                                                 login_timeout = NA_integer_, query_timeout = NA_real_) {
    rec$fetch_sql <- sql
    .startup_preview_fixture_frame()
  }, envir = helper_env)
  on.exit({
    assign("tracked_future_promise", old_tracked, envir = helper_env)
    assign("mergen_bounded_db_fetch_raw", old_fetch, envir = helper_env)
  }, add = TRUE)

  p <- mergen_startup_chat_preview_promise(42L, limit = NA_integer_, session_token = "oturum-2")
  got <- new.env(parent = emptyenv())
  promises::then(p, onFulfilled = function(v) got$value <- v)
  deadline <- Sys.time() + 5
  while (is.null(got$value) && Sys.time() < deadline) later::run_now(timeoutSecs = 0.1)

  testthat::expect_identical(rec$task_type, "startup_saved_chats")
  testthat::expect_identical(rec$dependency_mode, "explicit")
  testthat::expect_true("startup_preview_sql" %in% rec$global_names)
  testthat::expect_identical(rec$fetch_sql, db_chat_list_summary_query_sql())
  # Biçim load_chats_from_db(include_messages = FALSE) ile aynıdır.
  testthat::expect_identical(names(got$value[["11"]]),
                             c("title", "messages", "timestamp", "last_message_timestamp", "message_count"))
})

# Açılış işçi görevi, uygulama fonksiyonları YÜKLÜ OLMAYAN temiz bir R
# sürecinde (yalnızca açık globals, globalenv'e kopyalama yok) çalışabilmelidir:
# sözleşme future/callr'ın örtük globalenv kopyalamasına dayanmaz; iç içe
# uygulama fonksiyonu araması böyle bir süreçte "could not find function" verirdi.
testthat::test_that("açılış ön izleme görevi uygulama kodu yüklü olmayan temiz süreçte çalışır", {
  testthat::skip_if_not_installed("callr")
  testthat::skip_if_not_installed("DBI")
  testthat::skip_if_not_installed("odbc")
  .startup_preview_source_once()

  helper_env <- environment(mergen_startup_chat_preview_promise)
  old_tracked <- get("tracked_future_promise", envir = helper_env, inherits = TRUE)
  yakalanan <- new.env(parent = emptyenv())
  assign("tracked_future_promise", function(task_fn, globals = NULL, packages = NULL, ...) {
    # Gerçek açık sözleşme serileştiricisiyle işçi yükü üretilir.
    yakalanan$yuk <- c(yakalanan$yuk, list(worker_monitor_serialize_explicit_task(task_fn, globals, packages)))
    promises::promise_resolve(NULL)
  }, envir = helper_env)
  on.exit(assign("tracked_future_promise", old_tracked, envir = helper_env), add = TRUE)

  # Yapılandırılmış bir DSN'e (geliştirici/üretim) asla gidilmez: globaller
  # kasıtlı olarak var olmayan bir DSN ile kurulur.
  withr::local_envvar(DB_DSN = "mergen_test_olmayan_dsn")
  mergen_startup_chat_preview_promise(0L, limit = 6L)
  mergen_startup_chat_preview_promise(42L, limit = NA_integer_)
  calistir <- function(yuk) callr::r(function(yuk) {
    # Çocuk süreçte DB sınırı (DBI::dbConnect) taklit edilir: serileştirilmiş
    # görev bağlantı çağrısına ulaşırsa benzersiz bir koşul yükselir.
    loadNamespace("DBI")
    utils::assignInNamespace("dbConnect", function(drv, ...) {
      stop(sprintf("sahte_dbconnect_cagrildi dsn=%s", list(...)$dsn))
    }, ns = "DBI")
    # globalenv'e hiçbir şey kopyalanmaz: yalnızca görev ortamı görülür.
    tryCatch(list(deger = unserialize(yuk)()), error = function(e) list(hata = conditionMessage(e)))
  }, args = list(yuk = yuk))
  # Geçersiz kullanıcı: bağlantı (taklit) hiç çağrılmadan NULL.
  testthat::expect_identical(calistir(yakalanan$yuk[[1]]), list(deger = NULL))
  # Geçerli kullanıcı: gerçek serileştirilmiş görev ve SQL hazırlığı bağlantı
  # çağrısına ulaşır; hiçbir uygulama fonksiyonu eksik kalmaz.
  sonuc <- calistir(yakalanan$yuk[[2]])
  testthat::expect_identical(sonuc$hata, "sahte_dbconnect_cagrildi dsn=mergen_test_olmayan_dsn")
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
  testthat::expect_identical(g$startup_preview_sql, db_chat_preview_query_sql(6L))
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

  # Bütçeli okumada bağlantı denemesi bütçeyi aşamaz: login sınırı yoksa bütçe
  # iletilir; yapılandırılmış sınır bütçeden büyükse bütçeye indirilir.
  testthat::expect_error(db_chat_preview_fetch_raw(42L, 6L, "DSN", "UTF-8", "UTF-8", query_timeout = 5),
                         "baglanti_kurulmadi_test")
  testthat::expect_error(db_chat_preview_fetch_raw(42L, 6L, "DSN", "UTF-8", "UTF-8", login_timeout = 7L,
                                                   query_timeout = 4.2), "baglanti_kurulmadi_test")
  testthat::expect_error(db_chat_preview_fetch_raw(42L, 6L, "DSN", "UTF-8", "UTF-8", login_timeout = 3L,
                                                   query_timeout = 5), "baglanti_kurulmadi_test")
  testthat::expect_identical(yakalanan[[3]]$timeout, 5L)
  testthat::expect_identical(yakalanan[[4]]$timeout, 5L)
  testthat::expect_identical(yakalanan[[5]]$timeout, 3L)
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

testthat::test_that("gönderimden sonra açılan söyleşide başka oturumun daha yeni DB etkinliği korunur", {
  .startup_preview_source_once()
  t1 <- as.POSIXct("2026-07-01 11:00:00", tz = "UTC")
  t2 <- as.POSIXct("2026-07-01 12:00:00", tz = "UTC")
  anlik <- list("1" = list(title = "Bir", last_message_timestamp = t1, message_count = 2L))
  # "7" gönderimden SONRA bu sekmede açıldı (anlık görüntüde yok); başka sekme
  # DB okumasından önce ona bir mesaj daha ekledi.
  simdiki <- c(list("7" = list(title = "Yeni çğış", last_message_timestamp = t1, message_count = 1L)), anlik)
  db <- list("7" = list(title = "Yeni çğış", last_message_timestamp = t2, message_count = 2L),
             "1" = list(title = "Bir", last_message_timestamp = t1, message_count = 2L))
  birlesik <- mergen_saved_chats_merge_newer(db, anlik, simdiki)
  testthat::expect_identical(birlesik[["7"]]$message_count, 2L)
  testthat::expect_identical(birlesik[["7"]]$last_message_timestamp, t2)
  testthat::expect_identical(birlesik[["7"]]$title, "Yeni çğış")
  # DB daha yeni değilse yerel girdi aynen uygulanır (ör. yerel yeniden adlandırma).
  simdiki[["7"]]$title <- "Yerel ad"
  db[["7"]]$message_count <- 1L
  db[["7"]]$last_message_timestamp <- t1
  birlesik <- mergen_saved_chats_merge_newer(db, anlik, simdiki)
  testthat::expect_identical(birlesik[["7"]], simdiki[["7"]])
  testthat::expect_identical(names(birlesik), c("7", "1"))
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
  # Biçimlendirici çağrıları (satır sayısı) kaydedilir: kanıt döngü turu sayısı
  # değil, her turda gerçekten kaç satırın biçimlendirildiğidir.
  asil_bicimlendirici <- db_chat_preview_format_frame
  bicimlenen <- integer()
  assign("db_chat_preview_format_frame", function(frame) {
    bicimlenen <<- c(bicimlenen, nrow(frame))
    asil_bicimlendirici(frame)
  }, envir = globalenv())
  on.exit(assign("db_chat_preview_format_frame", asil_bicimlendirici, envir = globalenv()), add = TRUE)
  sonuc <- NULL
  later::with_temp_loop({
    # Dilimler oluşturulduğu (geçici) döngüye planlanır.
    p <- mergen_startup_chat_preview_format_staged(cerceve, dilim = 500L)
    testthat::expect_true(promises::is.promise(p))
    # Döngü ilerlemeden yalnızca ilk dilim biçimlendirilmiştir.
    testthat::expect_identical(bicimlenen, 500L)
    promises::then(p, function(v) sonuc <<- v)
    son <- Sys.time() + 5
    while (is.null(sonuc) && Sys.time() < son) {
      once <- length(bicimlenen)
      later::run_now(0.02, all = FALSE)
      # Her döngü turu en çok bir dilim biçimlendirir.
      testthat::expect_lte(length(bicimlenen) - once, 1L)
    }
  })
  testthat::expect_identical(sonuc, beklenen)
  # Kalan 500 ve 203 satır ayrı turlarda biçimlendirildi.
  testthat::expect_identical(bicimlenen, c(500L, 500L, 203L))
  # Küçük liste (ön izleme) doğrudan biçimlendirilir.
  testthat::expect_identical(mergen_startup_chat_preview_format_staged(cerceve[1:6, ]),
                             db_chat_preview_format_frame(cerceve[1:6, ]))
})

# Bütçeli okuma satırları parçalı getirir (dbSendQuery + dbFetch). Bu yardımcı
# DB sınırını taklit eder: uret(statement) ilk dbFetch çağrısında (R kesme
# denetim noktalarıyla) çalışır; sonuç kümesi temizlenince kaydedilir.
.sahte_parcali_sorgu <- function(uret, kayit = new.env(parent = emptyenv())) {
  list(
    dbSendQuery = function(conn, statement, ...) {
      kayit$sql <- statement
      kayit$bitti <- FALSE
      structure(list(), class = "sahte_sonuc")
    },
    dbFetch = function(res, n = -1, ...) {
      kayit$getirme <- c(kayit$getirme, n)
      if (isTRUE(kayit$bitti)) return(data.frame())
      kayit$bitti <- TRUE
      uret(kayit$sql)
    },
    dbHasCompleted = function(res, ...) isTRUE(kayit$bitti),
    dbClearResult = function(res, ...) { kayit$temizlendi <- TRUE; invisible(TRUE) }
  )
}
.parcali_sorgu_bagla <- function(uret, kayit = new.env(parent = emptyenv()), env = parent.frame()) {
  do.call(testthat::local_mocked_bindings,
          c(.sahte_parcali_sorgu(uret, kayit), list(.package = "DBI", .env = env)))
  invisible(kayit)
}

testthat::test_that("asılı kalan işçi sorgusu süre bütçesinde hata verir, bağlantı kapanır, kilit beklemesi sınırlanır", {
  testthat::skip_if_not_installed("DBI")
  testthat::skip_if_not_installed("odbc")
  .startup_preview_source_once()
  yakalanan <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    dbConnect = function(drv, ...) { yakalanan$args <- list(...); structure(list(), class = "sahte_baglanti") },
    dbDisconnect = function(conn, ...) { yakalanan$kapandi <- TRUE; invisible(TRUE) },
    dbExecute = function(conn, statement, ...) { yakalanan$execute <- statement; 0L },
    .package = "DBI"
  )
  sorgu <- .parcali_sorgu_bagla(function(sql) {
    # Asılı sorgu benzetimi: R kesme denetim noktalarında ilerleyen meşgul bekleme.
    yakalanan$sorgu_basladi <- TRUE
    bas <- Sys.time()
    while (as.numeric(difftime(Sys.time(), bas, units = "secs")) < 10) sum(seq_len(10))
    yakalanan$sorgu_bitti <- TRUE
    data.frame()
  })
  bas <- Sys.time()
  # Tanı iletisi R diline göre çevrilir; iddia ileti metnine değil davranışa
  # bakar: sorgu başladı, bitmeden kesildi ve süre bütçesine yakın hata verdi.
  testthat::expect_error(
    mergen_bounded_db_fetch_raw("SELECT 1", list(), dsn = "DSN", encoding = "UTF-8",
                                name_encoding = "UTF-8", query_timeout = 0.5),
    class = "error"
  )
  testthat::expect_lt(as.numeric(difftime(Sys.time(), bas, units = "secs")), 5)
  testthat::expect_true(isTRUE(yakalanan$sorgu_basladi))
  testthat::expect_null(yakalanan$sorgu_bitti)
  testthat::expect_true(isTRUE(yakalanan$kapandi))
  # Kesilen getirmenin sonuç kümesi de temizlenir.
  testthat::expect_true(isTRUE(sorgu$temizlendi))
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

testthat::test_that("LOCK_TIMEOUT kurulumu süre bütçesini tüketirse ana sorgu sınırsız çalışmaz", {
  testthat::skip_if_not_installed("DBI")
  testthat::skip_if_not_installed("odbc")
  .startup_preview_source_once()
  yakalanan <- new.env(parent = emptyenv())
  mesgul <- function(sn) {
    bas <- Sys.time()
    while (as.numeric(difftime(Sys.time(), bas, units = "secs")) < sn) sum(seq_len(10))
  }
  testthat::local_mocked_bindings(
    dbConnect = function(drv, ...) structure(list(), class = "sahte_baglanti"),
    dbDisconnect = function(conn, ...) { yakalanan$kapandi <- TRUE; invisible(TRUE) },
    # Kurulum deyimi bütçeden uzun asılı kalır; R sınırı siler ve hata verir.
    dbExecute = function(conn, statement, ...) { mesgul(10); 0L },
    .package = "DBI"
  )
  .parcali_sorgu_bagla(function(sql) {
    yakalanan$sorgu_basladi <- TRUE
    mesgul(3)
    yakalanan$sorgu_bitti <- TRUE
    data.frame(x = 1L)
  })
  bas <- Sys.time()
  testthat::expect_error(
    mergen_bounded_db_fetch_raw("SELECT 1", list(), dsn = "DSN", encoding = "UTF-8",
                                name_encoding = "UTF-8", query_timeout = 0.4),
    class = "error"
  )
  # Kusurlu sürümde kurulum hatası yutulur ve sorgu 3 sn sınırsız koşardı.
  testthat::expect_lt(as.numeric(difftime(Sys.time(), bas, units = "secs")), 2.5)
  testthat::expect_null(yakalanan$sorgu_bitti)
  testthat::expect_true(isTRUE(yakalanan$kapandi))
  # Süre sınırı çağrı sonrasına sızmaz.
  testthat::expect_silent(mesgul(0.6))
})

testthat::test_that("zaman aşımı olmayan LOCK_TIMEOUT kurulum hatası ölümcül değildir, sorgu kalan bütçeyle sınırlı koşar", {
  testthat::skip_if_not_installed("DBI")
  testthat::skip_if_not_installed("odbc")
  .startup_preview_source_once()
  yakalanan <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    dbConnect = function(drv, ...) structure(list(), class = "sahte_baglanti"),
    dbDisconnect = function(conn, ...) { yakalanan$kapandi <- TRUE; invisible(TRUE) },
    dbExecute = function(conn, statement, ...) stop("sürücü SET deyimini desteklemiyor (test)"),
    .package = "DBI"
  )
  .parcali_sorgu_bagla(function(sql) data.frame(ChatID = 1L))
  veri <- mergen_bounded_db_fetch_raw("SELECT 1", list(), dsn = "DSN", encoding = "UTF-8",
                                      name_encoding = "UTF-8", query_timeout = 5)
  testthat::expect_identical(veri$ChatID, 1L)
  testthat::expect_true(isTRUE(yakalanan$kapandi))

  # Kurulum hatasından sonra sorgu TAZE değil KALAN bütçeyle sınırlıdır: kurulum
  # 0,35 sn tüketip hata verir; 0,5 sn süren sorgu 0,6 sn'lik taze bütçeyle
  # tamamlanırdı, kalan (~0,25 sn) bütçeyle kesilir.
  mesgul <- function(sn) { b <- Sys.time(); while (as.numeric(difftime(Sys.time(), b, units = "secs")) < sn) sum(seq_len(10)) }
  testthat::local_mocked_bindings(
    dbExecute = function(conn, statement, ...) { mesgul(0.35); stop("sürücü SET deyimini desteklemiyor (test)") },
    .package = "DBI"
  )
  yakalanan$sorgu_basladi <- NULL
  .parcali_sorgu_bagla(function(sql) {
    yakalanan$sorgu_basladi <- TRUE
    mesgul(0.5)
    yakalanan$sorgu_bitti <- TRUE
    data.frame()
  })
  bas <- Sys.time()
  testthat::expect_error(
    mergen_bounded_db_fetch_raw("SELECT 1", list(), dsn = "DSN", encoding = "UTF-8",
                                name_encoding = "UTF-8", query_timeout = 0.6),
    class = "error"
  )
  # Sorgu başladı (erken ret değil) ama kalan bütçede kesildi.
  testthat::expect_true(isTRUE(yakalanan$sorgu_basladi))
  testthat::expect_null(yakalanan$sorgu_bitti)
  testthat::expect_lt(as.numeric(difftime(Sys.time(), bas, units = "secs")), 0.8)
})

# Başarılı bütçeli okuma sonrasında da süre sınırı aynı işçi sürecindeki
# ilgisiz işe sızmaz. (Hata yolundaki denetimler bunu kanıtlamaz: R süre
# sınırı dolduğunda sınırı kendisi siler.)
testthat::test_that("başarılı bütçeli okumadan sonra süre sınırı sonraki işe sızmaz", {
  testthat::skip_if_not_installed("DBI")
  testthat::skip_if_not_installed("odbc")
  .startup_preview_source_once()
  testthat::local_mocked_bindings(
    dbConnect = function(drv, ...) structure(list(), class = "sahte_baglanti"),
    dbDisconnect = function(conn, ...) invisible(TRUE),
    dbExecute = function(conn, statement, ...) 0L,
    .package = "DBI"
  )
  .parcali_sorgu_bagla(function(sql) data.frame(x = 1L))
  veri <- mergen_bounded_db_fetch_raw("SELECT 1", list(), dsn = "DSN", encoding = "UTF-8",
                                      name_encoding = "UTF-8", query_timeout = 0.3)
  testthat::expect_identical(veri$x, 1L)
  # Bütçeden (0,3 sn) uzun ilgisiz iş hata vermeden tamamlanır.
  testthat::expect_silent({
    t <- Sys.time()
    while (as.numeric(difftime(Sys.time(), t, units = "secs")) < 0.8) sum(1:10)
  })
})

# odbc 1.7'de parametreli (bind) yürütme kesilemez; bütçeli okuma tam sayı
# parametreleri güvenli SQL sabitine çevirip kesilebilir doğrudan yürütmeyi
# kullanır. Bütçesiz okuma parametre bağlamayı korur.
testthat::test_that("bütçeli okuma tam sayı parametreleri doğrudan yürütmeye çevirir, diğer türleri reddeder", {
  testthat::skip_if_not_installed("DBI")
  testthat::skip_if_not_installed("odbc")
  .startup_preview_source_once()
  yakalanan <- new.env(parent = emptyenv())
  yakalanan$baglanti <- 0L
  testthat::local_mocked_bindings(
    dbConnect = function(drv, ...) {
      yakalanan$baglanti <- yakalanan$baglanti + 1L
      yakalanan$args <- list(...)
      structure(list(), class = "sahte_baglanti")
    },
    dbDisconnect = function(conn, ...) invisible(TRUE),
    dbExecute = function(conn, statement, ...) 0L,
    # Bütçesiz yol parametre bağlamayı korur (dbGetQuery); bütçeli yol parçalı getirir.
    dbGetQuery = function(conn, statement, params = NULL, ...) {
      yakalanan$sql <- statement
      yakalanan$params <- params
      data.frame(x = 1L)
    },
    .package = "DBI"
  )
  .parcali_sorgu_bagla(function(sql) {
    yakalanan$sql <- sql
    yakalanan$params <- NULL
    data.frame(x = 1L)
  })
  sql <- "SELECT c.ChatID FROM MB_Chats c WHERE c.ChatID IN (?, ?) AND c.UserID = ? AND c.ChatTitle <> '?'"
  mergen_bounded_db_fetch_raw(sql, list(5L, 6, 42L), dsn = "DSN", encoding = "UTF-8",
                              name_encoding = "UTF-8", query_timeout = 5)
  testthat::expect_null(yakalanan$params)
  testthat::expect_identical(
    yakalanan$sql,
    "SELECT c.ChatID FROM MB_Chats c WHERE c.ChatID IN (5, 6) AND c.UserID = 42 AND c.ChatTitle <> '?'"
  )
  testthat::expect_true(isTRUE(yakalanan$args$interruptible))

  # Tam sayı olmayan parametre bütçesiz yürütülmez; bağlantı hiç açılmaz.
  onceki <- yakalanan$baglanti
  for (bozuk in list(list("42"), list(4.5), list(NA_integer_), list(c(1L, 2L)), list(1e12))) {
    testthat::expect_error(
      mergen_bounded_db_fetch_raw(sql, bozuk, dsn = "DSN", encoding = "UTF-8",
                                  name_encoding = "UTF-8", query_timeout = 5),
      "tam sayı", info = paste(deparse(bozuk), collapse = "")
    )
  }
  testthat::expect_identical(yakalanan$baglanti, onceki)

  # Bütçe yoksa parametre bağlama aynen korunur.
  mergen_bounded_db_fetch_raw("SELECT 1 WHERE 1 = ?", list(1L), dsn = "DSN", encoding = "UTF-8",
                              name_encoding = "UTF-8")
  testthat::expect_identical(yakalanan$params, list(1L))
  testthat::expect_identical(yakalanan$sql, "SELECT 1 WHERE 1 = ?")
})

testthat::test_that("gönderimden sonra açılan söyleşi: DB etkinlik zamanı korunur, yerel ilerleme sırayı değiştirir, eşit sayı yeniden okuma işaretler", {
  .startup_preview_source_once()
  t0 <- as.POSIXct("2026-07-01 09:00:00", tz = "UTC")
  t1 <- as.POSIXct("2026-07-01 11:00:00", tz = "UTC")
  t2 <- as.POSIXct("2026-07-01 12:00:00", tz = "UTC")
  anlik <- list("2" = list(title = "İki", last_message_timestamp = t1, message_count = 1L))
  db <- list("2" = list(title = "İki", last_message_timestamp = t1, message_count = 1L),
             "5" = list(title = "Eski", last_message_timestamp = t0, message_count = 2L))
  # İçerik aramasından açılan eski söyleşi: detay okuyucu etkinlik zamanı taşımaz.
  mesajlar <- list(list(type = "user", content = "çğış"), list(type = "ai", content = "yanıt"))
  hidrate <- c(anlik, list("5" = list(title = "Eski", messages = mesajlar, message_count = 2L)))
  birlesik <- mergen_saved_chats_merge_newer(db, anlik, hidrate)
  testthat::expect_identical(birlesik[["5"]]$last_message_timestamp, t0)
  testthat::expect_identical(birlesik[["5"]]$messages, mesajlar)
  testthat::expect_null(birlesik[["5"]]$transkript_yenile)
  testthat::expect_identical(names(birlesik), c("2", "5"))
  # Yerelde yeni mesaj (sayı DB'yi geçti): en yeni etkinlik başa taşınır.
  ileride <- hidrate
  ileride[["5"]]$messages <- c(mesajlar, list(list(type = "user", content = "yeni")))
  ileride[["5"]]$message_count <- 3L
  ileride[["5"]]$last_message_timestamp <- t2
  birlesik <- mergen_saved_chats_merge_newer(db, anlik, ileride)
  testthat::expect_identical(names(birlesik), c("5", "2"))
  testthat::expect_identical(birlesik[["5"]]$message_count, 3L)
  testthat::expect_identical(birlesik[["5"]]$last_message_timestamp, t2)
  # DB daha yeniyse DB'nin etkinliği kalır.
  db_yeni <- db
  db_yeni[["5"]]$message_count <- 4L
  db_yeni[["5"]]$last_message_timestamp <- t2 + 60
  birlesik <- mergen_saved_chats_merge_newer(db_yeni, anlik, ileride)
  testthat::expect_identical(birlesik[["5"]]$message_count, 4L)
  testthat::expect_identical(names(birlesik), c("2", "5"))
  # Eşit sayı ama farklı son mesaj zamanı: önbellek korunur, yeniden açılışta okuma istenir.
  db_esit <- db
  db_esit[["5"]]$message_count <- 3L
  db_esit[["5"]]$last_message_timestamp <- t1 + 30
  birlesik <- mergen_saved_chats_merge_newer(db_esit, anlik, ileride)
  testthat::expect_true(isTRUE(birlesik[["5"]]$transkript_yenile))
  testthat::expect_identical(length(birlesik[["5"]]$messages), 3L)
})

testthat::test_that("anlık görüntüdeki söyleşide hem DB hem yerel etkinlik ilerlediyse transkript yeniden okunmak üzere işaretlenir", {
  .startup_preview_source_once()
  t0 <- as.POSIXct("2026-07-01 10:00:00", tz = "UTC")
  iki <- list(list(type = "user", content = "a"), list(type = "ai", content = "b"))
  anlik <- list("1" = list(title = "Bir", messages = iki, last_message_timestamp = t0, message_count = 2L))
  # Başka sekme X'i, bu sekme Y'yi kaydetti: sayılar eşit (3) ama içerik farklı.
  simdiki <- anlik
  simdiki[["1"]]$messages <- c(iki, list(list(type = "user", content = "Y")))
  simdiki[["1"]]$message_count <- 3L
  simdiki[["1"]]$last_message_timestamp <- t0 + 120
  db <- list("1" = list(title = "Bir", last_message_timestamp = t0 + 60, message_count = 3L))
  birlesik <- mergen_saved_chats_merge_newer(db, anlik, simdiki)
  testthat::expect_true(isTRUE(birlesik[["1"]]$transkript_yenile))
  # Yalnızca yerel ilerlediyse (DB okuması eski) işaret konmaz.
  db_eski <- list("1" = list(title = "Bir", last_message_timestamp = t0, message_count = 2L))
  testthat::expect_null(mergen_saved_chats_merge_newer(db_eski, anlik, simdiki)[["1"]]$transkript_yenile)
})

testthat::test_that("bütçeli okuma satırları parçalı getirir; süre sınırı parçalar arasında denetlenir", {
  testthat::skip_if_not_installed("DBI")
  testthat::skip_if_not_installed("odbc")
  .startup_preview_source_once()
  kayit <- new.env(parent = emptyenv())
  parca_sayisi <- 3L
  mesgul <- function(sn) { bas <- Sys.time(); while (as.numeric(difftime(Sys.time(), bas, units = "secs")) < sn) sum(1:10) }
  bekleme <- 0
  testthat::local_mocked_bindings(
    dbConnect = function(drv, ...) structure(list(), class = "sahte_baglanti"),
    dbDisconnect = function(conn, ...) invisible(TRUE),
    dbExecute = function(conn, statement, ...) 0L,
    dbSendQuery = function(conn, statement, ...) { kayit$verilen <- 0L; structure(list(), class = "sahte_sonuc") },
    # Her getirme çağrısı ayrı bir parça döndürür (yerel getirme benzetimi).
    dbFetch = function(res, n = -1, ...) {
      kayit$n <- c(kayit$n, n)
      kayit$verilen <- kayit$verilen + 1L
      mesgul(bekleme)
      data.frame(ChatID = kayit$verilen)
    },
    dbHasCompleted = function(res, ...) kayit$verilen >= parca_sayisi,
    dbClearResult = function(res, ...) { kayit$temizlendi <- TRUE; invisible(TRUE) },
    .package = "DBI"
  )
  veri <- mergen_bounded_db_fetch_raw("SELECT 1", list(), dsn = "DSN", encoding = "UTF-8",
                                      name_encoding = "UTF-8", query_timeout = 5)
  testthat::expect_identical(veri$ChatID, 1:3)
  testthat::expect_true(all(kayit$n == 1000L))
  testthat::expect_true(isTRUE(kayit$temizlendi))
  # Her parça 0,3 sn sürer; 0,5 sn bütçe üçüncü parçadan önce aşılır ve okuma durur.
  kayit$n <- NULL
  kayit$temizlendi <- NULL
  bekleme <- 0.3
  bas <- Sys.time()
  testthat::expect_error(
    mergen_bounded_db_fetch_raw("SELECT 1", list(), dsn = "DSN", encoding = "UTF-8",
                                name_encoding = "UTF-8", query_timeout = 0.5),
    class = "error"
  )
  testthat::expect_lt(as.numeric(difftime(Sys.time(), bas, units = "secs")), 0.95)
  testthat::expect_lt(kayit$verilen, parca_sayisi)
  testthat::expect_true(isTRUE(kayit$temizlendi))
})

testthat::test_that("hidrate edilen söyleşi daha yeni DB başlığını ezmez, silinmişse geri gelmez ve eşit etkinlikte DB sırasını korur", {
  t1 <- as.POSIXct("2026-11-18 10:00:00", tz = "UTC")
  t2 <- as.POSIXct("2026-11-18 11:00:00", tz = "UTC")
  t3 <- as.POSIXct("2026-11-18 12:00:00", tz = "UTC")

  # 1) Başka sekmede yeniden adlandırılan ve burada yalnızca hidrate edilen söyleşi:
  #    DB başlığı korunur, hidrate edilmiş mesajlar da saklanır.
  anlik <- list("1" = list(title = "İlk", message_count = 2L, last_message_timestamp = t1))
  guncel <- list(
    "1" = list(title = "İlk", message_count = 2L, last_message_timestamp = t1),
    "9" = list(title = "Eski Başlık", messages = list(list(type = "user", content = "m")),
               message_count = 1L, last_message_timestamp = t1, hidrate_edildi = TRUE),
    "10" = list(title = "Silinmiş Hidrate", messages = list(list(type = "user", content = "x")),
                message_count = 1L, last_message_timestamp = t1, hidrate_edildi = TRUE),
    "11" = list(title = "Yerelde Yeni Oluşturulan", messages = list(list(type = "user", content = "y")),
                message_count = 1L, last_message_timestamp = t3)
  )
  db_liste <- list(
    "2" = list(title = "Daha Yeni", message_count = 5L, last_message_timestamp = t3),
    "9" = list(title = "Yeni DB Başlığı", message_count = 1L, last_message_timestamp = t1),
    "1" = list(title = "İlk", message_count = 2L, last_message_timestamp = t1)
  )
  birlesik <- mergen_saved_chats_merge_newer(db_liste, anlik, guncel)
  testthat::expect_identical(birlesik[["9"]]$title, "Yeni DB Başlığı")
  testthat::expect_length(birlesik[["9"]]$messages, 1L)
  testthat::expect_false("10" %in% names(birlesik))
  testthat::expect_true("11" %in% names(birlesik))

  # 2) DB yerel güncellemeyi zaten içeriyorsa (eşit sayı ve eşit zaman) DB sırası korunur.
  anlik2 <- list("5" = list(title = "Beş", message_count = 1L, last_message_timestamp = t1))
  guncel2 <- list("5" = list(title = "Beş", message_count = 2L, last_message_timestamp = t2))
  db2 <- list(
    "8" = list(title = "Sekiz", message_count = 3L, last_message_timestamp = t3),
    "5" = list(title = "Beş", message_count = 2L, last_message_timestamp = t2)
  )
  birlesik2 <- mergen_saved_chats_merge_newer(db2, anlik2, guncel2)
  testthat::expect_identical(names(birlesik2), c("8", "5"))
})

testthat::test_that("aşamalı biçimlendirme istek geçersizleşince kalan dilimleri işlemeden durur", {
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  cerceve <- data.frame(
    ChatID = 1:1200,
    ChatTitle = paste("Söyleşi", 1:1200),
    CreateTimestamp = rep(as.POSIXct("2026-11-18 10:00:00", tz = "UTC"), 1200),
    LastMessageTimestamp = rep(as.POSIXct("2026-11-18 10:00:00", tz = "UTC"), 1200),
    MessageCount = rep(1L, 1200),
    stringsAsFactors = FALSE
  )
  gecerli <- TRUE
  dilim_sayisi <- 0L
  eski_fmt <- get("db_chat_preview_format_frame", envir = globalenv())
  on.exit(assign("db_chat_preview_format_frame", eski_fmt, envir = globalenv()), add = TRUE)
  assign("db_chat_preview_format_frame", function(df) {
    dilim_sayisi <<- dilim_sayisi + 1L
    gecerli <<- FALSE
    eski_fmt(df)
  }, envir = globalenv())
  sonuc <- "bekliyor"
  loop <- later::create_loop(parent = NULL)
  on.exit(later::destroy_loop(loop), add = TRUE)
  later::with_loop(loop, {
    p <- mergen_startup_chat_preview_format_staged(cerceve, dilim = 500L, gecerli_mi = function() gecerli)
    promises::then(p, onFulfilled = function(v) sonuc <<- v)
    for (i in 1:10) later::run_now(timeoutSecs = 0.05, loop = loop)
  })
  testthat::expect_null(sonuc)
  testthat::expect_identical(dilim_sayisi, 1L)
})

testthat::test_that("mergen_startup_async_worker_ready sequential planda FALSE döner", {
  testthat::skip_if_not_installed("future")
  eski_plan <- future::plan(future::sequential)
  on.exit(future::plan(eski_plan), add = TRUE)
  testthat::expect_false(mergen_startup_async_worker_ready())
})

testthat::test_that("yerel etkinlik artışı daha yeni DB söyleşisinin önüne geçip 60. söyleşiyi dışlamaz", {
  base_ts <- as.POSIXct("2026-11-18 10:00:00", tz = "UTC")
  db_chats <- stats::setNames(lapply(1:61, function(i) {
    list(title = paste("Söyleşi", i), message_count = 2L,
         last_message_timestamp = base_ts + (62 - i) * 60)
  }), as.character(1:61))
  # 61. söyleşi en eski (ts = base + 60 sn); yerelde +10 sn ilerler (hâlâ 1..60'tan eski).
  dispatch_snapshot <- db_chats
  current <- db_chats
  current[["61"]]$message_count <- 3L
  current[["61"]]$last_message_timestamp <- base_ts + 70
  birlesik <- mergen_saved_chats_merge_newer(db_chats, dispatch_snapshot, current)
  ilk_60 <- utils::head(names(birlesik), 60L)
  testthat::expect_true("60" %in% ilk_60)
  testthat::expect_false("61" %in% ilk_60)
  testthat::expect_identical(names(birlesik)[61L], "61")
})

testthat::test_that("mergen_chat_reconcile_hydrated_detail kayıtsız yerel mesajları DB satırlarıyla uzlaştırır", {
  fmt_env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_chat_message_formatting.R"),
         encoding = "UTF-8", local = fmt_env)
  onceki <- list(
    title = "Eski Başlık",
    last_message_timestamp = as.POSIXct("2026-11-18 10:05:00", tz = "UTC"),
    transkript_yenile = TRUE,
    messages = list(
      list(id = "10", db_id = 10L, type = "user", content = "kayıtlı"),
      list(id = "msg_yerel_1", db_id = NULL, type = "user", content = "kaydedilemeyen taslak")
    ),
    message_count = 2L
  )
  detail <- list(
    title = "Güncel Başlık",
    timestamp = as.POSIXct("2026-11-18 10:00:00", tz = "UTC"),
    last_message_timestamp = NULL,
    messages = list(
      list(id = "10", db_id = 10L, type = "user", content = "kayıtlı"),
      list(id = "11", db_id = 11L, type = "ai", content = "diğer oturum yanıtı")
    ),
    message_count = 2L
  )
  sonuc <- fmt_env$mergen_chat_reconcile_hydrated_detail(detail, onceki)
  testthat::expect_identical(length(sonuc$messages), 3L)
  testthat::expect_identical(sonuc$message_count, 3L)
  testthat::expect_identical(sonuc$messages[[3]]$id, "msg_yerel_1")
  testthat::expect_true(isTRUE(sonuc$hidrate_edildi))
  testthat::expect_null(sonuc$transkript_yenile)
  testthat::expect_identical(sonuc$last_message_timestamp, onceki$last_message_timestamp)
})
