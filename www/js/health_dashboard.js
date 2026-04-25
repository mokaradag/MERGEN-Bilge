// ==============================================================================
// Dosya Yolu: www/js/health_dashboard.js
// Açıklama: Sistem Durumu sayfası için küçük istemci tarafı yardımcıları.
// ==============================================================================

(function() {
  var healthTooltipGuard = null;

  function removeHealthTooltips() {
    if (!window.jQuery) {
      return;
    }

    try {
      if (jQuery.fn && jQuery.fn.tooltip) {
        jQuery("[data-toggle='tooltip']").tooltip("hide");
        jQuery(".health-dashboard-container [data-toggle='tooltip']").tooltip("dispose");
      }
    } catch (e) {
      // Tooltip temizliği en iyi çaba ile yapılır; hata UI akışını durdurmamalıdır.
    }

    jQuery(".tooltip, .tooltip.show, .tooltip.fade").remove();
    jQuery("body").removeClass("tooltip-open");
  }

  function updateHealthTimestamp(message) {
    var time = message && message.time ? message.time : "--";
    var targetId = message && message.id ? message.id : "last_update_time";
    var target = document.getElementById(targetId) || document.getElementById("last_update_time");

    if (!target) {
      var candidates = document.querySelectorAll("span[id$='last_update_time']");
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
      trigger: "hover",
      delay: { show: 120, hide: 80 },
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

  function sendHealthPath(path, inputId) {
    if (!path || !window.Shiny || !Shiny.setInputValue) {
      return;
    }

    Shiny.setInputValue(inputId, {
      path: path,
      nonce: Date.now()
    }, { priority: "event" });
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
        sendHealthPath(path, inputId);
      });
  }

  function bindTooltipCleanup() {
    if (!window.jQuery) {
      return;
    }

    jQuery(document)
      .off("click.healthTooltipCleanup shown.bs.tab.healthTooltip hidden.bs.tab.healthTooltip mouseleave.healthTooltip mouseenter.healthTooltip")
      .on("click.healthTooltipCleanup", ".sidebar-menu a, .nav-tabs a, .nav-pills a, .health-dashboard-container button, .nav a", function() {
        removeHealthTooltips();
      })
      .on("mouseenter.healthTooltip", ".health-dashboard-container [data-toggle='tooltip']", function() {
        removeHealthTooltips();
      })
      .on("mouseleave.healthTooltip", ".health-dashboard-container [data-toggle='tooltip']", function() {
        removeHealthTooltips();
      })
      .on("shown.bs.tab.healthTooltip hidden.bs.tab.healthTooltip", "a[data-toggle='tab'], a[data-toggle='pill']", function() {
        removeHealthTooltips();
        window.setTimeout(initHealthTooltips, 140);
      });
  }

  function startTooltipGuard() {
    if (healthTooltipGuard) {
      window.clearInterval(healthTooltipGuard);
    }

    healthTooltipGuard = window.setInterval(function() {
      if (!document.querySelector(".health-dashboard-container")) {
        removeHealthTooltips();
        return;
      }

      var openTooltip = document.querySelector(".tooltip.show, .tooltip.in");
      var hoveredHealthElement = document.querySelector(".health-dashboard-container [data-toggle='tooltip']:hover");
      if (openTooltip && !hoveredHealthElement) {
        removeHealthTooltips();
      }
    }, 900);
  }

  function bootstrapHealthDashboard() {
    bindHealthPathButtons();
    bindTooltipCleanup();
    startTooltipGuard();
    window.setTimeout(initHealthTooltips, 250);
  }

  if (window.Shiny && Shiny.addCustomMessageHandler) {
    Shiny.addCustomMessageHandler("updateHealthTimestamp", updateHealthTimestamp);
    Shiny.addCustomMessageHandler("updateAdminTimestamp", updateHealthTimestamp);
    Shiny.addCustomMessageHandler("initHealthTooltips", function() {
      window.setTimeout(function() {
        bindHealthPathButtons();
        bindTooltipCleanup();
        initHealthTooltips();
      }, 80);
    });
    Shiny.addCustomMessageHandler("removeHealthTooltips", function() {
      removeHealthTooltips();
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", bootstrapHealthDashboard);
  } else {
    bootstrapHealthDashboard();
  }

  window.addEventListener("beforeunload", removeHealthTooltips);
  window.addEventListener("blur", removeHealthTooltips);
})();
