# ==============================================================================
# Dosya Yolu: R/helpers_runtime_metrics.R
# Açıklama: Süreç-içi (in-process), sır-güvenli, HAFİF çalışma-zamanı sayaçları.
#
# Soak/yük kanıtı attach modunda AYRI bir süreçten alınır; o yüzden uygulamanın
# iç sayaçları (kök sayfa önbellek isabeti, backpressure reddi, vb.) yük
# sürücüsünden GÖRÜNMEZ. Bu modül, bu sayaçları süreç içinde toplar ve sağlık/
# hazırlık uç noktası (R/helpers_app_http_routes.R) üzerinden yalnızca SAYISAL,
# sır içermeyen bir anlık görüntü olarak sunar. Böylece operatör/yük-dengeleyici
# uygulama-tarafı davranışı dürüstçe gözlemleyebilir.
#
# Tasarım sözleşmesi:
#   - Yalnızca SAYISAL sayaç/gauge tutar; ham metin/sır/DSN/anahtar TUTMAZ.
#   - İsimler ASCII'ye sıkıştırılır (sır sızıntısı ve log gürültüsü önlenir).
#   - Saf yardımcılardır: source-time'da Shiny/ağ/DB erişimi yapmaz; izole
#     testlerde tek başına source edilebilir.
#   - Tüm tüketiciler bu modülü guard'lı `exists(...)` ile çağırır; böylece
#     bağımsız test edilebilirlikleri korunur.
# ==============================================================================

# Çalışma-zamanı sayaç durumu (global ortamı kirletmemek için iç ortam).
.mergen_runtime_metrics <- new.env(parent = emptyenv())
.mergen_runtime_metrics$counters <- list()
.mergen_runtime_metrics$gauges <- list()
.mergen_runtime_metrics$started_at <- as.numeric(Sys.time())

# İsim normalizasyonu: yalnızca ASCII harf/rakam/alt-çizgi/nokta/tire. Sır-benzeri
# içerik metrik adına asla yazılmamalıdır; bu yine de ek bir güvenlik kemeridir.
.mergen_runtime_metric_key <- function(name) {
  key <- tryCatch(as.character(name)[1], error = function(e) "")
  if (is.na(key) || !nzchar(key)) return("unknown")
  key <- gsub("[^A-Za-z0-9_.-]", "_", key)
  substr(key, 1L, 60L)
}

# Bir sayaç değerini artırır (varsayılan +1). Negatif/NA `by` yok sayılır.
mergen_runtime_metric_inc <- function(name, by = 1L) {
  key <- .mergen_runtime_metric_key(name)
  step <- suppressWarnings(as.numeric(by)[1])
  if (!is.finite(step)) step <- 1
  st <- .mergen_runtime_metrics
  current <- st$counters[[key]]
  if (is.null(current) || !is.finite(current)) current <- 0
  st$counters[[key]] <- current + step
  invisible(st$counters[[key]])
}

# Anlık bir gauge değeri ayarlar (ör. o an aktif istek sayısı).
mergen_runtime_metric_set_gauge <- function(name, value) {
  key <- .mergen_runtime_metric_key(name)
  val <- suppressWarnings(as.numeric(value)[1])
  if (!is.finite(val)) val <- 0
  .mergen_runtime_metrics$gauges[[key]] <- val
  invisible(val)
}

# Bir sayacın mevcut değerini döndürür (yoksa 0).
mergen_runtime_metric_get <- function(name) {
  key <- .mergen_runtime_metric_key(name)
  st <- .mergen_runtime_metrics
  val <- st$counters[[key]]
  if (is.null(val)) val <- st$gauges[[key]]
  if (is.null(val) || !is.finite(val)) 0 else val
}

# Sır-güvenli anlık görüntü: yalnızca sayısal sayaç/gauge ve süreç uptime'ı.
mergen_runtime_metrics_snapshot <- function() {
  st <- .mergen_runtime_metrics
  uptime <- as.numeric(Sys.time()) - (st$started_at %||% as.numeric(Sys.time()))
  if (!is.finite(uptime) || uptime < 0) uptime <- 0
  list(
    uptime_sec = round(uptime, 1),
    counters = st$counters,
    gauges = st$gauges
  )
}

# Test/bakım: sayaçları ve gauge'ları sıfırlar (uptime başlangıcını korur).
mergen_runtime_metrics_reset <- function() {
  st <- .mergen_runtime_metrics
  st$counters <- list()
  st$gauges <- list()
  invisible(NULL)
}

# `%||%` bu dosya izole source edildiğinde de kullanılabilsin diye yerel guard.
if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}
