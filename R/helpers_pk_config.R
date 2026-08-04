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
# Not: Bu dosya yalnızca gerçekten TÜKETİLEN anahtarları kaydeder. Örneğin
#      MERGEN_PK_FILTER_TIMEOUT_SEC burada YOKTUR; onu v1'de tüketmek motorun
#      filtre sonuçlarını değiştirirdi ve bu, master planın §10 motor sınırı
#      sözleşmesine aykırıdır.
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
  # Sorgu sonucu satır tavanı. Ağır bir sorgu kendi tavanını metadata ile
  # taşıyabilir; bu yüzden öncelik zincirinin ilk basamağı sorgu metadatasıdır.
  MERGEN_PK_ROW_CAP = list(
    type = "integer",
    default = 50000L,
    min = 1L
  ),
  # Faz 1 (D9): Filtre planı LLM zaman aşımı. v1'deki sabit 8 saniye fazla
  # agresifti ve zaman aşımı "filtre gerekmedi" ile ayırt edilemiyordu.
  # YALNIZCA v2 tüketir; v1 kendi sabit değerinde bırakılır ki motor sınırı
  # sözleşmesi (§10) bozulmasın.
  MERGEN_PK_FILTER_TIMEOUT_SEC = list(
    type = "integer",
    default = 20L,
    min = 1L
  ),
  # Faz 1 (D1/D2): Bu orandan fazla satır bırakan filtre "etkisiz" sayılır ve
  # köken kaydında böyle raporlanır.
  MERGEN_PK_NOOP_FILTER_RATIO = list(
    type = "double",
    default = 0.95,
    min = 0,
    max = 1
  ),
  # Faz 1 (D7): Modele giden TÜM yükün (özet + tablolar + örnek satır JSON'u)
  # karakter bütçesi. Eski kod yalnızca özet metnini ölçüyordu.
  MERGEN_PK_PROMPT_CHAR_BUDGET = list(
    type = "integer",
    default = 120000L,
    min = 1000L
  ),
  # --- Faz 2 (§5.7): analiz paketi ----------------------------------------
  # Kategorik sütun başına gösterilen ilk-K değer. Eski özet yalnızca ilk beş
  # kategorik sütunu ve her birinin YALNIZCA ilk değerini veriyordu (D17).
  MERGEN_PK_TOPK_CATEGORIES = list(
    type = "integer",
    default = 10L,
    min = 1L
  ),
  # "Diğer" toplamasından önce gösterilen grup sayısı.
  MERGEN_PK_GROUP_TOPN = list(
    type = "integer",
    default = 15L,
    min = 1L
  ),
  # Pakete giren temsilî örnek satır sayısı (ilk-N + son-N + uç değer +
  # tabakalı). Eski yol `head(data, 500)` ile KONUMSAL YANLI idi (D18).
  MERGEN_PK_SAMPLE_ROWS = list(
    type = "integer",
    default = 30L,
    min = 1L
  ),
  # Sabit tohum -> yeniden üretilebilir tabakalı örnek.
  MERGEN_PK_SAMPLE_SEED = list(
    type = "integer",
    default = 42L
  ),
  # --- Faz 2 (§5.8): yanıt kompozisyonu eşikleri --------------------------
  MERGEN_PK_INLINE_MAX_ROWS = list(
    type = "integer",
    default = 15L,
    min = 1L
  ),
  MERGEN_PK_INLINE_MAX_COLS = list(
    type = "integer",
    default = 8L,
    min = 1L
  ),
  MERGEN_PK_DT_MAX_ROWS = list(
    type = "integer",
    default = 200L,
    min = 1L
  ),
  MERGEN_PK_INLINE_MAX_COLS_DT = list(
    type = "integer",
    default = 12L,
    min = 1L
  ),
  # Ek yolunda baloncukta gösterilen önizleme satırı.
  MERGEN_PK_PREVIEW_ROWS = list(
    type = "integer",
    default = 10L,
    min = 1L
  ),
  # --- Faz 2 (§5.9): dışa aktarım ----------------------------------------
  # TEK bir sayfa/parçadaki azami satır. Daha büyük sonuç ya doğrulanmış
  # numaralı parçalara bölünür ya da AÇIKÇA reddedilir; sessizce kırpılmaz.
  MERGEN_PK_EXPORT_MAX_ROWS = list(
    type = "integer",
    default = 100000L,
    min = 1L
  ),
  # Parça tavanı. Aşılırsa dışa aktarım reddedilir ve kullanıcıdan sorusunu
  # daraltması istenir.
  MERGEN_PK_EXPORT_MAX_PARTS = list(
    type = "integer",
    default = 20L,
    min = 1L
  ),
  # --- Faz 2 (§5.11): sayısal köken doğrulaması ---------------------------
  # `log` ile başlanır: gerçek yanlış-pozitif oranı VM'de ölçülmeden `warn`
  # veya `block` kipine geçilmez.
  MERGEN_PK_NUMERIC_PROVENANCE_MODE = list(
    type = "character",
    default = "log",
    allowed = c("off", "log", "warn", "block")
  )
)

# MERGEN_PK_TELEMETRY -> "telemetry" (sorgu metadata alan adı)
#
# Küçük harfe indirme yerelden BAĞIMSIZ olmalıdır: Türkçe Windows yerel ayarında
# `tolower("ID")` noktasız `ıd` üretir ve `..._HMAC_KEY_ID` anahtarı için hem
# metadata hem options() basamağı sessizce ıskalanır. Anahtar adları saf ASCII
# olduğundan A-Z ile sınırlı bir eşleme doğru ve yeterlidir.
pk_config_meta_key <- function(key) {
  chartr(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz",
    sub("^MERGEN_PK_", "", as.character(key)[1])
  )
}

# MERGEN_PK_TELEMETRY -> "mergen.pk.telemetry" (options() adı)
pk_config_option_key <- function(key) {
  paste0("mergen.pk.", pk_config_meta_key(key))
}

# Mantıksal değer ayrıştırma; Türkçe operatör alışkanlıkları da desteklenir.
.pk_config_as_logical <- function(value) {
  if (is.logical(value) && length(value) == 1L && !is.na(value)) return(value)
  if (length(value) != 1L) return(NULL)

  txt <- tolower(trimws(as.character(value)[1]))
  if (is.na(txt) || !nzchar(txt)) return(NULL)

  if (txt %in% c("true", "t", "1", "yes", "y", "on", "evet", "acik", "açık")) return(TRUE)
  if (txt %in% c("false", "f", "0", "no", "n", "off", "hayir", "hayır", "kapali", "kapalı")) return(FALSE)

  NULL
}

# Tam sayılar yuvarlanmaz. Kesirli, taşan veya birden çok değer geçersizdir.
.pk_config_as_integer <- function(value, spec) {
  if (length(value) != 1L) return(NULL)

  num <- suppressWarnings(as.numeric(as.character(value)[1]))
  if (length(num) != 1L || is.na(num) || !is.finite(num)) return(NULL)
  if (!identical(num, trunc(num))) return(NULL)
  if (num < -.Machine$integer.max || num > .Machine$integer.max) return(NULL)

  out <- as.integer(num)
  if (is.na(out)) return(NULL)
  if (!is.null(spec$min) && out < spec$min) return(NULL)
  if (!is.null(spec$max) && out > spec$max) return(NULL)

  out
}

# Ondalık değerler. Tam sayıdan ayrı tutulur; NaN/Inf ve aralık dışı reddedilir.
.pk_config_as_double <- function(value, spec) {
  if (length(value) != 1L) return(NULL)

  num <- suppressWarnings(as.numeric(as.character(value)[1]))
  if (length(num) != 1L || is.na(num) || !is.finite(num)) return(NULL)
  if (!is.null(spec$min) && num < spec$min) return(NULL)
  if (!is.null(spec$max) && num > spec$max) return(NULL)

  num
}

.pk_config_as_character <- function(value, spec) {
  if (length(value) != 1L) return(NULL)

  txt <- as.character(value)[1]
  if (is.na(txt)) return(NULL)

  txt <- trimws(txt)
  if (!nzchar(txt) && nzchar(spec$default %||% "")) return(NULL)
  if (!is.null(spec$allowed) && !(txt %in% spec$allowed)) return(NULL)

  txt
}

# Ham bir adayı anahtarın tipine göre doğrular. Geçersizse NULL döner ki
# çözümleyici bir sonraki önceliğe geçebilsin (sessiz varsayılana düşme).
.pk_config_coerce <- function(value, spec) {
  if (is.null(value) || length(value) == 0L) return(NULL)

  switch(
    spec$type %||% "character",
    logical   = .pk_config_as_logical(value),
    integer   = .pk_config_as_integer(value, spec),
    double    = .pk_config_as_double(value, spec),
    character = .pk_config_as_character(value, spec),
    NULL
  )
}

#' Etkin motor kipi ("v1" / "v2")
#'
#' Master plan §10: `v1` varsayılandır ve operatör VM'de doğrulayana kadar
#' öyle kalır. D1-D5, D7-D9 ve D12 YALNIZCA `v2` altında etkinleşir; RLS
#' kapalı başarısızlığı, salt-okunur SQL kapısı, ODBC redaksiyonu ve Faz 0
#' gözlemi ise bayraktan BAĞIMSIZ çalışır.
pk_engine_mode <- function(query_meta = NULL) {
  tryCatch(
    pk_config_resolve("MERGEN_PK_ENGINE", query_meta = query_meta),
    error = function(e) "v1"
  )
}

pk_engine_is_v2 <- function(query_meta = NULL) {
  identical(pk_engine_mode(query_meta), "v2")
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
      # `out[[key]] <- NULL` elemanı LISTEDEN SILER; çözülemeyen bir anahtar
      # bu yüzden raporda hiç görünmezdi. Tanılamada "yok" ile "çözülemedi"
      # ayrılabilsin diye açıkça NA yazılır.
      out[[key]] <- value %||% NA
    }
  }

  out
}
