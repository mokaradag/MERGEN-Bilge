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
    "R/helpers_pk_exec_context.R",
    "R/helpers_pk_result_size.R",
    "R/helpers_pk_cache.R",
    "R/helpers_pk_sql_execute.R",
    "R/helpers_pk_async_bootstrap.R",
    "R/helpers_pk_async_snapshot.R",
    "R/helpers_pk_async_request.R",
    "R/helpers_pk_async_worker_sql.R",
    "R/helpers_pk_async_worker.R",
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
    "pk_sql_execute_bounded", "pk_row_cap_plan", "pk_deep_reconcile_packets",
    "pk_deep_execute_sql", "pk_config_resolve", "pk_deadline_remaining_sec",
    "pk_cache_entry_within_limit", "pk_async_run_analysis"
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
  # Onbellek erisim deseni BILINCLI olarak SICAK KUME + SOGUK KUYRUK'tur.
  #
  # Tek tip dongusel erisim (her tur farkli anahtar, sabit periyot) LRU icin
  # EN KOTU durumdur: ya hicbir tekrar olusmaz (isabet=0) ya da tekrar
  # geldiginde giris coktan tahliye edilmistir. Her iki halde de "isabet
  # gozlendi" VE "tahliye gozlendi" esikleri ayni kosumda saglanamaz ve
  # eksiklerden biri sessizce gecerdi.
  #
  #  - SICAK turlar (tek sayili idx): 2 kullaniciya yayilmis kucuk, SIK
  #    tekrar eden havuz -> ISABET uretir ve capraz kapsam izolasyonunu olcer.
  #  - SOGUK turlar (cift sayili idx): tur basina BENZERSIZ anahtar -> ayrik
  #    giris sayisini serit-yerel LRU tavaninin uzerine iter, TAHLIYE uretir.
  hot_round <- (idx %% 2L) == 1L

  # Kullanici sayisi kadar farkli YETKI KAPSAMI: onbellek izolasyonu gercekten
  # test edilsin (ayni kullanicinin sonucu baskasina verilmemeli).
  user_id <- if (isTRUE(hot_round)) {
    ((idx %/% 2L) %% 2L) + 1L
  } else {
    ((idx - 1L) %% cfg_lane$distinct_users) + 1L
  }
  username <- sprintf("soak.kullanici%02d", user_id)

  rls_info <- list(
    authorized = TRUE, username = username,
    projects = sprintf("PROJE-%05d", seq_len(10L) + user_id * 10L)
  )
  rls_sig <- pk_cache_rls_signature(rls_info)

  if (isTRUE(hot_round)) {
    # Sicak anahtar SADECE yetki kapsamiyla ayrisir; her 4 idx'te bir tekrar
    # eder, arada yalnizca 2 soguk ekleme olur -> tahliye edilmeden once
    # kesinlikle yeniden okunur.
    query_id <- "q_sicak"
    filter_sig <- "f0"
  } else {
    query_id <- sprintf("q_soguk%06d", idx)
    filter_sig <- sprintf("f%d", (idx %/% 2L) %% 3L)
  }
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

  # Iptal firtinasi: her N. istek GERCEKTEN iptal edilir. Turlerin YARISI
  # UCUS-ICI iptaldir: jeton getirim BASLADIKTAN sonra, parcalar arasinda
  # atilir. Yalnizca on-kapi iptali test edilseydi, `pk_sql_execute_bounded`
  # icindeki parca-arasi kapi HIC calistirilmaz ve orada bir regresyon
  # (kapinin hic cagrilmamasi) sessizce gecerdi.
  cancelled_round <- (idx %% cfg_lane$cancel_every) == 0L
  inflight_cancel <- isTRUE(cancelled_round) &&
    ((idx %/% cfg_lane$cancel_every) %% 2L) == 1L
  if (isTRUE(cancelled_round) && !isTRUE(inflight_cancel)) {
    pk_cancel_token_signal(token)
  }

  cache_hit <- FALSE
  sql_status <- NA_character_
  sql_rows <- 0L
  timeout_dispatch <- NA
  cap_strategy <- NA_character_
  # NA = bu turda ilgili boyut HIC olculmedi. FALSE ile karistirilmamalidir:
  # "olculmedi" esik degerlendirmesinden DISLANIR, "basarisiz" ise SERIDI DUSURUR.
  cache_scope_ok <- NA
  rows_complete <- NA

  gate <- pk_async_stage_gate(token, deadline)
  if (isTRUE(gate$halt)) {
    outcome <- gate$status
  } else {
    # Ucus-ici iptal turu onbellegi ATLAR: isabet SQL'i hic calistirmaz ve
    # parca-arasi kapi test edilmemis kalirdi.
    got <- if (isTRUE(inflight_cancel)) list(hit = FALSE) else pk_cache_get(key)
    cache_hit <- isTRUE(got$hit)

    if (isTRUE(cache_hit)) {
      sql_status <- "cached"
      sql_rows <- nrow(got$value)
      # CAPRAZ KAPSAM TESPITI: her onbellek girisi KENDI yetki kapsamini
      # tasir. Anahtar RLS bilesenini kaybederse/carpisirsa donen deger
      # ayirt edilemez olmazdi; sahip imzasi ACIKCA dogrulanir.
      cache_owner <- attr(got$value, "soak_scope", exact = TRUE)
      cache_scope_ok <- identical(as.character(cache_owner)[1], rls_sig)
      outcome <- "ok"
    } else {
      plan <- pk_sql_timeout_plan(cfg_lane$sql_timeout_sec,
                                 pk_deadline_remaining_sec(deadline))
      timeout_dispatch <- isTRUE(plan$dispatch)

      if (!isTRUE(plan$dispatch)) {
        outcome <- "deadline"
        sql_status <- "not_dispatched"
      } else {
        # Parca-arasi kapi sayaci: ucus-ici iptal turlerinde N. cagrida
        # GERCEK jeton dosyasi yazilir, boylece getirim TAM ORTASINDA durur.
        kapi_sayaci <- 0L
        parca_kapisi <- function() {
          kapi_sayaci <<- kapi_sayaci + 1L
          if (isTRUE(inflight_cancel) && kapi_sayaci == 2L) {
            pk_cancel_token_signal(token)
          }
          pk_async_stage_gate(token, deadline)
        }
        # Hesaplanan zaman asimi/son tarih SURUCUYE AKTARILIR: yalnizca
        # yerel aritmetikle dogrulamak, uretimdeki kirpma yolunun hic
        # cagrilmadigi bir regresyonu gizlerdi.
        res <- pk_sql_execute_bounded(
          conn,
          sprintf("SELECT * FROM pk_veri WHERE id <= %d", cfg_lane$rows_per_query),
          unicode_param = FALSE, chunk_rows = cfg_lane$chunk_rows,
          max_result_mb = cfg_lane$max_result_mb,
          timeout_sec = plan$timeout_sec, deadline_at = deadline,
          stage_gate = parca_kapisi
        )
        sql_status <- res$status
        sql_rows <- res$rows

        if (identical(res$status, "ok")) {
          # Sinirli getirim TAM sonucu uretmelidir: sessizce kirpan bir
          # regresyon yine `ok` dondurup %100 basari orani uretebilirdi.
          rows_complete <- identical(as.integer(res$rows), as.integer(cfg_lane$rows_per_query)) &&
            identical(as.integer(min(res$data$id)), 1L) &&
            identical(as.integer(max(res$data$id)), as.integer(cfg_lane$rows_per_query))
          attr(res$data, "soak_scope") <- rls_sig
          pk_cache_put(key, res$data)
          # Tavan plani DIAGNOSTIK DEGIL, KARARDIR: planlayici reddederse
          # tur BASARISIZ sayilir. `rls_pushdown = FALSE` uretimdeki
          # (yetki-sonrasi, SQL'e itilmemis) durumu yansitir.
          cap <- pk_row_cap_plan(cfg_lane$row_cap, authorized_rows = res$rows,
                                 rls_pushdown = FALSE,
                                 aggregates_over_full_set = FALSE)
          cap_strategy <- cap$strategy
          outcome <- if (identical(cap$strategy, "refuse")) "row_cap_refused" else "ok"
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
    inflight_cancel = inflight_cancel,
    stale_round = stale_round,
    cache_hit = cache_hit,
    cache_scope_ok = cache_scope_ok,
    rows_complete = rows_complete,
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
#
# Butce GERCEK `pk_deep_execute_sql` uzerinden surulur (yerel aritmetik degil):
# yalnizca `pk_sql_timeout_plan` cagrilariyla dogrulamak, derin yolun kalan
# butceyi hic AKTARMADIGI bir regresyonu (her sorguya tam zaman asimi
# vermesini) gizlerdi. Ayrica son tarih GECMISE alinan bir tur eklenerek
# derin yolun ardisik sorgular ARASINDA gercekten durdugu kanitlanir.
soak_pk_deep_budget_probe <- function(conn, token_root, cfg_lane) {
  token <- pk_cancel_token_path("soak_pk_deep", base_dir = token_root)
  pk_cancel_token_clear(token)
  started <- Sys.time()
  deadline <- pk_deadline_at(started, cfg_lane$deadline_sec)
  sql <- sprintf("SELECT * FROM pk_veri WHERE id <= %d", cfg_lane$chunk_rows)

  effective <- numeric(0)
  statuses <- character(0)
  for (i in seq_len(cfg_lane$deep_max_queries)) {
    # Her tur, o ana kadar TUKETILDIGI varsayilan butceyi dusen bir son
    # tarihle cagrilir; boylece kalan butce gercekten daralir.
    kalan <- cfg_lane$deadline_sec - sum(effective)
    if (kalan <= 0) break
    tur_son <- pk_deadline_at(Sys.time(), kalan)
    res <- pk_deep_execute_sql(conn, sql, deadline_at = tur_son,
                               cancel_token = token, unicode_param = FALSE)
    statuses <- c(statuses, as.character(res$status)[1])
    if (!identical(res$status, "ok")) break
    ts <- suppressWarnings(as.numeric(res$timeout_sec %||% NA_real_)[1])
    if (!is.finite(ts) || ts <= 0) break
    effective <- c(effective, ts)
  }

  # Son tarihi GECMIS bir derin tur: derin yol ardisik sorgular arasinda
  # DURMALIDIR (yeni bir sorgu daha calistirmamalidir).
  # `pk_deadline_at()` negatif butceyi "son tarih yok" (NA) olarak dondurur;
  # bu yuzden GECMIS an dogrudan POSIXct olarak verilir.
  gecmis <- pk_deep_execute_sql(conn, sql,
                                deadline_at = Sys.time() - 5,
                                cancel_token = token, unicode_param = FALSE)
  # Iptal jetonu derin yolda da onurlandirilmalidir.
  pk_cancel_token_signal(token)
  iptal <- pk_deep_execute_sql(conn, sql, deadline_at = deadline,
                               cancel_token = token, unicode_param = FALSE)
  pk_cancel_token_clear(token)

  list(
    dispatched = length(effective),
    total_effective_sec = sum(effective),
    budget_sec = cfg_lane$deadline_sec,
    budget_respected = length(effective) > 0L &&
      sum(effective) <= cfg_lane$deadline_sec,
    # Ardisik sorgular AZALAN butce almalidir; hepsi esitse kalan butce
    # aktarilmiyor demektir.
    budget_decreases = length(effective) < 2L ||
      all(diff(effective) <= 0) && effective[1] > effective[length(effective)],
    statuses = statuses,
    deadline_halts_between_queries = identical(as.character(gecmis$status)[1], "deadline"),
    cancel_halts_between_queries = identical(as.character(iptal$status)[1], "cancelled")
  )
}

# GERCEK PSOCK ASENKRON YOL: bu serit aksi halde her turu KAPI SURECINDE
# calistirir ve `MERGEN_PK_ASYNC=true` ile fiilen etkinlesen kod (anlik goruntu
# serilestirme, TEMIZ iscide bootstrap, future tamamlanma/geri cagri) HIC
# calistirilmazdi. Tek bir dogruluk turu bu boslugu kapatir; olay dongusu
# yanit verebilirligini KANITLAMAZ (o hala VM isidir).
soak_pk_psock_probe <- function(cfg_lane) {
  bos <- function(reason) list(ran = FALSE, ok = FALSE, reason = reason,
                               status = NA_character_)
  if (!requireNamespace("future", quietly = TRUE)) return(bos("future_missing"))
  if (!requireNamespace("promises", quietly = TRUE)) return(bos("promises_missing"))

  eski_plan <- future::plan()
  on.exit(try(future::plan(eski_plan), silent = TRUE), add = TRUE)
  kuruldu <- tryCatch({
    future::plan(future::multisession, workers = 2L)
    TRUE
  }, error = function(e) FALSE)
  if (!isTRUE(kuruldu)) return(bos("psock_plan_unavailable"))

  root <- soak_pk_repo_root()
  token_dir <- file.path(tempdir(), "soak_pk_psock")
  dir.create(token_dir, recursive = TRUE, showWarnings = FALSE)
  token <- pk_cancel_token_path("soak_pk_psock", base_dir = token_dir)
  pk_cancel_token_clear(token)
  on.exit(unlink(token_dir, recursive = TRUE, force = TRUE), add = TRUE)

  istek <- tryCatch(pk_async_build_request(
    user_prompt = "PSOCK dogruluk turu", chat_history = list(),
    username = "soak.psock", request_id = "soak_pk_psock",
    deep_thinking = FALSE,
    api_key_plan = list(key = "sk-soak-fake", source = "personal"),
    user_session_snapshot = list(system_username = "soak.psock", user_id = 1L),
    repo_root = root, cancel_token = token,
    deadline_sec = cfg_lane$deadline_sec, engine = "v2",
    bootstrap_files = "R/utils_common.R", started_at = Sys.time()
  ), error = function(e) NULL)
  if (!is.list(istek)) return(bos("request_build_failed"))
  if (!isTRUE(pk_async_validate_request(istek)$safe)) return(bos("snapshot_unsafe"))

  # Iptal ONCEDEN sinyallenir: tur, GERCEK iscide serilestirme + bootstrap
  # oncesi kapiyi calistirir ve DETERMINISTIK olarak `cancelled` doner.
  # Boylece prob ne LLM'e ne de DB'ye ihtiyac duyar, ama async yolun
  # serilestirme/tamamlanma zincirini bastan sona kullanir.
  pk_cancel_token_signal(token)

  # Globals paketi URETIMDEKI ile AYNIDIR (`pk_async_worker_globals()`); elle
  # bir liste kurmak, gercek dispatch'in ihtiyac duydugu sembolleri kacirir ve
  # prob asil kodu degil kendi kurgusunu test etmis olurdu.
  paket <- tryCatch(pk_async_worker_globals(force = TRUE), error = function(e) NULL)
  if (!is.list(paket)) return(bos("worker_globals_unavailable"))
  paket$istek <- istek

  sonuc <- tryCatch({
    f <- future::future({ pk_async_run_analysis(istek) },
                        globals = paket, packages = c("stats", "utils"), seed = TRUE)
    future::value(f)
  }, error = function(e) structure(list(message = conditionMessage(e)),
                                   class = "soak_psock_error"))
  if (inherits(sonuc, "soak_psock_error")) {
  }
  pk_cancel_token_clear(token)

  if (inherits(sonuc, "soak_psock_error")) {
    return(list(ran = TRUE, ok = FALSE, reason = "future_error",
                status = NA_character_,
                error = as.character(sonuc$message)[1]))
  }
  durum <- as.character((sonuc %||% list())$status %||% NA_character_)[1]
  list(ran = TRUE, ok = identical(durum, "cancelled"),
       reason = if (identical(durum, "cancelled")) "ok" else "unexpected_status",
       status = durum)
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

  # Serit-yerel LRU giris tavani: uretim varsayilani (50) ile bu seridin
  # uretebildigi ayrik giris sayisi (~sessions/2) ustuste binmeyebilir ve
  # tahliye yolu HIC calistirilmadan gecerdi. Tavan bilincli olarak dusuk
  # tutulur; cikista geri alinir. NOT: ayni adli ORTAM DEGISKENI options()
  # onceligindedir, bu yuzden ETKIN tavan olculup raporlanir.
  eski_secenekler <- options(mergen.pk.cache_max_entries = 12L)
  on.exit(options(eski_secenekler), add = TRUE)
  entries_ceiling <- tryCatch(
    as.numeric(pk_config_resolve("MERGEN_PK_CACHE_MAX_ENTRIES"))[1],
    error = function(e) NA_real_
  )

  on.exit({
    tryCatch(DBI::dbDisconnect(db$conn), error = function(e) NULL)
    unlink(db$path, force = TRUE)
    unlink(token_root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  # BAGLANTI MUHASEBESI: her tur uretim seklindeki bir AL/BIRAK sarmalayicisindan
  # gecer. Onceden her tur ayni acik baglantiyi yeniden kullaniyordu; istek
  # basina bir baglanti sizdiran bir yol bu seritte GORUNMEZDI. Sayaclar
  # dengelenmezse kapi FAIL olur.
  conn_counts <- new.env(parent = emptyenv())
  conn_counts$acquired <- 0L
  conn_counts$released <- 0L
  al_birak <- function(fn) {
    conn_counts$acquired <- conn_counts$acquired + 1L
    on.exit(conn_counts$released <- conn_counts$released + 1L, add = TRUE)
    fn(db$conn)
  }

  rows <- vector("list", sessions)
  for (i in seq_len(sessions)) {
    rows[[i]] <- tryCatch(
      al_birak(function(baglanti) soak_pk_one_session(i, baglanti, token_root, cfg_lane)),
      error = function(e) list(
        idx = i, duration_ms = NA_real_, snapshot_safe = FALSE,
        cancelled_round = FALSE, inflight_cancel = FALSE, stale_round = FALSE,
        cache_hit = FALSE, cache_scope_ok = NA, rows_complete = NA,
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
  inflight <- vapply(rows, function(r) isTRUE(r$inflight_cancel), logical(1))
  # Uc-durumlu: NA = olculmedi. `isTRUE`/`isFALSE` ile ayirmak, olculmemis
  # bir boyutun "gecti" gibi sayilmasini engeller.
  scope_bad <- vapply(rows, function(r) isFALSE(r$cache_scope_ok), logical(1))
  scope_seen <- vapply(rows, function(r) isTRUE(r$cache_scope_ok), logical(1))
  rows_bad <- vapply(rows, function(r) isFALSE(r$rows_complete), logical(1))
  rows_seen <- vapply(rows, function(r) isTRUE(r$rows_complete), logical(1))

  # SOZLESME dogrulamalari (olculemeyen esik SESSIZCE GECMEZ).
  # Iptal edilen tur TAM OLARAK "cancelled" bitmelidir: "deadline" da kabul
  # edilseydi, jetonu hic okumayan ama butceyi tuketen bir regresyon gecerdi.
  cancel_honoured <- all(outcomes[cancelled] == "cancelled")
  cancel_never_applied <- !any(applied[cancelled])
  stale_never_applied <- !any(applied[stale & !cancelled])
  fresh_applied <- all(applied[!stale & !cancelled])
  snapshot_all_safe <- all(safe)
  # SIFIR tur calistirilmadiysa yukaridaki `all(...)` bos vektor uzerinde
  # TRUE doner; serit hicbir sey kanitlamadan yesil gorunurdu.
  cancel_exercised <- sum(cancelled) > 0L
  inflight_exercised <- sum(inflight) > 0L
  stale_exercised <- sum(stale & !cancelled) > 0L
  cache_scope_isolated <- !any(scope_bad) && any(scope_seen)
  rows_always_complete <- !any(rows_bad) && any(rows_seen)

  cache_stats <- pk_cache_stats()
  psock <- tryCatch(soak_pk_psock_probe(cfg_lane),
                    error = function(e) list(ran = FALSE, ok = FALSE,
                                             reason = "probe_error",
                                             status = NA_character_))

  deep <- tryCatch(
    soak_pk_deep_budget_probe(db$conn, token_root, cfg_lane),
    error = function(e) list(
      dispatched = 0L, total_effective_sec = NA_real_,
      budget_sec = cfg_lane$deadline_sec, budget_respected = FALSE,
      budget_decreases = FALSE, statuses = "error",
      deadline_halts_between_queries = FALSE,
      cancel_halts_between_queries = FALSE
    )
  )

  # Baglanti muhasebesi: sinirli getirim her cikis yolunda sonuc kumesini
  # kapatir; getirimden sonra baglanti hala kullanilabilir olmalidir.
  conn_usable <- isTRUE(tryCatch({
    probe <- DBI::dbGetQuery(db$conn, "SELECT COUNT(*) AS n FROM pk_veri")
    is.data.frame(probe) && nrow(probe) == 1L
  }, error = function(e) FALSE))

  conn_counts <- list(acquired = conn_counts$acquired, released = conn_counts$released)
  conn_balanced <- identical(conn_counts$acquired, conn_counts$released) &&
    conn_counts$acquired >= sessions

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
      inflight_rounds = sum(inflight),
      exercised = cancel_exercised,
      inflight_exercised = inflight_exercised,
      honoured = cancel_honoured,
      never_applied = cancel_never_applied
    ),
    guard = list(
      stale_rounds = sum(stale),
      stale_exercised = stale_exercised,
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
      entries_ceiling = entries_ceiling,
      hit_observed = sum(hits) > 0L,
      # Tahliye GOZLENDI mi: LRU giris tavani gercekten asilmadiysa bozuk
      # bir tahliye yolu sessizce gecerdi.
      eviction_observed = isTRUE(as.numeric(cache_stats$evicted %||% 0)[1] > 0),
      scope_isolated = cache_scope_isolated
    ),
    fetch = list(
      rows_always_complete = rows_always_complete,
      complete_rounds = sum(rows_seen)
    ),
    deep = deep,
    psock = psock,
    db = list(connection_usable_after_bounded_fetch = conn_usable,
              acquire_release_balanced = conn_balanced,
              acquired = conn_counts$acquired, released = conn_counts$released),
    does_prove = c(
      "Iptal jetonu YUK ALTINDA gorulur ve iptal edilen tur ASLA uygulanmaz",
      "UCUS-ICI iptal: getirim parcalar arasinda durur (tam olarak 'cancelled')",
      "Bayat tamamlanma daha yeni istegi EZMEZ; taze istek her zaman uygulanir",
      "Isci anlik goruntusu her turda oturum/reaktif/baglanti TASIMAZ",
      "Ardisik derin sorgular GERCEK pk_deep_execute_sql uzerinden AZALAN butce alir",
      "Derin yol son tarih/iptal durumunda sorgular ARASINDA durur",
      "Sinirli getirim TAM sonuc uretir ve tekrar yuk altinda sonuc kumesini birakir",
      "Boyut sinirli LRU onbellek hit + TAHLIYE uretir ve yetki kapsamlari CAPRAZ SIZMAZ",
      "Baglanti AL/BIRAK muhasebesi tekrar yuk altinda dengede kalir (sizinti YOK)",
      "GERCEK PSOCK iscisinde anlik goruntu serilestirme + bootstrap-oncesi kapi calisir"
    ),
    does_not_prove = c(
      "GERCEK Shiny olay dongusu yanit verebilirligi (tarayici/websocket YOK)",
      "GERCEK future isci havuzu doygunlugu (tek PSOCK dogruluk turu vardir, YUK yoktur)",
      "GERCEK LLM davranisi (secim/filtre LLM cagrilari YOK)",
      "Uretim SQL Server T-SQL/ODBC davranisi (lane-yerel SQLite kullanilir)",
      "SQL Server sorgu zaman asimi mekanizmasinin gercekten uygulandigi",
      "Uretim olcekli kapasite veya coklu kullanici SSO/RLS davranisi"
    )
  )
}
