# ==============================================================================
# Dosya Yolu: R/helpers_deep_analysis_phase6.R
# Açıklama: Faz 6 (§5.10) — Derin Düşünme'nin BLOKLAMAYAN YÜRÜTME kararları.
#
# NEDEN AYRI DOSYA: `R/helpers_deep_analysis.R` bakım ratchet bütçesine
# (659 satır) dayanıyordu. Bu dosya orkestratöre ait olmayan üç KARAR'ı taşır:
#
#   1) Faz 6 kurulumu (mutlak son tarih + oturum kapsamlı iptal jetonu +
#      ara katmanların göreceği option'lar) ve GERİ ALMA SINIRI.
#   2) Kısmi durma (iptal/son tarih) notunun bağlama yazılması.
#   3) Bozulmuş filtre planı kapısının derin moddaki karşılığı.
#
# SAFTIR: DB/ağ çağrısı YOKTUR. Yalnızca `options()` ve düz veri işler; Shiny
# `session` nesnesine yalnızca jeton adını türetmek için dokunur.
# ==============================================================================

#' Faz 6 kurulumunu uygula (GERİ ALMA SINIRI dahil)
#'
#' Yeni denetimler (mutlak analiz son tarihi, iptal jetonu, ara katman
#' option'ları) YALNIZCA asenkron kipte devrededir. `MERGEN_PK_ASYNC=false`
#' ilan edilen tek adımlık geri alma yoludur; son tarih orada da uygulansaydı,
#' daha önce geçerli olan uzun bir derin analiz bayrak KAPALIYKEN bile
#' kesilirdi.
#'
#' @return `list(detail_config = <güncellenmiş>, restore = <fonksiyon|NULL>)`.
pk_deep_phase6_setup <- function(detail_config, session, request_id, started_at) {
  aktif <- exists("pk_async_mode_active", mode = "function", inherits = TRUE) &&
    isTRUE(tryCatch(pk_async_mode_active(), error = function(e) FALSE))

  detail_config$pk_phase6_active <- isTRUE(aktif)
  if (!isTRUE(aktif)) {
    detail_config$pk_deadline_at <- NULL
    detail_config$pk_cancel_token <- NULL
    return(list(detail_config = detail_config, restore = NULL))
  }

  detail_config$pk_deadline_at <- pk_deadline_at(
    started_at,
    tryCatch(pk_config_resolve("MERGEN_PK_ANALYSIS_DEADLINE_SEC"), error = function(e) 300L)
  )

  # İptal jetonu OTURUM KAPSAMLIDIR. Durdur gözlemcisi
  # `mergen_pk_cancel_token_for_session()` yolunu işaretler; yalnızca istek
  # kimliğinden yeniden kurmak, HİÇ YAZILMAYAN bir dosyayı yoklamak olurdu.
  # Asenkron işçi bu sembolü zaten dispatch jetonuyla değiştirir.
  kimlik <- as.character(request_id %||% "")[1]
  detail_config$pk_cancel_token <- if (nzchar(kimlik)) {
    if (exists("mergen_pk_cancel_token_for_session", mode = "function", inherits = TRUE)) {
      tryCatch(mergen_pk_cancel_token_for_session(session, kimlik),
               error = function(e) pk_cancel_token_path(kimlik))
    } else {
      pk_cancel_token_path(kimlik)
    }
  } else {
    NULL
  }

  # Ara katmanlar (v1 çoklu seçici, v2 seçici, filtre LLM'i, telemetri) imza
  # değiştirmeden kalan bütçeyi görebilsin diye option olarak yayınlanır.
  eski_deadline <- getOption("mergen.pk.async.deadline_at", NULL)
  eski_token <- getOption("mergen.pk.async.cancel_token", NULL)
  options(mergen.pk.async.deadline_at = detail_config$pk_deadline_at,
          mergen.pk.async.cancel_token = detail_config$pk_cancel_token)

  list(
    detail_config = detail_config,
    restore = function() {
      options(mergen.pk.async.deadline_at = eski_deadline,
              mergen.pk.async.cancel_token = eski_token)
    }
  )
}

#' Kısmi durma durumunu bağlama AÇIKÇA yaz
#'
#' `break` ile çıkıp normal bir bağlam üretmek, kullanıcıya "tam analiz" gibi
#' görünen ama sessizce eksik bir yanıt vermek olurdu (§5.11).
pk_deep_apply_partial_halt <- function(detail_config, halt_status, completed_count) {
  durum <- tryCatch(as.character(halt_status)[1], error = function(e) NA_character_)
  if (length(durum) != 1L || is.na(durum) || !nzchar(durum)) return(detail_config)

  detail_config$pk_partial_halt_status <- durum
  detail_config$pk_partial_halt_note <- paste0(
    "UYARI: Bu derin analiz TAMAMLANMADI. Seçilen sorguların yalnızca ",
    completed_count, " tanesi çalıştırılabildi; kalanlar ",
    if (identical(durum, "deadline")) "süre sınırı" else "kullanıcı iptali",
    " nedeniyle çalıştırılmadı. Bulguları EKSİK olarak raporlayın."
  )
  cat(sprintf("[DEEP_ANALYSIS] KISMI sonuc (durum=%s); baglam eksik olarak isaretlendi.\n",
              durum))
  detail_config
}

#' Bozulmuş filtre planı kararı (derin mod)
#'
#' Ana yolla PARİTE: filtre planı zaman aşımı/bozuk yanıt nedeniyle
#' üretilemediğinde TÜM yetkili küme üzerinden sessizce devam EDİLMEZ; aksi
#' hâlde filtreli bir soruya tam-küme istatistiği kendinden emin biçimde
#' dönerdi. Derin modda yalnızca O SORGU başarısız olur; çalışma sürer.
pk_deep_filter_degraded_decision <- function(filter_status) {
  if (!exists("pk_filter_degraded_gate", mode = "function", inherits = TRUE)) {
    return(list(refuse = FALSE, message = NA_character_))
  }
  kapi <- tryCatch(pk_filter_degraded_gate(filter_status),
                   error = function(e) list(refuse = FALSE))
  if (!isTRUE(kapi$refuse)) return(list(refuse = FALSE, message = NA_character_))

  list(
    refuse = TRUE,
    message = as.character(
      kapi$message %||% "Filtre planı üretilemedi; sorgu atlandı."
    )[1]
  )
}
