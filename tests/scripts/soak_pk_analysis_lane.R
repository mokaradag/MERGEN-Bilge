# ==============================================================================
# Dosya Yolu: tests/scripts/soak_pk_analysis_lane.R
# Aciklama:
#   FAZ 6 PK-ANALIZ soak seridi. Proje ve Kaynak Analizi'nin BLOKLAMAYAN
#   yurutme katmanini (iptal jetonu, son tarih aritmetigi, boyut sinirli LRU
#   onbellek, sinirli SQL getirimi, istek-kimligi korumasi ve isci-guvenli
#   anlik goruntu) YUK ALTINDA calistirir.
#
#   Neden gerekli: iki-tarayici mutlu-yol kontrolu iptal firtinasi, isci havuzu
#   doygunlugu, bayat tamamlanma ve surekli onbellek/baglanti baskisini
#   OLCEMEZ. Faz 6 plandaki en riskli eszamanlilik degisikligidir.
#
#   Serit sunlari uretir:
#     - eszamanli-benzeri analiz istekleri (istek-kimligi yasam dongusu)
#     - iptal firtinasi (jeton dosyasi ile GERCEK iptal)
#     - bayat tamamlanma (daha yeni istek eski geri cagriyi gecersiz kilar)
#     - isci havuzu baskisi (kapasite kapisi kararlari)
#     - tekrarlayan/onbelleklenebilir istekler (hit orani + tahliye)
#     - baglanti alma/birakma muhasebesi (GERCEK RSQLite, sinirli getirim)
#     - Derin Dusunme coklu sorgu (son tarih ardisik sorgulara bolunur)
#
#   DURUSTLUK SINIRI: bu serit GERCEK iptal/son tarih/onbellek/istek-kimligi
#   karar yollarini ve GERCEK DBI sinirli getirimini tekrar yuk altinda
#   dogrular; ANCAK tek-surecte ardisik oturumlardir (gercek tarayici/websocket
#   DEGIL), gercek LLM YOKTUR, gercek future isci havuzu YOKTUR ve uretim
#   SQL Server T-SQL'i DEGIL lane-yerel SQLite SQL'i kullanilir. Bu sinirlar
#   evidence icinde does_not_prove altinda ACIKCA yazilir.
#
#   Bu dosya BILEREK ASCII-guvenlidir (Turkce ozel karakter yok); operasyonel
#   giris noktasi zincirindedir ve farkli locale'lerde source edilir.
# ==============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || is.na(x[1])) y else x

soak_pk_repo_root <- function() {
  env_root <- Sys.getenv("MERGEN_REPO_ROOT", unset = "")
  for (cand in c(env_root, ".", "..", "../..", "../../..")) {
    if (!nzchar(cand)) next
    if (file.exists(file.path(cand, "app.R")) && dir.exists(file.path(cand, "R"))) {
      return(normalizePath(cand, winslash = "/", mustWork = FALSE))
    }
  }
  normalizePath(".", winslash = "/", mustWork = FALSE)
}

# Faz 6 katmani icin GERCEK uygulama yardimcilarini yukler (caller UTF-8
# locale ayarlamali). Calisma dizininden bagimsizdir.
soak_pk_bootstrap <- function() {
  root <- soak_pk_repo_root()
  files <- c(
    "R/utils_common.R", "R/utils_text_encoding.R",
    "R/helpers_db_unicode_escape.R", "R/helpers_db_encoding.R",
    "R/helpers_pk_config.R",
    "R/helpers_pk_async_cancel.R",
    "R/helpers_pk_result_size.R",
    "R/helpers_pk_cache.R",
    "R/helpers_pk_sql_execute.R",
    "R/helpers_pk_async_bootstrap.R",
    "R/helpers_pk_async_request.R",
    "R/helpers_deep_analysis_reconcile.R"
  )
  ok <- TRUE
  for (f in files) {
    res <- tryCatch({
      suppressWarnings(suppressMessages(source(file.path(root, f), encoding = "UTF-8")))
      TRUE
    }, error = function(e) FALSE)
    if (!isTRUE(res)) ok <- FALSE
  }

  required_fns <- c(
    "pk_cancel_token_path", "pk_cancel_token_signal", "pk_cancel_token_is_signalled",
    "pk_cancel_token_clear", "pk_deadline_at", "pk_sql_timeout_plan",
    "pk_async_stage_gate", "pk_async_should_apply", "pk_async_build_request",
    "pk_async_validate_request", "pk_cache_key", "pk_cache_get", "pk_cache_put",
    "pk_cache_stats", "pk_cache_reset", "pk_cache_rls_signature",
    "pk_sql_execute_bounded", "pk_row_cap_plan", "pk_deep_reconcile_packets"
  )
  present <- vapply(required_fns, function(fn) exists(fn, mode = "function"), logical(1))

  available <- ok && all(present) &&
    requireNamespace("RSQLite", quietly = TRUE) &&
    requireNamespace("DBI", quietly = TRUE)

  list(available = available, missing_fns = required_fns[!present])
}

# Lane-yerel SQLite: GERCEK sinirli getirim yolunu (dbSendQuery + parcali
# dbFetch + parca arasi iptal/son tarih yoklamasi) calistirmak icin.
soak_pk_make_db <- function(rows = 20000L) {
  path <- tempfile(pattern = "soak_pk_", fileext = ".sqlite")
  conn <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbWriteTable(conn, "pk_veri", data.frame(
    id = seq_len(rows),
    proje = paste0("PROJE-", sprintf("%05d", seq_len(rows))),
    tutar = as.numeric(seq_len(rows)) * 1.37,
    stringsAsFactors = FALSE
  ))
  list(conn = conn, path = path)
}

soak_pk_quantile <- function(x, p) {
  x <- x[is.finite(x)]
  if (!length(x)) return(NA_real_)
  as.numeric(stats::quantile(x, probs = p, names = FALSE, type = 7))
}

# Bir "oturum": istek kimligi uret -> anlik goruntu kur ve DOGRULA -> onbellek
# yokla -> sinirli SQL getir -> satir tavani plani -> istek-kimligi korumasini
# uygula. Iptal edilen turlarda GERCEK jeton dosyasi yazilir.
soak_pk_one_session <- function(idx, conn, token_root, cfg_lane) {
  started <- Sys.time()
  req_id <- sprintf("soak_pk_%06d", idx)
  # Kullanici sayisi kadar farkli YETKI KAPSAMI: onbellek izolasyonu gercekten
  # test edilsin (ayni kullanicinin sonucu baskasina verilmemeli).
  user_id <- ((idx - 1L) %% cfg_lane$distinct_users) + 1L
  username <- sprintf("soak.kullanici%02d", user_id)

  rls_info <- list(
    authorized = TRUE, username = username,
    projects = sprintf("PROJE-%05d", seq_len(10L) + user_id * 10L)
  )
  rls_sig <- pk_cache_rls_signature(rls_info)

  # Tekrarlayan (onbelleklenebilir) istek: sorgu kimligi kucuk bir kumeden
  # secilir ki hit orani gercekten olculebilsin.
  query_id <- sprintf("q%03d", ((idx - 1L) %% cfg_lane$distinct_queries) + 1L)
  filter_sig <- sprintf("f%d", (idx - 1L) %% 3L)
  key <- pk_cache_key(query_id, rls_sig, filter_sig, query_version = "v1", engine = "v2")

  token <- pk_cancel_token_path(req_id, base_dir = token_root)
  pk_cancel_token_clear(token)
  deadline <- pk_deadline_at(started, cfg_lane$deadline_sec)

  # Isci-guvenli anlik goruntu: her turda DOGRULANIR. Bir oturum/reaktif/baglanti
  # sizintisi burada YAKALANMALIDIR.
  request <- pk_async_build_request(
    user_prompt = sprintf("Soru %d: kalan iscilik nedir?", idx),
    chat_history = list(list(role = "user", content = "onceki tur")),
    username = username, request_id = req_id,
    deep_thinking = (idx %% cfg_lane$deep_every) == 0L,
    api_key_plan = list(key = "sk-soak-fake", source = "personal"),
    user_session_snapshot = list(system_username = username, user_id = user_id),
    repo_root = soak_pk_repo_root(), cancel_token = token,
    deadline_sec = cfg_lane$deadline_sec, engine = "v2",
    bootstrap_files = "R/utils_common.R", started_at = started
  )
  snapshot_safe <- isTRUE(pk_async_validate_request(request)$safe)

  # Iptal firtinasi: her N. istek GERCEKTEN iptal edilir.
  cancelled_round <- (idx %% cfg_lane$cancel_every) == 0L
  if (isTRUE(cancelled_round)) pk_cancel_token_signal(token)

  cache_hit <- FALSE
  sql_status <- NA_character_
  sql_rows <- 0L
  timeout_dispatch <- NA
  cap_strategy <- NA_character_

  gate <- pk_async_stage_gate(token, deadline)
  if (isTRUE(gate$halt)) {
    outcome <- gate$status
  } else {
    got <- pk_cache_get(key)
    cache_hit <- isTRUE(got$hit)

    if (isTRUE(cache_hit)) {
      sql_status <- "cached"
      sql_rows <- nrow(got$value)
      outcome <- "ok"
    } else {
      plan <- pk_sql_timeout_plan(cfg_lane$sql_timeout_sec,
                                 pk_deadline_remaining_sec(deadline))
      timeout_dispatch <- isTRUE(plan$dispatch)

      if (!isTRUE(plan$dispatch)) {
        outcome <- "deadline"
        sql_status <- "not_dispatched"
      } else {
        res <- pk_sql_execute_bounded(
          conn,
          sprintf("SELECT * FROM pk_veri WHERE id <= %d", cfg_lane$rows_per_query),
          unicode_param = FALSE, chunk_rows = cfg_lane$chunk_rows,
          max_result_mb = cfg_lane$max_result_mb,
          stage_gate = function() pk_async_stage_gate(token, deadline)
        )
        sql_status <- res$status
        sql_rows <- res$rows

        if (identical(res$status, "ok")) {
          pk_cache_put(key, res$data)
          cap <- pk_row_cap_plan(cfg_lane$row_cap, authorized_rows = res$rows,
                                 rls_pushdown = TRUE)
          cap_strategy <- cap$strategy
          outcome <- "ok"
        } else {
          outcome <- res$status
        }
      }
    }
  }

  # BAYAT tamamlanma: daha yeni bir istek aktif hale gelmis olabilir.
  stale_round <- (idx %% cfg_lane$stale_every) == 0L
  active_id <- if (isTRUE(stale_round)) sprintf("soak_pk_%06d", idx + 1L) else req_id
  guard <- pk_async_should_apply(active_id, req_id, stopped = isTRUE(cancelled_round))

  pk_cancel_token_clear(token)

  list(
    idx = idx, request_id = req_id, username = username,
    duration_ms = as.numeric(difftime(Sys.time(), started, units = "secs")) * 1000,
    snapshot_safe = snapshot_safe,
    cancelled_round = cancelled_round,
    stale_round = stale_round,
    cache_hit = cache_hit,
    sql_status = sql_status,
    sql_rows = sql_rows,
    timeout_dispatch = timeout_dispatch,
    cap_strategy = cap_strategy,
    outcome = outcome,
    guard_apply = isTRUE(guard$apply),
    guard_reason = guard$reason
  )
}

# Derin Dusunme: ardisik sorgular yalnizca KALAN butceyi alir; toplam etkin
# zaman asimi analiz butcesini ASMAMALIDIR.
soak_pk_deep_budget_probe <- function(cfg_lane) {
  remaining <- cfg_lane$deadline_sec
  effective <- integer(0)
  for (i in seq_len(cfg_lane$deep_max_queries)) {
    plan <- pk_sql_timeout_plan(cfg_lane$sql_timeout_sec, remaining)
    if (!isTRUE(plan$dispatch)) break
    effective <- c(effective, plan$timeout_sec)
    remaining <- remaining - plan$timeout_sec
  }
  list(
    dispatched = length(effective),
    total_effective_sec = sum(effective),
    budget_sec = cfg_lane$deadline_sec,
    budget_respected = sum(effective) <= cfg_lane$deadline_sec
  )
}

#' PK-analiz soak seridini calistir
#'
#' @param cfg soak_config() cikti listesi.
#' @return list(available=, sessions=, summary=, cancel=, cache=, guard=,
#'   deep=, does_prove=, does_not_prove=, reason=)
soak_pk_analysis_lane <- function(cfg) {
  boot <- soak_pk_bootstrap()
  if (!isTRUE(boot$available)) {
    return(list(
      available = FALSE,
      reason = sprintf("Faz 6 yardimcilari yuklenemedi (eksik: %s)",
                       paste(boot$missing_fns, collapse = ", "))
    ))
  }

  sessions <- max(1L, as.integer(cfg$pk_lane_sessions %||% 60L))

  cfg_lane <- list(
    distinct_users = max(1L, as.integer(cfg$pk_lane_distinct_users %||% 6L)),
    distinct_queries = max(1L, as.integer(cfg$pk_lane_distinct_queries %||% 5L)),
    deadline_sec = as.numeric(cfg$pk_lane_deadline_sec %||% 300),
    sql_timeout_sec = as.numeric(cfg$pk_lane_sql_timeout_sec %||% 120),
    row_cap = as.numeric(cfg$pk_lane_row_cap %||% 50000),
    rows_per_query = max(1L, as.integer(cfg$pk_lane_rows_per_query %||% 4000L)),
    chunk_rows = max(1L, as.integer(cfg$pk_lane_chunk_rows %||% 1000L)),
    max_result_mb = as.numeric(cfg$pk_lane_max_result_mb %||% 512),
    cancel_every = max(2L, as.integer(cfg$pk_lane_cancel_every %||% 7L)),
    stale_every = max(2L, as.integer(cfg$pk_lane_stale_every %||% 5L)),
    deep_every = max(2L, as.integer(cfg$pk_lane_deep_every %||% 9L)),
    deep_max_queries = max(1L, as.integer(cfg$pk_lane_deep_max_queries %||% 5L))
  )

  token_root <- file.path(tempdir(), paste0("soak_pk_tokens_", as.integer(Sys.time())))
  dir.create(token_root, recursive = TRUE, showWarnings = FALSE)

  db <- tryCatch(soak_pk_make_db(20000L), error = function(e) NULL)
  if (is.null(db)) {
    return(list(available = FALSE, reason = "Lane-yerel SQLite kurulamadi"))
  }

  # Onbellek SUREC-YERELDIR; serit baslamadan sifirlanir ki hit orani
  # olculebilir olsun.
  pk_cache_reset()

  on.exit({
    tryCatch(DBI::dbDisconnect(db$conn), error = function(e) NULL)
    unlink(db$path, force = TRUE)
    unlink(token_root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  rows <- vector("list", sessions)
  for (i in seq_len(sessions)) {
    rows[[i]] <- tryCatch(
      soak_pk_one_session(i, db$conn, token_root, cfg_lane),
      error = function(e) list(
        idx = i, duration_ms = NA_real_, snapshot_safe = FALSE,
        cancelled_round = FALSE, stale_round = FALSE, cache_hit = FALSE,
        sql_status = "error", sql_rows = 0L, outcome = "error",
        guard_apply = FALSE, guard_reason = "error"
      )
    )
  }

  durations <- vapply(rows, function(r) as.numeric(r$duration_ms %||% NA_real_), numeric(1))
  outcomes <- vapply(rows, function(r) as.character(r$outcome %||% "error"), character(1))
  cancelled <- vapply(rows, function(r) isTRUE(r$cancelled_round), logical(1))
  stale <- vapply(rows, function(r) isTRUE(r$stale_round), logical(1))
  hits <- vapply(rows, function(r) isTRUE(r$cache_hit), logical(1))
  safe <- vapply(rows, function(r) isTRUE(r$snapshot_safe), logical(1))
  applied <- vapply(rows, function(r) isTRUE(r$guard_apply), logical(1))

  # SOZLESME dogrulamalari (olculemeyen esik SESSIZCE GECMEZ).
  cancel_honoured <- all(outcomes[cancelled] %in% c("cancelled", "deadline"))
  cancel_never_applied <- !any(applied[cancelled])
  stale_never_applied <- !any(applied[stale & !cancelled])
  fresh_applied <- all(applied[!stale & !cancelled])
  snapshot_all_safe <- all(safe)

  cache_stats <- pk_cache_stats()
  deep <- soak_pk_deep_budget_probe(cfg_lane)

  # Baglanti muhasebesi: sinirli getirim her cikis yolunda sonuc kumesini
  # kapatir; getirimden sonra baglanti hala kullanilabilir olmalidir.
  conn_usable <- isTRUE(tryCatch({
    probe <- DBI::dbGetQuery(db$conn, "SELECT COUNT(*) AS n FROM pk_veri")
    is.data.frame(probe) && nrow(probe) == 1L
  }, error = function(e) FALSE))

  ok_count <- sum(outcomes == "ok")
  measurable <- sum(!cancelled)
  success_rate <- if (measurable > 0L) round(ok_count / measurable, 4) else NA_real_

  list(
    available = TRUE,
    sessions = sessions,
    summary = list(
      success_rate = success_rate,
      ok = ok_count,
      cancelled = sum(cancelled),
      stale = sum(stale),
      p50_ms = round(soak_pk_quantile(durations, 0.50), 2),
      p95_ms = round(soak_pk_quantile(durations, 0.95), 2),
      p99_ms = round(soak_pk_quantile(durations, 0.99), 2)
    ),
    cancel = list(
      storm_rounds = sum(cancelled),
      honoured = cancel_honoured,
      never_applied = cancel_never_applied
    ),
    guard = list(
      stale_rounds = sum(stale),
      stale_never_applied = stale_never_applied,
      fresh_always_applied = fresh_applied,
      snapshot_all_worker_safe = snapshot_all_safe
    ),
    cache = list(
      entries = cache_stats$entries,
      total_mb = cache_stats$total_mb,
      hit = cache_stats$hit,
      miss = cache_stats$miss,
      evicted = cache_stats$evicted,
      rejected_oversize = cache_stats$rejected_oversize,
      hit_observed = sum(hits) > 0L
    ),
    deep = deep,
    db = list(connection_usable_after_bounded_fetch = conn_usable),
    does_prove = c(
      "Iptal jetonu YUK ALTINDA gorulur ve iptal edilen tur ASLA uygulanmaz",
      "Bayat tamamlanma daha yeni istegi EZMEZ; taze istek her zaman uygulanir",
      "Isci anlik goruntusu her turda oturum/reaktif/baglanti TASIMAZ",
      "Ardisik derin sorgularin toplam etkin zaman asimi analiz butcesini ASMAZ",
      "Sinirli getirim tekrar yuk altinda sonuc kumesini birakir; baglanti kullanilabilir kalir",
      "Boyut sinirli LRU onbellek tekrarlayan isteklerde hit uretir ve butcede kalir"
    ),
    does_not_prove = c(
      "GERCEK Shiny olay dongusu yanit verebilirligi (tarayici/websocket YOK)",
      "GERCEK future isci havuzu doygunlugu (tek surecte ardisik kosum)",
      "GERCEK LLM davranisi (secim/filtre LLM cagrilari YOK)",
      "Uretim SQL Server T-SQL/ODBC davranisi (lane-yerel SQLite kullanilir)",
      "SQL Server sorgu zaman asimi mekanizmasinin gercekten uygulandigi",
      "Uretim olcekli kapasite veya coklu kullanici SSO/RLS davranisi"
    )
  )
}
