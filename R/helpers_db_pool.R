# ==============================================================================
# Dosya Yolu: R/helpers_db_pool.R
# Açıklama: Üretim/VM için işlem-güvenli (transaction-safe) veritabanı bağlantı
#           havuzu katmanı. `pool` paketi üzerine kurulur; ham DSN/secret
#           loglamaz. Havuzlama opsiyoneldir (varsayılan KAPALI) ve testlerde
#           deterministik biçimde devre dışı bırakılabilir.
#
# Tasarım sözleşmesi:
#   - `R/helpers_db_connection.R` doğrudan ODBC bağlantı/serbest bırakma ve
#     worker bağlantı yardımcılarına odaklı kalır; havuz katmanı BURADA durur.
#   - Okuma yolları havuz aktifken otomatik olarak havuzu kullanır: havuz nesnesi
#     `.GlobalEnv$pool`'a yazılır ve mevcut `get_connection()` bu nesneyi döndürür
#     (geriye dönük uyumluluk; `get_connection()` değiştirilmedi).
#   - İŞLEM (transaction) yolları havuz nesnesini ASLA bağlantı gibi kullanmaz.
#     Çok-ifadeli `dbBegin/dbCommit/dbRollback` için `pool::poolCheckout()` ile
#     gerçek bir bağlantı ödünç alınır; hata/başarı her durumda iade edilir.
#   - Havuz kapalıyken tüm yollar mevcut doğrudan bağlantı davranışına düşer.
#
# Önemli: Bu dosya top-level `library(pool)` / `library(odbc)` YÜKLEMEZ;
# cloud-quick bootstrap'ı bozmamak için bağımlılıklar fonksiyon içinde
# `requireNamespace()` ile kontrol edilir (helpers_db_connection.R ile aynı
# desen).
# ==============================================================================

if (!requireNamespace("DBI", quietly = TRUE)) {
  stop("R/helpers_db_pool.R requires the 'DBI' package.", call. = FALSE)
}

# Havuz çalışma-zamanı durumu (global ortamı kirletmemek için iç ortam).
# pools  : target -> Pool nesnesi
# events : sınırlı halka tampon (secret-safe enstrümantasyon olayları)
# stats  : sayaçlar (checkout/return/leak/tx ...)
.mergen_db_pool_state <- new.env(parent = emptyenv())
.mergen_db_pool_state$pools <- list()
.mergen_db_pool_state$events <- list()
.mergen_db_pool_state$events_cap <- 200L
.mergen_db_pool_state$stats <- list(
  init = 0L, init_failed = 0L, init_skipped = 0L, closed = 0L,
  checkout = 0L, checkout_failed = 0L, returned = 0L,
  tx_begin = 0L, tx_commit = 0L, tx_rollback = 0L,
  direct_fallback = 0L
)

# ------------------------------------------------------------------------------
# Ortam değişkeni okuma yardımcıları (ASCII-güvenli truthy/sayı çözümleme).
# ------------------------------------------------------------------------------
.db_pool_truthy <- function(x) {
  v <- tolower(trimws(as.character(x %||% "")[1]))
  if (!nzchar(v)) return(NA)
  if (v %in% c("true", "t", "1", "yes", "y", "on", "evet", "acik", "aktif")) return(TRUE)
  if (v %in% c("false", "f", "0", "no", "n", "off", "hayir", "kapali", "pasif")) return(FALSE)
  NA
}

.db_pool_env_num <- function(name, default) {
  raw <- trimws(Sys.getenv(name, unset = ""))
  if (!nzchar(raw)) return(as.numeric(default))
  val <- suppressWarnings(as.numeric(raw))
  if (is.na(val)) as.numeric(default) else val
}

# Havuz açık mı? Ortam değişkeni > R option > varsayılan (KAPALI).
is_db_pool_enabled <- function() {
  env_raw <- Sys.getenv("MERGEN_DB_POOL_ENABLED", unset = NA_character_)
  if (!is.na(env_raw) && nzchar(trimws(env_raw))) {
    flag <- .db_pool_truthy(env_raw)
    if (!is.na(flag)) return(isTRUE(flag))
  }
  isTRUE(getOption("mergen.db.pool_enabled", FALSE))
}

# Havuz boyutlandırma/doğrulama yapılandırması. Varsayılanlar bilinçli olarak
# korumacıdır (tek Shiny süreci + SQL Server için makul).
#
# fail_fast: KAPALI (varsayılan) iken havuz başlatılamazsa uygulama/preflight
#   KIRILMAZ; sessizce doğrudan bağlantı yoluna düşülür (mevcut davranış).
#   AÇIK iken (MERGEN_DB_POOL_FAIL_FAST=TRUE) havuz başlatılamazsa
#   init_db_pool_once() açıkça stop() eder; böylece operatör havuz olmadan
#   üretime devam etmek yerine erken/gürültülü bir hata ister. Yalnızca env >
#   R option > FALSE sırasıyla çözülür; ham secret okumaz.
db_pool_config <- function() {
  fail_fast_env <- .db_pool_truthy(Sys.getenv("MERGEN_DB_POOL_FAIL_FAST", unset = ""))
  fail_fast <- if (!is.na(fail_fast_env)) {
    isTRUE(fail_fast_env)
  } else {
    isTRUE(getOption("mergen.db.pool_fail_fast", FALSE))
  }

  # KÜRESEL ADMİSYON TAVANI ve BU SÜRECİN PAYI (PR #703 incelemesi).
  #
  # `MERGEN_DB_POOL_MAX_SIZE` her `Pool` nesnesi İÇİNDE uygulanır, süreçler
  # ARASINDA değil. Faz 6 eşzamanlı PSOCK işçileri eklediği için ana sürecin
  # tavanın TAMAMINI alması toplam canlı oturumu `cap + workers * pay` yapardı.
  # Pay hesabı TEK yerdedir (`pk_db_admission_plan()`), ana süreç ve işçi AYNI
  # bölüşümü uygular. Asenkron KAPALIYKEN bölüşüm devreye girmez ve davranış
  # bit bazında korunur.
  admission_cap <- max(1L, as.integer(.db_pool_env_num("MERGEN_DB_POOL_MAX_SIZE", 8)))
  process_max <- admission_cap
  if (exists("pk_db_pool_process_share", mode = "function", inherits = TRUE)) {
    pay <- try(suppressWarnings(as.integer(pk_db_pool_process_share(admission_cap))[1]),
               silent = TRUE)
    if (!inherits(pay, "try-error") && length(pay) == 1L && !is.na(pay) && pay >= 1L) {
      process_max <- pay
    }
  }

  # Bölüşüm sonrası `min_size > max_size` kalırsa havuz kurulumu tutarsız olur.
  min_size <- max(0L, as.integer(.db_pool_env_num("MERGEN_DB_POOL_MIN_SIZE", 1)))

  list(
    enabled = is_db_pool_enabled(),
    fail_fast = fail_fast,
    min_size = min(min_size, process_max),
    admission_cap = admission_cap,
    max_size = process_max,
    idle_timeout_sec = max(1, .db_pool_env_num("MERGEN_DB_POOL_IDLE_TIMEOUT", 600)),
    validation_interval_sec = max(1, .db_pool_env_num("MERGEN_DB_POOL_VALIDATION_INTERVAL", 60))
  )
}

# ------------------------------------------------------------------------------
# Enstrümantasyon: secret-safe olay kaydı + sayaçlar. DSN/secret YAZILMAZ.
# ------------------------------------------------------------------------------
.db_pool_record_event <- function(type, fields = list()) {
  st <- .mergen_db_pool_state
  # Sayaç güncelle (varsa).
  if (!is.null(st$stats[[type]])) {
    st$stats[[type]] <- st$stats[[type]] + 1L
  }
  rec <- list(
    ts = as.numeric(Sys.time()),
    type = as.character(type)[1],
    fields = fields
  )
  st$events[[length(st$events) + 1L]] <- rec
  # Halka tampon: en eski olayları kırp.
  if (length(st$events) > st$events_cap) {
    st$events <- st$events[seq.int(length(st$events) - st$events_cap + 1L, length(st$events))]
  }
  # Opsiyonel performans kancası (varsa).
  if (exists("mergen_perf_log", mode = "function", inherits = TRUE)) {
    try(mergen_perf_log(paste0("db.pool.", type), fields = fields), silent = TRUE)
  }
  invisible(NULL)
}

# ------------------------------------------------------------------------------
# Aktif havuz nesnesini döndürür (yoksa NULL). Önce iç durum, sonra geriye dönük
# `.GlobalEnv$pool` (yalnızca primary). Geçersiz/kapalı havuzları yok sayar.
# ------------------------------------------------------------------------------
db_pool_get <- function(target = "primary") {
  st <- .mergen_db_pool_state
  obj <- st$pools[[target]]
  if (!is.null(obj) && inherits(obj, "Pool") && isTRUE(.db_pool_object_valid(obj))) {
    return(obj)
  }

  # Geriye dönük: server.R / eski kod .GlobalEnv$pool kullanır (yalnızca primary).
  # get0() yoksa NULL döner; ayrı bir tryCatch hata-işleyicisine gerek kalmaz.
  if (identical(target, "primary")) {
    legacy <- get0("pool", envir = .GlobalEnv, inherits = FALSE, ifnotfound = NULL)
    if (!is.null(legacy) && inherits(legacy, "Pool") && isTRUE(.db_pool_object_valid(legacy))) {
      return(legacy)
    }
  }

  NULL
}

# Havuz nesnesi hala geçerli mi? `pool` 1.x `$valid` alanını sunar.
.db_pool_object_valid <- function(obj) {
  v <- tryCatch(obj$valid, error = function(e) NA)
  if (is.na(v)) return(TRUE)  # alan okunamıyorsa geçerli varsay (en iyi çaba)
  isTRUE(v)
}

db_pool_is_active <- function(target = "primary") {
  !is.null(db_pool_get(target))
}

# ------------------------------------------------------------------------------
# Havuzu BİR KEZ başlatır. Etkin değilse (force = FALSE) sessizce atlar.
#   target  : "primary" | "secondary" | "tertiary"
#   factory : NULL ise üretim ODBC havuzu kurulur; aksi halde 0-argümanlı bir
#             fonksiyon olmalı ve bir `Pool` nesnesi döndürmelidir (testler için
#             SQLite havuzu enjekte etmeye olanak tanır).
#   force   : TRUE ise etkinlik bayrağına bakılmaksızın başlatır.
#   fail_fast : Varsayılan db_pool_config()$fail_fast. KAPALI iken başarısızlıkta
#             uygulama başlatmayı KIRMAZ (olay kaydeder, NULL döner). AÇIK iken
#             başlatma başarısız olursa açıkça stop() eder (ham secret içermeyen,
#             genel hata mesajı). Bu, operatörün "havuz yoksa düş" yerine "havuz
#             yoksa erken hata ver" davranışını seçmesine izin verir.
# ------------------------------------------------------------------------------
init_db_pool_once <- function(target = "primary", factory = NULL, force = FALSE,
                              fail_fast = isTRUE(db_pool_config()$fail_fast)) {
  if (!isTRUE(force) && !is_db_pool_enabled()) {
    .db_pool_record_event("init_skipped", list(target = target, reason = "disabled"))
    return(invisible(NULL))
  }

  existing <- .mergen_db_pool_state$pools[[target]]
  if (!is.null(existing) && inherits(existing, "Pool") && isTRUE(.db_pool_object_valid(existing))) {
    return(invisible(existing))
  }

  if (!requireNamespace("pool", quietly = TRUE)) {
    .db_pool_record_event("init_failed", list(target = target, reason = "pool_paketi_yok"))
    if (isTRUE(fail_fast)) {
      stop(sprintf("DB havuz fail-fast: '%s' havuzu icin 'pool' paketi yok.", target),
           call. = FALSE)
    }
    return(invisible(NULL))
  }

  cfg <- db_pool_config()

  pool_obj <- tryCatch({
    if (is.function(factory)) {
      built <- factory()
      if (!inherits(built, "Pool")) {
        stop("factory() bir 'Pool' nesnesi dondurmedi.", call. = FALSE)
      }
      built
    } else {
      .db_pool_build_default(target, cfg)
    }
  }, error = function(e) {
    .db_pool_record_event("init_failed",
                          list(target = target, error_class = class(e)[1]))
    NULL
  })

  if (is.null(pool_obj)) {
    if (isTRUE(fail_fast)) {
      # Genel mesaj: ham DSN/secret/koşul mesajı SIZDIRILMAZ (kök neden event
      # kaydında error_class olarak tutulur).
      stop(sprintf("DB havuz fail-fast: '%s' havuzu baslatilamadi (init_failed).", target),
           call. = FALSE)
    }
    return(invisible(NULL))
  }

  .mergen_db_pool_state$pools[[target]] <- pool_obj

  # Geriye dönük okuma yolu: primary havuzu `.GlobalEnv$pool`'a yaz.
  if (identical(target, "primary")) {
    assign("pool", pool_obj, envir = .GlobalEnv)
  }

  .db_pool_record_event("init", list(
    target = target,
    min_size = cfg$min_size,
    max_size = cfg$max_size,
    idle_timeout_sec = cfg$idle_timeout_sec
  ))

  invisible(pool_obj)
}

# Üretim ODBC havuzunu kurar (encoding sözleşmesi korunur).
.db_pool_build_default <- function(target, cfg) {
  if (!requireNamespace("odbc", quietly = TRUE)) {
    stop("Havuz icin 'odbc' paketi gerekli.", call. = FALSE)
  }

  dsn_var <- switch(target,
    "primary"   = "DB_DSN",
    "secondary" = "DB_DSN_2",
    "tertiary"  = "DB_DSN_3",
    "DB_DSN"
  )
  dsn_name <- Sys.getenv(dsn_var, Sys.getenv("DB_DSN", "TestConnection"))
  if (identical(dsn_name, "")) {
    stop(sprintf("Havuz icin '%s' DSN tanimi yok.", dsn_var), call. = FALSE)
  }

  # KRİTİK (üretim çökme koruması): pool::release(), iade edilen HER bağlantı
  # için validationInterval > 0 olduğunda `later` üzerinde TEKRARLAYAN bir arka
  # plan doğrulama görevi (scheduleTaskRecurring) zamanlar. Bu görev periyodik
  # olarak checkObjectValid() çağırır; bağlantı boştayken kopmuşsa (08S01)
  # yenisini kurmayı dener. Yeni dbConnect() geçici bir oturum-açma zaman
  # aşımıyla (08001 / "Login timeout expired") başarısız olursa, hata bu `later`
  # geri çağrısının DIŞINA YAKALANMADAN sızar ve tüm runApp() sürecini
  # sonlandırır (uygulama tamamen çöker). Bu hata uygulama kodundaki tryCatch
  # ile yakalanamaz; çünkü havuzun KENDİ arka plan görevinde, herhangi bir
  # observer/handler bağlamı dışında oluşur.
  #
  # Çözüm: validationInterval = 0. Bu, arka plan tekrarlayan doğrulama görevini
  # TAMAMEN devre dışı bırakır. Doğrulama yalnızca checkout (ödünç alma) anında
  # validateQuery = "SELECT 1" ile yapılır (validationInterval = 0 iken pool her
  # ödünç almada doğrular). Kopuk bir bağlantı checkout sırasında senkron olarak
  # tespit edilip değiştirilir; yeni bağlantı kurulamazsa hata SENKRON olarak
  # çağıranın tryCatch'ine düşer (save_message_to_db gibi yazma yolları bunu
  # zaten yakalar) ve uygulamayı çökertmez.
  #
  # MERGEN_DB_POOL_VALIDATION_INTERVAL ortam değişkeni geriye dönük uyumluluk
  # için db_pool_config() tarafından okunmaya devam eder (durum/snapshot raporu),
  # ancak ARTIK havuzun arka plan döngüsünü SÜRMEZ; üretim Shiny + later
  # bağlamında güvenli olan tek değer 0'dır. Bunu cfg$validation_interval_sec'e
  # geri bağlamayın (çökme regresyonu yaratır).
  # SÜRÜCÜ SEVİYESİ LOGIN ZAMAN AŞIMI (PR #703 incelemesi).
  #
  # `interruptible = TRUE` yalnızca bir ODBC İFADESİ çalışırken yardımcı olur;
  # FİZİKSEL BAĞLANTI KURULUMUNU sınırlamaz. `poolCheckout()` havuz büyürken
  # yeni bir fiziksel bağlantı kurabilir ve çağıranın `setTimeLimit()` sarmalı
  # derlenmiş DSN/login çağrısını GÜVENİLİR biçimde kesemez (bkz.
  # `helpers_db_connection.R` gerekçesi). Yavaş/erişilemez bir DSN bu yüzden
  # havuzlu yolda PK son tarihini aşabiliyordu.
  #
  # Havuz bağlantıları UZUN ÖMÜRLÜDÜR ve HANGİ isteğin onları oluşturacağı
  # önceden bilinemez; bu yüzden buraya İSTEK KALAN BÜTÇESİ değil, SABİT bir
  # operatör sınırı (`MERGEN_DB_LOGIN_TIMEOUT_SEC`, yoksa 30 sn) konur. İstek
  # bütçesi ayrıca checkout sarmalayıcısında uygulanmaya devam eder; ikisinin
  # ilişkisi: sürücü sınırı ÜST SINIR, istek bütçesi DAHA SIKI olandır.
  login_plan <- if (exists(".db_login_timeout_plan", mode = "function", inherits = TRUE)) {
    .db_login_timeout_plan(Inf)
  } else {
    list(mode = "bounded", timeout = 30L)
  }
  havuz_args <- list(
    drv = odbc::odbc(),
    dsn = dsn_name,
    encoding = .DEFAULT_DB_CLIENT_ENCODING,
    name_encoding = .DEFAULT_DB_NAME_ENCODING,
    minSize = cfg$min_size,
    maxSize = cfg$max_size,
    idleTimeout = cfg$idle_timeout_sec,
    validationInterval = 0,
    validateQuery = "SELECT 1",
    # Faz 6 (§5.10): havuzun ürettiği FİZİKSEL ODBC bağlantıları da kesilebilir
    # olmalıdır. Doğrudan bağlantı kurucusu bunu zaten geçiriyordu; havuz
    # geçirmediği için `pk_sql_execute_bounded()` içindeki setTimeLimit
    # interrupt'ı, SQLExecute bloklanmışken SQLCancel yoluna ULAŞAMIYORDU.
    interruptible = TRUE
  )
  # HAVUZ İÇİN "sürücü varsayılanı" KABUL EDİLMEZ: `driver_default` (operatör
  # hiçbir sınır tanımlamamış) hâlinde de yerleşik 30 sn uygulanır.
  #
  # Bu, doğrudan bağlantı sözleşmesiyle ÇELİŞMEZ: orada PK-DIŞI çağıranların
  # sürücü varsayılanı korunur, çünkü doğrudan yol VARSAYILAN yoldur. Havuz ise
  # AÇIKÇA opt-in'dir (`MERGEN_DB_POOL_ENABLED`, varsayılan kapalı), uzun ömürlü
  # ve PAYLAŞIMLIDIR: sınırsız bir login burada tek bir yavaş DSN yüzünden hem
  # PK son tarihini hem de havuzu bekleyen tüm oturumları askıda bırakır.
  havuz_args$timeout <- if (identical(login_plan$mode, "bounded")) {
    login_plan$timeout
  } else {
    .DB_DEFAULT_LOGIN_TIMEOUT_SEC
  }
  do.call(pool::dbPool, havuz_args)
}

# ------------------------------------------------------------------------------
# Havuzu(ları) temiz biçimde kapatır (uygulama durdurmada). target = NULL ise
# tüm havuzlar kapatılır.
# ------------------------------------------------------------------------------
close_db_pool_once <- function(target = NULL) {
  st <- .mergen_db_pool_state
  targets <- if (is.null(target)) names(st$pools) else target
  targets <- targets[nzchar(targets)]

  for (tg in targets) {
    obj <- st$pools[[tg]]
    if (!is.null(obj) && inherits(obj, "Pool")) {
      tryCatch({
        if (requireNamespace("pool", quietly = TRUE)) {
          pool::poolClose(obj)
        }
      }, error = function(e) {
        .db_pool_record_event("close_failed", list(target = tg, error_class = class(e)[1]))
      })
    }
    st$pools[[tg]] <- NULL
    if (identical(tg, "primary") && exists("pool", envir = .GlobalEnv, inherits = FALSE)) {
      legacy <- get0("pool", envir = .GlobalEnv, inherits = FALSE, ifnotfound = NULL)
      if (is.null(legacy) || inherits(legacy, "Pool")) {
        assign("pool", NULL, envir = .GlobalEnv)
      }
    }
    .db_pool_record_event("closed", list(target = tg))
  }

  invisible(NULL)
}

# ------------------------------------------------------------------------------
# İşlem-güvenli bağlantı edinme/iade. Havuz aktifse gerçek bir bağlantı ödünç
# alınır (checked_out = TRUE); aksi halde mevcut doğrudan bağlantı yoluna düşer.
# Dönüş, get_connection() ile uyumlu bir listedir: $conn, $pooled, $pool,
# $checked_out, $target.
# ------------------------------------------------------------------------------
db_acquire_tx_connection <- function(target = "primary") {
  pool_obj <- db_pool_get(target)
  ci_direct <- NULL

  # Havuz AKTİF DEĞİL: doğrudan bağlantıyı al. ANCAK get_connection() primary
  # hedefte `.GlobalEnv$pool`'u (bir Pool nesnesini) geri döndürebilir. Bu,
  # havuz nesnesinin geçersiz/eski olduğu (db_pool_get geçersiz sayıp NULL
  # döndürdüğü) ama .GlobalEnv$pool'un hâlâ bir Pool tuttuğu durumlarda olur.
  # İşlem (dbBegin/dbCommit) bir Pool üzerinde ASLA çalıştırılmamalıdır; her
  # ifade farklı bir bağlantıya checkout edilir ve işlem ifadeler arasında
  # tutamaz. Bu durumda Pool'u aşağıdaki ORTAK checkout bloğuna yönlendirip
  # gerçek bir bağlantı ödünç alırız (Pool'u işlem bağlantısı gibi GEÇİRMEYİZ).
  if (is.null(pool_obj) || !requireNamespace("pool", quietly = TRUE)) {
    ci_direct <- get_connection(target)
    if (inherits(ci_direct$conn, "Pool") && requireNamespace("pool", quietly = TRUE)) {
      pool_obj <- ci_direct$conn
    }
  }

  # ORTAK işlem-güvenli checkout: gerçek bir DBI bağlantısı ödünç alınır (ASLA
  # Pool nesnesi değil). Checkout HATA verirse YÜZEYE ÇIKARILIR; sessizce
  # Pool-nesnesi-üzerinde-işlem yoluna DÜŞÜLMEZ. Yazma yolu (save_message_to_db)
  # bu hatayı zaten yakalayıp loglar.
  if (!is.null(pool_obj) && requireNamespace("pool", quietly = TRUE)) {
    conn <- tryCatch(
      pool::poolCheckout(pool_obj),
      error = function(e) {
        .db_pool_record_event("checkout_failed", list(target = target, error_class = class(e)[1]))
        stop(e)
      }
    )
    .db_pool_record_event("checkout", list(target = target))
    return(list(conn = conn, pooled = TRUE, checked_out = TRUE,
                pool = pool_obj, target = target))
  }

  # GERÇEK doğrudan bağlantı (Pool değil): mevcut doğrudan-bağlantı yolu.
  st <- .mergen_db_pool_state
  st$stats$direct_fallback <- (st$stats$direct_fallback %||% 0L) + 1L
  ci_direct$checked_out <- FALSE
  ci_direct
}

db_release_tx_connection <- function(conn_info) {
  if (is.null(conn_info)) return(invisible(NULL))

  if (isTRUE(conn_info$checked_out) && !is.null(conn_info$conn)) {
    tryCatch({
      if (requireNamespace("pool", quietly = TRUE)) {
        pool::poolReturn(conn_info$conn)
        .db_pool_record_event("returned", list(target = conn_info$target %||% "primary"))
      }
    }, error = function(e) {
      .db_pool_record_event("return_failed", list(error_class = class(e)[1]))
    })
    return(invisible(NULL))
  }

  # Doğrudan bağlantı: mevcut serbest bırakma davranışı.
  release_connection(conn_info)
}

# ------------------------------------------------------------------------------
# with_db_connection: salt-okunur/tekil-ifade işlemleri için bağlantı ödünç alır
# ve HER DURUMDA iade eder. fn(conn) çağrılır; sonucu döner.
# ------------------------------------------------------------------------------
with_db_connection <- function(fn, target = "primary") {
  stopifnot(is.function(fn))
  conn_info <- db_acquire_tx_connection(target)
  on.exit(db_release_tx_connection(conn_info), add = TRUE)
  fn(conn_info$conn)
}

# ------------------------------------------------------------------------------
# with_db_transaction: çok-ifadeli işlemleri güvenli biçimde çalıştırır.
#   - Havuz aktifse gerçek bir bağlantı ödünç alınır (havuz nesnesi DEĞİL).
#   - dbBegin -> fn(conn) -> dbCommit.
#   - fn hata fırlatırsa dbRollback yapılır ve hata yeniden fırlatılır.
#   - Bağlantı, iade edilmeden ÖNCE commit/rollback ile temizlenir (havuza açık
#     işlemle dönüş engellenir).
# ------------------------------------------------------------------------------
with_db_transaction <- function(fn, target = "primary") {
  stopifnot(is.function(fn))
  conn_info <- db_acquire_tx_connection(target)
  conn <- conn_info$conn

  committed <- FALSE
  # İade her zaman EN SON çalışır; rollback ondan ÖNCE (after = FALSE ile öne alınır).
  on.exit(db_release_tx_connection(conn_info), add = TRUE)
  on.exit({
    if (!committed) {
      try(DBI::dbRollback(conn), silent = TRUE)
      .db_pool_record_event("tx_rollback", list(target = target))
    }
  }, add = TRUE, after = FALSE)

  DBI::dbBegin(conn)
  .db_pool_record_event("tx_begin", list(target = target))

  result <- fn(conn)

  DBI::dbCommit(conn)
  committed <- TRUE
  .db_pool_record_event("tx_commit", list(target = target))

  result
}

# ------------------------------------------------------------------------------
# Secret-safe havuz durumu anlık görüntüsü. Ham DSN/secret İÇERMEZ; yalnızca
# yapısal sayaçlar, boyut ve free/taken bağlantı sayıları raporlanır. Sağlık
# paneli / soak kanıtı bunu güvenle tüketebilir.
# ------------------------------------------------------------------------------
db_pool_status_snapshot <- function() {
  st <- .mergen_db_pool_state
  cfg <- db_pool_config()

  pools <- list()
  for (tg in names(st$pools)) {
    obj <- st$pools[[tg]]
    counts <- list(free = NA_integer_, taken = NA_integer_, valid = NA)
    if (!is.null(obj) && inherits(obj, "Pool")) {
      # Tek tryCatch bloğu: valid + free/taken sayaçları (ayrı anonim
      # işleyiciler yerine konsolide; fonksiyon-yoğunluk ratchet'i korunur).
      tryCatch({
        counts$valid <- isTRUE(obj$valid)
        counts$free <- as.integer(get("free", envir = obj$counters))
        counts$taken <- as.integer(get("taken", envir = obj$counters))
      }, error = function(e) NULL)
    }
    pools[[tg]] <- list(active = isTRUE(counts$valid),
                        free = counts$free, taken = counts$taken)
  }

  stats <- st$stats
  leaked <- as.integer((stats$checkout %||% 0L) - (stats$returned %||% 0L))

  list(
    enabled = isTRUE(cfg$enabled),
    fail_fast = isTRUE(cfg$fail_fast),
    config = list(
      min_size = cfg$min_size,
      max_size = cfg$max_size,
      idle_timeout_sec = cfg$idle_timeout_sec,
      validation_interval_sec = cfg$validation_interval_sec
    ),
    active_targets = names(st$pools),
    pools = pools,
    counters = list(
      init = stats$init %||% 0L,
      init_failed = stats$init_failed %||% 0L,
      init_skipped = stats$init_skipped %||% 0L,
      closed = stats$closed %||% 0L,
      checkout = stats$checkout %||% 0L,
      checkout_failed = stats$checkout_failed %||% 0L,
      returned = stats$returned %||% 0L,
      outstanding_checkouts = leaked,
      tx_begin = stats$tx_begin %||% 0L,
      tx_commit = stats$tx_commit %||% 0L,
      tx_rollback = stats$tx_rollback %||% 0L,
      direct_fallback = stats$direct_fallback %||% 0L
    ),
    recent_event_count = length(st$events)
  )
}

# Test/maintenance: sayaçları ve olay tamponunu sıfırlar (havuzları KAPATMAZ).
db_pool_reset_stats <- function() {
  st <- .mergen_db_pool_state
  st$events <- list()
  for (nm in names(st$stats)) st$stats[[nm]] <- 0L
  invisible(NULL)
}
