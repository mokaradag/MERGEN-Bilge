# ==============================================================================
# Dosya Yolu: tests/testthat/test-app-loading-brand-contract.R
# Açıklama: Açılış yükleme ekranı "MERGEN Bilge" marka başlığı sözleşmesi.
#   Kullanıcı şikayetleri:
#     - "Bilge" yazısının "g" harfi alttan kırpılıyor.
#     - "MERGEN Bilge" yazısı küçük; daha belirgin olmalı.
#     - Harflerin arası geniş; sıkılaştırılmalı.
#     - Ayraç (divider) renkli bir ribbon animasyonu olmalı.
#
# Bu test heavy Shiny runtime istemez; yalnızca CSS dosyasını tarar.
# ==============================================================================

.repo_root_app_loading_brand <- function() {
  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "R")) &&
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.read_repo_text_app_loading_brand <- function(rel_path) {
  repo_root <- .repo_root_app_loading_brand()
  full_path <- file.path(repo_root, rel_path)
  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) return("")
  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )
  if (is.na(txt)) txt <- ""
  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

test_that("app_loading.css alo-wordmark font boyutu eski 33px'ten buyutulmustur", {
  txt <- .read_repo_text_app_loading_brand("www/css/app_loading.css")
  expect_true(nzchar(txt), info = "www/css/app_loading.css okunamadi.")

  # 33px atandiysa kucuk; yeni baseline en az 36px olmalidir.
  expect_false(
    grepl("\\.alo-wordmark\\b[^}]*font-size:\\s*33px", txt, perl = TRUE),
    info = "Yukleme ekrani marka basligi 33px ile kucuk kalmamalidir."
  )

  expect_true(
    grepl("\\.alo-wordmark\\b[^}]*font-size:\\s*(3[6-9]|[4-9][0-9])px", txt, perl = TRUE),
    info = paste(
      "Yukleme ekrani marka basligi (.alo-wordmark) font-size en az 36px",
      "olmalidir; kullanici kararli daha buyuk marka istedi."
    )
  )
})

test_that("app_loading.css alo-wordmark descender'larin kirpilmamasi icin yer birakir", {
  txt <- .read_repo_text_app_loading_brand("www/css/app_loading.css")
  expect_true(nzchar(txt), info = "www/css/app_loading.css okunamadi.")

  # padding-bottom veya line-height > 1.1 araciligiyla "g" alt kuyrugu
  # kirpilmamali.
  has_padding_bottom <- grepl(
    "\\.alo-wordmark\\b[^}]*padding-bottom:\\s*[1-9]",
    txt, perl = TRUE
  )
  has_line_height <- grepl(
    "\\.alo-wordmark\\b[^}]*line-height:\\s*1\\.(1[1-9]|[2-9])",
    txt, perl = TRUE
  )

  expect_true(
    has_padding_bottom || has_line_height,
    info = paste(
      "Yukleme ekrani marka basligi alttan kirpilmamasi icin padding-bottom",
      "veya line-height >= 1.11 kullanmalidir."
    )
  )
})

test_that("app_loading.css alo-wordmark line-height: 1 keskin degerini kullanmaz", {
  txt <- .read_repo_text_app_loading_brand("www/css/app_loading.css")
  expect_true(nzchar(txt), info = "www/css/app_loading.css okunamadi.")

  # line-height: 1 descender'larin kirpilmasinin temel sebebidir.
  expect_false(
    grepl("\\.alo-wordmark\\b[^}]*line-height:\\s*1\\b\\s*;", txt, perl = TRUE),
    info = paste(
      "alo-wordmark line-height: 1 degeri 'g' gibi descender harflerin",
      "alttan kirpilmasina neden olur; en az 1.1 kullanilmalidir."
    )
  )
})

test_that("app_loading.css renkli ribbon animasyonu (sheen) tanimlidir", {
  txt <- .read_repo_text_app_loading_brand("www/css/app_loading.css")
  expect_true(nzchar(txt), info = "www/css/app_loading.css okunamadi.")

  # Sheen animasyonu — ayraç şeridi sürekli renkli akış efekti.
  expect_true(
    grepl("aloDividerSheen", txt, fixed = TRUE),
    info = paste(
      "Yukleme ekrani ayraciinda surekli renkli akan (sheen) animasyon",
      "tanimlanmalidir — kullanici istegi: 'colorful ribbon animated'."
    )
  )

  expect_true(
    grepl("@keyframes\\s+aloDividerSheen", txt, perl = TRUE),
    info = "aloDividerSheen icin @keyframes tanimi bulunmalidir."
  )

  # Animasyon background-position uzerinden surmelidir
  expect_true(
    grepl("background-position", txt, fixed = TRUE),
    info = "Ribbon animasyonu background-position uzerinden akmalidir."
  )
})

test_that("sidebar_user_panel.css uzun tam ad icin 2 satira wrap kullanir (ellipsis yerine)", {
  txt <- .read_repo_text_app_loading_brand("www/css/sidebar_user_panel.css")
  expect_true(nzchar(txt), info = "www/css/sidebar_user_panel.css okunamadi.")

  # white-space: nowrap kaldirilmis olmali (eski regresyon: tek satir ellipsis).
  expect_false(
    grepl("\\.mb-sidebar-user-name\\b[^}]*white-space:\\s*nowrap", txt, perl = TRUE),
    info = "Uzun tam ad nowrap ile tek satira sikistirilmamalidir."
  )

  # line-clamp: 2 kullanimi gereklidir.
  expect_true(
    grepl("\\.mb-sidebar-user-name\\b[^}]*-webkit-line-clamp:\\s*2", txt, perl = TRUE),
    info = paste(
      "Uzun tam ad 2 satira wrap edilmelidir (line-clamp: 2);",
      "Eski 'MEHMET ONUR KARA...' ellipsis goruntusu kabul edilmez."
    )
  )
})
