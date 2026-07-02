# ==============================================================================
# Dosya Yolu: tests/scripts/soak_secret_redaction.R
# Aciklama:
#   Operasyonel soak/yuk testi artifact'lari icin secret/gizlilik redaksiyon
#   yardimcilari. Amac: HICBIR ham sir (gercek/sahte API anahtari, bearer token,
#   DB parolasi/baglanti dizesi, SSO sirri, tam Windows kullanici profil yolu,
#   ham yuklenen dosya icerigi, hassas prompt) artifact'a yazilmasin.
#
#   Bu dosya BILEREK ASCII-guvenlidir (Turkce ozel karakter yok). Operasyonel
#   giris noktasi betikleri POSIX/C veya Windows/Turkce locale altinda
#   source(...) edilirken sessiz kirpilmaya ugramamalidir. Diakritiksiz Turkce
#   yorum kullanin. Bu kisit tests/testthat/test-operational-soak-gate-contract.R
#   ile zorlanir.
#
#   Bu betik run_vm_evidence_gate.R'deki redaksiyon modelini izler ve genisletir.
# ==============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || is.na(x[1])) y else x

# Degerleri ASLA loglanmamasi gereken ortam degiskeni adlari.
soak_sensitive_env_names <- function() {
  c(
    "LOCAL_LLM_ENDPOINT", "LOCAL_LLM_API_KEY",
    "LANGFLOW_API_KEY", "LANGFLOW_BASE_URL",
    "DB_DSN", "DB_DSN_2", "DB_DSN_3", "DB_PASSWORD",
    "AI_KEYS_MASTER", "MERGEN_DEFAULT_API_KEY",
    "SSO_KEYCLOAK_URL", "SSO_CLIENT_ID", "SSO_CLIENT_SECRET",
    "LOCAL_TTS_API_KEY", "IMAGE_GEN_ENDPOINT",
    "SERVICE_DESK_API_KEY_URL", "SERVICE_DESK_RATE_LIMIT_URL",
    "MERGEN_BROWSER_BIN", "MERGEN_SOAK_REAL_API_KEY",
    "MERGEN_SOAK_REAL_ENDPOINT_URL"
  )
}

# Ham bir girdiden kararli ve kisa bir takma ad uretir. Ham deger ASLA donmez.
# Ornek: sk-test-user001 -> key_3f9a1c0b2d
soak_pseudonym <- function(raw, prefix = "h") {
  raw <- as.character(raw %||% "")
  if (!nzchar(raw)) {
    return(sprintf("%s_empty", prefix))
  }
  digest_hex <- tryCatch(
    {
      if (requireNamespace("openssl", quietly = TRUE)) {
        as.character(openssl::sha256(enc2utf8(raw)))
      } else if (requireNamespace("digest", quietly = TRUE)) {
        digest::digest(enc2utf8(raw), algo = "sha256")
      } else {
        # Son care: tasinabilir, kriptografik olmayan ozet (yalniz takma ad icin).
        sprintf("%08x", sum(utf8ToInt(raw) * seq_along(utf8ToInt(raw))))
      }
    },
    error = function(e) "00000000"
  )
  sprintf("%s_%s", prefix, substr(digest_hex, 1, 10))
}

# Sahte kullanici anahtari pseudonimi (key_<hash>). Asla ham anahtar dondurmez.
soak_key_pseudonym <- function(raw_key) soak_pseudonym(raw_key, prefix = "key")

# Oturum/kullanici takma adi.
soak_session_pseudonym <- function(raw) soak_pseudonym(raw, prefix = "sess")

# Tek bir metin parcasini redakte eder. Sirasi onemlidir: once en uzun bilinen
# ortam degerleri, sonra desen-tabanli maskeleme.
soak_redact_text <- function(text) {
  out <- paste(as.character(text %||% ""), collapse = "\n")
  if (!nzchar(out)) {
    return("")
  }

  # 1) Bilinen hassas ortam degerleri (en uzundan kisaya, fixed maskeleme).
  values <- Sys.getenv(soak_sensitive_env_names(), unset = "")
  values <- unique(values[nzchar(values)])
  if (length(values) > 0L) {
    values <- values[order(nchar(values), decreasing = TRUE)]
    for (v in values) {
      out <- gsub(v, "<hidden>", out, fixed = TRUE)
    }
  }

  # 2) Authorization basliklari ve bearer tokenlar.
  out <- gsub("(?i)(authorization\\s*[:=]\\s*)(bearer\\s+)?[A-Za-z0-9._~+/=-]{6,}",
              "\\1<hidden>", out, perl = TRUE)
  out <- gsub("(?i)bearer\\s+[A-Za-z0-9._~+/=-]{6,}", "Bearer <hidden>", out, perl = TRUE)

  # 3) OpenAI tarzi anahtarlar (sk-... ve sk-test-...).
  out <- gsub("sk-[A-Za-z0-9_-]{3,}", "<hidden-key>", out, perl = TRUE)

  # 4) Genel key=value sirlari.
  out <- gsub(
    "(?i)\\b(api[_-]?key|api_token|access[_-]?token|token|password|passwd|pwd|secret|client_secret|master_key)\\b(\\s*[:=]\\s*)([\"']?)[^\"'\\s,}]{3,}\\3",
    "\\1\\2<hidden>", out, perl = TRUE
  )

  # 5) JWT benzeri uc parcali tokenlar.
  out <- gsub("eyJ[A-Za-z0-9_-]{5,}\\.[A-Za-z0-9_-]{5,}\\.[A-Za-z0-9_-]{5,}",
              "<hidden-jwt>", out, perl = TRUE)

  # 6) ODBC/DSN parola alanlari.
  out <- gsub("(?i)(pwd|password)\\s*=\\s*[^;\\s]+", "\\1=<hidden>", out, perl = TRUE)

  # 7) Windows kullanici profil yollari (C:\\Users\\<isim> -> maskeli).
  out <- gsub("(?i)([A-Z]:\\\\Users\\\\)[^\\\\\\r\\n\"']+", "\\1<user>", out, perl = TRUE)
  out <- gsub("(?i)(/home/)[^/\\r\\n\"']+", "\\1<user>", out, perl = TRUE)

  enc2utf8(out)
}

# Bir metni redakte EDILDIKTEN SONRA hala sir kalip kalmadigini tarar.
# Geriye tespit edilen olasi sizinti sayisini doner (0 ideal). Kendi
# kendini-dogrulama icin kullanilir.
soak_scan_for_secrets <- function(text) {
  out <- paste(as.character(text %||% ""), collapse = "\n")
  if (!nzchar(out)) {
    return(0L)
  }

  hits <- 0L
  patterns <- c(
    # Ham sk- anahtarlari (maskelenmemis).
    "sk-[A-Za-z0-9_-]{3,}",
    # Bearer + gercek token karakterleri.
    "(?i)bearer\\s+[A-Za-z0-9._~+/=-]{6,}",
    # JWT.
    "eyJ[A-Za-z0-9_-]{5,}\\.[A-Za-z0-9_-]{5,}\\.[A-Za-z0-9_-]{5,}"
  )
  for (p in patterns) {
    m <- gregexpr(p, out, perl = TRUE)[[1]]
    if (length(m) > 0L && m[1] != -1L) {
      hits <- hits + length(m)
    }
  }

  # Bilinen ham ortam degerleri (uzun olanlar) hala goruluyor mu?
  values <- Sys.getenv(soak_sensitive_env_names(), unset = "")
  values <- unique(values[nzchar(values) & nchar(values) >= 8L])
  for (v in values) {
    if (grepl(v, out, fixed = TRUE)) {
      hits <- hits + 1L
    }
  }

  as.integer(hits)
}

# Windows loglari bazen native encoding ile gelir; byte-safe okuyup UTF-8'e
# temizler (run_vm_evidence_gate.R ile ayni desen).
soak_read_text_file_safe <- function(path) {
  if (is.null(path) || !file.exists(path)) {
    return("")
  }
  size <- file.info(path)$size
  if (is.na(size) || size == 0L) {
    return("")
  }
  raw_bytes <- tryCatch(readBin(path, what = "raw", n = size), error = function(e) raw())
  if (length(raw_bytes) == 0L) {
    return("")
  }
  text <- tryCatch(rawToChar(raw_bytes), error = function(e) "")
  text <- iconv(text, from = "", to = "UTF-8", sub = "byte")
  if (is.na(text)) {
    return("")
  }
  enc2utf8(text)
}

# Bir dosyayi yerinde redakte eder (byte-safe oku, redakte et, UTF-8 yaz).
soak_redact_file <- function(path) {
  if (is.null(path) || !file.exists(path)) {
    return(invisible(FALSE))
  }
  raw_text <- soak_read_text_file_safe(path)
  writeLines(soak_redact_text(raw_text), path, useBytes = TRUE)
  invisible(TRUE)
}

# Bir dizindeki tum artifact dosyalarini redaksiyon kendi-dogrulamasindan
# gecirir. Geriye toplam olasi sizinti sayisini ve dosya basina detayi doner.
soak_redaction_self_check <- function(artifact_dir) {
  if (is.null(artifact_dir) || !dir.exists(artifact_dir)) {
    return(list(total_leaks = 0L, files = list(), checked = 0L))
  }
  files <- list.files(artifact_dir, recursive = TRUE, full.names = TRUE)
  # Ikili/log olmayan metin artifact'larini tara.
  per_file <- list()
  total <- 0L
  for (f in files) {
    text <- soak_read_text_file_safe(f)
    leaks <- soak_scan_for_secrets(text)
    if (leaks > 0L) {
      per_file[[basename(f)]] <- leaks
      total <- total + leaks
    }
  }
  list(total_leaks = as.integer(total), files = per_file, checked = length(files))
}
