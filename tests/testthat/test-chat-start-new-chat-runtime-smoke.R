# ==============================================================================
# Dosya Yolu: tests/testthat/test-chat-start-new-chat-runtime-smoke.R
# Açıklama: chat_start_new_chat() davranışsal runtime smoke testi. Yeni söyleşi
#           başlatıldığında sohbet durumunun tam sıfırlanmasını (mesajlar,
#           current_chat_id, karşılama bayrağı, oturum dosyaları, geçici dosya
#           temizliği), ekli dosya durumunun sıfırlanmasını ve oturum liste
#           depolarının temizlenmesini gerçek reaktif tur içinde doğrular.
#           Ağır UI bağımlılıkları (createWelcomeScreen) stub'lanır.
#           DB/LLM/tarayıcı gerekmez.
# ==============================================================================

.chat_start_new_chat_source_once <- function() {
  if (exists("chat_start_new_chat", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_chat_runtime.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

# createWelcomeScreen, showToast ve session_user_data_reset_lists global
# bağımlılıkları test süresince stub'lanır ve geri yüklenir.
.with_new_chat_stubs <- function(rec) {
  names <- c("createWelcomeScreen", "showToast", "session_user_data_reset_lists")
  had <- vapply(names, exists, logical(1), envir = globalenv(), inherits = FALSE)
  old <- lapply(names, function(nm) {
    if (exists(nm, envir = globalenv(), inherits = FALSE)) get(nm, envir = globalenv()) else NULL
  })
  names(old) <- names

  assign("createWelcomeScreen", function(...) shiny::div("welcome-stub"), envir = globalenv())
  assign("showToast", function(session, message, type = "info", ...) {
    rec$toast <- (rec$toast %||% 0L) + 1L
    invisible(TRUE)
  }, envir = globalenv())
  assign("session_user_data_reset_lists", function(session, keys) {
    rec$reset_keys <- keys
    invisible(TRUE)
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

testthat::test_that("chat_start_new_chat sohbet durumunu tam sıfırlar ve temizlik yapar", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  .chat_start_new_chat_source_once()

  rec <- new.env()
  rec$toast <- 0L
  rec$reset_keys <- NULL
  stubs <- .with_new_chat_stubs(rec)
  on.exit(stubs$restore(), add = TRUE)

  # Gerçek geçici dosyalar; new chat sonrası silinmiş olmalı.
  tmp1 <- tempfile(fileext = ".txt")
  tmp2 <- tempfile(fileext = ".txt")
  writeLines("a", tmp1)
  writeLines("b", tmp2)
  testthat::expect_true(file.exists(tmp1) && file.exists(tmp2))

  shiny::testServer(function(input, output, session) {
    attach_reset_count <- 0L

    values <- shiny::reactiveValues(
      messages = list(list(id = "m1"), list(id = "m2")),
      current_chat_id = "chat-123",
      show_welcome = FALSE,
      saved_chats = list(),
      temp_files = list(tmp1, tmp2)
    )

    session_files <- shiny::reactiveVal(list(
      "a.pdf" = list(name = "a.pdf"),
      "b.csv" = list(name = "b.csv")
    ))

    fm_data <- list(
      reset_attachment_state = function() {
        attach_reset_count <<- attach_reset_count + 1L
        invisible(TRUE)
      }
    )

    chat_start_new_chat(
      session = session,
      values = values,
      saved_chats_data = NULL,
      session_files = session_files,
      filePreview = NULL,
      current_user_id = 1L,
      file_manager_data = fm_data
    )

    session$userData$.values <- values
    session$userData$.session_files <- session_files
    session$userData$.attach_reset_count <- function() attach_reset_count
  }, {
    session$flushReact()

    values <- session$userData$.values
    session_files <- session$userData$.session_files

    # Sohbet durumu sıfırlanmalı.
    testthat::expect_identical(length(values$messages), 0L)
    testthat::expect_null(values$current_chat_id)
    testthat::expect_true(isTRUE(values$show_welcome))

    # Oturum dosyaları boşaltılmalı.
    testthat::expect_identical(length(session_files()), 0L)

    # Geçici dosyalar silinmeli ve liste temizlenmeli.
    testthat::expect_identical(length(values$temp_files), 0L)
    testthat::expect_false(file.exists(tmp1))
    testthat::expect_false(file.exists(tmp2))

    # Ekli dosya durumu sıfırlanmalı.
    testthat::expect_identical(session$userData$.attach_reset_count(), 1L)

    # Oturum liste depoları doğru anahtarlarla temizlenmeli.
    testthat::expect_true(all(
      c("current_session_files", "file_summaries", "mcp_registry_snapshot") %in% rec$reset_keys
    ))

    # Kullanıcıya bilgi toast'ı gösterilmeli.
    testthat::expect_gte(rec$toast, 1L)
  })

  # on.exit silmediyse temizle.
  unlink(c(tmp1, tmp2))
})
