# ==============================================================================
# Dosya Yolu: tests/testthat/test-image-generation-format-persistence.R
# Açıklama: Görsel yanıt biçimi, MIME sunumu ve çakışmasız yerel yayınlama
#           regresyonları. Ağ/gerçek model çağrısı yoktur.
# ==============================================================================

testthat::local_edition(3)

.image_fix_env <- function() {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_markdown_safety.R"),
         encoding = "UTF-8", local = env)
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_image_gallery.R"),
         encoding = "UTF-8", local = env)
  source(file.path(resolve_repo_root_for_tests(), "R", "module_image_generation.R"),
         encoding = "UTF-8", local = env)
  env
}

.image_fix_promote <- function(staging, hedef, var_mi, ...) {
  if (isTRUE(var_mi(hedef))) return(list(ok = FALSE, yabanci = TRUE, promoted = FALSE))
  moved <- isTRUE(suppressWarnings(file.rename(staging, hedef)))
  list(ok = moved && isTRUE(var_mi(hedef)), yabanci = FALSE, promoted = moved)
}

.image_fix_png_b64 <- "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

testthat::test_that("28 baytlık geçerli kayıpsız WebP değişmeden kaydedilir", {
  env <- .image_fix_env()
  env$mergen_promote_staged_file <- .image_fix_promote
  # libwebp/Pillow ile çözülen 1x1 saydam VP8L: 12 RIFF + 8 chunk + 8 veri baytı.
  bytes <- base64enc::base64decode("UklGRhQAAABXRUJQVlA4TAgAAAAvAAAAEIiICA==")
  testthat::expect_length(bytes, 28L)
  tmp <- withr::local_tempdir()
  withr::with_dir(tmp, {
    invisible(utils::capture.output(result <- env$save_image_locally(
      paste0("data:image/webp;base64,", base64enc::base64encode(bytes)), 7, 9
    )))
    testthat::expect_true(endsWith(result, ".webp"))
    testthat::expect_identical(readBin(result, "raw", n = 100L), bytes)
  })
})

testthat::test_that("parametreli data URL MIME ve mevcut doğrulama sınırlarını korur", {
  env <- .image_fix_env()
  env$mergen_promote_staged_file <- .image_fix_promote
  tmp <- withr::local_tempdir()
  withr::with_dir(tmp, {
    invisible(utils::capture.output(result <- env$save_image_locally(
      paste0("data:image/png;charset=utf-8;base64,", .image_fix_png_b64), 7, 9
    )))
    testthat::expect_true(endsWith(result, ".png"))
    testthat::expect_identical(readBin(result, "raw", n = 100L), base64enc::base64decode(.image_fix_png_b64))
    for (url in c(paste0("data:image/svg+xml;charset=utf-8;base64,", .image_fix_png_b64),
                  "data:image/png;charset=utf-8;base64,AAAA")) {
      invisible(utils::capture.output(rejected <- env$save_image_locally(url, 7, 9)))
      testthat::expect_null(rejected)
    }
  })
})

testthat::test_that("galeri ve oturumsuz sunum kaydedilen uzantının MIME türünü korur", {
  env <- .image_fix_env()
  tmp <- withr::local_tempdir()
  beklenen <- c(jpg = "image/jpeg", jpeg = "image/jpeg", gif = "image/gif", webp = "image/webp")

  for (ext in names(beklenen)) {
    yol <- file.path(tmp, paste0("ornek.", ext))
    writeBin(as.raw(c(1, 2, 3, 4)), yol)

    galeri <- env$get_image_thumbnail_base64(yol)
    sohbet <- env$mergen_serve_image_data_url(yol, session = NULL)

    testthat::expect_true(startsWith(galeri, paste0("data:", beklenen[[ext]], ";base64,")), info = ext)
    testthat::expect_true(startsWith(sohbet, paste0("data:", beklenen[[ext]], ";base64,")), info = ext)
  }
})

testthat::test_that("generate_image JPEG b64_json yanıtını JPEG olarak kaydeder", {
  env <- .image_fix_env()
  env$image_gen_config$endpoint <- "http://img.local/v1/images/generations"
  env$image_gen_config$translation_model <- ""
  env$mergen_promote_staged_file <- .image_fix_promote
  jpeg_b64 <- "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDh6KKK9c8g/9k="

  testthat::local_mocked_bindings(
    POST = function(...) structure(list(), class = "response"),
    status_code = function(...) 200L,
    content = function(x, as = NULL, ...) {
      list(data = list(list(b64_json = jpeg_b64)))
    },
    .package = "httr"
  )

  tmp <- withr::local_tempdir()
  withr::with_dir(tmp, {
    sonuc <- invisible(utils::capture.output(
      deger <- env$generate_image("a cat", "anahtar", user_id = 7L, chat_id = 9L)
    ))
    testthat::expect_true(deger$success)
    testthat::expect_null(deger$image_url)
    testthat::expect_true(endsWith(deger$local_path, ".jpg"))
    testthat::expect_identical(
      readBin(deger$local_path, "raw", file.info(deger$local_path)$size),
      base64enc::base64decode(jpeg_b64)
    )
    jpeg_raw <- base64enc::base64decode(jpeg_b64)
    jpeg_b64 <- base64enc::base64encode(c(jpeg_raw, charToRaw("trailing metadata")))
    invisible(utils::capture.output(trailed <- env$generate_image("a cat", "anahtar", user_id = 7L)))
    testthat::expect_true(trailed$success)
    testthat::expect_identical(readBin(trailed$local_path, "raw", n = 1000L),
                               c(jpeg_raw, charToRaw("trailing metadata")))
    jpeg_b64 <- base64enc::base64encode(head(jpeg_raw, -2L))
    invisible(utils::capture.output(truncated <- env$generate_image("a cat", "anahtar", user_id = 7L)))
    testthat::expect_false(truncated$success)
  })
})

testthat::test_that("PNG IEND sonrasındaki zararsız trailing baytlar kaydı bozmaz", {
  env <- .image_fix_env()
  env$mergen_promote_staged_file <- .image_fix_promote
  png_raw <- c(base64enc::base64decode(.image_fix_png_b64), as.raw(c(1, 2, 3)))
  data_url <- paste0("data:image/png;base64,", base64enc::base64encode(png_raw))

  tmp <- withr::local_tempdir()
  withr::with_dir(tmp, {
    yol <- invisible(utils::capture.output(
      deger <- env$save_image_locally(data_url, 7L, 9L)
    ))
    testthat::expect_true(is.character(deger) && length(deger) == 1L)
    testthat::expect_true(file.exists(deger))
    testthat::expect_true(endsWith(deger, ".png"))
  })
})

testthat::test_that("Base64 yayın hedef çakışmasında yeni ada yeniden denenir", {
  env <- .image_fix_env()
  targets <- character()
  calls <- 0L
  env$mergen_promote_staged_file <- function(staging, hedef, var_mi, ...) {
    calls <<- calls + 1L
    targets <<- c(targets, hedef)
    if (calls == 1L) return(list(ok = FALSE, yabanci = TRUE, promoted = FALSE))
    moved <- isTRUE(suppressWarnings(file.rename(staging, hedef)))
    list(ok = moved && isTRUE(var_mi(hedef)), yabanci = FALSE, promoted = moved)
  }
  data_url <- paste0("data:image/png;base64,", .image_fix_png_b64)

  tmp <- withr::local_tempdir()
  withr::with_dir(tmp, {
    invisible(utils::capture.output(
      deger <- env$save_image_locally(data_url, 7L, 9L)
    ))
    testthat::expect_true(file.exists(deger))
    testthat::expect_identical(calls, 2L)
    testthat::expect_length(unique(targets), 2L)
    testthat::expect_identical(deger, targets[[2L]])
  })
})

testthat::test_that("GIF trailer sonrasındaki baytlar korunur, kesik görüntü reddedilir", {
  env <- .image_fix_env()
  env$mergen_promote_staged_file <- .image_fix_promote
  gif_raw <- base64enc::base64decode("R0lGODdhAQABAIEAACRSdgAAAAAAAAAAACwAAAAAAQABAAAIBAABBAQAOw==")
  gif_raw[7] <- as.raw(0x2c) # 44 piksellik tuval: başlıktaki virgül görüntü ayıracı değildir.
  tmp <- withr::local_tempdir()
  withr::with_dir(tmp, {
    bytes <- c(gif_raw, charToRaw("trailing metadata"))
    invisible(utils::capture.output(result <- env$save_image_locally(
      paste0("data:image/gif;base64,", base64enc::base64encode(bytes)), 7, 9
    )))
    testthat::expect_true(file.exists(result))
    testthat::expect_identical(readBin(result, "raw", n = 1000L), bytes)
    invisible(utils::capture.output(truncated <- env$save_image_locally(
      paste0("data:image/gif;base64,", base64enc::base64encode(head(gif_raw, -1L))), 7, 9
    )))
    testthat::expect_null(truncated)
    testthat::expect_length(list.files(tmp, pattern = "\\.gif$", recursive = TRUE), 1L)
  })
})
