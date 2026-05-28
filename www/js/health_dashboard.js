// ==============================================================================
// Dosya Yolu: www/js/health_dashboard.js
// Açıklama: Sistem Durumu sayfası için küçük istemci tarafı yardımcıları.
// ==============================================================================

(function() {
  function removeHealthTooltips() {
    if (window.jQuery) {
      try {
        if (jQuery.fn && jQuery.fn.tooltip) {
          jQuery(".health-dashboard-container [data-toggle='tooltip']").tooltip("hide").tooltip("dispose");
          jQuery(".health-dashboard-container [title]").removeAttr("data-original-title");
        }
      } catch (e) {
        // Tooltip temizliği en iyi çaba ile yapılır.
      }
      jQuery(".tooltip, .tooltip.show, .tooltip.fade, .tooltip.in").remove();
      jQuery("body").removeClass("tooltip-open");
    }
  }

  function initHealthTooltips() {
    // Sağlık sayfasında Bootstrap tooltip yerine CSS tabanlı data-health-tooltip kullanılır.
    // Böylece otomatik yenileme sırasında body üzerinde kalan donmuş .tooltip düğümleri oluşmaz.
    removeHealthTooltips();
  }

  function showCopyToast(message, type) {
    var toast = document.createElement("div");
    toast.className = "health-copy-toast " + (type || "success");
    toast.textContent = message;
    document.body.appendChild(toast);

    window.setTimeout(function() {
      toast.classList.add("show");
    }, 20);

    window.setTimeout(function() {
      toast.classList.remove("show");
      window.setTimeout(function() {
        if (toast.parentNode) {
          toast.parentNode.removeChild(toast);
        }
      }, 260);
    }, 2400);
  }

  function fallbackCopyText(text) {
    var textArea = document.createElement("textarea");
    textArea.value = text;
    textArea.setAttribute("readonly", "readonly");
    textArea.style.position = "fixed";
    textArea.style.left = "-9999px";
    textArea.style.top = "-9999px";
    document.body.appendChild(textArea);
    textArea.focus();
    textArea.select();

    var ok = false;
    try {
      ok = document.execCommand("copy");
    } catch (e) {
      ok = false;
    }

    document.body.removeChild(textArea);
    return ok;
  }

  function copyTextToClipboard(text) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text).then(function() {
        return true;
      }).catch(function() {
        return fallbackCopyText(text);
      });
    }

    return Promise.resolve(fallbackCopyText(text));
  }

  function bindHealthPathButtons() {
    if (!window.jQuery) {
      return;
    }

    jQuery(document)
      .off("click.healthPath", ".health-path-copy-btn")
      .on("click.healthPath", ".health-path-copy-btn", function(event) {
        event.preventDefault();
        event.stopPropagation();
        removeHealthTooltips();

        var path = this.getAttribute("data-health-path") || "";
        if (!path) {
          showCopyToast("Kopyalanacak yol bulunamadı.", "error");
          return;
        }

        copyTextToClipboard(path).then(function(ok) {
          if (ok) {
            showCopyToast("Klasör yolu panoya kopyalandı. Windows Dosya Gezgini adres çubuğuna yapıştırıp Enter'a basın.", "success");
          } else {
            showCopyToast("Yol otomatik kopyalanamadı. Lütfen yolu elle seçip kopyalayın.", "error");
          }
        });
      });
  }

  function bindTooltipCleanup() {
    if (!window.jQuery) {
      return;
    }

    jQuery(document)
      .off("click.healthTooltipCleanup mouseleave.healthTooltip mouseenter.healthTooltip shown.bs.tab.healthTooltip hidden.bs.tab.healthTooltip")
      .on("click.healthTooltipCleanup", ".sidebar-menu a, .nav-tabs a, .nav-pills a, .nav a, .health-dashboard-container button", function() {
        removeHealthTooltips();
      })
      .on("mouseenter.healthTooltip", ".health-dashboard-container [data-health-tooltip]", function() {
        removeHealthTooltips();
      })
      .on("mouseleave.healthTooltip", ".health-dashboard-container [data-health-tooltip]", function() {
        removeHealthTooltips();
      })
      .on("shown.bs.tab.healthTooltip hidden.bs.tab.healthTooltip", "a[data-toggle='tab'], a[data-toggle='pill']", function() {
        removeHealthTooltips();
      });
  }

  function startTooltipGuard() {
    window.setInterval(function() {
      removeHealthTooltips();
    }, 1500);
  }

  function bootstrapHealthDashboard() {
    bindHealthPathButtons();
    bindTooltipCleanup();
    startTooltipGuard();
    removeHealthTooltips();
  }

  if (window.Shiny && Shiny.addCustomMessageHandler) {
    Shiny.addCustomMessageHandler("initHealthTooltips", function(message) {
      // Shiny yeni sürümlerde handler fonksiyonunun tek argüman almasını bekler.
      // Bu mesajda içerik kullanılmıyor; argüman sadece Shiny sözleşmesini korumak içindir.
      window.setTimeout(function() {
        bootstrapHealthDashboard();
        initHealthTooltips();
      }, 80);
    });

    Shiny.addCustomMessageHandler("removeHealthTooltips", function(message) {
      // Shiny mesaj içeriği kullanılmıyor; tek argüman sözleşme uyumu içindir.
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