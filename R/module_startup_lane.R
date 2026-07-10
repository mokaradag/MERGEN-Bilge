# R/module_startup_lane.R
# Dosya Yolu: R/module_startup_lane.R
# Açıklama: Başlangıç şeridi (startup lane) sunucu gözlemcileri. İstemci
#   çözümleyicisi (www/js/app_loading_lane.js) şeridi belirler; burada:
#     1) Şerit çözülene dek intro kararı BEKLETİLİR (seçici açıkken Three.js/
#        derin uzay sahnesi başlatılmaz), sonra startup_skip_intro gönderilir.
#        Hızlı Başlangıç intro'yu her zaman atlar; zengin şeritte eski
#        skip_intro tercihi aynen uygulanır.
#     2) Çözülen şerit oturuma (session$userData$startup_lane) ve ayarlara
#        (settings_data$startup_lane) işlenir.
#     3) Hızlı şeritte istemci medya ön yüklemesi hiç başlamayacağı için
#        character_media_ready kontrol noktası 'ertelendi' olarak işaretlenir;
#        sunucu hazır-olma sözleşmesi dürüst biçimde tamamlanır.
#   R/module_startup_screen.R bu dosyadaki startupLaneObserversInit()
#   fonksiyonunu çağırır; saf şerit çözümleme yardımcıları
#   R/helpers_startup_lane.R içindedir.

#' Başlangıç Şeridi Gözlemcilerini Başlat
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param settings_data Ayarlar modülünden dönen reaktif ayarlar
#' @param boot_ready Boot hazır-olma koordinatörü (opsiyonel)
startupLaneObserversInit <- function(input, session, settings_data, boot_ready = NULL) {

  # Şerit çözümü + intro kararı köprüsü. Şerit API'si yoksa (savunmacı geriye
  # dönük uyum) eski localStorage skip_intro davranışı birebir korunur.
  session$onFlushed(function() {
    shinyjs::runjs("
      (function() {
        function readLegacySkip() {
          try {
            var raw = localStorage.getItem('mergen_settings');
            if (raw) {
              var s = JSON.parse(raw);
              if (s.skip_intro === true) return true;
            }
          } catch(e) {}
          return false;
        }
        function sendSkip(skip) {
          Shiny.setInputValue('startup_skip_intro', skip === true, {priority: 'event'});
        }
        if (window.MergenStartupLane &&
            typeof window.MergenStartupLane.whenResolved === 'function') {
          window.MergenStartupLane.whenResolved(function(lane) {
            var src = 'stored';
            try {
              if (typeof window.MergenStartupLane.getSource === 'function' &&
                  window.MergenStartupLane.getSource()) {
                src = window.MergenStartupLane.getSource();
              }
            } catch(e) {}
            Shiny.setInputValue('startup_lane_resolved', {
              lane: lane,
              source: src,
              ts: Date.now()
            }, {priority: 'event'});
            sendSkip(lane === 'fast_lane' ? true : readLegacySkip());
          });
          return;
        }
        // Şerit API'si yok: eski davranış. Sunucu şerit kapısı için yine de
        // rich_lane bildirilir; aksi halde kayıtlı sohbet yüklemesi bekler.
        Shiny.setInputValue('startup_lane_resolved', {
          lane: 'rich_lane',
          source: 'legacy_no_api',
          ts: Date.now()
        }, {priority: 'event'});
        sendSkip(readLegacySkip());
      })();
    ")
  }, once = TRUE)

  # Çözülen şeridi oturum/ayar durumuna işle ve hızlı şeritte ertelenen
  # medya kontrol noktasını (idempotent) işaretle.
  observeEvent(input$startup_lane_resolved, {
    payload <- input$startup_lane_resolved
    lane_raw <- if (is.list(payload)) payload$lane else payload
    lane <- mergen_normalize_startup_lane(lane_raw, default = "rich_lane")
    if (identical(lane, "ask_once")) lane <- "rich_lane"

    # Çözüm kaynağı: "stored" / "selector" gerçek kullanıcı tercihidir;
    # "env_default" dağıtım varsayılanıdır ve KULLANICI TERCİHİ OLARAK
    # AYAR DURUMUNA YAZILMAZ. Aksi halde save_all_settings() ilgisiz bir
    # kaydetmede dağıtım varsayılanını localStorage'a kalıcılaştırır ve
    # operatörün sonraki varsayılan değişikliklerini geçersiz kılardı.
    lane_source <- if (is.list(payload)) as.character(payload$source %||% "stored")[1] else "stored"
    user_choice <- lane_source %in% c("stored", "selector")

    session$userData$startup_lane <- lane
    if (user_choice && !is.null(settings_data)) {
      settings_data$startup_lane <- lane
    }
    cat(sprintf("[STARTUP] Başlangıç şeridi çözüldü: %s (kaynak: %s)\n", lane, lane_source))

    if (identical(lane, "fast_lane") &&
        !is.null(boot_ready) && is.function(boot_ready$mark)) {
      boot_ready$mark(
        "character_media_ready",
        "Hızlı başlangıç: zengin medya ertelendi",
        detail = list(deferred = TRUE, lane = "fast_lane")
      )
    }
  }, ignoreInit = TRUE)

  invisible(NULL)
}

#' Kaydedilen Başlangıç Deneyimi şeridini uygula
#' @description "Ayarları Kaydet" akışından (save_all_settings) çağrılır:
#'   Yapılandırma sayfasındaki radyo seçimi bekleyen (pending) durumda tutulur
#'   ve YALNIZCA bu noktada gerçek yapılandırmaya işlenir. Geçersiz/boş bekleyen
#'   değer veya değişmeyen şerit no-op'tur. localStorage kalıcılaştırması
#'   save_all_settings() içindeki toplu saveSettings mesajıyla yapılır
#'   (settings$startup_lane, reactiveValuesToList çıktısına zaten dahildir);
#'   burada ek olarak canlı istemci şerit durumu (html sınıfı) güncellenir.
#' @param session Shiny session nesnesi
#' @param settings Merkezi ayarlar reactiveValues nesnesi
#' @param pending_lane Bekleyen şerit değeri (temp_startup_lane())
#' @return TRUE şerit değişti/uygulandı; FALSE no-op
mergen_apply_saved_startup_lane <- function(session, settings, pending_lane) {
  lane <- mergen_normalize_startup_lane(pending_lane, default = "ask_once")
  if (!lane %in% c("fast_lane", "rich_lane")) {
    return(invisible(FALSE))
  }

  if (identical(shiny::isolate(settings$startup_lane), lane)) {
    return(invisible(FALSE))
  }

  settings$startup_lane <- lane
  session$sendCustomMessage("applyStartupLane", list(lane = lane))
  cat(sprintf("[SETTINGS] Başlangıç deneyimi kaydedildi: %s (açılışta tam uygulanır)\n", lane))
  invisible(TRUE)
}
