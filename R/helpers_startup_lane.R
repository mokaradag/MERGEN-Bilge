# R/helpers_startup_lane.R
# Dosya Yolu: R/helpers_startup_lane.R
# Açıklama: Başlangıç deneyimi şeridi (startup lane) çözümleme yardımcıları.
#   İki şerit vardır:
#     - "fast_lane"  : Hızlı Başlangıç. Sinematik giriş, medya ön yükleme ve
#                      açılış müziği atlanır; kullanıcı doğrudan Ana Söyleşi'ye
#                      iner. Özellik SİLİNMEZ; yalnızca açılış yükü ertelenir.
#     - "rich_lane"  : Zengin Deneyim. Mevcut derin uzay girişi, Keşfet akışı,
#                      deneyim modları ve medya ön yükleme davranışı korunur.
#   Üçüncü değer "ask_once" bir şerit değildir: kayıtlı tercih yoksa ilk
#   açılışta kullanıcıya tek seferlik şerit seçici gösterilmesini ifade eder.
#
#   Tercih öncelik sırası:
#     1) Kullanıcının kayıtlı tercihi (localStorage mergen_settings.startup_lane)
#     2) MERGEN_STARTUP_LANE ortam değişkeni (dağıtım varsayılanı)
#     3) "ask_once" (ilk açılışta seçici göster)
#
#   Bu dosya saf karar yardımcılarından oluşur: Shiny/reaktif erişim, DB, ağ
#   veya dosya sistemi yan etkisi içermez. İstemci tarafındaki eşleniği
#   www/js/app_loading_lane.js dosyasıdır; iki taraf aynı sözleşmeyi paylaşır.

#' Geçerli başlangıç şeridi değerleri
#' @return Karakter vektörü: fast_lane, rich_lane, ask_once
mergen_startup_lane_values <- function() {
  c("fast_lane", "rich_lane", "ask_once")
}

#' Başlangıç şeridi değerini normalleştir
#' @description Serbest biçimli bir değeri kanonik şerit değerine çevirir.
#'   Bilinen kısa takma adlar tolere edilir; geçersiz/boş değerler güvenli
#'   biçimde varsayılana düşer.
#' @param value Ham değer (karakter/liste öğesi olabilir)
#' @param default Geçersiz değerde dönülecek kanonik değer
#' @return "fast_lane", "rich_lane" veya "ask_once"
mergen_normalize_startup_lane <- function(value, default = "ask_once") {
  if (!default %in% mergen_startup_lane_values()) {
    default <- "ask_once"
  }

  if (is.null(value) || length(value) < 1L) {
    return(default)
  }

  value <- value[[1]]
  if (is.list(value) || (!is.character(value) && !is.factor(value))) {
    value <- tryCatch(as.character(value), error = function(e) "")
  }
  value <- tolower(trimws(as.character(value)[1]))

  if (is.na(value) || !nzchar(value)) {
    return(default)
  }

  switch(
    value,
    "fast_lane" = "fast_lane",
    "fast"      = "fast_lane",
    "hizli"     = "fast_lane",
    "rich_lane" = "rich_lane",
    "rich"      = "rich_lane",
    "normal"    = "rich_lane",
    "zengin"    = "rich_lane",
    "ask_once"  = "ask_once",
    "ask"       = "ask_once",
    default
  )
}

#' Ortam değişkeninden dağıtım varsayılan şeridini oku
#' @param env_value Test edilebilirlik için enjekte edilebilir ham değer
#' @return Kanonik şerit değeri; ayarlanmamış/geçersizse "ask_once"
mergen_startup_lane_env_default <- function(env_value = Sys.getenv("MERGEN_STARTUP_LANE", "")) {
  mergen_normalize_startup_lane(env_value, default = "ask_once")
}

#' Etkin başlangıç şeridini çöz
#' @description Kayıtlı kullanıcı tercihi önceliklidir; yoksa ortam varsayılanı
#'   kullanılır. İkisi de kesin bir şerit vermiyorsa "ask_once" döner (ilk
#'   açılış seçicisi gösterilir).
#' @param stored Kayıtlı kullanıcı tercihi (NULL olabilir)
#' @param env_default Ortam varsayılanı (kanonik değer)
#' @return "fast_lane", "rich_lane" veya "ask_once"
mergen_resolve_startup_lane <- function(stored = NULL,
                                        env_default = mergen_startup_lane_env_default()) {
  stored_lane <- mergen_normalize_startup_lane(stored, default = "ask_once")
  if (stored_lane %in% c("fast_lane", "rich_lane")) {
    return(stored_lane)
  }

  env_lane <- mergen_normalize_startup_lane(env_default, default = "ask_once")
  if (env_lane %in% c("fast_lane", "rich_lane")) {
    return(env_lane)
  }

  "ask_once"
}

#' Şerit Hızlı Başlangıç mı?
#' @param lane Şerit değeri
#' @return TRUE yalnızca kanonik "fast_lane" için
mergen_startup_lane_is_fast <- function(lane) {
  identical(mergen_normalize_startup_lane(lane, default = "ask_once"), "fast_lane")
}

#' Hızlı Başlangıç hazır-olma sözleşmesi (istemci kapanış anahtarları)
#' @description Hızlı şeritte açılış katmanı yalnızca sohbet kabuğunun
#'   hazır olmasını bekler: bağlantı, kimlik ve Ana Söyleşi istemci
#'   bileşenleri. Kayıtlı sohbetler, dosya indeksi, galeri ve medya ön
#'   yüklemesi bu sözleşmenin PARÇASI DEĞİLDİR (arka planda sürebilir).
#'   www/js/app_loading.js içindeki FAST_LANE_REQUIRED listesi ile aynı
#'   olmalıdır.
#' @return Karakter vektörü (kontrol noktası anahtarları)
mergen_fast_lane_required_boot_keys <- function() {
  c("connect", "auth_ready", "welcome_client_ready")
}

#' Zengin Deneyim hazır-olma sözleşmesi (sunucu zorunlu kontrol noktaları)
#' @description R/module_boot_readiness.R içindeki varsayılan zorunlu küme ile
#'   aynıdır; zengin şeritte açılış katmanı yalnızca sunucu ready=TRUE
#'   bildirdiğinde kapanır.
#' @return Karakter vektörü (kontrol noktası anahtarları)
mergen_rich_lane_required_boot_keys <- function() {
  c(
    "auth_ready",
    "saved_chats_preview_ready",
    "file_index_ready",
    "character_media_ready",
    "welcome_client_ready"
  )
}
