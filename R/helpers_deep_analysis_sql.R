# ==============================================================================
# Dosya Yolu: R/helpers_deep_analysis_sql.R
# Açıklama: Faz 6 (§5.10, D16) — Derin Düşünme yolunun KİMLİK ve SQL YÜRÜTME
#           uzlaştırması: ana yolun kimlik kapısı, ÖNCEDEN YÜKLENMİŞ SQL metni
#           ve Faz-6 sınırlarıyla (parça/bayt/son tarih) çalışan yürütme.
#
# `R/helpers_deep_analysis_reconcile.R` içinden BÖLÜNMÜŞTÜR: orası PAKET
# SEVİYESİ uzlaştırmadır (köken, çapraz-sorgu aritmetiği yasağı, karşılaştırma)
# ve 24-fonksiyon bakım tavanına dayanmıştı.
#
# Manifest sırası ZORUNLUDUR: bu dosya `helpers_deep_analysis_reconcile.R`'den
# ÖNCE yüklenir.
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
      # Çözümleyici atomik bir değer (FALSE, karakter) döndürebilir; `$`
      # atomik vektörde hata verir ve fail-closed kimlik mesajını yutardı.
      reason = if (is.list(durum)) as.character(durum$reason %||% "unknown")[1] else "unknown",
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
#' Eksik önyükleme artık kendiliğinden disk/UNC yeniden okumasına DÜŞMEZ.
#' `read_file_fn` yalnızca çevrimdışı/izole testlerin açıkça enjekte edebildiği
#' uyumluluk kancasıdır; üretim çağrıları bu argümanı vermez.
pk_deep_query_sql_text <- function(query, read_file_fn = NULL) {
  onyuklu <- tryCatch(as.character(query$sql %||% "")[1], error = function(e) "")
  if (!is.na(onyuklu) && nzchar(trimws(onyuklu))) {
    return(list(sql = pk_deep_normalize_sql_text(onyuklu), source = "preloaded"))
  }

  # Otomatik dosya okuyucu YOKTUR. Yalnızca çağıranın AÇIKÇA enjekte ettiği
  # test/uyumluluk okuyucusu kullanılabilir; böylece runtime fail-closed kalır.
  if (is.function(read_file_fn)) {
    dosya <- tryCatch(as.character(query$sql_file %||% "")[1], error = function(e) "")
    if (!is.na(dosya) && nzchar(dosya)) {
      metin <- tryCatch(as.character(read_file_fn(dosya))[1], error = function(e) "")
      if (!is.na(metin) && nzchar(trimws(metin))) {
        return(list(sql = pk_deep_normalize_sql_text(metin), source = "file"))
      }
    }
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

  kapi <- function() pk_async_stage_gate(cancel_token, deadline_at)
  tavan_mb <- coz("MERGEN_PK_MAX_RESULT_MB", 512L)

  onbellek_anahtari <- as.character(cache_key %||% "")[1]
  if (nzchar(onbellek_anahtari) &&
      exists("pk_cache_get", mode = "function", inherits = TRUE)) {
    isabet <- tryCatch(
      pk_cache_get(onbellek_anahtari, query_meta = query_meta),
      error = function(e) list(hit = FALSE)
    )
    if (isTRUE(isabet$hit) && is.data.frame(isabet$value)) {
      # İSABET HİÇBİR KAPIYI ATLAMAZ. İptal/son tarih ve GÜNCEL sonuç tavanı,
      # ıskadaki ile AYNI biçimde uygulanır: aksi hâlde durdurulmuş bir istek
      # önbellekten "başarı" ile çıkar ve sıkılaştırılmış bir bellek tavanı,
      # eski/gevşek tavan altında kabul edilmiş bir girişi geçiremezdi.
      erken <- kapi()
      if (isTRUE(erken$halt)) {
        return(list(status = erken$status, data = NULL, rows = 0L,
                    error = NA_character_, timeout_sec = 0L,
                    timeout_reason = "halted_before_cache_use",
                    timeout_mechanism = "none", cached = FALSE))
      }
      if (isTRUE(pk_cache_entry_within_limit(isabet$value, tavan_mb))) {
        return(list(
          status = "ok", data = isabet$value, rows = nrow(isabet$value),
          error = NA_character_, timeout_sec = 0L, timeout_reason = "cache_hit",
          timeout_mechanism = "none", cached = TRUE
        ))
      }
      try(pk_cache_invalidate(onbellek_anahtari), silent = TRUE)
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

  # NOT: burada AYRICA `pk_sql_apply_statement_timeout()` ÇAĞRILMAZ. O çağrı
  # sınırlanmamış bir `SET LOCK_TIMEOUT` gidiş-dönüşüydü ve bounded yürütücü
  # zaten AYNI ayarı (bu kez kalan bütçeyle sınırlı biçimde) uyguluyor. Çift
  # tur, bozulmuş bir DB/ağda Durdur ve son tarihten ÖNCE asılabiliyordu.
  sonuc <- pk_sql_execute_bounded(
    conn = conn,
    sql_text = sql_text,
    unicode_param = isTRUE(unicode_param),
    chunk_rows = coz("MERGEN_PK_FETCH_CHUNK_ROWS", 5000L),
    max_result_mb = tavan_mb,
    stage_gate = kapi,
    timeout_sec = plan$timeout_sec,
    deadline_at = deadline_at,
    # SEÇİLEN SORGUNUN METADATA'SI AÇIKÇA GEÇİRİLİR.
    #
    # Derin analiz per-query yürütme bağlamı kurmaz; sınırlı yürütücü
    # `pk_active_query_meta()` üzerinden örtük okuduğunda `NULL` alıyor ve
    # sorgu override'ları (yük çarpanı, onaylı LOB) ÖLÜ kalıyordu.
    query_meta = query_meta
  )

  if (identical(sonuc$status, "ok") && nzchar(onbellek_anahtari) &&
      is.data.frame(sonuc$data) &&
      exists("pk_cache_put", mode = "function", inherits = TRUE)) {
    # Yazımdan HEMEN ÖNCE tekrar kapı: yürütücünün son birleştirme aşaması
    # sırasında gelen bir Durdur, yüzlerce MB'lık kalıcı bir önbellek yan
    # etkisi bırakmamalıdır.
    yazim_kapisi <- kapi()
    if (!isTRUE(yazim_kapisi$halt)) {
      try(
        pk_cache_put(onbellek_anahtari, sonuc$data, query_meta = query_meta),
        silent = TRUE
      )
    }
  }

  list(
    status = sonuc$status,
    data = sonuc$data,
    rows = sonuc$rows,
    error = sonuc$error,
    timeout_sec = plan$timeout_sec,
    timeout_reason = plan$reason,
    # Gerçekte UYGULANAN mekanizma sınırlı yürütücüden gelir; ön kontrol
    # değeri (ör. `deferred_pool`) tanılamayı yanıltıyordu.
    timeout_mechanism = sonuc$timeout_mechanism %||% "none",
    cached = FALSE
  )
}