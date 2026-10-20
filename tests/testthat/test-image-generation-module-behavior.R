# ==============================================================================
# Dosya Yolu: tests/testthat/test-image-generation-module-behavior.R
# Açıklama: R/module_image_generation.R görsel oluşturma modülünün davranışsal
#           testleri. Çeviri kapısı, yapılandırma/anahtar koruma yolları, yerel
#           dizin, web URL üretimi, UI bileşenleri ve HTML üretimi (XSS kaçışı).
#           Gerçek görsel/LLM endpoint'i çağrılmaz; httr mock ile yalıtılır.
# ==============================================================================

testthat::local_edition(3)

# UI oluşturucu fonksiyonlar div()/fluidRow()/selectInput() gibi shiny çağrıları
# kullandığı için shiny arama yoluna eklenir.
if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.imggen_env <- new.env(parent = globalenv())
for (name in c("utils_path_reservation.R", "helpers_files_promote_probe.R", "helpers_files_promote_target.R")) {
  source(file.path(resolve_repo_root_for_tests(), "R", name), encoding = "UTF-8", local = .imggen_env)
}

# render_* fonksiyonları artık kanonik mergen_generated_image_card_html
# (helpers_markdown_safety.R) yardımcısına delege eder. helper_bootstrap bunu
# yüklemediği izole koşumlarda WD-bağımsız repo kökünden yalnızca yoksa yükle.
if (!exists("mergen_generated_image_card_html", mode = "function")) {
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_markdown_safety.R"),
    encoding = "UTF-8",
    local = .imggen_env
  )
}

source(
  file.path(resolve_repo_root_for_tests(), "R", "module_image_generation.R"),
  encoding = "UTF-8",
  local = .imggen_env
)
# UI/HTML render yapıcıları ayrı dosyada (UI/runtime ayrımı); runtime dosyasından
# sonra source edilir (render_* yapıcıları get_image_web_url'i çağrı anında çözer).
source(
  file.path(resolve_repo_root_for_tests(), "R", "module_image_generation_ui.R"),
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

test_that("görsel modeli FLUX.2-dev varsayılanını ve yapılandırılan modeli kullanır", {
  for (model in c(NA_character_, "custom-image-model")) {
    withr::with_envvar(c(IMAGE_GEN_MODEL = model), {
      env <- new.env(parent = globalenv())
      source(file.path(resolve_repo_root_for_tests(), "R", "module_image_generation.R"),
             encoding = "UTF-8", local = env)
      expect_identical(env$image_gen_config$model, if (is.na(model)) "FLUX.2-dev" else model)
    })
  }
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

# Küçük, geçerli 1x1 PNG; üretim verisi veya büyük görsel fixture'ı içermez.
.image_png_b64 <- "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYPgPAAEDAQAIicLsAAAAAElFTkSuQmCC"

.mock_image_api <- function(image_data, .local_envir = parent.frame()) {
  testthat::local_mocked_bindings(
    POST = function(...) structure(list(), class = "response"),
    status_code = function(...) 200L,
    content = function(...) list(data = list(image_data)),
    .package = "httr", .env = .local_envir
  )
  rlang::local_bindings(
    image_gen_config = list(endpoint = "http://img.local/gen", model = "FLUX.2-dev",
                            translation_model = "", timeout = 180),
    .env = .imggen_env, .frame = .local_envir
  )
}

test_that("generate_image: Base64 yanıtı url ve revised_prompt olmadan veri URL'sine dönüşür", {
  .mock_image_api(list(b64_json = .image_png_b64))
  log <- utils::capture.output(sonuc <- .imggen_env$generate_image("a cat", "anahtar"))

  expect_true(sonuc$success)
  expect_identical(sonuc$image_url, paste0("data:image/png;base64,", .image_png_b64))
  expect_null(sonuc$revised_prompt)
  expect_null(sonuc$local_path)
  expect_false(any(grepl(substr(.image_png_b64, 1, 30), log, fixed = TRUE)))
})

test_that("generate_image: Base64 terfi sonrası gecikmeli görünürlükte çizilir ve yeniden yüklenir", {
  repo_root <- resolve_repo_root_for_tests()
  .mock_image_api(list(b64_json = .image_png_b64))
  rlang::local_bindings(mergen_promote_staged_file = function(staging, hedef, ...) {
    moved <- file.rename(staging, hedef)
    list(promoted = moved, ok = FALSE, yabanci = FALSE)
  }, .env = .imggen_env)
  withr::local_dir(withr::local_tempdir())
  log <- utils::capture.output(sonuc <- .imggen_env$generate_image(
    "a cat", "anahtar", user_id = 7, chat_id = 9
  ))

  expect_true(sonuc$success)
  expect_true(file.exists(sonuc$local_path))
  expect_gt(file.info(sonuc$local_path)$size, 0)
  expect_identical(readBin(sonuc$local_path, "raw", n = file.info(sonuc$local_path)$size),
                   base64enc::base64decode(.image_png_b64))
  expect_null(sonuc$image_url)
  expect_null(sonuc$revised_prompt)
  expect_false(any(grepl(substr(.image_png_b64, 1, 30), log, fixed = TRUE)))
  expect_false(grepl(.image_png_b64, jsonlite::toJSON(sonuc, auto_unbox = TRUE), fixed = TRUE))

  # Oturum servisi dosya yolunu alır; kart ve yeniden yükleme API yükünü istemez.
  rlang::local_bindings(mergen_serve_image_data_url = function(path) {
    expect_identical(path, sonuc$local_path)
    "session/image.png"
  }, .env = .imggen_env)
  visibility_checks <- 0L
  rlang::local_bindings(file.exists = function(path) {
    visibility_checks <<- visibility_checks + 1L
    if (visibility_checks == 1L) FALSE else base::file.exists(path)
  }, .env = .imggen_env)
  expect_true(any(grepl("hedef henüz görünmüyor", log, fixed = TRUE)))
  html <- .imggen_env$render_generated_image_html(sonuc, "flux-image")
  expect_identical(visibility_checks, 2L)
  restored <- .imggen_env$render_image_from_saved_path(sonuc$local_path, NULL, "flux-reload")
  expect_match(html, 'src="session/image.png"', fixed = TRUE)
  expect_match(restored, 'src="session/image.png"', fixed = TRUE)
  expect_false(grepl("base64,", html, fixed = TRUE))
  saved_chat <- new.env(parent = .imggen_env)
  source(file.path(repo_root, "R", "helpers_chat_message_formatting.R"),
         encoding = "UTF-8", local = saved_chat)
  reloaded <- saved_chat$db_message_render_image_html(sonuc$local_path, NULL, "flux-saved", user_id = 7)
  expect_match(reloaded, 'src="session/image.png"', fixed = TRUE)

  # Üretim işleyicisi sohbet metnine yalnızca yerel yol işaretini yazar.
  handler <- new.env(parent = .imggen_env)
  source(file.path(repo_root, "R", "server_handler_image_generation.R"),
         encoding = "UTF-8", local = handler)
  handler$mb_api_key_get_feature_key_value <- function(...) "anahtar"
  handler$removeUI <- handler$insertUI <- handler$showToast <- handler$log_debug <- function(...) NULL
  handler$tracked_future_promise <- function(...) promises::promise_resolve(sonuc)
  handler$`%...>%` <- promises::`%...>%`
  handler$`%...!%` <- promises::`%...!%`
  testthat::local_mocked_bindings(runjs = function(...) NULL, .package = "shinyjs")
  messages <- list()
  values <- new.env()
  values$current_chat_id <- 9
  handler$handle_image_generation_mode(list(
    input = list(), settings_data = list(), values = values,
    session = list(token = "image-test"), current_user_id = 7, user_message_text = "a cat",
    add_message_fn = function(content, type, html) {
      messages[[length(messages) + 1L]] <<- list(content = content, type = type, html = html)
    },
    reset_chat_state_fn = function() NULL
  ))
  for (i in seq_len(100L)) {
    if (later::loop_empty()) break
    later::run_now(timeout = 0)
  }
  expect_length(messages, 1L)
  expect_identical(messages[[1]]$content, paste0("[GÖRSEL:", sonuc$local_path, "] [Görsel oluşturuldu]"))
  expect_match(messages[[1]]$html, 'src="session/image.png"', fixed = TRUE)
  expect_false(grepl(.image_png_b64, messages[[1]]$content, fixed = TRUE))
})

test_that("generate_image: Base64 yerel kayıt başarısızsa veri içermeyen kontrollü hata döner", {
  .mock_image_api(list(b64_json = .image_png_b64))
  rlang::local_bindings(save_image_locally = function(...) NULL, .env = .imggen_env)
  sonuc <- .sessiz(.imggen_env$generate_image("a cat", "anahtar", user_id = 7))
  expect_false(sonuc$success)
  expect_identical(sonuc$error, "Görsel verisi yerel olarak kaydedilemedi")
  expect_null(sonuc$image_url)
})

test_that("generate_image: Base64 çözme hatası HTTP indirmesine düşmez ve yükü loglamaz", {
  .mock_image_api(list(b64_json = .image_png_b64))
  withr::local_dir(withr::local_tempdir())
  testthat::local_mocked_bindings(base64decode = function(...) stop("decode failed"),
                                 .package = "base64enc")
  get_calls <- 0L
  testthat::local_mocked_bindings(GET = function(...) {
    get_calls <<- get_calls + 1L
    stop("HTTP çağrılmamalı")
  }, .package = "httr")
  log <- utils::capture.output(sonuc <- .imggen_env$generate_image("a cat", "anahtar", user_id = 7))
  expect_false(sonuc$success)
  expect_identical(sonuc$error, "Görsel verisi yerel olarak kaydedilemedi")
  expect_identical(get_calls, 0L)
  expect_false(any(grepl(substr(.image_png_b64, 1, 30), log, fixed = TRUE)))
})

test_that("generate_image: URL varsa Base64 yerine URL korunur ve istek sözleşmesi değişmez", {
  .mock_image_api(list(url = "http://img.local/out.png", b64_json = .image_png_b64))
  rlang::local_bindings(
    save_image_locally = function(image_url, user_id, chat_id = NULL) {
      expect_identical(image_url, "http://img.local/out.png")
      "local/path.png"
    },
    .env = .imggen_env
  )
  testthat::local_mocked_bindings(
    base64decode = function(...) stop("Base64 çözülmemeli"),
    .package = "base64enc"
  )
  request <- NULL
  testthat::local_mocked_bindings(POST = function(url, ..., body) {
    expect_identical(url, "http://img.local/gen")
    request <<- jsonlite::fromJSON(body)
    structure(list(), class = "response")
  }, .package = "httr")
  sonuc <- .sessiz(.imggen_env$generate_image(
    "a cat", "anahtar", size = "1792x1024", quality = "hd", user_id = 7
  ))
  expect_true(sonuc$success)
  expect_identical(sonuc$image_url, "http://img.local/out.png")
  expect_identical(sonuc$local_path, "local/path.png")
  expect_null(sonuc$revised_prompt)
  expect_equal(request, list(model = "FLUX.2-dev", prompt = "a cat", n = 1,
                             size = "1792x1024", quality = "hd"))
})

test_that("generate_image: boş veya desteklenmeyen başarılı yanıt kontrollü veri hatası döndürür", {
  for (image_data in list(list(foo = "bar"), list(url = ""), list(b64_json = ""),
                          list(url = NA_character_), "invalid", NULL)) {
    local({
      .mock_image_api(image_data)
      sonuc <- .sessiz(.imggen_env$generate_image("a cat", "anahtar"))
      expect_false(sonuc$success)
      expect_identical(sonuc$error, "API yanıtında görsel verisi bulunamadı")
    })
  }
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

test_that("görsel render görünürlük denemesi sınırlıdır ve mevcut URL yedeğini korur", {
  attempts <- 0L
  waits <- numeric()
  rlang::local_bindings(
    get_image_web_url = function(path) { attempts <<- attempts + 1L; NULL },
    Sys.sleep = function(seconds) { waits <<- c(waits, seconds) },
    .env = .imggen_env
  )
  html <- .imggen_env$render_generated_image_html(
    list(success = TRUE, local_path = "pending.png", image_url = "http://img.local/image.png"), "pending"
  )
  expect_identical(attempts, 6L)
  expect_identical(waits, rep(0.02, 5L))
  expect_match(html, 'src="http://img.local/image.png"', fixed = TRUE)
})

test_that("görsel render çözülemeyen kaynakta başarı kartı yerine görüntüleme hatası üretir", {
  attempts <- 0L
  rlang::local_bindings(
    get_image_web_url = function(path) { attempts <<- attempts + 1L; NULL },
    Sys.sleep = function(...) NULL,
    mergen_generated_image_card_html = function(...) stop("Kaynaksız kart üretilmemeli"),
    .env = .imggen_env
  )
  for (src in list(NULL, character(), "", NA_character_, c("a", "b"), FALSE, "  ")) {
    result <- list(success = TRUE, local_path = "pending.png", image_url = src)
    html <- .imggen_env$render_generated_image_html(result, "pending")
    expect_match(html, "image-error-container", fixed = TRUE)
    expect_match(html, "Görsel oluşturuldu ancak görüntülenemedi.", fixed = TRUE)
    expect_false(grepl("generated-image-container", html, fixed = TRUE))
    expect_true(result$success)
  }
  expect_identical(attempts, 42L)
})
