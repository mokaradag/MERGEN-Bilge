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
    "OPENAI_API_KEY"
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