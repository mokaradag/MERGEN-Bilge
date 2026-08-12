# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_snapshot_validate.R
# Açıklama: Faz 6 (§5.10) — İŞÇİ-GÜVENLİ ANLIK GÖRÜNTÜ DOĞRULAMASI.
#
# TEMEL SÖZLEŞME: bir Shiny `session`, `reactiveValues`, reaktif ifade, dış
# işaretçi (`externalptr`) veya DB bağlantısı işçiye ASLA serileştirilmez.
# `pk_async_validate_request()` bunu SAVUNMACI biçimde doğrular; sessiz bir
# sızıntı üretimde anlaşılmaz serileştirme hatalarına dönüşür.
#
# `R/helpers_pk_async_snapshot.R` içinden BÖLÜNMÜŞTÜR: orası düz veri ÜRETİMİ ve
# yapılandırma anlık görüntüsüdür ve 24-fonksiyon bakım tavanına dayanmıştı.
#
# SAFTIR: Shiny/reaktif/DB/ağ ÇAĞIRMAZ. Manifest sırası ZORUNLUDUR: bu dosya
# `helpers_pk_async_snapshot.R`'den ÖNCE yüklenir.
# ==============================================================================

# İşçiye ASLA gitmemesi gereken nesne sınıfları. `ShinySession` sınıf adı
# sürüme göre değişebildiği için ayrıca `environment` ve `DBIConnection`
# kontrolü de yapılır.
.PK_ASYNC_FORBIDDEN_CLASSES <- c(
  "ShinySession", "MockShinySession", "session_proxy",
  "reactivevalues", "reactive", "reactiveVal", "Observer",
  "DBIConnection", "Pool", "OdbcConnection", "SQLiteConnection"
)

# Süreç-yerel TUTAMAÇLAR. Sınıf adına güvenmek yetmez: `externalptr`, zayıf
# referans ve S4 nesneleri sınıf listesinde görünmeyebilir ama işçiye
# taşındıklarında ya geçersiz işaretçi olarak serileşir ya da canlı oturum/DB
# durumunu sınırın ötesine sürükler.
.PK_ASYNC_FORBIDDEN_TYPES <- c(
  "externalptr", "weakref", "environment", "closure", "builtin", "special",
  "bytecode", "pairlist", "S4", "promise", "..."
)

.pk_async_forbidden_reason <- function(x, path) {
  if (is.function(x)) return(sprintf("%s: function", path))
  if (is.environment(x)) return(sprintf("%s: environment", path))

  tip <- tryCatch(typeof(x), error = function(e) "unknown")
  if (tip %in% .PK_ASYNC_FORBIDDEN_TYPES) return(sprintf("%s: %s", path, tip))
  if (isTRUE(tryCatch(isS4(x), error = function(e) FALSE))) {
    return(sprintf("%s: S4", path))
  }

  siniflar <- tryCatch(class(x), error = function(e) character(0))
  carpisan <- intersect(siniflar, .PK_ASYNC_FORBIDDEN_CLASSES)
  if (length(carpisan) > 0L) {
    return(sprintf("%s: %s", path, paste(carpisan, collapse = "/")))
  }

  NULL
}

# Öznitelikler de taşınır: bir `externalptr` yalnızca `attr(x, "handle")`
# içinde saklanıyorsa liste özyinelemesi onu HİÇ görmezdi.
.pk_async_attribute_violations <- function(x, path, depth) {
  ozellikler <- tryCatch(attributes(x), error = function(e) NULL)
  if (!is.list(ozellikler) || length(ozellikler) == 0L) return(character(0))

  adlar <- names(ozellikler)
  if (is.null(adlar)) adlar <- rep("", length(ozellikler))
  atlanacak <- c("names", "class", "row.names", "dim", "dimnames", "levels", "comment")

  ihlaller <- character(0)
  for (i in seq_along(ozellikler)) {
    if (nzchar(adlar[i]) && adlar[i] %in% atlanacak) next
    alt_ad <- if (nzchar(adlar[i])) adlar[i] else paste0("[[", i, "]]")
    alt <- pk_async_validate_request(
      ozellikler[[i]], path = paste0(path, "@", alt_ad), depth = depth + 1L
    )
    if (!isTRUE(alt$safe)) ihlaller <- c(ihlaller, alt$violations)
  }
  ihlaller
}

#' Anlık görüntünün İŞÇİ-GÜVENLİ olduğunu doğrula (savunmacı)
#'
#' Sessiz bir oturum/reaktif/bağlantı sızıntısı, üretimde işçi tarafında
#' anlaşılmaz bir serileştirme hatasına dönüşür ve iptal/temizleme sözleşmesini
#' de bozar. Bu yüzden kontrol AÇIK ve TESTLİDİR.
#'
#' @return `list(safe = TRUE/FALSE, violations = <chr>)`.
pk_async_validate_request <- function(request, path = "request", depth = 0L) {
  ihlaller <- character(0)

  # Derinlik bütçesi aşıldığında alt ağaç DENETLENMEMİŞTİR. Onu "güvenli"
  # saymak, tam da denetimden kaçan yerde bir oturum/bağlantı sızıntısına izin
  # vermek olurdu; bu yüzden KAPALI BAŞARISIZ olunur.
  if (depth > 12L) {
    return(list(safe = FALSE, violations = sprintf("%s: depth_limit_exceeded", path)))
  }

  sebep <- .pk_async_forbidden_reason(request, path)
  if (!is.null(sebep)) return(list(safe = FALSE, violations = sebep))

  if (is.list(request) && length(request) > 0L) {
    adlar <- names(request)
    if (is.null(adlar)) adlar <- rep("", length(request))
    for (i in seq_along(request)) {
      alt_ad <- if (nzchar(adlar[i])) adlar[i] else paste0("[[", i, "]]")
      alt <- pk_async_validate_request(
        request[[i]], path = paste0(path, "$", alt_ad), depth = depth + 1L
      )
      if (!isTRUE(alt$safe)) ihlaller <- c(ihlaller, alt$violations)
    }
  }

  ihlaller <- c(ihlaller, .pk_async_attribute_violations(request, path, depth))

  list(safe = length(ihlaller) == 0L, violations = ihlaller)
}