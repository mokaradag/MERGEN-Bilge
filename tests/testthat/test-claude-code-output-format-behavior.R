# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-output-format-behavior.R
# Açıklama: R/helpers_claude_code.R format_claude_code_output (Markdown->HTML)
#           ve get_thinking_message (persona düşünme mesajı seçimi) davranışsal
#           testleri. claude_code_thinking_messages testte stub'lanır; commonmark
#           ile çevrimdışı çalışır.
# ==============================================================================

testthat::local_edition(3)

.cco_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code.R"),
  encoding = "UTF-8",
  local = .cco_env
)

# Persona düşünme mesajlarını deterministik stub ile sağla.
.cco_env$claude_code_thinking_messages <- list(
  genel = c("Düşünüyorum...", "Analiz ediyorum..."),
  emre  = c("Emre kod akışını inceliyor")
)

# -----------------------------------------------------------------------------
# format_claude_code_output
# -----------------------------------------------------------------------------

test_that("format_claude_code_output boş/NULL girdide boş string döndürür", {
  expect_equal(.cco_env$format_claude_code_output(""), "")
  expect_equal(.cco_env$format_claude_code_output(NULL), "")
})

test_that("format_claude_code_output Markdown'ı HTML'e çevirir ve Türkçe'yi korur", {
  skip_if_not_installed("commonmark")

  html <- .cco_env$format_claude_code_output("# Başlık\n\nMetin **kalın** ve `kod`")
  expect_true(grepl("<h1", html, fixed = TRUE))
  expect_true(grepl("Başlık", html, fixed = TRUE))
  expect_true(grepl("<strong>kalın</strong>", html, fixed = TRUE))
  expect_true(grepl("<code>kod</code>", html, fixed = TRUE))
})

test_that("format_claude_code_output güvenli dönüştürücüde GFM uzantılarını korur", {
  skip_if_not_installed("commonmark")

  # Üretimde `render_safe_markdown_html()` yüklüdür; güvenli dal bu ortamda
  # kurulur. Varsayılan uzantı kümesi yalnızca strikethrough/table olduğu için
  # autolink ve tasklist AÇIKÇA verilmezse bağlantılar ve görev listeleri düz
  # metne düşüyordu (eski doğrudan çağrı `extensions = TRUE` idi).
  env <- new.env(parent = globalenv())
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_markdown_safety.R"),
    encoding = "UTF-8", local = env
  )
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code.R"),
    encoding = "UTF-8", local = env
  )

  html <- env$format_claude_code_output(
    "https://ornek.test/rapor

- [x] tamamlandı
- [ ] bekliyor

~~eski~~"
  )

  expect_true(grepl("<a href=\"https://ornek.test/rapor\"", html, fixed = TRUE))
  expect_true(grepl("type=\"checkbox\"", html, fixed = TRUE))
  expect_true(grepl("<del>eski</del>", html, fixed = TRUE))

  # Güvenlik sınırı korunur: ham HTML hâlâ kaçırılır.
  kacis <- env$format_claude_code_output("<script>alert(1)</script>")
  expect_false(grepl("<script>", kacis, fixed = TRUE))
})

# -----------------------------------------------------------------------------
# get_thinking_message
# -----------------------------------------------------------------------------

test_that("get_thinking_message persona + genel mesajlarının birleşiminden tek mesaj seçer", {
  birlesim <- c("Düşünüyorum...", "Analiz ediyorum...", "Emre kod akışını inceliyor")
  for (i in seq_len(10)) {
    msg <- .cco_env$get_thinking_message("emre")
    expect_length(msg, 1)
    expect_true(msg %in% birlesim)
  }
})

test_that("get_thinking_message eski persona kimliğini normalleştirir (mergen -> emre)", {
  birlesim <- c("Düşünüyorum...", "Analiz ediyorum...", "Emre kod akışını inceliyor")
  msg <- .cco_env$get_thinking_message("mergen")
  expect_true(msg %in% birlesim)
})

test_that("get_thinking_message persona mesajı olmayan kimlikte yalnızca genel mesajları kullanır", {
  genel <- c("Düşünüyorum...", "Analiz ediyorum...")
  for (i in seq_len(8)) {
    msg <- .cco_env$get_thinking_message("can")  # stub'da 'can' yok -> sadece genel
    expect_true(msg %in% genel)
  }
})
