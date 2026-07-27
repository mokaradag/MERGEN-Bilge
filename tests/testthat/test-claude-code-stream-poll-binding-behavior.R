# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-stream-poll-binding-behavior.R
# Açıklama: cc_bind_claude_code_stream_polling (R/module_claude_code_stream_poll.R)
#           Bilge Yolaç canlı akış gözlemci bağlayıcısının DETERMİNİSTİK
#           dallarını testServer ile test eder:
#             * stop_command gözlemcisi: çalışırken env$durduruldu=TRUE, süreç
#               öldürülür, cc-stream-end gönderilir ve finalize_streaming
#               REQUEST-ID kapsamlı "Durduruldu" ile çağrılır (korumalı sözleşme);
#               çalışmıyorken HİÇBİR ŞEY yapılmaz.
#             * prompt_submit_key gözlemcisi: çalışmıyorken run_command'a tıklar,
#               çalışırken tıklamaz.
#             * poll gözlemcisi erken dalları: env$durduruldu=TRUE -> finalize
#               "Durduruldu" (request-id kapsamlı); zaman aşımı -> finalize
#               "Zaman Aşımı" + cc-add-message hata mesajı.
#           invalidateLater(200) döngüsü TETİKLENMEZ (zaman ilerletilmez); her
#           dal tek bir flush ile çalışır. Gerçek CLI/süreç/DB/ağ GEREKMEZ.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

# module_claude_code_stream_poll.R'yi izole ortama yükler; yalnızca hedef
# dallarda erişilen yardımcıları stub'lar (CLAUDE_CODE_LOG_PREFIX, ensure_utf8).
.csp_env <- function() {
  env <- new.env(parent = globalenv())
  env$CLAUDE_CODE_LOG_PREFIX <- "[BILGE-YOLAC-TEST]"
  env$ensure_utf8 <- function(x) x
  env$cc_release_runtime_lease <- function(...) invisible(TRUE)
  # Yalnızca süreç bitişi (!proc$is_alive()) dalına ulaşan testler için
  # gereklidir; erken dallar (durduruldu/zaman aşımı) buna hiç ulaşmaz.
  env$parse_claude_code_json_output <- function(text) {
    list(text_output = "", tool_uses = list(), session_id = NULL)
  }
  source(file.path(resolve_repo_root_for_tests(), "R", "module_claude_code_stream_poll.R"),
         encoding = "UTF-8", local = env)
  env
}

# Sahte processx süreci: kill / poll_io / read_* / is_alive / get_exit_status.
.csp_fake_proc <- function(alive = TRUE) {
  p <- new.env(parent = emptyenv())
  p$killed <- FALSE
  p$kill <- function() { p$killed <- TRUE; invisible(NULL) }
  p$poll_io <- function(...) invisible(NULL)
  p$read_output_lines <- function() character(0)
  p$read_all_output <- function() ""
  p$read_all_error <- function() ""
  p$is_alive <- function() alive
  p$get_exit_status <- function() 0L
  p
}

# Akış ortam nesnesi (plain env -> reaktif değil, gözlemciyi tetiklemez).
.csp_stream_env <- function(...) {
  e <- new.env(parent = emptyenv())
  e$durduruldu <- FALSE
  e$baslangic <- Sys.time()
  e$zaman_asimi <- 600
  e$tum_satirlar <- character(0)
  e$request_id <- "rid"
  e$prompt <- "merhaba"
  e$user_id <- 1L
  e$session_token <- "tok"
  e$calisma_dizini <- tempdir()
  e$kaynak_calisma_dizini <- tempdir()
  dots <- list(...)
  for (n in names(dots)) e[[n]] <- dots[[n]]
  e
}

# finalize_streaming kaydedici.
.csp_finalize_rec <- function() {
  r <- new.env(parent = emptyenv())
  r$calls <- list()
  r
}

# Bağlayıcıyı saran küçük modül sunucusu; rv döndürür ki testte değiştirilebilsin.
.csp_make_server <- function(env, rv_init, finalize_rec) {
  function(id) {
    shiny::moduleServer(id, function(input, output, session) {
      rv <- do.call(shiny::reactiveValues, rv_init)
      env$cc_bind_claude_code_stream_polling(
        input = input,
        session = session,
        ns = session$ns,
        rv = rv,
        send_parca = function(parca, e) invisible(NULL),
        finalize_streaming = function(durum_metin, durum_ikon, durum_renk,
                                      sure = NULL, request_id = NULL) {
          finalize_rec$calls[[length(finalize_rec$calls) + 1L]] <- list(
            durum = durum_metin, ikon = durum_ikon, renk = durum_renk,
            sure = sure, request_id = request_id
          )
          invisible(TRUE)
        },
        observe_dir_contents = function(...) invisible(NULL)
      )
      rv
    })
  }
}

testthat::test_that("stop_command çalışırken: durduruldu işaretlenir, süreç öldürülür, request-id kapsamlı finalize", {
  testthat::skip_if_not_installed("shiny")
  env <- .csp_env()
  fin <- .csp_finalize_rec()
  sp <- .csp_stream_env(request_id = "rid-stop")
  proc <- .csp_fake_proc(alive = TRUE)
  srv <- .csp_make_server(env, list(
    is_running = TRUE, active_process = proc, stream_env = sp,
    poll_state = NULL, active_request_id = "ar-1"
  ), fin)

  shiny::testServer(srv, {
    rec <- new.env(parent = emptyenv()); rec$msgs <- list()
    root <- .subset2(session, "parent")
    root$sendCustomMessage <- function(type, message) {
      rec$msgs[[length(rec$msgs) + 1L]] <- list(type = type, message = message)
      invisible(NULL)
    }

    session$setInputs(stop_command = 1)

    testthat::expect_true(sp$durduruldu)
    testthat::expect_true(proc$killed)
    testthat::expect_length(fin$calls, 1L)
    testthat::expect_identical(fin$calls[[1]]$durum, "Durduruldu")
    testthat::expect_identical(fin$calls[[1]]$request_id, "rid-stop")
    # Stop gözlemcisi cc-stream-end yayınlamalı.
    testthat::expect_true(any(vapply(rec$msgs,
      function(m) identical(m$type, "cc-stream-end"), logical(1))))
  })
})

testthat::test_that("stop_command çalışmıyorken hiçbir şey yapmaz", {
  testthat::skip_if_not_installed("shiny")
  env <- .csp_env()
  fin <- .csp_finalize_rec()
  proc <- .csp_fake_proc(alive = TRUE)
  srv <- .csp_make_server(env, list(
    is_running = FALSE, active_process = proc, stream_env = .csp_stream_env(),
    poll_state = NULL, active_request_id = "ar-1"
  ), fin)

  shiny::testServer(srv, {
    session$setInputs(stop_command = 1)
    testthat::expect_length(fin$calls, 0L)
    testthat::expect_false(proc$killed)
  })
})

testthat::test_that("prompt_submit_key çalışmıyorken run_command'a tıklar", {
  testthat::skip_if_not_installed("shiny")
  env <- .csp_env()
  fin <- .csp_finalize_rec()
  clicked <- new.env(parent = emptyenv()); clicked$ids <- character(0)
  testthat::local_mocked_bindings(
    click = function(id, ...) { clicked$ids <- c(clicked$ids, id); invisible(NULL) },
    .package = "shinyjs"
  )
  srv <- .csp_make_server(env, list(
    is_running = FALSE, active_process = NULL, stream_env = NULL,
    poll_state = NULL, active_request_id = "ar-1"
  ), fin)

  shiny::testServer(srv, {
    session$setInputs(prompt_submit_key = 1)
    testthat::expect_true("run_command" %in% clicked$ids)
  })
})

testthat::test_that("prompt_submit_key çalışırken tıklamaz", {
  testthat::skip_if_not_installed("shiny")
  env <- .csp_env()
  fin <- .csp_finalize_rec()
  clicked <- new.env(parent = emptyenv()); clicked$ids <- character(0)
  testthat::local_mocked_bindings(
    click = function(id, ...) { clicked$ids <- c(clicked$ids, id); invisible(NULL) },
    .package = "shinyjs"
  )
  # active_process = NULL -> poll gözlemcisi req(!is.null(proc)) ile erken çıkar.
  srv <- .csp_make_server(env, list(
    is_running = TRUE, active_process = NULL, stream_env = NULL,
    poll_state = NULL, active_request_id = "ar-1"
  ), fin)

  shiny::testServer(srv, {
    session$setInputs(prompt_submit_key = 1)
    testthat::expect_false("run_command" %in% clicked$ids)
  })
})

testthat::test_that("poll gözlemcisi env$durduruldu=TRUE: request-id kapsamlı 'Durduruldu' finalize + kill", {
  testthat::skip_if_not_installed("shiny")
  env <- .csp_env()
  fin <- .csp_finalize_rec()
  proc <- .csp_fake_proc(alive = TRUE)
  sp <- .csp_stream_env(durduruldu = TRUE, request_id = "rid-poll")
  # is_running başlangıçta FALSE; expr içinde TRUE'ya çevrilince poll dalı çalışır.
  srv <- .csp_make_server(env, list(
    is_running = FALSE, active_process = proc, stream_env = sp,
    poll_state = NULL, active_request_id = "ar-1"
  ), fin)

  shiny::testServer(srv, {
    session$returned$is_running <- TRUE
    session$flushReact()

    testthat::expect_true(proc$killed)
    testthat::expect_length(fin$calls, 1L)
    testthat::expect_identical(fin$calls[[1]]$durum, "Durduruldu")
    testthat::expect_identical(fin$calls[[1]]$request_id, "rid-poll")
  })
})

testthat::test_that("cikti isleme worker gonderimi senkron hata verirse: rapor edilir ve state serbest kalir", {
  testthat::skip_if_not_installed("shiny")
  env <- .csp_env()
  fin <- .csp_finalize_rec()
  proc <- .csp_fake_proc(alive = FALSE)
  sp <- .csp_stream_env(request_id = "rid-dispatch-fail")

  rapor <- new.env(parent = emptyenv())
  rapor$ctx <- NULL
  rapor$hata <- NULL

  env$cc_dispatch_run_output_processing <- function(ctx) {
    stop("worker gonderilemedi: kume coktu")
  }
  env$cc_report_output_processing_failure <- function(ctx, error) {
    rapor$ctx <- ctx
    rapor$hata <- error
    invisible(TRUE)
  }

  srv <- .csp_make_server(env, list(
    is_running = TRUE, active_process = proc, stream_env = sp,
    poll_state = NULL, active_request_id = "ar-1"
  ), fin)

  shiny::testServer(srv, {
    session$flushReact()

    # rv$active_process senkron dispatch hatasına rağmen NULL'a çekilmiş
    # olmalı; aksi halde durum "hazırlanıyor"da takılı kalır.
    testthat::expect_null(session$returned$active_process)
    testthat::expect_false(is.null(rapor$ctx))
    testthat::expect_identical(rapor$ctx$env, sp)
    testthat::expect_true(grepl("kume coktu", conditionMessage(rapor$hata), fixed = TRUE))
    # Bu dal finalize_streaming'i DOĞRUDAN çağırmaz; hata raporlama
    # cc_report_output_processing_failure'a devredilir (yukarıda stub'landı).
    testthat::expect_length(fin$calls, 0L)
  })
})

testthat::test_that("poll gözlemcisi zaman aşımı: 'Zaman Aşımı' finalize + cc-add-message hata mesajı", {
  testthat::skip_if_not_installed("shiny")
  env <- .csp_env()
  fin <- .csp_finalize_rec()
  proc <- .csp_fake_proc(alive = TRUE)
  sp <- .csp_stream_env(
    durduruldu = FALSE,
    baslangic = Sys.time() - 1000,  # 1000 sn önce -> zaman aşımı
    zaman_asimi = 10,
    request_id = "rid-timeout"
  )
  srv <- .csp_make_server(env, list(
    is_running = FALSE, active_process = proc, stream_env = sp,
    poll_state = NULL, active_request_id = "ar-1"
  ), fin)

  shiny::testServer(srv, {
    rec <- new.env(parent = emptyenv()); rec$msgs <- list()
    root <- .subset2(session, "parent")
    root$sendCustomMessage <- function(type, message) {
      rec$msgs[[length(rec$msgs) + 1L]] <- list(type = type, message = message)
      invisible(NULL)
    }

    session$returned$is_running <- TRUE
    session$flushReact()

    testthat::expect_true(proc$killed)
    testthat::expect_length(fin$calls, 1L)
    testthat::expect_identical(fin$calls[[1]]$durum, "Zaman Aşımı")
    testthat::expect_identical(fin$calls[[1]]$request_id, "rid-timeout")
    # Kullanıcıya zaman aşımı hata mesajı gönderilmeli.
    err_msgs <- Filter(function(m) identical(m$type, "cc-add-message"), rec$msgs)
    testthat::expect_true(length(err_msgs) >= 1L)
    testthat::expect_identical(err_msgs[[1]]$message$type, "error")
    testthat::expect_true(grepl("zaman aşımına", err_msgs[[1]]$message$content, fixed = TRUE))
  })
})
