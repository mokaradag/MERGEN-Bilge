# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_history.R
# Açıklama: Faz 5 (§5.2) — dönen geçmiş pencereleri için söyleşi kimliği.
# ==============================================================================

.pk_select_history_signatures <- function(chat_history) {
  if (!is.list(chat_history) || !length(chat_history)) return(character(0))

  imzalar <- vapply(chat_history, function(m) {
    if (!is.list(m)) return("")
    rol <- tolower(trimws(as.character(m$role %||% m$type %||% "user")[1]))
    icerik <- trimws(as.character(m$content %||% "")[1])
    if (is.na(icerik) || !nzchar(icerik)) return("")
    paste0(rol, "|", substr(icerik, 1L, 300L))
  }, character(1), USE.NAMES = FALSE)

  imzalar[!is.na(imzalar) & nzchar(imzalar)]
}

# Önceki pencerenin SONU ile yeni pencerenin BAŞI arasındaki en uzun sıralı
# örtüşmeyi bulur. Genel durumda tek bir ortak ileti söyleşi kimliği sayılmaz.
.pk_select_history_overlap <- function(previous, current) {
  onceki <- as.character(previous %||% character(0))
  simdiki <- as.character(current %||% character(0))
  ust <- min(length(onceki), length(simdiki))
  if (ust < 2L) return(0L)

  for (k in seq.int(ust, 2L, by = -1L)) {
    if (identical(utils::tail(onceki, k), utils::head(simdiki, k))) return(k)
  }
  0L
}

# İlk seçim çağrısı, sunucu ilk kullanıcı iletisini ekledikten hemen sonra
# çalışır; dolayısıyla saklanan ilk pencere yalnızca bir `user|...` imzası
# taşıyabilir. Bir sonraki çağrıda iki-iletilik örtüşme henüz mümkün değildir.
# Bu dar geçiş yalnızca TEK bir durum kaydıyla eşleşiyorsa kabul edilir; aynı
# ilk kullanıcı iletisine sahip birden fazla kayıt varsa belirsizlik nedeniyle
# yeni söyleşi anahtarı üretilir.
.pk_select_first_follow_up_match <- function(previous, current) {
  onceki <- as.character(previous %||% character(0))
  simdiki <- as.character(current %||% character(0))

  length(onceki) == 1L &&
    length(simdiki) >= 2L &&
    startsWith(onceki[1], "user|") &&
    identical(onceki[1], simdiki[1])
}

.pk_select_new_chat_key <- function(signatures, state) {
  taban <- substr(paste0("__chat__:", signatures[1]), 1L, 220L)
  if (!(taban %in% names(state))) return(taban)

  i <- 2L
  repeat {
    aday <- substr(paste0(taban, ":", i), 1L, 240L)
    if (!(aday %in% names(state))) return(aday)
    i <- i + 1L
  }
}

#' Söyleşi anahtarı — durum bu anahtarla İZOLE edilir
#'
#' Dönen son-N geçmiş pencereleri aynı söyleşi sayılır. Genel durumda bunun
#' için en az iki iletilik SIRALI suffix/prefix örtüşmesi gerekir. Yalnızca ilk
#' kullanıcı iletisinden sonraki ilk takip çağrısında, benzersiz tek-ileti
#' başlangıç eşleşmesi kabul edilir; böylece ilk netleştirme/önceki-sorgu durumu
#' korunurken genel tek-ileti çakışmaları söyleşileri birleştiremez.
pk_select_chat_key <- function(chat_history, session = NULL) {
  imzalar <- .pk_select_history_signatures(chat_history)
  if (!length(imzalar)) return("__yeni__")

  if (is.null(session)) return(substr(imzalar[1], 1L, 220L))

  durum <- .pk_select_state_read(session)
  eslesme <- character(0)
  eslesme_sayisi <- integer(0)
  ilk_takip <- character(0)

  for (anahtar in names(durum)) {
    kayit <- durum[[anahtar]]
    onceki <- if (is.list(kayit)) kayit$history_signatures else NULL
    ortak <- .pk_select_history_overlap(onceki, imzalar)
    if (ortak >= 2L) {
      eslesme <- c(eslesme, anahtar)
      eslesme_sayisi <- c(eslesme_sayisi, ortak)
    } else if (.pk_select_first_follow_up_match(onceki, imzalar)) {
      ilk_takip <- c(ilk_takip, anahtar)
    }
  }

  if (length(eslesme)) {
    en_iyi <- max(eslesme_sayisi)
    anahtar <- sort(eslesme[eslesme_sayisi == en_iyi], method = "radix")[1]
  } else if (length(ilk_takip) == 1L) {
    anahtar <- ilk_takip[1]
  } else {
    anahtar <- .pk_select_new_chat_key(imzalar, durum)
  }

  kayit <- if (is.list(durum[[anahtar]])) durum[[anahtar]] else list()
  kayit$history_signatures <- utils::tail(imzalar, .PK_SELECT_STATE_MAX_SIGNATURES)
  durum[[anahtar]] <- kayit
  .pk_select_state_write(session, durum)
  anahtar
}
