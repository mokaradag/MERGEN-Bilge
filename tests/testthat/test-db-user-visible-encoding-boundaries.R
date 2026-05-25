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

.has_boundary_regex <- function(text, pattern) {
  isTRUE(suppressWarnings(grepl(
    pattern,
    text,
    perl = TRUE,
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

test_that("chat visible DB normalization repairs observed Turkish AI-answer mojibake", {
  skip_if_not(exists("normalize_db_visible_value", mode = "function", inherits = TRUE))

  broken_ai_answer <- "Ä°yi, teÅŸekkÃ¼r ederim! Sen nasÄ±lsÄ±n? YardÄ±mcÄ± olabilirim."
  expected_ai_answer <- "İyi, teşekkür ederim! Sen nasılsın? Yardımcı olabilirim."

  repaired <- normalize_db_visible_value(broken_ai_answer)

  expect_identical(
    repaired,
    expected_ai_answer
  )

  expect_false(
    grepl("Ã|Ä|Å|Â|\uFFFD", repaired, perl = TRUE),
    info = "Kullanıcıya görünen AI yanıtı DB yazımı öncesinde mojibake içermemelidir."
  )
})

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

test_that("image gallery MB_Messages updates repair only user-visible replacement text", {
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
      "new_content\\s*<-\\s*normalize_db_visible_value\\(new_content\\)"
    ),
    2L,
    label = "Tekil ve toplu görsel silme mesaj güncellemeleri görünür metni önce onarmalıdır."
  )

  expect_false(
    .has_boundary_regex(
      txt,
      "normalize_db_params\\(\\s*list\\(\\s*new_content\\s*,\\s*rows\\$MessageID\\[j\\]\\s*\\)\\s*,\\s*repair_mojibake\\s*=\\s*TRUE"
    ),
    info = "MessageID teknik alandır; karma parametre listesinde repair_mojibake=TRUE kullanılmamalıdır."
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

test_that("MB_Users SSO writes repair visible fields only", {
  db_txt <- .read_repo_text_for_db_encoding_boundary_tests("R/helpers_database.R")
  helper_txt <- .read_repo_text_for_db_encoding_boundary_tests("R/helpers_db_user_encoding.R")
  txt <- paste(db_txt, helper_txt, sep = "\n")

  expected <- c(
    "normalize_sso_claims_for_db <- function(sso_claims)",
    "\"full_name\"",
    "\"first_name\"",
    "\"last_name\"",
    "\"sektor\"",
    "\"department\"",
    "\"mudurluk\"",
    "\"username\"",
    "\"email\"",
    "\"sicil\"",
    "\"masraf_yeri_kodu\"",
    "\"keycloak_sid\"",
    "\"keycloak_sub\"",
    "sso_claims[[field_name]] <- normalize_db_visible_value(sso_claims[[field_name]])",
    "sso_claims[[field_name]] <- normalize_db_technical_value(sso_claims[[field_name]])",
    "username <- normalize_db_technical_value(username)",
    "sso_claims <- normalize_sso_claims_for_db(sso_claims)"
  )

  found <- vapply(expected, function(needle) .has_boundary_text(txt, needle), logical(1))

  expect_true(
    all(found),
    label = paste(
      "Eksik MB_Users SSO görünür/teknik ayrımı:",
      paste(expected[!found], collapse = ", ")
    )
  )

  expect_false(
    .has_boundary_text(db_txt, "normalize_text_tree_utf8(sso_claims, repair_mojibake = TRUE)"),
    info = "SSO claim ağacının tamamı mojibake onarımına sokulmamalıdır."
  )

  expect_false(
    .has_boundary_text(db_txt, "params = normalize_db_params(params, repair_mojibake = TRUE)"),
    info = "MB_Users SSO alanları karma parametre listesiyle whole-list repair yapmamalıdır."
  )
})

test_that("MB_Feedback extended writes repair tags/comments only", {
  txt <- .read_repo_text_for_db_encoding_boundary_tests("R/helpers_db_feedback.R")
  db_txt <- .read_repo_text_for_db_encoding_boundary_tests("R/helpers_database.R")

  expect_true(
    .has_boundary_text(db_txt, "R/helpers_db_feedback.R içine taşındı."),
    info = "helpers_database.R feedback helpers için yeni dosyaya yönlendirme notunu korumalıdır."
  )

  expected <- c(
    "safe_tags <- normalize_db_visible_value(safe_tags)",
    "safe_comment <- normalize_db_visible_value(safe_comment)",
    "feedback_type <- normalize_db_technical_value(feedback_type)"
  )

  found <- vapply(expected, function(needle) .has_boundary_text(txt, needle), logical(1))

  expect_true(
    all(found),
    label = paste(
      "Eksik MB_Feedback görünür/teknik ayrımı:",
      paste(expected[!found], collapse = ", ")
    )
  )

  expect_false(
    .has_boundary_regex(
      txt,
      "normalize_db_params\\(\\s*list\\(\\s*user_id\\s*,\\s*as\\.integer\\(message_id\\)\\s*,\\s*feedback_type\\s*,\\s*safe_tags\\s*,\\s*safe_comment\\s*\\)\\s*,\\s*repair_mojibake\\s*=\\s*TRUE"
    ),
    info = "FeedbackType teknik enum alanıdır; extended feedback karma parametre listesinde repair_mojibake=TRUE kullanılmamalıdır."
  )
})

test_that("mixed chat DB write params do not enable whole-list mojibake repair", {
  txt <- .read_repo_text_for_db_encoding_boundary_tests("R/helpers_db_chat_mutations.R")

  expected <- c(
    "initial_title <- normalize_db_visible_value(initial_title)",
    "msg$content <- normalize_db_visible_value(msg$content)",
    "msg$type <- normalize_db_technical_value(msg$type)",
    "reasoning_content <- normalize_db_visible_value(reasoning_content)",
    "new_content <- normalize_db_visible_value(new_content)",
    "new_title <- normalize_db_visible_value(new_title)",
    "response_text <- normalize_db_visible_value(response_text)",
    "message_type <- normalize_db_technical_value(message_type)",
    "model_used <- normalize_db_technical_value(model_used)"
  )

  found <- vapply(expected, function(needle) .has_boundary_text(txt, needle), logical(1))

  expect_true(
    all(found),
    label = paste(
      "Eksik sohbet DB görünür/teknik normalizasyon sınırı:",
      paste(expected[!found], collapse = ", ")
    )
  )

  forbidden_regex <- c(
    "list\\(chat_id\\s*,\\s*msg\\$content\\s*,\\s*msg\\$type\\s*,\\s*ts\\s*,\\s*next_order\\s*,\\s*reasoning_content\\s*\\)\\s*,\\s*repair_mojibake\\s*=\\s*TRUE",
    "list\\(chat_id\\s*,\\s*msg\\$content\\s*,\\s*msg\\$type\\s*,\\s*ts\\s*,\\s*next_order\\s*\\)\\s*,\\s*repair_mojibake\\s*=\\s*TRUE",
    "list\\(new_content\\s*,\\s*as\\.integer\\(message_id\\)\\s*\\)\\s*,\\s*repair_mojibake\\s*=\\s*TRUE",
    "list\\(new_title\\s*,\\s*chat_id\\s*\\)\\s*,\\s*repair_mojibake\\s*=\\s*TRUE",
    "list\\(chat_id\\s*,\\s*response_text\\s*,\\s*message_type\\s*,\\s*timestamp_gmt3\\s*,\\s*next_order\\s*\\)\\s*,\\s*repair_mojibake\\s*=\\s*TRUE"
  )

  matched <- forbidden_regex[vapply(forbidden_regex, function(pattern) {
    .has_boundary_regex(txt, pattern)
  }, logical(1))]

  expect_equal(
    matched,
    character(0),
    label = paste(
      "Karma sohbet DB parametre listelerinde whole-list repair_mojibake=TRUE kaldı:",
      paste(matched, collapse = ", ")
    )
  )
})

test_that("new MB_Messages writes have a post-insert encoding guard", {
  txt <- .read_repo_text_for_db_encoding_boundary_tests("R/helpers_db_chat_mutations.R")
  encoding_txt <- .read_repo_text_for_db_encoding_boundary_tests("R/helpers_db_encoding.R")
  conn_txt <- .read_repo_text_for_db_encoding_boundary_tests("R/helpers_db_connection.R")

  expect_true(
    .has_boundary_text(encoding_txt, "db_visible_text_has_mojibake <- function(value)"),
    label = "Central mojibake detector must exist for DB-visible text."
  )

  expect_true(
    .has_boundary_text(encoding_txt, "assert_mb_message_visible_encoding_clean <- function(conn, message_id)"),
    label = "Post-insert MB_Messages encoding guard must exist."
  )

  expect_false(
    .has_boundary_text(conn_txt, "assert_mb_message_visible_encoding_clean <- function(conn, message_id)"),
    label = "Post-insert MB_Messages encoding guard should stay in helpers_db_encoding.R, not helpers_db_connection.R."
  )

  expect_gte(
    .count_boundary_regex(
      txt,
      "assert_mb_message_visible_encoding_clean\\(conn,\\s*(message_id|response_message_id)\\)"
    ),
    2L,
    label = "Both main and worker MB_Messages write paths must verify encoding before commit."
  )
})

test_that("VM encoding preflight treats legacy mojibake as warning unless strict flag is set", {
  txt <- .read_repo_text_for_db_encoding_boundary_tests("tests/scripts/run_vm_encoding_preflight_real.R")

  expected <- c(
    "MERGEN_PREFLIGHT_FAIL_ON_LEGACY_MOJIBAKE",
    "Yeni yazma yolu MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=TRUE ile ayrıca doğrulanmalıdır.",
    "if (isTRUE(fail_on_legacy))",
    "vm_encoding_preflight_stop(legacy_message)",
    "cat(legacy_message, \"\\n\")"
  )

  found <- vapply(expected, function(needle) .has_boundary_text(txt, needle), logical(1))

  expect_true(
    all(found),
    label = paste(
      "Eksik legacy mojibake preflight sözleşmesi:",
      paste(expected[!found], collapse = ", ")
    )
  )
})

test_that("maintenance mojibake repair script does not terminate RStudio sessions", {
  txt <- .read_repo_text_for_db_encoding_boundary_tests(
    "tests/scripts/repair_mb_messages_mojibake.R"
  )

  expect_false(
    .has_boundary_regex(txt, "quit\\s*\\("),
    info = "source() ile çalıştırılan bakım scriptleri quit() çağırmamalıdır."
  )
})

test_that("chat DB readers normalize user-visible display frames on read", {
  txt <- .read_repo_text_for_db_encoding_boundary_tests("R/helpers_db_chat_readers.R")

  expect_gte(
    .count_boundary_regex(
      txt,
      "normalize_text_frame_utf8\\([^\\)]*repair_mojibake\\s*=\\s*TRUE"
    ),
    5L,
    label = "Sohbet listeleme, mesaj hidratasyonu ve geçmiş okuma yolları görünür metni onarmalıdır."
  )
})

test_that("identity display DB reads normalize KaynakAdi before UI use", {
  txt <- .read_repo_text_for_db_encoding_boundary_tests("R/module_user_identity.R")

  expect_gte(
    .count_boundary_regex(
      txt,
      "normalize_db_visible_value\\(result2?\\$KaynakAdi\\[1\\]\\)"
    ),
    2L,
    label = "Yerel kimlik çözümlemede DC01_user_base ve MB_Users KaynakAdi görünür metin olarak normalize edilmelidir."
  )
})

test_that("version history remains file-backed and UTF-8 safe, not DB-backed", {
  txt <- .read_repo_text_for_db_encoding_boundary_tests("R/config_version_history.R")

  expected <- c(
    "read_text_lines_utf8(",
    "repair_mojibake = TRUE",
    "normalize_text_utf8(trimmed, repair_mojibake = TRUE)"
  )

  found <- vapply(expected, function(needle) .has_boundary_text(txt, needle), logical(1))

  expect_true(
    all(found),
    label = paste(
      "Eksik version/Yenilikler UTF-8 okuma sözleşmesi:",
      paste(expected[!found], collapse = ", ")
    )
  )

  expect_false(
    .has_boundary_regex(txt, "SELECT\\s+.*version|MB_.*Version|MB_.*Surum|MB_.*Sürüm"),
    info = "Yenilikler/sürüm geçmişi incelenen sözleşmede DB-backed olmamalıdır."
  )
})