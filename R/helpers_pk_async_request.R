# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_request.R
# Açıklama: Faz 6 (§5.10) — işçiye taşınacak DÜZ, DEĞİŞTİRİLEMEZ istek anlık
#           görüntüsünün KURULMASI, İSTEK-KİMLİĞİ koruması, future planı
#           YETENEK kapısı ve işçi globals paketi.
#
# Bu dosya SAFTIR: Shiny/reaktif/DB/ağ ÇAĞIRMAZ. Yalnızca ana süreçte hazırlanan
# değerlerden düz veri üretir ve karar döndürür.
#
# İşçi-güvenli anlık görüntü DOĞRULAMASI ve düz veri sanitizasyonu AYRI
# dosyadadır: `R/helpers_pk_async_snapshot.R` (manifestte bu dosyadan ÖNCE
# yüklenir). İşçi bootstrap sözleşmesi, oturum vekili ve dosya listesi
# `R/helpers_pk_async_bootstrap.R` içindedir.
# ==============================================================================

# ------------------------------------------------------------------------------
# İSTEK ANLIK GÖRÜNTÜSÜ
# ------------------------------------------------------------------------------

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
                                   started_at = Sys.time(),
                                   config_snapshot = NULL) {
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
    # Ana süreçte çözülmüş yapılandırma (options() basamağı dahil) işçiye
    # taşınır; aksi hâlde işçi farklı güvenlik sınırlarıyla çalışabilir.
    pk_config = if (is.list(config_snapshot)) config_snapshot else pk_async_config_snapshot(),
    # DB havuzu AÇILIŞI `options()` üzerinden de yapılabilir; temiz bir PSOCK
    # işçisi ana sürecin rastgele option'larını GÖRMEZ ve havuz sessizce
    # kapalı sanılırdı (doğrudan `dbConnect()` = admisyon tavanı yok).
    db_pool_options = tryCatch(pk_async_db_pool_option_snapshot(), error = function(e) list()),
    # Yalnızca telemetri parmak izi anahtarı; hiçbir log/artifact'a yazılmaz.
    pk_secrets = tryCatch(pk_async_secret_snapshot(), error = function(e) list()),
    # Agregat DB admisyon payı işçi sayısına bağlıdır; işçi bunu kendisi
    # ÖLÇEMEZ (kendi süreci tek bir işçidir).
    worker_count = tryCatch(pk_async_worker_count(), error = function(e) 1L),
    started_at_epoch = as.numeric(started_at)
  )
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


#' Faz 6 asenkron çalışma zamanı ETKİN Mİ?
#'
#' Faz 6'nın yeni denetimleri (mutlak analiz son tarihi, sonuç önbelleği, satır
#' tavanı reddi) `MERGEN_PK_ASYNC=false` iken DEVREYE GİRMEZ; aksi hâlde ilan
#' edilen tek adımlık geri alma yolu gerçek bir geri alma olmazdı. İşçi içinde
#' bayrak okunamasa bile dispatch anında kurulan mutlak son tarih option'ı
#' asenkron kipin kanıtıdır.
pk_async_mode_active <- function(query_meta = NULL) {
  if (!is.null(getOption("mergen.pk.async.deadline_at", NULL))) return(TRUE)
  isTRUE(tryCatch(pk_async_enabled(query_meta), error = function(e) FALSE))
}

#' Asenkron gönderim yapılabilir mi? (niyet + yetenek + bağımlılıklar)
pk_async_available <- function(query_meta = NULL) {
  if (!isTRUE(pk_async_enabled(query_meta))) {
    return(list(available = FALSE, reason = "flag_off"))
  }
  plan_durumu <- pk_async_plan_capability()
  if (!isTRUE(plan_durumu$ok)) {
    return(list(available = FALSE, reason = plan_durumu$reason %||% "future_plan_not_async"))
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
    # `%||%` bootstrap'tan ÖNCE gereklidir: `pk_async_worker_bootstrap()` kendi
    # gövdesinde `files %||% character(0)` değerlendirir ve explicit-mode'da
    # özyinelemeli global genişletme YOKTUR. Eksikse temiz her işçi tipli
    # fallback yerine ham bir "could not find function" hatasıyla ölürdü.
    `%||%` = get("%||%", mode = "function", inherits = TRUE),
    # İPTAL/SON TARİH yardımcıları da bootstrap'tan ÖNCE gereklidir:
    # `pk_async_run_analysis()` mutlak son tarihi türetir ve İLK kapıyı
    # bootstrap'tan önce yoklar (yavaş/askıda bir repo yolu Durdur'u yok
    # saymasın diye). Explicit-mode özyinelemeli global genişletme YAPMADIĞI
    # için bunlar açıkça taşınmalıdır; eksik olduklarında TEMİZ bir PSOCK
    # işçisi "could not find function pk_deadline_at" ile ölür ve asenkron yol
    # ancak üretimde patlardı.
    pk_deadline_at = pk_deadline_at,
    pk_deadline_expired = pk_deadline_expired,
    pk_deadline_remaining_sec = pk_deadline_remaining_sec,
    pk_cancel_token_is_signalled = pk_cancel_token_is_signalled,
    pk_async_stage_gate = pk_async_stage_gate,
    pk_async_halt_message = pk_async_halt_message,
    pk_async_config_install = pk_async_config_install,
    pk_async_config_install_env = pk_async_config_install_env,
    pk_async_secret_install = pk_async_secret_install,
    .PK_ASYNC_WORKER_SECRET_KEYS = .PK_ASYNC_WORKER_SECRET_KEYS,
    pk_async_worker_bootstrap = pk_async_worker_bootstrap,
    pk_async_worker_session = pk_async_worker_session,
    pk_async_harvest_session = pk_async_harvest_session,
    pk_async_worker_ready = pk_async_worker_ready,
    pk_async_worker_entry_points = pk_async_worker_entry_points,
    # `pk_async_worker_bootstrap()` gövdesinde çağırdığı HER sembol de
    # bootstrap ÖNCESİ gereklidir; explicit-mode özyinelemeli genişletme
    # YAPMAZ. Eksikse temiz bir PSOCK işçisi HER istekte bootstrap'ta ölür ve
    # asenkron yol sessizce senkron yola düşerdi.
    pk_async_worker_required_files = pk_async_worker_required_files,
    pk_async_bootstrap_fingerprint = pk_async_bootstrap_fingerprint,
    pk_async_worker_sql_dependencies = pk_async_worker_sql_dependencies,
    .pk_async_file_digest = .pk_async_file_digest,
    pk_async_worker_stage_env = pk_async_worker_stage_env,
    pk_async_worker_commit_env = pk_async_worker_commit_env,
    pk_async_worker_install_globals = pk_async_worker_install_globals,
    .pk_async_worker_pool_ensure = .pk_async_worker_pool_ensure,
    .pk_async_worker_db_pool_init = .pk_async_worker_db_pool_init,
    pk_async_worker_pool_admission = pk_async_worker_pool_admission,
    pk_async_worker_pool_apply_share = pk_async_worker_pool_apply_share,
    pk_async_worker_pool_retire = pk_async_worker_pool_retire,
    pk_async_db_pool_option_install = pk_async_db_pool_option_install,
    .pk_async_pool_log = .pk_async_pool_log,
    # Artifact kaydı: iptal/hata yollarında ÖKSÜZ dosya bırakmamak için işçide
    # bootstrap'tan bağımsız olarak da bulunmalıdır.
    pk_artifact_track = pk_artifact_track,
    pk_artifact_release_tracked = pk_artifact_release_tracked,
    pk_artifact_discard_tracked = pk_artifact_discard_tracked,
    pk_async_discard_worker_artifact = pk_async_discard_worker_artifact,
    pk_async_run_analysis = if (exists("pk_async_run_analysis", mode = "function", inherits = TRUE)) {
      get("pk_async_run_analysis", mode = "function", inherits = TRUE)
    } else {
      NULL
    },
    .PK_ASYNC_BOOTSTRAP_FLAG = .PK_ASYNC_BOOTSTRAP_FLAG,
    .PK_ASYNC_POOL_READY_FLAG = .PK_ASYNC_POOL_READY_FLAG,
    .PK_ASYNC_OWNED_NAMES_SLOT = .PK_ASYNC_OWNED_NAMES_SLOT,
    .PK_ASYNC_DB_POOL_OPTIONS = .PK_ASYNC_DB_POOL_OPTIONS,
    .PK_ASYNC_HARVEST_SLOTS = .PK_ASYNC_HARVEST_SLOTS,
    .PK_ASYNC_USER_DATA_FIELDS = .PK_ASYNC_USER_DATA_FIELDS,
    .PK_ASYNC_WORKER_BUNDLE_MARK = .PK_ASYNC_WORKER_BUNDLE_MARK,
    bootstrap_files = pk_async_worker_bootstrap_files()
  )
  # Paketin İŞÇİ PAKETİ olduğunu kanıtlayan işaret: `pk_async_worker_install_globals()`
  # bu işaret olmadan hiçbir ortamı `globalenv()`'e kopyalamaz.
  paket[[.PK_ASYNC_WORKER_BUNDLE_MARK]] <- TRUE

  paket <- paket[!vapply(paket, is.null, logical(1))]
  .pk_async_globals_cache$bundle <- paket
  paket
}

pk_async_worker_globals_reset <- function() {
  .pk_async_globals_cache$bundle <- NULL
  invisible(TRUE)
}
