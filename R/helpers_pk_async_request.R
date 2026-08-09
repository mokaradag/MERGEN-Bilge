# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_request.R
# Açıklama: Faz 6 (§5.10) — işçiye taşınacak DÜZ, DEĞİŞTİRİLEMEZ istek anlık
#           görüntüsü, savunmacı işçi-güvenliği doğrulaması ve İSTEK-KİMLİĞİ
#           koruması.
#
# Bu dosya SAFTIR: Shiny/reaktif/DB/ağ ÇAĞIRMAZ. Yalnızca ana süreçte hazırlanan
# değerlerden düz veri üretir ve karar döndürür.
#
# TEMEL SÖZLEŞME: bir Shiny `session`, `reactiveValues`, reaktif ifade veya DB
# bağlantısı işçiye ASLA serileştirilmez. `pk_async_validate_request()` bunu
# savunmacı biçimde DOĞRULAR; sessiz bir sızıntı, üretimde işçi tarafında
# anlaşılmaz serileştirme hatalarına dönüşür.
#
# İşçi bootstrap sözleşmesi, oturum vekili ve globals paketi AYRI dosyadadır:
# `R/helpers_pk_async_bootstrap.R` (manifestte bu dosyadan ÖNCE yüklenir).
# ==============================================================================

# ------------------------------------------------------------------------------
# İSTEK ANLIK GÖRÜNTÜSÜ
# ------------------------------------------------------------------------------

# İşçiye ASLA gitmemesi gereken nesne sınıfları. `ShinySession` sınıf adı
# sürüme göre değişebildiği için ayrıca `environment` ve `DBIConnection`
# kontrolü de yapılır.
.PK_ASYNC_FORBIDDEN_CLASSES <- c(
  "ShinySession", "MockShinySession", "session_proxy",
  "reactivevalues", "reactive", "reactiveVal", "Observer",
  "DBIConnection", "Pool", "OdbcConnection", "SQLiteConnection"
)

.pk_async_forbidden_reason <- function(x, path) {
  if (is.function(x)) return(sprintf("%s: function", path))
  if (is.environment(x)) return(sprintf("%s: environment", path))

  siniflar <- tryCatch(class(x), error = function(e) character(0))
  carpisan <- intersect(siniflar, .PK_ASYNC_FORBIDDEN_CLASSES)
  if (length(carpisan) > 0L) {
    return(sprintf("%s: %s", path, paste(carpisan, collapse = "/")))
  }

  NULL
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

  if (depth > 12L) return(list(safe = TRUE, violations = character(0)))

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

  list(safe = length(ihlaller) == 0L, violations = ihlaller)
}

#' İşçiye taşınacak düz istek anlık görüntüsünü kur
#'
#' Kimlik, API anahtarı, önceki seçim durumu ve yapılandırma ANA SÜREÇTE
#' çözülür. Bu, D16'nın SSO hazırlık ihlalini de kapatır: kimlik hazır değilse
#' işçi HİÇ başlatılmaz.
#'
#' @param api_key_plan `mb_api_key_get_effective_key()` çıktısı.
#' @return Düz liste (fonksiyon/ortam/bağlantı İÇERMEZ).
pk_async_build_request <- function(user_prompt, chat_history, username,
                                   request_id, deep_thinking = FALSE,
                                   detail_level = "standart",
                                   api_key_plan = NULL,
                                   user_session_snapshot = list(),
                                   select_state = NULL,
                                   repo_root = NULL,
                                   cancel_token = NULL,
                                   deadline_sec = NULL,
                                   engine = "v1",
                                   bootstrap_files = NULL,
                                   started_at = Sys.time()) {
  anahtar_kaynagi <- as.character(api_key_plan$source %||% "unknown")[1]
  kisisel_anahtar <- if (identical(anahtar_kaynagi, "personal")) {
    as.character(api_key_plan$key %||% "")[1]
  } else {
    ""
  }

  list(
    user_prompt = as.character(user_prompt %||% "")[1],
    # Sohbet geçmişi ZATEN düz listedir; yine de yalnızca role/content taşınır.
    chat_history = .pk_async_plain_history(chat_history),
    username = as.character(username %||% "")[1],
    request_id = as.character(request_id %||% "")[1],
    deep_thinking = isTRUE(deep_thinking),
    detail_level = as.character(detail_level %||% "standart")[1],
    engine = as.character(engine %||% "v1")[1],
    # Anahtar DEĞERİ hiçbir log/telemetri/artifact'a yazılmaz; yalnızca vekil
    # oturuma konur. Kaynak `personal` değilse anahtar hiç taşınmaz ve işçi
    # kurum varsayılanını KENDİ ortamından çözer (semantik birebir korunur).
    api_key = kisisel_anahtar,
    api_key_source = anahtar_kaynagi,
    user_session = .pk_async_plain_user_data(user_session_snapshot),
    select_state = if (is.list(select_state)) select_state else list(),
    repo_root = as.character(repo_root %||% "")[1],
    # İşçi bootstrap dosya listesi DÜZ VERİDİR ve istekle birlikte taşınır;
    # işçi tarafında manifest okumaya gerek kalmaz.
    bootstrap_files = as.character(bootstrap_files %||% character(0)),
    cancel_token = as.character(cancel_token %||% "")[1],
    deadline_sec = suppressWarnings(as.numeric(deadline_sec %||% NA_real_)[1]),
    started_at_epoch = as.numeric(started_at)
  )
}

.pk_async_plain_history <- function(chat_history) {
  if (!is.list(chat_history) || length(chat_history) == 0L) return(list())

  lapply(chat_history, function(mesaj) {
    if (!is.list(mesaj)) return(list(role = "user", content = as.character(mesaj)[1]))
    list(
      role = as.character(mesaj$role %||% "user")[1],
      content = as.character(mesaj$content %||% "")[1],
      type = as.character(mesaj$type %||% "")[1]
    )
  })
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

# ------------------------------------------------------------------------------
# İSTEK-KİMLİĞİ KORUMASI
# ------------------------------------------------------------------------------

#' Geç gelen bir işçi sonucu UYGULANMALI MI?
#'
#' `mergen_is_current_request` deseninin PK karşılığıdır. Üç ayrı red sebebi
#' AYRI raporlanır; "durduruldu" ile "bayat" ayrımı telemetride anlamlıdır.
#'
#' @param active_request_id Şu anda aktif olan istek kimliği (ana süreçten).
#' @param req_id Bu geri çağrının sahibi olduğu istek kimliği.
#' @param stopped Kullanıcı bu isteği durdurdu mu?
#' @return `list(apply = TRUE/FALSE, reason = "ok"|"stale"|"stopped"|"unknown")`.
pk_async_should_apply <- function(active_request_id, req_id, stopped = FALSE) {
  benim <- tryCatch(as.character(req_id)[1], error = function(e) NA_character_)
  if (is.null(benim) || length(benim) == 0L || is.na(benim) || !nzchar(benim)) {
    # Kimliği olmayan bir geri çağrı durumu MUTASYONA UĞRATAMAZ (kapalı başarısız).
    return(list(apply = FALSE, reason = "unknown"))
  }

  if (isTRUE(stopped)) return(list(apply = FALSE, reason = "stopped"))

  aktif <- tryCatch(as.character(active_request_id)[1], error = function(e) NA_character_)
  if (is.null(aktif) || length(aktif) == 0L || is.na(aktif) || !nzchar(aktif)) {
    return(list(apply = FALSE, reason = "unknown"))
  }

  if (!identical(aktif, benim)) return(list(apply = FALSE, reason = "stale"))

  list(apply = TRUE, reason = "ok")
}

#' Asenkron yürütme bu SÜREÇTE gerçekten mümkün mü?
#'
#' `MERGEN_PK_ASYNC=true` niyeti belirtir; bu fonksiyon YETENEĞİ ölçer.
#' Sequential future planında "asenkron" çalıştırmak, işi ana olay döngüsünde
#' yapmakla AYNI ŞEYDİR — yani Faz 6'nın tek faydasını yok eder ve son tarih
#' zamanlayıcısı asla ateşlenemez. Bu durumda senkron yola dönmek DAHA DÜRÜSTTÜR.
pk_async_enabled <- function(query_meta = NULL) {
  if (!exists("pk_config_resolve", mode = "function", inherits = TRUE)) return(FALSE)
  isTRUE(tryCatch(pk_config_resolve("MERGEN_PK_ASYNC", query_meta), error = function(e) FALSE))
}

pk_async_plan_is_async <- function() {
  if (!requireNamespace("future", quietly = TRUE)) return(FALSE)

  tryCatch({
    plan_siniflari <- class(future::plan("list")[[1]])
    !any(c("sequential", "uniprocess", "transparent") %in% plan_siniflari)
  }, error = function(e) FALSE)
}

#' Asenkron gönderim yapılabilir mi? (niyet + yetenek + bağımlılıklar)
pk_async_available <- function(query_meta = NULL) {
  if (!isTRUE(pk_async_enabled(query_meta))) {
    return(list(available = FALSE, reason = "flag_off"))
  }
  if (!isTRUE(pk_async_plan_is_async())) {
    return(list(available = FALSE, reason = "future_plan_not_async"))
  }
  if (!exists("tracked_future_promise", mode = "function", inherits = TRUE)) {
    return(list(available = FALSE, reason = "tracked_future_promise_missing"))
  }
  if (!requireNamespace("promises", quietly = TRUE)) {
    return(list(available = FALSE, reason = "promises_missing"))
  }

  list(available = TRUE, reason = "ok")
}

# İşçi global paketinin SÜREÇ BAŞINA memoizasyonu. Her istekte yeniden kurmak,
# manifest okumasını ve dosya listesi üretimini OLAY DÖNGÜSÜNDE tekrarlardı.
.pk_async_globals_cache <- new.env(parent = emptyenv())

#' İşçiye taşınacak globals paketini üret (SÜREÇ BAŞINA MEMOIZE)
#'
#' Paket BİLİNÇLİ OLARAK KÜÇÜKTÜR: boru hattının yüzlerce fonksiyonu işçide
#' bootstrap ile yüklenir, serileştirilmez. Böylece explicit-mode gönderim,
#' olay döngüsünde `codetools` taraması YAPMAZ.
pk_async_worker_globals <- function(force = FALSE) {
  if (!isTRUE(force) && !is.null(.pk_async_globals_cache$bundle)) {
    return(.pk_async_globals_cache$bundle)
  }

  paket <- list(
    pk_async_worker_bootstrap = pk_async_worker_bootstrap,
    pk_async_worker_session = pk_async_worker_session,
    pk_async_harvest_session = pk_async_harvest_session,
    pk_async_worker_ready = pk_async_worker_ready,
    pk_async_worker_entry_points = pk_async_worker_entry_points,
    pk_async_run_analysis = if (exists("pk_async_run_analysis", mode = "function", inherits = TRUE)) {
      get("pk_async_run_analysis", mode = "function", inherits = TRUE)
    } else {
      NULL
    },
    .PK_ASYNC_BOOTSTRAP_FLAG = .PK_ASYNC_BOOTSTRAP_FLAG,
    .PK_ASYNC_HARVEST_SLOTS = .PK_ASYNC_HARVEST_SLOTS,
    .PK_ASYNC_USER_DATA_FIELDS = .PK_ASYNC_USER_DATA_FIELDS,
    bootstrap_files = pk_async_worker_bootstrap_files()
  )

  paket <- paket[!vapply(paket, is.null, logical(1))]
  .pk_async_globals_cache$bundle <- paket
  paket
}

pk_async_worker_globals_reset <- function() {
  .pk_async_globals_cache$bundle <- NULL
  invisible(TRUE)
}
