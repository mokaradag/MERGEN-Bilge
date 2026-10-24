# ==============================================================================
# Dosya Yolu: tests/testthat/test-image-generation-persistence-regressions.R
# Açıklama: Base64 görsel kaydının biçim, eşzamanlılık ve close/flush sınırlarını
#           gerçek endpoint çağırmadan doğrular.
# ==============================================================================

testthat::local_edition(3)

.new_imgpersist_env <- function() {
  env <- new.env(parent = globalenv())
  for (name in c("utils_path_reservation.R", "helpers_files_promote_probe.R", "helpers_files_promote_target.R")) {
    source(file.path(resolve_repo_root_for_tests(), "R", name), encoding = "UTF-8", local = env)
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_image_generation.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

.imgpersist_env <- .new_imgpersist_env()
.image_png_b64_persistence <- "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYPgPAAEDAQAIicLsAAAAAElFTkSuQmCC"

.save_b64_for_test <- function(env, dir, b64 = .image_png_b64_persistence) {
  withr::with_dir(dir, {
    utils::capture.output(
      result <- env$save_image_locally(
        paste0("data:image/png;base64,", b64),
        user_id = 7,
        chat_id = 9
      )
    )
    result
  })
}

test_that("Base64 kaydı PNG olmayan decoded baytları yayınlamaz", {
  tmp <- withr::local_tempdir()
  bad_b64 <- base64enc::base64encode(charToRaw("bu bir png değildir"))

  log <- withr::with_dir(tmp, utils::capture.output(
    result <- .imgpersist_env$save_image_locally(
      paste0("data:image/png;base64,", bad_b64),
      user_id = 7,
      chat_id = 9
    )
  ))

  expect_null(result)
  expect_true(any(grepl("validate-png", log, fixed = TRUE)))
  expect_length(list.files(tmp, pattern = "\\.png$", recursive = TRUE), 0L)
})

test_that("Base64 data URL MIME türünü ve dosya uzantısını korur", {
  tmp <- withr::local_tempdir()
  cases <- list(
    jpeg = list(raw = base64enc::base64decode("/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDh6KKK9c8g/9k="), ext = "\\.jpg$"),
    gif = list(raw = base64enc::base64decode("R0lGODdhAQABAIEAACRSdgAAAAAAAAAAACwAAAAAAQABAAAIBAABBAQAOw=="), ext = "\\.gif$"),
    webp = list(raw = base64enc::base64decode("UklGRjQAAABXRUJQVlA4ICgAAACwAQCdASoBAAEAAUAmJZACdLoABGaAAP70iIfma2Nnogf9x2Buu8QA"), ext = "\\.webp$")
  )

  for (mime in names(cases)) {
    case <- cases[[mime]]
    b64 <- base64enc::base64encode(case$raw)
    withr::with_dir(tmp, utils::capture.output(
      result <- .imgpersist_env$save_image_locally(
        paste0("data:image/", mime, ";base64,", b64), user_id = 7, chat_id = 9
      )
    ))
    expect_match(result, case$ext)
    expect_true(file.exists(result))
    expect_identical(readBin(result, "raw", n = length(case$raw)), case$raw)
  }
})

test_that("Base64 kaydı aynı hedefte bile çağrıya özel geçici dosya kullanır", {
  tmp <- withr::local_tempdir()
  env <- .new_imgpersist_env()
  temp_counter <- 0L
  published_from <- character()
  published_to <- character()

  env$tempfile <- function(pattern = "file", tmpdir = tempdir(), fileext = "") {
    if (identical(fileext, ".png")) return(file.path(tmpdir, "fixed.png"))
    temp_counter <<- temp_counter + 1L
    file.path(tmpdir, paste0("owned-", temp_counter, fileext))
  }
  env$mergen_promote_staged_file <- function(staging, hedef, var_mi, ...) {
    published_from <<- c(published_from, staging)
    published_to <<- c(published_to, hedef)
    list(ok = TRUE, yabanci = FALSE, promoted = TRUE)
  }

  expect_true(is.character(.save_b64_for_test(env, tmp)))
  expect_true(is.character(.save_b64_for_test(env, tmp)))
  expect_length(published_from, 2L)
  expect_identical(length(unique(published_from)), 2L)
  expect_identical(length(unique(published_to)), 1L)
  expect_false(any(published_from == paste0(published_to, ".tmp")))
})

test_that("Base64 kaydı close hatasını başarı saymaz ve geçici dosyayı temizler", {
  tmp <- withr::local_tempdir()
  env <- .new_imgpersist_env()
  close_calls <- 0L

  env$close <- function(con, ...) {
    close_calls <<- close_calls + 1L
    if (close_calls == 1L) stop("simulated close failure")
    base::close(con, ...)
  }

  log <- withr::with_dir(tmp, utils::capture.output(
    result <- env$save_image_locally(
      paste0("data:image/png;base64,", .image_png_b64_persistence),
      user_id = 7,
      chat_id = 9
    )
  ))

  expect_null(result)
  expect_gte(close_calls, 2L)
  expect_true(any(grepl("Base64 kayıt hatası: close", log, fixed = TRUE)))
  expect_length(list.files(tmp, pattern = "\\.png$", recursive = TRUE), 0L)
  expect_length(list.files(tmp, pattern = "\\.tmp$", recursive = TRUE, all.files = TRUE), 0L)
})

test_that("başarısız Base64 yayını yalnızca kendisine ait kısmi hedefi temizler", {
  for (foreign in c(FALSE, TRUE)) {
    tmp <- withr::local_tempdir()
    env <- .new_imgpersist_env()
    targets <- character()
    env$mergen_promote_staged_file <- function(staging, hedef, var_mi, ...) {
      targets <<- c(targets, hedef)
      writeBin(charToRaw("partial-or-foreign"), hedef)
      list(ok = FALSE, promoted = FALSE, yabanci = foreign, partial_owned = !foreign)
    }

    expect_null(.save_b64_for_test(env, tmp))
    images <- list.files(tmp, pattern = "\\.(png|jpg|gif|webp)$", recursive = TRUE)
    expect_length(images, if (foreign) 3L else 0L)
    expect_true(all(file.exists(targets) == foreign))
    if (foreign) for (target in targets) {
      expect_identical(readBin(target, "raw", n = 100L), charToRaw("partial-or-foreign"))
    }
    expect_length(list.files(tmp, pattern = "\\.tmp$", recursive = TRUE, all.files = TRUE), 0L)
  }
})

test_that("kısmi terfi yazımı hiçbir görsel denemesinin hedefini geride bırakmaz", {
  tmp <- withr::local_tempdir()
  env <- .new_imgpersist_env()
  env$file.link <- env$file.rename <- function(...) FALSE
  attempts <- 0L
  env$file.copy <- function(from, to, ...) {
    attempts <<- attempts + 1L
    base::writeBin(charToRaw("partial"), to)
    FALSE
  }
  env$writeBin <- function(object, con, ...) {
    if (endsWith(summary(con)$description, ".png")) {
      attempts <<- attempts + 1L
      base::writeBin(object[1:8], con)
      stop("kısmi hedef")
    }
    base::writeBin(object, con, ...)
  }
  expect_null(.save_b64_for_test(env, tmp))
  expect_identical(attempts, 3L)
  expect_length(list.files(tmp, pattern = "\\.(png|tmp)$", recursive = TRUE, all.files = TRUE), 0L)
})

test_that("rezervasyon alınamayan Base64 kaydı sonradan yayımlanan hedefi silmez", {
  tmp <- withr::local_tempdir()
  env <- .new_imgpersist_env()
  env$file.link <- function(...) FALSE
  env$mergen_reservation_token <- function(...) "fixture-token"
  env$mergen_reservation_acquire <- function(...) FALSE
  reads <- 0L
  target <- NULL
  bytes <- base64enc::base64decode(.image_png_b64_persistence)
  env$file.exists <- function(path) {
    present <- base::file.exists(path)
    if (endsWith(path, ".png") && !present) {
      reads <<- reads + 1L
      if (reads == 2L) {
        target <<- path
        writeBin(bytes, path) # Son yoklamadan sonra başka istek tamamlanır.
      }
    }
    present
  }

  expect_null(.save_b64_for_test(env, tmp))
  expect_identical(reads, 2L)
  expect_true(base::file.exists(target))
  expect_identical(readBin(target, "raw", n = length(bytes)), bytes)
  expect_length(list.files(tmp, pattern = "\\.tmp$", recursive = TRUE, all.files = TRUE), 0L)
})

test_that("terfi yardımcısı yoksa Base64 kaydı güvenli biçimde durur", {
  tmp <- withr::local_tempdir()
  env <- .new_imgpersist_env()
  env$exists <- function(x, ...) {
    if (identical(x, "mergen_promote_staged_file")) return(FALSE)
    base::exists(x, ...)
  }
  env$file.rename <- function(...) stop("Yardımsız terfi denenmemeli")
  expect_null(.save_b64_for_test(env, tmp))
  expect_length(list.files(tmp, recursive = TRUE, all.files = TRUE, no.. = TRUE), 0L)
})

test_that("kesik JPEG GIF ve WebP imzaları başarı olarak yayınlanmaz", {
  tmp <- withr::local_tempdir()
  cases <- list(
    jpeg = list(as.raw(c(0xff, 0xd8, 0xff, 0xd9)),
                c(as.raw(c(0xff, 0xd8)), raw(40L), as.raw(c(0xff, 0xd9)))),
    gif = list(c(charToRaw("GIF89a"), as.raw(0x3b)),
               c(charToRaw("GIF89a"), raw(40L), as.raw(c(0, 0x3b)))),
    webp = list(c(charToRaw("RIFF"), raw(4L), charToRaw("WEBP")))
  )
  for (mime in names(cases)) for (bytes in cases[[mime]]) {
    withr::with_dir(tmp, utils::capture.output(
      result <- .imgpersist_env$save_image_locally(
        paste0("data:image/", mime, ";base64,", base64enc::base64encode(bytes)), 7, 9
      )
    ))
    expect_null(result, info = mime)
  }
  expect_length(list.files(tmp, recursive = TRUE, all.files = TRUE, no.. = TRUE), 0L)
})
