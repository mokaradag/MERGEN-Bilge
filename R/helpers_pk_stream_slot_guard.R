# ==============================================================================
# Dosya Yolu: R/helpers_pk_stream_slot_guard.R
# Açıklama: Canlı akışta ÇÖZÜLMEMİŞ olgu yuvası (`{{fact:...}}`) koruyucuları
#           (master plan §5.11).
#
#           Erteleme kararı yalnızca bekleyen köken kaydına dayanıyordu; v2
#           kaydı saklanamadığında (bayat istek, depo yok) ham yuva delta'ları
#           istemciye, düşünce paneline ve kalıcı düşünce arşivine gidiyordu.
#           Bu dosya yuva söz diziminin KENDİSİNE bakar: görünür metin ilk yuva
#           açıcısından itibaren tamponlanır, düşünce metni nötrlenerek
#           gönderilir. Tüketici: R/server_handler_true_streaming.R.
#
#           NEDEN AYRI DOSYA: `R/helpers_pk_provenance_peek.R` bakım ratchet'i
#           (fonksiyon yoğunluğu / büyük dosya) sınırındadır.
#           Dosya saftır: Shiny/DB/ağ bağımlılığı yoktur; nötrleyici
#           (`pk_fact_reference_neutralize`) çağrı anında çözülür.
# ==============================================================================

# Sonlandırma metni nötrler ama gönderilmiş delta geri alınamaz. Açıcı iki
# parçaya bölünebildiği için sondaki olası yarım açıcı (`{`, `{{fa`) bir sonraki
# parçaya kadar tutulur.
.PK_STREAM_SLOT_OPENER <- "\\{\\{[[:space:]]*fact[[:space:]]*:"
.PK_STREAM_PARTIAL_OPENER <- "\\{(\\{[[:space:]]*(f(a(c(t[[:space:]]*)?)?)?)?)?$"

#' Görünür yanıt metninin akış planı
#'
#' @return `list(defer = TRUE)` metinde yuva açıcısı varsa (kalan metin
#'   sonlandırmaya kadar tamponlanır); aksi hâlde `list(defer = FALSE,
#'   send_until = n)` — gönderilebilecek son karakter konumu.
mergen_pk_stream_visible_plan <- function(text) {
  metin <- suppressWarnings(as.character(text %||% "")[1])
  if (length(metin) != 1L || is.na(metin)) metin <- ""
  if (grepl(.PK_STREAM_SLOT_OPENER, metin, ignore.case = TRUE, perl = TRUE)) {
    return(list(defer = TRUE, send_until = 0L))
  }
  yarim <- regexpr(.PK_STREAM_PARTIAL_OPENER, metin, ignore.case = TRUE, perl = TRUE)
  list(defer = FALSE,
       send_until = if (yarim > 0L) as.integer(yarim) - 1L else nchar(metin))
}

#' Düşünce akışının yayımlanabilir yeni parçası (nötrlenmiş)
#'
#' Düşünce metni ertelenmez (canlı panel korunur); bunun yerine KAPANMAMIŞ `{{`
#' açıcısından itibaren tutulur, yalnızca tamamlanmış kısım nötrlenerek gönderilir.
#' `final = TRUE` kalan her şeyi yayımlar. 200 karakteri aşan kapanmamış açıcı
#' tutulmaz (nötrleyici onu bozuk yuva olarak ele alır).
#'
#' @return `list(delta = <nötr metin>, sent = <ham metinde gönderilen son konum>)`
mergen_pk_stream_reasoning_release <- function(raw_text, sent_chars = 0L, final = FALSE) {
  ham <- suppressWarnings(as.character(raw_text %||% "")[1])
  if (length(ham) != 1L || is.na(ham)) ham <- ""
  gonderilen <- max(0L, as.integer(sent_chars %||% 0L)[1])
  n <- nchar(ham)
  if (gonderilen >= n) return(list(delta = "", sent = gonderilen))

  son <- n
  if (!isTRUE(final)) {
    kalan <- substr(ham, gonderilen + 1L, n)
    acik <- gregexpr("\\{\\{", kalan, perl = TRUE)[[1]]
    for (konum in rev(as.integer(acik[acik > 0L]))) {
      sonrasi <- substr(kalan, konum, nchar(kalan))
      if (!grepl("}}", sonrasi, fixed = TRUE) && nchar(sonrasi) <= 200L) {
        son <- gonderilen + konum - 1L
      }
    }
    yarim <- regexpr("\\{$", substr(ham, gonderilen + 1L, son), perl = TRUE)
    if (yarim > 0L) son <- gonderilen + as.integer(yarim) - 1L
  }
  if (son <= gonderilen) return(list(delta = "", sent = gonderilen))

  list(delta = mergen_pk_neutral_text(substr(ham, gonderilen + 1L, son)), sent = son)
}

#' Ham yuva sözdizimini nötrler (yalnızca `fact` önekli biçimler; yardımcı
#' yüklenmemişse metin aynen döner). Kalıcı düşünce arşivi de bunu kullanır.
mergen_pk_neutral_text <- function(text) {
  if (!exists("pk_fact_reference_neutralize", mode = "function", inherits = TRUE)) return(text)
  pk_fact_reference_neutralize(text)
}

#' Gerçek akış işleyicisinin görünür metin adımı (`stream_env` durumunu günceller)
#'
#' @return Gönderilecek `list(delta=, text=)`; tampon aktifse ya da yayımlanacak
#'   yeni metin yoksa `NULL`.
mergen_pk_stream_visible_step <- function(stream_env) {
  metin <- stream_env$accumulated_text %||% ""
  plan <- mergen_pk_stream_visible_plan(metin)
  if (isTRUE(plan$defer)) stream_env$defer_visible_text <- TRUE
  if (isTRUE(stream_env$defer_visible_text)) return(NULL)
  bas <- as.integer(stream_env$visible_sent_chars %||% 0L)
  if (plan$send_until <= bas) return(NULL)
  stream_env$visible_sent_chars <- plan$send_until
  list(delta = substr(metin, bas + 1L, plan$send_until),
       text = substr(metin, 1L, plan$send_until))
}

#' Gerçek akış işleyicisinin düşünce adımı: nötrlenmiş yeni parça (yoksa "")
mergen_pk_stream_reasoning_step <- function(stream_env, final = FALSE) {
  r <- mergen_pk_stream_reasoning_release(stream_env$accumulated_reasoning,
                                          stream_env$reasoning_sent_chars %||% 0L, final)
  stream_env$reasoning_sent_chars <- r$sent
  r$delta
}
