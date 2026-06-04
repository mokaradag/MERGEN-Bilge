# ==============================================================================
# Dosya Yolu: tests/testthat/test-image-generation-module-behavior.R
# Açıklama: R/module_image_generation.R görsel oluşturma modülünün davranışsal
#           testleri. Çeviri kapısı, yapılandırma/anahtar koruma yolları, yerel
#           dizin, web URL üretimi, UI bileşenleri ve HTML üretimi (XSS kaçışı).
#           Gerçek DALL-E/LLM endpoint'i çağrılmaz; httr mock ile yalıtılır.
# ==============================================================================

testthat::local_edition(3)

# UI oluşturucu fonksiyonlar div()/fluidRow()/selectInput() gibi shiny çağrıları
# kullandığı için shiny arama yoluna eklenir.
if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.imggen_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "module_image_generation.R"),
  encoding = "UTF-8",
  local = .imggen_env
)

# Çeviri yolu testleri için endpoint çözücüyü yalıtılmış ortamda stub'la.
.imggen_env$resolve_local_llm_endpoint <- function(model) "http://llm.local/v1"

# image_gen_config değişikliklerini geri almak için orijinali sakla.
.imggen_config_orig <- .imggen_env$image_gen_config

# cat() gürültüsünü bastırıp fonksiyon sonucunu döndürür.
.sessiz <- function(expr) {
  invisible(utils::capture.output(res <- expr))
  res
}

# -----------------------------------------------------------------------------
# Sabitler
# -----------------------------------------------------------------------------

test_that("IMAGE_SIZE_OPTIONS ve IMAGE_QUALITY_OPTIONS doğru Türkçe etiket/değerleri içerir", {
  expect_equal(unname(.imggen_env$IMAGE_SIZE_OPTIONS[["Kare (1024x1024)"]]), "1024x1024")
  expect_equal(unname(.imggen_env$IMAGE_SIZE_OPTIONS[["Yatay (1792x1024)"]]), "1792x1024")
  expect_equal(unname(.imggen_env$IMAGE_SIZE_OPTIONS[["Dikey (1024x1792)"]]), "1024x1792")
  expect_true("standard" %in% names(.imggen_env$IMAGE_QUALITY_OPTIONS))
  expect_true("hd" %in% names(.imggen_env$IMAGE_QUALITY_OPTIONS))
})

# -----------------------------------------------------------------------------
# get_user_image_dir
# -----------------------------------------------------------------------------

test_that("get_user_image_dir kullanıcı (ve sohbet) dizinini oluşturur", {
  tmp <- withr::local_tempdir()
  withr::with_dir(tmp, {
    dir1 <- .imggen_env$get_user_image_dir("42")
    expect_true(dir.exists(dir1))
    expect_true(grepl("user_images", dir1, fixed = TRUE))
    expect_true(grepl("42", dir1, fixed = TRUE))

    dir2 <- .imggen_env$get_user_image_dir("42", "sohbet9")
    expect_true(dir.exists(dir2))
    expect_true(grepl("sohbet9", dir2, fixed = TRUE))
  })
})

# -----------------------------------------------------------------------------
# translate_prompt_to_english
# -----------------------------------------------------------------------------

test_that("translate_prompt_to_english: çeviri modeli yapılandırılmamışsa orijinali döndürür", {
  # image_gen_config$translation_model varsayılan olarak "" (env yok).
  sonuc <- .sessiz(.imggen_env$translate_prompt_to_english("bir kedi çiz", "anahtar"))
  expect_equal(sonuc, "bir kedi çiz")
})

test_that("translate_prompt_to_english: metin İngilizce görünüyorsa çeviri atlanır", {
  withr::defer(.imggen_env$image_gen_config <- .imggen_config_orig)
  .imggen_env$image_gen_config$translation_model <- "ceviri-model"

  cagri <- new.env(); cagri$post <- 0L
  testthat::local_mocked_bindings(
    POST = function(...) { cagri$post <- cagri$post + 1L; structure(list(), class = "response") },
    .package = "httr"
  )

  sonuc <- .sessiz(.imggen_env$translate_prompt_to_english("a blue mountain landscape", "anahtar"))
  expect_equal(sonuc, "a blue mountain landscape")
  # İngilizce algılandığı için hiç HTTP isteği yapılmamalı.
  expect_identical(cagri$post, 0L)
})

test_that("translate_prompt_to_english: Türkçe metni başarılı çeviride İngilizceye çevirir", {
  withr::defer(.imggen_env$image_gen_config <- .imggen_config_orig)
  .imggen_env$image_gen_config$translation_model <- "ceviri-model"

  testthat::local_mocked_bindings(
    POST = function(...) structure(list(), class = "response"),
    status_code = function(...) 200L,
    content = function(...) list(choices = list(list(message = list(content = "  a cat  ")))),
    add_headers = function(...) NULL,
    timeout = function(...) NULL,
    .package = "httr"
  )

  sonuc <- .sessiz(.imggen_env$translate_prompt_to_english("güzel bir kedi resmi", "anahtar"))
  expect_equal(sonuc, "a cat")
})

test_that("translate_prompt_to_english: çeviri HTTP hatasında orijinal metne döner", {
  withr::defer(.imggen_env$image_gen_config <- .imggen_config_orig)
  .imggen_env$image_gen_config$translation_model <- "ceviri-model"

  testthat::local_mocked_bindings(
    POST = function(...) structure(list(), class = "response"),
    status_code = function(...) 500L,
    content = function(...) list(),
    add_headers = function(...) NULL,
    timeout = function(...) NULL,
    .package = "httr"
  )

  girdi <- "şehirde yağmurlu bir akşam"
  sonuc <- .sessiz(.imggen_env$translate_prompt_to_english(girdi, "anahtar"))
  expect_equal(sonuc, girdi)
})

# -----------------------------------------------------------------------------
# translate_revised_prompt_to_turkish
# -----------------------------------------------------------------------------

test_that("translate_revised_prompt_to_turkish: model yoksa İngilizce metni aynen döndürür", {
  sonuc <- .imggen_env$translate_revised_prompt_to_turkish("A red car", "anahtar")
  expect_equal(sonuc, "A red car")
})

test_that("translate_revised_prompt_to_turkish: başarılı çağrıda çevrilmiş yorumu döndürür", {
  withr::defer(.imggen_env$image_gen_config <- .imggen_config_orig)
  .imggen_env$image_gen_config$translation_model <- "ceviri-model"

  testthat::local_mocked_bindings(
    POST = function(...) structure(list(), class = "response"),
    status_code = function(...) 200L,
    content = function(...) list(choices = list(list(message = list(content = "Kırmızı bir araba.")))),
    add_headers = function(...) NULL,
    timeout = function(...) NULL,
    .package = "httr"
  )

  sonuc <- .sessiz(.imggen_env$translate_revised_prompt_to_turkish(
    "A red car", "anahtar", original_prompt = "kırmızı araba"
  ))
  expect_equal(sonuc, "Kırmızı bir araba.")
})

# -----------------------------------------------------------------------------
# generate_image (koruma yolları + başarı)
# -----------------------------------------------------------------------------

test_that("generate_image: endpoint yapılandırılmamışsa hata döndürür", {
  withr::defer(.imggen_env$image_gen_config <- .imggen_config_orig)

  # Test, kullanıcının gerçek .Renviron değerlerinden bağımsız olmalıdır.
  .imggen_env$image_gen_config$endpoint <- ""

  sonuc <- .sessiz(.imggen_env$generate_image("kedi", "anahtar"))

  expect_false(isTRUE(sonuc$success))
  expect_true(grepl("endpoint", sonuc$error, ignore.case = TRUE))
})

test_that("generate_image: API anahtarı boşsa hata döndürür", {
  withr::defer(.imggen_env$image_gen_config <- .imggen_config_orig)
  .imggen_env$image_gen_config$endpoint <- "http://img.local/gen"

  sonuc <- .sessiz(.imggen_env$generate_image("kedi", ""))
  expect_false(isTRUE(sonuc$success))
  expect_true(grepl("API anahtarı", sonuc$error, fixed = TRUE))
})

test_that("generate_image: başarılı yanıtta success=TRUE ve görsel verisi döndürür", {
  withr::defer(.imggen_env$image_gen_config <- .imggen_config_orig)
  withr::defer(.imggen_env$translate_prompt_to_english <- .tpe_orig)
  withr::defer(.imggen_env$translate_revised_prompt_to_turkish <- .trp_orig)
  withr::defer(.imggen_env$save_image_locally <- .sil_orig)

  .tpe_orig <- .imggen_env$translate_prompt_to_english
  .trp_orig <- .imggen_env$translate_revised_prompt_to_turkish
  .sil_orig <- .imggen_env$save_image_locally

  .imggen_env$image_gen_config$endpoint <- "http://img.local/gen"
  # Çeviri ve kaydetme yan etkilerini izole et.
  .imggen_env$translate_prompt_to_english <- function(prompt, api_key) prompt
  .imggen_env$translate_revised_prompt_to_turkish <- function(english_text, api_key, original_prompt = NULL) "Detaylı kedi yorumu"
  .imggen_env$save_image_locally <- function(image_url, user_id, chat_id = NULL) NULL

  testthat::local_mocked_bindings(
    POST = function(...) structure(list(), class = "response"),
    status_code = function(...) 200L,
    content = function(x, as = "parsed", ...) {
      list(data = list(list(url = "http://img.local/out.png", revised_prompt = "A detailed cat")))
    },
    add_headers = function(...) NULL,
    timeout = function(...) NULL,
    .package = "httr"
  )

  sonuc <- .sessiz(.imggen_env$generate_image("kedi", "anahtar", user_id = 7))
  expect_true(isTRUE(sonuc$success))
  expect_equal(sonuc$image_url, "http://img.local/out.png")
  expect_equal(sonuc$original_prompt, "kedi")
  expect_equal(sonuc$revised_prompt, "Detaylı kedi yorumu")
})

test_that("generate_image: API 200 dışı yanıtta hata mesajı döndürür", {
  withr::defer(.imggen_env$image_gen_config <- .imggen_config_orig)
  withr::defer(.imggen_env$translate_prompt_to_english <- .tpe_orig2)
  .tpe_orig2 <- .imggen_env$translate_prompt_to_english

  .imggen_env$image_gen_config$endpoint <- "http://img.local/gen"
  .imggen_env$translate_prompt_to_english <- function(prompt, api_key) prompt

  testthat::local_mocked_bindings(
    POST = function(...) structure(list(), class = "response"),
    status_code = function(...) 500L,
    content = function(x, as = "parsed", ...) {
      if (identical(as, "text")) return('{"error":{"message":"sunucu hatası"}}')
      list()
    },
    add_headers = function(...) NULL,
    timeout = function(...) NULL,
    .package = "httr"
  )

  sonuc <- .sessiz(.imggen_env$generate_image("kedi", "anahtar"))
  expect_false(isTRUE(sonuc$success))
  expect_true(grepl("API Hatası", sonuc$error, fixed = TRUE))
  expect_true(grepl("sunucu hatası", sonuc$error, fixed = TRUE))
})

# -----------------------------------------------------------------------------
# get_image_web_url
# -----------------------------------------------------------------------------

test_that("get_image_web_url: olmayan dosya için NULL, var olan dosya için data URL döndürür", {
  skip_if_not_installed("base64enc")

  expect_null(.imggen_env$get_image_web_url(NULL))
  expect_null(.imggen_env$get_image_web_url(file.path(tempdir(), "olmayan_dosya.png")))

  tmp <- tempfile(fileext = ".png")
  writeBin(as.raw(c(1, 2, 3, 4)), tmp)
  on.exit(unlink(tmp), add = TRUE)

  url <- .imggen_env$get_image_web_url(tmp)
  expect_true(is.character(url))
  expect_true(startsWith(url, "data:image/png;base64,"))
})

# -----------------------------------------------------------------------------
# UI bileşenleri
# -----------------------------------------------------------------------------

test_that("imageSettingsUI Türkçe başlık, boyut seçimi ve HD anahtarını üretir", {
  skip_if_not_installed("shiny")
  ns <- function(x) paste0("img-", x)
  html <- paste(as.character(.imggen_env$imageSettingsUI(ns)), collapse = "\n")

  expect_true(grepl("Görsel Oluşturma Ayarları", html, fixed = TRUE))
  expect_true(grepl("Görsel Boyutu", html, fixed = TRUE))
  expect_true(grepl("img-image_size", html, fixed = TRUE))
  expect_true(grepl("img-image_quality_hd", html, fixed = TRUE))
  # Boyut seçenekleri Türkçe etiketleriyle bulunmalı.
  expect_true(grepl("1024x1024", html, fixed = TRUE))
})

test_that("imageChatControlsUI ns ile ve ns olmadan (identity) doğru id'leri üretir", {
  skip_if_not_installed("shiny")

  html_ns <- paste(as.character(.imggen_env$imageChatControlsUI(function(x) paste0("c-", x))), collapse = "\n")
  expect_true(grepl("c-chat_image_size", html_ns, fixed = TRUE))
  expect_true(grepl("c-chat_image_quality_hd", html_ns, fixed = TRUE))
  expect_true(grepl("Kare", html_ns, fixed = TRUE))
  expect_true(grepl("Yatay", html_ns, fixed = TRUE))
  expect_true(grepl("Dikey", html_ns, fixed = TRUE))

  html_id <- paste(as.character(.imggen_env$imageChatControlsUI(NULL)), collapse = "\n")
  # ns NULL ise identity: ham id'ler kullanılır.
  expect_true(grepl("\"chat_image_size\"", html_id, fixed = TRUE))
  expect_true(grepl("\"chat_image_quality_hd\"", html_id, fixed = TRUE))
})

# -----------------------------------------------------------------------------
# render_generated_image_html
# -----------------------------------------------------------------------------

test_that("render_generated_image_html: başarısız sonuçta kaçışlı hata kutusu üretir", {
  html <- .imggen_env$render_generated_image_html(
    list(success = FALSE, error = "<script>alert(1)</script>"),
    message_id = "m1"
  )
  expect_true(grepl("image-error-container", html, fixed = TRUE))
  # XSS kaçışı: ham script etiketi gözükmemeli.
  expect_false(grepl("<script>", html, fixed = TRUE))
  expect_true(grepl("&lt;script&gt;", html, fixed = TRUE))
})

test_that("render_generated_image_html: başarılı sonuçta görsel, filigran ve butonları üretir", {
  html <- .imggen_env$render_generated_image_html(
    list(
      success = TRUE,
      image_url = "http://img.local/x.png",
      local_path = NULL,
      revised_prompt = "Mavi gökyüzü"
    ),
    message_id = "msg42"
  )
  expect_true(grepl("data-message-id=\"msg42\"", html, fixed = TRUE))
  expect_true(grepl("http://img.local/x.png", html, fixed = TRUE))
  expect_true(grepl("MERGEN Bilge", html, fixed = TRUE))
  expect_true(grepl("downloadGeneratedImage", html, fixed = TRUE))
  # Açıklama (revised_prompt) gösterilmeli.
  expect_true(grepl("Mavi gökyüzü", html, fixed = TRUE))
})

test_that("render_generated_image_html: revised_prompt içindeki HTML kaçışlanır", {
  html <- .imggen_env$render_generated_image_html(
    list(success = TRUE, image_url = "http://x/y.png", local_path = NULL,
         revised_prompt = "<img src=x onerror=alert(1)>"),
    message_id = "m"
  )
  expect_false(grepl("onerror=alert(1)>", html, fixed = TRUE))
  expect_true(grepl("&lt;img", html, fixed = TRUE))
})

# -----------------------------------------------------------------------------
# render_image_from_saved_path
# -----------------------------------------------------------------------------

test_that("render_image_from_saved_path: boş/olmayan yol için NULL döner", {
  expect_null(.sessiz(.imggen_env$render_image_from_saved_path(NULL, "açıklama", "m")))
  expect_null(.sessiz(.imggen_env$render_image_from_saved_path("", "açıklama", "m")))
  expect_null(.sessiz(.imggen_env$render_image_from_saved_path(
    file.path(tempdir(), "yok_olan_resim.png"), "açıklama", "m"
  )))
})

test_that("render_image_from_saved_path: var olan dosya için açıklamalı HTML üretir", {
  skip_if_not_installed("base64enc")

  tmp <- tempfile(fileext = ".png")
  writeBin(as.raw(c(10, 20, 30)), tmp)
  on.exit(unlink(tmp), add = TRUE)

  html <- .sessiz(.imggen_env$render_image_from_saved_path(tmp, "Kaydedilmiş görsel açıklaması", "m7"))
  expect_true(is.character(html))
  expect_true(grepl("data-message-id=\"m7\"", html, fixed = TRUE))
  expect_true(grepl("data:image/png;base64,", html, fixed = TRUE))
  expect_true(grepl("Kaydedilmiş görsel açıklaması", html, fixed = TRUE))
  expect_true(grepl("MERGEN Bilge", html, fixed = TRUE))
})