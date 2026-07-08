/* ==========================================================================
 * Dosya: www/js/ortak_oturumlar.js
 * Açıklama: Ortak Oturumlar istemci köprüsü.
 *   - data-oo-hedef-input taşıyan butonlar için delege tıklama: hedef Shiny
 *     input'una {id, nonce} yazar (dinamik DT/renderUI yüzeylerinde güvenli).
 *   - Canlı durum kalp atışı: 30 sn'de bir sunucuya sayfa bilgisiyle bildirir
 *     (sunucu tarafı ayrıca 20 sn kısma uygular). Kalp atışı UYGULAMA
 *     GENELİNDEDİR: kullanıcı hangi sayfada olursa olsun gönderilir; böylece
 *     başka sayfalardaki oturum açmış kullanıcılar da "çevrim içi" görünür.
 *   - Yan panel ve Bilge Yolaç panel daralt/genişlet düğmeleri (yalnızca
 *     görsel; DOM sınıfı toggle eder).
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
    var closest = ev.target && ev.target.closest ? ev.target : null;

    // Panel daralt/genişlet düğmeleri (Shiny input üretmez; yalnızca görsel).
    if (closest) {
      var yanToggle = ev.target.closest('[data-oo-toggle-yan]');
      if (yanToggle) {
        var yanPanel = yanToggle.closest('[data-oo-yan-panel]');
        if (yanPanel) {
          ev.preventDefault();
          yanPanel.classList.toggle('oo-yan-panel-kapali');
          return;
        }
      }

      var byToggle = ev.target.closest('[data-oo-toggle-by]');
      if (byToggle) {
        var byPanel = byToggle.closest('.oo-by-panel');
        if (byPanel) {
          ev.preventDefault();
          byPanel.classList.toggle('oo-by-panel-kapali');
          return;
        }
      }
    }

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
      el.getAttribute('data-oo-model-deger') ||
      el.getAttribute('data-oo-kullanici-id');

    if (!hedefInput || kimlik === null || kimlik === undefined) {
      return;
    }

    ev.preventDefault();
    ooSetInput(hedefInput, { id: kimlik, nonce: Date.now() });
  });

  function ooAktifSayfa() {
    var kap = document.querySelector('.ortak-calismalar-container[data-oo-sayfa]');
    if (kap) {
      return kap.getAttribute('data-oo-sayfa') || '';
    }
    // Ortak sayfada değilsek aktif shinydashboard sekmesini bildir (varsa).
    var aktifTab = document.querySelector('.sidebar-menu li.active a[data-value]');
    if (aktifTab) {
      return aktifTab.getAttribute('data-value') || '';
    }
    return '';
  }

  function ooKalpAtisiGonder() {
    // UYGULAMA GENELİ: ortak sayfada olunmasa da kalp atışı gönderilir;
    // böylece tüm oturum açmış kullanıcılar davet panelinde çevrim içi görünür.
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

  // --- Yan panel yeniden boyutlandırma: Katılımcılar / Ortak Belgeler ---------
  // Sürüklenebilir ayraç Katılımcılar panelinin yüksekliğini (--oo-katilimci-h)
  // ayarlar; seçim sessionStorage'da tutulur (oturum boyunca korunur). Yalnızca
  // görsel; Shiny input üretmez.
  var OO_KATILIMCI_KEY = 'oo_katilimci_h';

  function ooKatilimciYukseklikGeriYukle() {
    var deger;
    try {
      deger = window.sessionStorage.getItem(OO_KATILIMCI_KEY);
    } catch (e) {
      deger = null;
    }
    if (!deger) {
      return;
    }
    var icerikler = document.querySelectorAll('.oo-yan-panel-icerik');
    for (var i = 0; i < icerikler.length; i++) {
      if (!icerikler[i].style.getPropertyValue('--oo-katilimci-h')) {
        icerikler[i].style.setProperty('--oo-katilimci-h', deger);
      }
    }
  }

  function ooResizerUygula(icerik, katil, yeniYukseklik) {
    var alan = icerik.getBoundingClientRect();
    var maxH = Math.max(160, alan.height * 0.82);
    var h = Math.max(120, Math.min(maxH, yeniYukseklik));
    icerik.style.setProperty('--oo-katilimci-h', h + 'px');
    try {
      window.sessionStorage.setItem(OO_KATILIMCI_KEY, h + 'px');
    } catch (e) { /* yoksay */ }
  }

  document.addEventListener('pointerdown', function (ev) {
    var resizer = ev.target && ev.target.closest
      ? ev.target.closest('[data-oo-resizer]')
      : null;
    if (!resizer) {
      return;
    }
    var icerik = resizer.closest('.oo-yan-panel-icerik');
    var katil = icerik && icerik.querySelector('.oo-yan-katilimcilar');
    if (!icerik || !katil) {
      return;
    }

    ev.preventDefault();
    resizer.classList.add('oo-yan-resizer-aktif');
    var basY = ev.clientY;
    var basH = katil.getBoundingClientRect().height;

    function onMove(e) {
      ooResizerUygula(icerik, katil, basH + (e.clientY - basY));
    }
    function onUp() {
      document.removeEventListener('pointermove', onMove);
      document.removeEventListener('pointerup', onUp);
      resizer.classList.remove('oo-yan-resizer-aktif');
    }
    document.addEventListener('pointermove', onMove);
    document.addEventListener('pointerup', onUp);
  });

  // Klavye erişilebilirliği: ayraç odaktayken yukarı/aşağı ok yüksekliği ayarlar.
  document.addEventListener('keydown', function (ev) {
    if (ev.key !== 'ArrowUp' && ev.key !== 'ArrowDown') {
      return;
    }
    var resizer = ev.target && ev.target.closest
      ? ev.target.closest('[data-oo-resizer]')
      : null;
    if (!resizer) {
      return;
    }
    var icerik = resizer.closest('.oo-yan-panel-icerik');
    var katil = icerik && icerik.querySelector('.oo-yan-katilimcilar');
    if (!icerik || !katil) {
      return;
    }
    ev.preventDefault();
    var adim = ev.key === 'ArrowUp' ? -24 : 24;
    ooResizerUygula(icerik, katil, katil.getBoundingClientRect().height + adim);
  });

  // --- Mesaj akışı otomatik kaydırma -----------------------------------------
  // Oda 4 sn'de bir yeniden render edilir; kullanıcı akışın DİBİNE yakınsa yeni
  // mesajlar geldiğinde otomatik en alta kaydırılır. Kullanıcı geçmişi okumak
  // için yukarı kaydırdıysa konumu korunur (yakın-dip bayrağı scroll'da tutulur).
  document.addEventListener('scroll', function (ev) {
    var el = ev.target;
    if (!el || !el.id || el.id.indexOf('mesaj_akisi') === -1) {
      return;
    }
    el._ooYakinDip = (el.scrollHeight - el.scrollTop - el.clientHeight) < 160;
  }, true);

  document.addEventListener('shiny:value', function (ev) {
    var ad = ev && ev.name ? String(ev.name) : '';
    if (ad.indexOf('mesajlar_alani') === -1 && ad.indexOf('oda_alani') === -1) {
      return;
    }
    window.setTimeout(function () {
      ooKatilimciYukseklikGeriYukle();
      var akisi = document.querySelector('[id$="-mesaj_akisi"]');
      if (!akisi) {
        return;
      }
      // İlk render veya kullanıcı zaten dipteyse en alta kaydır.
      if (akisi._ooYakinDip !== false) {
        akisi.scrollTop = akisi.scrollHeight;
      }
    }, 30);
  });

  if (typeof document.addEventListener === 'function') {
    document.addEventListener('shiny:connected', ooKalpAtisiBaslat);
    document.addEventListener('shiny:disconnected', ooKalpAtisiDurdur);
  }
})();
