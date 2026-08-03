# ==============================================================================
# Dosya Yolu: R/helpers_pk_config.R
# Açıklama: Proje ve Kaynak Analizi yapılandırma çözümleyicisi. Bu araçtaki
#           hiçbir eşik/zaman aşımı/sınır sabit kodlanmaz; tümü tek bir
#           öncelik sırasıyla çözülür:
#
#             sorgu bazlı metadata -> .Renviron ortam değişkeni -> options()
#             -> yerleşik varsayılan
#
#           Dosya BİLEREK saf ve worker güvenlidir: Shiny/reactive/DB/ağ
#           bağımlılığı yoktur ve ortam değerleri future worker içinde
#           doğrudan Sys.getenv() ile okunur (kapanış serileştirilmez).
#
# Not: Faz 0 yalnızca gerçekten TÜKETTİĞİ anahtarları kaydeder. Örneğin
#      MERGEN_PK_FILTER_TIMEOUT_SEC burada YOKTUR; onu Faz 0'da tüketmek v1
#      motorunun filtre sonuçlarını değiştirirdi ve bu, master planın §10
#      motor sınırı sözleşmesine aykırıdır.
# ==============================================================================

# Desteklenen anahtarların tek kaynağı. Yeni faz yeni anahtar eklerken bu
# listeye girdi ekler; çözümleyici kodu değişmez.
pk_config_spec <- list(
  MERGEN_PK_ENGINE = list(
    type = "character",
    default = "v1",
    allowed = c("v1", "v2")
  ),
  MERGEN_PK_TELEMETRY = list(
    type = "logical",
    default = TRUE
  ),
  MERGEN_PK_LOG_QUESTION_TEXT = list(
    type = "logical",
    default = FALSE
  ),
  # Gizli değer: yalnızca varlığı/uzunluğu raporlanabilir, değeri asla loglanmaz.
  MERGEN_PK_TELEMETRY_HMAC_KEY = list(
    type = "character",
    default = "",
    secret = TRUE
  ),
  # Anahtar rotasyonu etiketi; parmak izinin yanında saklanır ki rotasyondan
  # sonra eski satırlar hangi anahtarla üretildiği bilinerek yorumlanabilsin.
  MERGEN_PK_TELEMETRY_HMAC_KEY_ID = list(
    type = "character",
    default = "k1"
  ),
  # Faz 3a: satır tavanı. Sorgu metadata'sındaki `row_cap` alanı bu global
  # değeri EZER (öncelik zinciri gereği), böylece ağır bir finans sorgusu kod
  # değişikliği olmadan kendi tavanını taşıyabilir. Bu, metadata katmanının
  # Tier-0 geri düşüşüdür: sorgu `row_cap` bildirmiyorsa buradaki değer geçerlidir.
  MERGEN_PK_ROW_CAP = list(
    type = "integer",
    default = 50000L,
    min = 1L
  )
)

# MERGEN_PK_TELEMETRY -> "telemetry" (sorgu metadata alan adı)
pk_config_meta_key <- function(key) {
  tolower(sub("^MERGEN_PK_", "", as.character(key)[1]))
}

# MERGEN_PK_TELEMETRY -> "mergen.pk.telemetry" (options() adı)
pk_config_option_key <- function(key) {
  paste0("mergen.pk.", pk_config_meta_key(key))
}

# Mantıksal değer ayrıştırma; Türkçe operatör alışkanlıkları da desteklenir.
.pk_config_as_logical <- function(value) {
  if (is.logical(value) && length(value) == 1L && !is.na(value)) return(value)

  txt <- tolower(trimws(as.character(value)[1]))
  if (is.na(txt) || !nzchar(txt)) return(NULL)

  if (txt %in% c("true", "t", "1", "yes", "y", "on", "evet", "acik", "açık")) return(TRUE)
  if (txt %in% c("false", "f", "0", "no", "n", "off", "hayir", "hayır", "kapali", "kapalı")) return(FALSE)

  NULL
}

# Tam sayı ayrıştırma; sınır dışı/çözümlenemeyen değer NULL döner (varsayılana düşer).
.pk_config_as_integer <- function(value, spec) {
  num <- suppressWarnings(as.numeric(as.character(value)[1]))
  if (length(num) != 1L || is.na(num) || !is.finite(num)) return(NULL)

  out <- as.integer(round(num))
  if (!is.null(spec$min) && out < spec$min) return(NULL)
  if (!is.null(spec$max) && out > spec$max) return(NULL)

  out
}

.pk_config_as_character <- function(value, spec) {
  txt <- as.character(value)[1]
  if (length(txt) != 1L || is.na(txt)) return(NULL)

  txt <- trimws(txt)
  # Boş metin yalnızca varsayılanı da boş olan anahtarlarda geçerli sayılır;
  # aksi halde "tanımsız" kabul edilip bir alt önceliğe düşülür.
  if (!nzchar(txt) && nzchar(spec$default %||% "")) return(NULL)
  if (!is.null(spec$allowed) && !(txt %in% spec$allowed)) return(NULL)

  txt
}

# Ham bir adayı anahtarın tipine göre doğrular. Geçersizse NULL döner ki
# çözümleyici bir sonraki önceliğe geçebilsin (sessiz varsayılana düşme).
.pk_config_coerce <- function(value, spec) {
  if (is.null(value)) return(NULL)
  if (length(value) == 0L) return(NULL)

  switch(
    spec$type %||% "character",
    logical   = .pk_config_as_logical(value),
    integer   = .pk_config_as_integer(value, spec),
    character = .pk_config_as_character(value, spec),
    NULL
  )
}

#' Yapılandırma değerini öncelik sırasıyla çöz
#'
#' @param key Anahtar adı (örn. "MERGEN_PK_TELEMETRY").
#' @param query_meta Seçilen sorgunun metadata listesi (opsiyonel). Sorgu bazlı
#'   değer global ayarı EZER; böylece ağır bir sorgu kendi sınırını taşıyabilir.
#' @return Anahtarın tipine uygun tek elemanlı değer.
pk_config_resolve <- function(key, query_meta = NULL) {
  key <- as.character(key)[1]
  spec <- pk_config_spec[[key]]

  if (is.null(spec)) {
    stop(sprintf("pk_config_resolve: tanimsiz yapilandirma anahtari '%s'.", key), call. = FALSE)
  }

  # 1) Sorgu bazlı metadata
  if (is.list(query_meta)) {
    candidate <- .pk_config_coerce(query_meta[[pk_config_meta_key(key)]], spec)
    if (!is.null(candidate)) return(candidate)
  }

  # 2) Ortam değişkeni (worker güvenli: doğrudan Sys.getenv)
  env_raw <- Sys.getenv(key, unset = NA_character_)
  if (!is.na(env_raw)) {
    candidate <- .pk_config_coerce(env_raw, spec)
    if (!is.null(candidate)) return(candidate)
  }

  # 3) options()
  candidate <- .pk_config_coerce(getOption(pk_config_option_key(key), default = NULL), spec)
  if (!is.null(candidate)) return(candidate)

  # 4) Yerleşik varsayılan
  spec$default
}

#' Gizli olmayan yapılandırma özeti (tanılama için)
#'
#' Gizli anahtarlar için yalnızca varlık/uzunluk bilgisi döner; ham değer
#' hiçbir koşulda çıktıya girmez.
pk_config_safe_snapshot <- function() {
  out <- list()

  for (key in names(pk_config_spec)) {
    spec <- pk_config_spec[[key]]
    value <- tryCatch(pk_config_resolve(key), error = function(e) NULL)

    if (isTRUE(spec$secret)) {
      out[[key]] <- list(
        present = !is.null(value) && nzchar(as.character(value)[1]),
        nchar = if (is.null(value)) 0L else nchar(as.character(value)[1]),
        value = "<hidden>"
      )
    } else {
      out[[key]] <- value
    }
  }

  out
}
