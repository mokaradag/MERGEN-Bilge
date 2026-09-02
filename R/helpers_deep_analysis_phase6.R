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
pk_deep_phase6_setup <- function(detail_config, session, request_id,
                                 started_at = Sys.time()) {
  aktif <- exists("pk_async_mode_active", mode = "function", inherits = TRUE) &&
    isTRUE(tryCatch(pk_async_mode_active(), error = function(e) FALSE))

  detail_config$pk_phase6_active <- isTRUE(aktif)
  if (!isTRUE(aktif)) {
    detail_config$pk_deadline_at <- NULL
    detail_config$pk_cancel_token <- NULL
    return(list(detail_config = detail_config, restore = NULL))
  }

  # SENKRON YEDEK YOLU: `senkron_yedek()` ORİJİNAL dispatch son tarihini
  # BİLEREK yayınlar (işçi/bootstrap süresi geri ÖDENMEZ). Burada taze bir
  # `started_at` üzerinden yeni bir tam analiz penceresi hesaplamak, başarısız
  # bir asenkron denemeden sonra toplam duvar saatini neredeyse İKİYE
  # KATLARDI. Önceden yayınlanmış bir son tarih varsa ERKEN OLAN korunur.
  hesaplanan <- pk_deadline_at(
    started_at,
    tryCatch(pk_config_resolve("MERGEN_PK_ANALYSIS_DEADLINE_SEC"), error = function(e) 300L)
  )
  onceki_son_tarih <- getOption("mergen.pk.async.deadline_at", NULL)
  detail_config$pk_deadline_at <- if (inherits(onceki_son_tarih, "POSIXct") &&
                                      length(onceki_son_tarih) == 1L &&
                                      !is.na(onceki_son_tarih)) {
    if (inherits(hesaplanan, "POSIXct") && length(hesaplanan) == 1L && !is.na(hesaplanan)) {
      min(onceki_son_tarih, hesaplanan)
    } else {
      onceki_son_tarih
    }
  } else {
    hesaplanan
  }

  # İptal jetonu OTURUM KAPSAMLIDIR. Durdur gözlemcisi
  # `mergen_pk_cancel_token_for_session()` yolunu işaretler; yalnızca istek
  # kimliğinden yeniden kurmak, HİÇ YAZILMAYAN bir dosyayı yoklamak olurdu.
  # Asenkron işçi bu sembolü zaten dispatch jetonuyla değiştirir.
  #
  # İŞÇİDE: `session` `pk_async_worker_session()` vekilidir ve `token` alanı
  # gerçek Shiny oturum jetonu DEĞİL istek kimliğidir. Yolu vekil üzerinden
  # YENİDEN KURMAK, ana sürecin işaretlediği dosyadan BAŞKA bir dosyayı
  # izlemek olurdu (işçi yalnızca `pk_cancel_token_path()`'i override eder;
  # bu dal onu ATLARDI) ve derin SQL/aşama kapıları Durdur'u KAÇIRIRDI.
  # Bu yüzden ZATEN YAYINLANMIŞ dispatch jetonu varsa o KULLANILIR.
  yayinlanan <- getOption("mergen.pk.async.cancel_token", NULL)
  yayinlanan <- tryCatch(as.character(yayinlanan)[1], error = function(e) NA_character_)

  kimlik <- as.character(request_id %||% "")[1]
  detail_config$pk_cancel_token <- if (!is.na(yayinlanan) && nzchar(yayinlanan)) {
    yayinlanan
  } else if (nzchar(kimlik)) {
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
  eski_start <- getOption("mergen.pk.async.started_at", NULL)
  # `started_at`: sorgu seçildikten SONRA uygulanan per-query
  # `analysis_deadline_sec` override'ı mutlak son tarihi AYNI başlangıçtan
  # yeniden hesaplar; geçen süre sıfırlanmaz.
  #
  # ORİJİNAL DİSPATCH BAŞLANGICI KORUNUR (PR #703 incelemesi): burada
  # `Sys.time()` yazmak, bootstrap + kurulum süresini İSTEĞE GERİ VERİR ve
  # per-query override'lı her derin istek ilan edilen duvar-saati son tarihinin
  # ötesine geçebilirdi. İşçi (ve sınırlı senkron yol) başlangıcı ZATEN
  # yayınlar; yalnızca hiç yayınlanmamışsa şimdiki an kullanılır.
  yayinlanan_baslangic <- eski_start
  if (is.null(yayinlanan_baslangic) ||
      !inherits(yayinlanan_baslangic, "POSIXct") ||
      length(yayinlanan_baslangic) != 1L || is.na(yayinlanan_baslangic)) {
    yayinlanan_baslangic <- Sys.time()
  }
  options(mergen.pk.async.deadline_at = detail_config$pk_deadline_at,
          mergen.pk.async.cancel_token = detail_config$pk_cancel_token,
          mergen.pk.async.started_at = yayinlanan_baslangic)

  list(
    detail_config = detail_config,
    restore = function() {
      options(mergen.pk.async.deadline_at = eski_deadline,
              mergen.pk.async.cancel_token = eski_token,
              mergen.pk.async.started_at = eski_start)
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

  # BİLİNMEYEN DURUM KULLANICI İPTALİ SAYILMAZ: eski ikili dal (`deadline` değilse "kullanıcı iptali") yalnızca iki durum bilindiği varsayımına dayanıyordu; `pk_deep_halt_result()` HERHANGİ bir metni durum kabul ettiği için ileride eklenecek bir durum (ör. kaynak sınırı) kullanıcıya "siz iptal ettiniz" diye raporlanır, yani olmamış bir kullanıcı eylemi LLM bağlamına gerçek gibi yazılırdı.
  neden <- switch(
    durum,
    deadline = "süre sınırı",
    cancelled = "kullanıcı iptali",
    "bilinmeyen bir durdurma"
  )
  detail_config$pk_partial_halt_status <- durum
  detail_config$pk_partial_halt_note <- paste0(
    "UYARI: Bu derin analiz TAMAMLANMADI. Seçilen sorguların yalnızca ",
    completed_count, " tanesi çalıştırılabildi; kalanlar ", neden,
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
#
# KAPALI BAŞARISIZ OLUR: bu yardımcı, derin modun bozulmuş bir filtre planıyla
# TÜM yetkili küme üzerinden sessizce analiz yapmasını ENGELLEMEK için vardır.
# Politikanın kendisi eksik/hatalıysa `refuse = FALSE` dönmek, tam da ortadan
# kaldırmak istediği güvensiz tam-küme davranışını GERİ GETİRİRDİ. Bu yüzden
# eksik veya hata veren politika değerlendirmesi sorguyu REDDEDER.
pk_deep_filter_degraded_decision <- function(filter_status) {
  reddet <- function(mesaj) list(refuse = TRUE, message = as.character(mesaj)[1])

  if (!exists("pk_filter_degraded_gate", mode = "function", inherits = TRUE)) {
    return(reddet(paste0(
      "Filtre bozulma politikası değerlendirilemedi (politika yüklü değil); ",
      "sorgu güvenlik gereği atlandı."
    )))
  }

  kapi <- tryCatch(pk_filter_degraded_gate(filter_status), error = function(e) NULL)
  if (is.null(kapi) || !is.list(kapi)) {
    return(reddet(paste0(
      "Filtre bozulma politikası değerlendirilemedi; sorgu güvenlik gereği atlandı."
    )))
  }
  if (!isTRUE(kapi$refuse)) return(list(refuse = FALSE, message = NA_character_))

  list(
    refuse = TRUE,
    message = as.character(
      kapi$message %||% "Filtre planı üretilemedi; sorgu atlandı."
    )[1]
  )
}

# ------------------------------------------------------------------------------
# v1 ÇOKLU SORGU SEÇİMİ (bütçe + tavan kararı)
# ------------------------------------------------------------------------------
#' v1 çoklu seçiciyi KALAN BÜTÇEYLE ve DOĞRU TAVANLA çalıştır
#'
#' İki karar birlikte verilir:
#'
#'  1) TAVAN: birincil sorgunun metadata'sı ancak seçimden SONRA bilinir ve
#'     yapılandırma sözleşmesi ona EN YÜKSEK önceliği verir. Seçiciye yalnızca
#'     küresel tavanı vermek, sorgu-seviyesi bir `deep_max_queries` override'ının
#'     tavanı DÜŞÜREBİLİP ASLA YÜKSELTEMEMESİNE yol açardı. Bu yüzden seçim şema
#'     üst sınırına kadar aday üretir; kesin tavan çağıranda uygulanır.
#'
#'  2) BÜTÇE: seçici KENDİ sabit zaman aşımını kullanırdı. Kalan bütçe o
#'     zaman aşımından küçükse çağrı hiç GÖNDERİLMEZ; gönderildiğinde de ETKİN
#'     zaman aşımı KALAN BÜTÇEDİR (plan yalnızca evet/hayır kapısı değildir).
pk_deep_select_multi_queries <- function(user_prompt, query_library, session,
                                         detail_config, stop_check = NULL) {
  tavan <- max(pk_deep_max_queries(), pk_deep_max_queries_upper_bound())

  plan <- pk_sql_timeout_plan(
    12, pk_deadline_remaining_sec(detail_config$pk_deadline_at)
  )
  if (!isTRUE(plan$dispatch)) {
    cat("[DEEP_ANALYSIS] Kalan butce yok; coklu secici calistirilmadi.\n")
    return(NULL)
  }

  find_multiple_queries_with_ai(
    user_prompt, query_library, session,
    max_queries = tavan,
    timeout_sec = plan$timeout_sec,
    stop_check = stop_check
  )
}

# ------------------------------------------------------------------------------
# TİPLİ HALT SONUCU (sorgu içi iptal/son tarih)
# ------------------------------------------------------------------------------
# `execute_single_deep_query()` eskiden halt durumunda `NULL` dönüyordu; halt
# SON seçilen sorguda gerçekleştiğinde durum KAYBOLUYOR ve kısmi sonuç sıradan
# bir başarı gibi sunuluyordu.
pk_deep_halt_result <- function(status) {
  durum <- tryCatch(as.character(status)[1], error = function(e) NA_character_)
  if (length(durum) != 1L || is.na(durum) || !nzchar(durum)) durum <- "cancelled"
  structure(list(pk_halt_status = durum), class = "pk_deep_halt")
}

# HALT NEDENİ TİPLİ OKUNUR.
#
# `stop_check()` yalnızca boole döner ve İKİ ayrı nedeni (kullanıcının Durdur'u
# ile son tarih aşımı) tek değere indirger. `stop_check()` doğru olduğunda ham
# `"cancelled"` raporlamak, kullanıcının HİÇ durdurmadığı bir son tarih aşımını
# "siz iptal ettiniz" diye bildiriyordu; SQL katmanı ve kapı-sonrası dallar ise
# tipli durumu zaten koruyordu, yani aynı analizde iki farklı anlatım oluşuyordu.
# Kapının KENDİ durumu okunur; okunamazsa `pk_deep_halt_result()` eski
# `"cancelled"` varsayılanına düşer (davranış değişmez).
pk_deep_halt_status <- function() {
  if (!exists("pk_active_stage_halt_status", mode = "function", inherits = TRUE)) return(NA_character_)
  tryCatch(pk_active_stage_halt_status(), error = function(e) NA_character_)
}

pk_deep_is_halt_result <- function(result) {
  inherits(result, "pk_deep_halt") ||
    (is.list(result) && nzchar(as.character(result$pk_halt_status %||% "")[1]))
}

# v2 filtre yürütücüsünün UYGULAMA SONRASI kararı (çerçeve özniteliğinde).
.pk_deep_filter_v2_decision <- function(filtered_data) {
  if (!exists("PK_FILTER_V2_ATTR", inherits = TRUE)) return(list())
  karar <- tryCatch(attr(filtered_data, PK_FILTER_V2_ATTR, exact = TRUE),
                    error = function(e) NULL)
  if (!is.list(karar)) return(list())
  karar
}
