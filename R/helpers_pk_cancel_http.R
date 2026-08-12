# ==============================================================================
# Dosya Yolu: R/helpers_pk_cancel_http.R
# Açıklama: Faz 6 (§5.10) — BLOKLAYAN HTTP ÇAĞRILARININ GERÇEKTEN İPTAL
#           EDİLEBİLMESİ.
#
# SORUN: seçici (v1/v2), filtre planlayıcı ve derin çoklu-sorgu seçici
# `call_local_llm()` üzerinden BLOKLAYAN bir HTTP isteği yapar. Çağrıdan ÖNCE ve
# SONRA aşama kapısı yoklamak, çağrı SIRASINDA gelen bir Durdur'u GÖREMEZ:
# kullanıcı Durdur'a bastıktan sonra işçi (ve derin kipte AÇIK DB bağlantısı)
# istek dönene veya kalan bütçe kadar zaman aşımı dolana kadar meşgul kalırdı.
#
# ÇÖZÜM: curl'ün ilerleme geri çağrısı. `progressfunction` `FALSE` döndürdüğünde
# curl aktarımı ANINDA iptal eder. curl bu geri çağrıyı veri akmasa bile
# periyodik olarak çağırdığı için, iptal jetonu/son tarih tek bir yoklama
# aralığı içinde gözlenir ve işçi bırakılır.
#
# KAPSAM: yapılandırma YALNIZCA aktif bir PK kapısı yayınlanmışken üretilir
# (`pk_active_stage_halt()` bir jeton/son tarih yoksa `FALSE` döner). Sohbet,
# Ortak Oturum, Bilge Yolaç ve diğer LLM yolları ETKİLENMEZ.
#
# SAFTIR: Shiny/reaktif/DB dokunuşu yoktur.
# ==============================================================================

#' Aktif bir PK iptal kapısı yayınlanmış mı?
#'
#' Kapı yoksa hiçbir istek yapılandırması değişmez ve davranış BİT BAZINDA
#' korunur.
pk_http_cancel_active <- function() {
  jeton <- getOption("mergen.pk.async.cancel_token", NULL)
  son_tarih <- getOption("mergen.pk.async.deadline_at", NULL)
  !is.null(jeton) || !is.null(son_tarih)
}

#' İptal edilebilir HTTP isteği için `httr` yapılandırması
#'
#' @param stop_check Opsiyonel özel kapı; verilmezse yayınlanmış PK kapısı.
#' @return `httr::config()` nesnesi. Kapı yoksa BOŞ yapılandırma döner (no-op).
pk_http_cancel_config <- function(stop_check = NULL) {
  if (!requireNamespace("httr", quietly = TRUE)) return(NULL)

  ozel <- is.function(stop_check)
  if (!ozel && !isTRUE(tryCatch(pk_http_cancel_active(), error = function(e) FALSE))) {
    return(httr::config())
  }

  kapi <- if (ozel) {
    stop_check
  } else if (exists("pk_active_stage_halt", mode = "function", inherits = TRUE)) {
    pk_active_stage_halt
  } else {
    return(httr::config())
  }

  # curl sözleşmesi: `TRUE` devam, `FALSE` AKTARIMI İPTAL ET. Geri çağrının
  # KENDİSİ hata atarsa aktarım da kesilir; bu yüzden kapı hatası "devam et"
  # olarak yorumlanır (kapalı başarısız olmak burada isteği gereksiz yere
  # öldürürdü).
  httr::config(
    noprogress = 0L,
    progressfunction = function(down, up) {
      !isTRUE(tryCatch(kapi(), error = function(e) FALSE))
    }
  )
}

#' Bir HTTP isteği iptal nedeniyle mi kesildi?
#'
#' curl iptali sıradan bir aktarım hatası gibi görünür; tipli sonuç üretebilmek
#' için hata metni ile kapının durumu birlikte değerlendirilir.
#' @param halted Aşama kapısı GERÇEKTEN durmuş mu? (varsayılan: canlı yoklama)
pk_http_cancelled_error <- function(message, halted = NULL) {
  metin <- tryCatch(as.character(message)[1], error = function(e) "")
  if (is.null(metin) || is.na(metin) || !nzchar(metin)) return(FALSE)

  # GERİ ÇAĞRIYA ÖZGÜ imzalar: yalnızca curl'ün iptal geri çağrısı üretir.
  # Bunlar tek başına iptal KANITIDIR.
  kesin <- c("Callback aborted", "aborted by callback", "Operation was aborted")
  if (any(vapply(kesin, function(p) grepl(p, metin, fixed = TRUE), logical(1)))) return(TRUE)

  # GENEL AKTARIM HATALARI TEK BAŞINA İPTAL DEĞİLDİR (PR #703 incelemesi).
  #
  # `Failed writing body` ve `transfer closed` sıradan bir sunucu/ağ kopmasında
  # da üretilir. Bunları koşulsuz iptal saymak, GERÇEK bir LLM kesintisini
  # "kullanıcı iptal etti / son tarih doldu" diye raporlar ve yanlış
  # seçici/yedek yoluna sokardı. Bu yüzden yalnızca aşama kapısı GERÇEKTEN
  # durmuşken iptal sayılırlar.
  belirsiz <- c("Failed writing body", "transfer closed")
  if (!any(vapply(belirsiz, function(p) grepl(p, metin, fixed = TRUE), logical(1)))) {
    return(FALSE)
  }

  durdu <- if (is.null(halted)) {
    isTRUE(tryCatch(pk_stage_halted(), error = function(e) FALSE))
  } else {
    isTRUE(halted)
  }
  isTRUE(durdu)
}

#' AKTİF PK isteği durdurulmuş / süresi dolmuş mu? (güvenli yoklama)
#'
#' `pk_active_stage_halt()` yalnızca yürütme bağlamı yardımcısı yüklüyken
#' vardır (izole testler, işçi önyükleme öncesi). Çağıranların her seferinde
#' yerel bir `exists()` sarmalayıcısı tanımlaması bakım oranı bütçelerini
#' tüketiyordu; ortak yüklem burada tek noktada tutulur.
pk_stage_halted <- function() {
  if (!exists("pk_active_stage_halt", mode = "function", inherits = TRUE)) return(FALSE)
  isTRUE(tryCatch(pk_active_stage_halt(), error = function(e) FALSE))
}
