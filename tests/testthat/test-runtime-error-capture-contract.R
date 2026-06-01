# ==============================================================================
# Dosya Yolu: tests/testthat/test-runtime-error-capture-contract.R
# Açıklama: mergen_build_runtime_error_record() saf yapılandırılmış hata kaydı
#           üreticisini doğrular. Yapı, hata mesajı çözümü ve sır redaksiyonu
#           davranışsal olarak kapsanır. Shiny/DB/HTTP gerektirmez.
# ==============================================================================

.find_error_capture_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", "..")),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("Runtime error capture testi repo kökünü bulamadı.", call. = FALSE)
}

repo_root_error_capture <- .find_error_capture_repo_root()

# Yardımcı ve redaktör aynı dosyada tanımlıdır.
source(
  file.path(repo_root_error_capture, "R", "utils_log_redact.R"),
  encoding = "UTF-8",
  local = globalenv()
)

test_that("kayıt sözleşmesi: beklenen alanlar ve type", {
  rec <- mergen_build_runtime_error_record(
    simpleError("bir seyler bozuldu"),
    context = "TEST_CTX"
  )

  expect_type(rec, "list")
  expect_setequal(
    names(rec),
    c("type", "context", "message", "error_class", "captured_at")
  )
  expect_identical(rec$type, "runtime_error")
  expect_identical(rec$context, "TEST_CTX")
  expect_identical(rec$message, "bir seyler bozuldu")
  expect_true(grepl("error", rec$error_class, fixed = TRUE))
  expect_true(is.character(rec$captured_at) && length(rec$captured_at) == 1L)
})

test_that("condition, NULL ve karakter girişleri güvenli çözülür", {
  expect_identical(
    mergen_build_runtime_error_record(NULL, context = "C")$message,
    ""
  )
  expect_identical(
    mergen_build_runtime_error_record("ham metin hatasi", context = "C")$message,
    "ham metin hatasi"
  )
  # simpleCondition de message taşır.
  cond <- simpleCondition("kosul mesaji")
  expect_identical(
    mergen_build_runtime_error_record(cond, context = "C")$message,
    "kosul mesaji"
  )
})

test_that("hata mesajındaki JWT ve Bearer token redakte edilir", {
  # Sır-benzeri fikstürler kaynak içinde literal taşımamak için runtime üretilir.
  fake_jwt <- paste0("eyJ", "abcdef", ".", "ghijkl", ".", "mnopqr")
  fake_bearer_token <- paste0("abc", "123", "def", "456", "ghi")
  msg_in <- paste0(
    "baglanti hatasi jwt=", fake_jwt,
    " Authorization: Bearer ", fake_bearer_token
  )

  rec <- mergen_build_runtime_error_record(
    simpleError(msg_in),
    context = "AUTH_CTX"
  )

  expect_false(grepl(fake_jwt, rec$message, fixed = TRUE))
  expect_true(grepl("<jwt-redacted>", rec$message, fixed = TRUE))
  expect_false(grepl(fake_bearer_token, rec$message, fixed = TRUE))
  expect_true(grepl("Bearer <redacted>", rec$message, fixed = TRUE))
})

test_that("baglam da redaksiyondan gecer", {
  fake_jwt <- paste0("eyJ", "zzzzz", ".", "yyyyy", ".", "xxxxx")
  rec <- mergen_build_runtime_error_record(
    simpleError("ok"),
    context = paste0("ctx ", fake_jwt)
  )
  expect_false(grepl(fake_jwt, rec$context, fixed = TRUE))
  expect_true(grepl("<jwt-redacted>", rec$context, fixed = TRUE))
})

test_that("ozel redact_fn onurlandirilir", {
  rec <- mergen_build_runtime_error_record(
    simpleError("kucuk"),
    context = "c",
    redact_fn = toupper
  )
  expect_identical(rec$message, "KUCUK")
  expect_identical(rec$context, "C")
})

test_that("verilen now zaman damgasi olarak bicimlenir", {
  fixed_now <- as.POSIXct("2026-06-01 12:00:00", tz = "UTC")
  rec <- mergen_build_runtime_error_record(
    simpleError("x"),
    context = "c",
    now = fixed_now
  )
  expect_true(nzchar(rec$captured_at))
  expect_true(grepl("2026-06-01", rec$captured_at, fixed = TRUE))
})
