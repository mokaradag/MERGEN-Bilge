# ==============================================================================
# Dosya Yolu: tests/testthat/test-db-user-visible-encoding-boundaries.R
# Açıklama: Kullanıcıya görünen DB yazma/okuma sınırlarında merkezi kodlama
#           normalizasyonunun kullanılmasını statik olarak korur.
# ==============================================================================

.find_repo_root_for_db_encoding_boundary_tests <- function() {
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
        dir.exists(file.path(candidate, "R"))) {
      return(candidate)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.read_repo_text_for_db_encoding_boundary_tests <- function(path) {
  repo_root <- .find_repo_root_for_db_encoding_boundary_tests()
  full_path <- file.path(repo_root, path)

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

  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.has_boundary_text <- function(text, needle) {
  isTRUE(suppressWarnings(grepl(
    needle,
    text,
    fixed = TRUE,
    useBytes = TRUE
  )))
}

.count_boundary_regex <- function(text, pattern) {
  matches <- gregexpr(pattern, text, perl = TRUE, useBytes = TRUE)[[1]]
  if (length(matches) == 1L && matches[1] < 0L) {
    return(0L)
  }
  length(matches)
}

test_that("DB normalization repair remains opt-in for technical character values", {
  skip_if_not(exists("normalize_db_value", mode = "function", inherits = TRUE))

  withr::local_envvar(c(
    DB_CLIENT_ENCODING = "UTF-8",
    DB_NAME_ENCODING = "UTF-8"
  ))

  broken <- "TÃ¼rkiye"
  expect_identical(
    normalize_db_value(broken, repair_mojibake = FALSE),
    broken
  )
  expect_identical(
    normalize_db_value(broken, repair_mojibake = TRUE),
    "Türkiye"
  )
})

test_that("support DB helpers normalize user-visible Turkish fields before writes", {
  txt <- .read_repo_text_for_db_encoding_boundary_tests("R/helpers_destek_database.R")

  expected <- c(
    "destek_normalize_visible_db_text <- function(",
    "destek_normalize_technical_db_text <- function(",
    "safe_etiketler <- if (is.null(etiketler)",
    "destek_normalize_visible_db_text(etiketler)",
    "destek_normalize_visible_db_text(en_cok_sevilen)",
    "destek_normalize_visible_db_text(gelistirme)",
    "safe_konular <- destek_normalize_visible_db_text(konular)",
    "safe_kategoriler <- destek_normalize_visible_db_text(kategoriler)",
    "safe_aciklama <- destek_normalize_visible_db_text(aciklama)",
    "destek_normalize_technical_db_text(ek_dosya_yollari)"
  )

  found <- vapply(expected, function(needle) .has_boundary_text(txt, needle), logical(1))

  expect_true(
    all(found),
    label = paste(
      "Eksik destek DB kodlama sınırı kayıtları:",
      paste(expected[!found], collapse = ", ")
    )
  )

  expect_false(
    .has_boundary_text(txt, "safe_oncelik <- destek_normalize_visible_db_text"),
    info = "Oncelik teknik enum alanıdır; mojibake onarımına sokulmamalıdır."
  )

  expect_false(
    .has_boundary_text(txt, "safe_ek_dosyalar <- destek_normalize_visible_db_text"),
    info = "Ek dosya yolları teknik/path alanıdır; mojibake onarımına sokulmamalıdır."
  )
})

test_that("support DB list/read helpers normalize display frames on read", {
  txt <- .read_repo_text_for_db_encoding_boundary_tests("R/helpers_destek_database.R")

  expect_true(
    .has_boundary_text(txt, "destek_normalize_result_frame <- function(result)"),
    label = "Destek okuma yolları için ortak result-frame normalizasyonu bulunmalıdır."
  )

  expect_gte(
    .count_boundary_regex(txt, "destek_normalize_result_frame\\(result\\)"),
    4L,
    label = "Destek geri bildirim/hata listeleme ve kullanıcı geçmişi okuma yolları normalize edilmelidir."
  )
})

test_that("image gallery MB_Messages updates use central DB normalization", {
  txt <- .read_repo_text_for_db_encoding_boundary_tests("R/helpers_image_gallery.R")

  expect_false(
    grepl(
      "params\\s*=\\s*list\\(\\s*new_content\\s*,\\s*rows\\$MessageID\\[j\\]",
      txt,
      perl = TRUE,
      useBytes = TRUE
    ),
    info = "MB_Messages.MessageContent için raw params=list(new_content, ...) yazımı geri gelmemelidir."
  )

  expect_gte(
    .count_boundary_regex(
      txt,
      "normalize_db_params\\(\\s*list\\(\\s*new_content\\s*,\\s*rows\\$MessageID\\[j\\]\\s*\\)\\s*,\\s*repair_mojibake\\s*=\\s*TRUE"
    ),
    2L,
    label = "Tekil ve toplu görsel silme mesaj güncellemeleri repair_mojibake=TRUE kullanmalıdır."
  )
})

test_that("SSO visible claims use central repair while technical claims avoid repair", {
  txt <- .read_repo_text_for_db_encoding_boundary_tests("R/helpers_sso.R")

  expected <- c(
    "normalize_sso_visible_claim <- function(value)",
    "normalize_text_utf8(value, repair_mojibake = TRUE)",
    "normalize_sso_technical_claim <- function(value)",
    "normalize_text_utf8(value, repair_mojibake = FALSE)",
    "username <- tolower(normalize_sso_technical_claim(raw_username))",
    "full_name  <- normalize_sso_visible_claim(raw_full_name)",
    "department <- normalize_sso_visible_claim(raw_department)",
    "email          = normalize_sso_technical_claim(raw_email)",
    "sicil          = normalize_sso_technical_claim(raw_sicil)"
  )

  found <- vapply(expected, function(needle) .has_boundary_text(txt, needle), logical(1))

  expect_true(
    all(found),
    label = paste(
      "Eksik SSO görünür/teknik kodlama ayrımı:",
      paste(expected[!found], collapse = ", ")
    )
  )
})