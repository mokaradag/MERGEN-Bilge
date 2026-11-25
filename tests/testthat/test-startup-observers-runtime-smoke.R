# ==============================================================================
# Dosya Yolu: tests/testthat/test-startup-observers-runtime-smoke.R
# Açıklama: startupObserversInit() davranışsal runtime smoke testleri.
#           1) Geçersiz/placeholder kullanıcı kimliği (0) ile kayıtlı sohbet
#              yüklemesinin ATLANMASI (SSO kimlik kayması koruması) ve
#              karşılama ekranının başlangıçta render edilmesi.
#           2) Başlangıç şeridi yarış düzeltmesi: şerit çözülmeden hiçbir
#              kayıtlı sohbet DB çağrısı başlamaz; Hızlı Başlangıç'ta tam
#              liste açılışın kritik yolunda YÜKLENMEZ ve ön izleme kritik yolu
#              bloklamaz; ön izleme uygulanınca tam liste arka planda bir kez
#              yüklenir, yerel durum değiştiyse Kayıtlı Söyleşiler/Geçmiş ilk
#              açıldığında tembel yüklenir; zengin şerit davranışı korunur.
#           DB/LLM/tarayıcı gerekmez; DB yükleyiciler stub'lanır.
# ==============================================================================

.startup_observers_source_once <- function() {
  needs <- !exists("startupObserversInit", envir = globalenv(),
                   mode = "function", inherits = TRUE) ||
           !exists("resolve_effective_user_id", envir = globalenv(),
                   mode = "function", inherits = TRUE) ||
           !exists("mergen_startup_lane_is_fast", envir = globalenv(),
                   mode = "function", inherits = TRUE)
  if (!needs) {
    return(invisible(TRUE))
  }

  # startupObserversInit resolve_effective_user_id'e (utils_common) ve şerit
  # yardımcılarına (helpers_startup_lane) bağımlıdır.
  source(
    file.path(resolve_repo_root_for_tests(), "R", "utils_common.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_startup_lane.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_observers_startup.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

# DB yükleyici ve async wrapper globalleri test süresince kayıt/stub edilir.
# tracked_future_promise stub'u task_fn'i senkron çalıştırır; rec$in_future
# işareti sayesinde DB stub'ları çağrının worker sarmalayıcısı içinden mi
# (async) yoksa doğrudan mı (senkron/kritik yol) geldiğini kaydeder.
# mergen_startup_chat_preview_promise stub'u hızlı şeridin ertelemeli ısıtma
# gönderimini sayar; gerçek DB/worker gerekmez.
.with_startup_db_stubs <- function(rec) {
  names <- c(
    "load_chats_preview_from_db",
    "load_chats_from_db",
    "tracked_future_promise",
    "mergen_startup_chat_preview_promise",
    "mergen_startup_async_worker_ready"
  )
  had <- vapply(names, exists, logical(1), envir = globalenv(), inherits = FALSE)
  old <- lapply(names, function(nm) {
    if (exists(nm, envir = globalenv(), inherits = FALSE)) get(nm, envir = globalenv()) else NULL
  })
  names(old) <- names

  rec$preview <- rec$preview %||% 0L
  rec$full <- rec$full %||% 0L
  rec$future <- rec$future %||% 0L
  rec$in_future <- FALSE
  rec$preview_in_future <- logical(0)
  rec$preview_user_ids <- integer(0)
  rec$preview_session_tokens <- character(0)
  rec$full_user_ids <- integer(0)
  rec$future_types <- character(0)

  assign("load_chats_preview_from_db", function(...) {
    rec$preview <- rec$preview + 1L
    rec$preview_in_future <- c(rec$preview_in_future, isTRUE(rec$in_future))
    rec$preview_result %||% list()
  }, envir = globalenv())
  assign("load_chats_from_db", function(user_id, ...) {
    rec$full <- rec$full + 1L
    rec$full_user_ids <- c(rec$full_user_ids, as.integer(user_id))
    rec$full_result %||% list()
  }, envir = globalenv())
  assign("tracked_future_promise", function(task_fn, task_type = NULL, ...) {
    rec$future <- rec$future + 1L
    rec$future_types <- c(rec$future_types, as.character(task_type %||% ""))
    if (identical(task_type, "startup_saved_chats") && isTRUE(rec$dispatch_full_once)) {
      rec$dispatch_full_once <- FALSE
      stop("işçi gönderimi başarısız")
    }
    rec$in_future <- TRUE
    on.exit(rec$in_future <- FALSE, add = TRUE)
    result <- task_fn()
    reject_this_full <- identical(task_type, "startup_saved_chats") &&
      (isTRUE(rec$reject_full) ||
         (isTRUE(rec$reject_full_once) && !isTRUE(rec$reject_full_once_used)))
    if (identical(task_type, "startup_saved_chats") &&
        isTRUE(rec$reject_full_once) && !isTRUE(rec$reject_full_once_used)) {
      rec$reject_full_once_used <- TRUE
    }
    if (isTRUE(reject_this_full)) {
      return(promises::promise(function(resolve, reject) {
        if (isTRUE(rec$defer_full_rejection)) {
          rec$reject_full_now <- function() reject(simpleError("tam liste sorgusu başarısız (test)"))
        } else {
          reject(simpleError("tam liste sorgusu başarısız (test)"))
        }
      }))
    }
    if (identical(task_type, "startup_saved_chats") &&
        isTRUE(rec$defer_full_fulfillment)) {
      return(promises::promise(function(resolve, reject) {
        rec$resolve_full <- function() resolve(result)
      }))
    }
    if (identical(task_type, "startup_saved_chats_preview") &&
        isTRUE(rec$defer_preview_fulfillment)) {
      return(promises::promise(function(resolve, reject) {
        rec$resolve_preview <- function() resolve(result)
      }))
    }
    promises::promise_resolve(result)
  }, envir = globalenv())
  assign("mergen_startup_async_worker_ready", function() {
    isTRUE(if (is.null(rec$async_worker_ready)) TRUE else rec$async_worker_ready)
  }, envir = globalenv())
  assign("mergen_startup_chat_preview_promise", function(user_id, limit = 6L, session_token = NULL, gecerli_mi = NULL) {
    # Tam liste (yalnızca açık NA sentineli; NaN reddedilir) üretimde aynı dar
    # worker'dan geçer; test kayıtları eski tam liste yolunun aynısıdır.
    if (length(limit) == 1L && (is.logical(limit) || is.numeric(limit)) && is.na(limit) && !is.nan(limit)) {
      # Geçerlilik yüklemi ve gönderim anındaki yerel durum kaydedilir.
      rec$gecerli_mi <- gecerli_mi
      rec$gecerli_gonderimde <- if (is.function(gecerli_mi)) isTRUE(gecerli_mi()) else NA
      if (is.function(rec$tam_gonderimde)) rec$tam_gonderimde()
      return(get("tracked_future_promise", envir = globalenv())(
        task_fn = function() get("load_chats_from_db", envir = globalenv())(user_id, include_messages = FALSE),
        task_type = "startup_saved_chats",
        session_token = session_token
      ))
    }
    if (isTRUE(rec$fail_preview_dispatch)) {
      stop("veritabanına ulaşılamadı (test)")
    }
    rec$preview <- rec$preview + 1L
    rec$preview_user_ids <- c(rec$preview_user_ids, as.integer(user_id))
    rec$preview_session_tokens <- c(rec$preview_session_tokens, as.character(session_token %||% ""))
    result <- rec$preview_result %||% list()
    reject_this_preview <- isTRUE(rec$reject_preview) ||
      (isTRUE(rec$reject_preview_once) && !isTRUE(rec$reject_preview_once_used))
    if (isTRUE(rec$reject_preview_once) && !isTRUE(rec$reject_preview_once_used)) {
      rec$reject_preview_once_used <- TRUE
    }
    if (isTRUE(reject_this_preview)) {
      return(promises::promise(function(resolve, reject) {
        reject(simpleError("ön izleme sorgusu başarısız (test)"))
      }))
    }
    if (isTRUE(rec$defer_preview_fulfillment)) {
      return(promises::promise(function(resolve, reject) {
        rec$resolve_preview <- function() resolve(result)
      }))
    }
    promises::promise_resolve(result)
  }, envir = globalenv())

  list(restore = function() {
    for (nm in c(names, "mergen_startup_async_worker_ready")) {
      if (isTRUE(had[[nm]])) {
        assign(nm, old[[nm]], envir = globalenv())
      } else if (exists(nm, envir = globalenv(), inherits = FALSE)) {
        rm(list = nm, envir = globalenv())
      }
    }
  })
}

.make_boot_ready_recorder <- function() {
  marks <- new.env(parent = emptyenv())
  marks$entries <- list()
  list(
    mark = function(key, label = key, pct = NULL, detail = NULL) {
      marks$entries[[length(marks$entries) + 1L]] <- list(key = key, detail = detail)
      invisible(TRUE)
    },
    entries = function() marks$entries,
    keys = function() vapply(marks$entries, function(e) e$key, character(1))
  )
}

testthat::test_that("startupObserversInit geçersiz kullanıcı kimliğinde kayıtlı sohbet yüklemez", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  .startup_observers_source_once()

  rec <- new.env()
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)

  shiny::testServer(function(input, output, session) {
    welcome_render_count <- 0L

    values <- shiny::reactiveValues(
      show_welcome = TRUE,
      saved_chats = list()
    )

    startupObserversInit(
      input = input,
      session = session,
      values = values,
      render_welcome_screen = function(...) {
        welcome_render_count <<- welcome_render_count + 1L
        invisible(NULL)
      },
      # SSO başlangıç placeholder'ı: geçersiz kullanıcı kimliği.
      current_user_id = function() 0L,
      sso_state = NULL,
      boot_ready = NULL
    )

    session$userData$.values <- values
    session$userData$.welcome_render_count <- function() welcome_render_count
  }, {
    session$flushReact()

    # Geçersiz kimlikte hiçbir DB yükleyici çağrılmamalı.
    testthat::expect_identical(rec$preview, 0L)
    testthat::expect_identical(rec$full, 0L)
    testthat::expect_identical(rec$future, 0L)

    # Şerit çözülse bile geçersiz kimlik yüklemeyi başlatamaz.
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))
    testthat::expect_identical(rec$preview, 0L)
    testthat::expect_identical(rec$full, 0L)

    # İstemci hazır sinyali de geçersiz kimlikte ön izleme gönderimi başlatamaz.
    session$setInputs(welcome_client_ready = list(fast_lane = TRUE, timestamp = 1))
    testthat::expect_identical(rec$preview, 0L)

    # Kayıtlı sohbet durumu boş kalmalı (yanlış kullanıcıdan veri sızmamalı).
    testthat::expect_identical(length(session$userData$.values$saved_chats), 0L)

    # Karşılama ekranı başlangıçta yine de render edilmeli.
    testthat::expect_gte(session$userData$.welcome_render_count(), 1L)
  })
})

testthat::test_that("hızlı şeritte ön izleme ilk çizimden sonra ısıtılır, açılış hiçbir DB işini beklemez", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_observers_source_once()

  rec <- new.env()
  rec$preview_result <- list(
    "preview-chat" = list(title = "Ön izleme", message_count = 0L)
  )
  # Tam liste gerçekte ön izlemeyi kapsar.
  rec$full_result <- list(
    "preview-chat" = list(title = "Ön izleme", message_count = 0L),
    "older-chat" = list(title = "Eski söyleşi", message_count = 2L)
  )
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)

  boot_ready <- .make_boot_ready_recorder()

  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input,
      session = session,
      values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() 42L,
      sso_state = NULL,
      boot_ready = boot_ready
    )
    session$userData$.values <- values
  }, {
    session$flushReact()

    rec$tam_gonderimde <- function() rec$gonderimdeki <- names(shiny::isolate(session$userData$.values$saved_chats))
    # Şerit çözülmeden HİÇBİR kayıtlı sohbet DB çağrısı başlamaz (yarış düzeltmesi).
    testthat::expect_identical(rec$preview, 0L)
    testthat::expect_identical(rec$full, 0L)
    # Kimlik hazır: auth_ready şerit beklenirken işaretlenmiş olmalı.
    testthat::expect_true("auth_ready" %in% boot_ready$keys())

    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "selector", ts = 1))

    # Hızlı şerit: tam yükleme AÇILIŞTA çalışmaz.
    testthat::expect_identical(rec$full, 0L)
    testthat::expect_false("startup_saved_chats" %in% rec$future_types)

    # Kritik açılış yolu artık ÖN İZLEME GÖNDERİMİNİ DE beklemez: şerit
    # çözümü anında hiçbir ön izleme çağrısı/worker hazırlığı başlamaz.
    testthat::expect_identical(rec$preview, 0L)

    # Dürüst kontrol noktaları: ön izleme hemen "ertelendi" olarak raporlanır,
    # tam liste ertelemesi ayrı anahtar kullanır ve gerçek yükleme anahtarı
    # (saved_chats_full_loaded) ertelenme için TÜKETİLMEZ.
    preview_marks <- Filter(function(e) identical(e$key, "saved_chats_preview_ready"), boot_ready$entries())
    testthat::expect_true(length(preview_marks) >= 1L)
    testthat::expect_true(isTRUE(preview_marks[[1]]$detail$deferred))
    full_deferred_marks <- Filter(function(e) identical(e$key, "saved_chats_full_deferred"), boot_ready$entries())
    testthat::expect_true(length(full_deferred_marks) >= 1L)
    testthat::expect_true(isTRUE(full_deferred_marks[[1]]$detail$deferred))
    testthat::expect_false("saved_chats_full_loaded" %in% boot_ready$keys())

    # Tembel yükleme bekleniyor işareti korunur.
    testthat::expect_true(isTRUE(session$userData$saved_chats_full_pending))

    # İlk çizim sinyali gelince ısıtma BİR KEZ gönderilir.
    session$setInputs(welcome_client_ready = list(fast_lane = TRUE, timestamp = 1))
    testthat::expect_identical(rec$preview, 1L)
    testthat::expect_identical(rec$preview_user_ids, 42L)
    # Oturum belirteci worker izleme kaydına taşınır (oturum kapsamı korunur).
    testthat::expect_identical(rec$preview_session_tokens, as.character(session$token))

    # Isıtma sonucu uygulanır ve ayrı hydrated kontrol noktası işaretlenir.
    later::run_now(timeoutSecs = 0.1)
    session$flushReact()
    testthat::expect_true(
      "preview-chat" %in% names(session$userData$.values$saved_chats)
    )
    hydrated_marks <- Filter(function(e) identical(e$key, "saved_chats_preview_hydrated"), boot_ready$entries())
    testthat::expect_true(length(hydrated_marks) >= 1L)

    # Ön izleme uygulandıktan sonra tam liste kullanıcı sayfayı açmadan,
    # arka planda (işçi sarmalayıcısında) BİR KEZ yüklenir.
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    session$flushReact()
    testthat::expect_identical(rec$full, 1L)
    # Tam liste ön izleme UYGULANDIKTAN sonra gönderildi (gönderim anında yalnız
    # ön izleme söyleşisi vardı) ve geçerlilik yüklemi gönderimde doğruydu.
    testthat::expect_identical(rec$gonderimdeki, "preview-chat")
    testthat::expect_true(is.function(rec$gecerli_mi))
    testthat::expect_true(isTRUE(rec$gecerli_gonderimde))
    testthat::expect_true("startup_saved_chats" %in% rec$future_types)
    testthat::expect_true(all(c("preview-chat", "older-chat") %in% names(session$userData$.values$saved_chats)))
    testthat::expect_true("saved_chats_full_loaded" %in% boot_ready$keys())

    # Tekrarlanan istemci hazır sinyali ikinci bir gönderim başlatamaz.
    session$setInputs(welcome_client_ready = list(fast_lane = TRUE, timestamp = 2))
    testthat::expect_identical(rec$preview, 1L)
  })
})


testthat::test_that("hızlı şeritte istemci sinyali gelmezse güvenlik zamanlayıcısı ön izlemeyi yükler", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_observers_source_once()

  rec <- new.env()
  rec$preview_result <- list(
    "fallback-chat" = list(title = "Geri dönüş", message_count = 0L)
  )
  # Arka plan tam listesi gerçekte ön izlemeyi kapsar; boş bir tam liste
  # sonucu iddiayı zamanlamaya bağımlı kılıyordu.
  rec$full_result <- rec$preview_result
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)

  old_opt <- getOption("mergen.startup_preview_fallback_secs")
  options(mergen.startup_preview_fallback_secs = 0.05)
  on.exit(options(mergen.startup_preview_fallback_secs = old_opt), add = TRUE)

  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input,
      session = session,
      values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() 42L,
      sso_state = NULL,
      boot_ready = NULL
    )
    session$userData$.values <- values
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))
    testthat::expect_identical(rec$preview, 0L)

    # welcome_client_ready hiç gelmese de zamanlayıcı ısıtmayı bir kez başlatır.
    deadline <- Sys.time() + 2
    while (rec$preview < 1L && Sys.time() < deadline) {
      later::run_now(timeoutSecs = 0.1)
    }
    testthat::expect_identical(rec$preview, 1L)

    later::run_now(timeoutSecs = 0.1)
    session$flushReact()
    testthat::expect_true(
      "fallback-chat" %in% names(session$userData$.values$saved_chats)
    )
  })
})


testthat::test_that("hızlı şeritte ön izleme gönderim/sorgu hatası açılışı bozmaz", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_observers_source_once()

  rec <- new.env()
  rec$fail_preview_dispatch <- TRUE
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)

  boot_ready <- .make_boot_ready_recorder()

  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input,
      session = session,
      values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() 42L,
      sso_state = NULL,
      boot_ready = boot_ready
    )
    session$userData$.values <- values
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))

    # Ertelenmiş kontrol noktası gönderim denemesinden ÖNCE işaretlendiği için
    # açılış sözleşmesi ısıtma hatasından bağımsızdır.
    testthat::expect_true("saved_chats_preview_ready" %in% boot_ready$keys())

    # Senkron gönderim hatası uyarıya çevrilir; observer/oturum çökmez.
    testthat::expect_warning(
      session$setInputs(welcome_client_ready = list(fast_lane = TRUE, timestamp = 1)),
      regexp = "Preview chat dispatch failed"
    )
    testthat::expect_identical(length(session$userData$.values$saved_chats), 0L)
  })
})


testthat::test_that("hızlı şeritte reddedilen ön izleme sözü açılışı bozmaz", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_observers_source_once()

  rec <- new.env()
  rec$reject_preview <- TRUE
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)

  rec$warned <- FALSE
  startup_init <- startupObserversInit
  environment(startup_init) <- list2env(list(warning = function(...) {
    metin <- paste(..., collapse = " ")
    if (grepl("Preview chat load failed", metin)) rec$warned <- TRUE else base::warning(...)
  }), parent = environment(startup_init))
  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startup_init(
      input = input,
      session = session,
      values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() 42L,
      sso_state = NULL,
      boot_ready = NULL
    )
    session$userData$.values <- values
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))

    session$setInputs(welcome_client_ready = list(fast_lane = TRUE, timestamp = 1))
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    testthat::expect_identical(rec$preview, 1L)
    testthat::expect_true(rec$warned)
    session$flushReact()
    testthat::expect_identical(length(session$userData$.values$saved_chats), 0L)
  })
})

testthat::test_that("hızlı şeritte reddedilen ön izleme daha sonra yeniden denenebilir", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_observers_source_once()

  rec <- new.env()
  rec$reject_preview_once <- TRUE
  rec$preview_result <- list(
    "retry-preview" = list(title = "Yeniden Deneme", message_count = 0L)
  )
  # Başarılı yeniden denemeden sonra arka plan tam listesi ön izlemeyi kapsar.
  rec$full_result <- rec$preview_result
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)

  rec$warned <- FALSE
  startup_init <- startupObserversInit
  environment(startup_init) <- list2env(list(warning = function(...) {
    metin <- paste(..., collapse = " ")
    if (grepl("Preview chat load failed", metin)) rec$warned <- TRUE else base::warning(...)
  }), parent = environment(startup_init))
  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startup_init(
      input = input,
      session = session,
      values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() 42L,
      sso_state = NULL,
      boot_ready = NULL
    )
    session$userData$.values <- values
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))

    session$setInputs(welcome_client_ready = list(fast_lane = TRUE, timestamp = 1))
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    testthat::expect_true(rec$warned)
    testthat::expect_identical(rec$preview, 1L)
    testthat::expect_identical(length(session$userData$.values$saved_chats), 0L)

    session$setInputs(welcome_client_ready = list(fast_lane = TRUE, timestamp = 2))
    later::run_now(timeoutSecs = 0.1)
    session$flushReact()

    testthat::expect_identical(rec$preview, 2L)
    testthat::expect_true("retry-preview" %in% names(session$userData$.values$saved_chats))
  })
})


testthat::test_that("hızlı şeritte ısıtma kimliği çalıştırma anında yeniden çözer", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_observers_source_once()

  rec <- new.env()
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)

  identity_state <- new.env(parent = emptyenv())
  identity_state$user_id <- 42L

  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input,
      session = session,
      values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() identity_state$user_id,
      sso_state = NULL,
      boot_ready = NULL
    )
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))
    testthat::expect_identical(rec$preview, 0L)

    # Kimlik ısıtma anına kadar geçersizleşirse hiçbir sorgu gönderilmez.
    identity_state$user_id <- 0L
    session$setInputs(welcome_client_ready = list(fast_lane = TRUE, timestamp = 1))
    testthat::expect_identical(rec$preview, 0L)

    # Geçersiz kimlik denemesi idempotent kapıyı tüketmemeli; SSO kimliği
    # sonradan hazır olduğunda yeni istemci sinyali ön izlemeyi başlatabilmeli.
    identity_state$user_id <- 84L
    session$setInputs(welcome_client_ready = list(fast_lane = TRUE, timestamp = 2))
    testthat::expect_identical(rec$preview, 1L)
    testthat::expect_identical(rec$preview_user_ids, 84L)
  })
})

testthat::test_that("hızlı şeritte tam liste sekme açılışında bir kez tembel yüklenir", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  .startup_observers_source_once()

  rec <- new.env()
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)

  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input,
      session = session,
      values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() 42L,
      sso_state = NULL,
      boot_ready = NULL
    )
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))
    testthat::expect_identical(rec$full, 0L)

    # Sekme tembel tetikleyicisi: ilk açılışta bir kez tam liste yüklenir.
    session$setInputs(tabs = "chat")
    testthat::expect_identical(rec$full, 0L)

    session$setInputs(tabs = "saved_chats")
    testthat::expect_identical(rec$full, 1L)
    # Tembel yükleme çalıştırma anında çözülen kullanıcı kimliğini kullanır.
    testthat::expect_identical(rec$full_user_ids, 42L)
    testthat::expect_true("startup_saved_chats" %in% rec$future_types)

    # Tekrarlı sekme geçişleri ikinci bir tam yükleme başlatmaz.
    session$setInputs(tabs = "history")
    testthat::expect_identical(rec$full, 1L)
  })
})


testthat::test_that("hızlı şeritte önceden seçili hedef sekme tam listeyi bir kez yükler", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  .startup_observers_source_once()

  rec <- new.env()
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)

  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input,
      session = session,
      values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() 42L,
      sso_state = NULL,
      boot_ready = NULL
    )
  }, {
    session$flushReact()

    # Şerit çözülmeden önce ilgisiz veya hedef sekmeler tam yükleme başlatamaz.
    session$setInputs(tabs = "chat")
    testthat::expect_identical(rec$full, 0L)
    session$setInputs(tabs = "history")
    testthat::expect_identical(rec$full, 0L)

    # Hızlı şerit çözülünce önceden seçili history aynı tembel yol üzerinden
    # başka bir sekme geçişi gerektirmeden tam listeyi başlatır.
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))
    testthat::expect_identical(rec$full, 1L)
    testthat::expect_identical(rec$full_user_ids, 42L)
    testthat::expect_true("startup_saved_chats" %in% rec$future_types)

    # Sonraki hedef sekme olayları aynı yüklemeyi yeniden başlatamaz.
    session$setInputs(tabs = "saved_chats")
    testthat::expect_identical(rec$full, 1L)
  })
})


testthat::test_that("hızlı şeritte geç kalan ön izleme tam listeyi daraltmaz", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_observers_source_once()

  rec <- new.env()
  rec$defer_preview_fulfillment <- TRUE
  rec$preview_result <- list(list(ChatID = 1L))
  rec$full_result <- list(
    list(ChatID = 1L),
    list(ChatID = 2L),
    list(ChatID = 3L)
  )
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)

  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input,
      session = session,
      values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() 42L,
      sso_state = NULL,
      boot_ready = NULL
    )
    session$userData$.values <- values
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))

    # Isıtma ilk çizim sinyaliyle gönderilir; fulfillment bilerek bekletilir.
    session$setInputs(welcome_client_ready = list(fast_lane = TRUE, timestamp = 1))
    testthat::expect_identical(rec$preview, 1L)
    testthat::expect_true(is.function(rec$resolve_preview))
    testthat::expect_identical(length(session$userData$.values$saved_chats), 0L)

    # Tembel tam liste yüklemesi önce başlar ve tamamlanır.
    session$setInputs(tabs = "saved_chats")
    later::run_now(timeoutSecs = 0.1)
    session$flushReact()
    testthat::expect_identical(rec$full, 1L)
    testthat::expect_identical(length(session$userData$.values$saved_chats), 3L)

    # Geç kalan ön izleme callback'i tam listeyi 1 öğeye düşürmemelidir.
    rec$resolve_preview()
    later::run_now(timeoutSecs = 0.1)
    session$flushReact()
    testthat::expect_identical(length(session$userData$.values$saved_chats), 3L)
  })
})


testthat::test_that("hızlı şeritte geç kalan ön izleme yerel sohbet değişikliğini ezmez", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_observers_source_once()

  rec <- new.env()
  rec$defer_preview_fulfillment <- TRUE
  rec$preview_result <- list(
    "stale-preview" = list(title = "Eski ön izleme", message_count = 0L)
  )
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)

  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input,
      session = session,
      values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() 42L,
      sso_state = NULL,
      boot_ready = NULL
    )
    session$userData$.values <- values
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))

    # Isıtma ilk çizim sinyaliyle gönderilir; fulfillment bilerek bekletilir.
    session$setInputs(welcome_client_ready = list(fast_lane = TRUE, timestamp = 1))
    testthat::expect_identical(rec$preview, 1L)
    testthat::expect_true(is.function(rec$resolve_preview))
    testthat::expect_identical(rec$full, 0L)

    # Yeni/saklanan bir sohbetin yaptığı gibi reactive state'i worker
    # başlatıldıktan sonra, callback tamamlanmadan güncelle.
    newer_saved_chats <- list(
      "local-new-chat" = list(
        title = "Yeni Söyleşi",
        message_count = 1L,
        messages = list(list(type = "user", content = "Korunmalı"))
      )
    )
    session$userData$.values$saved_chats <- newer_saved_chats

    # Eski ön izleme geç tamamlansa da daha yeni yerel durum aynen kalır.
    rec$resolve_preview()
    later::run_now(timeoutSecs = 0.1)
    session$flushReact()
    testthat::expect_identical(
      session$userData$.values$saved_chats,
      newer_saved_chats
    )
    testthat::expect_true("local-new-chat" %in% names(session$userData$.values$saved_chats))
    testthat::expect_false("stale-preview" %in% names(session$userData$.values$saved_chats))
    testthat::expect_identical(rec$full, 0L)
  })
})

testthat::test_that("hızlı şeritte geç kalan ön izleme kimlik değişiminden sonra uygulanmaz", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_observers_source_once()

  rec <- new.env()
  rec$defer_preview_fulfillment <- TRUE
  rec$preview_result <- list(
    "wrong-user-preview" = list(title = "Yanlış Kullanıcı", message_count = 0L)
  )
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)

  identity_state <- new.env(parent = emptyenv())
  identity_state$user_id <- 42L

  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input,
      session = session,
      values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() identity_state$user_id,
      sso_state = NULL,
      boot_ready = NULL
    )
    session$userData$.values <- values
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))
    session$setInputs(welcome_client_ready = list(fast_lane = TRUE, timestamp = 1))
    testthat::expect_identical(rec$preview_user_ids, 42L)

    identity_state$user_id <- 84L
    rec$resolve_preview()
    later::run_now(timeoutSecs = 0.1)
    session$flushReact()

    testthat::expect_identical(length(session$userData$.values$saved_chats), 0L)
    testthat::expect_false("wrong-user-preview" %in% names(session$userData$.values$saved_chats))
  })
})

testthat::test_that("hızlı şeritte geç kalan tam liste kimlik değişiminden sonra uygulanmaz", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_observers_source_once()

  rec <- new.env()
  rec$defer_full_fulfillment <- TRUE
  rec$full_result <- list(
    "wrong-user-full" = list(title = "Yanlış Kullanıcı", message_count = 0L)
  )
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)

  identity_state <- new.env(parent = emptyenv())
  identity_state$user_id <- 42L

  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input,
      session = session,
      values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() identity_state$user_id,
      sso_state = NULL,
      boot_ready = NULL
    )
    session$userData$.values <- values
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))
    session$setInputs(tabs = "saved_chats")
    testthat::expect_identical(rec$full_user_ids, 42L)
    testthat::expect_true(is.function(rec$resolve_full))

    identity_state$user_id <- 84L
    rec$resolve_full()
    later::run_now(timeoutSecs = 0.1)
    session$flushReact()

    testthat::expect_identical(length(session$userData$.values$saved_chats), 0L)
    testthat::expect_true(isTRUE(session$userData$saved_chats_full_pending))
    testthat::expect_false("wrong-user-full" %in% names(session$userData$.values$saved_chats))
  })
})

testthat::test_that("hızlı şeritte eski kimliğe ait tam liste hatası güncel kimlik için yeniden denemeyi açık bırakır", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_observers_source_once()

  rec <- new.env()
  rec$reject_full_once <- TRUE
  rec$defer_full_rejection <- TRUE
  rec$full_result <- list(
    "current-user-full" = list(title = "Güncel Kullanıcı", message_count = 0L)
  )
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)

  identity_state <- new.env(parent = emptyenv())
  identity_state$user_id <- 42L

  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input,
      session = session,
      values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() identity_state$user_id,
      sso_state = NULL,
      boot_ready = NULL
    )
    session$userData$.values <- values
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))
    testthat::expect_true(isTRUE(session$userData$saved_chats_full_pending))

    session$setInputs(tabs = "saved_chats")
    testthat::expect_identical(rec$full_user_ids, 42L)
    testthat::expect_true(is.function(rec$reject_full_now))
    testthat::expect_false(isTRUE(session$userData$saved_chats_full_pending))

    identity_state$user_id <- 84L
    rec$reject_full_now()
    later::run_now(timeoutSecs = 0.1)
    session$flushReact()

    testthat::expect_true(isTRUE(session$userData$saved_chats_full_pending))
    testthat::expect_identical(length(session$userData$.values$saved_chats), 0L)

    session$setInputs(tabs = "history")
    later::run_now(timeoutSecs = 0.1)
    session$flushReact()

    testthat::expect_identical(rec$full_user_ids, c(42L, 84L))
    testthat::expect_false(isTRUE(session$userData$saved_chats_full_pending))
    testthat::expect_true("current-user-full" %in% names(session$userData$.values$saved_chats))
  })
})

testthat::test_that("zengin şeritte açılış davranışı korunur (senkron ön izleme + arka plan tam liste)", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  .startup_observers_source_once()

  rec <- new.env()
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)

  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input,
      session = session,
      values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() 42L,
      sso_state = NULL,
      boot_ready = NULL
    )
  }, {
    session$flushReact()
    testthat::expect_identical(rec$preview, 0L)

    # Şerit API'si olmayan istemci köprüsünün gönderdiği legacy payload biçimi.
    session$setInputs(startup_lane_resolved = list(lane = "rich_lane", source = "legacy_no_api", ts = 1))

    # Zengin şerit: ön izleme senkron (worker dışında) yüklenir.
    testthat::expect_identical(rec$preview, 1L)
    testthat::expect_identical(rec$preview_in_future, FALSE)

    # Tam liste açılışta arka plan worker'ında başlar; tembel bekleme yoktur.
    testthat::expect_identical(rec$full, 1L)
    testthat::expect_identical(rec$full_user_ids, 42L)
    testthat::expect_true("startup_saved_chats" %in% rec$future_types)
    testthat::expect_false(isTRUE(session$userData$saved_chats_full_pending))
  })
})

testthat::test_that("oturum başka kullanıcıya geçince kayıtlı söyleşiler yeni sahip için yeniden yüklenir", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_observers_source_once()
  if (!exists("mergen_session_owner_transition", envir = globalenv(), mode = "function")) {
    source(file.path(resolve_repo_root_for_tests(), "R", "helpers_user_session_identity.R"),
           encoding = "UTF-8", local = globalenv())
  }

  rec <- new.env()
  rec$full_result <- list("a-chat" = list(title = "A söyleşisi", message_count = 1L))
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)
  kimlik <- new.env()
  kimlik$uid <- 7L

  shiny::testServer(function(input, output, session) {
    session$userData$kimlik_sahibi <- 7L
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input, session = session, values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() kimlik$uid,
      sso_state = NULL, boot_ready = NULL
    )
    session$userData$.values <- values
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "rich_lane", source = "stored", ts = 1))
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    testthat::expect_identical(names(shiny::isolate(session$userData$.values$saved_chats)), "a-chat")

    rec$full_result <- list("b-chat" = list(title = "B söyleşisi", message_count = 1L))
    kimlik$uid <- 8L
    mergen_session_owner_transition(session$userData, 7L, 8L)
    session$flushReact()
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    testthat::expect_identical(tail(rec$full_user_ids, 1L), 8L)
    testthat::expect_identical(names(shiny::isolate(session$userData$.values$saved_chats)), "b-chat")
  })
})

testthat::test_that("sahip değişiminde A'nın geç ön izlemesi B'ye yazılmaz; boş B listesi A'yı göstermez", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  testthat::skip_if_not_installed("shinyjs")
  .startup_observers_source_once()
  if (!exists("mergen_session_owner_transition", envir = globalenv(), mode = "function")) {
    source(file.path(resolve_repo_root_for_tests(), "R", "helpers_user_session_identity.R"),
           encoding = "UTF-8", local = globalenv())
  }

  rec <- new.env()
  rec$defer_preview_fulfillment <- TRUE
  rec$preview_result <- list("a-chat" = list(title = "A söyleşisi", message_count = 1L))
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)
  kimlik <- new.env()
  kimlik$uid <- 42L

  shiny::testServer(function(input, output, session) {
    session$userData$kimlik_sahibi <- 42L
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input, session = session, values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() kimlik$uid,
      sso_state = NULL, boot_ready = NULL
    )
    session$userData$.values <- values
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))
    session$setInputs(welcome_client_ready = list(fast_lane = TRUE, timestamp = 1))
    a_coz <- rec$resolve_preview

    # B'ye geçiş: B için ön izleme gönderilir, A'nın sonucu hâlâ bekliyor.
    rec$preview_result <- list()
    kimlik$uid <- 84L
    mergen_session_owner_transition(session$userData, 42L, 84L)
    session$flushReact()
    testthat::expect_identical(tail(rec$preview_user_ids, 1L), 84L)
    b_coz <- rec$resolve_preview

    a_coz()
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    session$flushReact()
    testthat::expect_false("a-chat" %in% names(shiny::isolate(session$userData$.values$saved_chats)))

    b_coz()
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    testthat::expect_length(shiny::isolate(session$userData$.values$saved_chats), 0L)
  })

  # Zengin şerit: yeni sahibin listesi boşsa önceki sahibin söyleşileri temizlenir.
  rec2 <- new.env()
  rec2$full_result <- list("a-chat" = list(title = "A söyleşisi", message_count = 1L))
  stubs2 <- .with_startup_db_stubs(rec2)
  on.exit(stubs2$restore(), add = TRUE, after = FALSE)
  kimlik$uid <- 7L
  shiny::testServer(function(input, output, session) {
    session$userData$kimlik_sahibi <- 7L
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input, session = session, values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() kimlik$uid,
      sso_state = NULL, boot_ready = NULL
    )
    session$userData$.values <- values
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "rich_lane", source = "stored", ts = 1))
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    testthat::expect_identical(names(shiny::isolate(session$userData$.values$saved_chats)), "a-chat")
    rec2$full_result <- list()
    kimlik$uid <- 8L
    mergen_session_owner_transition(session$userData, 7L, 8L)
    session$flushReact()
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    testthat::expect_length(shiny::isolate(session$userData$.values$saved_chats), 0L)
  })
})

testthat::test_that("kimlik kaybında kayıtlı söyleşiler bırakılır, aynı kullanıcı dönünce yeniden yüklenir", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("later")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  .startup_observers_source_once()
  if (!exists("mergen_session_owner_transition", envir = globalenv(), mode = "function")) {
    source(file.path(resolve_repo_root_for_tests(), "R", "helpers_user_session_identity.R"),
           encoding = "UTF-8", local = globalenv())
  }
  rec <- new.env()
  rec$full_result <- list("a-chat" = list(title = "A söyleşisi", message_count = 1L))
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)
  kimlik <- new.env()
  kimlik$uid <- 7L
  shiny::testServer(function(input, output, session) {
    session$userData$kimlik_sahibi <- 7L
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input, session = session, values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() kimlik$uid,
      sso_state = NULL, boot_ready = NULL
    )
    session$userData$.values <- values
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "rich_lane", source = "stored", ts = 1))
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    testthat::expect_identical(names(shiny::isolate(session$userData$.values$saved_chats)), "a-chat")
    kimlik$uid <- 0L
    mergen_session_owner_transition(session$userData, 7L, 0L)
    session$flushReact()
    testthat::expect_length(shiny::isolate(session$userData$.values$saved_chats), 0L)
    kimlik$uid <- 7L
    mergen_session_owner_transition(session$userData, 0L, 7L)
    session$flushReact()
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    testthat::expect_identical(names(shiny::isolate(session$userData$.values$saved_chats)), "a-chat")
  })
})


testthat::test_that("eski tam liste sonucu yeni sahibin tamamlanmış yüklemesini sıfırlamaz", {
  for (pkg in c("shiny", "shinyjs", "promises", "later")) testthat::skip_if_not_installed(pkg)
  .startup_observers_source_once()
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_user_session_identity.R"),
         encoding = "UTF-8", local = globalenv())
  rec <- new.env()
  rec$defer_full_fulfillment <- TRUE
  rec$full_result <- list(a = list(title = "A"))
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)
  kimlik <- new.env()
  kimlik$uid <- 7L
  shiny::testServer(function(input, output, session) {
    session$userData$kimlik_sahibi <- 7L
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(input, session, values, render_welcome_screen = function(...) NULL,
                         current_user_id = function() kimlik$uid, sso_state = NULL, boot_ready = NULL)
    session$userData$.values <- values
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "rich_lane", source = "stored", ts = 1))
    eski <- rec$resolve_full
    kimlik$uid <- 8L
    rec$full_result <- list(b = list(title = "B"))
    mergen_session_owner_transition(session$userData, 7L, 8L)
    session$flushReact()
    rec$resolve_full()
    for (i in 1:5) later::run_now(0.05)
    expect_identical(names(shiny::isolate(session$userData$.values$saved_chats)), "b")
    eski()
    for (i in 1:5) later::run_now(0.05)
    expect_false(isTRUE(session$userData$saved_chats_full_pending))
    expect_identical(names(shiny::isolate(session$userData$.values$saved_chats)), "b")
    session$setInputs(tabs = "saved_chats")
    expect_identical(rec$full, 2L)
  })
})


test_that("tam liste gönderimi eşzamanlı hata atarsa yükleme yeniden denenebilir", {
  for (paket in c("shiny", "shinyjs", "promises", "later")) skip_if_not_installed(paket)
  .startup_observers_source_once()
  rec <- new.env()
  rec$dispatch_full_once <- TRUE
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)
  rec$warned <- FALSE
  startup_init <- startupObserversInit
  environment(startup_init) <- list2env(list(warning = function(...) {
    metin <- paste(..., collapse = " ")
    if (grepl("Initial saved chat load failed", metin)) rec$warned <- TRUE else base::warning(...)
  }), parent = environment(startupObserversInit))
  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startup_init(input, session, values, function(...) invisible(NULL), current_user_id = function() 42L,
                         sso_state = NULL, boot_ready = NULL)
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))
    session$setInputs(tabs = "saved_chats")
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    session$flushReact()
    expect_true(rec$warned)
    expect_true(session$userData$saved_chats_full_pending)
    session$setInputs(tabs = "history")
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    session$flushReact()
    expect_identical(rec$full, 1L)
  })
})


testthat::test_that("arka plan tam listesi geç gelince arada açılan ve silinen söyleşiler korunur", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_observers_source_once()

  rec <- new.env()
  rec$defer_full_fulfillment <- TRUE
  rec$preview_result <- list("p1" = list(title = "Ön izleme", message_count = 1L))
  rec$full_result <- list(
    "p1" = list(title = "Ön izleme", message_count = 1L),
    "eski" = list(title = "Eski söyleşi", message_count = 4L)
  )
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)

  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input, session = session, values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() 42L, sso_state = NULL, boot_ready = NULL
    )
    session$userData$.values <- values
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))
    session$setInputs(welcome_client_ready = list(fast_lane = TRUE, timestamp = 1))
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    session$flushReact()
    testthat::expect_identical(rec$full, 1L)
    testthat::expect_true(is.function(rec$resolve_full))

    # Tam liste uçuştayken kullanıcı yeni bir söyleşi açtı.
    yerel <- session$userData$.values$saved_chats
    yerel[["yeni"]] <- list(title = "Yeni söyleşi çğış", message_count = 1L)
    session$userData$.values$saved_chats <- yerel

    rec$resolve_full()
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    session$flushReact()
    son <- session$userData$.values$saved_chats
    testthat::expect_true(all(c("yeni", "p1", "eski") %in% names(son)),
                          info = "eski DB görüntüsü yeni söyleşiyi silmemeli")
    testthat::expect_identical(son[["yeni"]]$title, "Yeni söyleşi çğış")
  })
})

testthat::test_that("bekleyen tam liste, uçuş sırasında üretim yoluyla işaretlenen silinmiş söyleşiyi geri getirmez", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_observers_source_once()

  rec <- new.env()
  rec$defer_full_fulfillment <- TRUE
  rec$preview_result <- list("p1" = list(title = "Ön izleme", message_count = 1L))
  # "77" gönderimden SONRA açıldı ve işçinin DB görüntüsüne girdi.
  rec$full_result <- list(
    "77" = list(title = "Açılıp silinen çğış", message_count = 1L),
    "p1" = list(title = "Ön izleme", message_count = 1L),
    "eski" = list(title = "Eski söyleşi", message_count = 4L)
  )
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)

  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input, session = session, values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() 42L, sso_state = NULL, boot_ready = NULL
    )
    session$userData$.values <- values
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))
    session$setInputs(welcome_client_ready = list(fast_lane = TRUE, timestamp = 1))
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    session$flushReact()
    testthat::expect_true(is.function(rec$resolve_full))
    # Uçuş sırasında silme doğrulandı: işaret üretimdeki yoldan yazılır
    # (mergen_saved_chats_mark_deleted); yetkili sürüm ARTMADI (yeniden okuma
    # başarısız yolu). Silme gözlemcisinin işaret yazımı ayrıca
    # test-saved-chats-delete-reload-behavior.R içinde sınanır.
    testthat::expect_true(mergen_saved_chats_mark_deleted(session, "77"))
    testthat::expect_identical(session$userData$saved_chats_silinenler, "77")
    testthat::expect_null(session$userData$saved_chats_yetkili_surum)
    rec$resolve_full()
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    session$flushReact()
    son <- shiny::isolate(session$userData$.values$saved_chats)
    testthat::expect_false("77" %in% names(son), info = "silinen söyleşi eski DB görüntüsüyle geri gelmemeli")
    testthat::expect_true(all(c("p1", "eski") %in% names(son)), info = "diğer söyleşiler korunmalı")
  })
})

testthat::test_that("tam liste uçuştayken silme ya da Tümünü Temizle sonrası eski DB görüntüsü uygulanmaz", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_observers_source_once()

  calistir <- function(yetkili_liste) {
    rec <- new.env()
    rec$defer_full_fulfillment <- TRUE
    rec$preview_result <- list("p1" = list(title = "Ön izleme", message_count = 1L))
    # Gönderimden sonra açılıp silinen "gecici" de DB görüntüsünde yer alır.
    rec$full_result <- list(
      "gecici" = list(title = "Açılıp silinen", message_count = 1L),
      "p1" = list(title = "Ön izleme", message_count = 1L),
      "eski" = list(title = "Eski söyleşi", message_count = 4L)
    )
    stubs <- .with_startup_db_stubs(rec)
    on.exit(stubs$restore(), add = TRUE)
    sonuc <- NULL
    shiny::testServer(function(input, output, session) {
      values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
      startupObserversInit(
        input = input, session = session, values = values,
        render_welcome_screen = function(...) invisible(NULL),
        current_user_id = function() 42L, sso_state = NULL, boot_ready = NULL
      )
      session$userData$.values <- values
    }, {
      session$flushReact()
      session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))
      session$setInputs(welcome_client_ready = list(fast_lane = TRUE, timestamp = 1))
      for (i in 1:5) later::run_now(timeoutSecs = 0.05)
      session$flushReact()
      testthat::expect_true(is.function(rec$resolve_full))
      # Silme/Tümünü Temizle gözlemcisiyle aynı: liste DB'den yetkili olarak
      # yeniden kurulur ve yetkili sürüm artar.
      session$userData$saved_chats_yetkili_surum <- 1L
      session$userData$.values$saved_chats <- yetkili_liste
      rec$resolve_full()
      for (i in 1:5) later::run_now(timeoutSecs = 0.05)
      session$flushReact()
      testthat::expect_true(isTRUE(session$userData$saved_chats_full_loaded))
      sonuc <<- shiny::isolate(session$userData$.values$saved_chats)
    })
    sonuc
  }

  # Tümünü Temizle: hiçbir eski söyleşi (önizlemede olmayanlar dahil) geri gelmez.
  testthat::expect_length(calistir(list()), 0L)
  # Gönderimden sonra açılıp silinen söyleşi geri gelmez; yetkili liste korunur.
  yetkili <- list("p1" = list(title = "Ön izleme", message_count = 1L),
                  "eski" = list(title = "Eski söyleşi", message_count = 4L))
  testthat::expect_identical(names(calistir(yetkili)), c("p1", "eski"))
})

testthat::test_that("önceki sahibin hazırlık süre sınırı yeni sahibin hazır-olmasını bozmaz; sahibe özgü anahtarlar sıfırlanır", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_observers_source_once()
  if (!exists("mergen_session_owner_transition", envir = globalenv(), mode = "function")) {
    source(file.path(resolve_repo_root_for_tests(), "R", "helpers_user_session_identity.R"),
           encoding = "UTF-8", local = globalenv())
  }
  eski_secenek <- options(mergen.management_ready_deadline_secs = 0.1)
  on.exit(options(eski_secenek), add = TRUE)

  rec <- new.env()
  rec$defer_full_fulfillment <- TRUE
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)
  kimlik <- new.env()
  kimlik$uid <- 7L
  isaret <- new.env()
  isaret$anahtarlar <- character()
  isaret$sifirlanan <- character()
  boot <- list(
    mark = function(key, ...) invisible(TRUE),
    mark_once = function(key, ...) { isaret$anahtarlar <- c(isaret$anahtarlar, key); invisible(TRUE) },
    reset = function(keys) { isaret$sifirlanan <- c(isaret$sifirlanan, keys); invisible(TRUE) }
  )

  shiny::testServer(function(input, output, session) {
    session$userData$kimlik_sahibi <- 7L
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input, session = session, values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() kimlik$uid,
      sso_state = NULL, boot_ready = boot
    )
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "rich_lane", source = "stored", ts = 1))
    testthat::expect_identical(rec$full_user_ids, 7L)
    # Geçmiş hazırlık tetiği yalnızca güncel tam liste nesline aitse geçerlidir.
    gecerli_tetik <- session$userData$mergen_gecmis_hazirla_gecerli
    testthat::expect_true(is.function(gecerli_tetik))
    testthat::expect_true(gecerli_tetik(1L))
    testthat::expect_false(gecerli_tetik("abc"))
    # A'nın süre sınırı dolmadan sahip B'ye geçer; B'nin süresi uzundur.
    options(mergen.management_ready_deadline_secs = 30)
    kimlik$uid <- 8L
    mergen_session_owner_transition(session$userData, 7L, 8L)
    session$flushReact()
    testthat::expect_true(all(c("history_rows_ready", "management_pages_ready") %in% isaret$sifirlanan))
    testthat::expect_false(gecerli_tetik(1L), info = "A'nın ertelenmiş hazırlık tetiği B için geçersiz olmalı")
    # A'nın 0,1 sn'lik süre sınırı geri çağrısı gerçekten çalışana dek (yakında
    # bekleyen later işi kalmayana dek, süre sınırlı) beklenir; yalnızca geçen
    # süreye güvenilmez. B'nin 30 sn'lik geri çağrısı bu pencerenin dışındadır.
    son <- Sys.time() + 10
    repeat {
      later::run_now(timeoutSecs = 0.05)
      if (later::next_op_secs() > 5 || Sys.time() >= son) break
    }
    testthat::expect_gt(later::next_op_secs(), 5)
    testthat::expect_identical(tail(rec$full_user_ids, 1L), 8L)
    testthat::expect_false("management_pages_ready" %in% isaret$anahtarlar,
                           info = "A'nın eski süre sınırı B'yi 'kısmen' işaretlememeli")
  })
})

testthat::test_that("zengin şeritte tam liste başlarken kimlik düşerse Söyleşi Yönetimi sonsuza dek beklemez, erişim açılmaz", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  .startup_observers_source_once()

  rec <- new.env()
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)
  kimlik <- new.env()
  kimlik$uid <- 42L
  # Senkron ön izleme sırasında kimlik düşer (ör. SSO oturumu sona erdi); okuma
  # önceki sahibin (42) tanınabilir satırını döndürür.
  assign("load_chats_preview_from_db", function(...) {
    rec$preview <- rec$preview + 1L
    kimlik$uid <- 0L
    list("4242" = list(title = "Önceki sahibin söyleşisi çğış", message_count = 1L))
  }, envir = globalenv())
  boot <- .make_boot_ready_recorder()

  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input, session = session, values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() kimlik$uid, sso_state = NULL, boot_ready = boot
    )
    session$userData$.values <- values
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "rich_lane", source = "stored", ts = 1))
    testthat::expect_identical(rec$preview, 1L)
    # Kimliksiz tam liste gönderilmez (veri erişimi yok); önceki sahibin ön izleme
    # satırı da kimlik düştükten sonra yayımlanmaz.
    testthat::expect_identical(rec$full, 0L)
    testthat::expect_length(shiny::isolate(session$userData$.values$saved_chats), 0L)
    # Toplu anahtar "kısmen" bildirilir: zengin açılış kimlik beklerken asılı kalmaz.
    yonetim <- Filter(function(e) identical(e$key, "management_pages_ready"), boot$entries())
    testthat::expect_length(yonetim, 1L)
    testthat::expect_true(isTRUE(yonetim[[1]]$detail$degraded))
    # Kimlik kaybı işareti açık FALSE değeridir (eksik alan kabul edilmez).
    testthat::expect_identical(yonetim[[1]]$detail$identity, FALSE)
    testthat::expect_true(isTRUE(session$userData$saved_chats_full_pending))
  })
})

testthat::test_that("yükleme sürerken açılan sayfa için başarısız tam liste bir kez yeniden denenir, süren hata döngüye girmez", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("later")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  .startup_observers_source_once()

  rec <- new.env()
  rec$reject_full <- TRUE
  rec$defer_full_rejection <- TRUE
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)

  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input, session = session, values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() 42L, sso_state = NULL, boot_ready = NULL
    )
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))
    session$setInputs(tabs = "saved_chats")
    testthat::expect_identical(rec$full, 1L)
    # Yükleme sürerken sayfaya yeniden gelinir: tetik atlanır ama ziyaret hatırlanır.
    session$setInputs(tabs = "chat")
    session$setInputs(tabs = "saved_chats")
    testthat::expect_identical(rec$full, 1L)
    reddet <- function() {
      rec$reject_full_now()
      for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    }
    testthat::expect_warning(reddet(), "Initial saved chat load failed")
    testthat::expect_identical(rec$full, 2L)
    # Yeniden deneme de başarısız: yeni ziyaret olmadan üçüncü deneme yapılmaz.
    testthat::expect_warning(reddet(), "Initial saved chat load failed")
    testthat::expect_identical(rec$full, 2L)
    testthat::expect_true(isTRUE(session$userData$saved_chats_full_pending))
    # İki hatadan sonra toparlanma kalıcı olarak kapanmaz: kaynak düzelir, kullanıcı
    # sayfadan çıkıp yeniden açar ve üçüncü deneme tam listeyi uygular.
    rec$reject_full <- FALSE
    rec$full_result <- list("toparlandi" = list(title = "Toparlandı", message_count = 1L))
    session$setInputs(tabs = "chat")
    session$setInputs(tabs = "saved_chats")
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    session$flushReact()
    testthat::expect_identical(rec$full, 3L)
    testthat::expect_true("toparlandi" %in% names(shiny::isolate(values$saved_chats)))
    testthat::expect_false(isTRUE(session$userData$saved_chats_full_pending))
  })
})

testthat::test_that("zengin şeritte sahip değişimi kimliksiz kalırsa Söyleşi Yönetimi kısmen olarak yayımlanır", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("later")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  .startup_observers_source_once()
  if (!exists("mergen_session_owner_transition", envir = globalenv(), mode = "function")) {
    source(file.path(resolve_repo_root_for_tests(), "R", "helpers_user_session_identity.R"),
           encoding = "UTF-8", local = globalenv())
  }
  rec <- new.env()
  rec$full_result <- list("a-chat" = list(title = "A söyleşisi", message_count = 1L))
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)
  boot <- .make_boot_ready_recorder()
  kimlik <- new.env()
  kimlik$uid <- 7L
  shiny::testServer(function(input, output, session) {
    session$userData$kimlik_sahibi <- 7L
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(
      input = input, session = session, values = values,
      render_welcome_screen = function(...) invisible(NULL),
      current_user_id = function() kimlik$uid, sso_state = NULL, boot_ready = boot
    )
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "rich_lane", source = "stored", ts = 1))
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    kimliksiz <- function() Filter(function(e) identical(e$key, "management_pages_ready") &&
                                     identical(e$detail$identity, FALSE), boot$entries())
    testthat::expect_length(kimliksiz(), 0L)
    kimlik$uid <- 0L
    mergen_session_owner_transition(session$userData, 7L, 0L)
    session$flushReact()
    testthat::expect_length(kimliksiz(), 1L)
    testthat::expect_true(isTRUE(kimliksiz()[[1]]$detail$degraded))
    testthat::expect_identical(rec$full, 1L)
  })
})

testthat::test_that("kimlik düşüp aynı kullanıcı dönse de eski nesle ait ön izleme uygulanmaz ve tam liste planlamaz", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_observers_source_once()
  if (!exists("mergen_session_owner_transition", envir = globalenv(), mode = "function")) {
    source(file.path(resolve_repo_root_for_tests(), "R", "helpers_user_session_identity.R"),
           encoding = "UTF-8", local = globalenv())
  }
  rec <- new.env()
  rec$defer_preview_fulfillment <- TRUE
  rec$preview_result <- list("eski-on-izleme" = list(title = "Eski ön izleme", message_count = 1L))
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)
  kimlik <- new.env(); kimlik$uid <- 7L
  shiny::testServer(function(input, output, session) {
    session$userData$kimlik_sahibi <- 7L
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(input = input, session = session, values = values,
                         render_welcome_screen = function(...) invisible(NULL),
                         current_user_id = function() kimlik$uid, sso_state = NULL, boot_ready = NULL)
    session$userData$.values <- values
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))
    session$setInputs(welcome_client_ready = list(fast_lane = TRUE, timestamp = 1))
    eski_coz <- rec$resolve_preview
    # Yeni neslin (yerine geçen) ön izlemesi ayırt edilebilir başlık taşır.
    rec$preview_result <- list("yeni-on-izleme" = list(title = "Yeni ön izleme", message_count = 1L))
    rec$full_result <- rec$preview_result
    # Kimlik düşer ve AYNI kullanıcı geri döner (kimlik ve boş liste yeniden eşleşir).
    kimlik$uid <- 0L
    mergen_session_owner_transition(session$userData, 7L, 0L)
    session$flushReact()
    kimlik$uid <- 7L
    mergen_session_owner_transition(session$userData, 0L, 7L)
    session$flushReact()
    tam_once <- rec$full
    eski_coz()
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    session$flushReact()
    testthat::expect_false("eski-on-izleme" %in% names(shiny::isolate(session$userData$.values$saved_chats)))
    testthat::expect_identical(rec$full, tam_once)
    # Yerine geçen ön izleme kimlik dönünce uygulanır ve tam bir tam liste başlatır.
    yeni_coz <- rec$resolve_preview
    testthat::expect_false(identical(yeni_coz, eski_coz), info = "kimlik dönünce yeni ön izleme gönderilmeli")
    yeni_coz()
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    session$flushReact()
    testthat::expect_true("yeni-on-izleme" %in% names(shiny::isolate(session$userData$.values$saved_chats)))
    testthat::expect_identical(rec$full, tam_once + 1L)
  })
})

# Hızlı şerit tam listesi: karşılama yalnızca görünen "Son Konuşmalar" dilimi
# değiştiyse yeniden çizilir; geçmiş satır hazırlığı (yonetim_hazirla) bu
# şeritte başlatılmaz (paylaşılan işçi kuyruğu spekülatif okumayla dolmaz).
.hizli_serit_tam_liste_senaryosu <- function(tam_liste) {
  .startup_observers_source_once()
  # Görünen dilim karşılaştırması üretimdeki karşılama yardımcısını kullanır
  # (çalışma zamanında kaynak manifestiyle yüklenir).
  if (!exists("mergen_welcome_recent_items", envir = globalenv(), mode = "function")) {
    source(file.path(resolve_repo_root_for_tests(), "R", "welcome_screen_modern.R"),
           encoding = "UTF-8", local = globalenv())
  }
  zaman <- function(saat) as.POSIXct(sprintf("2026-07-01 %02d:00:00", saat), tz = "UTC")
  rec <- new.env()
  rec$preview_result <- list(
    "p1" = list(title = "Bir", message_count = 1L, last_message_timestamp = zaman(10)),
    "p2" = list(title = "İki", message_count = 1L, last_message_timestamp = zaman(9)),
    "p3" = list(title = "Üç", message_count = 1L, last_message_timestamp = zaman(8)))
  rec$full_result <- tam_liste(rec$preview_result, zaman)
  rec$defer_full_fulfillment <- TRUE
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)
  js <- character()
  testthat::local_mocked_bindings(runjs = function(code) js <<- c(js, code), .package = "shinyjs")
  sonuc <- new.env()
  shiny::testServer(function(input, output, session) {
    cizim <- 0L
    session$userData$deep_space_dismissed <- TRUE
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(input = input, session = session, values = values,
                         render_welcome_screen = function(...) { cizim <<- cizim + 1L; invisible(NULL) },
                         current_user_id = function() 42L, sso_state = NULL, boot_ready = NULL)
    session$userData$.values <- values
    session$userData$.cizim <- function() cizim
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))
    session$setInputs(welcome_client_ready = list(fast_lane = TRUE, timestamp = 1))
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    session$flushReact()
    testthat::expect_true(is.function(rec$resolve_full), info = "ön izlemeden sonra tam liste gönderilmeli")
    sonuc$once <- session$userData$.cizim()
    rec$resolve_full()
    for (i in 1:5) later::run_now(timeoutSecs = 0.05)
    session$flushReact()
    sonuc$sonra <- session$userData$.cizim()
    sonuc$tam_yuklendi <- isTRUE(session$userData$saved_chats_full_loaded)
    sonuc$adlar <- names(shiny::isolate(session$userData$.values$saved_chats))
  })
  sonuc$js <- js
  sonuc
}

testthat::test_that("hızlı şerit tam listesi görünen dilim aynıysa karşılamayı yeniden çizmez ve geçmiş hazırlığını başlatmaz", {
  testthat::skip_if_not_installed("shiny"); testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises"); testthat::skip_if_not_installed("later")
  sonuc <- .hizli_serit_tam_liste_senaryosu(function(on_izleme, zaman) {
    c(on_izleme, list("eski" = list(title = "Eski", message_count = 3L, last_message_timestamp = zaman(1))))
  })
  testthat::expect_true(sonuc$tam_yuklendi)
  testthat::expect_true("eski" %in% sonuc$adlar)
  testthat::expect_identical(sonuc$sonra, sonuc$once, info = "görünen dilim değişmediyse yeniden çizim olmamalı")
  testthat::expect_false(any(grepl("history_module-hazirla", sonuc$js, fixed = TRUE)),
                         info = "hızlı şeritte geçmiş hazırlığı başlatılmamalı")
})

testthat::test_that("hızlı şerit tam listesi görünen dilimi değiştirirse karşılama bir kez yeniden çizilir", {
  testthat::skip_if_not_installed("shiny"); testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises"); testthat::skip_if_not_installed("later")
  sonuc <- .hizli_serit_tam_liste_senaryosu(function(on_izleme, zaman) {
    c(list("yeni" = list(title = "Daha yeni", message_count = 1L, last_message_timestamp = zaman(11))), on_izleme)
  })
  testthat::expect_true(sonuc$tam_yuklendi)
  testthat::expect_identical(sonuc$sonra, sonuc$once + 1L)
  testthat::expect_false(any(grepl("history_module-hazirla", sonuc$js, fixed = TRUE)),
                         info = "karşılamanın yeniden çizimi geçmiş hazırlığını başlatmamalı")
})

# Ön izleme sözünün devamı (hidrasyon kararı) sınırlı bir sürede gerçekten
# tamamlanana dek döngü çalıştırılır; söz yoksa, reddedilirse ya da süre
# dolarsa test başarısız olur (geçen döngü turu tamamlanma kanıtı sayılmaz).
.on_izleme_sozunu_bekle <- function(session, sure = 5) {
  soz <- session$userData$initial_saved_chats_preview_promise
  testthat::expect_true(promises::is.promise(soz), info = "ön izleme sözü saklanmalı")
  if (!promises::is.promise(soz)) return(invisible(FALSE))
  durum <- new.env(); durum$bitti <- FALSE; durum$hata <- NULL
  promises::then(soz, onFulfilled = function(...) durum$bitti <- TRUE,
                 onRejected = function(e) { durum$hata <- conditionMessage(e); durum$bitti <- TRUE })
  son <- Sys.time() + sure
  while (!isTRUE(durum$bitti) && Sys.time() < son) later::run_now(timeoutSecs = 0.05)
  testthat::expect_true(isTRUE(durum$bitti), info = "ön izleme sözü süre içinde tamamlanmalı")
  testthat::expect_null(durum$hata)
  session$flushReact()
  invisible(isTRUE(durum$bitti))
}

# Tümünü Temizle/silme senaryoları için ortak gecikmiş ön izleme düzeneği.
.gecikmis_on_izleme <- function(rec, kurulum) {
  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(input = input, session = session, values = values,
                         render_welcome_screen = function(...) invisible(NULL),
                         current_user_id = function() 42L, sso_state = NULL, boot_ready = NULL)
    session$userData$.values <- values
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))
    session$setInputs(welcome_client_ready = list(fast_lane = TRUE, timestamp = 1))
    testthat::expect_true(is.function(rec$resolve_preview))
    kurulum(session)
    rec$resolve_preview()
    .on_izleme_sozunu_bekle(session)
    rec$adlar <- names(shiny::isolate(session$userData$.values$saved_chats))
    rec$silinenler <- session$userData$saved_chats_silinenler
  })
  rec
}

.gecikmis_on_izleme_rec <- function() {
  rec <- new.env()
  rec$defer_preview_fulfillment <- TRUE
  rec$preview_result <- list("silinen" = list(title = "Silinen", message_count = 1L),
                             "kalan" = list(title = "Kalan", message_count = 1L))
  rec$async_worker_ready <- FALSE
  rec
}

testthat::test_that("gecikmiş ön izleme (denetim): durum değişmediyse söyleşiler yayımlanır", {
  testthat::skip_if_not_installed("shiny"); testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises"); testthat::skip_if_not_installed("later")
  .startup_observers_source_once()
  rec <- .gecikmis_on_izleme_rec()
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)
  .gecikmis_on_izleme(rec, function(session) invisible(NULL))
  testthat::expect_setequal(rec$adlar, c("silinen", "kalan"))
})

testthat::test_that("gecikmiş ön izleme doğrulanmış silinen söyleşiyi geri getirmez", {
  testthat::skip_if_not_installed("shiny"); testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises"); testthat::skip_if_not_installed("later")
  .startup_observers_source_once()
  rec <- .gecikmis_on_izleme_rec()
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)
  # Galeri hidrasyonu söyleşinin DB'de olmadığını doğruladı (yerel listeye dokunmadan).
  .gecikmis_on_izleme(rec, function(session) session$userData$saved_chats_silinenler <- "silinen")
  testthat::expect_identical(rec$adlar, "kalan")
})

testthat::test_that("oturum sahibi değişince önceki sahibin silinenler kümesi temizlenir", {
  testthat::skip_if_not_installed("shiny"); testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises"); testthat::skip_if_not_installed("later")
  .startup_observers_source_once()
  if (!exists("mergen_session_owner_transition", envir = globalenv(), mode = "function")) {
    source(file.path(resolve_repo_root_for_tests(), "R", "helpers_user_session_identity.R"),
           encoding = "UTF-8", local = globalenv())
  }
  rec <- .gecikmis_on_izleme_rec()
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)
  shiny::testServer(function(input, output, session) {
    session$userData$kimlik_sahibi <- 42L
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(input = input, session = session, values = values,
                         render_welcome_screen = function(...) invisible(NULL),
                         current_user_id = function() 42L, sso_state = NULL, boot_ready = NULL)
  }, {
    session$flushReact()
    session$userData$saved_chats_silinenler <- c("7", "9")
    mergen_session_owner_transition(session$userData, 42L, 43L)
    testthat::expect_identical(session$userData$saved_chats_silinenler, character())
  })
})

testthat::test_that("Tümünü Temizle sonrası (değer eşit olsa da) gecikmiş ön izleme silinen söyleşileri geri getirmez", {
  testthat::skip_if_not_installed("shiny"); testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises"); testthat::skip_if_not_installed("later")
  .startup_observers_source_once()
  rec <- new.env()
  rec$defer_preview_fulfillment <- TRUE
  rec$preview_result <- list("silinen" = list(title = "Silinen", message_count = 1L))
  # Arka plan tam listesi devre dışı: sonuç yalnızca ön izleme kararını gösterir.
  rec$async_worker_ready <- FALSE
  stubs <- .with_startup_db_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)
  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list())
    startupObserversInit(input = input, session = session, values = values,
                         render_welcome_screen = function(...) invisible(NULL),
                         current_user_id = function() 42L, sso_state = NULL, boot_ready = NULL)
    session$userData$.values <- values
  }, {
    session$flushReact()
    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "stored", ts = 1))
    session$setInputs(welcome_client_ready = list(fast_lane = TRUE, timestamp = 1))
    testthat::expect_true(is.function(rec$resolve_preview))
    # Gönderim yapıldı, söyleşi oluştu, Tümünü Temizle listeyi yeniden boşalttı:
    # değer gönderimdeki görüntüye eşit, ama yetkili sürüm arttı.
    session$userData$saved_chats_yetkili_surum <- 1L
    rec$resolve_preview()
    .on_izleme_sozunu_bekle(session)
    testthat::expect_length(shiny::isolate(session$userData$.values$saved_chats), 0L)
  })
})
