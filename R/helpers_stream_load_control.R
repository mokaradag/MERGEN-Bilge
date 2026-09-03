# ==============================================================================
# Dosya Yolu: R/helpers_stream_load_control.R
# Açıklama: Yüksek eşzamanlılık altında olay-döngüsü/LLM basıncını azaltan yük
#           denetimi yardımcıları:
#             - araç ailesine göre kabul-denetimi (backpressure) türü çözümü,
#             - takip (follow-up) önerisi üretimini yük altında kısma/atlama,
#             - kaydedilen sohbet (saved chats) yenilemesini debounce etme.
#           Bu dosya R/helpers_streaming_io.R (paylaşılan ortam/metrik yardımcıları)
#           ile R/helpers_request_backpressure.R'den SONRA yüklenir.
#
# Tasarım sözleşmesi (DAVRANIŞI VARSAYILAN OLARAK DEĞİŞTİRMEZ):
#   - Backpressure limitleri varsayılan 0 (KAPALI) iken her kabul başarılıdır.
#   - Takip üretimi varsayılan ETKİN; limit kapalıyken her zaman çalışır.
#   - Saved-chats debounce varsayılan 0 ms (anında yenileme = mevcut davranış).
# ==============================================================================

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}

# Araç ailesinden kabul-denetimi türünü çözer. Ağır işlemler kendi limit
# havuzlarını kullanır; diğerleri genel "llm" havuzunu paylaşır.
mergen_send_message_backpressure_kind <- function(tool_family) {
  tf <- tryCatch(as.character(tool_family)[1], error = function(e) "")
  if (length(tf) == 0L || is.na(tf)) tf <- ""

  switch(
    tf,
    sql_analysis  = "sql_analysis",
    mcp_excel     = "mcp_excel",
    summarization = "summarization",
    "llm"
  )
}

# ------------------------------------------------------------------------------
# Takip (follow-up) önerisi yük denetimi
# ------------------------------------------------------------------------------

# Takip üretim planını ortamdan çözer (saf).
#   enabled                  : MERGEN_FOLLOWUPS_ENABLED (varsayılan TRUE)
#   delay_seconds            : MERGEN_FOLLOWUP_DELAY_SECONDS (varsayılan 0 = mevcut)
#   disable_under_backpressure: MERGEN_DISABLE_FOLLOWUPS_UNDER_BACKPRESSURE (vars. TRUE)
mergen_followup_dispatch_plan <- function() {
  list(
    enabled = .mergen_stream_env_flag("MERGEN_FOLLOWUPS_ENABLED", default = TRUE),
    delay_seconds = max(0, .mergen_stream_env_num("MERGEN_FOLLOWUP_DELAY_SECONDS", 0)),
    disable_under_backpressure = .mergen_stream_env_flag(
      "MERGEN_DISABLE_FOLLOWUPS_UNDER_BACKPRESSURE", default = TRUE
    )
  )
}

# Takip üretimi için kabul kararı verir ve gerekiyorsa bir backpressure slotu alır.
# Dönüş: list(run, token, reason). Çağıran, run=TRUE ise üretimden SONRA token'ı
# mergen_send_message_release_slot(...) ile bırakmalıdır.
#   - plan etkin değilse           -> run=FALSE, reason="disabled"
#   - slot alınırsa                -> run=TRUE  (limit 0 iken token=NULL, no-op)
#   - slot alınamaz + disable bayrağı-> run=FALSE, reason="backpressure"
#   - slot alınamaz + bayrak kapalı -> run=TRUE  (en iyi-çaba; token=NULL)
mergen_followup_try_admit <- function(plan = NULL) {
  if (is.null(plan)) plan <- mergen_followup_dispatch_plan()

  if (!isTRUE(plan$enabled)) {
    .mergen_stream_metric_inc("followups_skipped_disabled")
    return(list(run = FALSE, token = NULL, reason = "disabled"))
  }

  admission <- if (exists("mergen_backpressure_try_acquire", mode = "function", inherits = TRUE)) {
    mergen_backpressure_try_acquire("followups")
  } else {
    list(acquired = TRUE, token = NULL)
  }

  if (isTRUE(admission$acquired)) {
    .mergen_stream_metric_inc("followups_scheduled")
    return(list(run = TRUE, token = admission$token, reason = "admitted"))
  }

  if (isTRUE(plan$disable_under_backpressure)) {
    .mergen_stream_metric_inc("followups_skipped_backpressure")
    return(list(run = FALSE, token = NULL, reason = "backpressure"))
  }

  # Kısma istenmiyorsa en iyi-çaba ile yine de çalıştır (slot yok).
  .mergen_stream_metric_inc("followups_scheduled")
  list(run = TRUE, token = NULL, reason = "best_effort")
}

# Yanıt sonlandıktan SONRA, kritik yolun DIŞINDA takip (follow-up) önerilerini
# bloklamayan bir later() döngüsünde üretip istemciye iletir. Üretim, kabul
# denetimi (backpressure) ile yük altında atlanabilir; üretici hata verirse sayaç
# artar ve sessizce geçilir. later_fn/build_fn enjekte edilebilir (test/izolasyon).
# Dönüş: planlama yapıldıysa TRUE, devre dışı ise FALSE.
mergen_stream_dispatch_followups <- function(session,
                                             msg_id,
                                             user_message_text,
                                             final_text,
                                             settings_data,
                                             api_config,
                                             followup_tools,
                                             fallback_followup_tool,
                                             plan = NULL,
                                             later_fn = NULL,
                                             build_fn = NULL) {
  if (is.null(plan)) plan <- mergen_followup_dispatch_plan()
  if (!isTRUE(plan$enabled)) return(invisible(FALSE))

  if (is.null(later_fn)) later_fn <- later::later
  if (is.null(build_fn)) build_fn <- build_followup_suggestions

  later_fn(function() {
    fu_admit <- mergen_followup_try_admit(plan)
    if (!isTRUE(fu_admit$run)) return(invisible(NULL))
    on.exit(mergen_send_message_release_slot(fu_admit$token), add = TRUE)

    followup_perf_start <- mergen_perf_now()
    followup_questions <- tryCatch(
      build_fn(
        user_message_text, final_text, settings_data, session,
        api_config, followup_tools, fallback_followup_tool
      ),
      error = function(e) {
        mergen_runtime_metric_inc("followups_failed")
        NULL
      }
    )

    # Varsayılan KAPALI perf işareti: artık kritik yolun DIŞINDA olan takip
    # üretim süresini (saniyeler olabilir) ölçer.
    mergen_perf_log("stream.followups", start = followup_perf_start,
                    fields = list(count = length(followup_questions %||% character(0))))

    if (!is.null(followup_questions) && length(followup_questions) > 0) {
      try(
        push_followup_update(session, msg_id, followup_questions, pending = FALSE),
        silent = TRUE
      )
    }
  }, delay = plan$delay_seconds)

  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# Kaydedilen sohbet yenilemesini debounce etme
# ------------------------------------------------------------------------------

# Debounce penceresini (ms) ortamdan çözer. Varsayılan 0 = debounce kapalı.
mergen_saved_chats_refresh_debounce_ms <- function() {
  ms <- .mergen_stream_env_num("MERGEN_SAVED_CHATS_REFRESH_DEBOUNCE_MS", 0)
  if (!is.finite(ms) || ms < 0) 0 else ms
}

# Oturuma özel debounce durumunu (pending/dirty) tutan ortamı döndürür/oluşturur.
.mergen_saved_chats_refresh_store <- function(session) {
  ud <- session$userData
  store <- ud$saved_chats_refresh_store
  if (is.null(store) || !is.environment(store)) {
    store <- new.env(parent = emptyenv())
    store$pending <- FALSE
    store$dirty <- FALSE
    ud$saved_chats_refresh_store <- store
  }
  store
}

# Kaydedilen sohbet listesini debounce ederek yeniler. Debounce 0 (varsayılan)
# iken anında yeniler (mevcut davranış). Debounce > 0 iken pencere içindeki birden
# çok çağrı tek bir yenilemede birleştirilir (coalesce); bekleyen zamanlayıcı
# varken yeni zamanlayıcı kurulmaz. Oturum-yereldir; bir oturum diğerini etkilemez.
mergen_schedule_saved_chats_refresh <- function(session, saved_chats_data,
                                                debounce_ms = NULL,
                                                later_fn = NULL) {
  refresh_fn <- tryCatch(saved_chats_data$refresh, error = function(e) NULL)
  if (!is.function(refresh_fn)) return(invisible(FALSE))

  if (is.null(later_fn)) later_fn <- later::later
  if (is.null(debounce_ms)) debounce_ms <- mergen_saved_chats_refresh_debounce_ms()
  debounce_ms <- suppressWarnings(as.numeric(debounce_ms)[1])
  if (!is.finite(debounce_ms) || debounce_ms <= 0) {
    try(refresh_fn(), silent = TRUE)
    .mergen_stream_metric_inc("saved_chats_refresh_executed")
    return(invisible(TRUE))
  }

  store <- .mergen_saved_chats_refresh_store(session)
  store$dirty <- TRUE

  if (isTRUE(store$pending)) {
    .mergen_stream_metric_inc("saved_chats_refresh_coalesced")
    return(invisible(TRUE))
  }

  store$pending <- TRUE
  .mergen_stream_metric_inc("saved_chats_refresh_scheduled")

  later_fn(function() {
    store$pending <- FALSE
    if (!isTRUE(store$dirty)) return(invisible(NULL))
    store$dirty <- FALSE
    ok <- tryCatch({ refresh_fn(); TRUE }, error = function(e) FALSE)
    if (isTRUE(ok)) {
      .mergen_stream_metric_inc("saved_chats_refresh_executed")
    } else {
      .mergen_stream_metric_inc("saved_chats_refresh_failed")
    }
  }, delay = debounce_ms / 1000)

  invisible(TRUE)
}