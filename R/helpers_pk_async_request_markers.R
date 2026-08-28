# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_request_markers.R
# Açıklama: Faz 6 (§5.10) — OTURUM ÜZERİNDEKİ İSTEK İŞARETLERİ: açıkça terk
#           edilmiş istek kimlikleri ve iptal jetonu SAHİPLİĞİ.
#
# `R/helpers_pk_async_session_registry.R` içinden BÖLÜNMÜŞTÜR: orası AKTİF
# istek defteri ve oturum-sonu kancasıdır ve 24-fonksiyon bakım tavanına
# dayanmıştı. Bu iki işaret kümesi defterin YAŞAM DÖNGÜSÜNE değil, tek tek
# İSTEKLERİN durumuna aittir.
#
# YAZIM DOĞRULAMA SÖZLEŞMESİ (PR #703 incelemesi): `session$userData` yazımları
# SESSİZCE yutulabilir (salt-okunur/sahte uygulamalar, yıkılmakta olan oturum).
# Bir işaret fonksiyonu, ANLAMINI VEREN durum mutasyonu kalıcı olmadığı hâlde
# `TRUE` DÖNDÜREMEZ. Bu yüzden her yazım `pk_session_state_write()` üzerinden
# GERİ OKUNARAK doğrulanır.
#
# GÜVENLİ TARAF (fail-safe) AYNASI: "terk edildi" ve "sahiplik geri alındı"
# işaretleri SÜREÇ-YERELDİR de tutulur. Bu iki işaretin YÖNÜ güvenlidir —
# yanlışlıkla "terk edildi" demek yalnızca bayat bir sonucu atar, yanlışlıkla
# "sahip değil" demek yalnızca gereksiz bir `.flag` yazılmasını ENGELLER.
# Geri çağrılar ve Durdur gözlemcisi AYNI ana süreçte çalıştığı için bu ayna
# `userData` yazılamadığında da doğru kararı garanti eder.
#
# Shiny `session$userData` üzerine yazar; REAKTİF okuma YAPMAZ.
# ==============================================================================

# ------------------------------------------------------------------------------
# DOĞRULANMIŞ OTURUM DURUMU YAZIMI
# ------------------------------------------------------------------------------

#' `session$userData[[key]]` değerini yaz ve GERİ OKUYARAK doğrula
#'
#' @return `TRUE` yalnızca yazım kalıcı olduysa; aksi hâlde `FALSE`.
pk_session_state_write <- function(session, key, value) {
  ud <- try(session$userData, silent = TRUE)
  if (inherits(ud, "try-error") || is.null(ud)) return(FALSE)
  anahtar <- .pk_marker_id(key)
  if (is.na(anahtar)) return(FALSE)

  yazildi <- try({ ud[[anahtar]] <- value; TRUE }, silent = TRUE)
  if (!identical(yazildi, TRUE)) return(FALSE)

  geri <- try(ud[[anahtar]], silent = TRUE)
  if (inherits(geri, "try-error")) return(FALSE)
  isTRUE(all.equal(geri, value))
}

# Tekrarlanan küçük dönüşümler TEK yerde tutulur: her çağrı yerinde ayrı bir
# `tryCatch(..., error = function(e) ...)` kapanışı tanımlamak bakım oranı
# fonksiyon bütçesini gereksizce tüketiyordu.
.pk_marker_id <- function(x) {
  ham <- try(as.character(x)[1], silent = TRUE)
  if (inherits(ham, "try-error") || is.null(ham) || length(ham) == 0L) return(NA_character_)
  if (is.na(ham) || !nzchar(ham)) return(NA_character_)
  ham
}

# `session$userData[[key]]` güvenli okuma (okunamıyorsa `NULL`).
.pk_marker_read <- function(session, key) {
  deger <- try(session$userData[[key]], silent = TRUE)
  if (inherits(deger, "try-error")) return(NULL)
  deger
}

.pk_request_marker_store$abandoned <- character(0)
.pk_request_marker_store$revoked <- character(0)
.pk_request_marker_store$closed <- character(0)  # oturum KAPANDI arıza-güvenli aynası

# Oturum jetonu + istek kimliği. Jeton okunamazsa istek kimliği tek başına
# kullanılır (kimlikler süreç içinde pratikte benzersizdir, her iki işaretin yönü de güvenlidir).
.pk_marker_key <- function(session, request_id) {
  kimlik <- .pk_marker_id(request_id)
  if (is.na(kimlik)) return(NA_character_)
  paste0(.pk_marker_session_id(session), "|", kimlik)
}

# OTURUM KİMLİĞİ. Önce `session$token`: Shiny bunu oturum başına benzersiz üretir
# ve oturum ömrü boyunca KARARLIDIR. Jetonsuz oturumlar (testler, işçi vekilleri)
# için `userData` içine BİR KEZ rastgele kimlik yazılır; böylece jetonsuz iki
# oturum AYNI boş anahtarı paylaşmaz. `format(userData)` ARTIK KULLANILMAZ:
# ortam adresi yalnızca nesne yaşarken benzersizdir ve yeniden kullanıldığında
# ölü bir oturumun işareti yeni oturuma sızabilir; adlandırılmış ortamlarda ise
# adres hiç yer almaz ve kimlik SABİTLEŞİR.
.PK_MARKER_SESSION_KEY <- "pk_marker_session_id"

.pk_marker_session_id <- function(session) {
  # `try()` HATA NESNESİ KİMLİK DEĞİLDİR: `try-error` hata METNİNİ taşıyan bir
  # dizedir, `nzchar()` TRUE döner ve metin geçerli jeton sanılırdı. `token`
  # erişimi hata veren HER vekil o zaman AYNI kimliği paylaşır ve
  # `.pk_session_hook_installed()` sonraki oturumda ÖNCEKİNİN işaretini görüp
  # `onSessionEnded` temizliğini hiç kurmazdı.
  ham_jeton <- try(session$token, silent = TRUE)
  jeton <- if (inherits(ham_jeton, "try-error")) NA_character_ else .pk_marker_id(ham_jeton)
  if (!is.na(jeton) && nzchar(jeton)) return(jeton)
  ud <- try(session$userData, silent = TRUE)
  if (inherits(ud, "try-error") || !is.environment(ud)) return("")
  # `session$token` ile AYNI gerekçe: başarısız `userData` okuması KİMLİK
  # DEĞİLDİR. `try-error` hata METNİNİ taşır, `nzchar()` TRUE döner ve aynı
  # okuma hatasını yaşayan İKİ vekil AYNI işaret alanını paylaşırdı; biri
  # diğerinin `onSessionEnded` temizliğini bastırabilirdi.
  ham_mevcut <- try(ud[[.PK_MARKER_SESSION_KEY]], silent = TRUE)
  mevcut <- if (inherits(ham_mevcut, "try-error")) NA_character_ else .pk_marker_id(ham_mevcut)
  if (!is.na(mevcut) && nzchar(mevcut)) return(mevcut)
  yeni <- paste0("pk-oturum-",
                 paste(format(as.hexmode(sample.int(2147483647L, 4L))), collapse = ""))
  try({ ud[[.PK_MARKER_SESSION_KEY]] <- yeni }, silent = TRUE)  # YAZ-SONRA-OKU: doğrulanmamış yazım kimlik SAYILMAZ
  if (identical(.pk_marker_id(try(ud[[.PK_MARKER_SESSION_KEY]], silent = TRUE)), yeni)) yeni else ""
}

# ------------------------------------------------------------------------------
# TERK EDİLMİŞ İSTEK KİMLİKLERİ
# ------------------------------------------------------------------------------
# Terk edilmiş istek kimlikleri (sonuçları ARTIK uygulanamaz).
#
# Bu işaret, A -> B -> A gezinmesinde AÇIKÇA terk edilmiş bir işçinin sonucunun
# diriltilmesini engelleyen tek korumadır: kimlik ve sohbet kimliği yeniden
# eşleşebilir. `userData` yazımı doğrulanamazsa süreç-yerel ayna devreye girer;
# koruma HİÇBİR durumda sessizce kaybolmaz.
mergen_pk_invalidate_requests <- function(session, request_ids) {
  kimlikler <- try(as.character(request_ids), silent = TRUE)
  if (inherits(kimlikler, "try-error")) kimlikler <- character(0)
  kimlikler <- kimlikler[!is.na(kimlikler) & nzchar(kimlikler)]
  if (!length(kimlikler)) return(invisible(character(0)))

  # ÖNCE süreç-yerel ayna: `userData` erişilemez olsa bile geçersizleme
  # KAYBOLMAZ.
  # SABİTLENİR: istek terminal duruma ulaşana kadar tavan bu işareti DÜŞÜREMEZ.
  for (kimlik in kimlikler) {
    .pk_marker_note("abandoned", .pk_marker_key(session, kimlik), pin = TRUE)
  }

  mevcut <- .pk_marker_read(session, "pk_abandoned_requests")
  if (!is.character(mevcut)) mevcut <- character(0)
  # Pencere sınırlı tutulur: oturum ömrü boyunca sınırsız büyümemeli.
  yeni <- utils::tail(unique(c(mevcut, kimlikler)), 200L)
  if (!isTRUE(pk_session_state_write(session, "pk_abandoned_requests", yeni))) {
    try(log_warn(paste0(
      "[PK_ASYNC] Terk isareti oturuma yazilamadi; surec-yerel ayna kullaniliyor."
    )), silent = TRUE)
  }
  invisible(yeni)
}

#' Bu istek AÇIKÇA terk edildi mi?
mergen_pk_request_abandoned <- function(session, request_id) {
  kimlik <- .pk_marker_id(request_id)
  if (is.na(kimlik)) return(FALSE)
  if (.pk_marker_has("abandoned", .pk_marker_key(session, kimlik))) return(TRUE)
  terk <- .pk_marker_read(session, "pk_abandoned_requests")
  is.character(terk) && kimlik %in% terk
}

# ------------------------------------------------------------------------------
# JETON SAHİPLİĞİ KAYDI
# ------------------------------------------------------------------------------
# Durdur gözlemcisi HER istek için çalışır (sohbet, görsel, özetleme...).
# Yalnızca PK dağıtıcısının SAHİP OLDUĞU istekler için jeton yazılmalıdır;
# aksi hâlde hiçbir tamamlanma yolunun temizlemediği `.flag` dosyaları birikir.
mergen_pk_register_cancel_token <- function(session, request_id) {
  kimlik <- .pk_marker_id(request_id)
  if (is.na(kimlik)) return(invisible(FALSE))

  mevcut <- .pk_marker_read(session, "pk_cancel_token_owners")
  if (!is.character(mevcut)) mevcut <- character(0)
  # Kayıt penceresi sınırlı tutulur: oturum ömrü boyunca sınırsız büyümemeli.
  mevcut <- utils::tail(unique(c(mevcut, kimlik)), 50L)

  # YAZIM SONUCU DENETLENİR: `userData` yazılamazsa Durdur gözlemcisi
  # `mergen_pk_request_has_cancel_token()` üzerinden sahipliği GÖREMEZ ve işçinin
  # dosya jetonunu HİÇ işaretlemez — yani Durdur sessizce çalışmaz hâle gelirdi.
  # Bu durumda ÇAĞIRAN asenkron gönderim YAPMAMALIDIR (kapalı başarısız).
  if (!isTRUE(pk_session_state_write(session, "pk_cancel_token_owners", mevcut))) {
    return(invisible(FALSE))
  }
  # Yeniden kaydedilen bir kimlik için önceki "geri alındı" vetosu kalkar.
  anahtar <- .pk_marker_key(session, kimlik)
  if (!is.na(anahtar)) {
    kalan <- .pk_request_marker_store$revoked
    if (is.character(kalan)) .pk_request_marker_store$revoked <- setdiff(kalan, anahtar)
  }
  invisible(mergen_pk_request_has_cancel_token(session, kimlik))
}

#' Jeton sahipliğini KALDIR (isteğin her terminal yolunda)
#'
#' `bitir_istek()` bayrağı temizler ve aktif isteği siler, ama sahiplik kaydı
#' kalırsa nihai LLM sırasında basılan Durdur AYNI istek kimliğiyle YENİ bir
#' `.flag` dosyası üretir. O dosyayı temizleyecek bir PK yolu artık YOKTUR.
#'
#' @return `TRUE` yalnızca sahiplik GERÇEKTEN kalkmışsa (geri okunarak doğrulanır).
mergen_pk_unregister_cancel_token <- function(session, request_id) {
  kimlik <- .pk_marker_id(request_id)
  if (is.na(kimlik)) return(invisible(FALSE))

  # ÖNCE süreç-yerel veto: `userData` yazımı yutulsa bile Durdur gözlemcisi
  # (aynı süreçte) artık bu istek için jeton yazmaz.
  .pk_marker_note("revoked", .pk_marker_key(session, kimlik))
  # TERMİNAL DURUM: terk işaretinin sabitlemesi kalkar (bkz. `.pk_marker_note()`).
  .pk_marker_unpin(.pk_marker_key(session, kimlik))

  mevcut <- .pk_marker_read(session, "pk_cancel_token_owners")
  if (is.character(mevcut) && length(mevcut)) {
    pk_session_state_write(session, "pk_cancel_token_owners", setdiff(mevcut, kimlik))
  }
  # SONUÇ GERİ OKUNUR: `TRUE` yalnızca sahiplik gerçekten görünmez olduğunda.
  invisible(!isTRUE(mergen_pk_request_has_cancel_token(session, kimlik)))
}

mergen_pk_request_has_cancel_token <- function(session, request_id) {
  kimlik <- .pk_marker_id(request_id)
  if (is.na(kimlik)) return(FALSE)
  if (.pk_marker_has("revoked", .pk_marker_key(session, kimlik))) return(FALSE)
  sahipler <- .pk_marker_read(session, "pk_cancel_token_owners")
  is.character(sahipler) && kimlik %in% sahipler
}
