# Ortak oturum açık tema kontrastı ve modal yerleşimi sözleşmesi.

.oo_light_css_oku <- function(yol) {
  baytlar <- readBin(yol, what = "raw", n = file.info(yol)$size)
  iconv(rawToChar(baytlar), from = "UTF-8", to = "UTF-8", sub = "byte")
}

test_that("ortak oturum açık tema kontrastı ve modal yerleşimi korunur", {
  repo_root <- resolve_repo_root_for_tests()
  css <- .oo_light_css_oku(file.path(repo_root, "www", "css", "ortak_oturumlar_light.css"))

  expect_true(grepl(".oo-hub-filtreler .radio-inline:has", css, fixed = TRUE))
  expect_true(grepl(".oo-davet-paneli .radio-inline:has", css, fixed = TRUE))
  expect_true(grepl("background: #1d4ed8 !important", css, fixed = TRUE))
  expect_true(grepl("color: #ffffff !important", css, fixed = TRUE))

  expect_true(grepl(".modal-dialog:has(.oo-yeni-oturum-modal)", css, fixed = TRUE))
  expect_true(grepl("max-width: 504px", css, fixed = TRUE))
  expect_true(grepl("grid-template-columns: 1fr", css, fixed = TRUE))
  expect_true(grepl("white-space: nowrap", css, fixed = TRUE))

  expect_true(grepl(".oo-btn-oturum-arsiv", css, fixed = TRUE))
  expect_true(grepl("border-color: #94a3b8 !important", css, fixed = TRUE))
  expect_true(grepl("color: #1e293b !important", css, fixed = TRUE))

  expect_true(grepl(".oo-secici .btn svg path", css, fixed = TRUE))
  expect_true(grepl("background: #e2e8f0 !important", css, fixed = TRUE))
  expect_true(grepl("visibility: visible !important", css, fixed = TRUE))

  expect_true(grepl(".destek-hakkinda-hero .destek-hakkinda-title", css, fixed = TRUE))
  expect_true(grepl("-webkit-text-fill-color: #ffffff", css, fixed = TRUE))
})