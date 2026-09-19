# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_artifact.R
# Açıklama: Faz 6 (§5.10) — asenkron PK isteğinin DIŞA AKTARIM ARTEFAKTI
#           yaşam döngüsü: işçi vekilinde üretilen eki gerçek oturumda sunma
#           (`registerDataObj`), sunulan her dosyanın URL aldığını doğrulama ve
#           sahiplik bırakıldığında artefaktı diskten temizleme.
#
# `R/helpers_pk_async_lifecycle.R` içinden BÖLÜNMÜŞTÜR: o dosya 285 satırlık
# bakım ratchet bütçesinin TAM tavanındaydı ve çip etiketi geri düşüş
# düzeltmesi (PR #719 inceleme, P3) oraya sığmıyordu. Bölme bilinçlidir ve
# DAVRANIŞ DEĞİŞTİRMEZ; artefakt sunumu/temizliği zaten ayrı bir sorumluluktur.
#
# Yükleme sırası: `R/helpers_pk_async_lifecycle.R` dosyasından HEMEN SONRA,
# `R/helpers_pk_async_apply.R` dosyasından ÖNCE (uygulama katmanı bu
# yardımcıları çağırır).
#
# Bu dosya Shiny `session` NESNESİNE dokunur (registerDataObj) ama REAKTİF
# BAĞLAM İSTEMEZ; tüm reaktif okumalar çağıranda `isolate()` ile yapılır.
# ==============================================================================

# Worker vekili registerDataObj içermez. Guard geçince artifact gerçek session'da sunulur.
mergen_pk_serve_worker_artifact <- function(result, session) {
  if (!is.list(result) || !is.list(result$pk_attachment)) {
    return(list(ok = TRUE, result = result))
  }
  # DOSYALI EK VAR AMA SUNUM YARDIMCISI YOK: KAPALI BAŞARISIZ (aksi hâlde çağıran
  # işçi-yerel artefaktı "sunulmuş" sayıp URL'siz indirme kartı gösterirdi).
  eski <- result$pk_attachment
  # DOSYASIZ EK URL BEKLEMEZ. `refused` / `failed` / `empty` durumları hiç
  # dosya taşımaz ve `pk_export_serve()` onları DEĞİŞTİRMEDEN döndürür; URL
  # denetimi bunları başarısız sayıp BAŞARILI bir analizi atıyordu.
  dosyasiz <- !is.list(eski$files) || !length(eski$files)

  # SINIFLANDIRMA KAPIDAN ÖNCE: yardımcı yoksa ve sunulacak DOSYA da yoksa
  # başarısızlık YOKTUR; eski sıra TAMAMLANMIŞ analizi `export_failed` atıyordu.
  if (!exists("pk_export_serve", mode = "function", inherits = TRUE)) {
    return(list(ok = isTRUE(dosyasiz), result = result))
  }
  yeni <- try(pk_export_serve(session, eski), silent = TRUE)
  # URL'SİZ KAYIT DA BAŞARISIZLIKTIR (PR #703 incelemesi).
  #
  # `pk_export_serve()` `session$registerDataObj()` hatasını KENDİ İÇİNDE
  # yakalar ve `url = NULL` taşıyan NORMAL bir artefakt döndürür; bu `try()`
  # ona HİÇ düşmez. Sonuç: indirme bağlantısı kurulamadığı hâlde `ok = TRUE`
  # raporlanıyor, tipli `export_failed` yolu ve artefakt temizliği atlanıyordu.
  if (!inherits(yeni, "try-error") && !dosyasiz &&
      !isTRUE(.pk_artifact_urls_ok(yeni))) {
    return(list(ok = FALSE, result = result))
  }
  if (inherits(yeni, "try-error")) {
    # SESSİZCE URL'siz eke geri dönmek, kullanıcıya ÇALIŞMAYAN bir indirme
    # kartı göstermek olurdu; üstelik başarı yolu artifact'i temizlemediği
    # için dosya da öksüz kalırdı. Bu yüzden TİPLİ başarısızlık döner.
    # DOSYASIZ EKTE SUNUM HATASI ANLAM TAŞIMAZ: sunulacak dosya yokken atılan bir hata TAMAMLANMIŞ analizi `export_failed` ile değiştiriyordu (URL denetimi bu durumu ZATEN atlıyor).
    if (isTRUE(dosyasiz)) return(list(ok = TRUE, result = result))
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

# Sunulan artefaktın HER dosyası kullanılabilir bir URL aldı mı?
.pk_artifact_urls_ok <- function(artifact) {
  if (!is.list(artifact)) return(FALSE)
  dosyalar <- artifact$files %||% list()
  if (!is.list(dosyalar) || !length(dosyalar)) return(FALSE)
  all(vapply(dosyalar, function(x) {
    if (!is.list(x)) return(FALSE)
    adres <- tryCatch(as.character(x$url %||% "")[1], error = function(e) "")
    !is.null(adres) && length(adres) == 1L && !is.na(adres) && nzchar(adres)
  }, logical(1)))
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
