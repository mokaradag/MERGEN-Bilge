/* ============================================================
 * Dosya: www/js/api_key_password_toggle.js
 * Açıklama: API anahtarı parola alanları için ortak göster/gizle
 *           düğmesi. Olay delegasyonu kullanır; dinamik Shiny modal
 *           içerikleri yeniden çizildiğinde de çalışır.
 *
 *           Güvenlik notu: Bu dosya API anahtarı değerini okumaz,
 *           saklamaz, loglamaz veya başka bir yere göndermez. Yalnızca
 *           input type değerini "password" / "text" arasında değiştirir.
 * ============================================================ */

(function () {
  "use strict";

  var FIELD_SELECTOR = "[data-api-key-password-field]";
  var INPUT_SELECTOR = 'input[data-api-key-password-input="1"]';
  var TOGGLE_SELECTOR = "[data-api-key-password-toggle]";

  function closestToggle(target) {
    if (!target || typeof target.closest !== "function") {
      return null;
    }
    return target.closest(TOGGLE_SELECTOR);
  }

  function setIcon(button, visible) {
    var icon = button.querySelector(".fa, .fas");
    if (!icon || !icon.classList) {
      return;
    }

    icon.classList.remove("fa-eye", "fa-eye-slash");
    icon.classList.add(visible ? "fa-eye" : "fa-eye-slash");
  }

  function setAccessibleState(button, visible) {
    var label = visible ?
      "API anahtarı görünür; gizlemek için tıklayın" :
      "API anahtarı gizli; göstermek için tıklayın";
    var title = visible ? "API anahtarı görünür" : "API anahtarı gizli";
    var text = button.querySelector(".api-key-password-toggle-text");

    button.setAttribute("aria-label", label);
    button.setAttribute("aria-pressed", visible ? "true" : "false");
    button.setAttribute("title", title);

    if (text) {
      text.textContent = label;
    }
  }

  function togglePasswordVisibility(button) {
    var field = button.closest(FIELD_SELECTOR);
    if (!field) {
      return;
    }

    var input = field.querySelector(INPUT_SELECTOR);
    if (!input) {
      return;
    }

    var showPlainText = input.type === "password";
    input.type = showPlainText ? "text" : "password";

    setIcon(button, showPlainText);
    setAccessibleState(button, showPlainText);

    try {
      input.focus({ preventScroll: true });
    } catch (e) {
      input.focus();
    }
  }

  document.addEventListener(
    "click",
    function (event) {
      var button = closestToggle(event.target);
      if (!button) {
        return;
      }

      event.preventDefault();
      togglePasswordVisibility(button);
    },
    true
  );
})();