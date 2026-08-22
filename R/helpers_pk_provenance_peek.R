# ==============================================================================
# Dosya Yolu: R/helpers_pk_provenance_peek.R
# Açıklama: Bekleyen köken kaydını TÜKETMEDEN inceleyen saf yardımcılar.
#
#           NEDEN AYRI DOSYA: `R/helpers_pk_provenance.R` bekleyen kaydı
#           SAKLAR / TÜKETİR / METNE İŞLER. Akış ve TTS hatları ise kaydı
#           tüketmeden yalnızca KİPİNİ öğrenmek zorundadır; `block` kipinde
#           doğrulama tamamlanma anında çalıştığı ve gerektiğinde model
#           düzyazısını deterministik yedekle DEĞİŞTİRDİĞİ için ham metni
#           göndermek geri alınamaz. Bu okuma-yalnızca sınır kendi dosyasında
#           tutulur; sahip dosya bakım ratchet'i (fonksiyon yoğunluğu) sınırında
#           olduğundan burada büyümek de doğru yerdir.
#
#           Dosya saftır: Shiny/reactive/DB/ağ bağımlılığı YOKTUR. Kaynak
#           manifesti bu dosyayı `helpers_pk_provenance.R` dosyasından SONRA
#           yükler (paylaşılan `.pk_provenance_store()` / yuva adları oradadır).
# ==============================================================================

#' Bekleyen kaydın kipini TÜKETMEDEN oku
#'
#' Akış hattı, doğrulamanın ERTELENDİĞİ `block` kipini metni istemciye
#' göndermeden ÖNCE bilmek zorundadır: `pk_provenance_decorate()` sayısal
#' iddiaları olgulara karşı doğrular ve gerektiğinde model düzyazısını
#' deterministik yedekle DEĞİŞTİRİR. Ham delta'lar çoktan gönderilmişse
#' kullanıcı doğrulanmamış sayıları GÖRMÜŞ (ya da TTS ile DUYMUŞ) olur ve bu
#' geri alınamaz. Bu yardımcı yuvayı TÜKETMEZ; yalnızca kipi bildirir.
#'
#' Sahiplik denetimi `pk_provenance_take()` ile AYNIDIR: kayıt bir isteğe
#' aitse, sahibini kanıtlamayan çağrı kipi de öğrenemez.
pk_provenance_peek <- function(session, request_id = NULL) {
  store <- .pk_provenance_store(session)
  if (!is.environment(store)) return(NULL)

  pending <- tryCatch(store[[.pk_provenance_slot]], error = function(e) NULL)
  if (is.null(pending) || !is.list(pending)) return(NULL)

  if (!is.null(pending$request_id) &&
      (is.null(request_id) ||
       !identical(as.character(request_id)[1], pending$request_id))) {
    return(NULL)
  }

  pending
}

pk_provenance_pending_mode <- function(session, request_id = NULL) {
  pending <- pk_provenance_peek(session, request_id = request_id)
  if (is.null(pending)) return(NA_character_)
  kip <- as.character(pending$mode %||% "")[1]
  if (is.na(kip) || !nzchar(kip)) NA_character_ else kip
}

#' `block` kipi bekliyor mu? (akış/TTS tamponlama kararı)
pk_provenance_blocks_streaming <- function(session, request_id = NULL) {
  identical(pk_provenance_pending_mode(session, request_id), "block")
}
