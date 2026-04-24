// ==============================================================================
// Dosya Yolu: www/js/health_dashboard.js
// Açıklama: Sistem Durumu sayfası için küçük istemci tarafı yardımcıları.
// ==============================================================================

(function() {
  function updateHealthTimestamp(message) {
    var time = message && message.time ? message.time : "--";
    var targetId = message && message.id ? message.id : "last_update_time";
    var target = document.getElementById(targetId) || document.getElementById("last_update_time");
    if (target) {
      target.textContent = "Son Güncelleme: " + time;
    }
  }

  if (window.Shiny && Shiny.addCustomMessageHandler) {
    Shiny.addCustomMessageHandler("updateHealthTimestamp", updateHealthTimestamp);
  }
})();
