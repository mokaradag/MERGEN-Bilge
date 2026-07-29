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

  expect_true(grepl("button.oo-btn-oturum-arsiv", css, fixed = TRUE))
  expect_true(grepl("background: #e2e8f0 !important", css, fixed = TRUE))
  expect_true(grepl("border: 1px solid #64748b !important", css, fixed = TRUE))
  expect_true(grepl("-webkit-text-fill-color: #0f172a", css, fixed = TRUE))

  secici_baslangic <- regexpr("/\\* shinyWidgets tetikleri", css)
  secici_bitis <- regexpr("/\\* Hakkında başlığı", css)
  expect_gt(secici_baslangic, 0)
  expect_gt(secici_bitis, secici_baslangic)
  secici_css <- substr(css, secici_baslangic, secici_bitis - 1L)

  expect_true(grepl(".oo-secici .action-button", secici_css, fixed = TRUE))
  expect_true(grepl(".oo-secici button.bttn", secici_css, fixed = TRUE))
  expect_true(grepl("background: transparent !important", secici_css, fixed = TRUE))
  expect_true(grepl("border: none !important", secici_css, fixed = TRUE))
  expect_true(grepl("box-shadow: none !important", secici_css, fixed = TRUE))
  expect_false(grepl("background: #e2e8f0 !important", secici_css, fixed = TRUE))
  expect_false(grepl("border: 1px solid #64748b !important", secici_css, fixed = TRUE))
  expect_true(grepl(".fa-microchip::before", secici_css, fixed = TRUE))
  expect_true(grepl(".fa-masks-theater::before", secici_css, fixed = TRUE))
  expect_true(grepl(".fa-toolbox::before", secici_css, fixed = TRUE))
  expect_true(grepl("visibility: visible !important", secici_css, fixed = TRUE))

  expect_true(grepl(".destek-hakkinda-hero .destek-hakkinda-title", css, fixed = TRUE))
  expect_true(grepl("-webkit-text-fill-color: #ffffff", css, fixed = TRUE))
})
