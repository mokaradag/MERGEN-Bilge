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


#' Bir önbellek değeri GÜNCEL sonuç tavanına sığıyor mu?
#'
#' Önbellek girişleri TTL boyunca (kalıcı işçilerde daha da uzun) yaşar. Operatör
#' `MERGEN_PK_MAX_RESULT_MB` değerini düşürdüğünde, eski ve daha gevşek tavan
#' altında kabul edilmiş bir giriş yeni sınırı ATLAYAMAMALIDIR.
pk_cache_entry_within_limit <- function(value, max_result_mb) {
  tavan <- suppressWarnings(as.numeric(max_result_mb)[1])
  if (length(tavan) != 1L || is.na(tavan) || !is.finite(tavan) || tavan <= 0) return(FALSE)

  bayt <- .pk_cache_object_bytes(value)
  if (is.na(bayt)) return(FALSE)
  bayt <= tavan * .PK_CACHE_MB
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

# Önbellek KAPALI sayılan yapılandırmalar. `ttl_sec == 0` da buradadır:
# `pk_cache_get()` yaşı sıfırdan büyük olan girişi hemen süresi dolmuş sayar,
# yani TTL=0 ile saklanan hiçbir şey yeniden kullanılamaz — ama saklama devam
# ederse işçi başına tüm bayt bütçesi boşuna tutulurdu.
.pk_cache_disabled <- function(limits) {
  if (is.finite(limits$max_entries) && limits$max_entries < 1) return(TRUE)
  if (is.finite(limits$max_bytes) && limits$max_bytes <= 0) return(TRUE)
  if (is.finite(limits$ttl_sec) && limits$ttl_sec <= 0) return(TRUE)
  FALSE
}

# Girişi düşür ve bayt muhasebesini DÜZELT. Muhasebe tek yerde yapılmazsa
# toplam sürüklenir ve bayt bütçesi anlamsızlaşır.
.pk_cache_drop_entry <- function(key, entry = NULL) {
  giris <- if (is.list(entry)) entry else .pk_cache_store$entries[[key]]
  if (!is.list(giris)) return(invisible(FALSE))
  .pk_cache_store$total_bytes <- max(
    0, .pk_cache_store$total_bytes - as.numeric(giris$bytes %||% 0)
  )
  .pk_cache_store$entries[[key]] <- NULL
  invisible(TRUE)
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

    .pk_cache_drop_entry(kurban, girisler[[kurban]])
    .pk_cache_store$stats$evicted <- .pk_cache_store$stats$evicted + 1L
  }

  invisible(TRUE)
}

# TÜM mağazayı GÜNCEL sınırlara göre uzlaştır.
#
# Sırasıyla: (1) süresi dolmuş girişler, (2) tek başına tavanı aşan girişler,
# (3) sayı/bayt bütçesi için LRU tahliyesi. `protect` yalnızca LRU adımında
# geçerlidir: çağıran o anda o girişi okumaktadır, ama süresi dolmuş veya tek
# başına çok büyük bir giriş KORUNMAZ.
.pk_cache_reconcile <- function(limits, now = Sys.time(), protect = NULL) {
  girisler <- .pk_cache_store$entries
  if (!length(girisler)) return(invisible(FALSE))

  korunan_anahtar <- as.character(protect %||% "")[1]

  for (ad in names(girisler)) {
    giris <- girisler[[ad]]
    if (!is.list(giris)) next
    # Çağıranın okuduğu giriş YUKARIDA ayrıca doğrulandı; burada TEKRAR
    # değerlendirmek `expired` sayacını iki kez artırırdı.
    if (nzchar(korunan_anahtar) && identical(ad, korunan_anahtar)) next

    if (is.finite(limits$ttl_sec) && limits$ttl_sec >= 0) {
      yas <- suppressWarnings(as.numeric(difftime(now, giris$stored_at, units = "secs")))
      if (is.na(yas) || yas > limits$ttl_sec) {
        .pk_cache_drop_entry(ad, giris)
        .pk_cache_store$stats$expired <- .pk_cache_store$stats$expired + 1L
        next
      }
    }

    bayt <- as.numeric(giris$bytes %||% NA_real_)
    if (is.finite(limits$max_entry_bytes) && !is.na(bayt) && bayt > limits$max_entry_bytes) {
      .pk_cache_drop_entry(ad, giris)
      .pk_cache_store$stats$evicted <- .pk_cache_store$stats$evicted + 1L
    }
  }

  # Sayı/bayt bütçesi: en eski kullanılan giriş ilk gider.
  korunan <- korunan_anahtar
  repeat {
    girisler <- .pk_cache_store$entries
    n <- length(girisler)
    if (n == 0L) break

    sayi_asim <- is.finite(limits$max_entries) && n > limits$max_entries
    bayt_asim <- is.finite(limits$max_bytes) &&
      .pk_cache_store$total_bytes > limits$max_bytes
    if (!sayi_asim && !bayt_asim) break

    adaylar <- setdiff(names(girisler), korunan)
    if (!length(adaylar)) break

    saatler <- vapply(girisler[adaylar], function(g) as.numeric(g$last_used %||% 0), numeric(1))
    kurban <- adaylar[which.min(saatler)][1]
    if (is.na(kurban) || !nzchar(kurban)) break

    .pk_cache_drop_entry(kurban, girisler[[kurban]])
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

  # SINIRLAR KAYIP ANAHTARDA DA UZLAŞTIRILIR.
  #
  # Eskiden eksik anahtar, `.pk_cache_limits()` ve `.pk_cache_reconcile()`
  # çalışmadan ÖNCE dönüyordu. Kalıcı bir işçide operatör önbelleği kapatır ya
  # da `MAX_ENTRIES`/`MAX_MB` değerini düşürür ve sonraki istekler hep YENİ
  # anahtarlar olursa, eski girişler süresiz yerleşik kalırdı: ne bu yol ne de
  # kapalı `pk_cache_put()` yolu onları temizliyordu. Dosyanın ilan ettiği
  # "sınırlar ANINDA etkilidir" davranışı böylece ihlal ediliyor ve her işçi
  # ÖNCEKİ bütçeyi taşımaya devam ediyordu.
  limitler <- .pk_cache_limits(query_meta)

  if (isTRUE(.pk_cache_disabled(limitler))) {
    for (ad in names(.pk_cache_store$entries)) .pk_cache_drop_entry(ad)
    .pk_cache_store$stats$miss <- .pk_cache_store$stats$miss + 1L
    return(list(hit = FALSE, value = NULL, reason = "cache_disabled"))
  }

  giris <- .pk_cache_store$entries[[anahtar]]
  if (!is.list(giris)) {
    .pk_cache_reconcile(limitler, now = now)
    .pk_cache_store$stats$miss <- .pk_cache_store$stats$miss + 1L
    return(list(hit = FALSE, value = NULL, reason = "miss"))
  }

  giris_bayt <- as.numeric(giris$bytes %||% NA_real_)
  if (is.finite(limitler$max_entry_bytes) && !is.na(giris_bayt) &&
      giris_bayt > limitler$max_entry_bytes) {
    .pk_cache_drop_entry(anahtar, giris)
    .pk_cache_store$stats$miss <- .pk_cache_store$stats$miss + 1L
    return(list(hit = FALSE, value = NULL, reason = "entry_over_current_limit"))
  }
  # GİRİŞ BAŞINA TAVAN ile TOPLAM BÜTÇE FARKLI SINIRLARDIR (PR #703 incelemesi).
  #
  # `max_entry_bytes = 128 MB`, mevcut giriş 120 MB iken operatör toplam
  # `max_bytes` değerini 100 MB'a indirirse giriş, giriş-başına denetimden
  # GEÇER; uzlaştırma diğer TÜM anahtarları tahliye eder ama korunan giriş
  # yüzünden toplam 120 MB'ta KALIR ve isabet yine servis edilirdi. Kendi başına
  # toplam bütçeyi aşan bir giriş DÜŞÜRÜLÜR; aksi hâlde salt-okuma iş yükünde
  # süreç `MERGEN_PK_CACHE_MAX_MB` üstünde SÜRESİZ kalırdı.
  if (is.finite(limitler$max_bytes) && !is.na(giris_bayt) &&
      giris_bayt > limitler$max_bytes) {
    .pk_cache_drop_entry(anahtar, giris)
    .pk_cache_store$stats$miss <- .pk_cache_store$stats$miss + 1L
    return(list(hit = FALSE, value = NULL, reason = "entry_over_total_budget"))
  }

  if (is.finite(limitler$ttl_sec) && limitler$ttl_sec >= 0) {
    yas <- suppressWarnings(as.numeric(difftime(now, giris$stored_at, units = "secs")))
    if (is.na(yas) || yas > limitler$ttl_sec) {
      .pk_cache_drop_entry(anahtar, giris)
      .pk_cache_store$stats$expired <- .pk_cache_store$stats$expired + 1L
      .pk_cache_store$stats$miss <- .pk_cache_store$stats$miss + 1L
      return(list(hit = FALSE, value = NULL, reason = "expired"))
    }
  }

  # SIKILAŞTIRILAN sayı/bayt bütçeleri de HEMEN etkili olmalıdır. Yalnızca
  # "önbellek tamamen kapalı" ve "bu giriş tek başına çok büyük" hâllerini ele
  # almak yetmez: kalıcı bir işçi 50 giriş / 500 MB tutarken operatör sınırları
  # 10 giriş / 100 MB'a indirirse, SALT-OKUMA iş yükünde hiçbir tahliye
  # tetiklenmez ve süreç yeni bütçenin ÇOK üstünde SÜRESİZ kalırdı.
  #
  # Bu giriş YUKARIDA zaten doğrulandı (süresi dolmamış, tek başına sığıyor);
  # uzlaştırma yalnızca DİĞER girişleri temizler.
  .pk_cache_reconcile(limitler, now = now, protect = anahtar)

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

  # Önbellek kapatılmış (0 giriş, 0 bayt veya 0 TTL): yazma YAPILMAZ.
  if (isTRUE(.pk_cache_disabled(limitler))) {
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
  .pk_cache_drop_entry(anahtar)

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
  .pk_cache_drop_entry(.pk_cache_scalar(key))
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

  # ÇARPIŞMAYA DAYANIKLI SQL İMZASI ZORUNLUDUR (PR #703 incelemesi).
  #
  # Eskiden `digest` yokken imza `nchar(sql_text)` idi. Anahtar aynı zamanda
  # BOŞ filtre imzası taşıdığından, aynı sorgu/kapsam/DB için AYNI KARAKTER
  # SAYISINA sahip İKİ FARKLI dinamik SQL ifadesi AYNI anahtara düşer ve ikinci
  # istek birincinin RLS ÖNCESİ çerçevesini yeniden kullanırdı. Uzunluk bir
  # imza değildir. `openssl` da kabul edilir (repoda başka yerlerde de yedek
  # olarak kullanılır); ikisi de yoksa ÖNBELLEK DEVRE DIŞI kalır (`""`).
  sql_imza <- if (requireNamespace("digest", quietly = TRUE)) {
    paste0("h:", digest::digest(metin, algo = "sha256"))
  } else if (requireNamespace("openssl", quietly = TRUE)) {
    paste0("h:", paste(as.character(openssl::sha256(charToRaw(enc2utf8(metin)))), collapse = ""))
  } else {
    return("")
  }

  pk_cache_key(
    query_id = kimlik,
    rls_signature = kapsam,
    filter_signature = "",
    query_version = sql_imza,
    engine = engine,
    # DB HEDEF KİMLİĞİ MANTIKSAL ADDAN İBARET DEĞİLDİR.
    #
    # Yalnızca `db_target` ("primary"/"secondary") anahtara girdiğinde,
    # desteklenen çalışma zamanı DSN değişimi/failover'ından SONRA aynı
    # sorgu/RLS/SQL üçlüsü ESKİ girdiye çarpıyor ve yeni bağlantı HİÇ
    # çalıştırılmadan ÖNCEKİ veritabanının satırları dönüyordu; ortamlar
    # TTL/tahliye olana kadar sessizce karışabiliyordu. Çözümlenmiş DSN adının
    # SIR OLMAYAN parmak izi de anahtara girer.
    extra = list(
      db = .pk_cache_scalar(query$db_target, "primary"),
      dsn = .pk_cache_db_fingerprint(query$db_target)
    )
  )
}

# Çözümlenmiş DSN adının sır olmayan kısa parmak izi.
#
# DSN ADI loglanmaz/dönmez; yalnızca sağlaması anahtara girer. DSN
# çözümlenemezse boş dize döner ve davranış eski hâliyle aynı kalır.
.pk_cache_db_fingerprint <- function(db_target) {
  hedef <- .pk_cache_scalar(db_target, "primary")
  degisken <- switch(hedef,
    "secondary" = "DB_DSN_2",
    "tertiary"  = "DB_DSN_3",
    "DB_DSN"
  )

  ad <- tryCatch(Sys.getenv(degisken, ""), error = function(e) "")
  if (!nzchar(ad)) return("")

  if (requireNamespace("openssl", quietly = TRUE)) {
    return(substr(paste(as.character(openssl::sha256(charToRaw(enc2utf8(ad)))),
                        collapse = ""), 1L, 16L))
  }
  # openssl yoksa anahtar yine de hedefe göre AYRIŞSIN diye uzunluk kullanılır;
  # DSN adının kendisi hiçbir koşulda anahtara yazılmaz.
  paste0("len", nchar(ad))
}
