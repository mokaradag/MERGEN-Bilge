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

# BLOCK KİPİ METİNLERİ: EKRANA GİDEN ve SESLENDİRİLEN metni birlikte üretir.
#
# Köken doğrulaması (§5.11) desteklenmeyen sayısal iddia bulduğunda model
# düzyazısını deterministik yedekle DEĞİŞTİRİR. Doğrulama yalnızca akış
# tamamlandığında yapılırsa TTS motoru HAM `full_response` ile çoktan çağrılmış
# olur ve kullanıcı hiçbir zaman GÖSTERİLMEYEN sayıları DUYAR; söylenmiş sesi
# geri almak mümkün değildir. Bu yüzden doğrulama akıştan ve TTS'ten ÖNCE
# çalışır. Alt bilgi (kaynakça/ek) yalnızca ekrana gider: `pk_provenance_decorate()`
# metni `paste0(govde, alt_bilgi)` biçiminde ürettiği için sondaki alt bilgi
# seslendirmeden çıkarılır.
#
# `block` kipi etkin değilse metin DEĞİŞMEDEN döner (davranış korunur).
mergen_pk_block_mode_texts <- function(full_response, session, request_id = NULL) {
  varsayilan <- list(display = full_response, tts = full_response)

  if (!exists("pk_provenance_blocks_streaming", mode = "function", inherits = TRUE)) {
    return(varsayilan)
  }
  bloklu <- isTRUE(tryCatch(
    pk_provenance_blocks_streaming(session, request_id = request_id),
    error = function(e) FALSE
  ))
  if (!bloklu) return(varsayilan)

  bekleyen <- tryCatch(pk_provenance_peek(session, request_id = request_id),
                       error = function(e) NULL)
  alt_bilgi <- as.character(bekleyen$footer %||% "")[1]
  # BLOCK KİPİNDE DEKORASYON HATASI HAM METNİ TESLİM EDEMEZ.
  #
  # `block` kipi tam da DESTEKLENMEYEN sayısal iddiaların kullanıcı GÖRMEDEN
  # ve DUYMADAN önce değiştirilmesi için vardır. Eski yedek (`full_response`)
  # doğrulama hata verdiğinde kipin engellemek için var olduğu çıktının TA
  # KENDİSİNİ hem ekrana hem TTS'e gönderiyordu. Artık kapalı başarısız
  # davranılır: bekleyen kaydın deterministik yedeği varsa o, yoksa sabit bir
  # reddetme metni kullanılır.
  dekore <- tryCatch(
    pk_provenance_decorate(full_response, session, request_id = request_id),
    error = function(e) {
      cat(sprintf("[PK] Köken dekorasyonu başarısız (block kipi): %s\n",
                  conditionMessage(e)))
      yedek <- as.character(bekleyen$fallback_text %||% "")[1]
      if (!is.na(yedek) && nzchar(yedek)) {
        paste0(yedek, if (!is.na(alt_bilgi)) alt_bilgi else "")
      } else {
        # TEK SAHİP: metin `helpers_pk_provenance.R` içindeki sabitten gelir.
        paste0(PK_PROVENANCE_BLOCK_REFUSAL_TR,
               if (!is.na(alt_bilgi)) alt_bilgi else "")
      }
    }
  )

  tts_metni <- if (!is.na(alt_bilgi) && nzchar(alt_bilgi) && endsWith(dekore, alt_bilgi)) {
    substr(dekore, 1L, nchar(dekore) - nchar(alt_bilgi))
  } else {
    dekore
  }

  list(display = dekore, tts = tts_metni)
}
