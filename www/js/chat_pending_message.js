// www/js/chat_pending_message.js
// İyimser (bekleyen) istem balonu. Gönderilen istem sunucu turunu beklemeden
// "bekleyen" balon olarak çizilir. Yalnızca sunumdur: yetki, hız sınırı ve
// kalıcılık sunucuda kalır. Sunucunun asıl balonu eklendiği mikro görevde
// bekleyen balon kaldırılır (çift balon ya da titreme olmaz); ret/bağlantı
// kopmasında kaldırılır ve metin girdiye geri yüklenir. input_handlers.js bu
// modülü window.MergenBekleyenIstem üzerinden kullanır.

$(document).ready(function() {
  // Gönderilen istem sunucu turunu beklemeden "bekleyen" balon olarak çizilir.
  // Yalnızca sunumdur: yetki, hız sınırı ve kalıcılık sunucuda kalır. Sunucunun
  // asıl balonu eklendiği mikro görevde bekleyen balon kaldırılır (çift balon ya
  // da titreme olmaz); ret/bağlantı kopmasında kaldırılır ve metin geri yüklenir.
  const bekleyenIstemler = [];

  function istemMetniCoz(b64) {
    try {
      return new TextDecoder().decode(Uint8Array.from(atob(b64 || ''), function(c) { return c.charCodeAt(0); }));
    } catch (e) { return null; }
  }

  function gonderDugmesiBekliyor(aktif) {
    const btn = document.querySelector('#send_stop_btn');
    if (!btn || !btn.classList) return;
    if (aktif) btn.classList.add('mergen-istem-bekliyor'); else btn.classList.remove('mergen-istem-bekliyor');
    if (typeof btn.setAttribute === 'function') {
      if (aktif) btn.setAttribute('aria-busy', 'true'); else btn.removeAttribute('aria-busy');
    }
    const ikon = typeof btn.querySelector === 'function' ? btn.querySelector('i') : null;
    if (ikon && !$('#send_stop_btn').hasClass('stop-mode')) {
      ikon.className = aktif ? 'fa-solid fa-stop' : 'fa-solid fa-paper-plane';
    }
  }

  function bekleyenBalonOlustur(id, metin) {
    const sarmal = document.createElement('div');
    sarmal.id = 'message_wrapper_' + id;
    sarmal.className = 'mergen-bekleyen-istem';
    sarmal.setAttribute('aria-busy', 'true');
    sarmal.style.opacity = '0.85';
    const balon = document.createElement('div');
    balon.className = 'message-bubble';
    balon.style.animation = 'none'; // .message-bubble solması ilk kareleri boş gösteriyordu
    const kullanici = document.createElement('div');
    kullanici.className = 'user-message';
    const sonBaslik = document.querySelector('#chat_content_container .user-message .message-header');
    let baslik;
    if (sonBaslik) {
      baslik = sonBaslik.cloneNode(true);
      baslik.querySelectorAll('.message-actions, [id]').forEach(function(el) {
        if (el.classList.contains('message-actions')) el.remove(); else el.removeAttribute('id');
      });
    } else {
      const yeni = function(sinif, ebeveyn) {
        const el = document.createElement(sinif === 'fas fa-user' ? 'i' : 'div');
        el.className = sinif;
        if (ebeveyn) ebeveyn.appendChild(el);
        return el;
      };
      baslik = yeni('message-header');
      const avatar = yeni('user-avatar gradient-user', baslik);
      avatar.style.width = '40px';
      avatar.style.height = '40px';
      yeni('fas fa-user', avatar);
      const bilgi = yeni('message-info', baslik);
      const ad = document.querySelector('.mb-sidebar-user-name');
      yeni('message-author', bilgi).textContent = ad ? (ad.getAttribute('title') || ad.textContent || '') : '';
      yeni('message-time', bilgi);
    }
    const zaman = baslik.querySelector('.message-time');
    if (zaman) { zaman.textContent = 'Gönderiliyor…'; zaman.classList.remove('hidden'); }
    const icerik = document.createElement('div');
    icerik.className = 'message-content';
    icerik.style.whiteSpace = 'pre-wrap';
    icerik.textContent = metin;
    kullanici.appendChild(baslik);
    kullanici.appendChild(icerik);
    balon.appendChild(kullanici);
    sarmal.appendChild(balon);
    return sarmal;
  }

  function bekleyenIstemiKaldir(kayit, geriYukle) {
    const i = bekleyenIstemler.indexOf(kayit);
    if (i < 0) return;
    bekleyenIstemler.splice(i, 1);
    if (kayit.el && kayit.el.parentNode) kayit.el.parentNode.removeChild(kayit.el);
    if (geriYukle) {
      const giris = typeof window.getMergenChatInputElement === 'function' ? window.getMergenChatInputElement() : null;
      if (giris && !String(giris.value || '').trim()) {
        giris.value = kayit.hamMetin;
        if (typeof window.adjustTextareaHeight === 'function') window.adjustTextareaHeight(giris);
        if (typeof window.updateCharCounter === 'function') window.updateCharCounter();
      }
      const $karsilama = $('#welcome_fullscreen_container');
      if (kayit.karsilamaGizlendi && $karsilama.children().length > 0) {
        $karsilama.removeClass('hidden');
        $('#chat_content_container').hide();
      }
    }
    if (!bekleyenIstemler.length) gonderDugmesiBekliyor(false);
  }

  // Sunucunun asıl kullanıcı balonu eklendiğinde eşleşen bekleyen balonu
  // aynı mikro görevde kaldır; asıl balon solma animasyonu olmadan görünür.
  // Kap başka bir akışla temizlenirse (Yeni Söyleşi, söyleşi yükleme) bekleyen
  // kayıt da düşer; gönderim hiçbir durumda kalıcı olarak kilitlenmez.
  const sohbetKabi = typeof document.getElementById === 'function' ? document.getElementById('chat_content_container') : null;
  if (typeof MutationObserver === 'function' && sohbetKabi) new MutationObserver(function(kayitlar) {
    if (!bekleyenIstemler.length) return;
    kayitlar.forEach(function(k) {
      (k.removedNodes || []).forEach(function(dugum) {
        const kayit = bekleyenIstemler.find(function(b) { return b.el && b.el === dugum; });
        if (kayit) { kayit.el = null; bekleyenIstemiKaldir(kayit, false); }
      });
      k.addedNodes.forEach(function(dugum) {
        if (!dugum.querySelector || (dugum.classList && dugum.classList.contains('mergen-bekleyen-istem'))) return;
        const icerik = dugum.querySelector('.user-message .message-content[data-copy-b64]');
        if (!icerik) return;
        const metin = (istemMetniCoz(icerik.getAttribute('data-copy-b64')) || '').trim();
        const kayit = bekleyenIstemler.find(function(b) { return b.metin === metin; });
        if (!kayit) return;
        const asil = dugum.querySelector('.message-bubble');
        if (asil) { asil.classList.remove('animate-fadeIn'); asil.style.animation = 'none'; }
        if (kayit.el && kayit.el.parentNode) kayit.el.parentNode.removeChild(kayit.el);
        kayit.el = null;
      });
    });
  }).observe(sohbetKabi, { childList: true, subtree: true });

  if (window.Shiny && typeof Shiny.addCustomMessageHandler === 'function') {
    Shiny.addCustomMessageHandler('mergenIstemSonucu', function(veri) {
      const kayit = bekleyenIstemler.find(function(b) { return b.id === (veri && veri.client_id); });
      if (kayit) bekleyenIstemiKaldir(kayit, !(veri && veri.durum === 'kabul'));
    });
  }

  $(document).on('shiny:disconnected', function() {
    bekleyenIstemler.slice().forEach(function(kayit) { bekleyenIstemiKaldir(kayit, true); });
  });

  // Bekleme sırasında düğmeye tıklama yutulur: sunucu isteği kabul etmeden
  // "Durdur" sinyali gönderilmez (çift tıklama isteği iptal etmez).
  if (typeof document.addEventListener === 'function') document.addEventListener('click', function(e) {
    const btn = e.target && e.target.closest ? e.target.closest('#send_stop_btn') : null;
    if (btn && btn.classList.contains('mergen-istem-bekliyor') && !btn.classList.contains('stop-mode')) {
      e.preventDefault();
      e.stopPropagation();
    }
  }, true);

  window.MergenBekleyenIstem = {
    varMi: function() { return bekleyenIstemler.length > 0; },
    ekle: function(hamMetin) {
      const istemKimligi = 'istem_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 8);
      const gosterilecek = hamMetin.trim() || 'Seçili dosyaların özeti istendi.';
      const kayit = { id: istemKimligi, metin: gosterilecek, hamMetin: hamMetin, el: null, karsilamaGizlendi: false };
      const kap = sohbetKabi;
      if (kap && typeof document.createElement === 'function') {
        const $karsilama = $('#welcome_fullscreen_container');
        if ($karsilama.length && !$karsilama.hasClass('hidden') && $karsilama.children().length > 0) {
          $karsilama.addClass('hidden');
          $(kap).show();
          kayit.karsilamaGizlendi = true;
        }
        kayit.el = bekleyenBalonOlustur(istemKimligi, gosterilecek);
        kap.appendChild(kayit.el);
      }
      bekleyenIstemler.push(kayit);
      gonderDugmesiBekliyor(true);
      return istemKimligi;
    }
  };
});
