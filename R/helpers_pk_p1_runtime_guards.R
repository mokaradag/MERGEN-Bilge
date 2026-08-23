# ==============================================================================
# Dosya Yolu: R/helpers_pk_p1_runtime_guards.R
# PR #705 P1: doğrudan DB süreç sınırı ve Derin Düşünme v2 paket köprüsü.
# ==============================================================================

# TEKRAR YÜKLEME KORUMASI "BAYRAK" DEĞİL, "ZATEN SARMALANMIŞ MI" SORUSUDUR.
#
# Eski sürüm dosyanın TAMAMINI tek bir `.pk_p1_runtime_guards_loaded` bayrağıyla
# çevreliyordu. `global.R` yeniden kaynaklandığında `helpers_pk_async_worker.R`
# `pk_async_run_analysis()`i SARMALANMAMIŞ hâliyle yeniden tanımlıyor, ama
# bayrak hâlâ TRUE olduğu için bu dosya sarmalayıcıyı YENİDEN KURMUYORDU.
# Sonuç: sonraki gönderim `.pk_p1_run_direct_disposable()` izolasyonunu
# tamamen atlıyordu. Karar artık `helpers_pk_worker_observers.R` ile aynı
# desene dayanır: MEVCUT public fonksiyon işaretli bir sarmalayıcı değilse
# yeniden kurulur. Yardımcı tanımlar düz atama olduğundan tekrar çalıştırılması
# güvenlidir.
.pk_p1_direct_child_marker <- "MERGEN_PK_DIRECT_DB_CHILD"

# Sarmalayıcı işareti: özyinelemeli sarmalamayı (sonsuz döngü) engeller.
.pk_p1_wrapper_mark <- "pk_p1_runtime_guard"

.pk_p1_is_wrapped <- function(fn) {
  is.function(fn) && isTRUE(attr(fn, .pk_p1_wrapper_mark, exact = TRUE))
}

# İşçi global paketi ÖNBELLEKLENİR. Sarmalayıcı yeniden kurulduğunda önbellek
# eski (sarmalanmamış) gövdeyi taşıyor olabilir; bu yüzden geçersiz kılınır.
.pk_p1_reset_worker_globals <- function() {
  sifirla <- get0("pk_async_worker_globals_reset", mode = "function",
                  inherits = TRUE, ifnotfound = NULL)
  if (is.function(sifirla)) try(sifirla(), silent = TRUE)
  invisible(TRUE)
}

.pk_p1_pool_enabled_for_request <- function(request) {
  snap <- request$db_pool_options
  if (is.list(snap)) {
    value <- snap[["mergen.db.pool_enabled"]]
    unset <- get0(".PK_ASYNC_OPTION_UNSET", inherits = TRUE,
                  ifnotfound = "__pk_option_unset__")
    if (!is.null(value) && !identical(value, unset)) {
      return(isTRUE(suppressWarnings(as.logical(value))[1]))
    }
  }
  fn <- get0("is_db_pool_enabled", mode = "function", inherits = TRUE,
             ifnotfound = NULL)
  is.function(fn) && isTRUE(tryCatch(fn(), error = function(e) FALSE))
}

.pk_p1_direct_gate <- function(request) {
  token <- as.character(request$cancel_token %||% "")[1]
  if (!nzchar(token)) token <- NULL
  started <- tryCatch(
    as.POSIXct(as.numeric(request$started_at_epoch %||% NA_real_),
               origin = "1970-01-01"),
    error = function(e) Sys.time()
  )
  if (length(started) != 1L || is.na(started)) started <- Sys.time()
  deadline <- pk_deadline_at(started, request$deadline_sec)
  function() pk_async_stage_gate(token, deadline)
}

# İsteğin KALAN mutlak bütçesi (saniye). Bütçe yoksa `Inf` döner ve davranış
# değişmez; sıfıra düşmüşse alt sınır 1 saniyedir (0/negatif değer kütüphane
# tarafından geçersiz sayılır ve başlatma HİÇ denenemezdi).
.pk_p1_remaining_budget_sec <- function(request) {
  sure <- suppressWarnings(as.numeric(request$deadline_sec %||% NA_real_)[1])
  if (!length(sure) || is.na(sure) || !is.finite(sure) || sure <= 0) return(Inf)

  baslangic <- tryCatch(
    as.POSIXct(suppressWarnings(as.numeric(request$started_at)[1]), origin = "1970-01-01"),
    error = function(e) NULL
  )
  if (is.null(baslangic) || is.na(baslangic)) return(sure)

  kalan <- sure - as.numeric(difftime(Sys.time(), baslangic, units = "secs"))
  if (!is.finite(kalan)) return(sure)
  max(kalan, 1)
}

.pk_p1_kill_cluster <- function(cluster) {
  if (is.null(cluster) || !length(cluster)) return(invisible(FALSE))
  for (node in cluster) {
    try(parallelly::killNode(node, signal = tools::SIGTERM), silent = TRUE)
  }
  invisible(TRUE)
}

.pk_p1_run_direct_disposable <- function(request) {
  gate <- .pk_p1_direct_gate(request)
  first_gate <- gate()
  if (isTRUE(first_gate$halt)) {
    return(list(status = first_gate$status, result = NULL,
                session_writes = list(), error = NA_character_,
                diagnostics = list(duration_ms = 0)))
  }

  # PSOCK BAŞLATMA DA İSTEK BÜTÇESİYLE SINIRLIDIR.
  #
  # `makeClusterPSOCK()` SENKRONDUR ve son iptal/son-tarih kapısından SONRA,
  # yoklama döngüsünden ÖNCE çalışır. El sıkışma askıda kalırsa istek, PK son
  # tarihi ÇOKTAN dolmuş olsa bile küme başlatma zaman aşımı kadar bloke
  # kalır; kapı bu çağrı dönene dek bunu GÖZLEYEMEZ. Başlatma kalan bütçeyle
  # sınırlanır ve dönüşte kapı YENİDEN yoklanır.
  # `connectTimeout`/`timeout` SOKET HAREKETSİZLİĞİNİ sınırlar, ÇAĞRININ TAMAMINI
  # değil: Unix/macOS'ta askıda bir el sıkışma bu iki değerin ÜSTÜNDE bloke
  # kalabilir. Bu yüzden başlatma AYRICA repo genelinde kullanılan bağımsız
  # bütçe sarmalayıcısından (`pk_async_bounded_fs()`) geçirilir; sarmalayıcı
  # yoksa (izole test/eski çalışma kopyası) davranış aynen korunur.
  kalan <- .pk_p1_remaining_budget_sec(request)
  baslat <- function() {
    if (is.finite(kalan)) {
      parallelly::makeClusterPSOCK(1L, connectTimeout = kalan, timeout = kalan)
    } else {
      parallelly::makeClusterPSOCK(1L)
    }
  }
  cluster <- if (is.finite(kalan) &&
                 exists("pk_async_bounded_fs", mode = "function", inherits = TRUE)) {
    sonuc <- pk_async_bounded_fs(baslat, deadline_at = Sys.time() + kalan)
    if (isTRUE(sonuc$ok)) sonuc$value else NULL
  } else {
    tryCatch(baslat(), error = function(e) NULL)
  }
  if (is.null(cluster)) {
    return(list(status = "bootstrap_failed", result = NULL,
                session_writes = list(), error = "Tek kullanimlik DB iscisi baslatilamadi.",
                diagnostics = list(duration_ms = 0)))
  }
  on.exit(.pk_p1_kill_cluster(cluster), add = TRUE)

  # Başlatma sırasında Durdur gelmiş ya da son tarih dolmuş olabilir.
  start_gate <- gate()
  if (isTRUE(start_gate$halt)) {
    return(list(status = start_gate$status, result = NULL,
                session_writes = list(), error = NA_character_,
                diagnostics = list(duration_ms = 0)))
  }

  old_plan <- future::plan()
  on.exit(try(future::plan(old_plan), silent = TRUE), add = TRUE)
  future::plan(future::cluster, workers = cluster)

  child <- future::future({
    Sys.setenv(MERGEN_PK_DIRECT_DB_CHILD = "1", MERGEN_DISABLE_FUTURES = "true")
    setwd(request$repo_root)
    source(file.path(request$repo_root, "global.R"), encoding = "UTF-8",
           local = globalenv())
    pk_async_run_analysis(request)
  }, seed = TRUE)

  repeat {
    state <- gate()
    if (isTRUE(state$halt)) {
      .pk_p1_kill_cluster(cluster)
      return(list(status = state$status, result = NULL,
                  session_writes = list(), error = NA_character_,
                  diagnostics = list(duration_ms = 0)))
    }
    if (isTRUE(future::resolved(child))) break
    Sys.sleep(0.05)
  }

  value <- tryCatch(future::value(child), error = function(e) e)
  .pk_p1_kill_cluster(cluster)
  if (inherits(value, "error")) {
    return(list(status = "error", result = NULL, session_writes = list(),
                error = "Tek kullanimlik DB iscisi tamamlanamadi.",
                diagnostics = list(duration_ms = 0)))
  }
  value
}

if (exists("pk_async_run_analysis", mode = "function", inherits = TRUE) &&
    !.pk_p1_is_wrapped(get("pk_async_run_analysis", mode = "function", inherits = TRUE))) {
  .pk_p1_original_pk_async_run_analysis <- get("pk_async_run_analysis",
                                               mode = "function", inherits = TRUE)
  pk_async_run_analysis <- function(request) {
    child <- identical(Sys.getenv(.pk_p1_direct_child_marker, unset = ""), "1")
    if (child || .pk_p1_pool_enabled_for_request(request)) {
      return(.pk_p1_original_pk_async_run_analysis(request))
    }
    .pk_p1_run_direct_disposable(request)
  }
  attr(pk_async_run_analysis, .pk_p1_wrapper_mark) <- TRUE
  .pk_p1_reset_worker_globals()
}

if (exists("execute_single_deep_query", mode = "function", inherits = TRUE) &&
    !.pk_p1_is_wrapped(get("execute_single_deep_query", mode = "function", inherits = TRUE))) {
.pk_p1_original_execute_single_deep_query <- get("execute_single_deep_query",
                                                 mode = "function", inherits = TRUE)
execute_single_deep_query <- function(query, user_prompt, session, rls_info,
                                      detail_config, stop_check = NULL,
                                      chat_history = NULL) {
  v2 <- exists("pk_engine_is_v2", mode = "function", inherits = TRUE) &&
    isTRUE(tryCatch(pk_engine_is_v2(query$meta), error = function(e) FALSE))
  if (!v2) {
    return(.pk_p1_original_execute_single_deep_query(
      query, user_prompt, session, rls_info, detail_config, stop_check, chat_history
    ))
  }

  # NATIF v2 YOLU LEGACY ÖZET KANCASINI ÇAĞIRMAZ.
  #
  # `execute_single_deep_query()` başarılı her v2 sorgusunu artık
  # `pk_deep_build_v2_packet_result()` üzerinden döndürür ve
  # `generate_statistical_summary()`ye HİÇ uğramaz. Bu sarmalayıcı ise legacy
  # kancanın `holder$data` doldurmasını "filtreli veri var" KANITI sayıyordu;
  # kanca hiç çağrılmadığı için sarmalayıcı başarılı HER v2 derin sorgusunu
  # istisnaya çeviriyor ve çevreleyen döngü onları başarısız sayıyordu.
  #
  # Kanca TEK çalıştırma etrafında kurulur (SQL İKİ KEZ ÇALIŞTIRILMAZ); natif
  # sonuç kanonik paketi (`pk_packet`) taşıyorsa OLDUĞU GİBİ kabul edilir ve
  # legacy yeniden kurulum ATLANIR.
  owner <- environment(.pk_p1_original_execute_single_deep_query)
  legacy <- get0("generate_statistical_summary", envir = owner, inherits = TRUE,
                 ifnotfound = NULL)
  if (!is.function(legacy)) {
    stop("v2 Derin Dusunme paket ozeti kurulamadı.", call. = FALSE)
  }

  holder <- new.env(parent = emptyenv())
  assign("generate_statistical_summary", function(data, ...) {
    holder$data <- data
    list(row_count = nrow(data), summary_text = "", preview_data = data[0, , drop = FALSE])
  }, envir = owner)
  on.exit(assign("generate_statistical_summary", legacy, envir = owner), add = TRUE)

  result <- .pk_p1_original_execute_single_deep_query(
    query, user_prompt, session, rls_info, detail_config, stop_check, chat_history
  )
  if (!is.list(result) || !isTRUE(result$success)) return(result)

  # NATİF v2 PAKETİ VARSA İŞ BİTMİŞTİR.
  if (!is.null(result$pk_packet)) return(result)

  if (!exists("data", envir = holder, inherits = FALSE)) {
    stop("v2 Derin Dusunme filtreli veri paketi olusturulamadi.", call. = FALSE)
  }

  filtered <- holder$data
  filters <- result$pk_observation$filters %||% list()
  effective <- .pk_result_effective_filters(
    policy = list(applied = NULL),
    filter_criteria = list(filters = filters)
  )
  authorized_rows <- suppressWarnings(as.integer(result$pk_observation$authorized_rows)[1])
  if (length(authorized_rows) != 1L || is.na(authorized_rows) || authorized_rows < nrow(filtered)) {
    authorized_rows <- nrow(filtered)
  }

  packet <- pk_packet_build(
    filtered,
    query,
    list(
      authorized_rows = authorized_rows,
      filtered_rows = nrow(filtered),
      filters = effective,
      filter_status = result$pk_observation$filter_status %||% "ok",
      degradations = list(),
      pre_aggregated_columns = query$pre_aggregated_columns
    )
  )
  rendered <- pk_packet_render(packet)

  result$summary_text <- rendered$text
  result$preview_json <- "{}"
  result$row_count <- nrow(filtered)
  result$pk_packet <- packet
  result$pk_packet_chars <- nchar(rendered$text, type = "chars")
  result$pk_packet_render_mode <- rendered$mode
  result$pk_facts <- pk_packet_all_facts(packet)
  result
}
attr(execute_single_deep_query, .pk_p1_wrapper_mark) <- TRUE
.pk_p1_reset_worker_globals()
}

# Geriye dönük uyumluluk: bazı tanı betikleri bu bayrağı okur. Artık KURULUM
# KARARINI VERMEZ; yalnızca dosyanın en az bir kez yüklendiğini bildirir.
.pk_p1_runtime_guards_loaded <- TRUE
