# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_lifecycle.R
# Açıklama: Faz 6 (§5.10) — TEK bir PK isteğinin ana-süreç yaşam-döngüsü:
#           gönderim anı anlık görüntüsü, kalan istek bütçesi, netleştirme
#           çipleri, kullanıcıya görünen sonuç metni ve işçi artifact'inin
#           sunulması/temizlenmesi.
#
# Oturum kapsamlı kayıt defteri (aktif istekler, sohbet nesli, jeton sahipliği)
# AYRI dosyadadır: `R/helpers_pk_async_session_registry.R`.
#
# Bu dosya `R/helpers_pk_async_apply.R` içinden BÖLÜNMÜŞTÜR: tek dosya bakım
# ratchet'inin 25-fonksiyon tavanını tüketiyordu. Ayrım aynı zamanda daha iyi
# bir sınır: "işçi sonucunu nasıl UYGULARIM" ile "isteğin ana-süreç yaşam
# döngüsünü nasıl YÖNETİRİM" farklı sorumluluklardır.
#
# Shiny `session` NESNESİNE dokunur (userData, registerDataObj) ama REAKTİF
# okuma yapmaz; reaktif okumalar çağıran tarafından `shiny::isolate()` ile
# sarmalanır.
# ==============================================================================

#' GÖNDERİM ANI anlık görüntüsü (ayarlar + etkin API anahtarı planı)
#'
#' Asenkron PK yolunda devam kapanışı dakikalar sonra çalışır. O sırada
#' kullanıcı karakter/kodlama/görsel/TTS ayarlarını veya kişisel API anahtarını
#' değiştirebilir; canlı reaktif nesneyi yeniden okumak, aynı isteğin İKİ
#' farklı ayar durumundan derlenmesine (ve analiz başarılıyken "API anahtarı
#' eksik" ile bitmesine) yol açardı.
mergen_pk_send_snapshot <- function(session, settings_data) {
  ayarlar <- tryCatch(
    shiny::isolate(shiny::reactiveValuesToList(settings_data)),
    error = function(e) NULL
  )
  anahtar <- tryCatch(
    mb_api_key_get_cached_for_send(
      session = session, require_auth = TRUE,
      allow_default = NULL, clear_on_mismatch = TRUE
    ),
    error = function(e) NULL
  )
  list(settings = ayarlar, api_key_plan = anahtar)
}

# ------------------------------------------------------------------------------
# İSTEK BÜTÇESİ (SENKRON YEDEK İÇİN)
# ------------------------------------------------------------------------------
mergen_pk_request_started_at <- function(request) {
  baslangic <- suppressWarnings(as.numeric(request$started_at_epoch %||% NA_real_)[1])
  if (length(baslangic) != 1L || is.na(baslangic)) return(NULL)
  as.POSIXct(baslangic, origin = "1970-01-01")
}

mergen_pk_request_deadline_at <- function(request) {
  baslangic <- mergen_pk_request_started_at(request)
  if (is.null(baslangic)) return(NULL)
  butce <- suppressWarnings(as.numeric(request$deadline_sec %||% NA_real_)[1])
  if (length(butce) != 1L || is.na(butce) || !is.finite(butce) || butce <= 0) return(NULL)
  pk_deadline_at(baslangic, butce)
}

mergen_pk_residual_budget_sec <- function(request) {
  son_tarih <- mergen_pk_request_deadline_at(request)
  if (is.null(son_tarih)) return(Inf)
  pk_deadline_remaining_sec(son_tarih)
}

# ------------------------------------------------------------------------------
# NETLEŞTİRME ÇİPLERİ
# ------------------------------------------------------------------------------
# v2 seçicisi düşük güven/yakın beraberlik durumlarında TIKLANABİLİR seçenekler
# üretir. Yalnızca prozayı eklemek, kullanıcıdan seçmesini isteyip seçenekleri
# göstermemek olurdu.
mergen_pk_emit_chips <- function(ctx, chips, message_id = NULL) {
  if (!is.list(chips) || length(chips) == 0L) return(invisible(FALSE))
  gonder <- tryCatch(ctx$emit_chips_fn, error = function(e) NULL)
  if (is.function(gonder)) {
    try(gonder(chips), silent = TRUE)
    return(invisible(TRUE))
  }
  oturum <- tryCatch(ctx$session, error = function(e) NULL)
  if (is.null(oturum) || !is.function(tryCatch(oturum$sendCustomMessage, error = function(e) NULL))) {
    return(invisible(FALSE))
  }

  # TARAYICI SÖZLEŞMESİ: `updateFollowupSuggestions` işleyicisi `data.id` ve
  # `data.followups` alanlarını ZORUNLU kılar; ikisinden biri yoksa HEMEN
  # döner. Eski `message_id`/`suggestions` alanları sessizce düşüyordu.
  #
  # HEDEF DE DOĞRU OLMALIDIR: işleyici `message_wrapper_<data.id>` düğümünü
  # arar. `req_id` gönderim yaşam döngüsü kimliğidir (`req_...`); DOM düğümü
  # ise `add_message_fn()`'in döndürdüğü SOHBET MESAJI kimliğiyle (`msg_...`
  # veya kalıcı DB kimliği) oluşturulur. Mesaj kimliği yoksa hiç gönderilmez:
  # var olmayan bir düğümü hedeflemek chip'leri sessizce kaybetmek olurdu.
  kimlik <- tryCatch(as.character(message_id %||% "")[1], error = function(e) "")
  if (is.na(kimlik) || !nzchar(kimlik)) return(invisible(FALSE))

  try(oturum$sendCustomMessage("updateFollowupSuggestions", list(
    id = kimlik,
    followups = chips,
    pending = FALSE
  )), silent = TRUE)
  invisible(TRUE)
}

mergen_pk_worker_outcome_text <- function(status, error = NA_character_) {
  if (identical(status, "cancelled") || identical(status, "deadline")) {
    return(pk_async_halt_message(status))
  }
  # Tipli KAYNAK sonuçları "modül hatası" değildir; kullanıcıya ne yapması
  # gerektiğini söyleyen kendi mesajları vardır.
  if (identical(status, "timeout")) {
    return(get0("PK_SQL_TIMEOUT_MESSAGE", inherits = TRUE,
                ifnotfound = "\U000023F1\U0000FE0F **Sorgu Zaman Aşımı:** Sorgu tamamlanamadı."))
  }
  if (identical(status, "too_large")) {
    return(get0("PK_RESULT_TOO_LARGE_MESSAGE", inherits = TRUE,
                ifnotfound = "\U0001F50D **Sonuç Kümesi Çok Büyük:** Lütfen sorunuzu daraltın."))
  }
  if (identical(status, "export_failed")) {
    return(paste0(
      "\U000026A0\U0000FE0F **Dosya Hazırlanamadı:** Analiz tamamlandı ancak ",
      "indirilebilir dosya bu oturumda sunulamadı. Lütfen tekrar deneyin."
    ))
  }
  # ALTYAPI ARIZASI: analiz arka plan işçisinde başlatılamadı. Senkron TEKRAR
  # OYNATMA YAPILMAZ (bu, promise geri çağrısında olay döngüsünü bloklardı ve
  # kullanıcının Durdur olayı da işlenemezdi), bu yüzden mesaj kullanıcıya
  # gerçekte ne olduğunu ve ne yapması gerektiğini söyler.
  if (identical(status, "bootstrap_failed") || identical(status, "infrastructure")) {
    return(paste0(
      "\U000026A0\U0000FE0F **Analiz Altyapısı Hazır Değil:** Analiz arka plan ",
      "işçisinde başlatılamadı. Lütfen sorunuzu tekrar gönderin; sorun sürerse ",
      "sistem yöneticinize bildirin."
    ))
  }
  mesaj <- try(as.character(error)[1], silent = TRUE)
  if (inherits(mesaj, "try-error")) mesaj <- NA_character_
  if (is.null(mesaj) || !length(mesaj) || is.na(mesaj) || !nzchar(mesaj)) {
    mesaj <- "Analiz tamamlanamadı."
  }
  paste0("\U000026A0\U0000FE0F Analiz modülü hatası: ", mesaj)
}

# Worker vekili registerDataObj içermez. Guard geçince artifact gerçek session'da sunulur.
mergen_pk_serve_worker_artifact <- function(result, session) {
  if (!is.list(result) || !is.list(result$pk_attachment) ||
      !exists("pk_export_serve", mode = "function", inherits = TRUE)) {
    return(list(ok = TRUE, result = result))
  }

  eski <- result$pk_attachment
  yeni <- try(pk_export_serve(session, eski), silent = TRUE)
  if (inherits(yeni, "try-error")) {
    # SESSİZCE URL'siz eke geri dönmek, kullanıcıya ÇALIŞMAYAN bir indirme
    # kartı göstermek olurdu; üstelik başarı yolu artifact'i temizlemediği
    # için dosya da öksüz kalırdı. Bu yüzden TİPLİ başarısızlık döner.
    return(list(ok = FALSE, result = result))
  }
  result$pk_attachment <- yeni

  if (exists("pk_compose_attachment_card", mode = "function", inherits = TRUE) &&
      is.character(result$pk_answer_block) && length(result$pk_answer_block) == 1L) {
    eski_kart <- try(pk_compose_attachment_card(eski), silent = TRUE)
    yeni_kart <- try(pk_compose_attachment_card(yeni), silent = TRUE)
    if (inherits(eski_kart, "try-error")) eski_kart <- NULL
    if (inherits(yeni_kart, "try-error")) yeni_kart <- NULL
    if (is.character(eski_kart) && length(eski_kart) == 1L && nzchar(eski_kart) &&
        is.character(yeni_kart) && length(yeni_kart) == 1L && nzchar(yeni_kart) &&
        grepl(eski_kart, result$pk_answer_block, fixed = TRUE)) {
      result$pk_answer_block <- sub(eski_kart, yeni_kart, result$pk_answer_block, fixed = TRUE)
    }
  }
  list(ok = TRUE, result = result)
}

mergen_pk_cleanup_worker_artifact <- function(result) {
  if (!is.list(result) || !is.list(result$pk_attachment)) return(invisible(FALSE))
  dosyalar <- result$pk_attachment$files %||% list()
  if (!is.list(dosyalar) || !length(dosyalar)) return(invisible(FALSE))

  yollar <- vapply(dosyalar, function(x) {
    if (!is.list(x)) return("")
    as.character(x$path %||% "")[1]
  }, character(1))
  yollar <- yollar[!is.na(yollar) & nzchar(yollar)]
  for (yol in yollar) try(unlink(yol, force = TRUE), silent = TRUE)
  for (dizin in unique(dirname(yollar))) {
    norm <- gsub("\\\\", "/", dizin)
    if (grepl("(^|/)run_[^/]*$", norm) && dir.exists(dizin) && !length(list.files(dizin))) {
      try(unlink(dizin, recursive = TRUE, force = TRUE), silent = TRUE)
    }
  }
  invisible(length(yollar) > 0L)
}
