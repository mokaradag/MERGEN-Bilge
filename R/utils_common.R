# ==============================================================================
# R/utils_common.R
# Dosya Yolu: R/utils_common.R
# Açıklama: Uygulama genelinde kullanılan temel yardımcı fonksiyonlar.
# NULL birleştirme operatörü, güvenli kontroller ve metin temizleyicileri içerir.
# global.R tarafından config_packages.R'den hemen sonra source() ile çağrılır.
# ==============================================================================

# --- NULL BİRLEŞTİRME OPERATÖRÜ ---
# Eğer sol taraf NULL ise sağ tarafı döndürür
`%||%` <- function(a, b) {
  if (is.null(a)) b else a
}

# --- UTF-8 METİN NORMALLEŞTİRİCİ ---
# Bozuk veya farklı kodlamadan gelen metinleri güvenli UTF-8'e çevirir.
normalize_utf8_text <- function(x) {
  if (is.null(x)) return("")
  if (length(x) == 0) return(character(0))

  x <- as.character(x)
  x[is.na(x)] <- ""

  donustur_tek <- function(deger) {
    if (length(deger) == 0 || identical(deger, "")) return("")

    denemeler <- c(
      tryCatch(suppressWarnings(iconv(deger, from = "",             to = "UTF-8", sub = "")), error = function(e) NA_character_),
      tryCatch(suppressWarnings(iconv(deger, from = "UTF-8",        to = "UTF-8", sub = "")), error = function(e) NA_character_),
      tryCatch(suppressWarnings(iconv(deger, from = "WINDOWS-1254", to = "UTF-8", sub = "")), error = function(e) NA_character_),
      tryCatch(suppressWarnings(iconv(deger, from = "latin1",       to = "UTF-8", sub = "")), error = function(e) NA_character_)
    )

    denemeler <- denemeler[!is.na(denemeler)]
    if (length(denemeler) == 0) return("")

    cikti <- denemeler[[1]]
    cikti <- sub("^\ufeff", "", cikti, perl = TRUE)
    Encoding(cikti) <- "UTF-8"
    cikti
  }

  vapply(x, donustur_tek, FUN.VALUE = character(1), USE.NAMES = FALSE)
}

# --- GÜVENLİ BOŞLUK TEMİZLEYİCİ ---
safe_trimws <- function(x) {
  temiz <- normalize_utf8_text(x)
  normalize_utf8_text(trimws(temiz))
}

# --- GÜVENLİ NZCHAR KONTROLÜ ---
safe_nzchar <- function(x) {
  if (!is.character(x) || length(x) == 0 || is.na(x[1])) return(FALSE)
  !identical(safe_trimws(x[1]), "")
}

# --- ÇAĞRI ANINDA DEĞER ÇÖZÜMLEYİCİ ---
# Parametre olarak sabit değer veya fonksiyon gelebilir.
# Fonksiyon geldiyse güvenli şekilde çağırır.
resolve_runtime_value <- function(x) {
  if (is.function(x)) {
    return(tryCatch(x(), error = function(e) NULL))
  }
  x
}

# --- ETKİN KULLANICI KİMLİĞİ ÇÖZÜMLEYİCİ ---
# Önce oturumdaki güncel kullanıcıyı, yoksa verilen fallback değeri kullanır.
# Böylece SSO akışında başlangıçtaki geçici kimlik yerine gerçek kullanıcıya ulaşılır.
resolve_effective_user_id <- function(session = NULL, current_user_id = NULL) {
  session_uid <- NULL

  if (!is.null(session) && !is.null(session$userData)) {
    session_uid <- session$userData$user_id %||% NULL
  }

  fallback_uid <- resolve_runtime_value(current_user_id)

  normalize_uid <- function(value) {
    uid <- suppressWarnings(as.integer(value %||% 0L))
    if (is.na(uid) || uid <= 0L) {
      return(0L)
    }
    uid
  }

  session_uid_int <- normalize_uid(session_uid)
  if (session_uid_int > 0L) {
    return(session_uid_int)
  }

  fallback_uid_int <- normalize_uid(fallback_uid)
  if (fallback_uid_int > 0L) {
    return(fallback_uid_int)
  }

  0L
}

# --- ZAMAN DAMGASI BİÇİMLENDİRİCİ ---
# Türkiye formatında (GG.AA.YYYY - SS:DD) zaman damgası üretir
format_timestamp <- function() {
  format(Sys.time(), "%d.%m.%Y - %H:%M")
}

# --- PLANLAYICI / AJAN META-METİN TEMİZLEYİCİ ---
# LLM yanıtlarından araç çağrısı kalıntılarını ve planlama cümlelerini temizler
strip_planner_text <- function(x) {
  # NULL veya character(0) güvenli kontrolü
  if (is.null(x)) return(x)
  if (!is.character(x) || length(x) == 0) return("")
  s <- x[1]
  if (!nzchar(s)) return(s)

  # JSON araç çağrısı kalıntılarını kaldır
  s <- gsub("\\{\\s*\"(tool|name)\"\\s*:\\s*\"[^\"]+\"[^{}]*\"arguments\"\\s*:\\s*\\{[^{}]*\\}\\s*\\}", "", s, perl = TRUE)
  s <- gsub("\\{\\s*\"action\"\\s*:\\s*\"[^\"]+\"[^{}]*\"parameters\"\\s*:\\s*\\{[^{}]*\\}\\s*\\}", "", s, perl = TRUE)
  s <- gsub("\\s*<tool_call>.*?</tool_call>\\s*", "", s, perl = TRUE)

  # Planlayıcı meta-cümlelerini kaldır (İngilizce kalıplar)
  s <- gsub("(?im)^(we need to .*|let'?s try.*|probably .*|i'?ll try.*|we will call.*|we will invoke.*|now produce the tool call\\.?|we need to produce a tool call\\.?)\\s*$", "", s, perl = TRUE)

  # Çoklu boş satırları tek satıra düşür
  s <- gsub("\n{3,}", "\n\n", s, perl = TRUE)
  trimws(s)
}