# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-observers-runtime-smoke.R
# Açıklama: fileObserversInit() davranışsal runtime smoke testleri.
#           MCP tek-dosya zorlamasını ve bağlamdan dosya çıkarma davranışını
#           gerçek reaktif tur içinde doğrular. Tam uygulama, DB, LLM veya
#           tarayıcı gerektirmez. processAndSummarizeFile yolu req() ile
#           tetiklenmediğinden ağır özetleme bağımlılığı çalışmaz.
# ==============================================================================

.file_observers_source_once <- function() {
  if (exists("fileObserversInit", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_observers_files.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

.with_stubbed_showToast_file <- function(recorder) {
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

testthat::test_that("fileObserversInit MCP açılınca yalnızca ilk dosyayı tutar", {
  testthat::skip_if_not_installed("shiny")
  .file_observers_source_once()

  toast_rec <- new.env(); toast_rec$count <- 0L
  toast_stub <- .with_stubbed_showToast_file(toast_rec)
  on.exit(toast_stub$restore(), add = TRUE)

  shiny::testServer(function(input, output, session) {
    session_files <- shiny::reactiveVal(list(
      "a.xlsx" = list(name = "a.xlsx"),
      "b.xlsx" = list(name = "b.xlsx"),
      "c.xlsx" = list(name = "c.xlsx")
    ))

    settings_data <- shiny::reactiveValues(enable_mcp_tools = FALSE)

    fm_data <- list(
      set_attachment_checked = function(name, checked) invisible(TRUE),
      files_added_to_context = shiny::reactiveVal(NULL)
    )

    fileObserversInit(
      input = input, session = session, settings_data = settings_data,
      session_files = session_files, file_manager_data = fm_data,
      current_user_id = function() 7L
    )

    session$userData$.session_files <- session_files
    session$userData$.settings_data <- settings_data
  }, {
    session$flushReact()

    session_files <- session$userData$.session_files
    settings_data <- session$userData$.settings_data

    # Başlangıçta 3 dosya var.
    testthat::expect_identical(length(session_files()), 3L)

    # MCP açılınca yalnızca ilk dosya kalmalı.
    settings_data$enable_mcp_tools <- TRUE
    session$flushReact()

    remaining <- names(session_files())
    testthat::expect_identical(length(remaining), 1L)
    testthat::expect_identical(remaining, "a.xlsx")

    # Kaldırılan dosyalar için uyarı toast'ı gösterilmeli.
    testthat::expect_gte(toast_rec$count, 1L)
  })
})

testthat::test_that("fileObserversInit remove_file_from_prompt doğru dosyayı çıkarır", {
  testthat::skip_if_not_installed("shiny")
  .file_observers_source_once()

  toast_rec <- new.env(); toast_rec$count <- 0L
  toast_stub <- .with_stubbed_showToast_file(toast_rec)
  on.exit(toast_stub$restore(), add = TRUE)

  shiny::testServer(function(input, output, session) {
    unchecked_names <- character(0)

    session_files <- shiny::reactiveVal(list(
      "rapor.pdf" = list(name = "rapor.pdf"),
      "veri.csv" = list(name = "veri.csv")
    ))

    settings_data <- shiny::reactiveValues(enable_mcp_tools = FALSE)

    fm_data <- list(
      set_attachment_checked = function(name, checked) {
        unchecked_names <<- c(unchecked_names, name)
        invisible(TRUE)
      },
      files_added_to_context = shiny::reactiveVal(NULL)
    )

    fileObserversInit(
      input = input, session = session, settings_data = settings_data,
      session_files = session_files, file_manager_data = fm_data,
      current_user_id = function() 7L
    )

    session$userData$.session_files <- session_files
    session$userData$.unchecked <- function() unchecked_names
  }, {
    session$flushReact()
    session_files <- session$userData$.session_files

    session$setInputs(remove_file_from_prompt = list(name = "rapor.pdf"))
    session$flushReact()

    remaining <- names(session_files())
    testthat::expect_identical(remaining, "veri.csv")
    testthat::expect_true("rapor.pdf" %in% session$userData$.unchecked())
    testthat::expect_gte(toast_rec$count, 1L)
  })
})
