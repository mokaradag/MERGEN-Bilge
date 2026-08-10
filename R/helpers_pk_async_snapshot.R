# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_snapshot.R
# Açıklama: Faz 6 (§5.10) — İŞÇİ-GÜVENLİ ANLIK GÖRÜNTÜ sözleşmesi.
#
# Bu dosya `R/helpers_pk_async_request.R` içinden BÖLÜNMÜŞTÜR: tek dosya bakım
# ratchet'inin 25-fonksiyon tavanını tüketiyordu. Ayrım aynı zamanda daha iyi
# bir sınır: "hangi VERİ işçiye taşınabilir" ile "istek nedir / gönderilebilir
# mi" farklı sorumluluklardır.
#
# SAFTIR: Shiny/reaktif/DB/ağ ÇAĞIRMAZ. Yalnızca düz veri doğrular/üretir.
#
# TEMEL SÖZLEŞME: bir Shiny `session`, `reactiveValues`, reaktif ifade, dış
# işaretçi (`externalptr`) veya DB bağlantısı işçiye ASLA serileştirilmez.
# `pk_async_validate_request()` bunu savunmacı biçimde DOĞRULAR; sessiz bir
# sızıntı, üretimde işçi tarafında anlaşılmaz serileştirme hatalarına dönüşür.
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

# `chat_add_message()` normal asistan turlarını `type = "ai"` olarak saklar ve
# `role` alanını DOLDURMAZ. Rolü körlemesine "user" yapmak, v2 seçim durumunun
# sohbet imzasını (`role %||% type`) senkron yoldan FARKLI üretirdi; aynı
# konuşma senkron/asenkron arasında geçiş yaptığında önceki sorgu/netleştirme
# bağlamı kaybolurdu.
.pk_async_message_role <- function(mesaj) {
  rol <- as.character(mesaj$role %||% "")[1]
  if (!is.na(rol) && nzchar(rol)) return(rol)

  tip <- as.character(mesaj$type %||% "")[1]
  if (is.na(tip)) tip <- ""
  if (tip %in% c("ai", "assistant")) return("assistant")
  if (nzchar(tip)) return(tip)
  "user"
}

# Skaler kimlikler İŞÇİ-GÜVENLİDİR ve v2 seçim durumu sözleşmesinin parçasıdır:
# `pk_select_chat_key()` kayan geçmiş penceresinde aynı sohbet anahtarını
# koruyabilmek için `db_id`/`id` alanlarını tercih eder.
.pk_async_message_scalar_id <- function(deger) {
  if (is.null(deger) || length(deger) != 1L) return(NULL)
  if (is.function(deger) || is.environment(deger) || is.list(deger)) return(NULL)
  ham <- tryCatch(as.character(deger)[1], error = function(e) NA_character_)
  if (is.na(ham) || !nzchar(ham)) return(NULL)
  ham
}

.pk_async_plain_history <- function(chat_history) {
  if (!is.list(chat_history) || length(chat_history) == 0L) return(list())

  lapply(chat_history, function(mesaj) {
    if (!is.list(mesaj)) return(list(role = "user", content = as.character(mesaj)[1]))
    cikti <- list(
      role = .pk_async_message_role(mesaj),
      content = as.character(mesaj$content %||% "")[1],
      type = as.character(mesaj$type %||% "")[1]
    )
    kimlik <- .pk_async_message_scalar_id(mesaj$id)
    if (!is.null(kimlik)) cikti$id <- kimlik
    db_kimlik <- .pk_async_message_scalar_id(mesaj$db_id)
    if (!is.null(db_kimlik)) cikti$db_id <- db_kimlik
    cikti
  })
}

#' Ana süreçte çözülmüş PK yapılandırmasının DÜZ anlık görüntüsü
#'
#' Kalıcı PSOCK işçisi AYRI bir R oturumudur; ana süreçteki `options()`
#' basamağı orada YOKTUR. Anlık görüntü alınmazsa işçi `MERGEN_PK_MAX_RESULT_MB`
#' gibi güvenlik sınırlarını sessizce yerleşik varsayılana düşürebilir. Gizli
#' anahtarlar DIŞARIDA bırakılır; sır işçiye taşınmaz.
pk_async_config_snapshot <- function() {
  if (!exists("pk_config_spec", inherits = TRUE) ||
      !exists("pk_config_resolve", mode = "function", inherits = TRUE)) {
    return(list())
  }

  spec <- get("pk_config_spec", inherits = TRUE)
  if (!is.list(spec)) return(list())

  cikti <- list()
  for (anahtar in names(spec)) {
    if (isTRUE(spec[[anahtar]]$secret)) next
    # Motor kipi ve async bayrağı DIŞARIDA bırakılır: ikisi de isteğin KENDİ
    # alanlarıyla açıkça taşınır ve işçi onları ayrıca sabitler. Anlık görüntü
    # üzerinden İKİNCİ bir kez kurulmaları, iç içe geri yükleme sırası
    # yüzünden işçi çıkışında süreç durumunu kirletirdi.
    if (anahtar %in% c("MERGEN_PK_ENGINE", "MERGEN_PK_ASYNC")) next
    deger <- tryCatch(pk_config_resolve(anahtar), error = function(e) NULL)
    if (is.null(deger) || length(deger) != 1L) next
    if (is.function(deger) || is.environment(deger) || is.list(deger)) next
    cikti[[anahtar]] <- deger
  }
  cikti
}

#' Anlık görüntüyü işçi sürecinde `options()` basamağına kur
#'
#' Öncelik zinciri KORUNUR: sorgu metadata'sı (1) ve ortam değişkeni (2) hâlâ
#' önce gelir; anlık görüntü yalnızca ana sürecin `options()` basamağını taşır.
#'
#' @return Geri yükleme için ESKİ option değerleri.
pk_async_config_install <- function(snapshot) {
  if (!is.list(snapshot) || length(snapshot) == 0L) return(list())
  if (!exists("pk_config_option_key", mode = "function", inherits = TRUE)) return(list())

  yeni <- list()
  for (anahtar in names(snapshot)) {
    ad <- tryCatch(pk_config_option_key(anahtar), error = function(e) NA_character_)
    if (is.na(ad) || !nzchar(ad)) next
    yeni[[ad]] <- snapshot[[anahtar]]
  }
  if (length(yeni) == 0L) return(list())

  eski <- do.call(options, yeni)
  eski
}

# Vekil oturumun `userData` içeriği: yalnızca ATOMİK, düz alanlar.
.PK_ASYNC_USER_DATA_FIELDS <- c(
  "system_username", "user_id", "auth_source", "auth_initialized",
  "sso_active", "current_chat_id"
)

.pk_async_plain_user_data <- function(snapshot) {
  if (!is.list(snapshot)) return(list())

  cikti <- list()
  for (alan in .PK_ASYNC_USER_DATA_FIELDS) {
    deger <- snapshot[[alan]]
    if (is.null(deger)) next
    if (is.function(deger) || is.environment(deger) || is.list(deger)) next
    if (length(deger) != 1L) next
    cikti[[alan]] <- deger
  }

  cikti
}

#' Ana süreçte vekil oturum için `userData` anlık görüntüsü topla
#'
#' Gerçek `session` nesnesi ASLA taşınmaz; yalnızca bu düz alanlar.
pk_async_capture_user_data <- function(session) {
  if (is.null(session)) return(list())
  ud <- tryCatch(session$userData, error = function(e) NULL)
  if (is.null(ud)) return(list())

  cikti <- list()
  for (alan in .PK_ASYNC_USER_DATA_FIELDS) {
    deger <- tryCatch(ud[[alan]], error = function(e) NULL)
    if (is.null(deger) || length(deger) != 1L) next
    if (is.function(deger) || is.environment(deger) || is.list(deger)) next
    cikti[[alan]] <- deger
  }

  cikti
}
