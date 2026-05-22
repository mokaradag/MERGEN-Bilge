# ==============================================================================
# Dosya Yolu: tests/testthat/test-log-redact.R
# Açıklama: redact_sensitive_text() fonksiyonunun JWT, Bearer/Basic, URL
# parola/anahtar parametreleri ve env anahtar değeri tespitindeki davranışını
# doğrulayan birim testleri. Fonksiyon yan etkisiz olmalı; normal metni
# değiştirmemesi önemlidir (yanlış pozitif regresyon koruması).
# ==============================================================================

local({
  source(
    file.path(repo_root_for_tests, "R", "utils_log_redact.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
})

test_that("redact_sensitive_text JWT benzeri deseni maskeler", {
  # Örnek JWT (gerçek değil): header.payload.signature
  ornek <- paste0(
    "Kullanıcı token döndü: ",
    "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.abcDEF123xyz"
  )
  sonuc <- redact_sensitive_text(ornek)
  expect_true(grepl("<jwt-redacted>", sonuc, fixed = TRUE))
  expect_false(grepl("eyJhbGciOiJIUzI1NiJ9", sonuc, fixed = TRUE))
})

test_that("redact_sensitive_text Bearer ve Basic header'ı maskeler", {
  metin1 <- "Authorization: Bearer abc123defGHI.jkl_mno-456"
  sonuc1 <- redact_sensitive_text(metin1)
  expect_true(grepl("Bearer <redacted>", sonuc1, fixed = TRUE))
  expect_false(grepl("abc123defGHI", sonuc1, fixed = TRUE))

  metin2 <- "Authorization: Basic dXNlcjpwYXNzMTIzNDU="
  sonuc2 <- redact_sensitive_text(metin2)
  expect_true(grepl("Basic <redacted>", sonuc2, fixed = TRUE))
})

test_that("redact_sensitive_text URL token/key parametrelerini maskeler", {
  m <- "GET https://api.ornek.com/veri?token=gizli_deger_123&id=42"
  sonuc <- redact_sensitive_text(m)
  expect_true(grepl("token=<redacted>", sonuc, fixed = TRUE))
  expect_false(grepl("gizli_deger_123", sonuc, fixed = TRUE))
  # id=42 gibi normal parametreler bozulmamalı
  expect_true(grepl("id=42", sonuc, fixed = TRUE))
})

test_that("redact_sensitive_text bilinen env anahtar değerini maskeler", {
  eski <- Sys.getenv("AI_KEYS_MASTER", unset = "")
  Sys.setenv(AI_KEYS_MASTER = "supersekretkey_abcdef1234")
  on.exit(Sys.setenv(AI_KEYS_MASTER = eski))

  m <- "Config yüklendi: anahtar=supersekretkey_abcdef1234 ortam=vm"
  sonuc <- redact_sensitive_text(m)
  expect_true(grepl("<AI_KEYS_MASTER:redacted>", sonuc, fixed = TRUE))
  expect_false(grepl("supersekretkey_abcdef1234", sonuc, fixed = TRUE))
})

test_that("redact_sensitive_text DB ve SSO env sırlarını literal değer olarak maskeler", {
  old_db <- Sys.getenv("DB_PASSWORD", unset = "")
  old_sso <- Sys.getenv("SSO_CLIENT_SECRET", unset = "")

  fake_db <- "fake_db_password_abcdef1234"
  fake_sso <- "fake_sso_secret_abcdef1234"

  Sys.setenv(
    DB_PASSWORD = fake_db,
    SSO_CLIENT_SECRET = fake_sso
  )

  on.exit({
    Sys.setenv(DB_PASSWORD = old_db)
    Sys.setenv(SSO_CLIENT_SECRET = old_sso)
  }, add = TRUE)

  sonuc <- redact_sensitive_text(c(
    paste("DB bağlantı hatası:", fake_db),
    paste("SSO yapılandırması:", fake_sso)
  ))

  expect_false(any(grepl(fake_db, sonuc, fixed = TRUE)))
  expect_false(any(grepl(fake_sso, sonuc, fixed = TRUE)))
  expect_true(any(grepl("<DB_PASSWORD:redacted>", sonuc, fixed = TRUE)))
  expect_true(any(grepl("<SSO_CLIENT_SECRET:redacted>", sonuc, fixed = TRUE)))
})

test_that("save_message_safely fallback log redaction contract korunur", {
  repo_root <- resolve_repo_root_for_tests()
  path <- file.path(repo_root, "R", "helpers_db_chat_mutations.R")
  txt <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  expect_true(grepl("redact_sensitive_text(log_json)", txt, fixed = TRUE))
})

test_that("redact_sensitive_text key-value biçimindeki sırları maskeler", {
  fake_values <- c(
    "fakeapi123",
    "fakepass123",
    "fakehead123",
    "fakeclient123"
  )

  giris <- c(
    paste0("api_", "key = ", fake_values[1]),
    paste0("pass", "word: ", fake_values[2]),
    paste0("x-api-", "key: ", fake_values[3]),
    paste0("client_", "secret=", fake_values[4])
  )

  sonuc <- redact_sensitive_text(giris)

  expect_true(all(grepl("<redacted>", sonuc, fixed = TRUE)))
  expect_false(any(vapply(
    fake_values,
    function(needle) any(grepl(needle, sonuc, fixed = TRUE)),
    logical(1)
  )))
})

test_that("redact_sensitive_text Claude özgü env anahtar değerini maskeler", {
  eski <- Sys.getenv("ANTHROPIC_API_KEY", unset = "")
  fake_value <- "anthropicfake123"

  Sys.setenv(ANTHROPIC_API_KEY = fake_value)
  on.exit(Sys.setenv(ANTHROPIC_API_KEY = eski), add = TRUE)

  sonuc <- redact_sensitive_text(paste("Claude key yüklendi:", fake_value))

  expect_true(grepl("<ANTHROPIC_API_KEY:redacted>", sonuc, fixed = TRUE))
  expect_false(grepl(fake_value, sonuc, fixed = TRUE))
})

test_that("redact_sensitive_text normal metni değiştirmez", {
  m <- "Kullanıcı Mehmet oturum açtı; süre 120s; Ankara saati."
  sonuc <- redact_sensitive_text(m)
  expect_equal(sonuc, m)
})

test_that("redact_sensitive_text NULL/NA/boş girişte güvenli çalışır", {
  expect_null(redact_sensitive_text(NULL))
  expect_identical(redact_sensitive_text(character(0)), character(0))
  expect_true(is.na(redact_sensitive_text(NA_character_)))
})

test_that("redact_sensitive_text vektörel girdi üzerinde çalışır", {
  giris <- c(
    "Bearer abcdef.GHIJKL-789",
    "basit metin",
    "?api_key=yas_12345"
  )
  sonuc <- redact_sensitive_text(giris)
  expect_equal(length(sonuc), 3L)
  expect_true(grepl("Bearer <redacted>", sonuc[1], fixed = TRUE))
  expect_equal(sonuc[2], "basit metin")
  expect_true(grepl("api_key=<redacted>", sonuc[3], fixed = TRUE))
})