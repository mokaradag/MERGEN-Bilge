# ==============================================================================
# Dosya Yolu: tests/testthat/test-startup-observers-runtime-smoke.R
# Açıklama: startupObserversInit() davranışsal runtime smoke testi. Geçersiz/
#           placeholder kullanıcı kimliği (0) ile kayıtlı sohbet yüklemesinin
#           ATLANMASINI (SSO kimlik kayması koruması) ve karşılama ekranının
#           başlangıçta render edilmesini gerçek reaktif tur içinde doğrular.
#           DB/LLM/tarayıcı gerekmez; DB yükleyiciler stub'lanır.
# ==============================================================================

.startup_observers_source_once <- function() {
  needs <- !exists("startupObserversInit", envir = globalenv(),
                   mode = "function", inherits = TRUE) ||
           !exists("resolve_effective_user_id", envir = globalenv(),
                   mode = "function", inherits = TRUE)
  if (!needs) {
    return(invisible(TRUE))
  }

  # startupObserversInit resolve_effective_user_id'e (utils_common) bağımlıdır.
  source(
    file.path(resolve_repo_root_for_tests(), "R", "utils_common.R"),
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
.with_startup_db_stubs <- function(rec) {
  names <- c("load_chats_preview_from_db", "load_chats_from_db", "tracked_future_promise")
  had <- vapply(names, exists, logical(1), envir = globalenv(), inherits = FALSE)
  old <- lapply(names, function(nm) {
    if (exists(nm, envir = globalenv(), inherits = FALSE)) get(nm, envir = globalenv()) else NULL
  })
  names(old) <- names

  assign("load_chats_preview_from_db", function(...) {
    rec$preview <- (rec$preview %||% 0L) + 1L
    list()
  }, envir = globalenv())
  assign("load_chats_from_db", function(...) {
    rec$full <- (rec$full %||% 0L) + 1L
    list()
  }, envir = globalenv())
  assign("tracked_future_promise", function(...) {
    rec$future <- (rec$future %||% 0L) + 1L
    NULL
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

testthat::test_that("startupObserversInit geçersiz kullanıcı kimliğinde kayıtlı sohbet yüklemez", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  .startup_observers_source_once()

  rec <- new.env()
  rec$preview <- 0L
  rec$full <- 0L
  rec$future <- 0L
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

    # Kayıtlı sohbet durumu boş kalmalı (yanlış kullanıcıdan veri sızmamalı).
    testthat::expect_identical(length(session$userData$.values$saved_chats), 0L)

    # Karşılama ekranı başlangıçta yine de render edilmeli.
    testthat::expect_gte(session$userData$.welcome_render_count(), 1L)
  })
})
