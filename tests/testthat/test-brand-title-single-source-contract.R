# ==============================================================================
# Dosya Yolu: tests/testthat/test-brand-title-single-source-contract.R
# Açıklama: "MERGEN Bilge" marka tipografisi için TEK doğru görsel kaynak
#           olarak www/css/brand_title.css'in korunduğunu doğrular.
#
# Korunan sözleşmeler:
#   1. www/css/brand_title.css var olmali ve manifest tarafindan yuklenmelidir.
#   2. Tek-kaynak mekanizmasi PAYLASILAN TOKENLARDIR: --mergen-brand-* token
#      ailesi :root'ta (koyu varsayilan) ve html[data-theme="light"]
#      override'inda tanimlanir.
#   3. Uc canli marka yuzeyi — navbar (.brand-text), acilis ekrani
#      (.alo-wordmark) ve deep-space (.deep-space-title) — hizalamayi bu
#      tokenlari TUKETEREK saglar (var(--mergen-brand-font-stack)).
#
# Not: Eski testin sabitledigi .mergen-brand-title* siniflari DOM'da hicbir
# zaman var olmamis hayalet bir paralel API idi ve kaldirildi. Sozlesme,
# hizalamanin gercek mekanizmasina (token tuketimi) yeniden capalandi.
# ==============================================================================

.find_repo_root_brand_title <- function() {
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

.read_brand_title_file <- function(rel_path) {
  repo_root <- .find_repo_root_brand_title()
  full_path <- file.path(repo_root, rel_path)
  if (!file.exists(full_path)) return("")

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    # BOŞ DOSYA DA VACUOUS GEÇİRİR: bu dosyalardaki taramaların çoğu
    # `expect_false(grepl(...))` biçimindedir ve boş dize hepsini karşılar.
    stop(sprintf("Kaynak dosya BOŞ ya da okunamıyor: %s", full_path), call. = FALSE)
  }

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

test_that("www/css/brand_title.css dosyasi mevcuttur", {
  repo_root <- .find_repo_root_brand_title()
  expect_true(file.exists(file.path(repo_root, "www", "css", "brand_title.css")),
              info = "Brand title CSS dosyasi olmalidir.")
})

test_that("brand_title.css ortak token tanimlarini icerir", {
  txt <- .read_brand_title_file("www/css/brand_title.css")
  expect_true(nzchar(txt), info = "www/css/brand_title.css okunamadi.")

  expect_true(
    grepl("--mergen-brand-font-stack", txt, fixed = TRUE, useBytes = TRUE),
    info = "Brand title CSS, --mergen-brand-font-stack tokenini tanimlamalidir."
  )

  expect_true(
    grepl("--mergen-brand-primary-weight", txt, fixed = TRUE, useBytes = TRUE),
    info = "--mergen-brand-primary-weight tokeni tanimlanmalidir."
  )

  expect_true(
    grepl("--mergen-brand-accent-gradient", txt, fixed = TRUE, useBytes = TRUE),
    info = "--mergen-brand-accent-gradient tokeni tanimlanmalidir."
  )

  # Hayalet paralel sinif API'si geri gelmemelidir; hizalama tokenlarla yapilir.
  expect_false(
    grepl(".mergen-brand-title", txt, fixed = TRUE, useBytes = TRUE),
    info = paste(
      "Hayalet .mergen-brand-title sinif ailesi geri eklenmemelidir;",
      "yeni marka yuzeyi eklerken --mergen-brand-* tokenlarini tuketin."
    )
  )
})

test_that("uc canli marka yuzeyi paylasilan font-stack tokenini tuketir", {
  txt <- .read_brand_title_file("www/css/brand_title.css")
  expect_true(nzchar(txt), info = "www/css/brand_title.css okunamadi.")

  # Navbar marka yazisi (.brand-text)
  expect_true(
    grepl(".brand-text", txt, fixed = TRUE, useBytes = TRUE),
    info = "Brand title CSS navbar .brand-text icin hizalama kurallari icermeli."
  )

  # Acilis ekrani wordmark (.alo-wordmark)
  expect_true(
    grepl(".alo-wordmark", txt, fixed = TRUE, useBytes = TRUE),
    info = "Brand title CSS acilis ekrani .alo-wordmark icin hizalama kurallari icermeli."
  )

  # Deep-space marka yazisi (.deep-space-title)
  expect_true(
    grepl(".deep-space-title", txt, fixed = TRUE, useBytes = TRUE),
    info = "Brand title CSS deep-space .deep-space-title icin hizalama kurallari icermeli."
  )

  # Hizalamanin gercek kaniti: uc yuzey de ayni font-stack tokenini tuketir.
  token_uses <- gregexpr("var(--mergen-brand-font-stack)", txt, fixed = TRUE)[[1]]
  token_use_count <- if (identical(token_uses[1], -1L)) 0L else length(token_uses)

  expect_true(
    token_use_count >= 3L,
    info = sprintf(
      "Uc canli marka yuzeyi var(--mergen-brand-font-stack) tuketmelidir (bulunan: %d).",
      token_use_count
    )
  )
})

test_that("config_ui_assets.R brand_title.css'i manifeste dahil eder", {
  txt <- .read_brand_title_file("R/config_ui_assets.R")
  expect_true(nzchar(txt), info = "R/config_ui_assets.R okunamadi.")

  expect_true(
    grepl('"css/brand_title.css"', txt, fixed = TRUE, useBytes = TRUE),
    info = paste(
      "config_ui_assets.R css/brand_title.css'i UI asset manifestine",
      "dahil etmelidir. Aksi halde marka tipografisi tek kaynaktan",
      "yuklenmez ve uc yer arasinda gorsel tutarsizlik olusur."
    )
  )
})

test_that("brand_title.css hem koyu hem acik tema icin renk tanimlar", {
  txt <- .read_brand_title_file("www/css/brand_title.css")
  expect_true(nzchar(txt), info = "www/css/brand_title.css okunamadi.")

  # :root altinda koyu tema (varsayilan) renk tokenlari
  expect_true(
    grepl("--mergen-brand-color-primary", txt, fixed = TRUE, useBytes = TRUE),
    info = "Brand title --mergen-brand-color-primary tokeni tanimlanmalidir."
  )

  # Açik tema icin renk override
  expect_true(
    grepl('html[data-theme="light"]', txt, fixed = TRUE, useBytes = TRUE),
    info = "Brand title CSS acik tema icin override icermelidir."
  )
})

test_that("brand_title.css'de CDN/disardan asset yok (offline kontrati)", {
  txt <- .read_brand_title_file("www/css/brand_title.css")
  expect_true(nzchar(txt), info = "www/css/brand_title.css okunamadi.")

  forbidden_url_patterns <- c(
    "http://",
    "https://",
    "//cdn.",
    "googleapis.com",
    "googlefonts.com",
    "fonts.googleapis"
  )

  for (pattern in forbidden_url_patterns) {
    expect_false(
      grepl(pattern, txt, fixed = TRUE, useBytes = TRUE),
      info = sprintf(
        "Brand title CSS '%s' icermemelidir; on-prem/offline kontratini koru.",
        pattern
      )
    )
  }
})
