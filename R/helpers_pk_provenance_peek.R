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
        # SABİT ÇÖZÜLEMEZSE HATA YAKALAYICISI DA DÜŞERDİ: kısmi dağıtımda `PK_PROVENANCE_BLOCK_REFUSAL_TR` bulunamaz, "object not found" `mergen_pk_block_mode_texts()` dışına kaçar ve çağıran `display`/`tts` çiftini HİÇ alamazdı. Aynı dosyadaki korumalı erişimci kullanılır.
        paste0(pk_block_mode_fallback_text(TRUE, ""),
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

# ==============================================================================
# DOĞRULANMIŞ METİNLER: EKRANA GİDEN ve SESLENDİRİLEN/TAKİBE GİDEN gövde
# ==============================================================================
#
# `mergen_pk_block_mode_texts()` yalnızca `block` kipini kapsar. TTS, takip
# önerisi ve akış hatları ise HER kipte doğrulanmış gövdeye ihtiyaç duyar:
# `warn` kipinde doğrulama desteklenmeyen sayıları GÖRÜNÜR biçimde işaretler ve
# dekorasyondan ÖNCEKİ metni seslendirmek/takibe vermek bu işaretleri atlar.
#
# KAPALI BAŞARISIZ SINIRI: dekorasyon hata verdiğinde ham düzyazı YALNIZCA
# doğrulanacak bekleyen bir köken kaydı YOKSA (yani PK dışı sıradan bir yanıt)
# korunur. Bekleyen kayıt varsa deterministik yedek ya da sabit reddetme metni
# kullanılır; `validated = FALSE` ile çağrana bildirilir (takip önerileri
# reddedilmiş düzyazıdan üretilmemelidir).
#
# `tts` alanı, ekranda kalan köken alt bilgisi ÇIKARILMIŞ gövdedir:
# `pk_provenance_decorate()` metni `paste0(govde, alt_bilgi)` biçiminde üretir.
mergen_pk_validated_texts <- function(text, session, request_id = NULL,
                                      block_mode = NULL) {
  metin <- suppressWarnings(as.character(text)[1])
  if (length(metin) != 1L || is.na(metin)) metin <- ""
  varsayilan <- list(display = metin, tts = metin, validated = TRUE)

  if (!exists("pk_provenance_decorate", mode = "function", inherits = TRUE)) {
    return(varsayilan)
  }

  # Bekleyen kayıt dekorasyondan ÖNCE okunur: `pk_provenance_decorate()` kaydı
  # TÜKETİR, sonrasında alt bilgi/yedek metin artık okunamaz.
  peek_hatasi <- FALSE
  bekleyen <- tryCatch(
    pk_provenance_peek(session, request_id = request_id),
    error = function(e) {
      peek_hatasi <<- TRUE
      NULL
    }
  )
  kayit_var <- is.list(bekleyen) || isTRUE(peek_hatasi)

  .skaler <- function(x) {
    v <- suppressWarnings(as.character(x)[1])
    if (length(v) != 1L || is.na(v)) "" else v
  }
  alt_bilgi <- if (is.list(bekleyen)) .skaler(bekleyen$footer) else ""

  bloklu <- if (is.null(block_mode)) {
    is.list(bekleyen) && identical(.skaler(bekleyen$mode), "block")
  } else {
    isTRUE(block_mode)
  }

  dekore <- tryCatch(
    pk_provenance_decorate(metin, session, request_id = request_id),
    error = function(e) {
      cat(sprintf("[PK] Köken dekorasyonu başarısız: %s\n", conditionMessage(e)[1]))
      NULL
    }
  )
  dekore_skaler <- if (is.null(dekore)) NA_character_ else suppressWarnings(as.character(dekore)[1])

  if (is.na(dekore_skaler)) {
    if (!kayit_var && !bloklu) {
      # PK dışı yanıt: doğrulanacak bir iddia yoktu, metin AYNEN korunur.
      return(varsayilan)
    }
    govde <- .skaler(if (is.list(bekleyen)) bekleyen$fallback_text else NULL)
    if (!nzchar(govde)) {
      govde <- if (exists("PK_PROVENANCE_BLOCK_REFUSAL_TR", inherits = TRUE)) {
        get("PK_PROVENANCE_BLOCK_REFUSAL_TR", inherits = TRUE)
      } else {
        metin
      }
    }
    return(list(display = paste0(govde, alt_bilgi), tts = govde, validated = FALSE))
  }

  govde <- if (nzchar(alt_bilgi) && endsWith(dekore_skaler, alt_bilgi)) {
    substr(dekore_skaler, 1L, nchar(dekore_skaler) - nchar(alt_bilgi))
  } else {
    dekore_skaler
  }
  list(display = dekore_skaler, tts = govde, validated = TRUE)
}

# AKIŞ SONU SARMALAYICISI.
#
# `handle_true_streaming_mode()` sonlandırıcısı bakım ratchet'i sınırındadır;
# şekil doğrulaması ve yedekler bu yüzden burada toplanır. Sözleşme: DÖNÜŞ
# HER ZAMAN tek ögeli `display`/`tts` ve mantıksal `validated` taşır.
#
# `mergen_pk_validated_texts()` YOKSA (izole test bağlamı) metin AYNEN döner ve
# `validated = TRUE` kalır: doğrulanacak bir hat kurulmamıştır. Yardımcı HATA
# verirse KAPALI BAŞARISIZ davranılır (`validated = FALSE`), böylece takip
# önerileri doğrulanmamış düzyazıdan üretilmez.
mergen_pk_stream_validated_text <- function(final_text, session, request_id,
                                            block_mode = FALSE) {
  yedek <- function(dogrulandi) {
    metin <- suppressWarnings(as.character(final_text)[1])
    if (length(metin) != 1L || is.na(metin)) metin <- ""
    list(display = metin, tts = metin, validated = isTRUE(dogrulandi))
  }

  if (!exists("mergen_pk_validated_texts", mode = "function", inherits = TRUE)) {
    return(yedek(TRUE))
  }

  sonuc <- tryCatch(
    mergen_pk_validated_texts(final_text, session, request_id = request_id,
                              block_mode = isTRUE(block_mode)),
    error = function(e) {
      cat(sprintf("[PK] Akış sonunda köken doğrulaması başarısız: %s\n",
                  conditionMessage(e)[1]))
      NULL
    }
  )
  if (!is.list(sonuc)) return(yedek(FALSE))

  gosterim <- suppressWarnings(as.character(sonuc$display)[1])
  if (length(gosterim) != 1L || is.na(gosterim)) return(yedek(FALSE))
  seslendirme <- suppressWarnings(as.character(sonuc$tts)[1])
  if (length(seslendirme) != 1L || is.na(seslendirme)) seslendirme <- gosterim

  list(display = gosterim, tts = seslendirme, validated = isTRUE(sonuc$validated))
}


# BENZETİLMİŞ AKIŞ SONLANDIRMASI İÇİN EKRANA GİDECEK METİN.
#
# `chat_simulate_streaming()` sonlandırıcısı bakım ratchet'i sınırındadır;
# kapalı başarısız karar bu yüzden burada toplanır. Sözleşme: DÖNÜŞ HER ZAMAN
# tek ögeli karakterdir. Doğrulama/dekorasyon düşerse HAM model metni
# yayımlanmaz; `mergen_pk_stream_validated_text()` bekleyen köken kaydı varken
# deterministik yedeği ya da sabit reddetme metnini döndürür.
pk_stream_display_text <- function(final_text, session, request_id,
                                   block_mode = FALSE) {
  metin <- suppressWarnings(as.character(final_text)[1])
  if (length(metin) != 1L || is.na(metin)) return(final_text)

  if (!exists("mergen_pk_stream_validated_text", mode = "function", inherits = TRUE)) {
    return(final_text)
  }

  sonuc <- try(mergen_pk_stream_validated_text(
    final_text, session, request_id = request_id, block_mode = isTRUE(block_mode)
  ), silent = TRUE)
  if (!is.list(sonuc)) return(final_text)

  gosterim <- suppressWarnings(as.character(sonuc$display)[1])
  if (length(gosterim) != 1L || is.na(gosterim) || !nzchar(gosterim)) return(final_text)
  gosterim
}

#' `block` kipinde HAM DUZYAZI YERINE gosterilecek deterministik yedek metin
#'
#' `block` kipi, dogrulanmamis duzyazinin kullaniciya GITMEMESI icin vardir.
#' Yedek metin normalde `PK_PROVENANCE_BLOCK_REFUSAL_TR` sabitinden gelir.
#' Sabit COZULEMEZSE (kismi dagitim, koken dosyasi manifestte yok) eski davranis
#' `full_response` degerine dusuyordu: kip TAM DA devreye girmesi gereken anda
#' ACIK BASARISIZ oluyor ve engellemesi gereken metni hem ekrana hem TTS'e
#' gonderiyordu. Soylenmis ses geri alinamaz; bu yuzden burada literal,
#' deterministik bir reddetme metni dondurulur.
#'
#' @param block_active `block` kipi etkin mi (mantiksal skaler).
#' @param raw_text Kip etkin DEGILSE dondurulecek ham metin.
#' @return Tek ogeli karakter.
pk_block_mode_fallback_text <- function(block_active, raw_text) {
  if (!isTRUE(block_active)) return(raw_text)

  if (exists("PK_PROVENANCE_BLOCK_REFUSAL_TR", inherits = TRUE)) {
    sabit <- suppressWarnings(as.character(
      get("PK_PROVENANCE_BLOCK_REFUSAL_TR", inherits = TRUE)
    )[1])
    if (length(sabit) == 1L && !is.na(sabit) && nzchar(sabit)) return(sabit)
  }

  paste0("\U000026A0\U0000FE0F **Yan\u0131t Do\u011frulanamad\u0131:** ",
         "Say\u0131sal k\u00f6ken do\u011frulamas\u0131 tamamlanamad\u0131\u011f\u0131 ",
         "i\u00e7in yan\u0131t g\u00f6sterilemiyor.")
}

#' Bayat akis geri cagrisi PAYLASILAN sohbet durumunu sifirlayabilir mi?
#'
#' Gecikmeli TTS/akis geri cagrisi cozuldugunde kullanici baska bir sohbete
#' gecmis olabilir. O anda `values` ARTIK YENI sohbetin paylasilan
#' `reactiveValues` nesnesidir; kosulsuz `chat_reset_state()` cagrisi surmekte
#' olan YENI istegin yazma animasyonunu kaldirir ve `is_sending` bayragini
#' temizler (gonder dugmesi yaniltici sekilde serbest kalir).
#'
#' Sozlesme: durumun sahibi DAHA YENI bir istekse hicbir seye dokunulmaz.
#' Etkin istek yoksa veya halen bayat istegin kendisiyse, UI'nin kilitli
#' kalmamasi icin sifirlamaya izin verilir.
#'
#' Etkin istek kimligi BURADA okunur: cagiran tarafta `tryCatch(...)` sarmalayici
#' bir isimsiz fonksiyon gerektirir ve o dosya fonksiyon yogunlugu ratchet'i
#' sinirindadir.
#'
#' @param session Shiny oturumu (etkin istek kimligi buradan okunur).
#' @param captured_request_id Geri cagriyi olusturan istegin kimligi.
#' @return `TRUE` ise sifirlama guvenlidir.
pk_stale_callback_may_reset <- function(session, captured_request_id) {
  current_request_id <- tryCatch(
    pk_provenance_current_request_id(session),
    error = function(e) NULL
  )

  guncel <- suppressWarnings(as.character(current_request_id %||% "")[1])
  if (length(guncel) != 1L || is.na(guncel) || !nzchar(guncel)) return(TRUE)

  yakalanan <- suppressWarnings(as.character(captured_request_id %||% "")[1])
  if (length(yakalanan) != 1L || is.na(yakalanan) || !nzchar(yakalanan)) return(FALSE)

  identical(guncel, yakalanan)
}
