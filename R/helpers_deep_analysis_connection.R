# ==============================================================================
# Dosya Yolu: R/helpers_deep_analysis_connection.R
# Açıklama: Derin Düşünme yolunun BİRİNCİL DB BAĞLANTISI YAŞAM DÖNGÜSÜ: korumalı
#           edinme, idempotent bırakma ve telemetri için kısa ömürlü sağlayıcı.
#
# `R/helpers_deep_analysis_reconcile.R` içinden BÖLÜNMÜŞTÜR: orası PAKET SEVİYESİ
# uzlaştırma (köken, çapraz-sorgu aritmetiği yasağı, gözlem fabrikası) sahibidir
# ve 293/19 bakım tavanına dayanmıştı. Bırakıcı ile sağlayıcı zaten bu dosyanın
# sorumluluğuydu; edinme kapısı da AYNI yaşam döngüsünün parçası olduğu için
# üçü birlikte buraya taşınmıştır. Orkestratör (`R/helpers_deep_analysis.R`) bu
# sınırı yalnızca ÇAĞIRIR, kendi içinde tekrarlamaz.
#
# Manifest sırası ZORUNLUDUR: bu dosya `helpers_deep_analysis_reconcile.R`'den
# ÖNCE, `helpers_deep_analysis_sql.R`'den SONRA yüklenir.
#
# Dosya saf DEĞİLDİR (DB bağlantısı açar/kapatır) ama Shiny/reaktif bağımlılığı
# YOKTUR: worker bootstrap'ından da güvenle yüklenir.
# ==============================================================================

#' Yetki okuması için BİRİNCİL bağlantıyı KORUMALI al.
#'
#' `get_connection()` hata fırlattığında (havuz tükenmesi, sürücü/DSN hatası) ham
#' R hatası `pk_deep_analysis_process()` dışına sızıyor ve o fonksiyonun diğer
#' TÜM hata yolları gibi tipli Türkçe mesaj dönmüyordu. `NULL` döndüğünde ise
#' `conn_list$conn` `NULL` oluyor ve `get_user_rls_info()` GEÇERSİZ tutamaçla
#' çağrılıp yetki okuması tipsiz biçimde başarısız oluyordu.
#' `execute_single_deep_query()` aynı çağrıyı zaten korumalı yapar; bu yardımcı
#' aynı sözleşmeyi orkestratörün birincil bağlantısına taşır.
#'
#' @param connect_fn Test/izolasyon için enjekte edilebilir bağlantı fabrikası.
#' @return `list(conn = , conn_list = , message = )`. `conn` `NULL` ise `message`
#'   kullanıcıya gösterilecek tipli Türkçe metindir.
pk_deep_acquire_primary_connection <- function(connect_fn = NULL) {
  if (is.null(connect_fn) && exists("get_connection", mode = "function", inherits = TRUE)) {
    connect_fn <- get("get_connection", mode = "function", inherits = TRUE)
  }

  conn_list <- if (is.function(connect_fn)) {
    tryCatch(connect_fn(), error = function(e) {
      # Ham sürücü metni DSN/sunucu/kullanıcı taşıyabilir; redaktör yoksa yazılmaz.
      cat(sprintf("[DEEP_ANALYSIS] Birincil baglanti alinamadi: %s\n",
                  if (exists("pk_safe_log_text", mode = "function", inherits = TRUE)) {
                    pk_safe_log_text(conditionMessage(e))
                  } else "(ayrinti gizlendi)"))
      NULL
    })
  } else {
    NULL
  }

  conn <- if (is.list(conn_list)) conn_list$conn else NULL
  if (is.null(conn)) {
    return(list(conn = NULL, conn_list = NULL, message = paste0(
      "\U000026A0\U0000FE0F **Veritabanı Bağlantısı Kurulamadı:** ",
      "Analiz için gerekli veritabanı bağlantısı alınamadı. ",
      "Lütfen daha sonra tekrar deneyin."
    )))
  }
  list(conn = conn, conn_list = conn_list, message = NULL)
}

#' Birincil bağlantı için İDEMPOTENT bırakıcı: çekirdek onu RLS okumasından
#' hemen sonra bırakır ama hata yolları için `on.exit` da kurar.
pk_deep_primary_connection_release <- function(conn_list) {
  durum <- new.env(parent = emptyenv())
  durum$serbest <- FALSE

  list(release = function() {
    if (isTRUE(durum$serbest)) return(invisible(FALSE))
    durum$serbest <- TRUE
    try(release_connection(conn_list), silent = TRUE)
    invisible(TRUE)
  })
}

#' Telemetri için KISA ÖMÜRLÜ bağlantı sağlayıcısı: her gözlem kendi
#' bağlantısını açıp hemen bırakır, böylece derin analiz boyunca kullanılmayan
#' bir birincil bağlantı tutulmaz. Açılamazsa `NULL` (telemetri fail-soft'tur).
pk_deep_short_lived_conn_provider <- function() {
  function() {
    liste <- tryCatch(get_connection(), error = function(e) NULL)
    if (!is.list(liste)) return(NULL)
    list(conn = liste$conn, release = function() release_connection(liste))
  }
}
