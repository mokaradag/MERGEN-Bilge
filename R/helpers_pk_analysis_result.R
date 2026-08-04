# ==============================================================================
# Dosya Yolu: R/helpers_pk_analysis_result.R
# Açıklama: Proje ve Kaynak Analizi sonuç kurucusu — v1 / v2 ayrımının TEK yeri.
#
#           Bu dosya, modülün kuyruğundaki "istatistik -> yük -> sistem istemi ->
#           dönüş sözleşmesi" bloğunu üstlenir. Amaç master plan §6'nın açık
#           talebidir: `R/module_proje_kaynak_analizi.R` KÜÇÜLMELİDİR. v2 dalını
#           modülün içine yazmak modülü büyütürdü.
#
#           v1 DALI DAVRANIŞ OLARAK DEĞİŞMEZ: aynı `generate_statistical_summary()`,
#           aynı yük kurucusu, aynı sistem istemi ve aynı dönüş sözleşmesi
#           (`data = secure_data` dâhil — D21 yalnızca v2'de düzeltilir, çünkü
#           §10 motor sınırı v1 kararlarına dokunmayı yasaklar).
#
#           v2 DALI (§5.7 / §5.8 / §5.9 / §5.11):
#             * analiz paketi TÜM satırlar üzerinden kurulur,
#             * sistem istemi epistemik etiketleme kullanır ve markdown tablo
#               ÜRETMEZ,
#             * sonuç tablosu ve Excel eki R tarafından üretilir,
#             * D21: `data` artık filtre SONRASI çerçevedir.
#
#           Dosya G/Ç yapar (dışa aktarım dosyası yazımı ve oturum kapsamlı
#           sunum); saf DEĞİLDİR. Saf kararlar paket/kompozisyon/dışa aktarım
#           planı dosyalarındadır.
# ==============================================================================

.pk_result_meta <- function(query) {
  if (is.list(query) && is.list(query$meta)) return(query$meta)
  list()
}

# v1 kuyruğu: BİREBİR korunur.
.pk_result_v1 <- function(filtered_data, secure_data, query, user_prompt,
                          analysis_mode, user_filter_applied) {
  stat_summary <- generate_statistical_summary(
    filtered_data,
    max_preview_rows = if (nrow(filtered_data) <= 500) nrow(filtered_data) else 500,
    mode = analysis_mode,
    rls_total_rows = nrow(secure_data),
    user_filter_applied = user_filter_applied,
    pre_aggregated_columns = query$pre_aggregated_columns
  )

  data_str <- pk_build_analysis_payload(
    stat_summary = stat_summary, query = query, engine_is_v2 = FALSE, policy = NULL
  )

  if (nrow(secure_data) > nrow(filtered_data)) {
    data_str <- paste0(
      data_str,
      sprintf("\n\n(RLS ve filtreleme oncesi toplam %d satir vardi)", nrow(secure_data))
    )
  }

  list(
    type = "data_analysis",
    data = secure_data,
    prompt_context = pk_build_analysis_system_prompt(analysis_mode, query),
    user_context = paste0(
      "KULLANICI SORUSU:\n", user_prompt,
      "\n\n--- R TARAFINDAN HAZIRLANAN ISTATISTIKSEL OZET ---\n", data_str,
      "\n\n--- OZET SONU ---\n\n",
      "Talimat: Yukaridaki istatistikleri kullanarak kullanicinin sorusuna DOGRUDAN cevap ver. ",
      "Sayilari AYNEN kullan. Trendleri ve onemli bulgulari vurgula."
    ),
    query_name = query$name,
    max_tokens = 4096
  )
}

# v2 kuyruğu: analiz paketi + kompozisyon + dışa aktarım.
.pk_result_v2 <- function(filtered_data, secure_data, query, user_prompt,
                          analysis_mode, policy, filter_criteria, session) {
  meta <- .pk_result_meta(query)

  paket <- pk_packet_build(filtered_data, query, list(
    authorized_rows = nrow(secure_data),
    filtered_rows = nrow(filtered_data),
    filters = filter_criteria$filters %||% list(),
    filter_status = filter_criteria$status,
    degradations = if (exists("pk_degradations_from_filter_status", mode = "function",
                              inherits = TRUE)) {
      pk_degradations_from_filter_status(filter_criteria$status)
    } else {
      list()
    },
    pre_aggregated_columns = query$pre_aggregated_columns
  ))

  yazi <- pk_packet_render(paket)

  ifsa <- if (is.list(policy) &&
              exists("pk_filter_policy_disclosure_block", mode = "function", inherits = TRUE)) {
    pk_filter_policy_disclosure_block(
      policy, dropped = policy$dropped %||% list(),
      noop_columns = policy$noop_columns %||% character(0)
    )
  } else {
    NULL
  }

  karar <- pk_compose_decide(nrow(filtered_data), ncol(filtered_data), user_prompt, meta)

  artefakt <- NULL
  if (!identical(karar$mode, "inline_table")) {
    artefakt <- tryCatch(
      pk_export_build(
        filtered_data, paket,
        context = list(
          query_id = query$id, query_name = query$name,
          username = tryCatch(session$userData$user_config$name, error = function(e) NULL),
          filters = filter_criteria$filters %||% list(),
          authorized_rows = nrow(secure_data), filtered_rows = nrow(filtered_data),
          rls_scope = "Kullanici yetkisi uygulandi"
        ),
        base_name = query$id %||% "pk_analiz", query = query
      ),
      error = function(e) {
        cat(sprintf("[PK_ANALIZ] Disa aktarim hatasi: %s\n", conditionMessage(e)))
        list(status = "failed", files = list(),
             message = "Dışa aktarım sırasında beklenmeyen bir hata oluştu.")
      }
    )
    artefakt <- tryCatch(pk_export_serve(session, artefakt), error = function(e) artefakt)
  }

  blok <- pk_compose_block(karar, filtered_data, artefakt, meta, meta)

  list(
    type = "data_analysis",
    # D21: v1 filtre ÖNCESİ çerçeveyi döndürüyordu ve hiçbir çağıran onu
    # okumuyordu. v2'de bu alan gerçekten sunulan veridir.
    data = filtered_data,
    prompt_context = pk_build_analysis_system_prompt_v2(analysis_mode, query),
    user_context = paste0(
      "KULLANICI SORUSU:\n", user_prompt,
      "\n\n--- R TARAFINDAN HESAPLANAN ANALIZ PAKETI ---\n", yazi$text,
      if (is.null(ifsa)) "" else paste0("\n\n", ifsa),
      "\n\n--- PAKET SONU ---\n\n",
      "Talimat: YALNIZCA yukaridaki paketteki olgulari kullanarak cevap ver. ",
      "Her sayisal iddianin yanina [fact:...] referansini koy. Hesaplama yapma, ",
      "tablo uretme; tablo ve ek R tarafindan eklenecektir."
    ),
    query_name = query$name,
    max_tokens = 4096,
    pk_facts = paket$facts,
    pk_answer_block = blok,
    pk_attachment = artefakt,
    pk_fallback_text = pk_compose_facts_summary(paket$facts),
    pk_packet_chars = yazi$chars
  )
}

#' Analiz sonucunu kur (motor sınırına göre v1 veya v2)
#'
#' @param filtered_data Yetki VE kullanıcı filtresi uygulanmış çerçeve.
#' @param secure_data Yetki uygulanmış, kullanıcı filtresi UYGULANMAMIŞ çerçeve.
#' @param policy v2 filtre politikası kararı (varsa).
pk_build_analysis_result <- function(filtered_data, secure_data, query, user_prompt,
                                     filter_criteria = list(), policy = NULL,
                                     session = NULL, engine_is_v2 = FALSE) {
  analysis_mode <- query$analysis_mode %||% "summary"
  kullanici_filtresi <- nrow(filtered_data) < nrow(secure_data)

  if (!isTRUE(engine_is_v2)) {
    return(.pk_result_v1(filtered_data, secure_data, query, user_prompt,
                         analysis_mode, kullanici_filtresi))
  }

  .pk_result_v2(filtered_data, secure_data, query, user_prompt, analysis_mode,
                policy, filter_criteria, session)
}
