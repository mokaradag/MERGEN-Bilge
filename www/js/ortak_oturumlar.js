/* ==========================================================================
 * Dosya: www/js/ortak_oturumlar.js
 * Açıklama: Ortak Oturumlar istemci köprüsü.
 *   - data-oo-hedef-input taşıyan butonlar için delege tıklama: hedef Shiny
 *     input'una {id, nonce} yazar (dinamik DT/renderUI yüzeylerinde güvenli).
 *   - Canlı durum kalp atışı: 30 sn'de bir sunucuya sayfa bilgisiyle bildirir
 *     (sunucu tarafı ayrıca 20 sn kısma uygular).
 * Not: Dosya adları/kimlikler CSS seçicisine ASLA enterpolasyonla gömülmez;
 * değerler dataset üzerinden düz metin olarak okunur (seçici güvenliği).
 * ========================================================================== */

(function () {
  'use strict';

  var OO_HEARTBEAT_MS = 30000;
  var heartbeatTimer = null;

  function ooSetInput(inputId, payload) {
    if (!inputId || typeof Shiny === 'undefined') {
      return;
    }
    if (typeof Shiny.setInputValue === 'function') {
      Shiny.setInputValue(inputId, payload, { priority: 'event' });
    } else if (typeof Shiny.onInputChange === 'function') {
      // Eski Shiny istemcileri için geriye dönük uyumlu yol.
      Shiny.onInputChange(inputId, payload);
    }
  }

  // Delege tıklama: dinamik render edilen kart/satır butonları için tek dinleyici.
  document.addEventListener('click', function (ev) {
    var el = ev.target && ev.target.closest
      ? ev.target.closest('[data-oo-hedef-input]')
      : null;

    if (!el) {
      return;
    }

    var hedefInput = el.getAttribute('data-oo-hedef-input');
    var kimlik = el.getAttribute('data-oo-oturum-id') ||
      el.getAttribute('data-oo-davet-id') ||
      el.getAttribute('data-oo-dosya-id') ||
      el.getAttribute('data-oo-kullanici-id');

    if (!hedefInput || !kimlik) {
      return;
    }

    ev.preventDefault();
    ooSetInput(hedefInput, { id: kimlik, nonce: Date.now() });
  });

  function ooAktifSayfa() {
    var kap = document.querySelector('.ortak-calismalar-container[data-oo-sayfa]');
    if (!kap) {
      return '';
    }
    return kap.getAttribute('data-oo-sayfa') || '';
  }

  function ooKalpAtisiGonder() {
    // Ortak Oturum yüzeyi hiç yüklenmemişse kalp atışı gönderilmez.
    if (!document.querySelector('.ortak-calismalar-container')) {
      return;
    }
    ooSetInput('ortak_calismalar_module-canli_kalp_atisi', {
      sayfa: ooAktifSayfa(),
      nonce: Date.now()
    });
  }

  function ooKalpAtisiBaslat() {
    if (heartbeatTimer !== null) {
      return;
    }
    ooKalpAtisiGonder();
    heartbeatTimer = window.setInterval(ooKalpAtisiGonder, OO_HEARTBEAT_MS);
  }

  function ooKalpAtisiDurdur() {
    if (heartbeatTimer !== null) {
      window.clearInterval(heartbeatTimer);
      heartbeatTimer = null;
    }
  }

  if (typeof document.addEventListener === 'function') {
    document.addEventListener('shiny:connected', ooKalpAtisiBaslat);
    document.addEventListener('shiny:disconnected', ooKalpAtisiDurdur);
  }
})();
