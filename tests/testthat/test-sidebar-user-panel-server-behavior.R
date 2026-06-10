# ==============================================================================
# Dosya Yolu: tests/testthat/test-sidebar-user-panel-server-behavior.R
# Açıklama: R/module_sidebar_user_panel.R davranış testleri:
#           - mb_sidebar_theme_switch(): tema butonu UI sözleşmesi,
#           - mb_sidebar_handle_logout_event(): logout olayında oturum kapatma
#             ve kimlik bilgisini loglama,
#           - mb_sidebar_user_panel_server(): kimlik durumlarına göre rozet
#             render'ı (yedek/Hazırlanıyor/tam kimlik) ve logout observer wiring.
#           Gerçek SSO/DB/tarayıcı GEREKMEZ; kimlik bir liste ile taklit edilir.
# ==============================================================================

testthat::local_edition(3)

suppressMessages({
  if (requireNamespace("shiny", quietly = TRUE)) library(shiny)
})

.sidebar_env <- function() {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  # Saf görünüm yardımcıları manifest sırasına uygun olarak modülden önce
  # yüklenir (R/helpers_sidebar_user_display.R).
  suppressMessages(source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_sidebar_user_display.R"),
    encoding = "UTF-8", local = env
  ))
  suppressMessages(source(
    file.path(resolve_repo_root_for_tests(), "R", "module_sidebar_user_panel.R"),
    encoding = "UTF-8", local = env
  ))
  env
}

# --- mb_sidebar_theme_switch --------------------------------------------------

test_that("mb_sidebar_theme_switch tema butonu sözleşmesini üretir", {
  env <- .sidebar_env()
  html <- paste(as.character(env$mb_sidebar_theme_switch()), collapse = "")
  expect_true(grepl("mb-theme-switch-btn", html, fixed = TRUE))
  expect_true(grepl("data-mergen-theme-toggle", html, fixed = TRUE))
  expect_true(grepl("Temayı değiştir", html, fixed = TRUE))
  expect_true(grepl("Koyu Tema", html, fixed = TRUE))
  # Güneş + ay ikonları mevcut olmalı.
  expect_true(grepl("theme-switch-sun", html, fixed = TRUE))
  expect_true(grepl("theme-switch-moon", html, fixed = TRUE))
})

# --- mb_sidebar_handle_logout_event -------------------------------------------

test_that("mb_sidebar_handle_logout_event oturumu kapatır ve kimliği loglar", {
  env <- .sidebar_env()
  rec <- new.env()
  rec$closed <- FALSE
  rec$logmsg <- ""
  env$log_info <- function(m, ...) { rec$logmsg <- m; invisible(NULL) }

  identity <- list(
    resolve_current_user_id = function() 42L,
    get_display_name = function(default = "") "Ada Lovelace"
  )
  fake_session <- list(close = function() { rec$closed <- TRUE; invisible(NULL) })

  suppressMessages(env$mb_sidebar_handle_logout_event(identity, fake_session))

  expect_true(rec$closed)
  expect_true(grepl("42", rec$logmsg, fixed = TRUE))
  expect_true(grepl("Ada Lovelace", rec$logmsg, fixed = TRUE))
})

test_that("mb_sidebar_handle_logout_event kimlik/oturum NULL olsa bile hatasız döner", {
  env <- .sidebar_env()
  env$log_info <- function(...) invisible(NULL)
  expect_silent(suppressMessages(env$mb_sidebar_handle_logout_event(NULL, NULL)))
})

# --- mb_sidebar_user_panel_server (testServer) --------------------------------

# Sunucu fonksiyonunu bir moduleServer kabuğuyla saran yardımcı.
.sidebar_server_wrapper <- function(env, identity, sso_state = NULL,
                                    logout_url = "", logout_recorder = NULL) {
  env$mergen_resolve_logout_url <- function() logout_url
  if (!is.null(logout_recorder)) {
    env$mb_sidebar_handle_logout_event <- function(identity, session) {
      logout_recorder$called <- TRUE
      invisible(NULL)
    }
  }
  function(id) {
    shiny::moduleServer(id, function(input, output, session) {
      env$mb_sidebar_user_panel_server(
        output = output,
        identity = identity,
        sso_state = sso_state,
        output_id = "sidebar_user_panel",
        session = session,
        input = input
      )
    })
  }
}

.sidebar_panel_html <- function(output_value) {
  paste(as.character(output_value), collapse = " ")
}

test_that("kimlik sözleşmesi yoksa yedek 'Yerel Kullanıcı' rozeti render edilir", {
  skip_if_not_installed("shiny")
  env <- .sidebar_env()

  shiny::testServer(.sidebar_server_wrapper(env, identity = NULL),
                    args = list(id = "sb"), {
    html <- .sidebar_panel_html(output$sidebar_user_panel)
    expect_true(grepl("Yerel Kullanıcı", html, fixed = TRUE))
  })
})

test_that("SSO aktif ama kimlik hazır değilken 'Oturum hazırlanıyor' rozeti gösterilir", {
  skip_if_not_installed("shiny")
  env <- .sidebar_env()
  identity <- list(
    get_display_name = function(default = "") "",
    get_first_name = function(default = "") "",
    resolve_current_user_id = function() 0L,
    is_auth_ready = function() FALSE,
    is_sso_active = function() TRUE,
    get_user_config = function(default = NULL) default
  )

  shiny::testServer(.sidebar_server_wrapper(env, identity = identity),
                    args = list(id = "sb"), {
    html <- .sidebar_panel_html(output$sidebar_user_panel)
    expect_true(grepl("Oturum hazırlanıyor", html, fixed = TRUE))
    expect_true(grepl("Kimlik doğrulanıyor", html, fixed = TRUE))
  })
})

test_that("kimlik hazırken rozet tam adı ve Departman bilgisini gösterir", {
  skip_if_not_installed("shiny")
  env <- .sidebar_env()
  identity <- list(
    get_display_name = function(default = "") "Mustafa Karadağ",
    get_first_name = function(default = "") "Mustafa",
    resolve_current_user_id = function() 1234L,
    is_auth_ready = function() TRUE,
    is_sso_active = function() FALSE,
    get_user_config = function(default = NULL) list(Departman = "Bilgi İşlem", sicil = "5678"),
    user_config_rv = function() list(Departman = "Bilgi İşlem", sicil = "5678")
  )

  shiny::testServer(.sidebar_server_wrapper(env, identity = identity),
                    args = list(id = "sb"), {
    html <- .sidebar_panel_html(output$sidebar_user_panel)
    expect_true(grepl("Mustafa Karadağ", html, fixed = TRUE))
    expect_true(grepl("Bilgi İşlem", html, fixed = TRUE))
  })
})

test_that("logout URL yapılandırılmışsa kontrol satırı çıkış butonu içerir", {
  skip_if_not_installed("shiny")
  env <- .sidebar_env()

  shiny::testServer(
    .sidebar_server_wrapper(env, identity = NULL, logout_url = "https://portal.kurum/logout"),
    args = list(id = "sb"), {
      controls <- .sidebar_panel_html(output$sidebar_user_panel_controls)
      expect_true(grepl("mb-sidebar-logout-btn", controls, fixed = TRUE))
      expect_true(grepl("Oturumu kapat", controls, fixed = TRUE))
    }
  )
})

test_that("logout URL yokken kontrol satırında çıkış butonu render EDİLMEZ", {
  skip_if_not_installed("shiny")
  env <- .sidebar_env()

  shiny::testServer(.sidebar_server_wrapper(env, identity = NULL, logout_url = ""),
                    args = list(id = "sb"), {
    controls <- .sidebar_panel_html(output$sidebar_user_panel_controls)
    expect_false(grepl("mb-sidebar-logout-btn", controls, fixed = TRUE))
    # Tema butonu yine de mevcut olmalı.
    expect_true(grepl("mb-theme-switch-btn", controls, fixed = TRUE))
  })
})

test_that("mergen_sidebar_logout input'u logout işleyicisini tetikler", {
  skip_if_not_installed("shiny")
  env <- .sidebar_env()
  rec <- new.env(); rec$called <- FALSE

  shiny::testServer(
    .sidebar_server_wrapper(env, identity = NULL, logout_recorder = rec),
    args = list(id = "sb"), {
      # observeEvent ignoreInit = TRUE: ilk değer init sayılıp atlanabildiği için
      # PRIME-THEN-SET kalıbı kullanılır (önce primele, sonra gerçek tetik).
      session$setInputs(mergen_sidebar_logout = 1)
      session$setInputs(mergen_sidebar_logout = 2)
      expect_true(rec$called)
    }
  )
})
