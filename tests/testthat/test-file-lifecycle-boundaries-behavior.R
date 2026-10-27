.file_lifecycle_boundary_env <- function(files, parent = globalenv()) {
  env <- new.env(parent = parent)
  if ("helpers_files_promote_target.R" %in% files)
    files <- c("helpers_files_promote_probe.R", files)
  for (path in files) source(file.path(resolve_repo_root_for_tests(), "R", path),
                            local = env, encoding = "UTF-8")
  env
}

test_that("özel kopya kaynak kipini umask ile ikinci kez daraltmaz", {
  env <- .file_lifecycle_boundary_env("helpers_files_promote_target.R")
  root <- withr::local_tempdir()
  src <- file.path(root, "source")
  dest <- file.path(root, "target")
  writeLines("paylaşılan", src)
  Sys.chmod(src, "0640", use_umask = FALSE)
  captured <- NULL
  env$Sys.chmod <- function(paths, mode, use_umask) {
    captured <<- list(mode = mode, use_umask = use_umask)
    base::Sys.chmod(paths, mode, use_umask)
  }
  mask <- Sys.umask("0077")
  withr::defer(Sys.umask(mask))
  expect_true(env$.mergen_promote_copy_exclusive(src, dest))
  expect_false(captured$use_umask)
  expect_identical(captured$mode, file.info(src)$mode[1])
  if (.Platform$OS.type != "windows") expect_identical(file.info(dest)$mode, file.info(src)$mode)
  expect_identical(readBin(dest, "raw", n = 100), readBin(src, "raw", n = 100))
})

test_that("kip desteklemeyen kopya baytları korur; gerçek yazım hatası başarısızdır", {
  for (failure in c(FALSE, TRUE)) {
    env <- .file_lifecycle_boundary_env("helpers_files_promote_target.R")
    root <- withr::local_tempdir()
    src <- file.path(root, "source")
    dest <- file.path(root, "target")
    writeLines("içerik", src)
    env$Sys.chmod <- function(...) FALSE
    if (failure) env$writeBin <- function(...) stop("yazım başarısız")
    expect_identical(env$.mergen_promote_copy_exclusive(src, dest), !failure)
    expect_identical(file.exists(dest), !failure)
    if (!failure) expect_identical(readLines(dest), readLines(src))
    expect_true(file.exists(src))
  }
})

test_that("izin uygulaması istisnası başarıya çevrilmez", {
  env <- .file_lifecycle_boundary_env("helpers_files_promote_target.R")
  root <- withr::local_tempdir()
  src <- file.path(root, "source")
  dest <- file.path(root, "target")
  writeLines("içerik", src)
  env$Sys.chmod <- function(...) stop("izin hatası")
  expect_false(env$.mergen_promote_copy_exclusive(src, dest))
  expect_false(file.exists(dest))
  expect_true(file.exists(src))
})

test_that("başarısız özel kopya yalnız kendi fiziksel dosyasını kaldırır", {
  for (phase in c("write", "close")) for (replacement in c(FALSE, TRUE)) {
    env <- .file_lifecycle_boundary_env("helpers_files_promote_target.R")
    root <- withr::local_tempdir()
    src <- file.path(root, "source")
    dest <- file.path(root, "target")
    writeLines("kaynak", src)
    replaced <- FALSE
    replace <- function() {
      if (replacement) {
        # Windows'ta açık hedefi değiştirmek yerine kapanış sonrasını uygula.
        # Yeni yazılan dosyayı tarayan süreç adı geçici kilitleyebilir; uyarı
        # sınanan kodun tryCatch'ini erken bitirmesin diye yeniden denenir.
        for (i in seq_len(50L)) {
          replaced <<- isTRUE(suppressWarnings(file.rename(dest, file.path(root, "old"))))
          if (replaced) break
          Sys.sleep(0.1)
        }
        if (replaced) writeLines("başkasının dosyası", dest)
      }
    }
    output <- NULL
    env$file <- function(description, open, ...) {
      con <- base::file(description, open, ...)
      if (identical(description, dest)) output <<- con
      con
    }
    if (phase == "write") env$writeBin <- function(object, con, ...) {
      base::writeBin(object, con, ...)
      if (replacement) base::close(con)
      replace()
      stop("yazım başarısız")
    }
    if (phase == "close") env$close <- function(con, ...) {
      if (!identical(con, output)) return(base::close(con, ...))
      base::close(con, ...)
      replace()
      stop("kapanış başarısız")
    }
    expect_false(env$.mergen_promote_copy_exclusive(src, dest))
    expect_identical(replaced, replacement)
    expect_identical(file.exists(dest), replacement)
    if (replacement) expect_identical(readLines(dest), "başkasının dosyası")
    expect_true(file.exists(src))
  }
})

test_that("fiziksel kimliksiz paylaşımda özel kopya kalıcı ad oluşturmadan reddedilir", {
  env <- .file_lifecycle_boundary_env("helpers_files_promote_target.R")
  root <- withr::local_tempdir()
  src <- file.path(root, "source")
  dest <- file.path(root, "target")
  writeLines("kaynak", src)
  for (inode in c(0, NA_real_)) {
    testthat::local_mocked_bindings(file_info = function(...)
      data.frame(device_id = 1, inode = inode), .package = "fs")
    expect_false(env$.mergen_promote_copy_exclusive(src, dest))
    expect_false(file.exists(dest))
    expect_identical(readLines(src), "kaynak")
  }
})

test_that("eksik sahip doğrulayıcısı rezervasyon devralmayı kapalı reddeder", {
  env <- .file_lifecycle_boundary_env("utils_path_reservation.R", parent = baseenv())
  reservation <- file.path(withr::local_tempdir(), "reservation")
  expect_true(env$mergen_reservation_acquire(reservation, "123-old"))
  env$mergen_reclaim_mutex <- function(...) stop("mutekse ulaşılmamalı")
  expect_false(env$mergen_reservation_takeover(reservation, "456-new", stale_sec = -1))
  expect_identical(env$mergen_reservation_owner(reservation), "123-old")
})

test_that("karantinadaki eski parti ilerlemeyi kaldırır ve kaynağı bırakmaz", {
  env <- .file_lifecycle_boundary_env("helpers_file_ingestion_runtime.R")
  controller <- env$file_ingestion_create_controller()
  calls <- list()
  controller$clear_notification <- function(id, uncertain = FALSE)
    calls[[length(calls) + 1L]] <<- list(id = id, uncertain = uncertain)
  job <- list(id = "batch", controller = controller, epoch = 0L, lease = new.env())
  controller$epoch <- 1L
  released <- 0L
  env$file_ingestion_release_job <- function(...) released <<- released + 1L
  env$file_ingestion_fail_job(job, simpleError("karantina"), uncertain = TRUE)
  env$file_ingestion_fail_job(job, simpleError("karantina"), uncertain = TRUE)
  expect_identical(calls, list(list(id = "batch", uncertain = FALSE)))
  expect_identical(released, 0L)
  expect_true(job$lease$uncertain_notified)
})

test_that("dosya yöneticisi terminal bildirimleri yakalanan oturumu kullanır", {
  env <- .file_lifecycle_boundary_env("helpers_file_manager_upload_runtime.R")
  session <- list(token = "captured-session")
  removed <- list()
  env$removeNotification <- function(id, session = NULL)
    removed[[length(removed) + 1L]] <<- list(id = id, session = session)
  env$showToast <- env$showNotification <- function(...) NULL
  ctx <- list(session = session)
  env$fm_commit_bulk_upload_results(list(), ctx, "completed")
  env$file_ingestion_new_batch_id <- function(...) "failed"
  env$file_ingestion_plan_batch <- function(...) list(tasks = list(list()))
  env$fm_normal_allowed_extensions <- function() "txt"
  env$fm_upload_limit_mb <- function() 10
  env$file_ingestion_valid_user_id <- function(...) TRUE
  env$SSO_ENABLED <- FALSE
  env$file_ingestion_submit_batch <- function(..., on_failure) {
    on_failure("hata", list())
    list(status = "started")
  }
  env$fm_dispatch_bulk_upload_batch(NULL, NULL, session, "7", function() TRUE,
    NULL, ctx, function(...) NULL)
  expect_identical(removed, list(list(id = "completed", session = session),
                                list(id = "failed", session = session)))
})
