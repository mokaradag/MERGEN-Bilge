# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-pipeline-upload-batch-behavior.R
# Açıklama: helpers_file_pipeline.R içindeki handle_file_upload_batch davranışını
#           doğrular. Bu fonksiyon fileInput/sürükle-bırak toplu yüklemesini
#           işler: girdiyi normalleştirir, uzantıyı TEK kaynaktan
#           (fm_normal_allowed_extensions) doğrular, geçerli dosyaları kalıcı
#           dizine kopyalar + indekse kaydeder + özetleme kuyruğuna alır.
#
#           Güvenlik/adversarial değer (Faz 5): desteklenmeyen uzantılı dosya
#           ASLA kopyalanmamalı, indekslenmemeli ve özetleme/UI'ya
#           eklenmemelidir ("gizli kaydedilmiş ama geçersiz yükleme" yok).
#           Ayrıca kopyalama başarısız olsa bile dosya oturumda kullanılabilir
#           kalır ve kullanıcı uyarılır; bildirim yaşam döngüsü temizlenir.
#
#           Tüm yan etkiler (showNotification/showToast/copy_to_mcp_base/
#           global_register_file/processAndSummarizeFile/shinyjs::delay) stub'lanır;
#           gerçek dosya deposu/LLM/ağ/future yoktur. Çevrimdışı ve deterministik.
# ==============================================================================

# Türkçe yorum: helpers_file_pipeline.R'yi yalıtılmış ortama yükler ve tüm
# yan-etkili bağımlılıkları kayıt yapan stub'larla değiştirir. Dönen liste hem
# ortamı (env) hem de kayıt nesnesini (rec) içerir.
.uploadBatchEnv <- function(allowed = c("txt", "pdf", "csv"),
                            copy_throws = FALSE) {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "helpers_file_pipeline.R"), encoding = "UTF-8", local = env)

  rec <- new.env(parent = emptyenv())
  rec$notifications <- 0L
  rec$removed <- 0L
  rec$toasts <- list()
  rec$copy_calls <- list()
  rec$register_calls <- list()
  rec$process_calls <- list()
  rec$added <- list()

  # Türkçe yorum: gürültülü cat çıktısını sustur (davranışı etkilemez)
  env$cat <- function(...) invisible(NULL)

  # Türkçe yorum: izin verilen uzantı kümesi deterministik kılınır
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

  # Türkçe yorum: kopyalama hedefi gerçek bir geçici dosyadır; böylece
  # file.info(dest)$size > 0 olur ve copy_ok TRUE dalı çalışır.
  env$copy_to_mcp_base <- function(upload, user_id) {
    rec$copy_calls[[length(rec$copy_calls) + 1L]] <- list(name = upload$name, user_id = user_id)
    if (isTRUE(copy_throws)) stop("disk dolu (test)")
    dest <- tempfile(fileext = paste0(".", tools::file_ext(upload$name)))
    writeLines("kopyalanan icerik", dest)
    dest
  }
  env$global_register_file <- function(dest, name, user_id = NULL, persist_under_mcp_base = TRUE, ...) {
    rec$register_calls[[length(rec$register_calls) + 1L]] <- list(name = name, user_id = user_id)
    invisible(TRUE)
  }
  env$path_exists_relaxed <- function(path) TRUE

  # Türkçe yorum: processAndSummarizeFile stub'lanır -> gerçek future/LLM yok.
  # Hangi dosyaların özetleme kuyruğuna alındığını kaydeder.
  env$processAndSummarizeFile <- function(file_info, current_user_id, session, ...) {
    rec$process_calls[[length(rec$process_calls) + 1L]] <- list(
      name = file_info$name,
      datapath = file_info$datapath,
      user_id = current_user_id
    )
    invisible(NULL)
  }

  list(env = env, rec = rec)
}

# Türkçe yorum: gerçek bir kaynak yükleme dosyası üretir (file.info boyutu için)
.makeUploadFile <- function(name) {
  p <- tempfile(fileext = paste0(".", tools::file_ext(name)))
  writeLines("kaynak yukleme icerigi", p)
  p
}

# Türkçe yorum: test için sahte oturum + reaktif kaydediciler
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

test_that("handle_file_upload_batch NULL girdi için sessizce çıkar", {
  h <- .uploadBatchEnv()
  a <- .uploadBatchArgs(h$rec)
  res <- h$env$handle_file_upload_batch(
    uploads_df = NULL, current_user_id = 7L, session = a$session,
    settings_data = a$settings_data, file_manager_data = a$file_manager_data,
    session_files_reactive = a$session_files_reactive,
    file_to_add_reactive = a$file_to_add_reactive
  )
  expect_null(res)
  expect_equal(h$rec$notifications, 0L)
  expect_equal(length(h$rec$copy_calls), 0L)
  expect_equal(length(h$rec$process_calls), 0L)
})

test_that("handle_file_upload_batch boş data.frame için sessizce çıkar", {
  h <- .uploadBatchEnv()
  a <- .uploadBatchArgs(h$rec)
  empty_df <- data.frame(name = character(0), datapath = character(0),
                         size = numeric(0), type = character(0),
                         stringsAsFactors = FALSE)
  res <- h$env$handle_file_upload_batch(
    uploads_df = empty_df, current_user_id = 7L, session = a$session,
    settings_data = a$settings_data, file_manager_data = a$file_manager_data,
    session_files_reactive = a$session_files_reactive,
    file_to_add_reactive = a$file_to_add_reactive
  )
  expect_null(res)
  expect_equal(length(h$rec$copy_calls), 0L)
})

test_that("handle_file_upload_batch okunamayan girdide hata toast'ı verir", {
  h <- .uploadBatchEnv()
  a <- .uploadBatchArgs(h$rec)
  # Türkçe yorum: data.frame değil ve $name içermeyen liste -> okunamadı dalı
  res <- h$env$handle_file_upload_batch(
    uploads_df = list(foo = 1), current_user_id = 7L, session = a$session,
    settings_data = a$settings_data, file_manager_data = a$file_manager_data,
    session_files_reactive = a$session_files_reactive,
    file_to_add_reactive = a$file_to_add_reactive
  )
  expect_null(res)
  expect_equal(length(h$rec$toasts), 1L)
  expect_identical(h$rec$toasts[[1]]$type, "error")
  expect_true(grepl("okunamad", h$rec$toasts[[1]]$message))
  expect_equal(length(h$rec$copy_calls), 0L)
})

test_that("handle_file_upload_batch desteklenmeyen uzantıyı reddeder ve HİÇBİR kalıcı yan etki üretmez (Faz 5)", {
  h <- .uploadBatchEnv(allowed = c("txt", "pdf", "csv"))
  a <- .uploadBatchArgs(h$rec)
  df <- data.frame(
    name = "zararli.exe",
    datapath = .makeUploadFile("zararli.exe"),
    size = 100, type = "application/octet-stream",
    stringsAsFactors = FALSE
  )
  testthat::local_mocked_bindings(
    delay = function(ms, expr) { force(expr); invisible(NULL) },
    .package = "shinyjs"
  )
  h$env$handle_file_upload_batch(
    uploads_df = df, current_user_id = 7L, session = a$session,
    settings_data = a$settings_data, file_manager_data = a$file_manager_data,
    session_files_reactive = a$session_files_reactive,
    file_to_add_reactive = a$file_to_add_reactive
  )

  # Türkçe yorum: kullanıcı "desteklenmiyor" uyarısı almalı
  warn_msgs <- vapply(h$rec$toasts, function(t) t$message, character(1))
  expect_true(any(grepl("desteklenmiyor", warn_msgs)))
  expect_true(any(grepl("exe", warn_msgs)))

  # Türkçe yorum: KRİTİK güvenlik kontratı — geçersiz dosya kopyalanmaz,
  # indekslenmez, UI'ya eklenmez, özetleme kuyruğuna alınmaz.
  expect_equal(length(h$rec$copy_calls), 0L)
  expect_equal(length(h$rec$register_calls), 0L)
  expect_equal(length(h$rec$added), 0L)
  expect_equal(length(h$rec$process_calls), 0L)
})

test_that("handle_file_upload_batch geçerli dosyayı kopyalar + indeksler + özetleme kuyruğuna alır", {
  h <- .uploadBatchEnv(allowed = c("txt", "pdf", "csv"))
  a <- .uploadBatchArgs(h$rec)
  df <- data.frame(
    name = "rapor.txt",
    datapath = .makeUploadFile("rapor.txt"),
    size = 200, type = "text/plain",
    stringsAsFactors = FALSE
  )
  testthat::local_mocked_bindings(
    delay = function(ms, expr) { force(expr); invisible(NULL) },
    .package = "shinyjs"
  )
  h$env$handle_file_upload_batch(
    uploads_df = df, current_user_id = 7L, session = a$session,
    settings_data = a$settings_data, file_manager_data = a$file_manager_data,
    session_files_reactive = a$session_files_reactive,
    file_to_add_reactive = a$file_to_add_reactive
  )

  expect_equal(length(h$rec$copy_calls), 1L)
  expect_identical(h$rec$copy_calls[[1]]$name, "rapor.txt")
  # Türkçe yorum: çözümlenen kullanıcı kimliği (oturumdaki 7L) kopyalamaya geçer
  expect_identical(h$rec$copy_calls[[1]]$user_id, 7L)

  expect_equal(length(h$rec$register_calls), 1L)
  expect_identical(h$rec$register_calls[[1]]$user_id, 7L)

  expect_equal(length(h$rec$added), 1L)
  # Türkçe yorum: UI'ya eklenen kayıtta datapath kalıcı hedefe güncellenmiş olmalı
  expect_true(grepl("\\.txt$", h$rec$added[[1]]$datapath))

  expect_equal(length(h$rec$process_calls), 1L)
  expect_identical(h$rec$process_calls[[1]]$name, "rapor.txt")

  # Türkçe yorum: "desteklenmiyor" uyarısı olmamalı
  warn_msgs <- vapply(h$rec$toasts, function(t) t$message, character(1))
  expect_false(any(grepl("desteklenmiyor", warn_msgs)))
  # Türkçe yorum: başlangıç bildirimi açılır ve sonunda temizlenir
  expect_gt(h$rec$notifications, 0L)
  expect_gt(h$rec$removed, 0L)
})

test_that("handle_file_upload_batch büyük harfli uzantıyı kabul eder (tools::file_ext + tolower)", {
  h <- .uploadBatchEnv(allowed = c("txt", "pdf", "csv"))
  a <- .uploadBatchArgs(h$rec)
  df <- data.frame(
    name = "RAPOR.TXT",
    datapath = .makeUploadFile("RAPOR.TXT"),
    size = 50, type = "text/plain",
    stringsAsFactors = FALSE
  )
  testthat::local_mocked_bindings(
    delay = function(ms, expr) { force(expr); invisible(NULL) },
    .package = "shinyjs"
  )
  h$env$handle_file_upload_batch(
    uploads_df = df, current_user_id = 7L, session = a$session,
    settings_data = a$settings_data, file_manager_data = a$file_manager_data,
    session_files_reactive = a$session_files_reactive,
    file_to_add_reactive = a$file_to_add_reactive
  )
  expect_equal(length(h$rec$process_calls), 1L)
})

test_that("handle_file_upload_batch karışık toplu yüklemede yalnızca geçerli dosyayı işler", {
  h <- .uploadBatchEnv(allowed = c("txt", "pdf", "csv"))
  a <- .uploadBatchArgs(h$rec)
  df <- data.frame(
    name = c("iyi.csv", "kotu.bin"),
    datapath = c(.makeUploadFile("iyi.csv"), .makeUploadFile("kotu.bin")),
    size = c(100, 200),
    type = c("text/csv", "application/octet-stream"),
    stringsAsFactors = FALSE
  )
  testthat::local_mocked_bindings(
    delay = function(ms, expr) { force(expr); invisible(NULL) },
    .package = "shinyjs"
  )
  h$env$handle_file_upload_batch(
    uploads_df = df, current_user_id = 7L, session = a$session,
    settings_data = a$settings_data, file_manager_data = a$file_manager_data,
    session_files_reactive = a$session_files_reactive,
    file_to_add_reactive = a$file_to_add_reactive
  )

  # Türkçe yorum: yalnızca .csv kopyalanır/işlenir; .bin atlanır
  expect_equal(length(h$rec$copy_calls), 1L)
  expect_identical(h$rec$copy_calls[[1]]$name, "iyi.csv")
  expect_equal(length(h$rec$process_calls), 1L)
  expect_identical(h$rec$process_calls[[1]]$name, "iyi.csv")
  warn_msgs <- vapply(h$rec$toasts, function(t) t$message, character(1))
  expect_true(any(grepl("desteklenmiyor", warn_msgs)))
})

test_that("handle_file_upload_batch kopyalama başarısızsa dosyayı oturumda tutar ve kullanıcıyı uyarır", {
  h <- .uploadBatchEnv(allowed = c("txt", "pdf", "csv"), copy_throws = TRUE)
  a <- .uploadBatchArgs(h$rec)
  df <- data.frame(
    name = "rapor.pdf",
    datapath = .makeUploadFile("rapor.pdf"),
    size = 300, type = "application/pdf",
    stringsAsFactors = FALSE
  )
  testthat::local_mocked_bindings(
    delay = function(ms, expr) { force(expr); invisible(NULL) },
    .package = "shinyjs"
  )
  h$env$handle_file_upload_batch(
    uploads_df = df, current_user_id = 7L, session = a$session,
    settings_data = a$settings_data, file_manager_data = a$file_manager_data,
    session_files_reactive = a$session_files_reactive,
    file_to_add_reactive = a$file_to_add_reactive
  )

  # Türkçe yorum: kopyalama denendi ama hata fırlattı -> indekse kayıt YOK
  expect_equal(length(h$rec$copy_calls), 1L)
  expect_equal(length(h$rec$register_calls), 0L)
  # Türkçe yorum: "kalıcı klasöre kaydedilemedi" uyarısı verilmeli
  warn_msgs <- vapply(h$rec$toasts, function(t) t$message, character(1))
  expect_true(any(grepl("kalıcı klasöre kaydedilemedi", warn_msgs)))
  # Türkçe yorum: yine de oturumda kullanılabilir -> UI'ya eklenir + özetlenir
  expect_equal(length(h$rec$added), 1L)
  expect_equal(length(h$rec$process_calls), 1L)
})

test_that("handle_file_upload_batch liste biçimli tek yüklemeyi işler", {
  h <- .uploadBatchEnv(allowed = c("txt", "pdf", "csv"))
  a <- .uploadBatchArgs(h$rec)
  upload <- list(
    name = "tekil.txt",
    datapath = .makeUploadFile("tekil.txt"),
    size = 120,
    type = "text/plain"
  )
  testthat::local_mocked_bindings(
    delay = function(ms, expr) { force(expr); invisible(NULL) },
    .package = "shinyjs"
  )
  h$env$handle_file_upload_batch(
    uploads_df = upload, current_user_id = 7L, session = a$session,
    settings_data = a$settings_data, file_manager_data = a$file_manager_data,
    session_files_reactive = a$session_files_reactive,
    file_to_add_reactive = a$file_to_add_reactive
  )
  expect_equal(length(h$rec$process_calls), 1L)
  expect_identical(h$rec$process_calls[[1]]$name, "tekil.txt")
})
