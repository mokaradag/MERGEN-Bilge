# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_worker_sql.R
# Açıklama: Faz 6 (§5.10) — işçi içindeki SINIRLI SQL köprüsü.
#
# `pk_analiz_process_request()` SQL'i `execute_pk_sql_unicode()` üzerinden
# çalıştırır. İşçi bu sembolü sınırlı/iptal edilebilir bir sürümle DEĞİŞTİRİR.
# Köprünün üç sorumluluğu vardır ve üçü de ayrı ayrı gözden geçirilebilir
# olsun diye orkestratörden AYRI dosyadadır:
#
#   1) SEÇİLEN SORGU metadata'sını kullanmak. Yapılandırma sözleşmesi sorgu
#      metadata'sına EN YÜKSEK önceliği verir; sınırlar seçimden ÖNCE
#      dondurulursa ağır bir sorgunun kendi zaman aşımını yükseltmesi (veya
#      daha sıkı bir sonuç tavanı taşıması) sessizce yok sayılırdı.
#
#   2) SONUÇ ÖNBELLEĞİNİ standart (derin olmayan) yola da bağlamak. Önbellek
#      yalnızca derin yola bağlıyken `MERGEN_PK_CACHE_*` denetimleri sıradan
#      tekil analiz için ÖLÜDÜR.
#
#   3) TİPLİ SONUCU KAYBETMEMEK. Modül karakter dönüşü "kullanıcıya gösterilecek
#      metin" olarak yorumlar; bu yüzden gerçek `timeout`/`too_large` durumu
#      ayrı bir kutuya yazılır ve işçi sarmalayıcısı nihai durumu ondan üretir.
#
# SAFTIR: Shiny/reaktif YOKTUR. DB çağrıları yalnızca kendisine verilen
# bağlantı üzerinden yapılır.
# ==============================================================================

#' İşçi SQL köprüsü için tipli durum kutusu
#'
#' Modül sınırından geçerken tip bilgisi kaybolur; kutu ana sarmalayıcının
#' nihai durumu doğru raporlamasını sağlar.
pk_async_sql_status_box <- function() {
  kutu <- new.env(parent = emptyenv())
  kutu$status <- NA_character_
  kutu$reason <- NA_character_
  kutu
}

.pk_async_sql_note <- function(box, status, reason = NA_character_) {
  if (!is.environment(box)) return(invisible(FALSE))
  # İLK terminal durum korunur: sonraki bir çağrı onu EZMEZ.
  if (!is.na(box$status)) return(invisible(FALSE))
  box$status <- as.character(status)[1]
  box$reason <- as.character(reason)[1]
  invisible(TRUE)
}

#' Sınırlı/iptal edilebilir `execute_pk_sql_unicode()` yerine geçen köprü
#'
#' @param stage_gate Aşama kapısı (iptal + son tarih).
#' @param deadline_at Mutlak analiz son tarihi VEYA onu döndüren fonksiyon.
#'   Fonksiyon biçimi, sorgu SEÇİLDİKTEN sonra uygulanan per-query
#'   `analysis_deadline_sec` override'ının bu sınırlayıcıya da ULAŞMASI
#'   içindir; sabit değer geçmişe dönük uyumluluk için desteklenir.
#' @param status_box `pk_async_sql_status_box()` çıktısı.
#' @param defaults Seçim yapılamadığında kullanılacak yedek sınırlar.
#' @return `data.frame` (başarı) veya kullanıcıya görünen Türkçe metin.
pk_async_bounded_sql_executor <- function(stage_gate, deadline_at, status_box,
                                          defaults = list()) {
  function(conn, sql_text) {
    baglam <- pk_active_exec_context()
    meta <- if (is.list(baglam$query)) baglam$query$meta else NULL

    coz <- function(key, fallback) {
      if (!exists("pk_config_resolve", mode = "function", inherits = TRUE)) return(fallback)
      tryCatch(pk_config_resolve(key, meta), error = function(e) fallback)
    }

    anahtar <- ""
    if (is.list(baglam$query) && !is.null(baglam$rls_info) &&
        exists("pk_query_result_cache_key", mode = "function", inherits = TRUE)) {
      anahtar <- tryCatch(
        pk_query_result_cache_key(
          baglam$query, baglam$rls_info, sql_text,
          engine = as.character(baglam$engine %||% "")[1]
        ),
        error = function(e) ""
      )
    }

    tavan_mb <- coz("MERGEN_PK_MAX_RESULT_MB", defaults$max_result_mb %||% 512L)

    if (nzchar(anahtar) && exists("pk_cache_get", mode = "function", inherits = TRUE)) {
      isabet <- tryCatch(pk_cache_get(anahtar, query_meta = meta),
                         error = function(e) list(hit = FALSE))
      # İsabet HİÇBİR kapıyı atlamaz: iptal/son tarih ve güncel boyut tavanı
      # ıskadaki ile AYNI biçimde uygulanır (aşağıdaki kontroller).
      if (isTRUE(isabet$hit) && is.data.frame(isabet$value)) {
        kapi <- tryCatch(stage_gate(), error = function(e) NULL)
        if (is.list(kapi) && isTRUE(kapi$halt)) {
          durum <- as.character(kapi$status %||% "cancelled")[1]
          .pk_async_sql_note(status_box, durum)
          return(pk_async_halt_message(durum))
        }
        if (isTRUE(pk_cache_entry_within_limit(isabet$value, tavan_mb))) {
          return(isabet$value)
        }
        try(pk_cache_invalidate(anahtar), silent = TRUE)
      }
    }

    exec <- pk_sql_execute_bounded(
      conn, sql_text, unicode_param = TRUE,
      chunk_rows = coz("MERGEN_PK_FETCH_CHUNK_ROWS", defaults$chunk_rows %||% 5000L),
      max_result_mb = tavan_mb,
      stage_gate = stage_gate,
      timeout_sec = coz("MERGEN_PK_SQL_TIMEOUT_SEC", defaults$sql_timeout %||% 120L),
      deadline_at = if (is.function(deadline_at)) deadline_at() else deadline_at
    )

    if (identical(exec$status, "ok")) {
      if (nzchar(anahtar) && is.data.frame(exec$data) &&
          exists("pk_cache_put", mode = "function", inherits = TRUE)) {
        # Yazımdan HEMEN ÖNCE tekrar kapı: durdurulmuş bir istek yüzlerce MB'lık
        # bir yan etki bırakmamalıdır.
        kapi <- tryCatch(stage_gate(), error = function(e) NULL)
        if (!(is.list(kapi) && isTRUE(kapi$halt))) {
          try(pk_cache_put(anahtar, exec$data, query_meta = meta), silent = TRUE)
        }
      }
      return(exec$data)
    }

    .pk_async_sql_note(status_box, exec$status, exec$error)

    if (exec$status %in% c("cancelled", "deadline")) return(pk_async_halt_message(exec$status))
    if (identical(exec$status, "too_large")) {
      return(get0("PK_RESULT_TOO_LARGE_MESSAGE", inherits = TRUE,
                  ifnotfound = "\U0001F50D **Sonuç Kümesi Çok Büyük:** Lütfen sorunuzu daraltın."))
    }
    if (identical(exec$status, "timeout")) return(PK_SQL_TIMEOUT_MESSAGE)

    stop(as.character(exec$error %||% "Sorgu calistirilamadi.")[1], call. = FALSE)
  }
}

# Kullanıcıya görünen SQL zaman aşımı mesajı. İptal ve son tarihten AYRIDIR:
# tek bir ifadenin zaman aşımına uğraması, tüm analiz bütçesinin dolmasıyla
# aynı şey değildir ve kullanıcıya farklı bir eylem önerir.
PK_SQL_TIMEOUT_MESSAGE <- paste0(
  "\U000023F1\U0000FE0F **Sorgu Zaman Aşımı:** Sorgu ayrılan sürede ",
  "tamamlanamadı. Lütfen sorunuzu daraltıp tekrar deneyin."
)
