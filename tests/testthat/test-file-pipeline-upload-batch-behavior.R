# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-pipeline-upload-batch-behavior.R
# Açıklama: helpers_file_pipeline.R içindeki handle_file_upload_batch ve
#           chat_upload_commit_results davranışını doğrular. Yükleme artık
#           BLOKLAMAYAN dosya alım hattına gönderilir: observer ucuz planı
#           yapar, doğrulama/kopyalama/bütünlük denetimi worker'da çalışır,
#           tablo/özetleme işleri ana süreç commit'inde tetiklenir.
#
#           Güvenlik/adversarial değer: desteklenmeyen uzantılı dosya ASLA
#           worker'a gönderilmez, kopyalanmaz, indekslenmez ve özetleme
#           kuyruğuna alınmaz ("gizli kaydedilmiş ama geçersiz yükleme" yok).
#
#           Performans sözleşmesi: gönderim çağrısı dönerken HENÜZ hiçbir
#           kopyalama/indeksleme/özetleme yapılmamış olmalıdır.
#
#           Tüm yan etkiler (showNotification/showToast/alım hattı/
#           processAndSummarizeFile) stub'lanır; gerçek dosya deposu, LLM, ağ
#           veya future yoktur. Çevrimdışı ve deterministiktir.
# ==============================================================================

# Türkçe yorum: pipeline'ı yalıtılmış ortama yükler ve alım hattını stub'lar.
.uploadBatchEnv <- function(allowed = c("txt", "pdf", "csv"),
                            submit_status = "started") {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "utils_common.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_file_ingestion_task.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_file_pipeline.R"), encoding = "UTF-8", local = env)

  rec <- new.env(parent = emptyenv())
  rec$notifications <- 0L
  rec$removed <- 0L
  rec$toasts <- list()
  rec$submitted <- list()
  rec$process_calls <- list()
  rec$added <- list()
  rec$copy_calls <- list()
  rec$register_calls <- list()

  env$cat <- function(...) invisible(NULL)
  env$fm_normal_allowed_extensions <- function() allowed

  env$showNotification <- function(...) {
    rec$notifications <- rec$notifications + 1L
    paste0("note-", rec$notifications)
  }
  env$removeNotification <- function(id) {
    rec$removed <- rec$removed + 1L
    invisible(NULL)
  }
  env$showToast <- function(session, message, type = "info", ...) {
    rec$toasts[[length(rec$toasts) + 1L]] <- list(message = message, type = type)
    invisible(NULL)
  }

  env$file_ingestion_session_controller <- function(session) new.env(parent = emptyenv())
  env$file_ingestion_submit_batch <- function(controller, tasks, user_id, on_complete = NULL,
                                              on_failure = NULL, batch_id = NULL) {
    rec$submitted[[length(rec$submitted) + 1L]] <- list(
      tasks = tasks, user_id = user_id, on_complete = on_complete,
      on_failure = on_failure, batch_id = batch_id
    )
    list(status = submit_status, batch_id = batch_id, queued = 0L)
  }

  env$processAndSummarizeFile <- function(file_info, current_user_id, session, ...) {
    args <- list(...)
    rec$process_calls[[length(rec$process_calls) + 1L]] <- list(
      name = file_info$name,
      datapath = file_info$datapath,
      user_id = current_user_id,
      already_persisted = isTRUE(args$already_persisted)
    )
    invisible(NULL)
  }

  env$copy_to_mcp_base <- function(upload, user_id) {
    rec$copy_calls[[length(rec$copy_calls) + 1L]] <- list(name = upload$name)
    upload$datapath
  }
  env$global_register_file <- function(dest, name, ...) {
    rec$register_calls[[length(rec$register_calls) + 1L]] <- list(name = name)
    invisible(TRUE)
  }

  list(env = env, rec = rec)
}

.makeUploadFile <- function(name) {
  p <- tempfile(fileext = paste0(".", tools::file_ext(name)))
  writeLines("kaynak yukleme icerigi", p)
  p
}

.uploadBatchArgs <- function(rec) {
  session <- list(userData = list(user_id = 7L), token = "tok-1")
  file_to_add_reactive <- function(uf) {
    rec$added[[length(rec$added) + 1L]] <- uf
    invisible(NULL)
  }
  list(
    session = session,
    settings_data = list(model_selection = "m1"),
    file_manager_data = list(),
    session_files_reactive = function(...) list(),
    file_to_add_reactive = file_to_add_reactive
  )
}

.runUploadBatch <- function(h, df) {
  a <- .uploadBatchArgs(h$rec)
  h$env$handle_file_upload_batch(
    uploads_df = df, current_user_id = 7L, session = a$session,
    settings_data = a$settings_data, file_manager_data = a$file_manager_data,
    session_files_reactive = a$session_files_reactive,
    file_to_add_reactive = a$file_to_add_reactive
  )
}

test_that("handle_file_upload_batch NULL girdi için sessizce çıkar", {
  h <- .uploadBatchEnv()
  expect_null(.runUploadBatch(h, NULL))
  expect_equal(h$rec$notifications, 0L)
  expect_equal(length(h$rec$submitted), 0L)
})

test_that("handle_file_upload_batch boş data.frame için sessizce çıkar", {
  h <- .uploadBatchEnv()
  empty_df <- data.frame(name = character(0), datapath = character(0),
                         size = numeric(0), type = character(0),
                         stringsAsFactors = FALSE)
  expect_null(.runUploadBatch(h, empty_df))
  expect_equal(length(h$rec$submitted), 0L)
})

test_that("handle_file_upload_batch okunamayan girdide hata toast'ı verir", {
  h <- .uploadBatchEnv()
  expect_null(.runUploadBatch(h, list(foo = 1)))
  expect_equal(length(h$rec$toasts), 1L)
  expect_identical(h$rec$toasts[[1]]$type, "error")
  expect_true(grepl("okunamad", h$rec$toasts[[1]]$message))
  expect_equal(length(h$rec$submitted), 0L)
})

test_that("handle_file_upload_batch desteklenmeyen uzantıyı reddeder ve HİÇBİR kalıcı yan etki üretmez", {
  h <- .uploadBatchEnv(allowed = c("txt", "pdf", "csv"))
  df <- data.frame(
    name = "zararli.exe",
    datapath = .makeUploadFile("zararli.exe"),
    size = 100, type = "application/octet-stream",
    stringsAsFactors = FALSE
  )
  .runUploadBatch(h, df)

  warn_msgs <- vapply(h$rec$toasts, function(t) t$message, character(1))
  expect_true(any(grepl("desteklenmiyor", warn_msgs)))
  expect_true(any(grepl("zararli.exe", warn_msgs, fixed = TRUE)))

  # KRİTİK güvenlik kontratı: worker'a gitmez, kopyalanmaz, indekslenmez.
  expect_equal(length(h$rec$submitted), 0L)
  expect_equal(length(h$rec$copy_calls), 0L)
  expect_equal(length(h$rec$register_calls), 0L)
  expect_equal(length(h$rec$process_calls), 0L)
  expect_equal(length(h$rec$added), 0L)
})

test_that("handle_file_upload_batch geçerli dosyayı alım hattına gönderir ve HEMEN döner", {
  h <- .uploadBatchEnv(allowed = c("txt", "pdf", "csv"))
  df <- data.frame(
    name = "rapor.txt",
    datapath = .makeUploadFile("rapor.txt"),
    size = 200, type = "text/plain",
    stringsAsFactors = FALSE
  )
  outcome <- .runUploadBatch(h, df)

  expect_identical(outcome$status, "started")
  expect_equal(length(h$rec$submitted), 1L)

  gorevler <- h$rec$submitted[[1]]$tasks
  expect_equal(length(gorevler), 1L)
  expect_identical(gorevler[[1]]$name, "rapor.txt")
  expect_identical(gorevler[[1]]$user_id, "7")

  # PERFORMANS SÖZLEŞMESİ: dönüş anında hiçbir pahalı iş yapılmamış olmalı.
  expect_equal(length(h$rec$copy_calls), 0L)
  expect_equal(length(h$rec$register_calls), 0L)
  expect_equal(length(h$rec$process_calls), 0L)
  expect_equal(length(h$rec$added), 0L)

  expect_gt(h$rec$notifications, 0L)
})

test_that("handle_file_upload_batch büyük harfli uzantıyı kabul eder", {
  h <- .uploadBatchEnv(allowed = c("txt", "pdf", "csv"))
  df <- data.frame(
    name = "RAPOR.TXT",
    datapath = .makeUploadFile("RAPOR.TXT"),
    size = 50, type = "text/plain",
    stringsAsFactors = FALSE
  )
  .runUploadBatch(h, df)
  expect_equal(length(h$rec$submitted[[1]]$tasks), 1L)
})

test_that("handle_file_upload_batch karışık toplu yüklemede yalnızca geçerli dosyayı gönderir", {
  h <- .uploadBatchEnv(allowed = c("txt", "pdf", "csv"))
  df <- data.frame(
    name = c("iyi.csv", "kotu.bin"),
    datapath = c(.makeUploadFile("iyi.csv"), .makeUploadFile("kotu.bin")),
    size = c(100, 200),
    type = c("text/csv", "application/octet-stream"),
    stringsAsFactors = FALSE
  )
  .runUploadBatch(h, df)

  gorevler <- h$rec$submitted[[1]]$tasks
  expect_equal(length(gorevler), 1L)
  expect_identical(gorevler[[1]]$name, "iyi.csv")

  warn_msgs <- vapply(h$rec$toasts, function(t) t$message, character(1))
  expect_true(any(grepl("desteklenmiyor", warn_msgs)))
})

test_that("handle_file_upload_batch kuyruk doluysa kullanıcıyı uyarır", {
  h <- .uploadBatchEnv(allowed = c("txt"), submit_status = "rejected")
  df <- data.frame(
    name = "rapor.txt", datapath = .makeUploadFile("rapor.txt"),
    size = 10, type = "text/plain", stringsAsFactors = FALSE
  )
  .runUploadBatch(h, df)

  warn_msgs <- vapply(h$rec$toasts, function(t) t$message, character(1))
  expect_true(any(grepl("kuyru", warn_msgs)))
  expect_gt(h$rec$removed, 0L)
})

test_that("commit başarılı dosyayı bağlama ekler ve TEKRAR kalıcılaştırmadan özetlemeye verir", {
  h <- .uploadBatchEnv(allowed = c("txt"))
  df <- data.frame(
    name = "rapor.txt", datapath = .makeUploadFile("rapor.txt"),
    size = 10, type = "text/plain", stringsAsFactors = FALSE
  )
  .runUploadBatch(h, df)

  a <- .uploadBatchArgs(h$rec)
  commit_ctx <- list(
    session = a$session,
    user_id = 7L,
    settings_data = a$settings_data,
    file_manager_data = a$file_manager_data,
    session_files_reactive = a$session_files_reactive,
    file_to_add_reactive = a$file_to_add_reactive
  )

  sonuclar <- list(list(
    ok = TRUE, name = "rapor.txt", dest = "/kalici/user_7/rapor.txt",
    size = 10, type = "text/plain"
  ))

  h$env$chat_upload_commit_results(sonuclar, commit_ctx, batch_id = "b1")

  expect_equal(length(h$rec$added), 1L)
  expect_identical(h$rec$added[[1]]$datapath, "/kalici/user_7/rapor.txt")
  expect_equal(length(h$rec$process_calls), 1L)
  # Kayıt tam olarak bir kez: commit yolu yeniden kalıcılaştırma istemez.
  expect_true(h$rec$process_calls[[1]]$already_persisted)
})

test_that("commit başarısız sonucu için kullanıcıyı uyarır ve özetleme yapmaz", {
  h <- .uploadBatchEnv(allowed = c("txt"))
  a <- .uploadBatchArgs(h$rec)
  commit_ctx <- list(
    session = a$session, user_id = 7L, settings_data = a$settings_data,
    file_manager_data = a$file_manager_data,
    session_files_reactive = a$session_files_reactive,
    file_to_add_reactive = a$file_to_add_reactive
  )

  sonuclar <- list(list(ok = FALSE, name = "bozuk.txt", code = "copy_failed", error = "disk dolu"))
  h$env$chat_upload_commit_results(sonuclar, commit_ctx, batch_id = "b2")

  expect_equal(length(h$rec$process_calls), 0L)
  expect_equal(length(h$rec$added), 0L)
  warn_msgs <- vapply(h$rec$toasts, function(t) t$message, character(1))
  expect_true(any(grepl("bozuk.txt", warn_msgs, fixed = TRUE)))
})

test_that("processAndSummarizeFile zaten kalıcı dosyayı yeniden kopyalamaz/indekslemez", {
  h <- .uploadBatchEnv(allowed = c("txt"))
  env <- h$env

  env$is_under_mcp_base <- function(p) FALSE
  env$session_user_data_put_list_item <- function(...) invisible(NULL)
  env$reactiveValuesToList <- function(x) list()
  env$`%...>%` <- function(lhs, rhs) invisible(NULL)
  env$`%...!%` <- function(lhs, rhs) invisible(NULL)
  env$tracked_future_promise <- function(...) invisible(NULL)

  session <- list(userData = list(user_id = 7L), token = "tok-1")

  env$processAndSummarizeFile <- NULL
  rm("processAndSummarizeFile", envir = env)
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_file_pipeline.R"),
    encoding = "UTF-8", local = env
  )

  env$processAndSummarizeFile(
    list(name = "rapor.txt", datapath = "/kalici/user_7/rapor.txt", size = 10),
    current_user_id = 7L, session = session, settings = list(),
    file_manager_data = list(), session_files_reactive = function(...) list(),
    already_persisted = TRUE
  )

  expect_equal(length(h$rec$copy_calls), 0L)
  expect_equal(length(h$rec$register_calls), 0L)
})
