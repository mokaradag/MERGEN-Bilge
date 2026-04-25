// ==============================================================================
// Dosya Yolu: www/js/health_dashboard.js
// Açıklama: Sistem Durumu sayfası için küçük istemci tarafı yardımcıları.
// ==============================================================================

(function() {
  function removeHealthTooltips() {
    if (!window.jQuery || !jQuery.fn || !jQuery.fn.tooltip) {
      return;
    }

    try {
      jQuery(".health-dashboard-container [data-toggle='tooltip']").tooltip("hide").tooltip("dispose");
      jQuery(".tooltip").remove();
      jQuery("body").removeClass("tooltip-open");
    } catch (e) {
      jQuery(".tooltip").remove();
    }
  }

  function updateHealthTimestamp(message) {
    var time = message && message.time ? message.time : "--";
    var targetId = message && message.id ? message.id : "last_update_time";
    var target = document.getElementById(targetId) || document.getElementById("last_update_time");

    if (!target && targetId.indexOf("-") !== -1) {
      var suffix = targetId.split("-").pop();
      var candidates = document.querySelectorAll("span[id$='" + suffix + "']");
      if (candidates.length > 0) {
        target = candidates[0];
      }
    }

    if (target) {
      target.textContent = "Son Güncelleme: " + time;
    }
  }

  function initHealthTooltips() {
    if (!window.jQuery || !jQuery.fn || !jQuery.fn.tooltip) {
      return;
    }

    removeHealthTooltips();
    jQuery(".health-dashboard-container [data-toggle='tooltip']").tooltip({
      container: "body",
      trigger: "hover focus",
      delay: { show: 120, hide: 120 },
      placement: function(tip, element) {
        return jQuery(element).attr("data-placement") || "top";
      }
    });
  }

  function resolveHealthPathInputId(buttonElement) {
    var container = buttonElement.closest(".health-dashboard-container");
    if (container && container.getAttribute("data-health-path-input-id")) {
      return container.getAttribute("data-health-path-input-id");
    }
    return "health_module-open_health_path";
  }

  function bindHealthPathButtons() {
    if (!window.jQuery) {
      return;
    }

    jQuery(document)
      .off("click.healthPath", ".health-path-open-btn")
      .on("click.healthPath", ".health-path-open-btn", function(event) {
        event.preventDefault();
        event.stopPropagation();
        removeHealthTooltips();

        var path = this.getAttribute("data-health-path") || "";
        var inputId = resolveHealthPathInputId(this);
        if (path && inputId && window.Shiny && Shiny.setInputValue) {
          Shiny.setInputValue(inputId, {
            path: path,
            nonce: Date.now()
          }, { priority: "event" });
        }
      });
  }

  function bindTooltipCleanup() {
    if (!window.jQuery) {
      return;
    }

    jQuery(document)
      .off("click.healthTooltipCleanup shown.bs.tab.healthTooltip hidden.bs.tab.healthTooltip mouseleave.healthTooltip")
      .on("click.healthTooltipCleanup", ".sidebar-menu a, .nav-tabs a, .nav-pills a, .health-dashboard-container button", function() {
        removeHealthTooltips();
      })
      .on("mouseleave.healthTooltip", ".health-dashboard-container [data-toggle='tooltip']", function() {
        jQuery(this).tooltip("hide");
        jQuery(".tooltip").remove();
      })
      .on("shown.bs.tab.healthTooltip hidden.bs.tab.healthTooltip", "a[data-toggle='tab']", function() {
        removeHealthTooltips();
        window.setTimeout(initHealthTooltips, 120);
      });
  }

  if (window.Shiny && Shiny.addCustomMessageHandler) {
    Shiny.addCustomMessageHandler("updateHealthTimestamp", updateHealthTimestamp);
    Shiny.addCustomMessageHandler("updateAdminTimestamp", updateHealthTimestamp);
    Shiny.addCustomMessageHandler("initHealthTooltips", function() {
      window.setTimeout(initHealthTooltips, 80);
    });
    Shiny.addCustomMessageHandler("removeHealthTooltips", function() {
      removeHealthTooltips();
    });
  }

  document.addEventListener("DOMContentLoaded", function() {
    bindHealthPathButtons();
    bindTooltipCleanup();
    window.setTimeout(initHealthTooltips, 250);
  });

  window.addEventListener("beforeunload", removeHealthTooltips);
})();
