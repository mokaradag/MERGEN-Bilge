# ==============================================================================
# Dosya Yolu: tests/testthat/test-chat-ui-observers-runtime-smoke.R
# Açıklama: chatUIObserversInit() davranışsal runtime smoke testleri.
#           Yeni söyleşi başlatıldığında analiz araçlarının kapatılmasını ve
#           takip sorusu tıklamasının yalnızca geçerli metinle mesaj
#           göndermesini gerçek reaktif tur içinde doğrular. Tam uygulama,
#           DB, LLM veya tarayıcı gerektirmez.
# ==============================================================================

.chat_ui_observers_source_once <- function() {
  if (exists("chatUIObserversInit", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_observers_chat_ui.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

# showToast global yardımcısı test ortamında stub'lanır ve geri yüklenir.
.with_stubbed_showToast <- function(recorder) {
  had <- exists("showToast", envir = globalenv(), inherits = FALSE)
  old <- if (had) get("showToast", envir = globalenv()) else NULL

  assign("showToast", function(session, message, type = "info", ...) {
    recorder$count <- recorder$count + 1L
    recorder$last <- message
    invisible(TRUE)
  }, envir = globalenv())

  list(
    restore = function() {
      if (had) {
        assign("showToast", old, envir = globalenv())
      } else if (exists("showToast", envir = globalenv(), inherits = FALSE)) {
        rm("showToast", envir = globalenv())
      }
    }
  )
}

testthat::test_that("chatUIObserversInit takip sorusunu yalnızca geçerli metinde gönderir", {
  testthat::skip_if_not_installed("shiny")
  .chat_ui_observers_source_once()

  shiny::testServer(function(input, output, session) {
    sent <- list()
    new_chat_count <- 0L

    chatUIObserversInit(
      input = input,
      session = session,
      values = shiny::reactiveValues(saved_chats = list()),
      start_new_chat = function() new_chat_count <<- new_chat_count + 1L,
      send_message = function(payload) {
        sent[[length(sent) + 1L]] <<- payload
        invisible(TRUE)
      },
      render_welcome_screen = function(...) invisible(NULL),
      settings_data = NULL
    )

    session$userData$.sent <- function() sent
    session$userData$.new_chat_count <- function() new_chat_count
  }, {
    session$flushReact()

    # Geçerli metinli takip sorusu mesaj göndermeli.
    session$setInputs(
      followup_question_clicked = list(text = "Daha fazla detay verir misin?")
    )
    session$flushReact()
    testthat::expect_identical(length(session$userData$.sent()), 1L)

    # Boş metinli takip sorusu mesaj göndermemeli (req(nzchar) kapısı).
    session$setInputs(
      followup_question_clicked = list(text = "")
    )
    session$flushReact()
    testthat::expect_identical(length(session$userData$.sent()), 1L)

    # Yeni söyleşi tetiklenmediği için sayaç sıfır kalmalı.
    testthat::expect_identical(session$userData$.new_chat_count(), 0L)
  })
})

testthat::test_that("chatUIObserversInit yeni söyleşide aktif analiz araçlarını kapatır", {
  testthat::skip_if_not_installed("shiny")
  # Yeni söyleşi yolu shinyjs::runjs / delay çağırdığı için shinyjs gerekir.
  testthat::skip_if_not_installed("shinyjs")
  .chat_ui_observers_source_once()

  toast_recorder <- new.env()
  toast_recorder$count <- 0L
  toast_recorder$last <- NULL
  toast_stub <- .with_stubbed_showToast(toast_recorder)
  on.exit(toast_stub$restore(), add = TRUE)

  shiny::testServer(function(input, output, session) {
    new_chat_count <- 0L

    settings_data <- shiny::reactiveValues(
      enable_rdata_tools = FALSE,
      enable_mcp_tools = TRUE,
      enable_summarization_tools = FALSE,
      enable_coding_tools = TRUE,
      enable_process_tools = FALSE,
      enable_app_expert_tools = FALSE,
      enable_image_tools = FALSE
    )

    chatUIObserversInit(
      input = input,
      session = session,
      values = shiny::reactiveValues(saved_chats = list()),
      start_new_chat = function() new_chat_count <<- new_chat_count + 1L,
      send_message = function(...) invisible(TRUE),
      render_welcome_screen = function(...) invisible(NULL),
      settings_data = settings_data
    )

    session$userData$.settings_data <- settings_data
    session$userData$.new_chat_count <- function() new_chat_count
  }, {
    session$flushReact()

    settings_data <- session$userData$.settings_data

    session$setInputs(new_chat_btn = 1)
    session$flushReact()

    # Tüm analiz araçları kapanmalı.
    analysis_tools <- c(
      "enable_rdata_tools", "enable_mcp_tools", "enable_summarization_tools",
      "enable_coding_tools", "enable_process_tools", "enable_app_expert_tools",
      "enable_image_tools"
    )
    for (tool in analysis_tools) {
      testthat::expect_false(
        isTRUE(settings_data[[tool]]),
        info = paste("Araç kapanmalıydı:", tool)
      )
    }

    # start_new_chat çağrılmış olmalı.
    testthat::expect_identical(session$userData$.new_chat_count(), 1L)

    # En az bir araç aktif olduğu için kullanıcıya bilgi toast'ı gösterilmeli.
    testthat::expect_gte(toast_recorder$count, 1L)
  })
})
