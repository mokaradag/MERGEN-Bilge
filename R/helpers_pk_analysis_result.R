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

# Modelin gördüğü "uygulanan filtre" listesi, LLM'in ÇIKARDIĞI ham küme değil
# gerçekten UYGULANAN kümedir. `apply_smart_filters()` geçersiz/etkisiz
# filtreleri düşürür; ham kümeyi göstermek pakete, `Bilgi` sayfasına ve alt
# bilgiye "bu filtre uygulandı" dedirtirdi — üstelik ifşa bloğu aynı filtrenin
# düşürüldüğünü söylerken.
.pk_result_effective_filters <- function(policy, filter_criteria) {
  if (is.list(policy) && !is.null(policy$applied) &&
      exists(".pk_filter_leaf_to_v1", mode = "function", inherits = TRUE)) {
    donusen <- tryCatch(lapply(policy$applied, .pk_filter_leaf_to_v1), error = function(e) NULL)
    if (is.list(donusen)) return(donusen)
  }
  filter_criteria$filters %||% list()
}

# Paket bütçesi, İSTEĞİN TAMAMINI kapsamalıdır: sistem istemi, kullanıcı
# sorusu, politika ifşası ve kuyruk talimatları da aynı yükün parçasıdır.
.pk_result_packet_budget <- function(overhead_chars, meta) {
  butce <- if (exists("pk_prompt_char_budget", mode = "function", inherits = TRUE)) {
    suppressWarnings(as.integer(pk_prompt_char_budget(query_meta = meta)))
  } else {
    120000L
  }
  if (length(butce) != 1L || is.na(butce) || butce <= 0L) butce <- 120000L

  # SABİT YÜK BÜTÇEYİ TÜKETİYORSA YAPAY ASGARİ AYRILMAZ.
  #
  # Eski `max(1000L, ...)` tabanı, zorunlu metin (sistem istemi + kullanıcı
  # sorusu + ifşalar + kuyruk talimatları) bütçeyi ZATEN aşmışken pakete 1000
  # karakter daha veriyordu. Sonuç, uç noktanın bağlam sınırının sessizce
  # aşılması ve isteğin TAMAMEN düşmesiydi. Negatif/ sıfır kalan bütçe artık
  # `0` olarak bildirilir; çağıran bunu `over_budget` olarak görür ve
  # deterministik özete iner.
  kalan <- as.integer(butce) - as.integer(overhead_chars)
  if (is.na(kalan) || kalan <= 0L) return(0L)
  kalan
}

# v2 kuyruğu: analiz paketi + kompozisyon + dışa aktarım.
.pk_result_v2 <- function(filtered_data, secure_data, query, user_prompt,
                          analysis_mode, policy, filter_criteria, session,
                          username = NULL, stop_check = NULL) {
  durduruldu <- function() is.function(stop_check) && isTRUE(tryCatch(stop_check(), error = function(e) FALSE))

  # Durdurma NEDENİ tiplidir: kullanıcı Stop'u ile son tarih AYRI sonuçlardır.
  halt_durumu <- function() {
    if (durduruldu()) return("cancelled")
    if (!exists("pk_async_stage_gate", mode = "function", inherits = TRUE)) return(NULL)
    jeton <- getOption("mergen.pk.async.cancel_token", NULL)
    son_tarih <- getOption("mergen.pk.async.deadline_at", NULL)
    if (is.null(jeton) && is.null(son_tarih)) return(NULL)
    kapi <- tryCatch(pk_async_stage_gate(jeton, son_tarih), error = function(e) NULL)
    if (!is.list(kapi) || !isTRUE(kapi$halt)) return(NULL)
    as.character(kapi$status %||% "cancelled")[1]
  }
  iptal_sonucu <- function(status = NULL) {
    list(type = "pk_stopped",
         pk_halt_status = as.character(status %||% halt_durumu() %||% "cancelled")[1])
  }
  iptal <- iptal_sonucu()

  meta <- .pk_result_meta(query)
  etkin_filtreler <- .pk_result_effective_filters(policy, filter_criteria)

  # PAKET KURULUMU KALAN BÜTÇEYLE SINIRLIDIR.
  #
  # `pk_packet_build()` büyük ama izinli bir sonuçta TÜM ÇERÇEVE üzerinde
  # kapsam/kategorik/gruplama/örnekleme işi yapar ve bu iş ilk iptal
  # denetiminden ÖNCE gelirdi. Sınırlı senkron geri düşmede bu, ana Shiny olay
  # döngüsünü bloke eder; işçide ise son tarih gözcüsü kullanıcıya çoktan yanıt
  # verdikten SONRA bile işçiyi meşgul tutardı. İş R/Rcpp hesabıdır, dolayısıyla
  # geçen süre bütçesi onu gerçekten kesebilir.
  if (!is.null(halt_durumu())) return(iptal_sonucu())

  paket_sonucu <- if (exists("pk_async_bounded_fs", mode = "function", inherits = TRUE)) {
    pk_async_bounded_fs(
      function() {
        pk_packet_build(filtered_data, query, list(
          authorized_rows = nrow(secure_data),
          filtered_rows = nrow(filtered_data),
          filters = etkin_filtreler,
          filter_status = filter_criteria$status,
          degradations = if (exists("pk_degradations_from_filter_status", mode = "function",
                                    inherits = TRUE)) {
            pk_degradations_from_filter_status(filter_criteria$status)
          } else {
            list()
          },
          pre_aggregated_columns = query$pre_aggregated_columns
        ))
      },
      getOption("mergen.pk.async.deadline_at", NULL)
    )
  } else {
    NULL
  }

  if (is.list(paket_sonucu)) {
    if (!isTRUE(paket_sonucu$ok)) return(iptal_sonucu(halt_durumu() %||% "deadline"))
    paket <- paket_sonucu$value
  } else {
    paket <- pk_packet_build(filtered_data, query, list(
      authorized_rows = nrow(secure_data),
      filtered_rows = nrow(filtered_data),
      filters = etkin_filtreler,
      filter_status = filter_criteria$status,
      degradations = if (exists("pk_degradations_from_filter_status", mode = "function",
                                inherits = TRUE)) {
        pk_degradations_from_filter_status(filter_criteria$status)
      } else {
        list()
      },
      pre_aggregated_columns = query$pre_aggregated_columns
    ))
  }

  ifsa <- if (is.list(policy) &&
              exists("pk_filter_policy_disclosure_block", mode = "function", inherits = TRUE)) {
    pk_filter_policy_disclosure_block(
      policy, dropped = policy$dropped %||% list(),
      noop_columns = policy$noop_columns %||% character(0)
    )
  } else {
    NULL
  }

  sistem_istemi <- pk_build_analysis_system_prompt_v2(analysis_mode, query)
  kuyruk_talimati <- paste0(
    "\n\n--- PAKET SONU ---\n\n",
    "Talimat: YALNIZCA yukaridaki paketteki olgulari kullanarak cevap ver. ",
    "Her sayisal iddianin yanina ilgili fact referansini koy. Hesaplama yapma, ",
    "tablo uretme; tablo ve ek R tarafindan eklenecektir."
  )
  bas_talimati <- paste0("KULLANICI SORUSU:\n", user_prompt,
                         "\n\n--- R TARAFINDAN HESAPLANAN ANALIZ PAKETI ---\n")

  # Bütçe muhasebesi PAKETİN DEĞİL isteğin tamamınındır.
  sabit_yuk <- nchar(sistem_istemi, type = "chars") +
    nchar(bas_talimati, type = "chars") +
    nchar(kuyruk_talimati, type = "chars") +
    nchar(as.character(ifsa %||% ""), type = "chars")

  if (durduruldu()) return(iptal)

  yazi <- pk_packet_render(paket, budget = .pk_result_packet_budget(sabit_yuk, meta),
                           query_meta = meta)

  tum_olgular <- pk_packet_all_facts(paket)
  yedek_metin <- pk_compose_facts_summary(paket$facts)

  # Düşürme merdiveni ZORUNLU bölümler yüzünden bütçeyi aşabilir. Bu durumda
  # paketi olduğu gibi göndermek, uç noktanın bağlam sınırını aşıp analizin
  # TAMAMINI düşürebilirdi; deterministik özete inilir.
  if (isTRUE(yazi$over_budget)) {
    ozet <- paste(c(
      "### BUTCE ASIMI",
      paste("- Analiz paketi yapilandirilmis bicimde istem butcesine SIGMADI;",
            "asagida yalnizca R tarafindan hesaplanan degerler yer aliyor."),
      "",
      yedek_metin
    ), collapse = "\n")

    if (nchar(ozet, type = "chars") <= yazi$budget) {
      yazi$text <- ozet
      yazi$chars <- nchar(ozet, type = "chars")
      yazi$over_budget <- FALSE
      yazi$omitted <- c(yazi$omitted, "Paket butce nedeniyle deterministik ozete indirildi.")
    } else {
      return(list(
        type = "error_message",
        content = paste0(
          "\U000026A0\U0000FE0F **Sonuç çok geniş:** Bu sorgunun analiz paketi güvenli ",
          "istem bütçesine sığmıyor. Lütfen sorunuzu daraltın (ör. tarih aralığı, ",
          "proje veya ölçü kısıtı ekleyin)."
        )
      ))
    }
  }

  karar <- pk_compose_decide(nrow(filtered_data), ncol(filtered_data), user_prompt, meta)

  if (durduruldu()) return(iptal)

  artefakt <- NULL
  if (!identical(karar$mode, "inline_table")) {
    artefakt <- tryCatch(
      pk_export_build(
        filtered_data, paket,
        context = list(
          query_id = query$id, query_name = query$name,
          # Denetim kimliği, RLS/telemetride kullanılan KİMLİĞİ DOĞRULANMIŞ
          # kullanıcı adıdır; `user_config$name` bir görünen ad olabilir,
          # boş olabilir veya kullanıcı tarafından değiştirilebilir.
          username = as.character(username %||%
            tryCatch(session$userData$user_config$name, error = function(e) NULL) %||% "?")[1],
          filters = etkin_filtreler,
          authorized_rows = nrow(secure_data), filtered_rows = nrow(filtered_data),
          rls_scope = "Kullanici yetkisi uygulandi"
        ),
        base_name = query$id %||% "pk_analiz", query = query, format = karar$format,
        # Yazım + geri okuma DOĞRULAMASI uzun sürer; iptal jetonu oraya da
        # geçirilmezse Durdur tüm I/O bitene kadar GÖZLENEMEZDİ.
        stop_check = stop_check
      ),
      error = function(e) {
        cat(sprintf("[PK_ANALIZ] Disa aktarim hatasi: %s\n", conditionMessage(e)))
        list(status = "failed", files = list(),
             message = "Dışa aktarım sırasında beklenmeyen bir hata oluştu.")
      }
    )
    artefakt <- tryCatch(pk_export_serve(session, artefakt), error = function(e) artefakt)
  }

  if (durduruldu()) return(iptal)

  blok <- paste0(pk_compose_block(karar, filtered_data, artefakt, meta, meta),
                 pk_compose_reference_links(query))

  list(
    type = "data_analysis",
    # D21: v1 filtre ÖNCESİ çerçeveyi döndürüyordu ve hiçbir çağıran onu
    # okumuyordu. v2'de bu alan gerçekten sunulan veridir.
    data = filtered_data,
    prompt_context = sistem_istemi,
    user_context = paste0(bas_talimati, yazi$text,
                          if (is.null(ifsa)) "" else paste0("\n\n", ifsa),
                          kuyruk_talimati),
    query_name = query$name,
    max_tokens = 4096,
    # Grup kırılımındaki ve bağlam bölümlerindeki olgular da doğrulama
    # indeksine girer; aksi hâlde DOĞRU alıntılanmış bir grup toplamı
    # `unknown_fact` sayılırdı.
    pk_facts = tum_olgular,
    pk_answer_block = blok,
    pk_attachment = artefakt,
    pk_fallback_text = yedek_metin,
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
                                     session = NULL, engine_is_v2 = FALSE,
                                     username = NULL, stop_check = NULL) {
  analysis_mode <- query$analysis_mode %||% "summary"
  kullanici_filtresi <- nrow(filtered_data) < nrow(secure_data)

  if (!isTRUE(engine_is_v2)) {
    return(.pk_result_v1(filtered_data, secure_data, query, user_prompt,
                         analysis_mode, kullanici_filtresi))
  }

  .pk_result_v2(filtered_data, secure_data, query, user_prompt, analysis_mode,
                policy, filter_criteria, session, username = username,
                stop_check = stop_check)
}
