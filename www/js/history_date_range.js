// ==============================================================================
// Dosya Yolu: www/js/history_date_range.js
// Açıklama: Söyleşi Geçmişi tarih aralığını tarayıcı yerel tarih alanlarından
//           Shiny girdisine aktarır. Bootstrap datepicker bağımlılığı kullanmaz.
// ==============================================================================

(function() {
  'use strict';

  var handlerRegistered = false;

  function findContainerByInputId(inputId) {
    var containers = document.querySelectorAll(
      '.history-native-date-range[data-shiny-input-id]'
    );

    for (var i = 0; i < containers.length; i += 1) {
      if (containers[i].getAttribute('data-shiny-input-id') === inputId) {
        return containers[i];
      }
    }

    return null;
  }

  function emitRange(container) {
    if (!window.Shiny || !container) return;

    var inputId = container.getAttribute('data-shiny-input-id');
    if (!inputId) return;

    var startEl = container.querySelector('[data-history-date-role="start"]');
    var endEl = container.querySelector('[data-history-date-role="end"]');

    if (!startEl || !endEl) return;

    window.Shiny.setInputValue(
      inputId,
      [startEl.value || '', endEl.value || ''],
      { priority: 'event' }
    );
  }

  function initContainer(container) {
    if (!container || container.dataset.initialized === 'true') return;

    container.dataset.initialized = 'true';
    emitRange(container);
  }

  function initAll() {
    var containers = document.querySelectorAll(
      '.history-native-date-range[data-shiny-input-id]'
    );

    containers.forEach(initContainer);
  }

  function registerMessageHandler() {
    if (handlerRegistered || !window.Shiny || !window.Shiny.addCustomMessageHandler) {
      return;
    }

    handlerRegistered = true;

    window.Shiny.addCustomMessageHandler('history-date-range-set', function(message) {
      if (!message || !message.inputId) return;

      var container = findContainerByInputId(message.inputId);
      if (!container) return;

      var startEl = container.querySelector('[data-history-date-role="start"]');
      var endEl = container.querySelector('[data-history-date-role="end"]');

      if (!startEl || !endEl) return;

      startEl.value = message.start || '';
      endEl.value = message.end || '';

      emitRange(container);
    });
  }

  document.addEventListener('DOMContentLoaded', function() {
    initAll();
    registerMessageHandler();
  });

  if (window.jQuery) {
    window.jQuery(document).on('shiny:connected', function() {
      initAll();
      registerMessageHandler();
    });
  }

  document.addEventListener('input', function(event) {
    var target = event.target;
    if (!target || !target.matches('.history-native-date-range [data-history-date-role]')) {
      return;
    }

    emitRange(target.closest('.history-native-date-range'));
  });

  document.addEventListener('change', function(event) {
    var target = event.target;
    if (!target || !target.matches('.history-native-date-range [data-history-date-role]')) {
      return;
    }

    emitRange(target.closest('.history-native-date-range'));
  });

  initAll();
  registerMessageHandler();
})();