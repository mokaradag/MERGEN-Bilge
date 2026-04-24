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

  function initHealthTooltips() {
    if (!window.jQuery || !jQuery.fn || !jQuery.fn.tooltip) {
      return;
    }

    jQuery(".health-dashboard-container [data-toggle='tooltip']").tooltip("dispose").tooltip({
      container: "body",
      trigger: "hover",
      delay: { show: 120, hide: 250 },
      placement: function(tip, element) {
        return jQuery(element).attr("data-placement") || "top";
      }
    });
  }

  if (window.Shiny && Shiny.addCustomMessageHandler) {
    Shiny.addCustomMessageHandler("updateHealthTimestamp", updateHealthTimestamp);
    Shiny.addCustomMessageHandler("initHealthTooltips", function() {
      window.setTimeout(initHealthTooltips, 80);
    });
  }

  document.addEventListener("DOMContentLoaded", function() {
    window.setTimeout(initHealthTooltips, 250);
  });
})();
