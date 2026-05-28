/* ==============================================================================
 * Dosya Yolu: www/js/console_error_probe.js
 * Açıklama: Boş/gizli görünen istemci tarafı konsol hatalarını yakalamak için
 *           erken yüklenen tanılama kancaları. Varsayılan olarak sessizdir;
 *           yalnızca localStorage MERGEN_DEBUG_CONSOLE_ERRORS=1 ise log yazar.
 * ============================================================================== */

(function() {
  'use strict';

  function mergenConsoleDebugEnabled() {
    try {
      return window.localStorage &&
        window.localStorage.getItem('MERGEN_DEBUG_CONSOLE_ERRORS') === '1';
    } catch (e) {
      return false;
    }
  }

  function mergenNormalizeError(value) {
    if (!value) return null;

    try {
      if (value.stack) return value.stack;
      if (value.message) return value.message;
      return String(value);
    } catch (e) {
      return '[Hata nesnesi okunamadı]';
    }
  }

  function mergenDebugLog(label, payload) {
    if (!mergenConsoleDebugEnabled()) return;

    try {
      console.log(label, payload);
    } catch (e) {
      /* Tanılama logu uygulama akışını bozmasın. */
    }
  }

	function mergenDescribeErrorTarget(target) {
	  if (!target || target === window) {
		return null;
	  }

	  var tagName = '';

	  try {
		tagName = target.tagName ? String(target.tagName).toLowerCase() : '';
	  } catch (e) {
		tagName = '';
	  }

	  var url = '';

	  try {
		url =
		  target.currentSrc ||
		  target.src ||
		  target.href ||
		  target.data ||
		  target.poster ||
		  '';
	  } catch (e) {
		url = '';
	  }

	  var id = '';
	  var className = '';

	  try {
		id = target.id || '';
		className = typeof target.className === 'string' ? target.className : '';
	  } catch (e) {
		id = '';
		className = '';
	  }

	  var html = '';

	  try {
		html = target.outerHTML ? String(target.outerHTML).slice(0, 500) : '';
	  } catch (e) {
		html = '';
	  }

	  return {
		tag: tagName,
		id: id,
		className: className,
		url: url,
		html: html
	  };
	}

	window.addEventListener('error', function(e) {
	  var targetInfo = mergenDescribeErrorTarget(e.target);

	  if (targetInfo) {
		// Boş message/source/line bilgisi çoğunlukla JS hatası değil,
		// yüklenemeyen resim, video, ses, CSS, JS veya benzeri bir varlıktır.
		mergenDebugLog('[MERGEN_DEBUG_RESOURCE_ERROR]', {
		  target: targetInfo
		});
		return;
	  }

	  // Gerçek JS çalışma zamanı hataları burada görünür.
	  mergenDebugLog('[MERGEN_DEBUG_ERROR]', {
		message: e.message || '',
		source: e.filename || '',
		line: e.lineno || 0,
		column: e.colno || 0,
		error: mergenNormalizeError(e.error)
	  });
	}, true);

  window.addEventListener('unhandledrejection', function(e) {
    mergenDebugLog('[MERGEN_DEBUG_PROMISE]', {
      reason: mergenNormalizeError(e.reason)
    });
  }, true);

  var nativeConsoleError = console.error;

  console.error = function() {
    var args = Array.prototype.slice.call(arguments);

    if (mergenConsoleDebugEnabled()) {
      try {
        nativeConsoleError.apply(
          console,
          ['[MERGEN_DEBUG_CONSOLE_ERROR_CALL]'].concat(args)
        );
      } catch (e) {
        /* Tanılama sarmalayıcısı sessiz kalmalı. */
      }
    }

    return nativeConsoleError.apply(console, args);
  };
})();