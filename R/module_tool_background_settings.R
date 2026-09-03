# ============================================================
# Başlık: Araç Arka Plan Animasyonları Ayar Yardımcıları
# Dosya: R/module_tool_background_settings.R
# Açıklama: "Araç Arka Plan Animasyonları" yapılandırma ayarının sunucu
#           tarafındaki yardımcılarını barındırır. Ayar değişikliği
#           istemciye toggleToolBackgrounds custom message ile bildirilir;
#           böylece sohbet ekranındaki heptagon + bağlam parçacığı katmanı
#           anında açılıp kapatılır. UI ve mevcut settings altyapısıyla
#           çakışmaması için bu dosya yalnızca küçük yardımcılar sağlar.
# ============================================================

#' Tool background özelliğinin varsayılan açık/kapalı durumu
#'
#' @description Varsayılan olarak araç arka plan animasyonları AÇIK gelir.
#'   Kurumsal kullanım için sade görünüm tercih edilirse Yapılandırma sayfasından
#'   kapatılabilir.
#'
#' @return Mantıksal değer
mb_tool_bg_default_enabled <- function() {
  TRUE
}

#' Yüklenen ayar bilgisinden tool background değerini çöz
#'
#' @description settings$loaded_settings veya mergen_settings JSON'unda
#'   "enable_tool_backgrounds" bayrağını güvenli şekilde çözümler. Geçersiz
#'   veya eksik değerlerde varsayılana düşer.
#'
#' @param value Yüklenmiş ayar değeri (mantıksal/numerik/karakter olabilir)
#' @param default Varsayılan değer
#' @return Mantıksal değer
mb_tool_bg_coerce_enabled <- function(value, default = mb_tool_bg_default_enabled()) {
  if (is.null(value)) return(isTRUE(default))
  if (length(value) == 0L) return(isTRUE(default))
  v <- value[[1]]
  if (is.logical(v) && !is.na(v)) return(isTRUE(v))
  if (is.numeric(v) && !is.na(v)) return(v > 0)
  if (is.character(v) && nzchar(v)) {
    lc <- tolower(trimws(v))
    if (lc %in% c("true", "1", "yes", "on")) return(TRUE)
    if (lc %in% c("false", "0", "no", "off")) return(FALSE)
  }
  isTRUE(default)
}

#' Araç arka plan ayarını istemciye uygula
#'
#' @description Yapılandırma sayfasındaki "Araç Arka Plan Animasyonları"
#'   tercihi değiştiğinde sohbet sayfası arka plan animasyon katmanını
#'   istemci tarafında anında açar/kapatır. localStorage senkronizasyonu
#'   da burada yapılır.
#'
#' @param session Shiny oturumu
#' @param enabled Mantıksal değer
mb_tool_bg_apply_to_client <- function(session, enabled) {
  if (is.null(session)) return(invisible(NULL))
  flag <- isTRUE(enabled)
  tryCatch({
    session$sendCustomMessage(
      "toggleToolBackgrounds",
      list(enabled = flag)
    )
  }, error = function(e) {
    # Sessiz geç: SSO bağlanma sürecinde session erişimi henüz tam değilse
    invisible(NULL)
  })
  invisible(NULL)
}
