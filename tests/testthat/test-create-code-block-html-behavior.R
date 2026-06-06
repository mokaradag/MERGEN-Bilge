# ==============================================================================
# Dosya Yolu: tests/testthat/test-create-code-block-html-behavior.R
# Açıklama: create_code_block_html() davranışsal testleri. Kod bloğu HTML
#           iskeleti, dil etiketi, data-lang özniteliği ve kodun HTML kaçışı
#           (XSS koruması) doğrulanır. Açık dil verildiğinde detect_language
#           çağrılmaz. DB/LLM/tarayıcı gerekmez.
# ==============================================================================

# İzole çalıştırma için: create_code_block_html() shiny::HTML'i niteliksiz çağırır.
# Tam suite'te shiny başka testlerce attach edilir; tek başına koşumda gerekir.
suppressMessages(library(shiny))

.create_code_block_source_once <- function() {
  if (exists("create_code_block_html", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("LANG_MAP", envir = globalenv(), inherits = TRUE)) {
    return(invisible(TRUE))
  }

  # create_code_block_html LANG_MAP'e (helpers_language) bağımlıdır.
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_language.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_messaging.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

testthat::test_that("create_code_block_html iskelet, dil etiketi ve data-lang üretir", {
  .create_code_block_source_once()
  testthat::skip_if_not_installed("stringr")
  testthat::skip_if_not_installed("htmltools")

  out <- as.character(create_code_block_html("x <- 1", language = "r"))

  testthat::expect_true(grepl("code-container", out, fixed = TRUE))
  testthat::expect_true(grepl("data-lang=\"r\"", out, fixed = TRUE))
  # LANG_MAP[["r"]] = "R" görünen dil etiketi.
  testthat::expect_true(grepl(">R</span>", out, fixed = TRUE))
  # Kod içeriği HTML kaçışlı olmalı: "<" -> "&lt;".
  testthat::expect_true(grepl("x &lt;- 1", out, fixed = TRUE))
})

testthat::test_that("create_code_block_html kod içeriğini kaçışlar (XSS koruması)", {
  .create_code_block_source_once()
  testthat::skip_if_not_installed("stringr")
  testthat::skip_if_not_installed("htmltools")

  out <- as.character(create_code_block_html("<script>alert(1)</script>", language = "text"))

  # Ham <script> etiketi çıktıda aktif olmamalı.
  testthat::expect_false(grepl("<script", out, ignore.case = TRUE))
  # Kaçışlı hali bulunmalı.
  testthat::expect_true(grepl("&lt;script&gt;", out, fixed = TRUE))
  testthat::expect_true(grepl("data-lang=\"text\"", out, fixed = TRUE))
})
