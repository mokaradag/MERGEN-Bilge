# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_session_registry.R
# Açıklama: Faz 6 (§5.10) — OTURUM KAPSAMLI PK istek kayıt defteri.
#
# NEDEN AYRI DOSYA: `R/helpers_pk_async_lifecycle.R` bakım ratchet'inin
# 25-fonksiyon tavanını tüketti. Ayrım aynı zamanda daha iyi bir sınır:
# "oturumun HANGİ istekleri var / sohbet kimliği nedir" ile "TEK bir isteğin
# sonucu nasıl sunulur/temizlenir" farklı sorumluluklardır.
#
# İki ayrı sorunu çözer:
#
#   1) BELLEK: istek başına bir `onSessionEnded()` kapanışı, tamamlanan HER
#      isteğin gönderim çerçevesini oturum ömrü boyunca canlı tutuyordu.
#      Burada oturum başına TEK kanca kurulur; yalnızca AKTİF istekler tutulur.
#
#   2) TERK EDİLEN İŞÇİ: sohbet değiştiğinde sonucu zaten atılacak bir işçi,
#      DB bağlantısını ve işçi yuvasını doğal bitişine kadar tutuyordu.
#      `mergen_pk_abandon_active_requests()` o anda iptal sinyali gönderir.
#
# Shiny `session$userData` üzerine yazar; REAKTİF okuma YAPMAZ.
# ==============================================================================

# ------------------------------------------------------------------------------
# AKTİF İSTEK KAYIT DEFTERİ (OTURUM BAŞINA TEK oturum-sonu kancası)
# ------------------------------------------------------------------------------
# Her istek için ayrı bir `onSessionEnded()` kapanışı kaydetmek, tamamlanan
# HER isteğin gönderim çerçevesini (ctx, request, mesaj anlık görüntüleri,
# devam kapanışları) oturum ömrü boyunca canlı tutuyordu: bellek istek sayısıyla
# doğrusal büyüyordu. Bunun yerine oturum başına TEK kanca kurulur ve yalnızca
# HÂLÂ AKTİF istekler kayıt defterinde tutulur.
#' Oturum HÂLÂ AÇIK MI?
#'
#' Kapanan bir oturumda `onSessionEnded` kancası kayıt defterini boşaltır ve
#' bu bayrağı düşürür; geç gelen geri çağrılar korumayı GEÇEMEZ.
mergen_pk_session_open <- function(session) {
  # SÜREÇ-YEREL AYNA ÖNCE OKUNUR: `userData` OKUNABİLİR ama YAZIMI yutan oturum vekillerinde kapanış işareti oturuma hiç ulaşmaz; geç biten işçi geri çağrısı KAPANMIŞ oturumu AÇIK sanıp artefakt sunmaya devam ederdi (`.pk_session_hook_mark` ile AYNI arıza-güvenli deseni).
  if (.pk_marker_has("closed", .pk_marker_key(session, "<session-closed>"))) return(FALSE)

  durum <- try(session$userData[["pk_session_closed"]], silent = TRUE)
  # KAPALI BAŞARISIZ: `userData` artık OKUNAMIYORSA (oturum yıkıldı, ortam
  # geçersiz) `try()` bir `try-error` döndürür ve `!isTRUE(try-error)` bunu
  # AÇIK oturum sayardı — tam da bu okumanın başarısız olduğu anda tamamlanmış
  # bir future artifact sunmaya, oturum yazımı uygulamaya ve nihai LLM'i
  # tetiklemeye devam ederdi. Okunamayan canlılık durumu KAPALI kabul edilir.
  if (inherits(durum, "try-error")) return(FALSE)
  !isTRUE(durum)
}

mergen_pk_active_registry <- function(session) {
  ud <- tryCatch(session$userData, error = function(e) NULL)
  if (is.null(ud)) return(NULL)
  kayit <- try(ud[["pk_active_requests"]], silent = TRUE)
  if (!is.environment(kayit)) {
    kayit <- new.env(parent = emptyenv())
    yazildi <- try({ ud[["pk_active_requests"]] <- kayit; TRUE }, silent = TRUE)
    # Kayıt defteri OTURUMA BAĞLANAMADIYSA yerel ortamı döndürmek, "kayıt
    # başarılı" görüntüsü verip ERİŞİLEMEYEN bir deftere yazmak olurdu: sonraki
    # Durdur/oturum-sonu araması o isteği ne iptal edebilir ne serbest bırakabilirdi.
    if (!identical(yazildi, TRUE)) return(NULL)
    # Geri okuma DOĞRULAMASI: bazı sahte/salt-okunur `userData` uygulamaları
    # atamayı sessizce yutar.
    dogrulama <- try(ud[["pk_active_requests"]], silent = TRUE)
    if (!is.environment(dogrulama)) return(NULL)
    kayit <- dogrulama
  }
  kayit
}

mergen_pk_register_active_request <- function(session, request_id, cancel_token,
                                              release_fn = NULL) {
  kayit <- mergen_pk_active_registry(session)
  if (is.null(kayit)) return(invisible(FALSE))
  kimlik <- tryCatch(as.character(request_id)[1], error = function(e) NA_character_)
  if (is.na(kimlik) || !nzchar(kimlik)) return(invisible(FALSE))

  kayit[[kimlik]] <- list(cancel_token = cancel_token, release = release_fn)

  # Oturum-sonu kancası oturum başına BİR KEZ kurulur.
  #
  # İŞARET YAZIMI DOĞRULANIR (PR #703): işaret kalıcı olmazsa SONRAKİ her istek
  # `kurulu = FALSE` görür ve yeni bir `onSessionEnded` kapanışı kurar — tam da
  # bu defterin ortadan kaldırdığı istek-başına kapanış birikmesi geri gelir ve
  # aynı terk/serbest bırakma temizliği kopmada defalarca çalışır. `userData`
  # yazımı yutulursa SÜREÇ-YEREL ayna işareti taşır (kanca ve gözlemciler aynı
  # süreçtedir), böylece kurulum yine oturum başına TEK kalır.
  if (!isTRUE(.pk_session_hook_installed(session))) {
    ok <- try({
      session$onSessionEnded(function() {
        # YAZIM DOĞRULANIR: sessizce yutulan bir atama oturumu AÇIK bırakırdı. Kalıcı yazım başarısızsa süreç-yerel ayna işaret taşır (kanca ve gözlemciler AYNI süreçtedir).
        kalici <- isTRUE(try(pk_session_state_write(session, "pk_session_closed", TRUE), silent = TRUE))
        try(.pk_marker_note("closed", .pk_marker_key(session, "<session-closed>")), silent = TRUE)
        if (!kalici) {
          try(log_warn("[PK_ASYNC] Oturum kapali isareti oturuma yazilamadi; surec-yerel ayna kullaniliyor."), silent = TRUE)
        }
        try(mergen_pk_abandon_active_requests(session, release = TRUE), silent = TRUE)
      })
      TRUE
    }, silent = TRUE)
    # KANCA KURULAMADIYSA kayıt GERİ ALINIR ve `FALSE` döner. Aksi hâlde çağıran
    # yaşam döngüsü korumasının VAR OLDUĞUNU varsayar: oturum kapanışı ne
    # `pk_session_closed` yazar, ne jetonu işaretler, ne de serbest bırakma
    # kapanışını çalıştırır — geç geri çağrılar ölü bir oturumu hedefler ve
    # backpressure tutulu kalır.
    if (!identical(ok, TRUE)) {
      try(rm(list = kimlik, envir = kayit), silent = TRUE)
      return(invisible(FALSE))
    }
    if (!isTRUE(.pk_session_hook_mark(session))) {
      try(rm(list = kimlik, envir = kayit), silent = TRUE)
      return(invisible(FALSE))
    }
  }
  invisible(TRUE)
}

# Oturum-sonu kancası kurulu mu? (`userData` VEYA süreç-yerel ayna)
.pk_session_hook_installed <- function(session) {
  if (.pk_marker_has("hooked", .pk_marker_key(session, "<session-end-hook>"))) return(TRUE)
  isTRUE(try(session$userData[["pk_session_end_hook"]], silent = TRUE))
}

# Kancayı işaretle; işaret HİÇBİR yolda kalıcı olamazsa `FALSE`.
.pk_session_hook_mark <- function(session) {
  kalici <- isTRUE(pk_session_state_write(session, "pk_session_end_hook", TRUE))
  aynali <- isTRUE(.pk_marker_note("hooked", .pk_marker_key(session, "<session-end-hook>")))
  if (!kalici) {
    try(log_warn(paste0(
      "[PK_ASYNC] Oturum-sonu kanca isareti oturuma yazilamadi; ",
      "surec-yerel ayna kullaniliyor."
    )), silent = TRUE)
  }
  isTRUE(kalici || aynali)
}

mergen_pk_unregister_active_request <- function(session, request_id) {
  kayit <- mergen_pk_active_registry(session)
  if (is.null(kayit)) return(invisible(FALSE))
  kimlik <- tryCatch(as.character(request_id)[1], error = function(e) NA_character_)
  if (is.na(kimlik) || !nzchar(kimlik)) return(invisible(FALSE))
  if (!is.null(kayit[[kimlik]])) rm(list = kimlik, envir = kayit)
  invisible(TRUE)
}

#' Kayıtlı TÜM aktif PK isteklerini terk et (iptal sinyali + slot bırakma)
#'
#' Sohbet bağlamı değiştiğinde (Yeni Söyleşi / kayıtlı sohbet açma) ya da oturum
#' kapandığında çağrılır. Aksi hâlde sonucu ZATEN atılacak bir işçi, DB
#' bağlantısını ve işçi yuvasını doğal bitişine veya tam analiz son tarihine
#' kadar tutmaya devam ederdi.
# BACKPRESSURE YUVASI HER ZAMAN BIRAKILIR.
#
# Kayıtlı `release` kapanışı YALNIZCA `mergen_send_message_release_values_token()`
# çağırır ve o yardımcı zaten SAHİPLİK denetimlidir: `backpressure_request_id`
# hâlâ bu isteğe ait değilse hiçbir şey yapmaz. Dolayısıyla daha yeni bir
# isteğin yuvasını ya da sıfırlanmış TAZE durumu ezmesi mümkün değildir.
#
# Eski `release = FALSE` varsayılanı yalnızca iptal sinyali gönderiyordu; ODBC/
# LLM/yerel kod içinde takılmış bir işçi iptal bayrağını hemen göremediğinde
# her gezinme süreç genelinde bir admisyon yuvasını işçi/son tarih bitene kadar
# TUTUYOR ve bir süre sonra ilgisiz TAZE istekler "sunucu meşgul" ile
# başarısız oluyordu.
#
# `release` parametresi geriye dönük uyumluluk için KORUNUR; bugün yuva
# bırakma ondan bağımsızdır ve yalnızca ek temizleme kapanışları için ayrılmıştır.
mergen_pk_abandon_active_requests <- function(session, release = FALSE) {
  kayit <- mergen_pk_active_registry(session)
  if (is.null(kayit)) return(invisible(0L))

  adlar <- ls(kayit, all.names = TRUE)
  if (!length(adlar)) return(invisible(0L))

  for (kimlik in adlar) {
    giris <- try(kayit[[kimlik]], silent = TRUE)
    if (!is.list(giris)) next
    try(pk_cancel_token_signal(giris$cancel_token), silent = TRUE)
    # Sahiplik denetimli yuva bırakma her yolda çalışır (bkz. yukarıdaki not).
    if (is.function(giris$release)) try(giris$release(), silent = TRUE)
  }

  # İSTEK KİMLİKLERİ AÇIKÇA GEÇERSİZLENİR. Yalnızca jetonu işaretlemek yetmez:
  # kullanıcı A -> B -> A gezinirse `active_request_id` HÂLÂ req1 olabilir ve
  # `mergen_pk_chat_identity()` yeniden `chat:A` üretir; koruma o zaman AÇIKÇA
  # TERK EDİLMİŞ bir sonucu kabul edip bayat yanıt/oturum yazımlarını uygulardı.
  mergen_pk_invalidate_requests(session, adlar)
  if (isTRUE(release)) for (kimlik in adlar) try(.pk_marker_unpin(.pk_marker_key(session, kimlik)), silent = TRUE)  # OTURUM SONU: BU OTURUMA AIT SABITLEMELER BIRAKILIR; `pinned` SUREC-YERELDIR ve terminal geri cagriya ulasamayan istek burada birakilmazsa surec omru boyunca kalir, 500 girdilik tavan yalnizca KALAN kumeye uygulanirdi (diger CANLI oturumlarin sabitlemeleri korunur).

  # TERK EDİLEN GİRDİLER KAYITTAN SİLİNİR: kayıt "yalnızca AKTİF istekler"
  # sözleşmesindedir, ama girdi istek-sahipli `release` kapanışını ve yakaladığı
  # durumu canlı tutuyordu; takılı bir işçi terminal geri çağrısına hiç ulaşmazsa
  # her gezinme oturum belleğini büyütürdü. Bayat sonuç koruması AYRI terk-işareti
  # deposundadır (yukarıda), bu yüzden silme korumayı zayıflatmaz.
  for (kimlik in adlar) {
    if (!is.null(kayit[[kimlik]])) try(rm(list = kimlik, envir = kayit), silent = TRUE)
  }

  invisible(length(adlar))
}


mergen_pk_bump_chat_epoch <- function(session) {
  ud <- tryCatch(session$userData, error = function(e) NULL)
  if (is.null(ud)) return(invisible(NA_integer_))
  mevcut <- suppressWarnings(as.integer(tryCatch(ud[["pk_unsaved_chat_epoch"]],
                                                 error = function(e) NA_integer_))[1])
  if (length(mevcut) != 1L || is.na(mevcut)) mevcut <- 0L
  yeni <- mevcut + 1L
  # YAZ-SONRA-OKU DOĞRULAMASI.
  #
  # `try(...)` yutulan bir yazımda da sessizce geçer; nesil ARTMAZ ve iki AYRI
  # kaydedilmemiş söyleşi AYNI kimliğe (`<new-chat>:0`) düşer. Geç biten bir
  # işçi sonucu o zaman YENİ söyleşiye uygulanabilirdi. Yazım doğrulanamazsa
  # arayan `NA` görür ve kimlik çakışmasını varsaymaz.
  yazildi <- tryCatch({
    ud[["pk_unsaved_chat_epoch"]] <- yeni
    okunan <- suppressWarnings(as.integer(ud[["pk_unsaved_chat_epoch"]])[1])
    length(okunan) == 1L && !is.na(okunan) && identical(okunan, yeni)
  }, error = function(e) FALSE)

  if (!isTRUE(yazildi)) {
    .pk_chat_epoch_mirror[[.pk_marker_key(session, "epoch")]] <- yeni  # KALICI OLMAYAN ARTIS OKUMA YOLUNDA DA KARSILANIR: aksi halde YENI kaydedilmemis sohbet ONCEKININ kimligini korur ve gec biten isci sonucu YENI sohbete uygulanirdi (kanca/kapali isaretleriyle AYNI surec-yerel ayna deseni).
    return(invisible(NA_integer_))
  }
  invisible(yeni)
}

# Kalici olmayan nesil artislarinin surec-yerel aynasi (bkz. yukaridaki not).
.pk_chat_epoch_mirror <- new.env(parent = emptyenv())

mergen_pk_chat_identity <- function(session, values) {
  kimlik <- try(shiny::isolate(values$current_chat_id), silent = TRUE)
  if (inherits(kimlik, "try-error")) kimlik <- NULL

  if (!is.null(kimlik) && length(kimlik)) {
    metin <- try(as.character(kimlik)[1], silent = TRUE)
    if (!inherits(metin, "try-error") && !is.na(metin) && nzchar(metin)) {
      return(paste0("chat:", metin))
    }
  }

  nesil <- suppressWarnings(as.integer(tryCatch(
    session$userData[["pk_unsaved_chat_epoch"]], error = function(e) NA_integer_
  ))[1])
  ayna <- suppressWarnings(as.integer(.pk_chat_epoch_mirror[[.pk_marker_key(session, "epoch")]] %||% NA_integer_)[1])  # AYNA DAHA YENIYSE O KULLANILIR: yutulan bir yazim iki AYRI kaydedilmemis sohbeti AYNI kimlige dusuruyordu.
  if (length(nesil) != 1L || is.na(nesil)) nesil <- 0L
  if (length(ayna) == 1L && !is.na(ayna) && ayna > nesil) nesil <- ayna
  paste0("<new-chat>:", nesil)
}
