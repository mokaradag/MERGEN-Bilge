# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_history.R
# Açıklama: Faz 5 (§5.2) — dönen geçmiş pencereleri için söyleşi kimliği.
# ==============================================================================

.pk_select_history_signatures <- function(chat_history) {
  if (!is.list(chat_history) || !length(chat_history)) return(character(0))

  imzalar <- vapply(chat_history, function(m) {
    if (!is.list(m)) return("")
    # ROL KANONİKLEŞTİRMESİ — SENKRON/ASENKRON AYNI İMZAYI ÜRETMELİDİR.
    #
    # Normal sohbet geçmişi yardımcı iletiyi `type = "ai"` (rolsüz) tutar;
    # asenkron anlık görüntü AYNI iletiyi `role = "assistant"` + `type = "ai"`
    # olarak taşır. Bu fonksiyon `role`u tercih ettiği için aynı söyleşi
    # yürütme kipine göre `ai|...` ya da `assistant|...` imzası üretiyor,
    # örtüşme denetimi başarısız oluyor ve önceki sorgu/açıklama bağlamı
    # kayboluyordu. Eşanlamlılar TEK kanonik role indirgenir.
    # `tolower()` YERELE DUYARLIDIR: Türkçe `LC_CTYPE` altında "AI" -> "aı"
    # (noktasız `ı`) olur, `switch()` "ai" dalını ıskalar ve imza `aı|...`
    # çıkar. Rol/tip birer MAKİNE BELİRTECİDİR; ASCII katlama doğru sözleşmedir.
    # `%||%` YALNIZCA `NULL` ATLAR: `role = NA` + `type = "ai"` durumunda
    # `ham_rol` `NA` kalıyor, `switch()` geçerli rol üretmiyor ve dıştaki
    # `vapply(..., character(1))` "values must be length 1" ile sorgu seçimini
    # KESİYORDU. Boş olmayan tekil değer sırayla `role` -> `type` -> `"user"`.
    .ilk_metin <- function(x) {
      v <- suppressWarnings(trimws(as.character(x)[1]))
      if (length(v) != 1L || is.na(v) || !nzchar(v)) NULL else v
    }
    ham_rol <- .ilk_metin(m$role) %||% .ilk_metin(m$type) %||% "user"
    ham_rol <- if (exists("pk_ascii_lower", mode = "function", inherits = TRUE)) {
      pk_ascii_lower(ham_rol)
    } else {
      chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", ham_rol)
    }
    rol <- switch(ham_rol,
      "ai" = "assistant", "assistant" = "assistant", "bot" = "assistant",
      "human" = "user", "user" = "user",
      ham_rol
    )
    icerik <- trimws(as.character(m$content %||% "")[1])
    if (is.na(icerik) || !nzchar(icerik)) return("")

    # Normal sohbet çalışma zamanında her ileti kalıcı/oturum-yerel benzersiz bir
    # kimlik taşır. Akış sırasında `id` geçici kalabilir; DB'ye yazıldıktan sonra
    # `db_id` kalıcı kimliği taşır ve kaydedilmiş söyleşi yeniden yüklendiğinde
    # `id` bu DB kimliğinden kurulur. Bu yüzden varsa `db_id` tercih edilmelidir;
    # aksi halde yeniden yükleme aynı ileti için farklı imza üretebilir.
    db_kimligi <- trimws(as.character(m$db_id %||% "")[1])
    if (is.na(db_kimligi)) db_kimligi <- ""
    gecici_kimlik <- trimws(as.character(m$id %||% "")[1])
    if (is.na(gecici_kimlik)) gecici_kimlik <- ""
    kimlik <- if (nzchar(db_kimligi)) db_kimligi else gecici_kimlik
    kimlik_parcasi <- if (nzchar(kimlik)) {
      paste0("id=", substr(kimlik, 1L, 120L), "|")
    } else {
      ""
    }

    paste0(rol, "|", kimlik_parcasi, substr(icerik, 1L, 300L))
  }, character(1), USE.NAMES = FALSE)

  imzalar[!is.na(imzalar) & nzchar(imzalar)]
}

# Önceki pencerenin SONU ile yeni pencerenin BAŞI arasındaki en uzun sıralı
# örtüşmeyi bulur. Genel durumda tek bir ortak metin söyleşi kimliği sayılmaz.
# Ancak dönen kısa pencereler yalnızca bir ortak ileti bırakabilir; bu durumda
# tek örtüşme ancak imza kararlı bir `id=` kimliği taşıyorsa kabul edilir.
.pk_select_history_overlap <- function(previous, current) {
  onceki <- as.character(previous %||% character(0))
  simdiki <- as.character(current %||% character(0))
  ust <- min(length(onceki), length(simdiki))
  if (ust < 1L) return(0L)

  for (k in seq.int(ust, 1L, by = -1L)) {
    if (!identical(utils::tail(onceki, k), utils::head(simdiki, k))) next
    if (k >= 2L) return(k)

    tek <- utils::tail(onceki, 1L)
    if (length(tek) == 1L &&
        grepl("^[^|]+\\|id=[^|]+\\|", tek, perl = TRUE)) {
      return(1L)
    }
  }
  0L
}

# İlk seçim çağrısı, sunucu ilk kullanıcı iletisini ekledikten hemen sonra
# çalışır; dolayısıyla saklanan ilk pencere yalnızca bir `user|...` imzası
# taşıyabilir. Bir sonraki çağrıda iki-iletilik örtüşme henüz mümkün değildir.
# Kimliksiz tek-ileti başlangıç eşleşmesi yalnızca hâlâ "ilk takip için uygun"
# işaretli kayıtlarla kabul edilir. Normal çalışma zamanında ileti kimliği varsa
# bu eşleşme zaten `.pk_select_history_overlap()` tarafından güvenle yakalanır.
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
#' için en az iki iletilik SIRALI suffix/prefix örtüşmesi gerekir; dönen pencere
#' yalnızca bir ortak ileti bıraktığında ise o imzanın kararlı `id=` kimliği
#' taşıması yeterlidir. İlk takipte kimliksiz tek ileti ayrıca kabul edilir;
#' birden çok aynı-açılış kaydı varsa seçim yapılmaz ve yeni durum açılır.
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
    if (ortak >= 1L) {
      eslesme <- c(eslesme, anahtar)
      eslesme_sayisi <- c(eslesme_sayisi, ortak)
    } else if (is.list(kayit) &&
               !identical(kayit$first_follow_up_eligible, FALSE) &&
               .pk_select_first_follow_up_match(onceki, imzalar)) {
      ilk_takip <- c(ilk_takip, anahtar)
    }
  }

  yeni_anahtar <- FALSE
  if (length(eslesme)) {
    en_iyi <- max(eslesme_sayisi)
    anahtar <- sort(eslesme[eslesme_sayisi == en_iyi], method = "radix")[1]
  } else if (length(ilk_takip) == 1L) {
    anahtar <- ilk_takip[1]
  } else {
    anahtar <- .pk_select_new_chat_key(imzalar, durum)
    yeni_anahtar <- TRUE
  }

  kayit <- if (is.list(durum[[anahtar]])) durum[[anahtar]] else list()
  kayit$history_signatures <- utils::tail(imzalar, .PK_SELECT_STATE_MAX_SIGNATURES)
  if (isTRUE(yeni_anahtar) && length(imzalar) == 1L) {
    kayit$first_follow_up_eligible <- TRUE
  } else if (length(imzalar) >= 2L) {
    kayit$first_follow_up_eligible <- FALSE
  }
  durum[[anahtar]] <- kayit
  # `touched` VERİLİR: `.pk_select_state_write()` bir anahtarı listenin SONUNA yalnızca `touched` ile taşır ve AYNI çağrıda `utils::tail(state, .PK_SELECT_STATE_MAX_CHATS)` ile budar. Kullanıcının İÇİNDE OLDUĞU söyleşinin kaydı `touched` olmadan yazıldığında tazelik yenilenmiyor; sonraki bir büyüme olayı tam da az önce kullanılan söyleşiyi tahliye edip imzalarını, hatırlanan sorgu kimliğini ve bekleyen teklifini DÜŞÜRÜYORDU.
  .pk_select_state_write(session, durum, touched = anahtar)
  anahtar
}
