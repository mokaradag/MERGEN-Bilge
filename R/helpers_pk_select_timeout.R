# ==============================================================================
# Dosya Yolu: R/helpers_pk_select_timeout.R
# Açıklama: Faz 5 / Faz 6 — sorgu SEÇİCİSİNİN etkin HTTP zaman aşımı sözleşmesi.
#
# NEDEN AYRI DOSYA: v1 (`helpers_pk_analysis_ai_selector.R`) ve v2
# (`helpers_pk_query_selection_ai.R`) seçicileri aynı kararı veriyordu, fakat
# yalnızca v2 TABAN zaman aşımını her yolda uyguluyordu. v1'de taban değer
# YALNIZCA bir async son tarihi yayımlanmışken kuruluyordu; sevk edilen
# varsayılanlar (eski motor + kapalı async) hiçbir son tarih yayımlamaz,
# dolayısıyla asılı bir uç nokta ANA Shiny sürecini süresizce bloke
# edebiliyordu (D14'ün v1'de geri dönüşü). Karar tek yerde toplanır ki iki
# hat bir daha ayrışamasın.
#
# SÖZLEŞME: taban `MERGEN_PK_SELECT_TIMEOUT_SEC`'tir; kalan analiz bütçesi
# tabanı yalnızca DARALTIR, asla genişletmez. Aşağı yuvarlama 0 üretiyorsa
# istek HİÇ gönderilmez (`dispatch = FALSE`).
#
# Dosya SAFTIR: Shiny/reactive/DB/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

#' Seçici çağrısı için etkin zaman aşımını çöz
#'
#' @param base_sec Taban saniye. `NULL` ise `MERGEN_PK_SELECT_TIMEOUT_SEC`
#'   çözümlenir; çözümleme başarısız olursa güvenli varsayılan 60 saniyedir.
#' @param query_meta Sorgu metadata'sı (yalnızca yapılandırma çözümlemesi için).
#' @return `dispatch` (istek gönderilsin mi) ve `timeout_sec` alanlı liste.
pk_select_effective_timeout <- function(base_sec = NULL, query_meta = NULL) {
  taban <- base_sec
  if (is.null(taban)) {
    taban <- tryCatch(
      pk_config_resolve("MERGEN_PK_SELECT_TIMEOUT_SEC", query_meta = query_meta),
      error = function(e) NULL
    )
  }
  taban <- suppressWarnings(as.integer(taban)[1])
  # Geçersiz/eksik taban SINIRSIZ demek DEĞİLDİR: bu yardımcı tam olarak
  # "asılı uç nokta olay döngüsünü bloke etmesin" diye vardır.
  if (length(taban) != 1L || is.na(taban) || taban < 1L) taban <- 60L

  son_tarih <- getOption("mergen.pk.async.deadline_at", NULL)

  # SON TARİH YOKSA bütçe kurulmamıştır: taban zaman aşımıyla gönderilir.
  if (is.null(son_tarih)) {
    return(list(dispatch = TRUE, timeout_sec = taban))
  }

  # MUTLAK SON TARİH VARSA KAPALI BAŞARISIZ DAVRANILIR: eski yol, yardımcı
  # eksikse ya da hesap hata verirse TAM tabanı geri verip gönderime İZİN
  # veriyordu; süresi dolmuş bir istek 60 sn'lik yeni bir LLM çağrısı
  # başlatabiliyordu. Bütçe hesaplanamıyorsa gönderim YAPILMAZ.
  if (!exists("pk_sql_timeout_plan", mode = "function", inherits = TRUE) ||
      !exists("pk_deadline_remaining_sec", mode = "function", inherits = TRUE)) {
    return(list(dispatch = FALSE, timeout_sec = 0L))
  }

  kalan <- tryCatch(pk_deadline_remaining_sec(son_tarih),
                    error = function(e) NA_real_)
  if (length(kalan) != 1L || is.na(kalan)) {
    return(list(dispatch = FALSE, timeout_sec = 0L))
  }

  plan <- tryCatch(pk_sql_timeout_plan(taban, kalan), error = function(e) NULL)
  if (!is.list(plan)) return(list(dispatch = FALSE, timeout_sec = 0L))

  # GEÇERSİZ PLAN TABANLA DEĞİŞTİRİLMEZ: taban kalan bütçeden UZUN olabilir.
  ts <- suppressWarnings(as.integer(plan$timeout_sec)[1])
  if (length(ts) != 1L || is.na(ts) || ts < 1L) return(list(dispatch = FALSE, timeout_sec = 0L))
  list(dispatch = isTRUE(plan$dispatch), timeout_sec = ts)
}
