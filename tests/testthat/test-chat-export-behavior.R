# ==============================================================================
# Dosya Yolu: tests/testthat/test-chat-export-behavior.R
# Açıklama: R/module_chat_export.R chatExportInit() "Sohbeti Kopyala" akışının
#           DAVRANIŞSAL testleri. Bu dosya daha önce hiçbir test tarafından
#           çağrılmıyordu.
#
#           chatExportInit moduleServer DEĞİLDİR; session doğrudan iletilir.
#           copy_chat_btn gözlemcisi mesajları "[zaman] yazar:\nicerik" biçiminde
#           birleştirir (kullanıcı için görünen ad, AI için 'MERGEN Bilge') ve
#           panoya yazmak için shinyjs::runjs çağırır. runjs custom message'ı kök
#           MockShinySession üzerinden yakalanıp içeriği doğrulanır. İndirme
#           işleyicisi testServer'da çağrılamadığından kapsam dışıdır.
#           Gerçek pano/indirme/DB GEREKMEZ.
# ==============================================================================

.source_chat_export_for_test <- function() {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  suppressMessages({ library(shiny); library(shinyjs) })
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_chat_export.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# copy_chat_btn'i prime-then-set ile tetikler, yakalanan tüm mesajları düz metne çevirir.
.capture_copy <- function(env, messages, user_display_name, userData = NULL) {
  rec <- new.env(); rec$msgs <- list()
  shiny::testServer(function(input, output, session) {
    if (!is.null(userData)) {
      for (nm in names(userData)) session$userData[[nm]] <- userData[[nm]]
    }
    values <- shiny::reactiveValues(messages = messages)
    env$chatExportInit(input, output, session, values, user_display_name)
  }, {
    session$sendCustomMessage <- function(type, message) {
      rec$msgs[[length(rec$msgs) + 1L]] <- list(type = type, message = message)
      invisible(TRUE)
    }
    session$setInputs(copy_chat_btn = 1)
    session$setInputs(copy_chat_btn = 2)
  })
  rec
}

.copy_blob <- function(rec) {
  paste(vapply(rec$msgs, function(m) {
    tryCatch(jsonlite::toJSON(m, auto_unbox = TRUE, null = "null"),
             error = function(e) paste(unlist(m), collapse = " "))
  }, character(1)), collapse = " ")
}

.sample_msgs <- function() {
  list(
    list(type = "user", timestamp = "10:00", content = "Merhaba dunya"),
    list(type = "ai",   timestamp = "10:01", content = "Selam, nasil yardimci olabilirim")
  )
}

# ------------------------------------------------------------------------------
# Kopyalama: yazar etiketleri ve içerik
# ------------------------------------------------------------------------------
testthat::test_that("copy_chat_btn kullanıcı görünen adını ve MERGEN Bilge etiketini kullanır", {
  env <- .source_chat_export_for_test()
  rec <- .capture_copy(env, .sample_msgs(), user_display_name = "Ahmet")
  blob <- .copy_blob(rec)
  testthat::expect_true(grepl("Ahmet", blob, fixed = TRUE))
  testthat::expect_true(grepl("MERGEN Bilge", blob, fixed = TRUE))
  testthat::expect_true(grepl("Merhaba dunya", blob, fixed = TRUE))
  testthat::expect_true(grepl("Selam, nasil yardimci", blob, fixed = TRUE))
  # Panoya yazma çağrısı yer almalı.
  testthat::expect_true(grepl("clipboard", blob, fixed = TRUE))
})

testthat::test_that("copy_chat_btn user_display_name fonksiyon olarak verilince çözülür", {
  env <- .source_chat_export_for_test()
  rec <- .capture_copy(env, .sample_msgs(), user_display_name = function() "Zeynep")
  blob <- .copy_blob(rec)
  testthat::expect_true(grepl("Zeynep", blob, fixed = TRUE))
})

testthat::test_that("copy_chat_btn görünen ad yoksa oturum verisi/varsayılana düşer", {
  env <- .source_chat_export_for_test()
  # user_display_name NULL -> session$userData$user_config$name'e düşmeli.
  rec <- .capture_copy(env, .sample_msgs(), user_display_name = NULL,
                       userData = list(user_config = list(name = "Veli")))
  blob <- .copy_blob(rec)
  testthat::expect_true(grepl("Veli", blob, fixed = TRUE))
})

testthat::test_that("copy_chat_btn hiçbir ad kaynağı yoksa 'Kullanıcı' varsayılanını kullanır", {
  env <- .source_chat_export_for_test()
  rec <- .capture_copy(env, .sample_msgs(), user_display_name = "")
  blob <- .copy_blob(rec)
  testthat::expect_true(grepl("Kullanıcı", blob, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# Boş sohbet guard'ı
# ------------------------------------------------------------------------------
testthat::test_that("copy_chat_btn mesaj yoksa panoya yazma çağrısı üretmez", {
  env <- .source_chat_export_for_test()
  rec <- .capture_copy(env, list(), user_display_name = "Ahmet")
  blob <- .copy_blob(rec)
  # req(length(values$messages) > 0) başarısız -> clipboard çağrısı olmamalı.
  testthat::expect_false(grepl("clipboard.writeText", blob, fixed = TRUE))
})
