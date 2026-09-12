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

# --- ORTAM BAYRAĞI OKUYUCU (toleranslı, KAPALI-BAŞARISIZ) ---
# TRUE/T/1/yes/on/evet/açık ve FALSE/F/0/no/off/hayır/kapalı tanınır. Boş değer
# `default`, tanınmayan değer ise çağıranın GÜVENLİ tarafı olan `invalid` döner
# ve süreç başına BİR KEZ uyarır. Küçük harfe indirme yerelden bağımsızdır
# (Türkçe İ/ı).
.MERGEN_ENV_FLAG_UYARILAN <- new.env(parent = emptyenv())

mergen_env_flag <- function(name, default = FALSE, invalid = default) {
  raw <- Sys.getenv(name, unset = "")
  key <- trimws(as.character(raw)[1])
  if (is.na(key)) key <- ""
  key <- chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", key)
  # Türkçe harfler ASCII eşdeğerine katlanır: chartr yalnızca ASCII katladığı
  # için "AÇIK" değeri "aÇik" kalıyor ve hiçbir listeyle eşleşmiyordu.
  key <- chartr("ÇĞİÖŞÜçğıöşü", "cgiosucgiosu", key)
  if (!nzchar(key)) return(isTRUE(default))
  if (key %in% c("true", "t", "1", "yes", "y", "on", "evet", "acik")) return(TRUE)
  if (key %in% c("false", "f", "0", "no", "n", "off", "hayir", "kapali")) return(FALSE)
  # Aynı ad için uyarı tekrarlanmaz: MCP tablo okuyucusu gibi çağrı yolları bu
  # noktaya her istekte ulaşıp günlüğü aynı satırla dolduruyordu.
  # Anahtar YALNIZCA ortam değişkeni adıdır: ham değer de anahtara girince
  # değer değiştiğinde aynı ad için ikinci kez uyarılıyor ve günlük tekrarlıyordu.
  uyari_anahtari <- as.character(name)[1]
  if (!exists(uyari_anahtari, envir = .MERGEN_ENV_FLAG_UYARILAN, inherits = FALSE)) {
    assign(uyari_anahtari, TRUE, envir = .MERGEN_ENV_FLAG_UYARILAN)
    warning(sprintf(
      "%s ortam değişkeni geçersiz ('%s'); güvenli varsayılan (%s) kullanılıyor.",
      name, raw, if (isTRUE(invalid)) "TRUE" else "FALSE"
    ), call. = FALSE)
  }
  isTRUE(invalid)
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
# --- KANONİK KULLANICI KİMLİĞİ ---
# Kayıplı dönüşümü reddeder: `as.integer(1.9)` 1 değerine düşüyor ve sorgular
# YANLIŞ kullanıcı kapsamını kullanabiliyordu. Metin biçimde yalnızca saf ondalık
# basamaklar kabul edilir ("1e2" gibi bilimsel gösterim reddedilir).
mergen_canonical_user_id <- function(value) {
  if (is.null(value) || length(value) != 1L) return(0L)
  if (is.na(value)) return(0L)

  if (is.character(value)) {
    metin <- trimws(value)
    if (!nzchar(metin) || !grepl("^[0-9]+$", metin)) return(0L)
    uid <- suppressWarnings(as.integer(metin))
    return(if (is.na(uid) || uid <= 0L) 0L else uid)
  }

  # Mantıksal değer kimlik değildir: `TRUE` sessizce 1 numaralı kullanıcıya
  # dönüşüyordu (fail-closed).
  if (!is.numeric(value)) return(0L)
  sayi <- suppressWarnings(as.numeric(value))
  if (is.na(sayi) || !is.finite(sayi) || sayi <= 0) return(0L)
  # `all.equal()` TOLERANSLI kıyaslar: `2 + 1e-9` geçip `trunc()` ile 2L'ye
  # düşüyordu. Kanonik kimlik sözleşmesi TAM eşitlik ister.
  if (sayi != trunc(sayi)) return(0L)
  uid <- suppressWarnings(as.integer(trunc(sayi)))
  if (is.na(uid) || uid <= 0L) return(0L)
  uid
}

resolve_effective_user_id <- function(session = NULL, current_user_id = NULL) {
  session_uid <- NULL

  if (!is.null(session) && !is.null(session$userData)) {
    session_uid <- session$userData$user_id %||% NULL
  }

  fallback_uid <- resolve_runtime_value(current_user_id)

  normalize_uid <- function(value) mergen_canonical_user_id(value %||% 0L)

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
  s <- gsub("(?s)\\s*<tool_call>.*?</tool_call>\\s*", "", s, perl = TRUE)

  # Planlayıcı meta-cümlelerini kaldır (İngilizce kalıplar)
  s <- gsub("(?im)^(we need to .*|let'?s try.*|probably .*|i'?ll try.*|we will call.*|we will invoke.*|now produce the tool call\\.?|we need to produce a tool call\\.?)\\s*$", "", s, perl = TRUE)

  # Çoklu boş satırları tek satıra düşür
  s <- gsub("\n{3,}", "\n\n", s, perl = TRUE)
  trimws(s)
}