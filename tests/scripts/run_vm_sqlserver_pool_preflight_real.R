# ==============================================================================
# Dosya Yolu: tests/scripts/run_vm_sqlserver_pool_preflight_real.R
# Aciklama:
#   Windows VM uzerinde GERCEK SQL Server'a karsi ISLEM-GUVENLI DB HAVUZUNUN
#   (R/helpers_db_pool.R) dogru davrandigini ON KONTROLDEN gecirir:
#     - havuz baslar (init_db_pool_once),
#     - checkout/return dengeli (baglanti sizintisi yok),
#     - with_db_transaction commit yolu calisir,
#     - rollback yolu satir BIRAKMAZ,
#     - Turkce metin parametre round-trip'i (ODBC bind/okuma) korunur,
#     - (yazma testi acilirsa) Turkce metin AT-REST (diske yazilip okunarak)
#       mojibake'siz korunur.
#
#   GUVENLIK/GUARD:
#     - Yalniz MERGEN_SQLSERVER_POOL_PREFLIGHT_REAL=TRUE iken calisir.
#     - Havuz acik olmalidir: MERGEN_DB_POOL_ENABLED=TRUE.
#     - Yazma probe'lari yalniz MERGEN_SQLSERVER_POOL_WRITE_TEST=TRUE iken calisir.
#     - Yikici islem YAPMAZ: yazma testi tek, BENZERSIZ etiketli bir tablo olusturur,
#       probe'lari yapar ve tabloyu DROP eder (temizler).
#     - Bulut/offline ortamda (pool/odbc/DB_DSN yok) GUVENLE atlar (skipped_reason).
#     - Ham DSN/parola/secret ASLA loglanmaz/yazilmaz.
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

sqlpf_bool <- function(name, default = FALSE) {
  raw <- tolower(trimws(Sys.getenv(name, unset = "")))
  if (!nzchar(raw)) return(isTRUE(default))
  if (raw %in% c("true", "t", "1", "yes", "y", "on", "evet")) return(TRUE)
  if (raw %in% c("false", "f", "0", "no", "n", "off", "hayir")) return(FALSE)
  isTRUE(default)
}

sqlpf_repo_root <- function() {
  for (cand in c(".", "..", "../..")) {
    if (file.exists(file.path(cand, "app.R")) && dir.exists(file.path(cand, "R"))) {
      return(normalizePath(cand, winslash = "/", mustWork = TRUE))
    }
  }
  stop("run_vm_sqlserver_pool_preflight_real.R repo kokunden calistirilmalidir.", call. = FALSE)
}

sqlpf_repo_root_dir <- sqlpf_repo_root()
sqlpf_old_wd <- getwd()
setwd(sqlpf_repo_root_dir)
on.exit(setwd(sqlpf_old_wd), add = TRUE)

# .Renviron (varsa) yukle; mevcut shell degerleri oncelikli.
sqlpf_load_renviron <- function(path = ".Renviron") {
  if (!file.exists(path)) return(FALSE)
  before <- Sys.getenv(names(Sys.getenv()), unset = NA_character_)
  keep <- names(before)[!is.na(before) & nzchar(before)]
  ok <- tryCatch(readRenviron(path), error = function(e) FALSE, warning = function(w) FALSE)
  if (!isTRUE(ok)) return(FALSE)
  for (nm in keep) do.call(Sys.setenv, stats::setNames(list(unname(before[nm])), nm))
  TRUE
}
invisible(sqlpf_load_renviron(".Renviron"))

# Redaksiyon yardimcisini soak'tan al (ASCII-safe); yoksa basit yedek.
sqlpf_redact <- function(text) {
  red_path <- file.path("tests", "scripts", "soak_secret_redaction.R")
  if (exists("soak_redact_text", mode = "function")) {
    return(soak_redact_text(text))
  }
  if (file.exists(red_path)) {
    tryCatch(source(red_path, encoding = "UTF-8"), error = function(e) NULL)
    if (exists("soak_redact_text", mode = "function")) return(soak_redact_text(text))
  }
  gsub("sk-[A-Za-z0-9_-]{3,}", "<hidden-key>", as.character(text %||% ""), perl = TRUE)
}

# DB_CLIENT_ENCODING/DB_NAME_ENCODING degerleri SIR DEGILDIR (orn WINDOWS-1254);
# guvenle gosterilebilir. DSN ise gosterilmez.
sqlpf_safe_encoding_label <- function(name) {
  v <- toupper(trimws(Sys.getenv(name, unset = "")))
  if (nzchar(v)) v else "(ayarsiz)"
}

# Turkce at-rest fikstur (parser-guvenli \u kacislari; kaynak ASCII kalir, calisma
# zamani dogru UTF-8 Turkce uretir.
sqlpf_turkish_fixture <- function() {
  paste0(
    "\u0130stanbul, Ankara, T\u00fcrk\u00e7e, ",
    "\u011f\u00fc\u015f\u00f6\u00e7\u0131\u0130\u011e\u00dc\u015e\u00d6\u00c7"
  )
}

# Mojibake tespiti: varsa uygulamanin gercek helper'ini kullan; yoksa \u kacisli
# yedek token listesi (kaynak ASCII kalir).
sqlpf_has_mojibake <- function(value) {
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
sqlpf_ts <- format(Sys.time(), "%Y%m%d-%H%M%S", tz = "UTC")
sqlpf_artifact_dir <- file.path("artifacts", "sqlserver-pool-preflight", sqlpf_ts)

sqlpf_result <- list(
  schema_version = "1.0",
  gate = "run_vm_sqlserver_pool_preflight_real",
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  validation_execution_status = "ran_by_sqlserver_pool_preflight",
  ran = FALSE,
  skipped_reason = NA_character_,
  write_test_enabled = FALSE,
  db_client_encoding = sqlpf_safe_encoding_label("DB_CLIENT_ENCODING"),
  db_name_encoding = sqlpf_safe_encoding_label("DB_NAME_ENCODING"),
  db_dsn_present = nzchar(Sys.getenv("DB_DSN", "")),
  pool_config = NULL,
  pool_initialized = FALSE,
  read_select_ok = NA,
  turkish_param_roundtrip_passed = NA,
  tx_commit_ok = NA,
  tx_rollback_clean = NA,
  turkish_at_rest_roundtrip_passed = NA,
  pool_outstanding_checkouts = NA_integer_,
  mojibake_hits = 0L,
  warnings = character(0),
  sqlserver_pool_preflight_passed = FALSE,
  does_prove = character(0),
  does_not_prove = c(
    "Uzun sureli uretim yuku altinda dayaniklilik KANITLAMAZ (operasyonel soak ayri).",
    "Gercek tarayici/websocket eszamanliligini KANITLAMAZ.",
    "Bu kapi yalniz havuzlu DB yolunu + Turkce at-rest/round-trip'i dogrular."
  )
)

sqlpf_finish <- function(passed, skipped_reason = NA_character_) {
  sqlpf_result$db_client_encoding <<- sqlpf_safe_encoding_label("DB_CLIENT_ENCODING")
  sqlpf_result$db_name_encoding <<- sqlpf_safe_encoding_label("DB_NAME_ENCODING")
  sqlpf_result$sqlserver_pool_preflight_passed <<- isTRUE(passed)
  if (!is.na(skipped_reason)) sqlpf_result$skipped_reason <<- skipped_reason

  dir.create(sqlpf_artifact_dir, recursive = TRUE, showWarnings = FALSE)
  ev_json <- jsonlite::toJSON(sqlpf_result, auto_unbox = TRUE, pretty = TRUE, null = "null")
  writeLines(sqlpf_redact(as.character(ev_json)),
             file.path(sqlpf_artifact_dir, "evidence.json"), useBytes = TRUE)

  md <- c(
    "# SQL Server Havuzlu DB Preflight Ozeti",
    "",
    sprintf("- Olusturulma: %s", sqlpf_result$created_at),
    sprintf("- Calisti: %s", as.character(sqlpf_result$ran)),
    if (!is.na(sqlpf_result$skipped_reason)) sprintf("- Atlama nedeni: %s", sqlpf_result$skipped_reason) else "",
    sprintf("- Yazma testi: %s", as.character(sqlpf_result$write_test_enabled)),
    sprintf("- DB client encoding: %s | DB name encoding: %s",
            sqlpf_result$db_client_encoding, sqlpf_result$db_name_encoding),
    sprintf("- Havuz baslatildi: %s | bekleyen checkout: %s",
            as.character(sqlpf_result$pool_initialized),
            as.character(sqlpf_result$pool_outstanding_checkouts)),
    sprintf("- SELECT 1: %s | Turkce param round-trip: %s",
            as.character(sqlpf_result$read_select_ok),
            as.character(sqlpf_result$turkish_param_roundtrip_passed)),
    sprintf("- tx commit: %s | tx rollback temiz: %s | Turkce at-rest round-trip: %s",
            as.character(sqlpf_result$tx_commit_ok),
            as.character(sqlpf_result$tx_rollback_clean),
            as.character(sqlpf_result$turkish_at_rest_roundtrip_passed)),
    sprintf("- mojibake: %s", as.character(sqlpf_result$mojibake_hits)),
    sprintf("- GENEL: **%s**",
            if (isTRUE(passed)) "PASS" else if (!is.na(skipped_reason)) "SKIPPED" else "FAIL"),
    ""
  )
  writeLines(sqlpf_redact(paste(md[nzchar(md) | md == ""], collapse = "\n")),
             file.path(sqlpf_artifact_dir, "summary.md"), useBytes = TRUE)

  cat(sprintf("\nSQL Server havuz preflight: %s\n",
              if (isTRUE(passed)) "PASS" else if (!is.na(skipped_reason)) "SKIPPED" else "FAIL"))
  cat(sprintf("Artifact: %s\n", file.path(sqlpf_artifact_dir, "evidence.json")))
}

cat("== SQL Server Havuzlu DB Preflight ==\n")

# ------------------------------------------------------------------------------
# GUARD'lar.
# ------------------------------------------------------------------------------
if (!sqlpf_bool("MERGEN_SQLSERVER_POOL_PREFLIGHT_REAL", FALSE)) {
  reason <- "MERGEN_SQLSERVER_POOL_PREFLIGHT_REAL!=TRUE; gercek SQL Server havuz preflight atlandi (guvenli)."
  cat(sprintf("SKIP: %s\n", reason))
  sqlpf_finish(FALSE, skipped_reason = reason)
} else if (!sqlpf_bool("MERGEN_DB_POOL_ENABLED", FALSE)) {
  reason <- "MERGEN_DB_POOL_ENABLED!=TRUE; havuz kapali oldugu icin havuzlu preflight atlandi."
  cat(sprintf("SKIP: %s\n", reason))
  sqlpf_finish(FALSE, skipped_reason = reason)
} else if (!requireNamespace("pool", quietly = TRUE) ||
           !requireNamespace("odbc", quietly = TRUE) ||
           !requireNamespace("DBI", quietly = TRUE)) {
  reason <- "pool/odbc/DBI paketlerinden biri yok; havuzlu SQL Server preflight atlandi (bulut/offline)."
  cat(sprintf("SKIP: %s\n", reason))
  sqlpf_finish(FALSE, skipped_reason = reason)
} else if (!nzchar(Sys.getenv("DB_DSN", ""))) {
  reason <- "DB_DSN ayarli degil; gercek SQL Server'a baglanilamaz; preflight atlandi."
  cat(sprintf("SKIP: %s\n", reason))
  sqlpf_finish(FALSE, skipped_reason = reason)
} else {

  # ----------------------------------------------------------------------------
  # Gercek calisma: yardimcilari yukle, havuzu kur, probe'lari yap.
  # ----------------------------------------------------------------------------
  sqlpf_result$ran <- TRUE
  write_test <- sqlpf_bool("MERGEN_SQLSERVER_POOL_WRITE_TEST", FALSE)
  sqlpf_result$write_test_enabled <- write_test

  helper_files <- c(
    "R/utils_common.R", "R/utils_text_encoding.R",
    "R/helpers_db_unicode_escape.R", "R/helpers_db_encoding.R",
    "R/helpers_db_connection.R", "R/helpers_db_pool.R"
  )
  for (f in helper_files) {
    tryCatch(source(f, encoding = "UTF-8"),
             error = function(e) sqlpf_result$warnings <<- c(sqlpf_result$warnings,
               sqlpf_redact(sprintf("source(%s): %s", f, conditionMessage(e)))))
  }

  required_fns <- c("init_db_pool_once", "close_db_pool_once", "with_db_connection",
                    "with_db_transaction", "db_pool_status_snapshot",
                    "db_pool_reset_stats", "normalize_db_visible_value",
                    "normalize_db_read_visible_value")
  missing_fns <- required_fns[!vapply(required_fns,
                                      function(fn) exists(fn, mode = "function"), logical(1))]

  if (length(missing_fns) > 0L) {
    reason <- sprintf("Gerekli havuz/encoding fonksiyonlari yuklenemedi: %s",
                      paste(missing_fns, collapse = ", "))
    cat(sprintf("FAIL: %s\n", reason))
    sqlpf_finish(FALSE)
    stop(reason, call. = FALSE)
  } else {
    cfg <- db_pool_config()
    sqlpf_result$pool_config <- list(min_size = cfg$min_size, max_size = cfg$max_size,
                                     idle_timeout_sec = cfg$idle_timeout_sec)

    db_pool_reset_stats()
    pool_obj <- tryCatch(init_db_pool_once("primary"), error = function(e) {
      sqlpf_result$warnings <<- c(sqlpf_result$warnings,
        sqlpf_redact(sprintf("init_db_pool_once: %s", conditionMessage(e))))
      NULL
    })
    sqlpf_result$pool_initialized <- !is.null(pool_obj) &&
      isTRUE(tryCatch(db_pool_is_active("primary"), error = function(e) FALSE))

    probe_ok <- function(expr) {
      tryCatch(expr, error = function(e) {
        sqlpf_result$warnings <<- c(sqlpf_result$warnings,
          sqlpf_redact(sprintf("probe hatasi: %s", conditionMessage(e))))
        NULL
      })
    }

    if (!isTRUE(sqlpf_result$pool_initialized)) {
      sqlpf_result$warnings <- c(sqlpf_result$warnings,
        "Havuz baslatilamadi/aktif degil; SELECT/round-trip probe'lari calismadi.")
    } else {
      # 1) Salt-okunur SELECT 1.
      sel <- probe_ok(with_db_connection(function(conn) {
        DBI::dbGetQuery(conn, "SELECT 1 AS one")$one[1]
      }))
      sqlpf_result$read_select_ok <- identical(as.integer(sel %||% NA), 1L)

      # 2) Turkce param round-trip (YAZMA YOK): ODBC bind + okuma decode.
      tr <- sqlpf_turkish_fixture()
      param_back <- probe_ok(with_db_connection(function(conn) {
        DBI::dbGetQuery(conn, "SELECT ? AS t",
                        params = list(normalize_db_visible_value(tr)))$t[1]
      }))
      if (!is.null(param_back)) {
        restored <- normalize_db_read_visible_value(param_back)
        sqlpf_result$turkish_param_roundtrip_passed <-
          identical(enc2utf8(restored), enc2utf8(tr)) && !sqlpf_has_mojibake(restored)
        if (sqlpf_has_mojibake(restored)) sqlpf_result$mojibake_hits <- sqlpf_result$mojibake_hits + 1L
      }

      # 3) Yazma testi (opsiyonel): benzersiz etiketli tablo + commit/rollback/at-rest.
      if (isTRUE(write_test)) {
        tbl <- sprintf("MB_SoakPoolPreflight_%s_%d", sqlpf_ts,
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

          tag <- sprintf("soakpool-%s", sqlpf_ts)

          # 3a) commit yolu: bir satir ekle (commit).
          ins <- probe_ok(with_db_transaction(function(conn) {
            DBI::dbExecute(conn, sprintf("INSERT INTO %s (tag, content) VALUES (?, ?)", tbl),
                           params = list(tag, normalize_db_visible_value(tr)))
            TRUE
          }))
          cnt_after_commit <- probe_ok(with_db_connection(function(conn) {
            DBI::dbGetQuery(conn, sprintf("SELECT COUNT(*) AS n FROM %s WHERE tag = ?", tbl),
                            params = list(tag))$n[1]
          }))
          sqlpf_result$tx_commit_ok <- isTRUE(ins) &&
            identical(as.integer(cnt_after_commit %||% 0L), 1L)

          # 3b) at-rest: AYRI bir checkout ile geri oku + Turkce dogrula.
          at_rest <- probe_ok(with_db_connection(function(conn) {
            DBI::dbGetQuery(conn, sprintf("SELECT content FROM %s WHERE tag = ?", tbl),
                            params = list(tag))$content[1]
          }))
          if (!is.null(at_rest)) {
            restored2 <- normalize_db_read_visible_value(at_rest)
            sqlpf_result$turkish_at_rest_roundtrip_passed <-
              identical(enc2utf8(restored2), enc2utf8(tr)) && !sqlpf_has_mojibake(restored2)
            if (sqlpf_has_mojibake(restored2)) sqlpf_result$mojibake_hits <- sqlpf_result$mojibake_hits + 1L
          }

          # 3c) rollback yolu: niyetli hata -> satir BIRAKMAMALI.
          before_rb <- probe_ok(with_db_connection(function(conn) {
            DBI::dbGetQuery(conn, sprintf("SELECT COUNT(*) AS n FROM %s", tbl))$n[1]
          }))
          tryCatch(with_db_transaction(function(conn) {
            DBI::dbExecute(conn, sprintf("INSERT INTO %s (tag, content) VALUES (?, ?)", tbl),
                           params = list("rollback-probe", "rollback-probe"))
            stop("kasitli rollback")
          }), error = function(e) NULL)
          after_rb <- probe_ok(with_db_connection(function(conn) {
            DBI::dbGetQuery(conn, sprintf("SELECT COUNT(*) AS n FROM %s", tbl))$n[1]
          }))
          sqlpf_result$tx_rollback_clean <-
            identical(as.integer(before_rb %||% -1L), as.integer(after_rb %||% -2L))
        } else {
          sqlpf_result$warnings <- c(sqlpf_result$warnings,
            "Etiketli probe tablosu olusturulamadi (DDL izni yok?); at-rest yazma testi atlandi.")
        }
      } else {
        sqlpf_result$warnings <- c(sqlpf_result$warnings,
          "MERGEN_SQLSERVER_POOL_WRITE_TEST!=TRUE; at-rest yazma probe'lari calismadi (yalniz round-trip).")
      }
    }

    # Havuz sizinti kontrolu + kapat.
    snap <- tryCatch(db_pool_status_snapshot(), error = function(e) NULL)
    if (!is.null(snap)) {
      sqlpf_result$pool_outstanding_checkouts <- as.integer(snap$counters$outstanding_checkouts %||% NA)
    }
    tryCatch(close_db_pool_once(), error = function(e) NULL)

    # ----------------------------------------------------------------------------
    # PASS karari: gerekli probe'lar (init + select + param round-trip + leak yok).
    # at-rest/rollback yalniz write_test aciksa GEREKLIDIR.
    # ----------------------------------------------------------------------------
    leak_free <- identical(as.integer(sqlpf_result$pool_outstanding_checkouts %||% -1L), 0L)
    base_pass <- isTRUE(sqlpf_result$pool_initialized) &&
      isTRUE(sqlpf_result$read_select_ok) &&
      isTRUE(sqlpf_result$turkish_param_roundtrip_passed) &&
      isTRUE(leak_free) &&
      identical(as.integer(sqlpf_result$mojibake_hits), 0L)

    write_pass <- if (isTRUE(write_test)) {
      isTRUE(sqlpf_result$tx_commit_ok) &&
        isTRUE(sqlpf_result$tx_rollback_clean) &&
        isTRUE(sqlpf_result$turkish_at_rest_roundtrip_passed)
    } else {
      TRUE
    }

    passed <- base_pass && write_pass

    if (isTRUE(passed)) {
      sqlpf_result$does_prove <- c(
        "Havuz gercek SQL Server'a karsi basladi; checkout/return dengeli (sizinti yok).",
        "Havuzlu baglantida SELECT 1 ve Turkce parametre round-trip'i mojibake'siz calisti.",
        if (isTRUE(write_test)) {
          "with_db_transaction commit/rollback dogru; rollback satir birakmadi; Turkce metin AT-REST mojibake'siz korundu."
        } else {
          "Yazma testi kapali; commit/rollback/at-rest dogrulanmadi (yalniz round-trip)."
        }
      )
    }

    sqlpf_finish(passed)

    if (!isTRUE(passed)) {
      stop(sprintf("SQL Server havuz preflight FAIL. Ayrintilar: %s",
                   file.path(sqlpf_artifact_dir, "evidence.json")), call. = FALSE)
    }
    cat("OK: SQL Server havuz preflight PASS.\n")
  }
}

invisible(TRUE)
