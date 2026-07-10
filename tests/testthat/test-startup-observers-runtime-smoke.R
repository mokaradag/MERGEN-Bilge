# ==============================================================================
# Dosya Yolu: tests/testthat/test-startup-observers-runtime-smoke.R
# Açıklama: startupObserversInit() davranışsal runtime smoke testleri.
#           1) Geçersiz/placeholder kullanıcı kimliği (0) ile kayıtlı sohbet
#              yüklemesinin ATLANMASI (SSO kimlik kayması koruması) ve
#              karşılama ekranının başlangıçta render edilmesi.
#           2) Başlangıç şeridi yarış düzeltmesi: şerit çözülmeden hiçbir
#              kayıtlı sohbet DB çağrısı başlamaz; Hızlı Başlangıç'ta tam
#              liste açılışta YÜKLENMEZ ve ön izleme kritik yolu bloklamaz;
#              tam liste Kayıtlı Söyleşiler/Geçmiş ilk açıldığında bir kez
#              tembel yüklenir; zengin şerit davranışı korunur.
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
.with_startup_db_stubs <- function(rec) {
  names <- c("load_chats_preview_from_db", "load_chats_from_db", "tracked_future_promise")
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
    rec$in_future <- TRUE
    on.exit(rec$in_future <- FALSE, add = TRUE)
    result <- task_fn()
    if (identical(task_type, "startup_saved_chats_preview") &&
        isTRUE(rec$defer_preview_fulfillment)) {
      return(promises::promise(function(resolve, reject) {
        rec$resolve_preview <- function() resolve(result)
      }))
    }
    promises::promise_resolve(result)
  }, envir = globalenv())

  list(restore = function() {
    for (nm in names) {
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

    # Kayıtlı sohbet durumu boş kalmalı (yanlış kullanıcıdan veri sızmamalı).
    testthat::expect_identical(length(session$userData$.values$saved_chats), 0L)

    # Karşılama ekranı başlangıçta yine de render edilmeli.
    testthat::expect_gte(session$userData$.welcome_render_count(), 1L)
  })
})

testthat::test_that("hızlı şeritte açılış tam liste yüklemez, ön izleme kritik yolu bloklamaz", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  .startup_observers_source_once()

  rec <- new.env()
  rec$preview_result <- list(
    "preview-chat" = list(title = "Ön izleme", message_count = 0L)
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

    # Şerit çözülmeden HİÇBİR kayıtlı sohbet DB çağrısı başlamaz (yarış düzeltmesi).
    testthat::expect_identical(rec$preview, 0L)
    testthat::expect_identical(rec$full, 0L)
    # Kimlik hazır: auth_ready şerit beklenirken işaretlenmiş olmalı.
    testthat::expect_true("auth_ready" %in% boot_ready$keys())

    session$setInputs(startup_lane_resolved = list(lane = "fast_lane", source = "selector", ts = 1))

    # Hızlı şerit: tam yükleme AÇILIŞTA çalışmaz.
    testthat::expect_identical(rec$full, 0L)
    testthat::expect_false("startup_saved_chats" %in% rec$future_types)

    # Ön izleme kritik yolu bloklamaz: yalnızca worker sarmalayıcı içinden çağrılır.
    testthat::expect_identical(rec$preview, 1L)
    testthat::expect_identical(rec$preview_in_future, TRUE)
    testthat::expect_true("startup_saved_chats_preview" %in% rec$future_types)

    # Arada daha yeni bir durum oluşmadığında normal hızlı-şerit ön izlemesi uygulanır.
    later::run_now(timeoutSecs = 0.1)
    session$flushReact()
    testthat::expect_true(
      "preview-chat" %in% names(session$userData$.values$saved_chats)
    )

    # Tembel yükleme bekleniyor işareti ve dürüst ertelenmiş kontrol noktası.
    testthat::expect_true(isTRUE(session$userData$saved_chats_full_pending))
    full_marks <- Filter(function(e) identical(e$key, "saved_chats_full_loaded"), boot_ready$entries())
    testthat::expect_true(length(full_marks) >= 1L)
    testthat::expect_true(isTRUE(full_marks[[1]]$detail$deferred))
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

    # Worker sonucu hazır olsa da fulfillment bilerek bekletilir.
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
