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

# --- GÜVENLİ NZCHAR KONTROLÜ ---
# Tek satırda NULL, NA ve boş karakter kontrolü yapar
safe_nzchar <- function(x) {
  is.character(x) && length(x) > 0 && !is.na(x[1]) && nzchar(x[1])
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

  uid <- suppressWarnings(as.integer(session_uid %||% fallback_uid %||% 0L))
  if (is.na(uid)) uid <- 0L

  uid
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