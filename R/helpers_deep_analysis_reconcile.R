# ==============================================================================
# Dosya Yolu: R/helpers_deep_analysis_reconcile.R
# Açıklama: Faz 6 (D16, §10) — Derin Düşünme'nin ana PK yolu ile uzlaştırılması.
# ==============================================================================

#' Derin mod için kimlik: ana yol ile aynı fail-closed kapı.
pk_deep_resolve_username <- function(session, resolver = NULL) {
  if (is.null(resolver) &&
      exists("resolve_pk_analysis_username", mode = "function", inherits = TRUE)) {
    resolver <- get("resolve_pk_analysis_username", mode = "function", inherits = TRUE)
  }

  if (!is.function(resolver)) {
    return(list(
      ready = FALSE, username = NA_character_, reason = "resolver_missing",
      message = paste0(
        "\U000026A0\U0000FE0F **Kimlik Doğrulama Hatası:** Kullanıcı kimliği ",
        "güvenli biçimde çözümlenemedi; derin analiz sürdürülmedi."
      )
    ))
  }

  durum <- tryCatch(resolver(session), error = function(e) NULL)
  if (!is.list(durum) || !isTRUE(durum$ready)) {
    return(list(
      ready = FALSE,
      username = NA_character_,
      reason = as.character(durum$reason %||% "unknown")[1],
      message = paste0(
        "\U000023F3 **Kimlik Doğrulama Hazırlanıyor:** ",
        "Derin analiz için kullanıcı kimliğiniz henüz hazır değil. ",
        "Lütfen SSO oturumunuz tamamlandıktan sonra tekrar deneyin."
      )
    ))
  }

  list(
    ready = TRUE,
    username = as.character(durum$username)[1],
    reason = "ok",
    message = NA_character_
  )
}

#' Sorgu için SQL metnini çöz.
#'
#' Runtime'da tek kanonik kaynak startup sırasında önyüklenen `query$sql`'dir.
#' Eksik önyükleme, request-time disk/UNC yeniden okumasına düşmek yerine
#' fail-closed biçimde "missing" döner. `read_file_fn` yalnızca eski çağrı
#' imzasıyla uyumluluk için korunur ve bilinçli olarak kullanılmaz.
pk_deep_query_sql_text <- function(query, read_file_fn = NULL) {
  onyuklu <- tryCatch(as.character(query$sql %||% "")[1], error = function(e) "")
  if (!is.na(onyuklu) && nzchar(trimws(onyuklu))) {
    return(list(sql = pk_deep_normalize_sql_text(onyuklu), source = "preloaded"))
  }

  list(sql = "", source = "missing")
}

#' SQL metnini ana yolla aynı biçimde normalize et (BOM + satır sonu).
pk_deep_normalize_sql_text <- function(sql_text) {
  metin <- tryCatch(as.character(sql_text)[1], error = function(e) "")
  if (is.na(metin) || !nzchar(metin)) return("")

  metin <- enc2utf8(metin)
  bom <- intToUtf8(65279L)
  if (startsWith(metin, bom)) metin <- substring(metin, 2L)
  gsub("\r\n?|\r", "\n", metin, perl = TRUE)
}

#' Derin mod SQL yürütme: Unicode yol + kalan request deadline + Faz 6 sınırları.
pk_deep_execute_sql <- function(conn, sql_text, deadline_at = NULL,
                                cancel_token = NULL, query_meta = NULL,
                                unicode_param = TRUE, cache_key = NULL) {
  coz <- function(key, fallback) {
    if (!exists("pk_config_resolve", mode = "function", inherits = TRUE)) return(fallback)
    tryCatch(pk_config_resolve(key, query_meta), error = function(e) fallback)
  }

  onbellek_anahtari <- as.character(cache_key %||% "")[1]
  if (nzchar(onbellek_anahtari) &&
      exists("pk_cache_get", mode = "function", inherits = TRUE)) {
    isabet <- tryCatch(
      pk_cache_get(onbellek_anahtari, query_meta = query_meta),
      error = function(e) list(hit = FALSE)
    )
    if (isTRUE(isabet$hit) && is.data.frame(isabet$value)) {
      return(list(
        status = "ok", data = isabet$value, rows = nrow(isabet$value),
        error = NA_character_, timeout_sec = 0L, timeout_reason = "cache_hit",
        timeout_mechanism = "none", cached = TRUE
      ))
    }
  }

  kalan <- pk_deadline_remaining_sec(deadline_at)
  plan <- pk_sql_timeout_plan(coz("MERGEN_PK_SQL_TIMEOUT_SEC", 120L), kalan)
  if (!isTRUE(plan$dispatch)) {
    return(list(
      status = "deadline", data = NULL, rows = 0L,
      error = NA_character_, timeout_sec = 0L,
      timeout_reason = plan$reason
    ))
  }

  zaman_asimi <- pk_sql_apply_statement_timeout(conn, plan$timeout_sec)

  sonuc <- pk_sql_execute_bounded(
    conn = conn,
    sql_text = sql_text,
    unicode_param = isTRUE(unicode_param),
    chunk_rows = coz("MERGEN_PK_FETCH_CHUNK_ROWS", 5000L),
    max_result_mb = coz("MERGEN_PK_MAX_RESULT_MB", 512L),
    stage_gate = function() pk_async_stage_gate(cancel_token, deadline_at),
    timeout_sec = plan$timeout_sec,
    deadline_at = deadline_at
  )

  if (identical(sonuc$status, "ok") && nzchar(onbellek_anahtari) &&
      is.data.frame(sonuc$data) &&
      exists("pk_cache_put", mode = "function", inherits = TRUE)) {
    try(
      pk_cache_put(onbellek_anahtari, sonuc$data, query_meta = query_meta),
      silent = TRUE
    )
  }

  list(
    status = sonuc$status,
    data = sonuc$data,
    rows = sonuc$rows,
    error = sonuc$error,
    timeout_sec = plan$timeout_sec,
    timeout_reason = plan$reason,
    timeout_mechanism = zaman_asimi$mechanism,
    cached = FALSE
  )
}

#' Derin Düşünme sıralı-küme tavanı.
pk_deep_max_queries <- function(query_meta = NULL) {
  if (!exists("pk_config_resolve", mode = "function", inherits = TRUE)) return(5L)
  deger <- tryCatch(
    pk_config_resolve("MERGEN_PK_DEEP_MAX_QUERIES", query_meta),
    error = function(e) 5L
  )
  tavan <- suppressWarnings(as.integer(deger)[1])
  if (length(tavan) != 1L || is.na(tavan) || tavan < 1L) return(5L)
  tavan
}

# ------------------------------------------------------------------------------
# Paket seviyesi uzlaştırma
# ------------------------------------------------------------------------------

pk_deep_reconcile_packets <- function(query_results) {
  paketler <- if (is.list(query_results)) Filter(is.list, query_results) else list()

  koken <- lapply(paketler, function(sonuc) {
    gozlem <- if (is.list(sonuc$pk_observation)) sonuc$pk_observation else list()
    list(
      query_id = as.character(gozlem$query_id %||% NA_character_)[1],
      query_name = as.character(sonuc$query_name %||% gozlem$query_name %||% "?")[1],
      success = isTRUE(sonuc$success),
      row_count = suppressWarnings(as.numeric(sonuc$row_count %||% NA_real_)[1]),
      pre_rls_rows = suppressWarnings(as.numeric(gozlem$pre_rls_rows %||% NA_real_)[1]),
      authorized_rows = suppressWarnings(as.numeric(gozlem$authorized_rows %||% NA_real_)[1]),
      filtered_rows = suppressWarnings(as.numeric(gozlem$filtered_rows %||% NA_real_)[1]),
      filter_status = as.character(gozlem$filter_status %||% "not_reached")[1],
      relevance = suppressWarnings(as.numeric(sonuc$relevance %||% NA_real_)[1]),
      error = as.character(sonuc$error_msg %||% NA_character_)[1]
    )
  })

  basarili <- vapply(koken, function(k) isTRUE(k$success), logical(1))

  list(
    packets = paketler,
    provenance = koken,
    successful = sum(basarili),
    failed = length(koken) - sum(basarili),
    cross_query_arithmetic_allowed = FALSE,
    instruction = PK_DEEP_NO_CROSS_ARITHMETIC_INSTRUCTION,
    comparability = pk_deep_packet_comparability(koken)
  )
}

PK_DEEP_NO_CROSS_ARITHMETIC_INSTRUCTION <- paste0(
  "ÖNEMLİ KISIT: Aşağıdaki her analiz bloğu BAĞIMSIZ bir sorgudan gelir ve ",
  "kendi kapsamını, kendi filtrelerini ve kendi satır sayılarını taşır. ",
  "Bloklar arasındaki sayıları TOPLAMAYIN, ORTALAMASINI ALMAYIN, ",
  "BİRBİRİNDEN ÇIKARMAYIN ve tek bir toplam üretmeyin. Aynı kırılıma ",
  "(grain) sahip görünmeleri bunun için izin değildir; sorgular örtüşen ",
  "popülasyonları veya uyumsuz toplama semantiği olan ölçüleri kapsayabilir. ",
  "Her bulguyu hangi sorgudan geldiğini belirterek raporlayın."
)

pk_deep_packet_comparability <- function(provenance) {
  if (!is.list(provenance) || length(provenance) < 2L) {
    return(list(comparable = FALSE, reason = "single_packet"))
  }

  list(
    comparable = FALSE,
    reason = "distinct_queries_distinct_scopes",
    packet_count = length(provenance)
  )
}

# ------------------------------------------------------------------------------
# Gözlem + birleşik köken alt bilgisi fabrikası
# ------------------------------------------------------------------------------

pk_deep_observation_helpers <- function(session, conn, username, user_prompt,
                                        request_id, started_at) {
  pk_request_id <- request_id
  pk_started_at <- started_at

  pk_observe_deep <- function(observation) {
    if (!exists("pk_analysis_observe", mode = "function", inherits = TRUE)) return("")

    info <- list(
      request_id = pk_request_id,
      question = user_prompt,
      username = username,
      engine = "v1",
      deep_thinking = TRUE,
      duration_ms = as.numeric(difftime(Sys.time(), pk_started_at, units = "secs")) * 1000
    )
    if (is.list(observation) && length(observation) > 0L) {
      info[names(observation)] <- observation
    }

    tryCatch({
      footer <- pk_analysis_observe(session, conn, info)
      footer <- as.character(footer)[1]
      if (is.na(footer)) "" else footer
    }, error = function(e) "")
  }

  stash_deep_footer <- function(footers) {
    if (!exists("pk_provenance_stash", mode = "function", inherits = TRUE)) {
      return(invisible(FALSE))
    }

    footers <- as.character(footers)
    footers <- footers[!is.na(footers) & nzchar(footers)]
    if (length(footers) == 0L) return(invisible(FALSE))

    standard_prefix <- "\n\n---\n**Analiz Kaynağı**\n"
    bodies <- vapply(footers, function(footer) {
      body <- if (startsWith(footer, standard_prefix)) {
        substring(footer, nchar(standard_prefix) + 1L)
      } else {
        footer
      }
      sub("\n$", "", body)
    }, character(1))

    combined_footer <- paste0(
      "\n\n---\n",
      "**Analiz Kaynağı (Derin Analiz)**\n",
      paste(bodies, collapse = "\n\n"),
      "\n"
    )

    pk_provenance_stash(session, combined_footer, request_id = pk_request_id)
  }

  list(observe = pk_observe_deep, stash = stash_deep_footer)
}