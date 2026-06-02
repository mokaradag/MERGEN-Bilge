# ==============================================================================
# Dosya Yolu: tests/testthat/test-log-redact-connection-string-behavior.R
# Açıklama: redact_sensitive_text() için ODBC/SQL Server bağlantı dizesi parola
#           sızıntısı sınırını davranışsal kapsar. Bu uygulama DB_DSN/ODBC ile
#           bağlandığından, loglanan bir "Pwd=..." bağlantı dizesi veya sürücü
#           hatası parolayı sızdırabilir. Test, "Pwd/PWD/pwd" değerinin maskelendiğini
#           ve "Uid=" (kullanıcı adı) ile kısa/sözcük-içi durumların aşırı
#           maskelenmediğini doğrular. Sır-benzeri değer kaynakta literal taşımamak
#           için runtime üretilir.
# ==============================================================================

.find_redact_conn_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", "..")),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "R"))) {
      return(candidate)
    }
  }

  stop("Redaksiyon bağlantı dizesi testi repo kökünü bulamadı.", call. = FALSE)
}

repo_root_redact_conn <- .find_redact_conn_repo_root()

source(
  file.path(repo_root_redact_conn, "R", "utils_log_redact.R"),
  encoding = "UTF-8",
  local = globalenv()
)

# Sır-benzeri değer kaynakta literal olarak durmasın diye runtime üretilir.
.redact_conn_secret <- paste0("S3", "cretValue", "123")

test_that("ODBC bağlantı dizesindeki Pwd parolası maskelenir, Uid korunur", {
  conn <- paste0("Driver={ODBC};Server=db1;Uid=svc_user;Pwd=", .redact_conn_secret)
  out <- redact_sensitive_text(conn)

  expect_false(grepl(.redact_conn_secret, out, fixed = TRUE))
  expect_true(grepl("Pwd=<redacted>", out, fixed = TRUE))
  # Kullanıcı adı sır değildir; korunmalıdır.
  expect_true(grepl("Uid=svc_user", out, fixed = TRUE))
  expect_true(grepl("Server=db1", out, fixed = TRUE))
})

test_that("Pwd/PWD/pwd büyük-küçük harf varyantları maskelenir", {
  for (key in c("Pwd", "PWD", "pwd")) {
    out <- redact_sensitive_text(paste0(key, "=", .redact_conn_secret))
    expect_false(grepl(.redact_conn_secret, out, fixed = TRUE), info = key)
    expect_true(grepl(paste0(key, "=<redacted>"), out, fixed = TRUE), info = key)
  }
})

test_that("URL query string &pwd= maskelenir, komşu parametreler korunur", {
  url <- paste0("conn?host=db&pwd=", .redact_conn_secret, "&db=app")
  out <- redact_sensitive_text(url)
  expect_false(grepl(.redact_conn_secret, out, fixed = TRUE))
  expect_true(grepl("pwd=<redacted>", out, fixed = TRUE))
  expect_true(grepl("host=db", out, fixed = TRUE))
  expect_true(grepl("db=app", out, fixed = TRUE))
})

test_that("aşırı maskeleme yok: kullanıcı adı, kısa değer ve sözcük-içi pwd korunur", {
  # Uid bir sır değildir.
  expect_identical(redact_sensitive_text("Uid=svc_user"), "Uid=svc_user")
  # 6 karakterden kısa değerler eşik gereği maskelenmez (yanlış pozitif önleme).
  expect_identical(redact_sensitive_text("Pwd=abc"), "Pwd=abc")
  # Sözcük-içi 'pwd' (örn. keypwd) bir anahtar değildir.
  expect_identical(
    redact_sensitive_text("the keypwd column is fine"),
    "the keypwd column is fine"
  )
})

test_that("mevcut password= ve Bearer redaksiyonu bozulmaz", {
  out_pw <- redact_sensitive_text(paste0("password=", .redact_conn_secret))
  expect_true(grepl("password=<redacted>", out_pw, fixed = TRUE))

  out_bearer <- redact_sensitive_text(paste0("Authorization: Bearer ", paste0("abc", "123", "def", "456")))
  expect_true(grepl("Bearer <redacted>", out_bearer, fixed = TRUE))
})
