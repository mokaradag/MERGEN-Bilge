# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_lifecycle.R
# Açıklama: Faz 6 (§5.10) — PK asenkron isteğinin ANA SÜREÇ yaşam-döngüsü
#           yardımcıları: kaydedilmemiş sohbet kimliği (nesil sayacı), kalan
#           istek bütçesi, netleştirme çipleri, iptal-jetonu sahipliği ve işçi
#           artifact'inin sunulması/temizlenmesi.
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

# ------------------------------------------------------------------------------
# KAYDEDİLMEMİŞ SOHBET KİMLİĞİ (NESİL SAYACI)
# ------------------------------------------------------------------------------
# `current_chat_id == NULL` her kaydedilmemiş sohbet için AYNIDIR. Nesil
# sayacı, "Yeni Söyleşi" sonrası taze sohbeti öncekinden ayırır; böylece
# tamamlanan bir işçi sonucu yanlış sohbete uygulanamaz.
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

# ------------------------------------------------------------------------------
# İSTEK BÜTÇESİ (SENKRON YEDEK İÇİN)
# ------------------------------------------------------------------------------
mergen_pk_request_deadline_at <- function(request) {
  baslangic <- suppressWarnings(as.numeric(request$started_at_epoch %||% NA_real_)[1])
  if (length(baslangic) != 1L || is.na(baslangic)) return(NULL)
  butce <- suppressWarnings(as.numeric(request$deadline_sec %||% NA_real_)[1])
  if (length(butce) != 1L || is.na(butce) || !is.finite(butce) || butce <= 0) return(NULL)
  pk_deadline_at(as.POSIXct(baslangic, origin = "1970-01-01"), butce)
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
mergen_pk_emit_chips <- function(ctx, chips) {
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
  try(oturum$sendCustomMessage("updateFollowupSuggestions", list(
    message_id = as.character(ctx$req_id %||% "")[1],
    suggestions = chips
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
  if (identical(status, "bootstrap_failed")) {
    return(paste0(
      "\U000026A0\U0000FE0F **Analiz Altyapısı Hazır Değil:** Analiz arka plan ",
      "işçisinde başlatılamadı. Analiz senkron olarak yeniden denendi."
    ))
  }
  mesaj <- try(as.character(error)[1], silent = TRUE)
  if (inherits(mesaj, "try-error")) mesaj <- NA_character_
  if (is.null(mesaj) || !length(mesaj) || is.na(mesaj) || !nzchar(mesaj)) {
    mesaj <- "Analiz tamamlanamadı."
  }
  paste0("\U000026A0\U0000FE0F Analiz modülü hatası: ", mesaj)
}

# ------------------------------------------------------------------------------
# JETON SAHİPLİĞİ KAYDI
# ------------------------------------------------------------------------------
# Durdur gözlemcisi HER istek için çalışır (sohbet, görsel, özetleme...).
# Yalnızca PK dağıtıcısının SAHİP OLDUĞU istekler için jeton yazılmalıdır;
# aksi hâlde hiçbir tamamlanma yolunun temizlemediği `.flag` dosyaları birikir.
mergen_pk_register_cancel_token <- function(session, request_id) {
  ud <- tryCatch(session$userData, error = function(e) NULL)
  if (is.null(ud)) return(invisible(FALSE))
  kimlik <- tryCatch(as.character(request_id)[1], error = function(e) NA_character_)
  if (is.na(kimlik) || !nzchar(kimlik)) return(invisible(FALSE))

  mevcut <- tryCatch(ud[["pk_cancel_token_owners"]], error = function(e) NULL)
  if (!is.character(mevcut)) mevcut <- character(0)
  # Kayıt penceresi sınırlı tutulur: oturum ömrü boyunca sınırsız büyümemeli.
  mevcut <- utils::tail(unique(c(mevcut, kimlik)), 50L)
  try(ud[["pk_cancel_token_owners"]] <- mevcut, silent = TRUE)
  invisible(TRUE)
}

mergen_pk_request_has_cancel_token <- function(session, request_id) {
  kimlik <- tryCatch(as.character(request_id)[1], error = function(e) NA_character_)
  if (is.na(kimlik) || !nzchar(kimlik)) return(FALSE)
  sahipler <- tryCatch(session$userData[["pk_cancel_token_owners"]], error = function(e) NULL)
  is.character(sahipler) && kimlik %in% sahipler
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
