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
