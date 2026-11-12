// www/js/chat_pending_message.js
// İyimser (bekleyen) istem balonu. Gönderilen istem sunucu turunu beklemeden
// "bekleyen" balon olarak çizilir. Yalnızca sunumdur: yetki, hız sınırı ve
// kalıcılık sunucuda kalır. input_handlers.js bu modülü
// window.MergenBekleyenIstem üzerinden kullanır.
//
// Durum sözleşmesi (istek başına, istemci kimliğiyle):
//   bekliyor  -> sunucu sonucu (mergenIstemSonucu) gelene kadar kayıt tutulur;
//                gönderim kilitlidir.
//   kabul     -> sunucu eklenen mesajın kimliğini (mesaj_id) döner; bekleyen
//                balon YALNIZCA o kimlikli asıl balon DOM'dayken kalkar.
//   ret       -> balon kalkar, metin girdiye geri yüklenir (taslak korunur).
//   ayrıldı   -> kap başka bir akışla temizlendi (Yeni Söyleşi/yükleme);
//                kilit kalkar ama sonuç hâlâ beklenir (ret metni kaybolmaz).
// Metin eşleşmesi yalnızca görsel bir ipucudur (çift balon titremesini
// önlemek için bekleyen balonu gizler); kabul/ret kararı asla metinden
// çıkarılmaz.

$(document).ready(function() {
  const bekleyenIstemler = [];
  const kabulBekleyenler = [];
  const KABUL_DUGUM_BEKLEME_MS = 4000;
  let dugmeOnceki = null;
  let canliBolge = null;

  function istemMetniCoz(b64) {
    try {
      return new TextDecoder().decode(Uint8Array.from(atob(b64 || ''), function(c) { return c.charCodeAt(0); }));
    } catch (e) { return null; }
  }

  // Ekran okuyucu bildirimi: meşgul balonun dışında, tek bir kibar canlı bölge.
  // Bölge modül yüklenirken (boş) oluşturulur; aynı görevde oluşturulup
  // doldurulan bir canlı bölgenin ilk duyurusu bazı ekran okuyucularda kaçar.
  if (document.body && typeof document.createElement === 'function') {
    canliBolge = document.createElement('div');
    canliBolge.setAttribute('role', 'status');
    canliBolge.setAttribute('aria-live', 'polite');
    canliBolge.className = 'mergen-istem-canli-bolge';
    canliBolge.style.cssText = 'position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap;';
    document.body.appendChild(canliBolge);
  }
  function canliBildir(metin) {
    if (canliBolge) canliBolge.textContent = metin;
  }

  function kilitliMi() {
    return bekleyenIstemler.some(function(b) { return !b.ayrildi; });
  }

  // Düğme bekleme durumu: Durdur simgesi GÖSTERİLMEZ (tıklama yutulurken
  // yanıltıcıydı); döner simge + "gönderiliyor" erişilebilir adı kullanılır.
  // Sunucu durdurma moduna geçtiyse simge/etiket sunucuya aittir, dokunulmaz.
  function dugmeDurumunuGuncelle() {
    const btn = document.querySelector('#send_stop_btn');
    if (!btn || !btn.classList) return;
    const aktif = kilitliMi();
    const durdurModu = btn.classList.contains('stop-mode');
    const ikon = typeof btn.querySelector === 'function' ? btn.querySelector('i') : null;
    if (aktif) {
      if (!btn.classList.contains('mergen-istem-bekliyor')) {
        dugmeOnceki = { title: btn.getAttribute('title'), aria: btn.getAttribute('aria-label') };
      }
      btn.classList.add('mergen-istem-bekliyor');
      btn.setAttribute('aria-busy', 'true');
      btn.setAttribute('aria-disabled', 'true');
      if (!durdurModu) {
        if (ikon) ikon.className = 'fa-solid fa-spinner fa-spin';
        btn.setAttribute('title', 'Gönderiliyor…');
        btn.setAttribute('aria-label', 'İstem gönderiliyor');
      }
      return;
    }
    if (!btn.classList.contains('mergen-istem-bekliyor')) return;
    btn.classList.remove('mergen-istem-bekliyor');
    btn.removeAttribute('aria-busy');
    btn.removeAttribute('aria-disabled');
    if (!durdurModu) {
      if (ikon) ikon.className = 'fa-solid fa-paper-plane';
      const once = dugmeOnceki || {};
      if (once.title == null) btn.removeAttribute('title'); else btn.setAttribute('title', once.title);
      if (once.aria == null) btn.removeAttribute('aria-label'); else btn.setAttribute('aria-label', once.aria);
    }
    dugmeOnceki = null;
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

  // Kendi kaldırmamız gözlemcide "kap temizlendi" sayılmasın diye önce bağ koparılır.
  function balonuKaldir(kayit) {
    const el = kayit.el;
    kayit.el = null;
    if (el && el.parentNode) el.parentNode.removeChild(el);
  }

  function solmayiKapat(dugum) {
    const asil = dugum && dugum.querySelector ? dugum.querySelector('.message-bubble') : null;
    if (asil) { asil.classList.remove('animate-fadeIn'); asil.style.animation = 'none'; }
  }

  function listedenCikar(liste, kayit) {
    const i = liste.indexOf(kayit);
    if (i >= 0) liste.splice(i, 1);
  }

  // Ret/bağlantı kopması: metin kaybolmaz. Bekleme sırasında yazılmış bir
  // taslak varsa üzerine yazılmaz; reddedilen istem taslağın önüne eklenir.
  function metniGeriYukle(kayit) {
    const giris = typeof window.getMergenChatInputElement === 'function' ? window.getMergenChatInputElement() : null;
    if (!giris) return;
    // Yalnızca taslak reddedilen istemle birebir aynıysa yeniden eklenmez; alt
    // dize eşleşmesi (ör. istem "a", taslak "taslak") istemi yutmamalıdır.
    const mevcut = String(giris.value || '');
    if (!mevcut.trim()) giris.value = kayit.hamMetin;
    else if (mevcut.trim() !== String(kayit.hamMetin || '').trim()) giris.value = kayit.hamMetin + '\n' + mevcut;
    else return;
    if (typeof window.adjustTextareaHeight === 'function') window.adjustTextareaHeight(giris);
    if (typeof window.updateCharCounter === 'function') window.updateCharCounter();
  }

  function reddet(kayit) {
    const ayniGorunum = !kayit.ayrildi;
    balonuKaldir(kayit);
    metniGeriYukle(kayit);
    // Karşılama yalnızca görünüm hâlâ aynıysa (kapta başka balon yoksa) geri gelir;
    // kullanıcı bu arada bir söyleşi açtıysa etkin söyleşi gizlenmez.
    const $karsilama = $('#welcome_fullscreen_container');
    if (ayniGorunum && kayit.karsilamaGizlendi && sohbetKabi && !sohbetKabi.children.length &&
        $karsilama.children().length > 0) {
      $karsilama.removeClass('hidden');
      $(sohbetKabi).hide();
    }
    canliBildir('İstem gönderilemedi; metin giriş alanına geri yüklendi.');
  }

  function kabulBekleyeniBitir(kayit, dugum) {
    listedenCikar(kabulBekleyenler, kayit);
    if (kayit.zamanlayici) clearTimeout(kayit.zamanlayici);
    if (dugum) solmayiKapat(dugum);
    balonuKaldir(kayit);
  }

  function kabulEt(kayit, mesajId) {
    const dugum = mesajId && typeof document.getElementById === 'function'
      ? document.getElementById('message_wrapper_' + mesajId) : null;
    if (dugum || !mesajId || !kayit.el) {
      if (dugum) solmayiKapat(dugum);
      balonuKaldir(kayit);
      return;
    }
    // Asıl balon henüz çizilmedi (ya da metin eşleşmesi başka bir balona aitti):
    // bekleyen balon görünür kalır ve o kimlikli balon gelince kalkar.
    kayit.el.style.display = '';
    kayit.mesajId = mesajId;
    kabulBekleyenler.push(kayit);
    kayit.zamanlayici = setTimeout(function() { kabulBekleyeniBitir(kayit, null); }, KABUL_DUGUM_BEKLEME_MS);
  }

  const sohbetKabi = typeof document.getElementById === 'function' ? document.getElementById('chat_content_container') : null;
  if (typeof MutationObserver === 'function' && sohbetKabi) new MutationObserver(function(kayitlar) {
    if (!bekleyenIstemler.length && !kabulBekleyenler.length) return;
    let degisti = false;
    kayitlar.forEach(function(k) {
      (k.removedNodes || []).forEach(function(dugum) {
        const kayit = bekleyenIstemler.find(function(b) { return b.el && b.el === dugum; });
        if (kayit) { kayit.el = null; kayit.ayrildi = true; degisti = true; }
        const kabul = kabulBekleyenler.find(function(b) { return b.el && b.el === dugum; });
        if (kabul) { kabul.el = null; kabulBekleyeniBitir(kabul, null); }
      });
      (k.addedNodes || []).forEach(function(dugum) {
        if (!dugum.querySelector || (dugum.classList && dugum.classList.contains('mergen-bekleyen-istem'))) return;
        const kabul = kabulBekleyenler.find(function(b) { return dugum.id === 'message_wrapper_' + b.mesajId; });
        if (kabul) { kabulBekleyeniBitir(kabul, dugum); return; }
        const icerik = dugum.querySelector('.user-message .message-content[data-copy-b64]');
        if (!icerik) return;
        const metin = (istemMetniCoz(icerik.getAttribute('data-copy-b64')) || '').trim();
        const kayit = bekleyenIstemler.find(function(b) { return !b.ayrildi && !b.sunucuDugumu && b.metin === metin; });
        if (!kayit) return;
        // Görsel ipucu: çift balon görünmesin diye bekleyen balon gizlenir; karar sunucudan gelir.
        kayit.sunucuDugumu = dugum;
        solmayiKapat(dugum);
        if (kayit.el) kayit.el.style.display = 'none';
      });
    });
    if (degisti) dugmeDurumunuGuncelle();
  }).observe(sohbetKabi, { childList: true, subtree: true });

  if (window.Shiny && typeof Shiny.addCustomMessageHandler === 'function') {
    Shiny.addCustomMessageHandler('mergenIstemSonucu', function(veri) {
      const kayit = bekleyenIstemler.find(function(b) { return b.id === (veri && veri.client_id); });
      if (!kayit) return;
      listedenCikar(bekleyenIstemler, kayit);
      if (veri.durum === 'kabul') kabulEt(kayit, String(veri.mesaj_id || '')); else reddet(kayit);
      dugmeDurumunuGuncelle();
    });
  }

  // Bağlantı koptu: asıl balonu görülmüş (sunucunun kabul ettiği) istem geri
  // yüklenmez; aksi halde yeniden gönderim mesajı çoğaltırdı.
  $(document).on('shiny:disconnected', function() {
    bekleyenIstemler.slice().forEach(function(kayit) {
      listedenCikar(bekleyenIstemler, kayit);
      if (kayit.sunucuDugumu) balonuKaldir(kayit); else reddet(kayit);
    });
    dugmeDurumunuGuncelle();
  });

  // Bekleme sırasında düğmeye tıklama yutulur: sunucu sonucu gelmeden "Durdur"
  // sinyali gönderilmez. Sunucu durdurma moduna kabul bildiriminden hemen önce
  // geçtiği için çift tıklamanın ikinci vuruşu yeni isteği iptal edemez.
  if (typeof document.addEventListener === 'function') document.addEventListener('click', function(e) {
    const btn = e.target && e.target.closest ? e.target.closest('#send_stop_btn') : null;
    if (btn && btn.classList.contains('mergen-istem-bekliyor')) {
      e.preventDefault();
      e.stopPropagation();
    }
  }, true);

  window.MergenBekleyenIstem = {
    varMi: kilitliMi,
    ekle: function(hamMetin) {
      const istemKimligi = 'istem_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 8);
      const gosterilecek = hamMetin.trim() || 'Seçili dosyaların özeti istendi.';
      const kayit = { id: istemKimligi, metin: gosterilecek, hamMetin: hamMetin, el: null,
                      karsilamaGizlendi: false, ayrildi: false, sunucuDugumu: null };
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
      dugmeDurumunuGuncelle();
      canliBildir('İstem gönderiliyor…');
      return istemKimligi;
    }
  };
});
