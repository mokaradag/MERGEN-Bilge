# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_marker_store.R
# Açıklama: PK asenkron istek işaretlerinin SÜREÇ-YEREL aynası.
#
#           NEDEN AYRI DOSYA: `R/helpers_pk_async_request_markers.R` OTURUM
#           kapsamlı işaret semantiğini (terk, jeton sahipliği, kapanış kancası)
#           tanımlar. Buradaki ayna ise `session$userData` yazımı doğrulanamadığı
#           durumda korumanın kaybolmamasını sağlayan AYRI bir sorumluluktur ve
#           sahip dosya bakım ratchet'i sınırındadır.
#
#           Dosya saftır: Shiny/DB/ağ bağımlılığı YOKTUR. Kaynak manifesti bu
#           dosyayı `helpers_pk_async_request_markers.R` dosyasından ÖNCE yükler.
# ==============================================================================

# ------------------------------------------------------------------------------
# SÜREÇ-YEREL GÜVENLİ TARAF AYNASI
# ------------------------------------------------------------------------------
.pk_request_marker_store <- new.env(parent = emptyenv())

# Ayna sınırlı tutulur: uzun ömürlü bir süreçte sınırsız büyümemeli.
#
# ANCAK SINIR YALNIZCA SABİTLENMEMİŞ girdilere uygulanır. 500'lük süreç geneli
# tavan, terminal geri çağrısına HENÜZ ULAŞMAMIŞ bir isteğin TEK terk işaretini
# de düşürebiliyordu — oysa bu ayna tam olarak `session$userData` yazımının
# başarısız olduğu durum için vardır. Yoğun bir süreçte yeterince yeni
# geçersizleme sonrası eski bir A -> B -> A işçisi ne `userData` işaretini ne
# de ayna işaretini bulur ve bayat sonucu YENİDEN uygulanabilir hâle gelirdi.

# ANAHTAR TEK ÖGELİ OLMALIDIR: `character(0)` girdisinde `if (is.na(key))`
# "argument is of length zero" ile PATLAR ve bu KORUMA katmanının kendisi
# istisna fırlatırdı; koruma sessizce devre dışı kalmalı, çökmemeli.
.pk_marker_key_ok <- function(key) length(key) == 1L && !is.na(key) && nzchar(key)

.pk_marker_note <- function(slot, key, pin = FALSE) {
  if (!.pk_marker_key_ok(key)) return(invisible(FALSE))
  mevcut <- .pk_request_marker_store[[slot]]
  if (!is.character(mevcut)) mevcut <- character(0)

  sabit <- .pk_request_marker_store$pinned
  if (!is.character(sabit)) sabit <- character(0)
  if (isTRUE(pin)) {
    sabit <- unique(c(sabit, key))
    .pk_request_marker_store$pinned <- sabit
  }

  tumu <- unique(c(mevcut, key))
  sabitli <- intersect(tumu, sabit)
  serbest <- utils::tail(setdiff(tumu, sabit), 500L)
  .pk_request_marker_store[[slot]] <- unique(c(sabitli, serbest))
  invisible(TRUE)
}

# İstek terminal duruma ulaştı: sabitleme kalkar, girdi normal tavana tabidir.
.pk_marker_unpin <- function(key) {
  if (!.pk_marker_key_ok(key)) return(invisible(FALSE))
  sabit <- .pk_request_marker_store$pinned
  if (!is.character(sabit)) return(invisible(FALSE))
  .pk_request_marker_store$pinned <- setdiff(sabit, key)
  invisible(TRUE)
}

.pk_marker_has <- function(slot, key) {
  if (!.pk_marker_key_ok(key)) return(FALSE)
  mevcut <- .pk_request_marker_store[[slot]]
  is.character(mevcut) && key %in% mevcut
}

#' Test/izolasyon için süreç-yerel aynayı sıfırla
pk_request_markers_reset <- function() {
  # HER YUVA temizlenir: `hooked` dışarıda kalınca jetonu testler arasında
  # tekrarlanan bir oturum ikizinde sızan işaret TRUE okunuyor ve
  # `session$onSessionEnded()` kurulumu fark edilmeden ATLANIYORDU. `closed` yuvası AYNI gerekçeyle temizlenir: sızan kapanış işareti sonraki testte oturumu KAPALI gösterirdi.
  for (yuva in c("abandoned", "revoked", "hooked", "closed", "pinned")) {
    .pk_request_marker_store[[yuva]] <- character(0)
  }
  invisible(TRUE)
}

