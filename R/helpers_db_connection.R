# ==============================================================================
# Dosya Yolu: R/helpers_db_connection.R
# Açıklama: Veritabanı bağlantısı, havuz sağlık kontrolü ve worker tarafı
#           güvenli DB bağlantı yardımcılarını içerir.
# ==============================================================================

# Bu dosya test bootstrap içinde cloud-quick modunda da source edilir.
# Bu nedenle odbc/pool gibi ağır runtime paketleri top-level library() ile
# zorunlu kılınmaz; gerçek bağlantı açan fonksiyonlar kendi içinde
# requireNamespace() ile net hata verir.
if (!requireNamespace("DBI", quietly = TRUE)) {
  stop("R/helpers_db_connection.R requires the 'DBI' package.", call. = FALSE)
}

if (!exists("resolve_db_client_encoding", mode = "function", inherits = TRUE) ||
    !exists("normalize_db_params", mode = "function", inherits = TRUE)) {
  stop(
    "R/helpers_db_encoding.R must be sourced before R/helpers_db_connection.R",
    call. = FALSE
  )
}

# ------------------------------------------------------------------------------
# Hafif, opsiyonel performans olcum kancasi (yalnizca MERGEN_PERF_LOG=1 /
# options(mergen.perf_log=TRUE) iken aktiftir). Performans yardimcisi
# yuklenmemisse (izole testler / cloud-quick bootstrap) sessizce devre disi
# kalir. Havuzlama olmadan her cagri yeni bir ODBC baglantisi acip kapattigi
# icin bu kanca, ana Shiny dongusunde olusan baglanti kurma/kapatma suresinin
# olculmesini saglar. Olcum kapaliyken ek maliyet ihmal edilebilir.
# ------------------------------------------------------------------------------
.db_perf_log <- function(event, start = NULL, fields = list()) {
  if (exists("mergen_perf_log", mode = "function", inherits = TRUE)) {
    try(mergen_perf_log(event, start = start, fields = fields), silent = TRUE)
  }
  invisible(NULL)
}

# ------------------------------------------------------------------------------
# Faz 6 (§5.10) — İSTEK ÖMRÜ FARKINDA DB KURULUM/TEARDOWN SINIRI
# ------------------------------------------------------------------------------
# `interruptible = TRUE` yalnızca bağlantı KURULDUKTAN SONRAKİ ifade yürütmesini
# etkiler. Bağlantının kendisini kurmak (DSN çözümleme + login) ve kapatmak
# senkron sürücü çağrılarıdır; bunlar sınırlanmazsa PK isteği hem sert analiz
# son tarihini hem de Durdur'u AŞABİLİR (işçi yuvası + DB oturumu meşgul kalır).
#
# Bütçe YOKSA (`NULL` son tarih / PK dışı çağıran) davranış DEĞİŞMEZ: `Inf`
# bütçe ile `setTimeLimit` hiç kurulmaz.
.db_pk_residual_budget_sec <- function() {
  son_tarih <- getOption("mergen.pk.async.deadline_at", NULL)
  if (is.null(son_tarih)) return(Inf)
  if (!exists("pk_deadline_remaining_sec", mode = "function", inherits = TRUE)) return(Inf)
  kalan <- tryCatch(pk_deadline_remaining_sec(son_tarih), error = function(e) Inf)
  if (length(kalan) != 1L || is.na(kalan)) return(Inf)
  kalan
}

# Teardown bütçe TÜKENMİŞ olsa bile denenmelidir; aksi hâlde bağlantı hiç
# kapatılmaz ve gerçek bir sızıntı oluşurdu. Bu yüzden tabanı vardır.
.db_pk_teardown_budget_sec <- function() {
  kalan <- .db_pk_residual_budget_sec()
  if (!is.finite(kalan)) return(Inf)
  max(2, min(10, kalan))
}

# Kalan bütçeden SÜRÜCÜ login zaman aşımı (saniye, tam sayı).
#
# ODBC `SQL_ATTR_LOGIN_TIMEOUT` saniye çözünürlüğündedir ve `0` = SINIRSIZ
# demektir; bu yüzden taban 1 saniyedir. Bütçe yoksa yapılandırılmış varsayılan
# kullanılır ve PK dışı çağıranların davranışı DEĞİŞMEZ.
.DB_DEFAULT_LOGIN_TIMEOUT_SEC <- 30L

.db_connect_timeout_sec <- function(budget_sec) {
  varsayilan <- suppressWarnings(as.integer(
    Sys.getenv("MERGEN_DB_LOGIN_TIMEOUT_SEC", unset = NA_character_)
  ))
  if (length(varsayilan) != 1L || is.na(varsayilan) || varsayilan < 1L) {
    varsayilan <- .DB_DEFAULT_LOGIN_TIMEOUT_SEC
  }

  butce <- suppressWarnings(as.numeric(budget_sec)[1])
  if (length(butce) != 1L || is.na(butce) || !is.finite(butce)) return(varsayilan)
  max(1L, min(varsayilan, as.integer(floor(butce))))
}

.db_with_elapsed_budget <- function(budget_sec, fn) {
  butce <- suppressWarnings(as.numeric(budget_sec)[1])
  if (length(butce) != 1L || is.na(butce) || !is.finite(butce)) return(fn())
  if (butce <= 0) {
    stop("PK istek butcesi tukendi; DB islemi baslatilmadi.", call. = FALSE)
  }

  on.exit(try(setTimeLimit(cpu = Inf, elapsed = Inf, transient = TRUE), silent = TRUE),
          add = TRUE)
  setTimeLimit(cpu = Inf, elapsed = max(0.05, butce), transient = TRUE)
  fn()
}

.DEFAULT_DSN <- Sys.getenv("DB_DSN", "TestConnection")

get_pool_info <- function() {
  start_time <- Sys.time()
  conn_info <- NULL

  tryCatch({
    conn_info <- get_connection()
    DBI::dbGetQuery(conn_info$conn, "SELECT 1 AS ok")

    elapsed_ms <- round(as.numeric(difftime(Sys.time(), start_time, units = "secs")) * 1000)
    mode_text <- if (isTRUE(conn_info$pooled)) "Bağlantı Havuzu" else "Doğrudan Bağlantı"

    list(
      valid = TRUE,
      mode = mode_text,
      note = sprintf("Veritabanı erişim testi başarılı (%d ms)", elapsed_ms),
      response_ms = elapsed_ms
    )
  }, error = function(e) {
    list(
      valid = FALSE,
      mode = "Doğrudan Bağlantı",
      note = "Veritabanı erişim testi başarısız",
      error = conditionMessage(e)
    )
  }, finally = {
    release_connection(conn_info)
  })
}

db_pool_healthy <- function(timeout_sec = 5) {
  basla <- Sys.time()

  info <- tryCatch({
    setTimeLimit(elapsed = as.numeric(timeout_sec), transient = TRUE)
    on.exit(setTimeLimit(elapsed = Inf, transient = TRUE), add = TRUE)
    get_pool_info()
  }, error = function(e) {
    list(valid = FALSE, error = conditionMessage(e))
  })

  sure <- as.numeric(difftime(Sys.time(), basla, units = "secs"))
  if (sure > as.numeric(timeout_sec)) {
    return(FALSE)
  }

  isTRUE(info$valid)
}

# ------------------------------------------------------------------------------
# VERİTABANI HEDEF TANIMLARI (DATABASE TARGET CONSTANTS)
# ------------------------------------------------------------------------------
# Uygulama genelinde hangi veritabanına gidileceğini belirten standart
# etiketler; `R/library_queries.R` sorguları ve PK analiz modülü kullanır.
#
# `global.R` İÇİNDEN BURAYA TAŞINDI: Faz 6 PK işçisi `global.R`'yi HİÇ
# yüklemez, yalnızca manifest bölümlerini yükler. Tanım orada kaldığı sürece
# temiz bir PSOCK işçisinde `R/library_queries.R` "object 'DB_TARGETS' not
# found" ile düşüyor ve asenkron yol her istekte senkron yedeğe iniyordu.
# Manifest sırası `database` -> `sql_library` olduğundan tanım tüketicilerden
# ÖNCE hazırdır.
DB_TARGETS <- list(
  PRIMARY   = "primary",   # Ana veritabanı (Varsayılan) -> .Renviron: DB_DSN
  SECONDARY = "secondary", # İkincil veritabanı          -> .Renviron: DB_DSN_2
  TERTIARY  = "tertiary"   # Üçüncül veritabanı          -> .Renviron: DB_DSN_3
)

get_connection <- function(target = "primary") {
  dsn_var <- switch(target,
    "primary"   = "DB_DSN",
    "secondary" = "DB_DSN_2",
    "tertiary"  = "DB_DSN_3",
    "DB_DSN"
  )

  if (target == "primary" && exists("pool", envir = .GlobalEnv, inherits = FALSE)) {
    pool_obj <- tryCatch(
      get("pool", envir = .GlobalEnv, inherits = FALSE),
      error = function(e) NULL
    )

    if (!is.null(pool_obj) && inherits(pool_obj, "Pool")) {
      .db_perf_log("db.connection_open", fields = list(target = target, pooled = TRUE))
      return(list(conn = pool_obj, pooled = TRUE, pool = pool_obj))
    }
  }

  if (!requireNamespace("odbc", quietly = TRUE) || !requireNamespace("DBI", quietly = TRUE)) {
    stop("Worker/process requires 'odbc' and 'DBI' packages installed.", call. = FALSE)
  }

  dsn_name <- Sys.getenv(dsn_var, .DEFAULT_DSN)

  if (identical(dsn_name, "")) {
    stop(
      sprintf(
        "HATA: '%s' için .Renviron içinde DSN tanımı bulunamadı (Target: %s)",
        dsn_var,
        target
      ),
      call. = FALSE
    )
  }

  conn_start <- proc.time()[["elapsed"]]
  # Faz 6 (§5.10): bağlantı KURULUMU da istek bütçesine dahildir. Yavaş bir
  # DSN/login, kalan analiz bütçesinin ötesine geçebilir ve stop-file bu sırada
  # yoklanamaz; bu yüzden kurulum kalan bütçeyle SINIRLANIR.
  conn_budget <- .db_pk_residual_budget_sec()
  # SÜRÜCÜ SEVİYESİ LOGIN ZAMAN AŞIMI.
  #
  # `setTimeLimit()` İŞ BİRLİĞİNE dayalıdır: derlenmiş çağrılar onu yalnızca
  # kesme noktalarında gözler ve `odbc`'nin `interruptible = TRUE` desteği
  # `SQLExecute`/`SQLExecuteDirect` içindir — BAĞLANTI KURULUMUNU kapsamaz.
  # Yavaş bir DSN/login bu yüzden yalnızca elapsed sınırıyla GARANTİ altına
  # alınamaz. `odbc::dbConnect(..., timeout = )` bunu sürücüye devreder.
  login_timeout <- .db_connect_timeout_sec(conn_budget)
  conn <- .db_with_elapsed_budget(conn_budget, function() {
    DBI::dbConnect(
      odbc::odbc(),
      dsn = dsn_name,
      encoding = .DEFAULT_DB_CLIENT_ENCODING,
      name_encoding = .DEFAULT_DB_NAME_ENCODING,
      timeout = login_timeout,
      # PSOCK workers are non-interactive, so odbc otherwise defaults this to
      # FALSE. The bounded PK executor relies on R interrupts to trigger
      # odbc's SQLCancel path while SQLExecute/SQLExecuteDirect is blocked.
      interruptible = TRUE
    )
  })
  .db_perf_log("db.connection_open", start = conn_start,
               fields = list(target = target, pooled = FALSE))

  list(conn = conn, pooled = FALSE, pool = NULL)
}

release_connection <- function(conn_info) {
  if (is.null(conn_info)) return(invisible(NULL))

  if (isTRUE(conn_info$pooled)) {
    return(invisible(NULL))
  }

  close_start <- proc.time()[["elapsed"]]
  # Faz 6: `dbDisconnect()` senkron bir sürücü çağrısıdır. Zaman aşımına
  # uğramış/iptal edilmiş bir istekte teardown askıda kalırsa, işçi yuvası
  # sert analiz son tarihinin ÖTESİNDE meşgul kalırdı. Temizliğin kendi
  # tabanı vardır: bütçe tükenmiş olsa bile kapatma denenmelidir.
  kapatildi <- tryCatch({
    .db_with_elapsed_budget(.db_pk_teardown_budget_sec(), function() {
      DBI::dbDisconnect(conn_info$conn)
    })
    TRUE
  }, error = function(e) FALSE)

  if (isTRUE(kapatildi)) {
    .db_perf_log("db.connection_close", start = close_start, fields = list(pooled = FALSE))
    return(invisible(NULL))
  }

  # SINIRLI KAPATMA BAŞARISIZ. Hatayı yutup tek uygulama referansını düşürmek,
  # fiziksel SQL Server oturumunu bir finalizer/GC'ye kadar AÇIK bırakır; arka
  # arkaya yavaş kapanışlar bağlantı kapasitesini tüketebilir. Bu yüzden
  # BÜTÇESİZ (son çare) bir kapatma denenir ve sonuç AÇIKÇA loglanır.
  yeniden <- tryCatch({ DBI::dbDisconnect(conn_info$conn); TRUE }, error = function(e) FALSE)
  .db_perf_log("db.connection_close", start = close_start,
               fields = list(pooled = FALSE, bounded_close_failed = TRUE,
                             forced_close_ok = isTRUE(yeniden)))
  if (!isTRUE(yeniden) && exists("log_warn", mode = "function", inherits = TRUE)) {
    try(log_warn("[DB] Baglanti kapatilamadi; fiziksel oturum ACIK kalmis olabilir."),
        silent = TRUE)
  }

  invisible(NULL)
}

worker_db_connect <- function(max_retries = 3, retry_delay = 1) {
  for (i in seq_len(max_retries)) {
    tryCatch({
      if (!requireNamespace("odbc", quietly = TRUE) || !requireNamespace("DBI", quietly = TRUE)) {
        stop("Worker needs 'odbc' and 'DBI' packages installed.", call. = FALSE)
      }

      conn <- DBI::dbConnect(
        odbc::odbc(),
        dsn = Sys.getenv("DB_DSN", .DEFAULT_DSN),
        encoding = .DEFAULT_DB_CLIENT_ENCODING,
        name_encoding = .DEFAULT_DB_NAME_ENCODING,
        interruptible = TRUE
      )

      return(conn)
    }, error = function(e) {
      if (i == max_retries) {
        stop(
          paste("Failed to connect to database after", max_retries, "attempts:", e$message),
          call. = FALSE
        )
      }

      Sys.sleep(retry_delay * i)
    })
  }
}
