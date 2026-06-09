# ==============================================================================
# Dosya Yolu: tests/testthat/test-generated-image-card-html-contract.R
# Açıklama: Oluşturulan görsel kartı HTML işaretlemesi artık tek kanonik
#           yardımcıda (mergen_generated_image_card_html, helpers_markdown_safety.R)
#           toplanır. Bu test:
#             1) yardımcının XSS-güvenli kart sözleşmesini dondurur,
#             2) aynı kart işaretlemesinin görsel oluşturma ve sohbet mesajı
#                biçimlendirme yollarında yeniden çoğaltılmadığını korur.
#           Gerçek DB/LLM/tarayıcı gerektirmez; saf string davranışıdır.
# ==============================================================================

testthat::local_edition(3)

# UI/HTML kaçışı htmltools'a bağlıdır; izole koşumda arama yoluna ekle.
if (requireNamespace("htmltools", quietly = TRUE)) {
  suppressMessages(library(htmltools))
}

.img_card_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_markdown_safety.R"),
  encoding = "UTF-8",
  local = .img_card_env
)

# Repo dosyalarını Windows/VM güvenli biçimde bayt olarak okur (geçersiz UTF-8'e
# dayanıklı). Plain readLines + grepl yerine bu desen kullanılır.
.read_repo_text_img_card <- function(path) {
  full_path <- file.path(resolve_repo_root_for_tests(), path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  enc2utf8(txt)
}

# -----------------------------------------------------------------------------
# Kanonik kart sözleşmesi
# -----------------------------------------------------------------------------

test_that("mergen_generated_image_card_html kanonik kart yapısını üretir", {
  html <- .img_card_env$mergen_generated_image_card_html(
    message_id = "msg42",
    img_src = "http://img.local/x.png",
    description = "Mavi gökyüzü"
  )

  expect_true(is.character(html))
  expect_true(grepl('data-message-id="msg42"', html, fixed = TRUE))
  expect_true(grepl("http://img.local/x.png", html, fixed = TRUE))
  expect_true(grepl("image-watermark", html, fixed = TRUE))
  expect_true(grepl("MERGEN Bilge", html, fixed = TRUE))
  # İndir / Kopyala / Yazdır butonları kart sözleşmesinin parçasıdır.
  expect_true(grepl("downloadGeneratedImage", html, fixed = TRUE))
  expect_true(grepl("copyGeneratedImage", html, fixed = TRUE))
  expect_true(grepl("printGeneratedImage", html, fixed = TRUE))
  expect_true(grepl("Mavi gökyüzü", html, fixed = TRUE))
})

test_that("mergen_generated_image_card_html message_id'yi XSS'e karşı kaçışlar", {
  html <- .img_card_env$mergen_generated_image_card_html(
    message_id = 'm"><script>alert(1)</script>',
    img_src = "http://x/y.png",
    description = NULL
  )

  expect_false(grepl("<script>", html, fixed = TRUE))
  expect_true(grepl("&lt;script&gt;", html, fixed = TRUE))
})

test_that("mergen_generated_image_card_html description'ı XSS'e karşı kaçışlar", {
  html <- .img_card_env$mergen_generated_image_card_html(
    message_id = "m",
    img_src = "http://x/y.png",
    description = "<img src=x onerror=alert(1)>"
  )

  expect_false(grepl("onerror=alert(1)>", html, fixed = TRUE))
  expect_true(grepl("&lt;img", html, fixed = TRUE))
})

test_that("mergen_generated_image_card_html boş/NULL açıklamada açıklama bloğu eklemez", {
  html_null <- .img_card_env$mergen_generated_image_card_html(
    message_id = "m", img_src = "u", description = NULL
  )
  html_empty <- .img_card_env$mergen_generated_image_card_html(
    message_id = "m", img_src = "u", description = ""
  )

  expect_false(grepl("image-description", html_null, fixed = TRUE))
  expect_false(grepl("image-description", html_empty, fixed = TRUE))
})

test_that("mergen_generated_image_card_html img_src'yi olduğu gibi src içine yerleştirir", {
  marker <- "data:image/png;base64,AAAA"
  html <- .img_card_env$mergen_generated_image_card_html(
    message_id = "m", img_src = marker, description = NULL
  )
  expect_true(grepl(sprintf('src="%s"', marker), html, fixed = TRUE))
})

# -----------------------------------------------------------------------------
# Çoğaltma karşıtı koruma: kart işaretlemesi tek kaynakta kalmalı
# -----------------------------------------------------------------------------

test_that("oluşturulan görsel kart butonları yalnızca kanonik yardımcıda tanımlanır", {
  # image-action-btn-modern buton sınıfı yalnızca tam kart işaretlemesinde geçer.
  markdown_safety_txt <- .read_repo_text_img_card("R/helpers_markdown_safety.R")
  image_module_txt <- .read_repo_text_img_card("R/module_image_generation.R")
  chat_format_txt <- .read_repo_text_img_card("R/helpers_chat_message_formatting.R")

  expect_true(
    grepl("image-action-btn-modern", markdown_safety_txt, fixed = TRUE),
    info = "Kanonik kart yardımcısı helpers_markdown_safety.R içinde kart butonlarını içermelidir."
  )

  expect_false(
    grepl("image-action-btn-modern", image_module_txt, fixed = TRUE),
    info = "module_image_generation.R kart işaretlemesini tekrar inline etmemeli; kanonik yardımcıyı kullanmalı."
  )

  expect_false(
    grepl("image-action-btn-modern", chat_format_txt, fixed = TRUE),
    info = "helpers_chat_message_formatting.R kart işaretlemesini tekrar inline etmemeli; kanonik yardımcıyı kullanmalı."
  )
})

test_that("görsel kart tüketicileri kanonik yardımcıyı çağırır", {
  image_module_txt <- .read_repo_text_img_card("R/module_image_generation.R")
  chat_format_txt <- .read_repo_text_img_card("R/helpers_chat_message_formatting.R")

  expect_true(
    grepl("mergen_generated_image_card_html", image_module_txt, fixed = TRUE),
    info = "module_image_generation.R kanonik kart yardımcısını çağırmalıdır."
  )

  expect_true(
    grepl("mergen_generated_image_card_html", chat_format_txt, fixed = TRUE),
    info = "helpers_chat_message_formatting.R kanonik kart yardımcısını çağırmalıdır."
  )
})

test_that("kanonik kart yardımcısı helpers_markdown_safety.R içinde tanımlanır", {
  markdown_safety_txt <- .read_repo_text_img_card("R/helpers_markdown_safety.R")

  expect_true(
    grepl("mergen_generated_image_card_html <- function", markdown_safety_txt, fixed = TRUE),
    info = paste(
      "Kanonik görsel kart yardımcısı helpers_markdown_safety.R içinde kalmalıdır",
      "(helpers_chat_message_formatting.R'den önce yüklenir)."
    )
  )
})

test_that("printGeneratedImage yazdırma sekmesini erken kapatmaz", {
  image_tools_js <- .read_repo_text_img_card("www/js/image_tools.js")

  expect_true(grepl("window.printGeneratedImage", image_tools_js, fixed = TRUE))
  expect_true(grepl("printWindow.print()", image_tools_js, fixed = TRUE))
  expect_false(
    grepl("window.close()", image_tools_js, fixed = TRUE) ||
      grepl("printWindow.close()", image_tools_js, fixed = TRUE),
    info = "Yazdır penceresini otomatik kapatmak tarayıcıda anlık flicker'a ve iptal edilen yazdırmaya yol açabilir."
  )
})
