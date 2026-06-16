# ==============================================================================
# Dosya Yolu: tests/testthat/test-image-generation-ui-refactor-contract.R
# Açıklama: Görsel oluşturma UI/runtime ayrımı sözleşmesi. UI/HTML render
#           yapıcıları (imageSettingsUI, imageChatControlsUI,
#           render_generated_image_html, render_image_from_saved_path)
#           R/module_image_generation_ui.R içindedir; IO/üretim/çeviri
#           yardımcıları (generate_image, save_image_locally,
#           translate_*, get_user_image_dir, get_image_web_url) ve
#           IMAGE_SIZE_OPTIONS sabiti R/module_image_generation.R'de kalır.
#           Davranış kapsaması test-image-generation-module-behavior.R'dedir.
# ==============================================================================

testthat::local_edition(3)

.imggen_repo_root <- resolve_repo_root_for_tests()
.imggen_runtime_path <- file.path(.imggen_repo_root, "R", "module_image_generation.R")
.imggen_ui_path <- file.path(.imggen_repo_root, "R", "module_image_generation_ui.R")

# ASCII çapaları için bayt-güvenli okuyucu (Windows VM'de geçersiz UTF-8'e dayanıklı).
.imggen_read_bytes <- function(path) {
  raw <- readBin(path, what = "raw", n = file.info(path)$size)
  iconv(rawToChar(raw), from = "UTF-8", to = "UTF-8", sub = "byte")
}

# -----------------------------------------------------------------------------
# UI/runtime ayrım sözleşmesi
# -----------------------------------------------------------------------------

test_that("UI/HTML render yapıcıları yeni UI dosyasında tanımlıdır", {
  expect_true(file.exists(.imggen_ui_path))

  ui_env <- new.env(parent = globalenv())
  source(.imggen_ui_path, encoding = "UTF-8", local = ui_env)

  expect_true(exists("imageSettingsUI", envir = ui_env, inherits = FALSE))
  expect_true(exists("imageChatControlsUI", envir = ui_env, inherits = FALSE))
  expect_true(exists("render_generated_image_html", envir = ui_env, inherits = FALSE))
  expect_true(exists("render_image_from_saved_path", envir = ui_env, inherits = FALSE))
})

test_that("runtime dosyası UI yapıcılarını içermez, IO/üretim yardımcılarını içerir", {
  runtime_env <- new.env(parent = globalenv())
  source(.imggen_runtime_path, encoding = "UTF-8", local = runtime_env)

  # UI yapıcıları runtime dosyasından çıkarıldı.
  expect_false(exists("imageSettingsUI", envir = runtime_env, inherits = FALSE))
  expect_false(exists("imageChatControlsUI", envir = runtime_env, inherits = FALSE))
  expect_false(exists("render_generated_image_html", envir = runtime_env, inherits = FALSE))
  expect_false(exists("render_image_from_saved_path", envir = runtime_env, inherits = FALSE))

  # IO/üretim/çeviri yardımcıları ve UI render'ın çağrı anında ihtiyaç duyduğu
  # get_image_web_url + IMAGE_SIZE_OPTIONS runtime dosyasında kalır.
  expect_true(exists("generate_image", envir = runtime_env, inherits = FALSE))
  expect_true(exists("save_image_locally", envir = runtime_env, inherits = FALSE))
  expect_true(exists("translate_prompt_to_english", envir = runtime_env, inherits = FALSE))
  expect_true(exists("translate_revised_prompt_to_turkish", envir = runtime_env, inherits = FALSE))
  expect_true(exists("get_user_image_dir", envir = runtime_env, inherits = FALSE))
  expect_true(exists("get_image_web_url", envir = runtime_env, inherits = FALSE))
  expect_true(exists("IMAGE_SIZE_OPTIONS", envir = runtime_env, inherits = FALSE))

  # Kaynak metninde de UI yapıcıları runtime dosyasına geri taşınmamalı.
  runtime_text <- .imggen_read_bytes(.imggen_runtime_path)
  expect_false(grepl("imageSettingsUI <- function", runtime_text, fixed = TRUE, useBytes = TRUE))
  expect_false(grepl("render_generated_image_html <- function", runtime_text, fixed = TRUE, useBytes = TRUE))
})

test_that("manifest runtime dosyasını UI dosyasından önce yükler (bağımlılık-önce)", {
  expect_source_manifest_contains_for_tests(c(
    "R/module_image_generation.R",
    "R/module_image_generation_ui.R"
  ))
  expect_source_manifest_order_for_tests(c(
    "R/module_image_generation.R",
    "R/module_image_generation_ui.R"
  ))
})

test_that("generate_image worker yolu UI dosyasına bağımlı değildir (UI yapıcıları worker'da koşmaz)", {
  # generate_image yalnızca runtime dosyasındaki çeviri/kaydetme yardımcılarına
  # bağlıdır; UI render yapıcıları async worker görevinde çağrılmaz.
  runtime_text <- .imggen_read_bytes(.imggen_runtime_path)
  # generate_image gövdesi UI render fonksiyonlarını çağırmamalı.
  expect_false(grepl("render_generated_image_html(", runtime_text, fixed = TRUE, useBytes = TRUE))
  expect_false(grepl("imageSettingsUI(", runtime_text, fixed = TRUE, useBytes = TRUE))
})
