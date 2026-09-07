# ==============================================================================
# Dosya Yolu: tests/testthat/test-messaging-render-behavior.R
# Açıklama: R/helpers_messaging.R mesaj/HTML işleme yardımcılarının davranışsal
#           testleri. parse_ai_response_robustly (kod çiti var/yok) ve
#           process_message_content (kullanıcı/ai, boş içerik) doğrulanır.
#           Ham HTML güvenlik sınırı (script kaçışı) da kontrol edilir.
#           Gerçek LLM/DB gerektirmez; commonmark/stringr ile çevrimdışı çalışır.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))  # create_code_block_html HTML() kullanır
}

.msg_env <- new.env(parent = globalenv())
# Bağımlılık sırası: markdown güvenliği -> dil/kod yardımcıları -> mesaj işleme.
for (f in c("helpers_markdown_safety.R", "helpers_language.R", "helpers_messaging.R")) {
  source(file.path(resolve_repo_root_for_tests(), "R", f), encoding = "UTF-8", local = .msg_env)
}

.sessiz <- function(expr) {
  invisible(utils::capture.output(res <- expr))
  res
}

# -----------------------------------------------------------------------------
# parse_ai_response_robustly
# -----------------------------------------------------------------------------

test_that("parse_ai_response_robustly kod çiti yokken markdown'ı HTML'e çevirir (has_code FALSE)", {
  skip_if_not_installed("commonmark")

  sonuc <- .msg_env$parse_ai_response_robustly("Merhaba **dünya**")
  expect_false(isTRUE(sonuc$has_code))
  expect_true(grepl("<strong>dünya</strong>", sonuc$html, fixed = TRUE))
})

test_that("parse_ai_response_robustly tek kod çiti olduğunda kod bloğu üretir (has_code TRUE)", {
  skip_if_not_installed("commonmark")
  skip_if_not_installed("shiny")

  sonuc <- .msg_env$parse_ai_response_robustly("Önce metin\n```r\nx <- 1\n```\nSonra metin")
  expect_true(isTRUE(sonuc$has_code))
  expect_true(nchar(sonuc$html) > 0)
  # Kod içeriği (değişken adı) çıktıda yer almalı.
  expect_true(grepl("x", sonuc$html, fixed = TRUE))
})

test_that("parse_ai_response_robustly etiketsiz kod bloğunda açılış çitini bırakmaz", {
  skip_if_not_installed("commonmark")
  skip_if_not_installed("shiny")

  # Dil etiketi olmayan blokta `language` "auto" olur; bu bir DİL ADI DEĞİLDİR.
  # "```auto" deseni eşleşmediği için açılış çiti kod içeriğinde kalıyor ve kod
  # bloğunun ilk satırında ``` görünüyordu (kopyalanan kod bozuk oluyordu).
  sonuc <- .msg_env$parse_ai_response_robustly("Önce metin\n```\nprint(1)\nx <- 2\n```\nSonra")

  expect_true(isTRUE(sonuc$has_code))
  expect_true(grepl("print(1)", sonuc$html, fixed = TRUE))
  # Kod gövdesinde artık çit satırı kalmamalı. Ters tırnak HTML kaçışına
  # girmediği için kaçırılmış biçim de ayrıca denetlenir.
  expect_false(grepl("&#96;", sonuc$html, fixed = TRUE))
  expect_false(grepl("```", sonuc$html, fixed = TRUE))
})

test_that("parse_ai_response_robustly etiketli kod bloğunun dilini korur", {
  skip_if_not_installed("commonmark")
  skip_if_not_installed("shiny")

  sonuc <- .msg_env$parse_ai_response_robustly("```python\nx = 1\n```")
  expect_true(isTRUE(sonuc$has_code))
  expect_true(grepl("x = 1", sonuc$html, fixed = TRUE))
  expect_false(grepl("```", sonuc$html, fixed = TRUE))
  # Test adı DİL korumasını iddia eder; dil işareti gerçekten doğrulanmalıdır.
  # Aksi hâlde parse_ai_response_robustly etiketi tamamen düşürse bile geçerdi.
  expect_true(grepl("data-lang=\"python\"", sonuc$html, fixed = TRUE))
})

test_that("parse_ai_response_robustly literal \\n dizilerini gerçek satır sonuna çevirir", {
  skip_if_not_installed("commonmark")

  # Girdi 'satir1\nsatir2' (literal ters bölü + n) -> markdown öncesi gerçek satıra döner.
  sonuc <- .msg_env$parse_ai_response_robustly("satir1\\nsatir2")
  expect_false(isTRUE(sonuc$has_code))
  expect_true(grepl("satir1", sonuc$html, fixed = TRUE))
  expect_true(grepl("satir2", sonuc$html, fixed = TRUE))
})

test_that("parse_ai_response_robustly ham script etiketini aktif HTML olarak bırakmaz (güvenlik)", {
  skip_if_not_installed("commonmark")

  sonuc <- .msg_env$parse_ai_response_robustly("Zararlı: <script>alert(1)</script>")
  expect_false(grepl("<script>alert(1)</script>", sonuc$html, fixed = TRUE))
})

# -----------------------------------------------------------------------------
# process_message_content
# -----------------------------------------------------------------------------

test_that("process_message_content kullanıcı düz metnini markdown HTML olarak işler", {
  skip_if_not_installed("commonmark")

  sonuc <- .sessiz(.msg_env$process_message_content("merhaba **kalın**", "user"))
  expect_false(isTRUE(sonuc$has_code))
  expect_true(grepl("merhaba", sonuc$html, fixed = TRUE))
  expect_true(grepl("<strong>kalın</strong>", sonuc$html, fixed = TRUE))
})

test_that("process_message_content ai mesajında markdown vurgusunu render eder", {
  skip_if_not_installed("commonmark")

  sonuc <- .sessiz(.msg_env$process_message_content("Sonuç: **önemli**", "ai"))
  expect_false(isTRUE(sonuc$has_code))
  expect_true(grepl("<strong>önemli</strong>", sonuc$html, fixed = TRUE))
})

test_that("process_message_content uzunluğu sıfır içeriği güvenle boş stringe indirger", {
  skip_if_not_installed("commonmark")

  sonuc <- .sessiz(.msg_env$process_message_content(character(0), "ai"))
  expect_false(isTRUE(sonuc$has_code))
  expect_true(is.character(sonuc$html))
})
