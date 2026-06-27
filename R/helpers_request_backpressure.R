# ==============================================================================
# Dosya Yolu: R/helpers_request_backpressure.R
# Açıklama: Süreç-genelinde (per-process) PAHALI işlemler (sohbet/LLM) için
#           HAFİF, opsiyonel, varsayılan KAPALI bir kabul-denetimi (admission
#           control / backpressure) yardımcısı.
#
# Neden: Tek Shiny/httpuv süreci, aşırı yük altında çok sayıda eşzamanlı pahalı
# işlemi aynı anda yürütmeye çalışırsa event-loop tıkanır; yeni bağlantıları
# kabul etmek ve mevcut istekleri sonlandırmak gecikir (response_timeout /
# event-loop kuyruğu). Bu sınırlayıcı, eşzamanlı pahalı işlem sayısını üst-sınıra
# bağlar ve sınır aşıldığında isteği HIZLICA, dostça bir "sunucu yoğun, birazdan
# tekrar deneyin" durumuyla reddeder (uzun, gizli timeout yerine).
#
# Tasarım sözleşmesi (DAVRANIŞI VARSAYILAN OLARAK DEĞİŞTİRMEZ):
#   - Sınır 0 ise (VARSAYILAN) sınırlayıcı KAPALIDIR: her acquire başarılıdır;
#     mevcut runtime davranışı bayt-bayt korunur. Operatör yalnızca açıkça
#     MERGEN_MAX_CONCURRENT_LLM > 0 ayarlarsa kabul-denetimi devreye girer.
#   - KENDİ-İYİLEŞEN (self-healing): her slot bir zaman damgası taşır; TTL'den
#     (MERGEN_BACKPRESSURE_TTL_SECONDS, varsayılan 180 sn) eski slotlar bir
#     sonraki acquire'da otomatik geri toplanır. Böylece bir terminal yolda
#     release atlanırsa bile kapasite KALICI olarak azalmaz (sızdıran slot TTL
#     içinde temizlenir). Bu, akış (streaming) sonlandırmasının her yolunu
#     izlemek zorunda kalmadan güvenli wiring sağlar.
#   - release(token) IDEMPOTENT'tir: bilinmeyen/zaten-bırakılmış token no-op'tur
#     (çift-bırakma kapasiteyi bozmaz).
#   - stop/iptal'i BOZMAZ: reddedilen istek hiçbir durum değiştirmeden döner;
#     kabul edilen istek normal sonlandırma/iptal yollarında bırakılır.
#   - Saf yardımcılardır: source-time'da Shiny/ağ/DB erişimi yapmaz; `now`
#     enjekte edilebildiği için deterministik test edilebilir.
# ==============================================================================

# Kabul-denetimi çalışma-zamanı durumu (iç ortam; global'i kirletmez).
#   slots : token -> list(kind, ts)
#   stats : kind -> list(admitted, rejected, expired)
#   seq   : monotonik token sayacı
.mergen_backpressure_state <- new.env(parent = emptyenv())
.mergen_backpressure_state$slots <- list()
.mergen_backpressure_state$stats <- list()
.mergen_backpressure_state$seq <- 0L

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}

# Verilen `kind` için ortam değişkeni adını üretir (ASCII-güvenli, büyük harf).
.mergen_backpressure_env_name <- function(kind) {
  k <- toupper(gsub("[^A-Za-z0-9]", "_", as.character(kind)[1] %||% "llm"))
  paste0("MERGEN_MAX_CONCURRENT_", k)
}

# Eşzamanlı işlem üst sınırı. Ortam değişkeni > R option > varsayılan (0 = KAPALI).
# 0 veya negatif/geçersiz değerler "sınırsız (kapalı)" anlamına gelir.
mergen_backpressure_limit <- function(kind = "llm") {
  raw <- trimws(Sys.getenv(.mergen_backpressure_env_name(kind), unset = ""))
  if (!nzchar(raw)) {
    opt <- getOption(paste0("mergen.backpressure.", tolower(kind), "_limit"), NULL)
    raw <- if (is.null(opt)) "" else as.character(opt)[1]
  }
  val <- suppressWarnings(as.integer(raw))
  if (is.na(val) || val < 0L) return(0L)
  val
}

# Slot TTL'i (saniye). Kendi-iyileşme penceresi; akış işlemleri uzun sürebildiği
# için makul büyük tutulur. 0/geçersiz -> varsayılan 180.
mergen_backpressure_ttl_sec <- function() {
  raw <- trimws(Sys.getenv("MERGEN_BACKPRESSURE_TTL_SECONDS", unset = ""))
  val <- suppressWarnings(as.numeric(raw))
  if (!is.finite(val) || val <= 0) return(180)
  val
}

.mergen_backpressure_stat_bump <- function(kind, field, by = 1L) {
  st <- .mergen_backpressure_state
  cur <- st$stats[[kind]]
  if (is.null(cur)) cur <- list(admitted = 0L, rejected = 0L, expired = 0L)
  cur[[field]] <- (cur[[field]] %||% 0L) + as.integer(by)
  st$stats[[kind]] <- cur
  invisible(NULL)
}

# TTL'den eski slotları geri toplar (kendi-iyileşme). Geri toplanan slot sayısı
# döner.
.mergen_backpressure_reap <- function(now = as.numeric(Sys.time())) {
  st <- .mergen_backpressure_state
  if (length(st$slots) == 0L) return(0L)
  ttl <- mergen_backpressure_ttl_sec()
  expired <- 0L
  keep <- list()
  for (tok in names(st$slots)) {
    slot <- st$slots[[tok]]
    age <- now - (slot$ts %||% now)
    if (is.finite(age) && age > ttl) {
      .mergen_backpressure_stat_bump(slot$kind %||% "llm", "expired")
      expired <- expired + 1L
    } else {
      keep[[tok]] <- slot
    }
  }
  st$slots <- keep
  expired
}

# Belirli bir tür için o an aktif (canlı) slot sayısı (önce TTL reap çalışır).
mergen_backpressure_active <- function(kind = "llm", now = as.numeric(Sys.time())) {
  .mergen_backpressure_reap(now)
  st <- .mergen_backpressure_state
  if (length(st$slots) == 0L) return(0L)
  sum(vapply(st$slots, function(s) identical(s$kind, kind), logical(1)))
}

# Bir slot ödünç almayı dener.
# Dönüş listesi: acquired (TRUE/FALSE), token (acquired ise string), active, limit,
#                retry_after_sec (reddedildiyse öneri).
# Sınır 0 ise her zaman acquired=TRUE (sınırlayıcı kapalı); token yine de üretilir
# ki çağıran tek bir release sözleşmesi kullanabilsin (release no-op olur).
mergen_backpressure_try_acquire <- function(kind = "llm", now = as.numeric(Sys.time())) {
  limit <- mergen_backpressure_limit(kind)

  # Sınır 0 (VARSAYILAN) = sınırlayıcı KAPALI: hiç slot/istatistik tutmadan
  # anında kabul et. Böylece kapalıyken sıfır ek yük ve sıfır durum birikimi olur
  # (davranış bayt-bayt korunur). token = NULL -> sonraki release no-op.
  if (limit <= 0L) {
    return(list(acquired = TRUE, token = NULL, kind = kind,
                active = 0L, limit = 0L, retry_after_sec = 0L))
  }

  active <- mergen_backpressure_active(kind, now = now)

  if (active >= limit) {
    .mergen_backpressure_stat_bump(kind, "rejected")
    if (exists("mergen_runtime_metric_inc", mode = "function", inherits = TRUE)) {
      try(mergen_runtime_metric_inc(paste0("backpressure_reject_", kind)), silent = TRUE)
    }
    return(list(
      acquired = FALSE, token = NULL, kind = kind,
      active = active, limit = limit, retry_after_sec = 2L
    ))
  }

  st <- .mergen_backpressure_state
  st$seq <- st$seq + 1L
  token <- sprintf("%s-%d", kind, st$seq)
  st$slots[[token]] <- list(kind = kind, ts = now)
  .mergen_backpressure_stat_bump(kind, "admitted")

  if (exists("mergen_runtime_metric_inc", mode = "function", inherits = TRUE)) {
    try(mergen_runtime_metric_inc(paste0("backpressure_admit_", kind)), silent = TRUE)
  }
  if (exists("mergen_runtime_metric_set_gauge", mode = "function", inherits = TRUE)) {
    try(mergen_runtime_metric_set_gauge(paste0("backpressure_active_", kind), active + 1L), silent = TRUE)
  }

  list(
    acquired = TRUE, token = token, kind = kind,
    active = active + 1L, limit = limit, retry_after_sec = 0L
  )
}

# Bir slotu serbest bırakır. IDEMPOTENT: NULL/bilinmeyen/zaten-bırakılmış token
# no-op'tur.
mergen_backpressure_release <- function(token) {
  if (is.null(token)) return(invisible(FALSE))
  tok <- tryCatch(as.character(token)[1], error = function(e) NA_character_)
  if (is.na(tok) || !nzchar(tok)) return(invisible(FALSE))

  st <- .mergen_backpressure_state
  slot <- st$slots[[tok]]
  if (is.null(slot)) return(invisible(FALSE))

  st$slots[[tok]] <- NULL
  if (exists("mergen_runtime_metric_set_gauge", mode = "function", inherits = TRUE)) {
    kind <- slot$kind %||% "llm"
    try(mergen_runtime_metric_set_gauge(
      paste0("backpressure_active_", kind),
      mergen_backpressure_active(kind)
    ), silent = TRUE)
  }
  invisible(TRUE)
}

# Sır-güvenli anlık görüntü: tür başına aktif/limit + admitted/rejected/expired.
mergen_backpressure_snapshot <- function() {
  st <- .mergen_backpressure_state
  .mergen_backpressure_reap()
  kinds <- unique(c(names(st$stats), vapply(st$slots, function(s) s$kind %||% "llm", character(1))))
  kinds <- kinds[nzchar(kinds)]
  per_kind <- list()
  for (k in kinds) {
    stats <- st$stats[[k]] %||% list(admitted = 0L, rejected = 0L, expired = 0L)
    per_kind[[k]] <- list(
      active = mergen_backpressure_active(k),
      limit = mergen_backpressure_limit(k),
      admitted = stats$admitted %||% 0L,
      rejected = stats$rejected %||% 0L,
      expired = stats$expired %||% 0L
    )
  }
  list(
    ttl_sec = mergen_backpressure_ttl_sec(),
    kinds = per_kind,
    total_active_slots = length(st$slots)
  )
}

# Test/bakım: tüm slotları, istatistikleri ve token sayacını sıfırlar.
mergen_backpressure_reset <- function() {
  st <- .mergen_backpressure_state
  st$slots <- list()
  st$stats <- list()
  st$seq <- 0L
  invisible(NULL)
}
