# ==============================================================================
# Dosya Yolu: tests/scripts/run_vm_db_pool_preflight_real.R
# Aciklama:
#   Windows VM uzerinde GERCEK SQL Server'a karsi ISLEM-GUVENLI DB HAVUZUNUN
#   (R/helpers_db_pool.R) MEKANIK + GOZLEMLENEBILIRLIK + FAIL-FAST davranisini
#   on kontrolden gecirir. Bu betik DURUSTCE HAFIF ve VARSAYILAN YIKICI DEGILDIR:
#     - havuz baslar (init_db_pool_once) ve snapshot tutarli/sir-guvenli,
#     - SNAPSHOT alanlari: enabled, active_targets, free/taken, checkout, returned,
#       outstanding_checkouts, tx_begin/commit/rollback, direct_fallback, init_failed,
#     - COKLU checkout/return dongusu (varsayilan 5) sizinti BIRAKMAZ,
#     - with_db_transaction commit yolu calisir (SELECT 1; no-op commit),
#     - with_db_transaction rollback yolu (niyetli hata) baglanti iade eder,
#     - rollback IADEDEN ONCE calisir (havuza acik islemle donulmez),
#     - checkout == returned ve outstanding_checkouts == 0,
#     - Turkce metin parametre round-trip'i (ODBC bind/okuma) korunur (YAZMA YOK).
#
#   Opsiyonel Turkce AT-REST yazma testi (MERGEN_DB_POOL_WRITE_TEST=TRUE): tek,
#   BENZERSIZ etiketli bir tablo olusturur, Turkce metni yazip okur, mojibake
#   kontrol eder, rollback'in satir birakmadigini dogrular, sonra tabloyu DROP
#   eder. Daha kapsamli at-rest/encoding kapisi icin:
#   tests/scripts/run_vm_sqlserver_pool_preflight_real.R.
#
#   FAIL-FAST: MERGEN_DB_POOL_FAIL_FAST=TRUE iken havuz baslatilamazsa preflight
#   HARD FAIL eder (init_db_pool_once stop() eder). Varsayilan (fail-open) modda
#   havuz baslatilamazsa preflight FAIL raporlar ama dogrudan-baglanti yolunun
#   uygulamada calismaya devam edecegini de belirtir.
#
#   GUVENLIK/GUARD:
#     - Havuz acik olmalidir: MERGEN_DB_POOL_ENABLED=TRUE (degilse GUVENLE SKIP).
#     - DB_DSN ayarli olmalidir (degilse GUVENLE SKIP).
#     - Bulut/offline ortamda (pool/odbc/DBI yok) GUVENLE atlar (skipped_reason).
#     - Yazma probe'lari yalniz MERGEN_DB_POOL_WRITE_TEST=TRUE iken calisir.
#     - Ham DSN/parola/secret ASLA loglanmaz/yazilmaz (soak_redact_text + tablo
#       adinda zaman damgasi disinda secret yok).
#     - UNMEASURED bir kontrol ASLA PASS olarak raporlanmaz.
#
#   source(...) ile GUVENLIDIR (quit() yoktur). Rscript altinda, gerekli bir probe
#   basarisizsa stop() ile sifir-disi cikis kodu uretir.
#
#   Bu dosya BILEREK ASCII-guvenlidir (Turkce ozel karakter yok); Turkce fikstur
#   metni \u kacislariyla uretilir (parser-guvenli, Windows VM uyumlu).
# ==============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || is.na(x[1])) y else x

options(warn = 1)
for (.loc in c("C.UTF-8", "en_US.UTF-8", "tr_TR.UTF-8")) {
  if (tryCatch(nzchar(Sys.setlocale("LC_CTYPE", .loc)),
               error = function(e) FALSE, warning = function(w) FALSE)) break
}

dbpf_bool <- function(name, default = FALSE) {
  raw <- tolower(trimws(Sys.getenv(name, unset = "")))
  if (!nzchar(raw)) return(isTRUE(default))
  if (raw %in% c("true", "t", "1", "yes", "y", "on", "evet")) return(TRUE)
  if (raw %in% c("false", "f", "0", "no", "n", "off", "hayir")) return(FALSE)
  isTRUE(default)
}

dbpf_int <- function(name, default) {
  raw <- trimws(Sys.getenv(name, unset = ""))
  if (!nzchar(raw)) return(as.integer(default))
  v <- suppressWarnings(as.integer(raw))
  if (is.na(v) || v < 1L) as.integer(default) else v
}

dbpf_repo_root <- function() {
  for (cand in c(".", "..", "../..")) {
    if (file.exists(file.path(cand, "app.R")) && dir.exists(file.path(cand, "R"))) {
      return(normalizePath(cand, winslash = "/", mustWork = TRUE))
    }
  }
  stop("run_vm_db_pool_preflight_real.R repo kokunden calistirilmalidir.", call. = FALSE)
}

dbpf_repo_root_dir <- dbpf_repo_root()
dbpf_old_wd <- getwd()
setwd(dbpf_repo_root_dir)
on.exit(setwd(dbpf_old_wd), add = TRUE)

# .Renviron (varsa) yukle; mevcut shell degerleri oncelikli. Sozlesme testi/CI
# determinizmi icin acik kacis: MERGEN_DB_POOL_PREFLIGHT_SKIP_RENVIRON acikken repo
# .Renviron'i YENIDEN OKUNMAZ (boylece guard'lar deterministik dogrulanabilir;
# URETIM preflight'i bu bayragi KULLANMAZ).
dbpf_load_renviron <- function(path = ".Renviron") {
  if (dbpf_bool("MERGEN_DB_POOL_PREFLIGHT_SKIP_RENVIRON", FALSE)) return(FALSE)
  if (!file.exists(path)) return(FALSE)
  before <- Sys.getenv(names(Sys.getenv()), unset = NA_character_)
  keep <- names(before)[!is.na(before) & nzchar(before)]
  ok <- tryCatch(readRenviron(path), error = function(e) FALSE, warning = function(w) FALSE)
  if (!isTRUE(ok)) return(FALSE)
  for (nm in keep) do.call(Sys.setenv, stats::setNames(list(unname(before[nm])), nm))
  TRUE
}
invisible(dbpf_load_renviron(".Renviron"))

# Redaksiyon yardimcisini soak'tan al (ASCII-safe); yoksa basit yedek.
dbpf_redact <- function(text) {
  if (exists("soak_redact_text", mode = "function")) return(soak_redact_text(text))
  red_path <- file.path("tests", "scripts", "soak_secret_redaction.R")
  if (file.exists(red_path)) {
    tryCatch(source(red_path, encoding = "UTF-8"), error = function(e) NULL)
    if (exists("soak_redact_text", mode = "function")) return(soak_redact_text(text))
  }
  gsub("sk-[A-Za-z0-9_-]{3,}", "<hidden-key>", as.character(text %||% ""), perl = TRUE)
}

# DB_CLIENT_ENCODING/DB_NAME_ENCODING degerleri SIR DEGILDIR; guvenle gosterilebilir.
dbpf_safe_encoding_label <- function(name) {
  v <- toupper(trimws(Sys.getenv(name, unset = "")))
  if (nzchar(v)) v else "(ayarsiz)"
}

# Turkce at-rest fikstur (parser-guvenli \u kacislari; kaynak ASCII kalir).
dbpf_turkish_fixture <- function() {
  paste0(
    "\u0130stanbul, I\u011fd\u0131r, T\u00fcrk\u00e7e, ",
    "\u011f\u00fc\u015f\u00f6\u00e7\u0131\u0130\u011e\u00dc\u015e\u00d6\u00c7"
  )
}

# Mojibake tespiti: varsa uygulamanin gercek helper'ini kullan; yoksa \u kacisli
# yedek token listesi (kaynak ASCII kalir).
dbpf_has_mojibake <- function(value) {
  if (exists("db_visible_text_has_mojibake", mode = "function")) {
    return(isTRUE(tryCatch(db_visible_text_has_mojibake(value), error = function(e) FALSE)))
  }
  text <- paste(enc2utf8(as.character(value %||% "")), collapse = "\n")
  tokens <- c("\u00c3\u00a7", "\u00c3\u00bc", "\u00c4\u00b1",
              "\u00c3\u00b6", "\u00c5\u00b8", "\u00c4\u009f")
  any(vapply(tokens, function(tok) grepl(tok, text, fixed = TRUE), logical(1)))
}

# ------------------------------------------------------------------------------
# Artifact + sonuc.
# ------------------------------------------------------------------------------
dbpf_ts <- format(Sys.time(), "%Y%m%d-%H%M%S", tz = "UTC")
dbpf_artifact_dir <- file.path("artifacts", "db-pool-preflight", dbpf_ts)
dbpf_cycles <- dbpf_int("MERGEN_DB_POOL_PREFLIGHT_CYCLES", 5L)

dbpf_result <- list(
  schema_version = "1.0",
  gate = "run_vm_db_pool_preflight_real",
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  validation_execution_status = "ran_by_db_pool_preflight",
  ran = FALSE,
  skipped_reason = NA_character_,
  fail_fast_mode = FALSE,
  write_test_enabled = FALSE,
  db_client_encoding = dbpf_safe_encoding_label("DB_CLIENT_ENCODING"),
  db_name_encoding = dbpf_safe_encoding_label("DB_NAME_ENCODING"),
  db_dsn_present = nzchar(Sys.getenv("DB_DSN", "")),
  pool_config = NULL,
  pool_initialized = FALSE,
  pool_active = FALSE,
  init_count = NA_integer_,
  init_failed_count = NA_integer_,
  cycles_requested = dbpf_cycles,
  cycles_ok = NA_integer_,
  read_select_ok = NA,
  tx_commit_ok = NA,
  tx_rollback_returned = NA,
  turkish_param_roundtrip_passed = NA,
  turkish_at_rest_roundtrip_passed = NA,
  tx_rollback_clean = NA,
  checkout_count = NA_integer_,
  returned_count = NA_integer_,
  pool_outstanding_checkouts = NA_integer_,
  direct_fallback_count = NA_integer_,
  mojibake_hits = 0L,
  warnings = character(0),
  db_pool_preflight_passed = FALSE,
  does_prove = character(0),
  does_not_prove = c(
    "Uzun sureli uretim yuku altinda dayaniklilik KANITLAMAZ (operasyonel soak ayri).",
    "Gercek tarayici/websocket eszamanliligini KANITLAMAZ.",
    "Kapasite/throughput kazanimi KANITLAMAZ (yalniz havuz mekanigi/gozlemlenebilirligi).",
    "Bu kapi havuzlu DB yolunun MEKANIK + gozlemlenebilirlik + fail-fast davranisini dogrular."
  )
)

dbpf_finish <- function(passed, skipped_reason = NA_character_) {
  dbpf_result$db_client_encoding <<- dbpf_safe_encoding_label("DB_CLIENT_ENCODING")
  dbpf_result$db_name_encoding <<- dbpf_safe_encoding_label("DB_NAME_ENCODING")
  dbpf_result$db_pool_preflight_passed <<- isTRUE(passed)
  if (!is.na(skipped_reason)) dbpf_result$skipped_reason <<- skipped_reason

  dir.create(dbpf_artifact_dir, recursive = TRUE, showWarnings = FALSE)
  ev_json <- jsonlite::toJSON(dbpf_result, auto_unbox = TRUE, pretty = TRUE, null = "null")
  writeLines(dbpf_redact(as.character(ev_json)),
             file.path(dbpf_artifact_dir, "evidence.json"), useBytes = TRUE)

  md <- c(
    "# DB Havuz Preflight Ozeti (Mekanik + Gozlemlenebilirlik + Fail-fast)",
    "",
    sprintf("- Olusturulma: %s", dbpf_result$created_at),
    sprintf("- Calisti: %s", as.character(dbpf_result$ran)),
    if (!is.na(dbpf_result$skipped_reason)) sprintf("- Atlama nedeni: %s", dbpf_result$skipped_reason) else "",
    sprintf("- Fail-fast modu: %s | Yazma testi: %s",
            as.character(dbpf_result$fail_fast_mode), as.character(dbpf_result$write_test_enabled)),
    sprintf("- DB client encoding: %s | DB name encoding: %s",
            dbpf_result$db_client_encoding, dbpf_result$db_name_encoding),
    sprintf("- Havuz baslatildi: %s | aktif: %s | init: %s | init_failed: %s",
            as.character(dbpf_result$pool_initialized), as.character(dbpf_result$pool_active),
            as.character(dbpf_result$init_count), as.character(dbpf_result$init_failed_count)),
    sprintf("- checkout/return dongusu: %s/%s OK",
            as.character(dbpf_result$cycles_ok), as.character(dbpf_result$cycles_requested)),
    sprintf("- SELECT 1: %s | Turkce param round-trip: %s",
            as.character(dbpf_result$read_select_ok),
            as.character(dbpf_result$turkish_param_roundtrip_passed)),
    sprintf("- tx commit: %s | tx rollback iade: %s | Turkce at-rest: %s | rollback temiz: %s",
            as.character(dbpf_result$tx_commit_ok),
            as.character(dbpf_result$tx_rollback_returned),
            as.character(dbpf_result$turkish_at_rest_roundtrip_passed),
            as.character(dbpf_result$tx_rollback_clean)),
    sprintf("- checkout: %s | returned: %s | bekleyen (leak): %s | direct_fallback: %s",
            as.character(dbpf_result$checkout_count), as.character(dbpf_result$returned_count),
            as.character(dbpf_result$pool_outstanding_checkouts),
            as.character(dbpf_result$direct_fallback_count)),
    sprintf("- mojibake: %s", as.character(dbpf_result$mojibake_hits)),
    sprintf("- GENEL: **%s**",
            if (isTRUE(passed)) "PASS" else if (!is.na(skipped_reason)) "SKIPPED" else "FAIL"),
    ""
  )
  writeLines(dbpf_redact(paste(md[nzchar(md) | md == ""], collapse = "\n")),
             file.path(dbpf_artifact_dir, "summary.md"), useBytes = TRUE)

  cat(sprintf("\nDB havuz preflight: %s\n",
              if (isTRUE(passed)) "PASS" else if (!is.na(skipped_reason)) "SKIPPED" else "FAIL"))
  cat(sprintf("Artifact: %s\n", file.path(dbpf_artifact_dir, "evidence.json")))
}

cat("== DB Havuz Preflight (Mekanik + Gozlemlenebilirlik + Fail-fast) ==\n")

# ------------------------------------------------------------------------------
# GUARD'lar.
# ------------------------------------------------------------------------------
if (!dbpf_bool("MERGEN_DB_POOL_ENABLED", FALSE)) {
  reason <- "MERGEN_DB_POOL_ENABLED!=TRUE; havuz kapali oldugu icin havuzlu preflight atlandi (guvenli)."
  cat(sprintf("SKIP: %s\n", reason))
  dbpf_finish(FALSE, skipped_reason = reason)
} else if (!requireNamespace("pool", quietly = TRUE) ||
           !requireNamespace("odbc", quietly = TRUE) ||
           !requireNamespace("DBI", quietly = TRUE)) {
  reason <- "pool/odbc/DBI paketlerinden biri yok; havuzlu preflight atlandi (bulut/offline)."
  cat(sprintf("SKIP: %s\n", reason))
  dbpf_finish(FALSE, skipped_reason = reason)
} else if (!nzchar(Sys.getenv("DB_DSN", ""))) {
  reason <- "DB_DSN ayarli degil; gercek SQL Server'a baglanilamaz; preflight atlandi."
  cat(sprintf("SKIP: %s\n", reason))
  dbpf_finish(FALSE, skipped_reason = reason)
} else {

  # ----------------------------------------------------------------------------
  # Gercek calisma: yardimcilari yukle, havuzu kur, probe'lari yap.
  # ----------------------------------------------------------------------------
  dbpf_result$ran <- TRUE
  write_test <- dbpf_bool("MERGEN_DB_POOL_WRITE_TEST", FALSE)
  dbpf_result$write_test_enabled <- write_test

  helper_files <- c(
    "R/utils_common.R", "R/utils_text_encoding.R",
    "R/helpers_db_unicode_escape.R", "R/helpers_db_encoding.R",
    "R/helpers_db_connection.R", "R/helpers_db_pool.R"
  )
  for (f in helper_files) {
    tryCatch(source(f, encoding = "UTF-8"),
             error = function(e) dbpf_result$warnings <<- c(dbpf_result$warnings,
               dbpf_redact(sprintf("source(%s): %s", f, conditionMessage(e)))))
  }

  required_fns <- c("init_db_pool_once", "close_db_pool_once", "with_db_connection",
                    "with_db_transaction", "db_pool_status_snapshot", "db_pool_config",
                    "db_pool_reset_stats", "db_pool_is_active",
                    "normalize_db_visible_value", "normalize_db_read_visible_value")
  missing_fns <- required_fns[!vapply(required_fns,
                                      function(fn) exists(fn, mode = "function"), logical(1))]

  if (length(missing_fns) > 0L) {
    reason <- sprintf("Gerekli havuz/encoding fonksiyonlari yuklenemedi: %s",
                      paste(missing_fns, collapse = ", "))
    cat(sprintf("FAIL: %s\n", reason))
    dbpf_finish(FALSE)
    stop(reason, call. = FALSE)
  } else {
    cfg <- db_pool_config()
    dbpf_result$fail_fast_mode <- isTRUE(cfg$fail_fast)
    dbpf_result$pool_config <- list(min_size = cfg$min_size, max_size = cfg$max_size,
                                    idle_timeout_sec = cfg$idle_timeout_sec,
                                    fail_fast = isTRUE(cfg$fail_fast))

    probe_ok <- function(expr) {
      tryCatch(expr, error = function(e) {
        dbpf_result$warnings <<- c(dbpf_result$warnings,
          dbpf_redact(sprintf("probe hatasi: %s", conditionMessage(e))))
        NULL
      })
    }

    db_pool_reset_stats()
    # Fail-fast modunda init_db_pool_once() hata firlatabilir; bu BILEREK
    # yakalanir cunki preflight her durumda sir-guvenli ozet yazmalidir. Fail-fast
    # init hatasi base_pass=FALSE'a yansir (pool_initialized FALSE kalir).
    pool_obj <- probe_ok(init_db_pool_once("primary"))
    dbpf_result$pool_initialized <- !is.null(pool_obj)
    dbpf_result$pool_active <- isTRUE(probe_ok(db_pool_is_active("primary")) %||% FALSE)

    snap0 <- probe_ok(db_pool_status_snapshot())
    if (!is.null(snap0)) {
      dbpf_result$init_count <- as.integer(snap0$counters$init %||% NA)
      dbpf_result$init_failed_count <- as.integer(snap0$counters$init_failed %||% NA)
    }

    if (!isTRUE(dbpf_result$pool_active)) {
      dbpf_result$warnings <- c(dbpf_result$warnings,
        if (isTRUE(cfg$fail_fast)) {
          "Havuz baslatilamadi ve FAIL-FAST acik; preflight FAIL (operatorun istedigi davranis)."
        } else {
          "Havuz baslatilamadi/aktif degil; mekanik probe'lar calismadi (fail-open: uygulama dogrudan baglantiya duser)."
        })
    } else {
      # 1) COKLU checkout/return dongusu (sizinti yok kanaati).
      cycles_ok <- 0L
      for (i in seq_len(dbpf_cycles)) {
        v <- probe_ok(with_db_connection(function(conn) {
          DBI::dbGetQuery(conn, "SELECT 1 AS one")$one[1]
        }))
        if (identical(as.integer(v %||% NA), 1L)) cycles_ok <- cycles_ok + 1L
      }
      dbpf_result$cycles_ok <- cycles_ok
      dbpf_result$read_select_ok <- identical(cycles_ok, as.integer(dbpf_cycles))

      # 2) Turkce param round-trip (YAZMA YOK): ODBC bind + okuma decode.
      tr <- dbpf_turkish_fixture()
      param_back <- probe_ok(with_db_connection(function(conn) {
        DBI::dbGetQuery(conn, "SELECT ? AS t",
                        params = list(normalize_db_visible_value(tr)))$t[1]
      }))
      if (!is.null(param_back)) {
        restored <- normalize_db_read_visible_value(param_back)
        dbpf_result$turkish_param_roundtrip_passed <-
          identical(enc2utf8(restored), enc2utf8(tr)) && !dbpf_has_mojibake(restored)
        if (dbpf_has_mojibake(restored)) dbpf_result$mojibake_hits <- dbpf_result$mojibake_hits + 1L
      }

      # 3) Islem commit yolu (NO-OP guvenli): SELECT 1 -> dogal commit.
      commit_res <- probe_ok(with_db_transaction(function(conn) {
        as.integer(DBI::dbGetQuery(conn, "SELECT 1 AS one")$one[1])
      }))
      dbpf_result$tx_commit_ok <- identical(as.integer(commit_res %||% NA), 1L)

      # 4) Islem rollback yolu (niyetli hata): baglanti IADE edilmeli; sayac artmali.
      ret_before <- as.integer((probe_ok(db_pool_status_snapshot()) %||% list())$counters$returned %||% NA)
      tryCatch(with_db_transaction(function(conn) {
        DBI::dbGetQuery(conn, "SELECT 1 AS one")
        stop("kasitli rollback (mekanik)")
      }), error = function(e) NULL)
      snap_rb <- probe_ok(db_pool_status_snapshot())
      ret_after <- as.integer((snap_rb %||% list())$counters$returned %||% NA)
      rb_count <- as.integer((snap_rb %||% list())$counters$tx_rollback %||% 0L)
      dbpf_result$tx_rollback_returned <- isTRUE(rb_count >= 1L) &&
        isTRUE(!is.na(ret_before) && !is.na(ret_after) && ret_after > ret_before)

      # 5) Opsiyonel YAZMA testi: Turkce at-rest commit/rollback (etiketli tablo + DROP).
      if (isTRUE(write_test)) {
        # SQL Server regular tanimlayicilari tire (-) iceremez; ASCII-disi her seyi temizle.
        tbl_ts <- gsub("[^0-9A-Za-z]", "", dbpf_ts)
        tbl <- sprintf("MB_DbPoolPreflight_%s_%d", tbl_ts,
                       as.integer(stats::runif(1, 1, 1e6)))
        created <- probe_ok(with_db_transaction(function(conn) {
          DBI::dbExecute(conn, sprintf(
            "CREATE TABLE %s (id INT IDENTITY(1,1) PRIMARY KEY, tag NVARCHAR(64), content NVARCHAR(400))",
            tbl))
          TRUE
        }))
        if (isTRUE(created)) {
          on.exit({
            tryCatch(with_db_transaction(function(conn) {
              DBI::dbExecute(conn, sprintf("DROP TABLE %s", tbl)); TRUE
            }), error = function(e) NULL)
          }, add = TRUE)

          tag <- sprintf("dbpool-%s", dbpf_ts)
          probe_ok(with_db_transaction(function(conn) {
            DBI::dbExecute(conn, sprintf("INSERT INTO %s (tag, content) VALUES (?, ?)", tbl),
                           params = list(tag, normalize_db_visible_value(tr)))
            TRUE
          }))
          at_rest <- probe_ok(with_db_connection(function(conn) {
            DBI::dbGetQuery(conn, sprintf("SELECT content FROM %s WHERE tag = ?", tbl),
                            params = list(tag))$content[1]
          }))
          if (!is.null(at_rest)) {
            restored2 <- normalize_db_read_visible_value(at_rest)
            dbpf_result$turkish_at_rest_roundtrip_passed <-
              identical(enc2utf8(restored2), enc2utf8(tr)) && !dbpf_has_mojibake(restored2)
            if (dbpf_has_mojibake(restored2)) dbpf_result$mojibake_hits <- dbpf_result$mojibake_hits + 1L
          }
          # Yazma rollback temizligi: niyetli hata -> satir BIRAKMAMALI.
          before_rb <- probe_ok(with_db_connection(function(conn) {
            DBI::dbGetQuery(conn, sprintf("SELECT COUNT(*) AS n FROM %s", tbl))$n[1]
          }))
          tryCatch(with_db_transaction(function(conn) {
            DBI::dbExecute(conn, sprintf("INSERT INTO %s (tag, content) VALUES (?, ?)", tbl),
                           params = list("rollback-probe", "rollback-probe"))
            stop("kasitli rollback (yazma)")
          }), error = function(e) NULL)
          after_rb <- probe_ok(with_db_connection(function(conn) {
            DBI::dbGetQuery(conn, sprintf("SELECT COUNT(*) AS n FROM %s", tbl))$n[1]
          }))
          dbpf_result$tx_rollback_clean <-
            identical(as.integer(before_rb %||% -1L), as.integer(after_rb %||% -2L))
        } else {
          dbpf_result$warnings <- c(dbpf_result$warnings,
            "Etiketli probe tablosu olusturulamadi (DDL izni yok?); at-rest yazma testi atlandi.")
        }
      }
    }

    # Sizinti kontrolu + kapat.
    snap <- probe_ok(db_pool_status_snapshot())
    if (!is.null(snap)) {
      dbpf_result$checkout_count <- as.integer(snap$counters$checkout %||% NA)
      dbpf_result$returned_count <- as.integer(snap$counters$returned %||% NA)
      dbpf_result$pool_outstanding_checkouts <- as.integer(snap$counters$outstanding_checkouts %||% NA)
      dbpf_result$direct_fallback_count <- as.integer(snap$counters$direct_fallback %||% NA)
    }
    tryCatch(close_db_pool_once(), error = function(e) NULL)

    # ----------------------------------------------------------------------------
    # PASS karari. UNMEASURED (NA) bir alan ASLA PASS sayilmaz.
    # ----------------------------------------------------------------------------
    leak_free <- identical(as.integer(dbpf_result$pool_outstanding_checkouts %||% -1L), 0L)
    balanced <- isTRUE(!is.na(dbpf_result$checkout_count) &&
                       !is.na(dbpf_result$returned_count) &&
                       dbpf_result$checkout_count == dbpf_result$returned_count)
    base_pass <- isTRUE(dbpf_result$pool_active) &&
      identical(as.integer(dbpf_result$init_failed_count %||% -1L), 0L) &&
      isTRUE(dbpf_result$read_select_ok) &&
      isTRUE(dbpf_result$tx_commit_ok) &&
      isTRUE(dbpf_result$tx_rollback_returned) &&
      isTRUE(dbpf_result$turkish_param_roundtrip_passed) &&
      isTRUE(leak_free) && isTRUE(balanced) &&
      identical(as.integer(dbpf_result$mojibake_hits), 0L)

    write_pass <- if (isTRUE(write_test)) {
      isTRUE(dbpf_result$turkish_at_rest_roundtrip_passed) &&
        isTRUE(dbpf_result$tx_rollback_clean)
    } else {
      TRUE
    }

    passed <- base_pass && write_pass

    if (isTRUE(passed)) {
      dbpf_result$does_prove <- c(
        "Havuz gercek SQL Server'a karsi basladi; checkout==return ve outstanding=0 (sizinti yok).",
        sprintf("%d checkout/return dongusu sorunsuz; havuzlu SELECT 1 ve Turkce parametre round-trip'i mojibake'siz.",
                dbpf_cycles),
        "with_db_transaction commit/rollback mekanigi dogru; rollback bagantiyi iade etti (havuza acik islemle donulmedi).",
        if (isTRUE(write_test)) {
          "Turkce metin AT-REST mojibake'siz korundu; yazma rollback'i satir birakmadi."
        } else {
          "Yazma testi kapali; at-rest commit/rollback dogrulanmadi (yalniz mekanik + round-trip)."
        }
      )
    }

    dbpf_finish(passed)

    if (!isTRUE(passed)) {
      stop(sprintf("DB havuz preflight FAIL. Ayrintilar: %s",
                   file.path(dbpf_artifact_dir, "evidence.json")), call. = FALSE)
    }
    cat("OK: DB havuz preflight PASS.\n")
  }
}

invisible(TRUE)
