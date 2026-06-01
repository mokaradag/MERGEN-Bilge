# ==============================================================================
# Dosya Yolu: R/utils_log_redact.R
# Açıklama: Log ve hata metinlerinde kazara sızabilecek hassas içeriği (JWT,
# Bearer token, API anahtarı env değerleri, query string parolaları) maskeler.
# Kurumsal Windows VM'de log dosyaları merkezi toplama araçları tarafından
# okunur; gizli verinin "tesadüfen" loglanması kalıcı sızıntı oluşturabilir.
# Bu modül yan etkisiz bir fonksiyon ihraç eder; çağıran taraf kendi log
# fonksiyonunu sarmalayabilir veya metni göndermeden önce redakte edebilir.
# ==============================================================================

# Kontrollü bir liste: hassas değerleri ortam değişkeninden alır ve log içinde
# ham değer geçiyorsa maskeler. Liste üretim ortamına göre genişletilebilir.
.redact_env_var_names <- function() {
  c(
    "AI_KEYS_MASTER",
    "LOCAL_LLM_API_KEY",
    "LOCAL_LLM_ENDPOINT_ALT_API_KEY",
    "LOCAL_TTS_API_KEY",
    "SERVICE_DESK_API_KEY_URL",
    "ANTHROPIC_API_KEY",
    "CLAUDE_CODE_API_KEY",
    "CLAUDE_API_KEY",
    "OPENAI_API_KEY",

    # DB / ODBC secrets. The current app primarily uses DSN names, but VM
    # profiles may still define password-like env vars for drivers/scripts.
    "DB_PASSWORD",
    "DB_PASS",
    "DB_PWD",
    "ODBC_PASSWORD",
    "ODBC_PWD",
    "SQL_PASSWORD",
    "SQLSERVER_PASSWORD",
    "MSSQL_PASSWORD",

    # SSO / OIDC / Keycloak secrets. The current implicit-flow config does not
    # require one, but this keeps logs safe if a secret is later introduced.
    "SSO_CLIENT_SECRET",
    "SSO_KEYCLOAK_CLIENT_SECRET",
    "KEYCLOAK_CLIENT_SECRET",
    "OIDC_CLIENT_SECRET",
    "SSO_SECRET"
  )
}

# Belirtilen env değerini metin içinde arayıp, bulursa yer değiştirir.
# Çok kısa değerler (örn. boş string) atlanır; aksi halde yanlış pozitif olur.
.redact_literal_values <- function(text) {
  for (var_name in .redact_env_var_names()) {
    var_value <- Sys.getenv(var_name, unset = "")
    if (!nzchar(var_value) || nchar(var_value) < 8L) next
    text <- gsub(var_value, sprintf("<%s:redacted>", var_name), text, fixed = TRUE)
  }
  text
}

# Ana redaksiyon fonksiyonu. Girişteki her bir karakter elemanı üzerinde
# sırasıyla aşağıdaki desenleri maskeler. Regex'ler olabildiğince dar
# tutulmuştur; amaç gerçek gizli değeri yakalamak, normal metni değiştirmemektir.
redact_sensitive_text <- function(x) {
  if (is.null(x)) return(x)
  if (!is.character(x)) {
    x <- tryCatch(as.character(x), error = function(e) "")
  }
  if (!length(x)) return(character(0))

  vapply(x, function(elem) {
    if (is.na(elem) || !nzchar(elem)) return(elem)

    metin <- elem

    # 1) JWT formatı: header.payload.signature (URL-safe base64 parçaları).
    # Üretimde decode edilmiş token'ların log'a girmesi en yaygın risktir.
    metin <- gsub(
      "eyJ[A-Za-z0-9_\\-]{5,}\\.[A-Za-z0-9_\\-]{5,}\\.[A-Za-z0-9_\\-]{5,}",
      "<jwt-redacted>",
      metin,
      perl = TRUE
    )

    # 2) Authorization header tipi: "Bearer xyz" veya "Basic xyz".
    metin <- gsub(
      "(?i)\\b(Bearer|Basic)\\s+[A-Za-z0-9._\\-=/+]{6,}",
      "\\1 <redacted>",
      metin,
      perl = TRUE
    )

    # 3) URL query string parametreleri: ?token=, &password=, &api_key=, &secret=
    metin <- gsub(
      "(?i)([?&](?:token|password|passwd|api[_-]?key|apikey|secret|access[_-]?token)=)[^&#\\s]+",
      "\\1<redacted>",
      metin,
      perl = TRUE
    )

    # 3B) Header / key-value biçimindeki sırları maskele:
    # api_key = ..., x-api-key: ..., password: ..., client_secret=...
    secret_key_pattern <- paste(
      c(
        "api[_-]?key",
        "apikey",
        "x-api-key",
        "token",
        "access[_-]?token",
        "refresh[_-]?token",
        "secret",
        "client[_-]?secret",
        "password",
        "passwd"
      ),
      collapse = "|"
    )

    metin <- gsub(
      paste0("(?i)\\b(", secret_key_pattern, ")(\\s*[:=]\\s*)\"[^\"]{6,}\""),
      "\\1\\2\"<redacted>\"",
      metin,
      perl = TRUE
    )

    metin <- gsub(
      paste0("(?i)\\b(", secret_key_pattern, ")(\\s*[:=]\\s*)'[^']{6,}'"),
      "\\1\\2'<redacted>'",
      metin,
      perl = TRUE
    )

    metin <- gsub(
      paste0("(?i)\\b(", secret_key_pattern, ")(\\s*[:=]\\s*)[^\\s,;}{\"'&#<>]{6,}"),
      "\\1\\2<redacted>",
      metin,
      perl = TRUE
    )

    # 4) Bilinen env değişkeni değerleri.
    metin <- .redact_literal_values(metin)

    metin
  }, character(1), USE.NAMES = FALSE)
}

# Runtime hatalarını yapılandırılmış, sır-redakteli ve yan etkisiz bir kayda
# çevirir. Çağıran taraf bu kaydı tek satır halinde loglayabilir veya bir olay
# izleme akışına gönderebilir. Bilinçli olarak Shiny/DB/dosya/HTTP içermez;
# böylece izole test edilebilir ve hata yolunda kendisi yeni hata üretmez.
mergen_build_runtime_error_record <- function(error,
                                              context = "unknown",
                                              redact_fn = NULL,
                                              now = Sys.time()) {
  # Redaksiyon fonksiyonu verilmediyse aynı modüldeki güvenli redaktörü kullan.
  if (is.null(redact_fn) && exists("redact_sensitive_text", mode = "function")) {
    redact_fn <- get("redact_sensitive_text", mode = "function")
  }

  # Hata mesajını koşula göre güvenli biçimde çöz.
  error_msg <- tryCatch({
    if (inherits(error, "condition")) {
      conditionMessage(error)
    } else if (is.null(error)) {
      ""
    } else {
      paste(as.character(error), collapse = " ")
    }
  }, error = function(e) "")

  # Hata sınıfı (R sınıf adları) tanılama için saklanır; sır taşımaz.
  error_class <- tryCatch({
    cls <- class(error)
    if (length(cls)) paste(cls, collapse = ",") else "unknown"
  }, error = function(e) "unknown")

  # Hem bağlam hem mesaj redakte edilir; hata metni token/DSN/parola taşıyabilir.
  redact_one <- function(value) {
    value <- as.character(value)[1]
    if (is.na(value)) value <- ""
    if (is.function(redact_fn)) {
      value <- tryCatch(as.character(redact_fn(value))[1], error = function(e) value)
      if (is.na(value)) value <- ""
    }
    enc2utf8(value)
  }

  captured_at <- tryCatch(
    format(now, "%Y-%m-%dT%H:%M:%S%z"),
    error = function(e) ""
  )
  if (length(captured_at) != 1L || is.na(captured_at)) {
    captured_at <- ""
  }

  list(
    type = "runtime_error",
    context = redact_one(context),
    message = redact_one(error_msg),
    error_class = enc2utf8(error_class),
    captured_at = captured_at
  )
}