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
//   koptu     -> sonucu gelmemiş istemin akıbeti bilinemez (oturum yeniden
//                bağlanmaz); metin girdiye geri yüklenir, asla otomatik
//                gönderilmez.
//   zaman aşımı -> bağlantı açıkken sonuç sınırlı süre içinde gelmezse (olay
//                kayboldu) kilit kalkar, metin belirsiz-teslim bildirimiyle
//                girdiye geri yüklenir; asla otomatik gönderilmez. Geç gelen
//                "kabul" (istemci kimliğiyle) asıl balon mesaj kimliğiyle
//                DOM'a gelince yalnızca geri yüklenen istem bölümünü kaldırır.
// Metin eşleşmesi yalnızca görsel bir ipucudur (çift balon titremesini
// önlemek için bekleyen balonu gizler); kabul/ret ve bağlantı kopması kararı
// asla metinden çıkarılmaz.

$(document).ready(function() {
  const bekleyenIstemler = [];
  const kabulBekleyenler = [];
  const KABUL_DUGUM_BEKLEME_MS = 4000;
  // Sunucu sonucu için üst sınır: kayıp bir gönderim olayı (bağlantı açık)
  // gönderimi sonsuza dek kilitlemez. Sunucu turu bunun çok altında biter.
  const ISTEM_SONUC_BEKLEME_MS = 60000;
  // Zaman aşımına uğramış istemler (sınırlı): geç sonuç doğru eşlenir.
  const zamanAsimlari = [];
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

  function girisAlani() {
    return typeof window.getMergenChatInputElement === 'function' ? window.getMergenChatInputElement() : null;
  }

  function girisiYenile(giris) {
    if (typeof window.adjustTextareaHeight === 'function') window.adjustTextareaHeight(giris);
    if (typeof window.updateCharCounter === 'function') window.updateCharCounter();
  }

  // Geri yükleme bölümleri: yalnızca kurtarmanın girdiye GERÇEKTEN eklediği
  // metin, istek kimliğiyle ve girdideki sırasıyla (üstten alta) tutulur. Metin
  // eşitliği sahiplik kanıtı değildir; bölüm, girdinin başındaki konumuyla
  // bulunur. Ret/kopma bölümleri de kullanıcı tüketene (gönderim) ya da
  // silene dek tutulur: sahip sıfırlaması onları da kaldırabilir.
  const geriYuklemeler = [];
  const GERI_YUKLEME_SINIRI = 16;
  // Bölümleri girdinin başından sırayla konumlar; yerinde bulunmayan bölüm
  // kullanıcı tarafından silinmiş/düzenlenmiş sayılır ve sahipliği düşer.
  function bolumleriKonumla(deger) {
    const konumlar = [];
    let ofset = 0;
    for (let i = 0; i < geriYuklemeler.length;) {
      const b = geriYuklemeler[i];
      const yerinde = b.sonda ? deger.slice(ofset) === b.metin : deger.startsWith(b.metin, ofset);
      if (!yerinde) { geriYuklemeler.splice(i, 1); continue; }
      konumlar.push(b);
      ofset += b.metin.length;
      i++;
    }
    return { konumlar: konumlar, kalan: deger.slice(ofset) };
  }
  // Seçilen sahiplerin bölümleri konumlarıyla kesilir; diğer bölümler ve
  // taslak aynen kalır.
  function bolumleriKaldir(secici) {
    const giris = girisAlani();
    if (!giris || !geriYuklemeler.length) return;
    const yer = bolumleriKonumla(String(giris.value || ''));
    const kalanlar = yer.konumlar.filter(function(b) { return !secici(b); });
    if (kalanlar.length === yer.konumlar.length) return;
    yer.konumlar.forEach(function(b) { if (kalanlar.indexOf(b) < 0) listedenCikar(geriYuklemeler, b); });
    // En alttaki (satır sonu olmayan) bölüm kalktıysa üstündeki satır sonu da kalkar.
    const sonKalan = kalanlar[kalanlar.length - 1];
    if (!yer.kalan && yer.konumlar[yer.konumlar.length - 1].sonda && sonKalan && !sonKalan.sonda) {
      sonKalan.metin = sonKalan.metin.slice(0, -1);
      sonKalan.sonda = true;
    }
    giris.value = kalanlar.map(function(b) { return b.metin; }).join('') + yer.kalan;
    girisiYenile(giris);
  }

  // Ret/bağlantı kopması: metin kaybolmaz. Bekleme sırasında yazılmış bir
  // taslak varsa üzerine yazılmaz; reddedilen istem taslağın önüne eklenir.
  // Eklenen bölüm istek kimliğiyle kaydedilir: geç kabulde yalnızca o bölüm
  // kalkar, taslak ve diğer isteklerin bölümleri korunur.
  function metniGeriYukle(kayit) {
    const giris = girisAlani();
    const ham = String(kayit.hamMetin || '');
    if (!giris || !ham.trim()) return;
    const mevcut = String(giris.value || '');
    let bolum;
    if (!mevcut.trim()) {
      geriYuklemeler.length = 0;
      giris.value = ham;
      bolum = { id: kayit.id, metin: ham, sonda: true };
    } else if (mevcut.trim() === ham.trim() && !bolumleriKonumla(mevcut).konumlar.length) {
      // Bağımsız yazılmış özdeş taslak: hiçbir şey eklenmez, sahiplik de alınmaz.
      return;
    } else {
      giris.value = ham + '\n' + mevcut;
      bolum = { id: kayit.id, metin: ham + '\n', sonda: false };
    }
    geriYuklemeler.unshift(bolum);
    if (geriYuklemeler.length > GERI_YUKLEME_SINIRI) geriYuklemeler.pop();
    girisiYenile(giris);
  }

  // Geç kabul (asıl balon DOM'dayken): yalnızca bu isteğin kendi bölümü kalkar.
  function geriYuklemeyiUzlastir(kayit) {
    bolumleriKaldir(function(b) { return b.id === kayit.id; });
  }

  function reddet(kayit, bildirim) {
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
    canliBildir(bildirim || 'İstem gönderilemedi; metin giriş alanına geri yüklendi.');
  }

  function kabulBekleyeniBitir(kayit, dugum) {
    listedenCikar(kabulBekleyenler, kayit);
    if (kayit.zamanlayici) clearTimeout(kayit.zamanlayici);
    if (dugum) solmayiKapat(dugum);
    balonuKaldir(kayit);
    // Geç kabulde geri yüklenen metin ancak asıl balon görünürken kalkar.
    if (dugum && kayit.gec) geriYuklemeyiUzlastir(kayit);
  }

  // Asıl balon gecikirse kabul edilmiş istem kaybolmaz: bekleyen balon
  // "gönderiliyor" durumundan çıkar, görünür kalır; asıl balon gelince kalkar.
  function kabulGorunumunuTamamla(kayit) {
    const el = kayit.el;
    if (!el) return;
    el.removeAttribute('aria-busy');
    el.style.opacity = '';
    const zaman = el.querySelector ? el.querySelector('.message-time') : null;
    if (zaman) zaman.textContent = '';
  }

  function kabulEt(kayit, mesajId) {
    // Başka bir istem hâlâ gönderiliyorsa onun durumu duyurulmaya devam eder.
    if (!kilitliMi()) canliBildir('İstem gönderildi.');
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
    kayit.zamanlayici = setTimeout(function() { kabulGorunumunuTamamla(kayit); }, KABUL_DUGUM_BEKLEME_MS);
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
      if (!kayit) { gecSonucuIsle(veri); return; }
      listedenCikar(bekleyenIstemler, kayit);
      if (kayit.sonucZamanlayici) clearTimeout(kayit.sonucZamanlayici);
      if (veri.durum === 'kabul') kabulEt(kayit, String(veri.mesaj_id || '')); else reddet(kayit);
      dugmeDurumunuGuncelle();
    });
    // Oturum sahibi değişti: önceki sahibin sonuçlanmamış istemleri metni geri
    // yüklenmeden düşer; daha önce geri yüklenmiş (zaman aşımı, ret ya da
    // kopma) istem bölümleri girdiden kaldırılır. Yeni sahip eski sahibin
    // istemini görmez.
    Shiny.addCustomMessageHandler('mergenBekleyenIstemSifirla', function() {
      bekleyenIstemler.splice(0).concat(kabulBekleyenler.splice(0), zamanAsimlari.splice(0)).forEach(function(kayit) {
        if (kayit.sonucZamanlayici) clearTimeout(kayit.sonucZamanlayici);
        if (kayit.zamanlayici) clearTimeout(kayit.zamanlayici);
        balonuKaldir(kayit);
      });
      bolumleriKaldir(function() { return true; });
      geriYuklemeler.length = 0;
      dugmeDurumunuGuncelle();
    });
  }

  // Zaman aşımından sonra gelen sonuç: "ret" için metin zaten geri yüklendi.
  // "Kabul" istemci kimliğiyle eşlenir ve mevcut kabul yaşam döngüsünden
  // (kabulBekleyenler) geçer: geri yüklenen istem, sunucunun verdiği mesaj
  // kimlikli asıl balon DOM'da görünene dek girdide kalır (istem hiçbir anda
  // görünmez olmaz); balon gelince yalnızca geri yüklenen istem bölümü kalkar.
  function gecSonucuIsle(veri) {
    const i = zamanAsimlari.findIndex(function(b) { return b.id === (veri && veri.client_id); });
    if (i < 0) return;
    const kayit = zamanAsimlari.splice(i, 1)[0];
    if (veri.durum !== 'kabul') return;
    if (!kilitliMi()) canliBildir('Gecikmeli istem iletildi.');
    const mesajId = String(veri.mesaj_id || '');
    if (!mesajId || !geriYuklemeler.some(function(b) { return b.id === kayit.id; })) return;
    const dugum = typeof document.getElementById === 'function'
      ? document.getElementById('message_wrapper_' + mesajId) : null;
    if (dugum) { geriYuklemeyiUzlastir(kayit); return; }
    kayit.mesajId = mesajId;
    kayit.gec = true;
    kabulBekleyenler.push(kayit);
    // Asıl balonu hiç gelmeyen geç kabuller sınırlı tutulur (metin girdide kalır).
    const gecler = kabulBekleyenler.filter(function(b) { return b.gec; });
    if (gecler.length > 8) listedenCikar(kabulBekleyenler, gecler[0]);
  }

  function sonucZamanAsimi(kayit) {
    if (bekleyenIstemler.indexOf(kayit) < 0) return;
    listedenCikar(bekleyenIstemler, kayit);
    zamanAsimlari.push(kayit);
    if (zamanAsimlari.length > 8) zamanAsimlari.shift();
    reddet(kayit, 'İstemin iletilip iletilmediği doğrulanamadı; metin giriş alanına geri yüklendi. Göndermeden önce söyleşiyi kontrol edin.');
    dugmeDurumunuGuncelle();
  }

  // Bağlantı koptu: sonucu gelmemiş istemin kabul edilip edilmediği bilinemez.
  // Aynı metinli bir balon kabul kanıtı sayılmaz; istem kaybolmasın diye metin
  // girdiye geri yüklenir ve belirsizlik açıkça bildirilir (otomatik yeniden
  // gönderim yok; kabul edilmişse yeniden yüklemede kayıtlı söyleşide görünür).
  $(document).on('shiny:disconnected', function() {
    bekleyenIstemler.slice().forEach(function(kayit) {
      listedenCikar(bekleyenIstemler, kayit);
      if (kayit.sonucZamanlayici) clearTimeout(kayit.sonucZamanlayici);
      reddet(kayit, 'Bağlantı koptu; istemin iletilip iletilmediği doğrulanamadı. Metin giriş alanına geri yüklendi.');
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

  // Kullanıcı bir geri yükleme bölümünü silip/düzenlediğinde sahiplik hemen
  // düşer; aynı metin sonradan yeniden yazılsa da geç kabul onu silmez.
  if (typeof document.addEventListener === 'function') document.addEventListener('input', function(e) {
    if (geriYuklemeler.length && e.target && e.target === girisAlani()) bolumleriKonumla(String(e.target.value || ''));
  }, true);

  window.MergenBekleyenIstem = {
    varMi: kilitliMi,
    ekle: function(hamMetin) {
      // Gönderim girdiyi tüketir: önceki geri yüklemelerin sahipliği biter.
      geriYuklemeler.length = 0;
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
      kayit.sonucZamanlayici = setTimeout(function() { sonucZamanAsimi(kayit); }, ISTEM_SONUC_BEKLEME_MS);
      dugmeDurumunuGuncelle();
      canliBildir('İstem gönderiliyor…');
      return istemKimligi;
    }
  };
});
