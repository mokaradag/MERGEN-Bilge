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
# v2 analiz-paketi köprüsü
# ------------------------------------------------------------------------------

# Derin v2 seçim köprüsü çekirdek orkestrasyon sırasında global motor kapısını
# v1 gibi gösterebilir; seçilmiş sorgunun istek-yerel işareti önceliklidir.
pk_deep_query_is_v2 <- function(query) {
  isTRUE(query$pk_engine_v2) ||
    identical(as.character(query$pk_engine_mode %||% "")[1], "v2") ||
    (exists("pk_engine_is_v2", mode = "function", inherits = TRUE) &&
       isTRUE(tryCatch(pk_engine_is_v2(query$meta), error = function(e) FALSE)))
}

# Paket ve gözlem aynı GERÇEKTEN uygulanmış filtre kümesini görür.
pk_deep_effective_filters <- function(policy, filter_criteria, engine_v2 = FALSE) {
  if (isTRUE(engine_v2) &&
      exists(".pk_result_effective_filters", mode = "function", inherits = TRUE)) {
    return(tryCatch(.pk_result_effective_filters(policy, filter_criteria),
                    error = function(e) filter_criteria$filters %||% list()))
  }
  filter_criteria$filters %||% list()
}

# v2 tekil Deep Thinking sonucu, standart PK v2 yolunun AYNI paket/fact
# çekirdeğinden kurulur. Grain/weighted/latest/unit/percent semantics burada
# yeniden uygulanmaz; sahipleri pk_packet_build()/pk_packet_all_facts()'tır.
pk_deep_build_v2_packet_result <- function(filtered_data, secure_data, query,
                                           filter_status, applied_filters,
                                           detail_config, finish_result,
                                           pre_rls_rows, stop_check = NULL) {
  query_name <- query$name %||% "Bilinmeyen Sorgu"
  finish <- function(result, outcome = NULL) {
    finish_result(
      result,
      filter_status = filter_status,
      filters = applied_filters,
      pre_rls_rows = pre_rls_rows,
      authorized_rows = nrow(secure_data),
      filtered_rows = nrow(filtered_data),
      outcome = outcome
    )
  }
  halted <- function() {
    if (is.function(stop_check) && isTRUE(tryCatch(stop_check(), error = function(e) FALSE))) {
      return("cancelled")
    }
    gate <- tryCatch(
      pk_async_stage_gate(detail_config$pk_cancel_token, detail_config$pk_deadline_at),
      error = function(e) NULL
    )
    if (is.list(gate) && isTRUE(gate$halt)) as.character(gate$status)[1] else NULL
  }

  gerekli <- c("pk_packet_build", "pk_packet_render", "pk_packet_all_facts",
               "pk_compose_facts_summary")
  if (any(!vapply(gerekli, exists, logical(1), mode = "function", inherits = TRUE))) {
    return(finish(list(
      query_name = query_name, success = FALSE,
      error_msg = paste0("Kanonik v2 analiz paketi bileşenleri yüklenmedi; ",
                         "legacy özete güvenlik gereği geri düşülmedi.")
    ), "Hata"))
  }

  durum <- halted()
  if (!is.null(durum)) return(pk_deep_halt_result(durum))

  build <- function() pk_packet_build(filtered_data, query, list(
    authorized_rows = nrow(secure_data), filtered_rows = nrow(filtered_data),
    filters = applied_filters, filter_status = filter_status,
    degradations = if (exists("pk_degradations_from_filter_status", mode = "function",
                              inherits = TRUE)) {
      pk_degradations_from_filter_status(filter_status)
    } else list(),
    pre_aggregated_columns = query$pre_aggregated_columns
  ))

  paket_sonucu <- if (exists("pk_async_bounded_fs", mode = "function", inherits = TRUE)) {
    pk_async_bounded_fs(build, detail_config$pk_deadline_at)
  } else {
    list(ok = TRUE, value = build())
  }
  if (!isTRUE(paket_sonucu$ok)) return(pk_deep_halt_result(halted() %||% "deadline"))
  paket <- paket_sonucu$value

  durum <- halted()
  if (!is.null(durum)) return(pk_deep_halt_result(durum))

  paket_yazi <- pk_packet_render(paket, query_meta = query$meta)
  if (isTRUE(paket_yazi$over_budget)) {
    return(finish(list(
      query_name = query_name, success = FALSE,
      error_msg = paste0("Kanonik v2 analiz paketi güvenli istem bütçesine sığmadı; ",
                         "legacy özete geri düşülmeden sorgu atlandı.")
    ), "Reddedildi"))
  }

  durum <- halted()
  if (!is.null(durum)) return(pk_deep_halt_result(durum))

  cat(sprintf("[DEEP_QUERY] '%s' - Başarılı: %d satır, kanonik v2 paket oluşturuldu.\n",
              query_name, nrow(filtered_data)))

  finish(list(
    query_name = query_name,
    query_desc = query$description %||% "",
    query_id = query$id,
    query_meta = query$meta,
    success = TRUE,
    row_count = nrow(filtered_data),
    relevance = query$relevance_score %||% 0,
    pk_engine_mode = "v2",
    pk_packet = paket,
    pk_packet_text = paket_yazi$text,
    pk_packet_chars = paket_yazi$chars,
    pk_facts = pk_packet_all_facts(paket),
    pk_fallback_text = pk_compose_facts_summary(paket$facts),
    data = filtered_data
  ), "Basarili")
}

# Uzlaştırmadan SONRA yalnız başarılı v2 paketlerinin olguları nihai numeric
# provenance registry'sine girer; bozulmuş/başarısız paketler kanıt değildir.
pk_deep_collect_v2_provenance <- function(query_results, primary_meta = NULL) {
  v2 <- Filter(function(r) {
    isTRUE(r$success) && identical(as.character(r$pk_engine_mode %||% "")[1], "v2")
  }, query_results %||% list())
  if (!length(v2)) {
    return(list(facts = NULL, fallback_text = NULL, query_id = NULL, mode = NULL))
  }

  facts <- unlist(lapply(v2, function(r) r$pk_facts %||% list()), recursive = FALSE)
  fallback <- vapply(v2, function(r) {
    txt <- as.character(r$pk_fallback_text %||% "")[1]
    if (is.na(txt) || !nzchar(txt)) "" else paste0("### ", r$query_name %||% "Sorgu", "\n", txt)
  }, character(1))
  fallback <- fallback[nzchar(fallback)]

  ids <- vapply(v2, function(r) {
    as.character(r$query_id %||% r$pk_observation$query_id %||% "")[1]
  }, character(1))
  ids <- ids[nzchar(ids)]

  list(
    facts = if (length(facts)) facts else NULL,
    fallback_text = if (length(fallback)) paste(fallback, collapse = "\n\n") else NULL,
    query_id = if (length(ids)) paste(ids, collapse = ",") else NULL,
    mode = if (exists("pk_numeric_provenance_mode", mode = "function", inherits = TRUE)) {
      tryCatch(pk_numeric_provenance_mode(primary_meta), error = function(e) NULL)
    } else NULL
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

    # ETKİN MOTOR TELEMETRİYE GERÇEK DEĞERİYLE YAZILIR.
    #
    # `engine = "v1"` sabitlenmişti; Derin Düşünme v2 seçim/filtre yolundan
    # geçtiğinde bile tüm gözlemler v1 diye kaydediliyordu. Bu, motora göre
    # bölümlenmiş telemetri ve soak sonuçlarını kullanılamaz hâle getiriyor,
    # yani bu PR'ın doğrulamak istediği davranış ölçülemiyordu.
    etkin_motor <- if (exists("pk_engine_is_v2", mode = "function", inherits = TRUE)) {
      if (isTRUE(tryCatch(pk_engine_is_v2(), error = function(e) FALSE))) "v2" else "v1"
    } else {
      "v1"
    }

    info <- list(
      request_id = pk_request_id,
      question = user_prompt,
      username = username,
      engine = etkin_motor,
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

  # Birleşik Deep Thinking alt bilgisi, v2 altında yalnızca görünen footer'ı
  # değil uzlaştırılmış kanonik olgu kayıtlarını da taşır. Böylece nihai model
  # yanıtı standart v2 yolu ile AYNI numeric-provenance doğrulamasından geçer.
  # v1 çağrılarında yeni argümanların tamamı NULL'dur ve eski footer davranışı
  # değişmez.
  stash_deep_footer <- function(footers, facts = NULL, fallback_text = NULL,
                                query_id = NULL, mode = NULL) {
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

    pk_provenance_stash(
      session, combined_footer, request_id = pk_request_id,
      facts = facts, fallback_text = fallback_text,
      query_id = query_id, mode = mode
    )
  }

  list(observe = pk_observe_deep, stash = stash_deep_footer)
}
