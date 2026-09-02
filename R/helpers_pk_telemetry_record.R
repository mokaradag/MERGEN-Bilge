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

  # BELGELENMİŞ "k1" VARSAYILANI HER BOŞ DEĞERDE UYGULANIR. `pk_config_resolve()`
  # yalnızca HATA yükseltirse yedeğe düşmek yetersizdi: `MERGEN_PK_TELEMETRY_HMAC_KEY_ID`
  # hiç ayarlanmadığında boş değer dönüyor ve `ParmakIziAnahtarID` BOŞ yazılıyordu;
  # anahtar rotasyonundan sonra hangi anahtarın eski satırları ürettiği bilinemezdi.
  # Uzunluk da `NVARCHAR(32)` sütununa göre sınırlanır.
  key_id <- tryCatch(pk_config_resolve("MERGEN_PK_TELEMETRY_HMAC_KEY_ID"), error = function(e) NULL)
  key_id <- suppressWarnings(as.character(key_id)[1])
  if (length(key_id) != 1L || is.na(key_id) || !nzchar(key_id)) key_id <- "k1"

  list(fingerprint = digest_hex, key_id = .pk_tel_chr(key_id, 32L))
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
  # GEÇERSİZ ÇOK BAYTLI METİN TÜM KAYDI DÜŞÜRMEZ (PR #705 incelemesi, P3).
  #
  # `.pk_tel_chr()` `.pk_telemetry_normalize_record()` ÖNCESİNDE çalışır, yani
  # HAM DB metnini alır. Değer UTF-8 etiketli ama bozuk baytlar taşıyorsa
  # (Windows'ta CP1254 kaynak verisi) `nchar()`/`substr()` "invalid multibyte
  # string" hatası verir; hata `pk_telemetry_build_record()` dışına kaçar ve
  # `pk_telemetry_log_analysis()` TÜM `MB_Analiz_Log` satırını atlardı. Tek bir
  # bozuk `KullaniciAdi` değeri bütün denetim kaydını siliyordu. Kırpma artık
  # kodlama hatasına toleranslıdır ve sorun O ALANLA sınırlı kalır.
  txt <- tryCatch(
    if (nchar(txt) > max_chars) substr(txt, 1L, max_chars) else txt,
    error = function(e) {
      temiz <- suppressWarnings(iconv(txt, to = "UTF-8", sub = ""))
      if (is.na(temiz)) return(NA_character_)
      substr(temiz, 1L, max_chars)
    }
  )
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
# MB_Analiz_Log INSERT'inin kullandığı TAM sütun kümesi (kayıt alan sırasıyla).
# Hazırlık probu bu kümeyi doğrular: yalnızca `AnalizLogID` bakılırsa YENİ bir
# sütun eklenmeden önce oluşturulmuş ESKİ bir tablo "hazır" sayılır, sonra her
# analiz aynı INSERT'i deneyip başarısız olur ve telemetri satırları hiç yazılmaz.
.PK_TELEMETRY_INSERT_COLUMNS <- c(
  "IstekID", "KullaniciID", "KullaniciAdi", "Motor", "DerinDusunme",
  "SoruMetni", "SoruParmakIzi", "ParmakIziAnahtarID", "SecilenSorguID",
  "SecilenSorguAdi", "FiltreDurumu", "FiltreSayisi", "SatirRlsOncesi",
  "SatirYetkiSonrasi", "SatirFiltreSonrasi", "BozulmaKodlari", "Sonuc",
  "ToplamSureMs", "OlusturmaZamani"
)

#' Hazırlık probunun doğrulaması gereken sütunlar
#'
#' Kimlik sütunu (`AnalizLogID`) INSERT listesinde yer almaz ama tablonun
#' varlığını kanıtlar; bu yüzden projeksiyona o da eklenir.
#'
#' @return Karakter vektörü.
pk_telemetry_required_columns <- function() {
  c("AnalizLogID", .PK_TELEMETRY_INSERT_COLUMNS)
}

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
