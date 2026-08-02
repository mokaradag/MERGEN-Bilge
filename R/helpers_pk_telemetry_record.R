# ==============================================================================
# Dosya Yolu: R/helpers_pk_telemetry_record.R
# Açıklama: Proje ve Kaynak Analizi telemetri KAYDININ saf katmanı: soru
#           normalizasyonu, sunucu anahtarlı parmak izi, alan kırpma ve
#           MB_Analiz_Log satırının kurulması.
#
# Bu dosya BİLEREK saftır: DB bağlantısı açmaz, sorgu çalıştırmaz, Shiny/
# reactive durum okumaz. Yazım/hazırlık tespiti R/helpers_pk_telemetry.R
# içindedir. Bölme, gizlilik kararının DB olmadan test edilebilmesini sağlar
# ve sürdürülebilirlik bütçesini korur.
#
# GİZLİLİK:
#   MERGEN_PK_LOG_QUESTION_TEXT=false (varsayılan) iken ham soru metni
#   YAZILMAZ; yerine sunucu anahtarlı (HMAC-SHA256) parmak izi saklanır. Düz
#   (anahtarsız) özet YETMEZ: sorular sonlu bir proje sözlüğünden geldiği için
#   düşük entropilidir ve tabloyu okuyabilen biri aday soruları özetleyip
#   eşleştirebilir. Anahtar yoksa parmak izi de yazılmaz.
#   Bu dosya hiçbir koşulda anahtarın kendisini kayda veya loga koymaz.
# ==============================================================================

# Parmak izi öncesi soru normalizasyonu. Amaç, aynı sorunun yazım/boşluk
# farklarına rağmen aynı parmak izini üretmesidir. Türkçe küçültme yerel
# ayardan bağımsız olsun diye stringi (ICU) kullanılır; yoksa küçültme atlanır
# (gruplama kalitesi düşer, güvenlik etkilenmez).
.pk_telemetry_normalize_question <- function(question) {
  txt <- tryCatch(as.character(question)[1], error = function(e) NA_character_)
  if (is.null(txt) || length(txt) != 1L || is.na(txt)) return("")

  txt <- enc2utf8(txt)

  if (requireNamespace("stringi", quietly = TRUE)) {
    txt <- tryCatch(
      stringi::stri_trans_tolower(stringi::stri_trans_nfc(txt), locale = "tr"),
      error = function(e) txt
    )
  }

  trimws(gsub("[[:space:]]+", " ", txt))
}

#' Sorunun sunucu anahtarlı parmak izini üret
#'
#' @return `list(fingerprint=, key_id=)`; anahtar yoksa her ikisi de NA.
pk_telemetry_question_fingerprint <- function(question) {
  empty <- list(fingerprint = NA_character_, key_id = NA_character_)

  key <- tryCatch(pk_config_resolve("MERGEN_PK_TELEMETRY_HMAC_KEY"), error = function(e) "")
  if (is.null(key) || !nzchar(as.character(key)[1])) return(empty)

  normalized <- .pk_telemetry_normalize_question(question)
  if (!nzchar(normalized)) return(empty)
  if (!requireNamespace("openssl", quietly = TRUE)) return(empty)

  digest_hex <- tryCatch(
    as.character(openssl::sha256(charToRaw(normalized), key = as.character(key)[1])),
    error = function(e) NA_character_
  )
  if (is.na(digest_hex) || !nzchar(digest_hex)) return(empty)

  key_id <- tryCatch(pk_config_resolve("MERGEN_PK_TELEMETRY_HMAC_KEY_ID"), error = function(e) "k1")

  list(fingerprint = digest_hex, key_id = as.character(key_id)[1])
}

.pk_tel_int <- function(x) {
  if (is.null(x) || length(x) != 1L) return(NA_integer_)
  val <- suppressWarnings(as.integer(x))
  if (length(val) != 1L) return(NA_integer_)
  val
}

.pk_tel_chr <- function(x, max_chars = 400L) {
  if (is.null(x) || length(x) == 0L) return(NA_character_)
  txt <- tryCatch(as.character(x)[1], error = function(e) NA_character_)
  if (is.na(txt)) return(NA_character_)
  if (nchar(txt) > max_chars) txt <- substr(txt, 1L, max_chars)
  txt
}

# Istanbul yerel saati (sabit +3). MB_Ortak* ailesindeki .oo_db_now() ile aynı
# sözleşme: değer UTC biçiminde formatlanır ama +3 kaydırılmış saklanır, böylece
# SSMS'te Türkiye saatiyle okunur.
.PK_TEL_TZ_OFFSET_SN <- 3L * 3600L

.pk_telemetry_now <- function() {
  format(Sys.time() + .PK_TEL_TZ_OFFSET_SN, "%Y-%m-%d %H:%M:%S", tz = "UTC")
}

#' Telemetri satırını kur (saf; DB'ye dokunmaz)
#'
#' Gizlilik kararı burada verilir, böylece testler DB olmadan da kanıtlayabilir.
#' Yalnızca tanımlı alanlar taşınır; girdideki keyfi alanlar kayda GEÇMEZ.
pk_telemetry_build_record <- function(info) {
  info <- if (is.list(info)) info else list()

  log_question <- isTRUE(tryCatch(
    pk_config_resolve("MERGEN_PK_LOG_QUESTION_TEXT"),
    error = function(e) FALSE
  ))

  fingerprint <- pk_telemetry_question_fingerprint(info$question)

  codes <- info$degradation_codes %||% character(0)
  codes <- if (length(codes) > 0) paste(as.character(codes), collapse = ",") else NA_character_

  list(
    IstekID            = .pk_tel_chr(info$request_id, 64L),
    KullaniciID        = .pk_tel_int(info$user_id),
    KullaniciAdi       = .pk_tel_chr(info$username, 200L),
    Motor              = .pk_tel_chr(info$engine %||% "v1", 10L),
    DerinDusunme       = if (isTRUE(info$deep_thinking)) 1L else 0L,
    SoruMetni          = if (log_question) .pk_tel_chr(info$question, 4000L) else NA_character_,
    SoruParmakIzi      = fingerprint$fingerprint,
    ParmakIziAnahtarID = fingerprint$key_id,
    SecilenSorguID     = .pk_tel_chr(info$query_id, 64L),
    SecilenSorguAdi    = .pk_tel_chr(info$query_name, 400L),
    FiltreDurumu       = .pk_tel_chr(info$filter_status, 32L),
    FiltreSayisi       = .pk_tel_int(info$filter_count),
    SatirRlsOncesi     = .pk_tel_int(info$pre_rls_rows),
    SatirYetkiSonrasi  = .pk_tel_int(info$authorized_rows),
    SatirFiltreSonrasi = .pk_tel_int(info$filtered_rows),
    BozulmaKodlari     = .pk_tel_chr(codes, 400L),
    Sonuc              = .pk_tel_chr(info$outcome %||% "Basarili", 32L),
    ToplamSureMs       = .pk_tel_int(info$duration_ms),
    OlusturmaZamani    = .pk_telemetry_now()
  )
}

# Görünür Türkçe metinler ve teknik değerler AYRI normalize edilir; karışık
# parametre listesine toplu mojibake onarımı UYGULANMAZ (CLAUDE.md sözleşmesi).
.pk_telemetry_normalize_record <- function(record) {
  visible_cols <- c("SoruMetni", "SecilenSorguAdi", "KullaniciAdi")
  technical_cols <- c(
    "IstekID", "Motor", "SoruParmakIzi", "ParmakIziAnahtarID",
    "SecilenSorguID", "FiltreDurumu", "BozulmaKodlari", "Sonuc"
  )

  apply_norm <- function(cols, fn_name) {
    if (!exists(fn_name, mode = "function", inherits = TRUE)) return(invisible(NULL))
    fn <- get(fn_name, mode = "function", inherits = TRUE)

    for (col in cols) {
      if (!is.na(record[[col]])) {
        record[[col]] <<- tryCatch(fn(record[[col]]), error = function(e) record[[col]])
      }
    }
    invisible(NULL)
  }

  apply_norm(visible_cols, "normalize_db_visible_value")
  apply_norm(technical_cols, "normalize_db_technical_value")

  record
}
