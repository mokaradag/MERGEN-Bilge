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

# Geliştiricinin ortamındaki gerçek ya da sahte kimlik bilgisi değişkenleri
# (ör. DB_PASSWORD) literal değer redaktörüyle sonuçları değiştirmesin diye
# test süresince kaldırılır ve sonunda geri yüklenir.
.redact_env_yalit <- function(env = parent.frame()) {
  adlar <- .redact_env_var_names()
  withr::local_envvar(stats::setNames(rep(NA_character_, length(adlar)), adlar), .local_envir = env)
}

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
  password_key <- paste0("pass", "word")

  out_pw <- redact_sensitive_text(paste0(password_key, "=", .redact_conn_secret))
  expect_true(grepl(paste0(password_key, "=<redacted>"), out_pw, fixed = TRUE))

  out_bearer <- redact_sensitive_text(paste0("Authorization: Bearer ", paste0("abc", "123", "def", "456")))
  expect_true(grepl("Bearer <redacted>", out_bearer, fixed = TRUE))
})
test_that("log sınırı tırnaklı bağlantı tanımlayıcılarını ve kısa tırnaklı sırları maskeler", {
  ozel_dsn <- paste0("Ozel", "Uretim")
  ic_sunucu <- paste0("ic-", "sunucu")
  kisa <- paste0("a", "b", "c")
  for (tirnak in c("\"", "'")) {
    q <- function(x) paste0(tirnak, x, tirnak)
    ileti <- paste0("DSN=", q(ozel_dsn), ";Server=", q(ic_sunucu), ";PWD=", q(kisa))
    out <- redacted_condition_message(simpleError(ileti))
    expect_false(grepl(ozel_dsn, out, fixed = TRUE))
    expect_false(grepl(ic_sunucu, out, fixed = TRUE))
    expect_false(grepl(paste0("=", q(kisa)), out, fixed = TRUE))
    expect_true(grepl(paste0("DSN=", q("<redacted>")), out, fixed = TRUE))
    expect_true(grepl(paste0("PWD=", q("<redacted>")), out, fixed = TRUE))
    out_token <- redact_connection_identifiers(paste0("token: ", q(kisa)))
    expect_false(grepl(kisa, out_token, fixed = TRUE))
  }
  # Anahtarı olmayan tırnaklı Türkçe metin (tanı bağlamı) korunur.
  tani <- "Çalışma tablosu \"Söyleşi\" bulunamadı"
  expect_identical(redacted_condition_message(simpleError(tani)), tani)
})

test_that("log sınırı JSON-tırnaklı anahtarları, kısa çıplak sırları ve kapanmamış tırnaklı değerleri maskeler", {
  .redact_env_yalit()
  sentetik <- paste0("sentetik", "-", "jeton", "-42")
  kisa <- paste0("ab", "cde")
  pw <- paste0("a", "bc")
  # JSON biçiminde tırnaklı anahtar (her iki tırnak türü).
  for (girdi in c(paste0("{\"token\":\"", sentetik, "\"}"), paste0("{\"PWD\":\"", pw, "\"}"),
                  paste0("{'client_secret': '", kisa, "'}"), paste0("{\"token\": ", "12345", "}"))) {
    out <- redacted_condition_message(simpleError(girdi))
    expect_false(grepl(sentetik, out, fixed = TRUE), info = girdi)
    expect_false(grepl(paste0("\"", pw, "\""), out, fixed = TRUE), info = girdi)
    expect_false(grepl(kisa, out, fixed = TRUE), info = girdi)
    expect_false(grepl("12345", out, fixed = TRUE), info = girdi)
    expect_true(grepl("<redacted>", out, fixed = TRUE), info = girdi)
  }
  # Kısa çıplak sırlar (genel redaktörün 6 karakter eşiği bu katmanda yok).
  for (anahtar in c("secret", "token", "api_key", "x-api-key", "client_secret")) {
    for (ayrac in c("=", ": ")) {
      out <- redacted_condition_message(simpleError(paste0(anahtar, ayrac, kisa)))
      expect_identical(out, paste0(anahtar, ayrac, "<redacted>"))
    }
  }
  # Genel redaktörün eşiği değişmez (yalnızca log katmanı genişledi).
  expect_identical(redact_sensitive_text(paste0("secret=", kisa)), paste0("secret=", kisa))
  # Kesilmiş tanıda kapanmamış tırnaklı değer satır sonuna kadar maskelenir.
  expect_identical(redacted_condition_message(simpleError(paste0("PWD='", pw))), "PWD='<redacted>")
  cok_satir <- redacted_condition_message(simpleError(paste0("bağlanamadı: PWD=\"", pw, "\nsonraki satır korunur")))
  expect_false(grepl(pw, cok_satir, fixed = TRUE))
  expect_true(grepl("sonraki satır korunur", cok_satir, fixed = TRUE))
  # Kaçışlı tırnak içeren değerin kuyruğu sızmaz.
  expect_identical(redact_connection_identifiers(paste0("api_key=\"ab\\\"", kisa, "\"")), "api_key=\"<redacted>\"")
  # Karışık biçim: süslü, tırnaklı ve çıplak değerler birlikte; sözcük içi anahtar korunur.
  karisik <- redacted_condition_message(simpleError(paste0(
    "Driver={ODBC Driver 17};Server='ic-", "sunucu';Pwd={A}}B}; mytoken=", kisa)))
  expect_identical(karisik, paste0("Driver={<redacted>};Server='<redacted>';Pwd={<redacted>}; mytoken=", kisa))
  # Anahtarsız Türkçe tanı bağlamı ve "Database:" düzyazısı korunur.
  expect_identical(redacted_condition_message(simpleError("Database: bağlantı başarısız")),
                   "Database: bağlantı başarısız")
})

test_that("log sınırı kaçış belirsizliğinde, camelCase jetonlarda, CRLF'de ve kısa Authorization'da kapalı maskeler", {
  .redact_env_yalit()
  kuyruk <- paste0("kuy", "ruk42")
  pw <- paste0("ab", "cde")
  kisa <- paste0("YT", "pi")
  # Genel redaktörden önce işlenir: kaçışlı tırnaktan önce 6+ karakter olsa da kuyruk sızmaz.
  out <- redacted_condition_message(simpleError(paste0("api_key=\"abcdef\\\"", kuyruk, "\"")))
  expect_false(grepl(kuyruk, out, fixed = TRUE))
  # Düz ters bölü sonraki anahtarın değerini açığa çıkarmaz (iki alan da maskede kalır).
  out <- redacted_condition_message(simpleError(paste0("Server='db\\';PWD='", pw, "'")))
  expect_false(grepl(pw, out, fixed = TRUE))
  expect_false(grepl("db", out, fixed = TRUE))
  # Ters bölü içeren sunucu adı (HOST\INSTANCE) ve komşu alan maskelenir.
  out <- redacted_condition_message(simpleError("Server='HOST\\INST';Database='x'"))
  expect_false(grepl("HOST", out, fixed = TRUE))
  # authToken / idToken JSON alanları maskelenir; sözcük içi `mytoken` korunur.
  for (anahtar in c("authToken", "idToken", "auth_token")) {
    out <- redacted_condition_message(simpleError(paste0("{\"", anahtar, "\":\"", pw, "\"}")))
    expect_identical(out, paste0("{\"", anahtar, "\":\"<redacted>\"}"), info = anahtar)
  }
  # Kapanmamış tırnaklı değer CRLF'den önce maskelenir, sonraki satır korunur.
  out <- redacted_condition_message(simpleError(paste0("PWD='", pw, "\r\nsonraki satır")))
  expect_identical(out, "PWD='<redacted>\r\nsonraki satır")
  out <- redacted_condition_message(simpleError(paste0("Pwd={", pw, "\r\nsonraki satır")))
  expect_false(grepl(pw, out, fixed = TRUE))
  expect_true(grepl("\r\nsonraki satır", out, fixed = TRUE))
  # Tırnaklı bağlantı anahtarının çıplak değeri maskelenir; `UID=` biçimi de korunur.
  expect_identical(redacted_condition_message(simpleError("{\"uid\":12345}")), "{\"uid\":<redacted>}")
  expect_identical(redacted_condition_message(simpleError("UID=12345;x")), "UID=<redacted>;x")
  # Kısa Authorization kimlik bilgisi şema korunarak maskelenir.
  for (sema in c("Basic", "Bearer")) {
    out <- redacted_condition_message(simpleError(paste0("Authorization: ", sema, " ", kisa)))
    expect_identical(out, paste0("Authorization: ", sema, " <redacted>"), info = sema)
  }
  out <- redacted_condition_message(simpleError(paste0("{\"Authorization\":\"Basic ", kisa, "\"}")))
  expect_false(grepl(kisa, out, fixed = TRUE))
  # Genel redaktörün kısa değer sözleşmesi değişmez.
  expect_identical(redact_sensitive_text(paste0("Authorization: Basic ", kisa)),
                   paste0("Authorization: Basic ", kisa))
})

test_that("boşluk içeren çıplak ODBC parolası tümüyle maskelenir; DB hata özeti SQL gövdesini atar", {
  .redact_env_yalit()
  ikinci <- paste0("ikinci", "kelime")
  out <- redacted_condition_message(simpleError(paste0("PWD=abc ", ikinci, ";UID=test;Server=x")))
  expect_false(grepl(ikinci, out, fixed = TRUE))
  expect_identical(out, "PWD=<redacted>;UID=<redacted>;Server=<redacted>")
  # Sürücü tanısındaki SQL (gömülü hesap kimliğiyle) günlük özetine girmez.
  hata <- simpleError(paste0("nanodbc: 42000 [SQL Server] Invalid column DSN=ozel <SQL> ",
                             "'SELECT c.ChatID FROM MB_Chats c WHERE c.UserID = 4242'"))
  ozet <- mergen_db_error_log_summary(hata)
  expect_false(grepl("4242", ozet, fixed = TRUE))
  expect_false(grepl("ozel", ozet, fixed = TRUE))
  expect_match(ozet, "<SQL gizlendi>", fixed = TRUE)
  expect_match(ozet, "^\\[simpleError\\] nanodbc: 42000")
  # SQL'siz tanı bağlamı korunur.
  expect_identical(mergen_db_error_log_summary(simpleError("Login timeout expired")),
                   "[simpleError] Login timeout expired")
})

test_that("tanı ters bölüyle biten kapanmamış tırnaklı parolada kesilse de değer maskelenir", {
  .redact_env_yalit()
  pw <- paste0("ab", "c")
  out <- redacted_condition_message(simpleError(paste0("hata PWD='", pw, "\\")))
  expect_identical(out, "hata PWD='<redacted>")
})
