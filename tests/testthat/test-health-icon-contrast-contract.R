# ==============================================================================
# Dosya Yolu: tests/testthat/test-health-icon-contrast-contract.R
# Açıklama: Sistem Durumu metrik kartı ikon çiplerinin kontrast sözleşmesi.
#           Her durum için glif rengi, çip zemininin (durum tonu kart zemini
#           üzerinde) karşısında WCAG metin-dışı 3:1 eşiğini hem açık hem koyu
#           temada sağlamalıdır. Gri zeminde koyu glif ve doygun yeşil/amber
#           zeminde beyaz glif bu eşiğin altında kalıyordu.
# ==============================================================================

.hic_css <- function() {
  yol <- file.path(resolve_repo_root_for_tests(), "www", "css", "health_dashboard.css")
  metin <- rawToChar(readBin(yol, what = "raw", n = file.info(yol)$size))
  Encoding(metin) <- "UTF-8"
  gsub("/\\*[\\s\\S]*?\\*/", "", gsub("\r\n?", "\n", metin), perl = TRUE)
}

.hic_rule <- function(css, selector) {
  kacis <- gsub("([.\\[\\]\"=()])", "\\\\\\1", selector, perl = TRUE)
  m <- regmatches(css, regexpr(paste0("(?m)^\\s*", kacis, "\\s*\\{([^}]*)\\}"), css, perl = TRUE))
  if (!length(m)) return(NA_character_)
  sub("^[^{]*\\{", "", sub("\\}$", "", m))
}

.hic_hex <- function(govde, ozellik = "color") {
  m <- regmatches(govde, regexpr(paste0("(^|[;\\s])", ozellik, ":\\s*#[0-9a-fA-F]{6}"), govde, perl = TRUE))
  if (!length(m)) return(NULL)
  hex <- sub(".*#", "", m)
  strtoi(substring(hex, c(1, 3, 5), c(2, 4, 6)), 16L)
}

.hic_tint <- function(govde) {
  m <- regmatches(govde, regexpr("--hm-tint:\\s*[0-9]+,\\s*[0-9]+,\\s*[0-9]+", govde, perl = TRUE))
  if (!length(m)) return(NULL)
  as.numeric(strsplit(sub("--hm-tint:\\s*", "", m), ",\\s*")[[1]])
}

.hic_contrast <- function(a, b) {
  lum <- function(c) {
    v <- c / 255
    v <- ifelse(v <= 0.03928, v / 12.92, ((v + 0.055) / 1.055)^2.4)
    sum(c(0.2126, 0.7152, 0.0722) * v)
  }
  l <- sort(c(lum(a), lum(b)), decreasing = TRUE)
  (l[1] + 0.05) / (l[2] + 0.05)
}

.hic_alpha <- function(govde) {
  m <- regmatches(govde, regexpr("background:\\s*rgba\\(var\\(--hm-tint\\),\\s*[0-9.]+\\)", govde, perl = TRUE))
  as.numeric(sub(".*,\\s*([0-9.]+)\\)$", "\\1", m))
}

test_that("metrik kartı ikon çipleri iki temada da 3:1 kontrastı sağlar", {
  css <- .hic_css()
  taban <- .hic_rule(css, ".health-metric-icon")
  expect_false(is.na(taban))
  isik_taban <- .hic_rule(css, 'html[data-theme="light"] .health-metric-tile .health-metric-icon')
  expect_false(is.na(isik_taban))
  koyu_alfa <- .hic_alpha(taban)
  isik_alfa <- .hic_alpha(isik_taban)
  expect_length(koyu_alfa, 1L)
  expect_length(isik_alfa, 1L)

  koyu_kart <- c(26, 26, 26)     # var(--background-light, #1a1a1a)
  isik_kart <- c(255, 255, 255)
  karistir <- function(ton, alfa, zemin) ton * alfa + zemin * (1 - alfa)

  for (durum in c("ok", "warning", "critical", "unknown", "not_configured")) {
    koyu <- .hic_rule(css, paste0(".health-metric-tile.health-status-", durum, " .health-metric-icon"))
    isik <- .hic_rule(css, paste0('html[data-theme="light"] .health-metric-tile.health-status-', durum,
                                  " .health-metric-icon"))
    expect_false(is.na(koyu), info = durum)
    expect_false(is.na(isik), info = durum)
    ton <- .hic_tint(koyu)
    expect_length(ton, 3L)

    koyu_oran <- .hic_contrast(.hic_hex(koyu), karistir(ton, koyu_alfa, koyu_kart))
    isik_oran <- .hic_contrast(.hic_hex(isik), karistir(ton, isik_alfa, isik_kart))
    expect_gte(koyu_oran, 3, label = paste("koyu tema", durum))
    expect_gte(isik_oran, 3, label = paste("açık tema", durum))
  }
})

test_that("nötr durum çipleri gri gradyana dönmez", {
  css <- .hic_css()
  expect_false(grepl("health-metric-icon\\s*\\{[^}]*#64748b 0%, #475569", css, perl = TRUE))
})
