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
    # Manifest bolumleri: `pk_async_worker_bootstrap_files()` uretimdeki isci
    # dosya kumesini BURADAN turetir. Yuklenmezse liste bos kalir ve PSOCK
    # bootstrap turu `empty_file_list` ile duser (yani hicbir sey kanitlamaz).
    "R/config_source_manifest.R",
    "R/utils_common.R", "R/utils_text_encoding.R",
    "R/helpers_db_unicode_escape.R", "R/helpers_db_encoding.R",
    "R/helpers_db_connection.R",
    "R/helpers_db_pool.R",
    "R/helpers_pk_config.R",
    "R/helpers_pk_async_cancel.R",
    "R/helpers_pk_exec_context.R",
    "R/helpers_pk_cancel_http.R",
    "R/helpers_pk_result_columns.R",
    "R/helpers_pk_result_size.R",
    "R/helpers_pk_cache_key.R",
    "R/helpers_pk_cache.R",
    "R/helpers_pk_sql_execute.R",
    "R/helpers_pk_sql_connection.R",
    "R/helpers_pk_async_worker_env.R",
    "R/helpers_pk_async_worker_pool.R",
    "R/helpers_pk_async_bootstrap_fs.R",
    "R/helpers_pk_async_bootstrap.R",
    "R/helpers_pk_async_snapshot_validate.R",
    "R/helpers_pk_async_snapshot.R", "R/helpers_pk_async_secrets.R",
    "R/helpers_pk_async_probe.R",
    "R/helpers_pk_async_plan.R",
    "R/helpers_pk_async_request.R",
    "R/helpers_pk_async_worker_sql.R",
    "R/helpers_pk_async_worker.R",
    "R/helpers_deep_analysis_sql.R",
    "R/helpers_deep_analysis_reconcile.R"
  )
  ok <- TRUE
  # KULLANILAMAMA NEDENI AYRISTIRILIR: `available = FALSE` UC AYRI nedenden
  # dogar (source hatasi, eksik yardimci islev, eksik paket). Yalnizca
  # `missing_fns` dondurulunce `RSQLite`/`DBI` eksik bir makinede gerekce
  # "Faz 6 yardimcilari yuklenemedi (eksik: )" olarak BOS kaliyor ve
  # `fail_on_pk_unavailable = TRUE` kapisi operatore hicbir ipucu vermeden
  # sert basarisizlik uretiyordu.
  basarisiz_dosyalar <- character(0)
  for (f in files) {
    res <- tryCatch({
      suppressWarnings(suppressMessages(source(file.path(root, f), encoding = "UTF-8")))
      TRUE
    }, error = function(e) FALSE)
    if (!isTRUE(res)) {
      ok <- FALSE
      basarisiz_dosyalar <- c(basarisiz_dosyalar, f)
    }
  }

  required_fns <- c(
    "pk_cancel_token_path", "pk_cancel_token_signal", "pk_cancel_token_is_signalled",
    "pk_cancel_token_clear", "pk_deadline_at", "pk_sql_timeout_plan",
    "pk_async_stage_gate", "pk_async_should_apply", "pk_async_build_request",
    "pk_async_validate_request", "pk_cache_key", "pk_cache_get", "pk_cache_put",
    "pk_cache_stats", "pk_cache_reset", "pk_cache_rls_signature",
    "pk_sql_execute_bounded", "pk_row_cap_plan", "pk_deep_reconcile_packets",
    "pk_deep_execute_sql", "pk_config_resolve", "pk_deadline_remaining_sec",
    "pk_cache_entry_within_limit", "pk_async_run_analysis",
    "pk_async_worker_bootstrap_files", "pk_async_worker_globals"
  )
  present <- vapply(required_fns, function(fn) exists(fn, mode = "function"), logical(1))

  eksik_paketler <- Filter(
    function(p) !requireNamespace(p, quietly = TRUE),
    c("RSQLite", "DBI")
  )
  available <- ok && all(present) && length(eksik_paketler) == 0L

  list(
    available = available,
    source_ok = isTRUE(ok),
    failed_files = basarisiz_dosyalar,
    missing_packages = as.character(eksik_paketler),
    missing_fns = required_fns[!present]
  )
}

# Bootstrap basarisizliginin GERCEK nedenini tek satirda toplar. Bos parcalar
# atlanir; hicbir parca yoksa genel bir gerekce dondurulur.
soak_pk_bootstrap_reason <- function(boot) {
  parcalar <- character(0)
  if (length(boot$failed_files %||% character(0))) {
    parcalar <- c(parcalar, sprintf("kaynak yuklenemedi: %s",
                                    paste(boot$failed_files, collapse = ", ")))
  }
  if (length(boot$missing_packages %||% character(0))) {
    parcalar <- c(parcalar, sprintf("eksik paket: %s",
                                    paste(boot$missing_packages, collapse = ", ")))
  }
  if (length(boot$missing_fns %||% character(0))) {
    parcalar <- c(parcalar, sprintf("eksik islev: %s",
                                    paste(boot$missing_fns, collapse = ", ")))
  }
  if (!length(parcalar)) parcalar <- "neden belirlenemedi"
  sprintf("Faz 6 yardimcilari yuklenemedi (%s)", paste(parcalar, collapse = "; "))
}

# Lane-yerel SQLite: GERCEK sinirli getirim yolunu (dbSendQuery + parcali
# dbFetch + parca arasi iptal/son tarih yoklamasi) calistirmak icin.
soak_pk_make_db <- function(rows = 20000L) {
  path <- tempfile(pattern = "soak_pk_", fileext = ".sqlite")
  conn <- DBI::dbConnect(RSQLite::SQLite(), path)
  # KAYNAK TEMIZLIGI: `dbWriteTable()` basarisiz olursa cagiran hatayi yakalayip
  # devam ediyor, ancak baglanti ACIK ve gecici dosya DISKTE kaliyordu. Soak
  # sureci boyunca her basarisiz kurulum bir baglanti sizdiriyordu.
  tamamlandi <- FALSE
  on.exit({
    if (!tamamlandi) {
      try(DBI::dbDisconnect(conn), silent = TRUE)
      unlink(path, force = TRUE)
    }
  }, add = TRUE)
  DBI::dbWriteTable(conn, "pk_veri", data.frame(
    id = seq_len(rows),
    proje = paste0("PROJE-", sprintf("%05d", seq_len(rows))),
    tutar = as.numeric(seq_len(rows)) * 1.37,
    stringsAsFactors = FALSE
  ))
  tamamlandi <- TRUE
  list(conn = conn, path = path)
}

# UCUS-ICI IPTAL TETIKLEYICISININ KENDI KENDINE KALIBRASYONU
#
# Eskiden "3. kapi cagrisinda iptal et" seklinde SABIT bir ordinal kullaniliyordu.
# O sayi `pk_sql_execute_bounded()` icindeki kapi yerlesimine (giris + dongu
# basi) baglidir. PR #703 incelemesi "hicbir yeni bloklayan surucu cagrisi
# Durdur sonrasinda BASLATILMAZ" sozlesmesini ekleyince her bloklayan cagri da
# kapiyi yokluyor; sabit ordinal artik GETIRIM BASLAMADAN once dusuyor ve
# `chunks == 0` uretiyordu. Serit bunu dogru sekilde BASARISIZ saydi.
#
# Cozum ordinali buyutmek DEGIL, KALIBRE ETMEKTIR: ayni sorgu, artan k
# degerleriyle iptal edilerek `chunks >= 1` veren ILK k bulunur. Boylece serit
# ileride kapi yerlesimi yeniden degistiginde de kendini duzeltir. Bulunamazsa
# `NA` doner ve cagiran turu "olculmedi" degil BASARISIZ sayar (kapi zaten
# `chunks >= 1` dogrulamasini yapar).
soak_pk_calibrate_inflight_gate <- function(conn, sql, cfg_lane, max_k = 40L) {
  for (k in seq.int(2L, max_k)) {
    sayac <- 0L
    kapi <- function() {
      sayac <<- sayac + 1L
      if (sayac >= k) return(list(halt = TRUE, status = "cancelled"))
      list(halt = FALSE, status = "ok")
    }
    res <- tryCatch(pk_sql_execute_bounded(
      conn, sql, unicode_param = FALSE, chunk_rows = cfg_lane$chunk_rows,
      max_result_mb = cfg_lane$max_result_mb, timeout_sec = cfg_lane$sql_timeout_sec,
      deadline_at = NULL, stage_gate = kapi
    ), error = function(e) NULL)
    if (is.null(res)) next
    if (identical(res$status, "cancelled") &&
        isTRUE(as.integer(res$chunks %||% 0L) >= 1L)) {
      return(k)
    }
    # Iptal edilmeden TAMAMLANDIYSA daha buyuk k denemenin anlami yok.
    if (identical(res$status, "ok")) break
  }
  NA_integer_
}

soak_pk_quantile <- function(x, p) {
  x <- x[is.finite(x)]
  if (!length(x)) return(NA_real_)
  as.numeric(stats::quantile(x, probs = p, names = FALSE, type = 7))
}

# Bir "oturum": istek kimligi uret -> anlik goruntu kur ve DOGRULA -> onbellek
# yokla -> sinirli SQL getir -> satir tavani plani -> istek-kimligi korumasini
# uygula. Iptal edilen turlarda GERCEK jeton dosyasi yazilir.
soak_pk_one_session <- function(idx, conn, token_root, cfg_lane,
                                inflight_gate_k = NA_integer_) {
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
  # NA = bu tur ucus-ici iptal turu DEGILDI (olcum yapilmadi).
  inflight_after_fetch <- NA

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
        # Parca-arasi kapi sayaci: ucus-ici iptal turlerinde jeton dosyasi
        # ILK GETIRIM TAMAMLANDIKTAN SONRA yazilir.
        #
        # TETIKLEYICI ORDINALI SABIT DEGIL, KALIBREDIR: `pk_sql_execute_bounded()`
        # kapiyi hem girisde, hem getirim dongusunun her turunda, hem de HER
        # BLOKLAYAN SURUCU CAGRISINDAN once yoklar. Bu yerlesim degistiginde
        # sabit bir ordinal iptali getirim BASLAMADAN once atar ve parca
        # SINIRINDAKI kapi hic test edilmezdi. `soak_pk_calibrate_inflight_gate()`
        # `chunks >= 1` veren ILK ordinali olcerek verir; asagidaki
        # `res$chunks >= 1` dogrulamasi da bunu her turda YENIDEN kanitlar.
        esik_k <- suppressWarnings(as.integer(inflight_gate_k)[1])
        if (length(esik_k) != 1L || is.na(esik_k) || esik_k < 2L) esik_k <- 3L
        kapi_sayaci <- 0L
        parca_kapisi <- function() {
          kapi_sayaci <<- kapi_sayaci + 1L
          if (isTRUE(inflight_cancel) && kapi_sayaci == esik_k) {
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
        # UCUS-ICI IPTAL KANITI: iptal GERCEKTEN bir parca getirildikten
        # SONRA gerceklesmis olmalidir. `chunks == 0` demek, iptalin getirim
        # baslamadan once yakalandigi (dolayisiyla parca-arasi kapinin HIC
        # test edilmedigi) anlamina gelir; bu tur "olculmedi" degil,
        # BASARISIZ sayilir.
        if (isTRUE(inflight_cancel)) {
          inflight_after_fetch <- identical(res$status, "cancelled") &&
            isTRUE(as.integer(res$chunks %||% 0L) >= 1L)
        }

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
    inflight_after_fetch = inflight_after_fetch,
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

  # TEK MUTLAK SON TARIH + GERCEK GECEN ZAMAN.
  #
  # Onceki surum her tur icin `sum(effective)` uzerinden TAZE bir son tarih
  # uretiyordu; azalan butce testin KENDI aritmetigi tarafindan garanti
  # ediliyordu. Bu, "her sorgu icin son tarihi sifirlayan" bir uretim
  # regresyonunu gizlerdi. Simdi ayni `derin_son` NESNESI butun cagrilara
  # verilir ve turlar arasinda GERCEK duvar saati tuketilir; azalma yalnizca
  # uretim tarafi kalan butceyi dogru aktardiginda gozlenir.
  #
  # Butce BILINCLI olarak kucuktur: `MERGEN_PK_SQL_TIMEOUT_SEC` (120 sn)
  # baglayici olmamalidir; aksi halde her tur ayni degeri dondurur ve azalma
  # HIC olculemez.
  derin_butce <- cfg_lane$deep_budget_sec
  derin_son <- pk_deadline_at(Sys.time(), derin_butce)

  effective <- numeric(0)
  statuses <- character(0)
  for (i in seq_len(cfg_lane$deep_max_queries)) {
    res <- pk_deep_execute_sql(conn, sql, deadline_at = derin_son,
                               cancel_token = token, unicode_param = FALSE)
    statuses <- c(statuses, as.character(res$status)[1])
    if (!identical(res$status, "ok")) break
    ts <- suppressWarnings(as.numeric(res$timeout_sec %||% NA_real_)[1])
    if (!is.finite(ts) || ts <= 0) break
    effective <- c(effective, ts)
    # Gercek zaman tuket: SQLite sorgusu milisaniyeler surer, dolayisiyla
    # butce kendiliginden daralmazdi.
    if (i < cfg_lane$deep_max_queries) Sys.sleep(cfg_lane$deep_step_sleep_sec)
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
    budget_sec = derin_butce,
    # Her tur AYRI AYRI kalan butcenin altinda kalmalidir. (Toplami
    # karsilastirmak yanlis olurdu: butce takvim degil, MUTLAK SON TARIHTIR;
    # ardisik turlarin toplami son tarihi asabilir, onemli olan her turun o
    # anki KALAN butceyi asmamasidir.)
    budget_respected = length(effective) > 0L &&
      all(effective <= derin_butce),
    # EN AZ IKI sorgu ZORUNLUDUR. Tek sorguyla "gecti" saymak, capraz-sorgu
    # butce aktariminin HIC calistirilmadigi bir kosumu yesil gosterirdi.
    budget_decreases = length(effective) >= 2L &&
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
                               status = NA_character_,
                               bootstrap_ran = FALSE, bootstrap_ok = FALSE,
                               bootstrap_status = NA_character_)
  if (!requireNamespace("future", quietly = TRUE)) return(bos("future_missing"))
  if (!requireNamespace("promises", quietly = TRUE)) return(bos("promises_missing"))

  # ISCI ORTAMI: temiz PSOCK iscileri `R/config_file_store.R` icindeki zorunlu
  # ortam degiskeni denetiminden gecer. Uretimde bunlar `.Renviron`'dan gelir;
  # seritte YER TUTUCU degerler kullanilir (GERCEK SIR/DSN/ENDPOINT DEGIL).
  # HER DEGER KOSULSUZ AYARLANIR. Eskiden yalnizca TANIMSIZ olanlar
  # dolduruluyordu; `.Renviron` icinde GERCEK bir `DB_DSN` veya
  # `LOCAL_LLM_ENDPOINT` tanimli oldugunda iptal EDILMEMIS bootstrap turu
  # `pk_async_run_analysis()` cagirisini URETIM yapilandirmasiyla calistirip
  # gercek veritabani/LLM servisine baglanabiliyordu. Onceki degerler
  # saklanir ve cikista (hata dahil) AYNEN geri yuklenir. Degerler
  # `future::plan()` ONCESINDE ayarlanmalidir: PSOCK iscileri ortami dogum
  # aninda devralir.
  yer_tutucu <- list(
    LOCAL_LLM_ENDPOINT = "http://127.0.0.1:1/v1",
    DB_DSN = "soak_lane_placeholder_dsn",
    AI_KEYS_MASTER = "soak-lane-placeholder-master",
    MCP_FILES_BASE = file.path(tempdir(), "soak_pk_mcp"),
    MERGEN_MCP_BASE_DIR = file.path(tempdir(), "soak_pk_mcp"),
    MERGEN_FILES_ROOT = file.path(tempdir(), "soak_pk_files"),
    MERGEN_UPLOADS_DIR = file.path(tempdir(), "soak_pk_uploads"),
    MERGEN_INDEX_PATH = file.path(tempdir(), "soak_pk_index.json")
  )
  onceki_env <- Sys.getenv(names(yer_tutucu), unset = NA_character_, names = TRUE)
  for (ad in names(yer_tutucu)) {
    do.call(Sys.setenv, stats::setNames(list(yer_tutucu[[ad]]), ad))
  }
  on.exit({
    for (ad in names(onceki_env)) {
      if (is.na(onceki_env[[ad]])) {
        try(Sys.unsetenv(ad), silent = TRUE)
      } else {
        try(do.call(Sys.setenv, stats::setNames(list(onceki_env[[ad]]), ad)),
            silent = TRUE)
      }
    }
  }, add = TRUE)

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
  pk_cancel_token_clear(token)

  if (inherits(sonuc, "soak_psock_error")) {
    return(list(ran = TRUE, ok = FALSE, reason = "future_error",
                status = NA_character_,
                bootstrap_ran = FALSE, bootstrap_ok = FALSE,
                bootstrap_status = NA_character_,
                error = as.character(sonuc$message)[1]))
  }
  durum <- as.character((sonuc %||% list())$status %||% NA_character_)[1]

  # IKINCI TUR: IPTAL EDILMEMIS, GERCEK BOOTSTRAP.
  #
  # Yukaridaki tur jetonu ONCEDEN sinyalledigi icin isci hicbir dosya
  # SOURCE ETMEDEN `cancelled` doner. Tek basina birakilsaydi, TEMIZ bir
  # PSOCK iscisinde bootstrap'in tamamen bozuk olmasi (eksik globals, kirik
  # kaynak sirasi, eksik giris noktasi) bu kapiyi HALA yesil gecerdi.
  # Bu tur GERCEK zorunlu dosya kumesini source eder ve giris noktalarini
  # dogrular; analizin kendisi DB/LLM olmadan basarisiz olabilir, kabul
  # edilen SEY bootstrap'in tamamlanmis olmasidir.
  bs <- soak_pk_psock_bootstrap_round(cfg_lane, root, token_dir, paket)

  list(ran = TRUE, ok = identical(durum, "cancelled"),
       reason = if (identical(durum, "cancelled")) "ok" else "unexpected_status",
       status = durum,
       bootstrap_ran = isTRUE(bs$ran),
       bootstrap_ok = isTRUE(bs$ok),
       bootstrap_status = as.character(bs$status %||% NA_character_)[1],
       bootstrap_reason = as.character(bs$reason %||% NA_character_)[1])
}

# Temiz PSOCK iscisinde GERCEK bootstrap + giris noktasi dogrulamasi.
#
# `bootstrap_failed` KABUL EDILMEZ: bu, uretimdeki `MERGEN_PK_ASYNC=true`
# yolunun her istekte senkron yedege dusecegi anlamina gelir. Diger her durum
# (DB/LLM olmadigi icin olusan hata dahil) bootstrap'in TAMAMLANDIGINI
# kanitlar; serit LLM/DB kanitlamaz, yalnizca isci giris yolunu kanitlar.
soak_pk_psock_bootstrap_round <- function(cfg_lane, root, token_dir, paket) {
  bos <- function(reason) list(ran = FALSE, ok = FALSE, reason = reason,
                               status = NA_character_)

  token <- pk_cancel_token_path("soak_pk_psock_boot", base_dir = token_dir)
  pk_cancel_token_clear(token)
  on.exit(try(pk_cancel_token_clear(token), silent = TRUE), add = TRUE)

  istek <- tryCatch(pk_async_build_request(
    user_prompt = "PSOCK bootstrap dogruluk turu", chat_history = list(),
    username = "soak.psock.boot", request_id = "soak_pk_psock_boot",
    deep_thinking = FALSE,
    api_key_plan = list(key = "sk-soak-fake", source = "personal"),
    user_session_snapshot = list(system_username = "soak.psock.boot", user_id = 1L),
    repo_root = root, cancel_token = token,
    # URETIMDEKI manifest turevli TAM kume. `pk_async_build_request()` bos
    # birakilan listeyi `character(0)` yapar ve isci `empty_file_list` ile
    # dogrudan `bootstrap_failed` doner; o zaman prob yine hicbir sey
    # kanitlamazdi.
    bootstrap_files = pk_async_worker_bootstrap_files(),
    deadline_sec = cfg_lane$psock_bootstrap_deadline_sec, engine = "v2",
    started_at = Sys.time()
  ), error = function(e) NULL)
  if (!is.list(istek)) return(bos("request_build_failed"))
  if (!isTRUE(pk_async_validate_request(istek)$safe)) return(bos("snapshot_unsafe"))

  paket$istek <- istek
  sonuc <- tryCatch({
    f <- future::future({ pk_async_run_analysis(istek) },
                        globals = paket, packages = c("stats", "utils"), seed = TRUE)
    future::value(f)
  }, error = function(e) structure(list(message = conditionMessage(e)),
                                   class = "soak_psock_error"))

  if (inherits(sonuc, "soak_psock_error")) {
    return(list(ran = TRUE, ok = FALSE, reason = "future_error",
                status = NA_character_,
                error = as.character(sonuc$message)[1]))
  }

  durum <- as.character((sonuc %||% list())$status %||% NA_character_)[1]
  bootstrap_dustu <- identical(durum, "bootstrap_failed")
  list(ran = TRUE, ok = !isTRUE(bootstrap_dustu) && !is.na(durum),
       reason = if (isTRUE(bootstrap_dustu)) "bootstrap_failed" else "ok",
       status = durum)
}

# TEK GIRIS TAVANI PROBU.
#
# Toplam bayt butcesi (`MERGEN_PK_CACHE_MAX_MB`) ile TEK GIRIS tavani
# (`MERGEN_PK_CACHE_MAX_ENTRY_MB`) FARKLI sinirlardir. Yalnizca toplami
# olcen bir kapi, tek giris tavanini yok sayan bir regresyonu gecirirdi:
# toplam butcenin altinda kalan tek bir buyuk giris kabul edilir ve butun
# onbellek kapilari yine yesil olurdu.
#
# Prob, tavani kucuk bir degere cekip TAVANI ASAN bir giris yazmayi dener;
# giris REDDEDILMELIDIR (`stored = FALSE`, `reason = "entry_too_large"`) ve
# `rejected_oversize` sayaci artmalidir.
soak_pk_cache_oversize_probe <- function() {
  bos <- list(ran = FALSE, rejected = FALSE, stored = NA, reason = NA_character_,
              rejected_delta = 0L)
  if (!exists("pk_cache_put", mode = "function") ||
      !exists("pk_cache_stats", mode = "function")) {
    return(bos)
  }

  onceki <- tryCatch(as.integer(pk_cache_stats()$rejected_oversize %||% 0L),
                     error = function(e) NA_integer_)
  if (is.na(onceki)) return(bos)

  # TEK GIRIS TAVANI ORTAM DEGISKENIYLE DE SABITLENIR.
  #
  # `pk_config_resolve()` sirasi `query_meta -> ENVIRONMENT -> options()`
  # seklindedir, yani ORTAM `options()` degerini EZER. `.Renviron` icinde
  # `MERGEN_PK_CACHE_MAX_ENTRY_MB` tanimliysa asagidaki secenek YOK SAYILIR ve
  # prob, yapilandirilmis (muhtemelen cok daha buyuk) gercek tavani hic asmadan
  # "gecmis" gorunurdu. Iki kanal da sabitlenir ve geri yuklenir.
  eski <- options(mergen.pk.cache_max_entry_mb = 1L)
  on.exit(options(eski), add = TRUE)

  eski_env_giris <- Sys.getenv("MERGEN_PK_CACHE_MAX_ENTRY_MB", unset = NA_character_)
  Sys.setenv(MERGEN_PK_CACHE_MAX_ENTRY_MB = "1")
  on.exit({
    if (is.na(eski_env_giris)) {
      Sys.unsetenv("MERGEN_PK_CACHE_MAX_ENTRY_MB")
    } else {
      do.call(Sys.setenv,
              stats::setNames(list(eski_env_giris), "MERGEN_PK_CACHE_MAX_ENTRY_MB"))
    }
  }, add = TRUE)

  # CERCEVE BOYUTU COZULMUS TAVANDAN TURETILIR: sabit bir satir sayisi, tavan
  # degistiginde sessizce yetersiz kalabilirdi.
  cozulmus_mb <- tryCatch(
    as.numeric(pk_config_resolve("MERGEN_PK_CACHE_MAX_ENTRY_MB"))[1],
    error = function(e) NA_real_
  )
  if (length(cozulmus_mb) != 1L || is.na(cozulmus_mb) || !is.finite(cozulmus_mb) ||
      cozulmus_mb <= 0) {
    return(bos)
  }

  # BENZERSIZ metinler ZORUNLUDUR: R ayni karakter degerini tek bir CHARSXP
  # olarak paylasir, dolayisiyla tekrarlanan bir dizgi `object.size()` ile
  # yalnizca isaretci maliyeti uretir ve tavan HIC asilmazdi.
  # ~65 bayt/satir: cozulmus tavanin en az 4 katini hedefler.
  n <- max(60000L, as.integer(ceiling(cozulmus_mb * 1024 * 1024 * 4 / 65)))
  buyuk <- data.frame(
    id = seq_len(n),
    metin = paste0("soak-", sprintf("%08d", seq_len(n)), "-", strrep("x", 48L)),
    stringsAsFactors = FALSE
  )
  sonuc <- tryCatch(pk_cache_put("soak_pk_oversize", buyuk), error = function(e) NULL)
  sonrasi <- tryCatch(as.integer(pk_cache_stats()$rejected_oversize %||% 0L),
                      error = function(e) NA_integer_)

  if (!is.list(sonuc) || is.na(sonrasi)) return(bos)

  # Giris ONBELLEGE ALINMAMIS olmalidir: okuma da ISKA donmelidir.
  okundu <- tryCatch(pk_cache_get("soak_pk_oversize"), error = function(e) list(hit = TRUE))

  list(
    ran = TRUE,
    stored = isTRUE(sonuc$stored),
    reason = as.character(sonuc$reason %||% NA_character_)[1],
    rejected_delta = as.integer(sonrasi - onceki),
    rejected = !isTRUE(sonuc$stored) && !isTRUE(okundu$hit) &&
      identical(as.character(sonuc$reason)[1], "entry_too_large") &&
      as.integer(sonrasi - onceki) >= 1L
  )
}

# URETIM HAVUZUNU serit-yerel SQLite uzerine kurar.
#
# `init_db_pool_once()` test enjeksiyonu icin `factory` argumanini kabul eder
# (CLAUDE.md havuz sozlesmesi). Boylece serit, ODBC/SQL Server olmadan GERCEK
# `db_acquire_tx_connection()` / `db_release_tx_connection()` yolunu ve onun
# checkout/return muhasebesini calistirir.
soak_pk_install_pool <- function(db_path) {
  gerekli <- c("init_db_pool_once", "db_acquire_tx_connection",
               "db_release_tx_connection", "db_pool_status_snapshot",
               "close_db_pool_once")
  if (!all(vapply(gerekli, function(f) exists(f, mode = "function"), logical(1)))) {
    return(FALSE)
  }
  if (!requireNamespace("pool", quietly = TRUE)) return(FALSE)

  fabrika <- function() {
    pool::dbPool(
      drv = RSQLite::SQLite(), dbname = db_path,
      minSize = 1L, maxSize = 4L, idleTimeout = 60,
      validationInterval = 0
    )
  }
  havuz <- tryCatch(init_db_pool_once("primary", factory = fabrika, force = TRUE,
                                      fail_fast = FALSE),
                    error = function(e) NULL)
  !is.null(havuz) && inherits(havuz, "Pool")
}

soak_pk_teardown_pool <- function() {
  if (exists("close_db_pool_once", mode = "function")) {
    try(close_db_pool_once("primary"), silent = TRUE)
  }
  if (exists("pool", envir = .GlobalEnv, inherits = FALSE)) {
    try(rm("pool", envir = .GlobalEnv), silent = TRUE)
  }
  invisible(NULL)
}

# Uretim havuzunun KENDI checkout/return muhasebesi. Serit sayaclari yalnizca
# "kac tur calisti" bilgisidir; SIZINTI kanitini bu fonksiyon uretir.
soak_pk_pool_leak <- function() {
  if (!exists("db_pool_status_snapshot", mode = "function")) return(NA_integer_)
  anlik <- tryCatch(db_pool_status_snapshot(), error = function(e) NULL)
  if (!is.list(anlik)) return(NA_integer_)
  # `checkout - returned`; havuz sayaclari `counters` altindadir.
  as.integer(anlik$counters$outstanding_checkouts %||% NA_integer_)
}

#' PK-analiz soak seridini calistir
#'
#' @param cfg soak_config() cikti listesi.
#' @return list(available=, sessions=, summary=, cancel=, cache=, guard=,
#'   deep=, does_prove=, does_not_prove=, reason=)
soak_pk_analysis_lane <- function(cfg) {
  boot <- soak_pk_bootstrap()
  if (!isTRUE(boot$available)) {
    return(list(available = FALSE, reason = soak_pk_bootstrap_reason(boot)))
  }

  sessions <- max(1L, as.integer(cfg$pk_lane_sessions %||% 60L))

  cfg_lane <- list(
    distinct_users = max(1L, as.integer(cfg$pk_lane_distinct_users %||% 6L)),
    # NOT: "farkli sorgu kimligi" icin AYAR YOKTUR ve OLMAMALIDIR. Seridin
    # onbellek erisim deseni bilerek SABITTIR (SICAK KUME + SOGUK KUYRUK):
    # serit-yerel LRU tavani 12 giristir; sicak havuz buyutulurse sicak
    # anahtarlar yeniden okunmadan tahliye olur ve ayni kosuda hem ISABET hem
    # TAHLIYE uretilemez. Eskiden burada cozulen `distinct_queries` alani
    # HICBIR YERDE OKUNMUYORDU; operator `MERGEN_SOAK_PK_DISTINCT_QUERIES`
    # ayarlayinca desenin degistigini SANIYOR ama serit ayni kaliyordu.
    deadline_sec = as.numeric(cfg$pk_lane_deadline_sec %||% 300),
    sql_timeout_sec = as.numeric(cfg$pk_lane_sql_timeout_sec %||% 120),
    row_cap = as.numeric(cfg$pk_lane_row_cap %||% 50000),
    rows_per_query = max(1L, as.integer(cfg$pk_lane_rows_per_query %||% 4000L)),
    chunk_rows = max(1L, as.integer(cfg$pk_lane_chunk_rows %||% 1000L)),
    max_result_mb = as.numeric(cfg$pk_lane_max_result_mb %||% 512),
    cancel_every = max(2L, as.integer(cfg$pk_lane_cancel_every %||% 7L)),
    stale_every = max(2L, as.integer(cfg$pk_lane_stale_every %||% 5L)),
    deep_every = max(2L, as.integer(cfg$pk_lane_deep_every %||% 9L)),
    deep_max_queries = max(2L, as.integer(cfg$pk_lane_deep_max_queries %||% 5L)),
    # Derin butce KUCUK tutulur ki `MERGEN_PK_SQL_TIMEOUT_SEC` degil KALAN
    # BUTCE baglayici olsun; aksi halde azalma olculemez.
    deep_budget_sec = max(4, as.numeric(cfg$pk_lane_deep_budget_sec %||% 10)),
    deep_step_sleep_sec = max(0.2, as.numeric(cfg$pk_lane_deep_step_sleep_sec %||% 1.2)),
    # Bootstrap turu GERCEKTEN kaynak yukler; son tarih bunun icin yeterli
    # olmalidir (yoksa tur "deadline" doner ve bootstrap hic olculmez).
    psock_bootstrap_deadline_sec = max(30, as.numeric(cfg$pk_lane_psock_bootstrap_deadline_sec %||% 120))
  )

  token_root <- file.path(tempdir(), paste0("soak_pk_tokens_", as.integer(Sys.time())))
  dir.create(token_root, recursive = TRUE, showWarnings = FALSE)

  # TABLO BOYUTU YAPILANDIRMADAN TURETILIR: fikstur sabit 20000 satirken
  # `MERGEN_SOAK_PK_ROWS_PER_QUERY` bunun uzerine ayarlanirsa her tur eksik
  # satir dondurur, `rows_complete` FALSE olur ve kapi URETIM kodu dogruyken
  # `pk_bounded_fetch_complete` gerilemesi RAPOR EDIYORDU.
  db <- tryCatch(
    soak_pk_make_db(max(20000L, as.integer(cfg_lane$rows_per_query))),
    error = function(e) NULL
  )
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
  # ORTAM DEGISKENI DE IZOLE EDILIR.
  #
  # `pk_config_resolve()` ORTAMI `options()` uzerinde onceliklendirir; operator
  # `.Renviron` icinde `MERGEN_PK_CACHE_MAX_ENTRIES` degerini seridin uretebildigi
  # ayrik anahtar sayisinin USTUNDE tanimladiginda tahliye HIC gerceklesmiyor ve
  # `pk_cache_eviction_observed` esigi KOD kusuru degil ORTAM nedeniyle
  # dusuyordu. Serit kendi tavanini her iki kanalda da kurar ve cikista GERI ALIR.
  eski_secenekler <- options(mergen.pk.cache_max_entries = 12L)
  on.exit(options(eski_secenekler), add = TRUE)
  eski_env_tavan <- Sys.getenv("MERGEN_PK_CACHE_MAX_ENTRIES", unset = NA_character_)
  Sys.setenv(MERGEN_PK_CACHE_MAX_ENTRIES = "12")
  on.exit({
    if (is.na(eski_env_tavan)) {
      Sys.unsetenv("MERGEN_PK_CACHE_MAX_ENTRIES")
    } else {
      Sys.setenv(MERGEN_PK_CACHE_MAX_ENTRIES = eski_env_tavan)
    }
  }, add = TRUE)
  entries_ceiling <- tryCatch(
    as.numeric(pk_config_resolve("MERGEN_PK_CACHE_MAX_ENTRIES"))[1],
    error = function(e) NA_real_
  )

  # SIRA ONEMLIDIR: `on.exit()` isleyicileri KAYIT SIRASINDA calisir. Uretim
  # havuzu SQLite dosyasina acik baglanti tutar; havuz once yikilmazsa Windows
  # `unlink()` acik tanitici yuzunden basarisiz olur ve serit her kosuda
  # `tempdir()` icinde bir SQLite dosyasi birakir. Havuz yikimi bu yuzden
  # BAGLANTI KAPATMA/SILME ile AYNI isleyicide ve ONUNDE calisir.
  on.exit({
    try(soak_pk_teardown_pool(), silent = TRUE)
    tryCatch(DBI::dbDisconnect(db$conn), error = function(e) NULL)
    unlink(db$path, force = TRUE)
    unlink(token_root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  # BAGLANTI MUHASEBESI: her tur URETIMDEKI al/birak ciftinden gecer.
  #
  # ONCEKI SURUM KENDINI DOGRULUYORDU: sarmalayici `get_connection()` /
  # `release_connection()` cagirmiyor, yalnizca kendi sayaclarini artirip
  # azaltiyordu. `on.exit()` sayesinde `acquired == released` HER ZAMAN
  # dogruydu; uretim yolu her istekte bir baglanti sizdirsa bile serit yesil
  # kalirdi. Simdi sarmalayici GERCEK `db_acquire_tx_connection()` /
  # `db_release_tx_connection()` ciftini kullanir ve muhasebe uretimin KENDI
  # checkout/return sayaclarindan (`db_pool_status_snapshot()`) okunur; bir
  # sizinti dogrudan `leaked > 0` olarak gorunur.
  #
  # `pool` paketi yoksa serit-yerel SQLite baglantisina duser (davranis
  # onceki gibidir) ve bu durum artifact'ta `instrumented = FALSE` olarak
  # ACIKCA raporlanir; "olculmedi" ile "gecti" karistirilmaz.
  # Havuz yikimi yukaridaki isleyicide (silmeden ONCE) yapilir; burada AYRI bir
  # `on.exit()` kaydi YOKTUR, aksi halde silme once calisirdi.
  havuz_kuruldu <- soak_pk_install_pool(db$path)

  conn_counts <- new.env(parent = emptyenv())
  conn_counts$acquired <- 0L
  conn_counts$released <- 0L
  al_birak <- function(fn) {
    if (!isTRUE(havuz_kuruldu)) {
      conn_counts$acquired <- conn_counts$acquired + 1L
      on.exit(conn_counts$released <- conn_counts$released + 1L, add = TRUE)
      return(fn(db$conn))
    }
    bilgi <- db_acquire_tx_connection("primary")
    conn_counts$acquired <- conn_counts$acquired + 1L
    on.exit({
      db_release_tx_connection(bilgi)
      conn_counts$released <- conn_counts$released + 1L
    }, add = TRUE)
    fn(bilgi$conn)
  }

  # UCUS-ICI iptal tetikleyicisi TURLERDEN ONCE bir kez kalibre edilir; ayni
  # sorgu sekli tum turlerde kullanildigi icin tek olcum yeterlidir.
  inflight_gate_k <- tryCatch(
    al_birak(function(baglanti) soak_pk_calibrate_inflight_gate(
      baglanti,
      sprintf("SELECT * FROM pk_veri WHERE id <= %d", cfg_lane$rows_per_query),
      cfg_lane
    )),
    error = function(e) NA_integer_
  )

  rows <- vector("list", sessions)
  for (i in seq_len(sessions)) {
    rows[[i]] <- tryCatch(
      al_birak(function(baglanti) soak_pk_one_session(i, baglanti, token_root, cfg_lane,
                                                     inflight_gate_k = inflight_gate_k)),
      error = function(e) list(
        idx = i, duration_ms = NA_real_, snapshot_safe = FALSE,
        cancelled_round = FALSE, inflight_cancel = FALSE, stale_round = FALSE,
        cache_hit = FALSE, cache_scope_ok = NA, rows_complete = NA,
        inflight_after_fetch = NA,
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
  # UCUS-ICI iptal, GERCEKTEN bir parca getirildikten SONRA gerceklesmis olmali.
  inflight_bad <- vapply(rows, function(r) isFALSE(r$inflight_after_fetch), logical(1))
  inflight_seen <- vapply(rows, function(r) isTRUE(r$inflight_after_fetch), logical(1))

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
  # OLCULDU + HEPSI DOGRU: getirim baslamadan yakalanan bir "ucus-ici" tur
  # bu boyutu DUSURUR (aksi halde parca-arasi kapi hic test edilmeden gecerdi).
  inflight_exercised <- sum(inflight) > 0L && !any(inflight_bad) && any(inflight_seen)
  stale_exercised <- sum(stale & !cancelled) > 0L
  cache_scope_isolated <- !any(scope_bad) && any(scope_seen)
  rows_always_complete <- !any(rows_bad) && any(rows_seen)

  # Tek giris tavani probu istatistikler OKUNMADAN ONCE calisir; kendi
  # sayac farkini kendisi olcer ve serit sayaclarini bozmaz (giris zaten
  # REDDEDILDIGI icin toplam bayt/giris sayisi degismez).
  oversize <- tryCatch(soak_pk_cache_oversize_probe(),
                       error = function(e) list(ran = FALSE, rejected = FALSE,
                                                stored = NA, reason = "probe_error",
                                                rejected_delta = 0L))
  cache_stats <- pk_cache_stats()
  psock <- tryCatch(soak_pk_psock_probe(cfg_lane),
                    error = function(e) list(ran = FALSE, ok = FALSE,
                                             reason = "probe_error",
                                             status = NA_character_,
                                             bootstrap_ran = FALSE,
                                             bootstrap_ok = FALSE,
                                             bootstrap_status = NA_character_))

  deep <- tryCatch(
    soak_pk_deep_budget_probe(db$conn, token_root, cfg_lane),
    error = function(e) list(
      dispatched = 0L, total_effective_sec = NA_real_,
      budget_sec = cfg_lane$deep_budget_sec, budget_respected = FALSE,
      budget_decreases = FALSE, statuses = "error",
      deadline_halts_between_queries = FALSE,
      cancel_halts_between_queries = FALSE
    )
  )

  # Baglanti muhasebesi: sinirli getirim her cikis yolunda sonuc kumesini
  # kapatir; getirimden sonra baglanti hala kullanilabilir olmalidir.
  #
  # PR #705: PROB, GETIRIMIN GERCEKTEN KULLANDIGI YOLDAN yapilir. Onceden
  # `db$conn` (serit kurulum baglantisi) sorgulaniyordu; sinirli getirimden
  # sonra HAVUZDAKI baglanti kirli/kullanilamaz kalsa bile bu kapi yesil
  # kaliyordu. Artik `al_birak()` uzerinden URETIM checkout'u yeniden alinir.
  conn_usable <- isTRUE(tryCatch(
    al_birak(function(baglanti) {
      probe <- DBI::dbGetQuery(baglanti, "SELECT COUNT(*) AS n FROM pk_veri")
      is.data.frame(probe) && nrow(probe) == 1L
    }),
    error = function(e) FALSE))

  # SIZINTI KANITI URETIMDEN OKUNUR. Serit sayaclari `on.exit()` sayesinde her
  # zaman dengelidir; asil kanit uretim havuzunun checkout-return farkidir.
  pool_leaked <- soak_pk_pool_leak()
  # AYRI AD: `conn_counts` `al_birak()` kapanisinin MUTASYONA ugrattigi bir
  # ortamdir. Ayni ada duz bir liste baglamak, sonraki bir `al_birak()` cagrisini
  # liste uzerinde calistirir; R o noktada cerceve-yerel bir KOPYA olusturur ve
  # al/birak muhasebesi SESSIZCE duser. Mevcut cagri sirasi bunu maskeliyordu.
  conn_ozet <- list(acquired = conn_counts$acquired,
                    released = conn_counts$released,
                    instrumented = isTRUE(havuz_kuruldu),
                    pool_leaked = pool_leaked)
  # PR #705: ENSTRUMANTASYON YOKSA KAPI GECMEZ.
  #
  # Onceki kosul `(!isTRUE(havuz_kuruldu) || ...)` idi: havuz kurulamadiginda
  # serit KENDI dogasi geregi dengeli sayaclarina duser ve kapi "uretim
  # acquire/release sizinti kapsami" raporlardi -- oysa uretim yolu HIC
  # calistirilmamis olurdu. "Olculmedi" ile "gecti" karistirilamaz: enstrumante
  # kosum ZORUNLUdur ve uretim sizinti sayaci SIFIR olmalidir.
  conn_balanced <- identical(conn_ozet$acquired, conn_ozet$released) &&
    conn_ozet$acquired >= sessions &&
    isTRUE(havuz_kuruldu) &&
    identical(as.integer(pool_leaked %||% -1L), 0L)

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
      inflight_after_fetch_rounds = sum(inflight_seen),
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
      # ETKIN URETIM TAVANI (soak yan degiskeni DEGIL). `MERGEN_SOAK_PK_CACHE_MAX_MB`
      # ile `MERGEN_PK_CACHE_MAX_MB` BAGIMSIZ degiskenlerdir: kapi soak yan
      # degiskenine bakinca, operator VM'de uretim tavanini 64 MB'a indirip soak
      # varsayilanini 512 MB birakmis olsa bile gozlenen toplam uretim sinirinin
      # USTUNDEYKEN kontrol GECIYOR (bozuk bayt-tahliye yolu yesil kaliyor).
      # Ayna durum da vardir: yalnizca soak degiskenini dusurmek kapiyi ORTAM
      # nedeniyle dusururdu. Bu yuzden uretimin KENDI cozumleyicisi okunur.
      total_ceiling_mb = suppressWarnings(as.numeric(tryCatch(
        pk_config_resolve("MERGEN_PK_CACHE_MAX_MB"), error = function(e) NA_real_))[1]),
      hit = cache_stats$hit,
      miss = cache_stats$miss,
      evicted = cache_stats$evicted,
      rejected_oversize = cache_stats$rejected_oversize,
      entries_ceiling = entries_ceiling,
      hit_observed = sum(hits) > 0L,
      # Tahliye GOZLENDI mi: LRU giris tavani gercekten asilmadiysa bozuk
      # bir tahliye yolu sessizce gecerdi.
      eviction_observed = isTRUE(as.numeric(cache_stats$evicted %||% 0)[1] > 0),
      scope_isolated = cache_scope_isolated,
      # TEK GIRIS tavani AYRI bir sinirdir; ayri kanit uretilir.
      oversize_probe_ran = isTRUE(oversize$ran),
      oversize_rejected = isTRUE(oversize$rejected),
      oversize_reason = oversize$reason,
      oversize_rejected_delta = oversize$rejected_delta
    ),
    fetch = list(
      rows_always_complete = rows_always_complete,
      complete_rounds = sum(rows_seen)
    ),
    deep = deep,
    psock = psock,
    db = list(connection_usable_after_bounded_fetch = conn_usable,
              acquire_release_balanced = conn_balanced,
              acquired = conn_ozet$acquired, released = conn_ozet$released,
              # URETIM al/birak ciftinden mi gecildi (yoksa serit-yerel
              # baglanti mi kullanildi) ve uretimin KENDI sizinti sayaci.
              instrumented = isTRUE(conn_ozet$instrumented),
              pool_leaked = conn_ozet$pool_leaked),
    does_prove = c(
      "Iptal jetonu YUK ALTINDA gorulur ve iptal edilen tur ASLA uygulanmaz",
      "UCUS-ICI iptal: getirim parcalar arasinda durur (tam olarak 'cancelled')",
      "Bayat tamamlanma daha yeni istegi EZMEZ; taze istek her zaman uygulanir",
      "Isci anlik goruntusu her turda oturum/reaktif/baglanti TASIMAZ",
      "Ardisik derin sorgular TEK MUTLAK son tarih uzerinden AZALAN butce alir",
      "TEK GIRIS onbellek tavanini asan sonuc REDDEDILIR (toplam butceden AYRI)",
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
