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
  ud <- tryCatch(session$userData, error = function(e) NULL)
  kurulu <- isTRUE(try(ud[["pk_session_end_hook"]], silent = TRUE))
  if (!kurulu) {
    ok <- try({
      session$onSessionEnded(function() {
        try(session$userData[["pk_session_closed"]] <- TRUE, silent = TRUE)
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
    try(ud[["pk_session_end_hook"]] <- TRUE, silent = TRUE)
  }
  invisible(TRUE)
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
# `release` VARSAYILAN OLARAK FALSE'tur: gezinme/yeni sohbet yollarında eski
# isteğin serbest bırakma kapanışını çalıştırmak, ZATEN sıfırlanmış TAZE durumu
# ezerdi. Yalnızca oturum kapanışı `release = TRUE` ile çağırır (orada ezilecek
# taze durum yoktur ve yazma/temizleme kapanışlarının koşması gerekir).
mergen_pk_abandon_active_requests <- function(session, release = FALSE) {
  kayit <- mergen_pk_active_registry(session)
  if (is.null(kayit)) return(invisible(0L))

  adlar <- ls(kayit, all.names = TRUE)
  if (!length(adlar)) return(invisible(0L))

  for (kimlik in adlar) {
    giris <- try(kayit[[kimlik]], silent = TRUE)
    if (!is.list(giris)) next
    try(pk_cancel_token_signal(giris$cancel_token), silent = TRUE)
    if (isTRUE(release) && is.function(giris$release)) try(giris$release(), silent = TRUE)
  }

  # İSTEK KİMLİKLERİ AÇIKÇA GEÇERSİZLENİR. Yalnızca jetonu işaretlemek yetmez:
  # kullanıcı A -> B -> A gezinirse `active_request_id` HÂLÂ req1 olabilir ve
  # `mergen_pk_chat_identity()` yeniden `chat:A` üretir; koruma o zaman AÇIKÇA
  # TERK EDİLMİŞ bir sonucu kabul edip bayat yanıt/oturum yazımlarını uygulardı.
  mergen_pk_invalidate_requests(session, adlar)
  invisible(length(adlar))
}


mergen_pk_bump_chat_epoch <- function(session) {
  ud <- tryCatch(session$userData, error = function(e) NULL)
  if (is.null(ud)) return(invisible(NA_integer_))
  mevcut <- suppressWarnings(as.integer(tryCatch(ud[["pk_unsaved_chat_epoch"]],
                                                 error = function(e) NA_integer_))[1])
  if (length(mevcut) != 1L || is.na(mevcut)) mevcut <- 0L
  yeni <- mevcut + 1L
  try(ud[["pk_unsaved_chat_epoch"]] <- yeni, silent = TRUE)
  invisible(yeni)
}

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
  if (length(nesil) != 1L || is.na(nesil)) nesil <- 0L
  paste0("<new-chat>:", nesil)
}
