# ==============================================================================
# Dosya Yolu: R/helpers_deep_analysis_reconcile.R
# Açıklama: Faz 6 (D16, §10) — Derin Düşünme'nin ana PK yolu ile uzlaştırılması.
# ==============================================================================

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

# SEÇİM aşamasında uygulanabilecek EN YÜKSEK tavan.
#
# Sıralı-küme tavanı sorgu metadata'sıyla YÜKSELTİLEBİLİR, ama metadata ancak
# BİRİNCİL SORGU SEÇİLDİKTEN sonra bilinir. Seçiciye yalnızca küresel tavan
# verilirse (ör. küresel 5, sorgu override'ı 10) aday sayısı 5'te kalır ve
# override tavanı ASLA yükseltemez. Bu yüzden seçim, şema tarafından izin
# verilen üst sınıra kadar aday üretir; kesin tavan metadata bilindikten sonra
# uygulanır. Şema sınırı okunamazsa küresel tavan korunur (davranış değişmez).
pk_deep_max_queries_upper_bound <- function() {
  kuresel <- pk_deep_max_queries()

  ust <- tryCatch({
    if (!exists("pk_config_spec", inherits = TRUE)) return(kuresel)
    spec <- get("pk_config_spec", inherits = TRUE)
    aday <- spec[["MERGEN_PK_DEEP_MAX_QUERIES"]]$max
    suppressWarnings(as.integer(aday)[1])
  }, error = function(e) NA_integer_)

  if (length(ust) != 1L || is.na(ust) || ust < kuresel) return(kuresel)
  ust
}

# ------------------------------------------------------------------------------
# Paket seviyesi uzlaştırma
# ------------------------------------------------------------------------------

# `NULL`, `NA` ve boş metni AYNI ŞEKİLDE "eksik" sayan birleştirici.
.pk_deep_coalesce_text <- function(value, fallback) {
  metin <- tryCatch(as.character(value)[1], error = function(e) NA_character_)
  if (length(metin) != 1L || is.na(metin) || !nzchar(trimws(metin))) {
    return(as.character(fallback)[1])
  }
  metin
}

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

  # BOZULMUŞ filtre durumu (zaman aşımı / bozuk LLM yanıtı) taşıyan bir paket
  # BAŞARILI KANIT DEĞİLDİR. Filtre üretilemediğinde v2 yürütücüsü tüm yetkili
  # kümeyi döndürebilir; paketi "başarılı" saymak, filtreli bir soruya tam-küme
  # istatistiğini KENDİNDEN EMİN biçimde raporlamak olurdu.
  bozuk_filtre <- vapply(koken, function(k) {
    if (!exists("pk_filter_status_is_degraded", mode = "function", inherits = TRUE)) {
      return(FALSE)
    }
    isTRUE(tryCatch(pk_filter_status_is_degraded(k$filter_status), error = function(e) FALSE))
  }, logical(1))

  if (any(bozuk_filtre)) {
    # `%||%` bu repoda YALNIZCA `NULL` için yedeğe düşer. `koken[[i]]$error`
    # yukarıda `NA_character_` ile ilklendirildiği için `%||%` kullanmak
    # açıklama yerine `NA` KORURDU (aynı desen `error_msg` için de geçerli).
    dusurme_sebebi <- "Filtre planı üretilemedi; paket kanıt olarak kullanılmadı."
    for (i in which(bozuk_filtre)) {
      koken[[i]]$success <- FALSE
      koken[[i]]$error <- .pk_deep_coalesce_text(koken[[i]]$error, dusurme_sebebi)
      if (i <= length(paketler) && is.list(paketler[[i]])) {
        paketler[[i]]$success <- FALSE
        paketler[[i]]$error_msg <- .pk_deep_coalesce_text(paketler[[i]]$error_msg, dusurme_sebebi)
      }
    }
  }

  basarili <- vapply(koken, function(k) isTRUE(k$success), logical(1))

  list(
    packets = paketler,
    provenance = koken,
    successful = sum(basarili),
    failed = length(koken) - sum(basarili),
    degraded_filter = sum(bozuk_filtre),
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