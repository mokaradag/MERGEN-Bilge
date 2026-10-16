# ==============================================================================
# Dosya Yolu: tests/testthat/test-image-generation-response-guards.R
# Açıklama: Base64 yanıt boyutu, opsiyonel revised_prompt ve güvenli yerel
#           yayınlama için dar regresyon testleri.
# ==============================================================================

testthat::local_edition(3)

.img_guard_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "module_image_generation.R"),
  encoding = "UTF-8",
  local = .img_guard_env
)
.img_guard_env$resolve_local_llm_endpoint <- function(model) "http://llm.local/v1"

.guard_png_b64 <- "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYPgPAAEDAQAIicLsAAAAAElFTkSuQmCC"

.guard_sessiz <- function(expr) {
  invisible(utils::capture.output(res <- expr))
  res
}

.guard_mock_image_api <- function(image_data, .local_envir = parent.frame()) {
  testthat::local_mocked_bindings(
    POST = function(...) structure(list(), class = "response"),
    status_code = function(...) 200L,
    content = function(...) list(data = list(image_data)),
    .package = "httr", .env = .local_envir
  )
  rlang::local_bindings(
    image_gen_config = list(
      endpoint = "http://img.local/gen", model = "FLUX.2-dev",
      translation_model = "", timeout = 180
    ),
    .env = .img_guard_env, .frame = .local_envir
  )
}

.guard_saved_files <- function(root) {
  if (!dir.exists(root)) return(character())
  list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE,
             include.dirs = FALSE, no.. = TRUE)
}

test_that("generate_image boş dizi revised_prompt değerini yok sayar", {
  .guard_mock_image_api(list(b64_json = .guard_png_b64, revised_prompt = character()))

  sonuc <- .guard_sessiz(.img_guard_env$generate_image("a cat", "anahtar"))

  expect_true(sonuc$success)
  expect_null(sonuc$revised_prompt)
  expect_identical(sonuc$image_url, paste0("data:image/png;base64,", .guard_png_b64))
})

test_that("generate_image encoded Base64 sınırını veri URL'si oluşturmadan reddeder", {
  .guard_mock_image_api(list(b64_json = "QUJDREVGR0g="))
  rlang::local_bindings(
    IMAGE_GEN_MAX_BASE64_ENCODED_BYTES = 8,
    .env = .img_guard_env
  )

  sonuc <- .guard_sessiz(.img_guard_env$generate_image("a cat", "anahtar"))

  expect_false(sonuc$success)
  expect_identical(sonuc$error, "API yanıtındaki görsel verisi izin verilen boyutu aşıyor")
  expect_null(sonuc$image_url)
})

test_that("save_image_locally decoded Base64 sınırını yazmadan reddeder", {
  withr::local_dir(withr::local_tempdir())
  rlang::local_bindings(IMAGE_GEN_MAX_DECODED_BYTES = 1, .env = .img_guard_env)

  log <- utils::capture.output(sonuc <- .img_guard_env$save_image_locally(
    paste0("data:image/png;base64,", .guard_png_b64), 7
  ))

  expect_null(sonuc)
  expect_true(any(grepl("Base64 kayıt hatası: decoded-size", log, fixed = TRUE)))
  expect_length(.guard_saved_files(file.path(getwd(), "user_images", "7")), 0L)
})

test_that("save_image_locally decode hatasını aşama bazlı ve payloadsuz loglar", {
  withr::local_dir(withr::local_tempdir())
  testthat::local_mocked_bindings(
    base64decode = function(...) stop("forced decode failure"),
    .package = "base64enc"
  )

  log <- utils::capture.output(sonuc <- .img_guard_env$save_image_locally(
    paste0("data:image/png;base64,", .guard_png_b64), 7
  ))

  expect_null(sonuc)
  expect_true(any(grepl("Base64 kayıt hatası: decode", log, fixed = TRUE)))
  expect_false(any(grepl("forced decode failure", log, fixed = TRUE)))
  expect_false(any(grepl(substr(.guard_png_b64, 1, 30), log, fixed = TRUE)))
})

test_that("save_image_locally dosya açma hatasını aşama bazlı loglar", {
  withr::local_dir(withr::local_tempdir())
  rlang::local_bindings(
    file = function(...) stop("forced file open failure"),
    .env = .img_guard_env
  )

  log <- utils::capture.output(sonuc <- .img_guard_env$save_image_locally(
    paste0("data:image/png;base64,", .guard_png_b64), 7
  ))

  expect_null(sonuc)
  expect_true(any(grepl("Base64 kayıt hatası: file-open", log, fixed = TRUE)))
  expect_false(any(grepl("forced file open failure", log, fixed = TRUE)))
  expect_length(.guard_saved_files(file.path(getwd(), "user_images", "7")), 0L)
})

test_that("save_image_locally yazma hatasında kısmi PNG veya temp dosya bırakmaz", {
  withr::local_dir(withr::local_tempdir())
  rlang::local_bindings(
    writeBin = function(...) stop("forced write failure"),
    .env = .img_guard_env
  )

  log <- utils::capture.output(sonuc <- .img_guard_env$save_image_locally(
    paste0("data:image/png;base64,", .guard_png_b64), 7
  ))

  expect_null(sonuc)
  expect_true(any(grepl("Base64 kayıt hatası: write", log, fixed = TRUE)))
  expect_false(any(grepl("forced write failure", log, fixed = TRUE)))
  expect_length(.guard_saved_files(file.path(getwd(), "user_images", "7")), 0L)
})
