// www/js/deep_space_intro_lifecycle.js
// Dosya Yolu: www/js/deep_space_intro_lifecycle.js
// Açıklama: Derin uzay giriş animasyonu için zamanlayıcı, resize rAF ve
// otomatik başlatma yaşam döngüsü sınırı. Sahne/Three.js kurulumuna dokunmaz;
// yalnızca stale callback ve teardown sahipliğini tek yerde toplar.

window.DeepSpaceIntroLifecycle = (function() {
  'use strict';

  function createTimers() {
    var timeoutIds = [];
    var rafIds = [];

    function trackTimeout(callback, delay) {
      var timeoutId = window.setTimeout(function() {
        forget(timeoutIds, timeoutId);
        callback();
      }, delay);
      timeoutIds.push(timeoutId);
      return timeoutId;
    }

    function clearTrackedTimeout(timeoutId) {
      if (!timeoutId) return;
      window.clearTimeout(timeoutId);
      forget(timeoutIds, timeoutId);
    }

    function trackRaf(callback) {
      var rafId = window.requestAnimationFrame(function(timestamp) {
        forget(rafIds, rafId);
        callback(timestamp);
      });
      rafIds.push(rafId);
      return rafId;
    }

    function cancelTrackedRaf(rafId) {
      if (!rafId) return;
      window.cancelAnimationFrame(rafId);
      forget(rafIds, rafId);
    }

    function cancelAll() {
      timeoutIds.forEach(function(timeoutId) {
        window.clearTimeout(timeoutId);
      });
      rafIds.forEach(function(rafId) {
        window.cancelAnimationFrame(rafId);
      });
      timeoutIds = [];
      rafIds = [];
    }

    return {
      trackTimeout: trackTimeout,
      clearTrackedTimeout: clearTrackedTimeout,
      trackRaf: trackRaf,
      cancelTrackedRaf: cancelTrackedRaf,
      cancelAll: cancelAll
    };
  }

  function forget(ids, id) {
    var index = ids.indexOf(id);
    if (index >= 0) {
      ids.splice(index, 1);
    }
  }

  function shouldSkipIntro(storage) {
    try {
      var raw = storage.getItem('mergen_settings');
      if (!raw) return false;
      var settings = JSON.parse(raw);
      return settings.skip_intro === true;
    } catch (e) {
      return false;
    }
  }

  function autoInit(options) {
    options = options || {};
    var storage = options.storage || window.localStorage;
    var documentRef = options.document || document;
    var manager = options.manager || window.DeepSpaceIntro;
    var containerId = options.containerId || 'deep-space-canvas';
    var texturePath = options.texturePath || 'lib/threejs/textures/';

    if (shouldSkipIntro(storage)) return false;

    var container = documentRef.getElementById(containerId);
    if (container && manager && !manager.isActive()) {
      manager.init(containerId, {
        texturePath: texturePath
      });
      return true;
    }

    return false;
  }

  function bindAutoInit(options) {
    options = options || {};
    var documentRef = options.document || document;
    var callback = function() {
      autoInit(options);
    };

    if (documentRef.readyState === 'loading') {
      documentRef.addEventListener('DOMContentLoaded', callback, { once: true });
    } else {
      callback();
    }
  }

  return {
    createTimers: createTimers,
    shouldSkipIntro: shouldSkipIntro,
    autoInit: autoInit,
    bindAutoInit: bindAutoInit
  };
})();
