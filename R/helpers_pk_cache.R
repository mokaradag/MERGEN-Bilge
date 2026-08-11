# ==============================================================================
# Dosya Yolu: R/helpers_pk_cache.R
# Açıklama: Faz 6 (§5.10) — BOYUT SINIRLI LRU sonuç önbelleği.
#
# Neden TTL tek başına yetmez: 300 saniyelik bir pencere, o pencerede üretilen
# HER büyük sonucun aynı anda yerleşik kalmasına izin verir. Yeterince farklı
# imza üzerinden bir tutam 50.000 satırlık frame, hiçbir şey süresi dolmadan
# işçinin belleğini tüketebilir. Bu yüzden üç sınır BİRLİKTE uygulanır:
#   - giriş sayısı tavanı  (MERGEN_PK_CACHE_MAX_ENTRIES)
#   - toplam bayt bütçesi  (MERGEN_PK_CACHE_MAX_MB)
#   - tek giriş tavanı     (MERGEN_PK_CACHE_MAX_ENTRY_MB)
#
# Tek giriş tavanını aşan bir sonuç, diğer HER ŞEYİ tahliye ederek kendine yer
# açmaz; HİÇ önbelleğe alınmaz.
#
# GÜVENLİK SINIRI — anahtar YETKİ KAPSAMINI İÇERİR. Bir kullanıcının sonucu,
# farklı RLS kapsamına sahip başka bir kullanıcıya ASLA yeniden kullandırılamaz.
# Bir önbellek ıskası kabul edilebilir; kullanıcılar arası sızıntı KABUL EDİLEMEZ.
#
# SQL sonucu (RLS ÖNCESİ frame) önbelleğe alınabilir, AMA yalnızca yetki
# imzasıyla ANAHTARLANMIŞ hâlde: farklı kapsam farklı anahtar demektir, dolayısıyla
# çapraz kullanıcı yeniden kullanımı yapısal olarak imkânsızdır. Bu, aynı ham
# veriyi kapsam başına tekrar saklamak anlamına gelir (bilinçli maliyet).
# KRİTİK: önbellek isabeti HİÇBİR KAPIYI ATLAMAZ — gerçek-sütun doğrulaması
# (metadata gate) ve RLS uygulaması isabetten SONRA da KOŞULSUZ çalışır.
#
# KAPSAM DÜRÜSTLÜĞÜ: önbellek SÜREÇ-YERELDİR. Her future işçisi ve ana süreç
# kendi deposunu taşır; bu bir dağıtık önbellek DEĞİLDİR. Bayt bütçeleri de bu
# yüzden süreç başınadır.
# ==============================================================================

.PK_CACHE_MB <- 1024 * 1024

# Süreç-yerel depo. `emptyenv()` ebeveyni bilinçlidir: depo global aramaya
# düşmez, dolayısıyla test/işçi bağlamında beklenmedik bir nesneyi yakalamaz.
.pk_cache_store <- new.env(parent = emptyenv())
.pk_cache_store$entries <- list()
.pk_cache_store$total_bytes <- 0
.pk_cache_store$clock <- 0
.pk_cache_store$stats <- list(hit = 0L, miss = 0L, expired = 0L,
                              rejected_oversize = 0L, evicted = 0L)

#' Önbelleği tamamen sıfırla (test ve oturum sonu temizliği)
pk_cache_reset <- function() {
  .pk_cache_store$entries <- list()
  .pk_cache_store$total_bytes <- 0
  .pk_cache_store$clock <- 0
  .pk_cache_store$stats <- list(hit = 0L, miss = 0L, expired = 0L,
                                rejected_oversize = 0L, evicted = 0L)
  invisible(TRUE)
}

.pk_cache_scalar <- function(x, default = "") {
  ham <- tryCatch(as.character(x)[1], error = function(e) NA_character_)
  if (is.null(ham) || length(ham) == 0L || is.na(ham)) return(default)
  ham
}

#' Önbellek anahtarı üret
#'
#' Sonucu etkileyebilen HER boyut anahtara girer. `rls_signature` yetki
#' kapsamının kararlı özetidir; onu dışarıda bırakmak kullanıcılar arası
#' sızıntı demektir. `query_version` ise sorgu tanımı/SQL değiştiğinde
#' deterministik geçersizleştirme sağlar.
#'
#' @return Tek elemanlı karakter anahtar.
pk_cache_key <- function(query_id, rls_signature, filter_signature,
                         query_version = "", engine = "", extra = NULL) {
  parcalar <- c(
    paste0("q=", .pk_cache_scalar(query_id, "?")),
    paste0("v=", .pk_cache_scalar(query_version)),
    paste0("e=", .pk_cache_scalar(engine)),
    # Yetki kapsamı: ASLA çıkarılmaz.
    paste0("r=", .pk_cache_scalar(rls_signature, "__no_scope__")),
    paste0("f=", .pk_cache_scalar(filter_signature))
  )

  if (!is.null(extra) && length(extra) > 0L) {
    adlar <- names(extra)
    if (is.null(adlar)) adlar <- paste0("x", seq_along(extra))
    sira <- order(adlar, method = "radix")
    for (i in sira) {
      parcalar <- c(parcalar, paste0(adlar[i], "=", .pk_cache_scalar(extra[[i]])))
    }
  }

  paste(parcalar, collapse = "|")
}

#' Yetki kapsamı imzası (RLS bilgisinden kararlı özet)
#'
#' Anahtara ham yetki listesi gömmek yerine kararlı bir özet kullanılır; imza
#' hem kısa hem de kapsam değiştiğinde kesin olarak değişir. Kullanıcı adı
#' TEK BAŞINA yeterli değildir: aynı kullanıcının yetkisi DB'de değişebilir.
pk_cache_rls_signature <- function(rls_info) {
  if (!is.list(rls_info)) return("__no_scope__")
  if (!isTRUE(rls_info$authorized)) return("__unauthorized__")

  alanlar <- setdiff(names(rls_info), c("conn", "connection", "session"))
  alanlar <- sort(alanlar, method = "radix")

  parcalar <- vapply(alanlar, function(ad) {
    deger <- rls_info[[ad]]
    if (is.function(deger) || is.environment(deger)) return(paste0(ad, "=<opaque>"))
    metin <- tryCatch(
      paste(as.character(unlist(deger, use.names = FALSE)), collapse = ","),
      error = function(e) "<unserializable>"
    )
    paste0(ad, "=", substr(metin, 1L, 2000L))
  }, character(1), USE.NAMES = FALSE)

  ham <- paste(parcalar, collapse = ";")
  if (requireNamespace("digest", quietly = TRUE)) {
    return(paste0("h:", digest::digest(ham, algo = "sha256")))
  }

  # digest yokken bile kapsam ayrımı KORUNUR: ham metin kısaltılarak kullanılır.
  paste0("t:", substr(ham, 1L, 4000L))
}

.pk_cache_object_bytes <- function(value) {
  bayt <- tryCatch(as.numeric(utils::object.size(value)), error = function(e) NA_real_)
  if (length(bayt) != 1L || is.na(bayt) || !is.finite(bayt) || bayt < 0) return(NA_real_)
  bayt
}

.pk_cache_limits <- function(query_meta = NULL) {
  coz <- function(key, fallback) {
    if (!exists("pk_config_resolve", mode = "function", inherits = TRUE)) return(fallback)
    tryCatch(pk_config_resolve(key, query_meta), error = function(e) fallback)
  }

  list(
    max_entries = as.numeric(coz("MERGEN_PK_CACHE_MAX_ENTRIES", 50L)),
    max_bytes = as.numeric(coz("MERGEN_PK_CACHE_MAX_MB", 512L)) * .PK_CACHE_MB,
    max_entry_bytes = as.numeric(coz("MERGEN_PK_CACHE_MAX_ENTRY_MB", 128L)) * .PK_CACHE_MB,
    ttl_sec = as.numeric(coz("MERGEN_PK_CACHE_TTL_SEC", 300L))
  )
}

# LRU tahliyesi: en KÜÇÜK `last_used` saatine sahip giriş ilk gider. Sayaç
# (Sys.time() değil) kullanılır; aynı saniye içinde birden çok erişimde
# zaman damgası ayırt etmez ve tahliye sırası belirsiz hâle gelirdi.
.pk_cache_evict_until <- function(limits, incoming_bytes = 0) {
  gerekli_bayt <- max(0, incoming_bytes)

  repeat {
    girisler <- .pk_cache_store$entries
    n <- length(girisler)
    if (n == 0L) break

    sayi_asim <- is.finite(limits$max_entries) && n >= limits$max_entries &&
      gerekli_bayt > 0
    bayt_asim <- is.finite(limits$max_bytes) &&
      (.pk_cache_store$total_bytes + gerekli_bayt) > limits$max_bytes

    if (!sayi_asim && !bayt_asim) break

    saatler <- vapply(girisler, function(g) as.numeric(g$last_used %||% 0), numeric(1))
    kurban <- names(girisler)[which.min(saatler)][1]
    if (is.na(kurban) || !nzchar(kurban)) break

    .pk_cache_store$total_bytes <- max(
      0, .pk_cache_store$total_bytes - as.numeric(girisler[[kurban]]$bytes %||% 0)
    )
    .pk_cache_store$entries[[kurban]] <- NULL
    .pk_cache_store$stats$evicted <- .pk_cache_store$stats$evicted + 1L
  }

  invisible(TRUE)
}

#' Önbellekten oku
#'
#' @return `list(hit = TRUE/FALSE, value = , reason = )`.
pk_cache_get <- function(key, query_meta = NULL, now = Sys.time()) {
  anahtar <- .pk_cache_scalar(key)
  if (!nzchar(anahtar)) {
    .pk_cache_store$stats$miss <- .pk_cache_store$stats$miss + 1L
    return(list(hit = FALSE, value = NULL, reason = "invalid_key"))
  }

  giris <- .pk_cache_store$entries[[anahtar]]
  if (!is.list(giris)) {
    .pk_cache_store$stats$miss <- .pk_cache_store$stats$miss + 1L
    return(list(hit = FALSE, value = NULL, reason = "miss"))
  }

  limitler <- .pk_cache_limits(query_meta)
  if (is.finite(limitler$ttl_sec) && limitler$ttl_sec >= 0) {
    yas <- suppressWarnings(as.numeric(difftime(now, giris$stored_at, units = "secs")))
    if (is.na(yas) || yas > limitler$ttl_sec) {
      .pk_cache_store$total_bytes <- max(
        0, .pk_cache_store$total_bytes - as.numeric(giris$bytes %||% 0)
      )
      .pk_cache_store$entries[[anahtar]] <- NULL
      .pk_cache_store$stats$expired <- .pk_cache_store$stats$expired + 1L
      .pk_cache_store$stats$miss <- .pk_cache_store$stats$miss + 1L
      return(list(hit = FALSE, value = NULL, reason = "expired"))
    }
  }

  .pk_cache_store$clock <- .pk_cache_store$clock + 1
  giris$last_used <- .pk_cache_store$clock
  .pk_cache_store$entries[[anahtar]] <- giris
  .pk_cache_store$stats$hit <- .pk_cache_store$stats$hit + 1L

  list(hit = TRUE, value = giris$value, reason = "hit")
}

#' Önbelleğe yaz
#'
#' @return `list(stored = TRUE/FALSE, bytes = , reason = )`.
pk_cache_put <- function(key, value, query_meta = NULL, now = Sys.time()) {
  anahtar <- .pk_cache_scalar(key)
  if (!nzchar(anahtar)) return(list(stored = FALSE, bytes = NA_real_, reason = "invalid_key"))

  limitler <- .pk_cache_limits(query_meta)

  # Önbellek kapatılmış (0 giriş veya 0 bayt): yazma YAPILMAZ.
  if (is.finite(limitler$max_entries) && limitler$max_entries < 1) {
    return(list(stored = FALSE, bytes = NA_real_, reason = "cache_disabled"))
  }
  if (is.finite(limitler$max_bytes) && limitler$max_bytes <= 0) {
    return(list(stored = FALSE, bytes = NA_real_, reason = "cache_disabled"))
  }

  bayt <- .pk_cache_object_bytes(value)
  if (is.na(bayt)) return(list(stored = FALSE, bytes = NA_real_, reason = "size_unknown"))

  # TEK giriş tavanı: aşan giriş HİÇ önbelleğe alınmaz. Yer açmak için mevcut
  # her şeyi tahliye etmek yasaktır.
  if (is.finite(limitler$max_entry_bytes) && bayt > limitler$max_entry_bytes) {
    .pk_cache_store$stats$rejected_oversize <-
      .pk_cache_store$stats$rejected_oversize + 1L
    return(list(stored = FALSE, bytes = bayt, reason = "entry_too_large"))
  }

  # Tek başına toplam bütçeyi aşıyorsa da alınmaz (tahliye kurtarmaz).
  if (is.finite(limitler$max_bytes) && bayt > limitler$max_bytes) {
    .pk_cache_store$stats$rejected_oversize <-
      .pk_cache_store$stats$rejected_oversize + 1L
    return(list(stored = FALSE, bytes = bayt, reason = "entry_too_large"))
  }

  # Aynı anahtar güncelleniyorsa ESKİ baytı önce muhasebeden düş; aksi hâlde
  # toplam sürüklenir ve bütçe anlamsızlaşır.
  mevcut <- .pk_cache_store$entries[[anahtar]]
  if (is.list(mevcut)) {
    .pk_cache_store$total_bytes <- max(
      0, .pk_cache_store$total_bytes - as.numeric(mevcut$bytes %||% 0)
    )
    .pk_cache_store$entries[[anahtar]] <- NULL
  }

  .pk_cache_evict_until(limitler, incoming_bytes = bayt)

  .pk_cache_store$clock <- .pk_cache_store$clock + 1
  .pk_cache_store$entries[[anahtar]] <- list(
    value = value,
    bytes = bayt,
    stored_at = now,
    last_used = .pk_cache_store$clock
  )
  .pk_cache_store$total_bytes <- .pk_cache_store$total_bytes + bayt

  list(stored = TRUE, bytes = bayt, reason = "stored")
}

#' Tek anahtarı geçersizleştir
pk_cache_invalidate <- function(key) {
  anahtar <- .pk_cache_scalar(key)
  giris <- .pk_cache_store$entries[[anahtar]]
  if (!is.list(giris)) return(invisible(FALSE))

  .pk_cache_store$total_bytes <- max(
    0, .pk_cache_store$total_bytes - as.numeric(giris$bytes %||% 0)
  )
  .pk_cache_store$entries[[anahtar]] <- NULL
  invisible(TRUE)
}

#' Önbellek durumu (SIR İÇERMEZ: yalnızca sayaç ve bayt)
#'
#' Anahtarlar sorgu kimliği ve yetki İMZASI taşır; imza karma olduğundan ham
#' yetki değeri raporlanmaz. Yine de anahtar METNİ dışa verilmez.
pk_cache_stats <- function() {
  list(
    entries = length(.pk_cache_store$entries),
    total_bytes = .pk_cache_store$total_bytes,
    total_mb = round(.pk_cache_store$total_bytes / .PK_CACHE_MB, 3),
    hit = .pk_cache_store$stats$hit,
    miss = .pk_cache_store$stats$miss,
    expired = .pk_cache_store$stats$expired,
    rejected_oversize = .pk_cache_store$stats$rejected_oversize,
    evicted = .pk_cache_store$stats$evicted
  )
}

#' LRU sırası (en eski -> en yeni). YALNIZCA test/tanılama içindir.
pk_cache_lru_order <- function() {
  girisler <- .pk_cache_store$entries
  if (length(girisler) == 0L) return(character(0))
  saatler <- vapply(girisler, function(g) as.numeric(g$last_used %||% 0), numeric(1))
  names(girisler)[order(saatler, method = "radix")]
}

#' Sorgu + yetki kapsamı + SQL metni için önbellek anahtarı üret
#'
#' Derin analiz ve tekil analiz yolunun SQL sonucunu paylaşabilmesi için tek
#' anahtar üreticisi. SQL METNİ de anahtara girer: sorgu kütüphanesi güncellenip
#' aynı kimlik farklı SQL taşımaya başladığında geçersizleştirme DETERMİNİSTİK
#' olur (sürüm alanına güvenmek yetmez).
#'
#' @return Anahtar metni; kimlik veya kapsam çözülemezse `""` (önbellek atlanır).
pk_query_result_cache_key <- function(query, rls_info, sql_text, engine = "") {
  kimlik <- .pk_cache_scalar(query$id, "")
  if (!nzchar(kimlik)) return("")

  kapsam <- pk_cache_rls_signature(rls_info)
  if (identical(kapsam, "__no_scope__") || identical(kapsam, "__unauthorized__")) {
    # Kapsam bilinmiyorsa/yetkisizse önbelleğe HİÇ girilmez: yanlış kapsamla
    # paylaşma riskini almaya değmez.
    return("")
  }

  metin <- .pk_cache_scalar(sql_text, "")
  if (!nzchar(metin)) return("")

  sql_imza <- if (requireNamespace("digest", quietly = TRUE)) {
    paste0("h:", digest::digest(metin, algo = "sha256"))
  } else {
    paste0("n:", nchar(metin))
  }

  pk_cache_key(
    query_id = kimlik,
    rls_signature = kapsam,
    filter_signature = "",
    query_version = sql_imza,
    engine = engine,
    extra = list(db = .pk_cache_scalar(query$db_target, "primary"))
  )
}
