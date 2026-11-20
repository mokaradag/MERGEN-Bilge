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
    for (let i = 0; i < bekleyenIstemler.length; i++) {
      if (!bekleyenIstemler[i].ayrildi) return true;
    }
    for (let i = 0; i < kabulBekleyenler.length; i++) {
      const b = kabulBekleyenler[i];
      if (!b.gec || b.sureDoldu) continue;
      for (let j = 0; j < geriYuklemeler.length; j++) {
        if (geriYuklemeler[j].id === b.id && !geriYuklemeler[j].duzenlendi) return true;
      }
    }
    return false;
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

  // Geri yükleme bölümleri: kurtarmanın girdiye GERÇEKTEN eklediği metin, istek
  // kimliğiyle ve girdideki ARALIĞIYLA ([bas, son)) tutulur. Metin eşitliği
  // sahiplik kanıtı değildir: aralık, her girdi değişikliğinde düzenlenen
  // bölgeye göre kaydırılır (imleç konumu düzenlemenin yerini belirler; aynı
  // metinli iki bölümden hangisinin silindiği metinden çıkarılmaz).
  //   - Bölüm tamamen silinirse kaydı düşer (yeniden yazılan metin sahiplenilmez).
  //   - Bölüm düzenlenirse kaydı DÜZENLENDİ olarak kalır: geç kabul onu silmez
  //     (kullanıcının düzenlemesi korunur) ama sahip sıfırlaması kaldırır.
  //   - Bölümün dışındaki düzenleme (ayrı satırda taslak) sahipliği etkilemez.
  // Kayıtlar kullanıcı tüketene (gönderim), silene ya da sahip sıfırlanana dek
  // tutulur; sayı sınırı yoktur (her kayıt girdideki gerçek metne karşılık gelir).
  const geriYuklemeler = [];
  let sonDeger = '';
  let oncekiSecim = null;

  function ekImzasi() {
    const ek = document.querySelector('#file_prompt_indicator_ui');
    if (!ek || !ek.children || !ek.children.length) return '';
    const dogrudan = String(ek.textContent || '').trim();
    if (dogrudan) return dogrudan;
    const parcalar = [];
    for (let i = 0; i < ek.children.length; i++) {
      parcalar.push(String((ek.children[i] && ek.children[i].textContent) || '').trim());
    }
    return parcalar.join('|').trim();
  }

  function sahipsizleriBudala() {
    const canli = {};
    for (let i = 0; i < geriYuklemeler.length; i++) canli[geriYuklemeler[i].id] = true;
    const sahipsizZa = [];
    for (let i = 0; i < zamanAsimlari.length; i++) {
      if (!canli[zamanAsimlari[i].id]) sahipsizZa.push(zamanAsimlari[i]);
    }
    while (sahipsizZa.length > 8) listedenCikar(zamanAsimlari, sahipsizZa.shift());
    const sahipsizGec = [];
    for (let i = 0; i < kabulBekleyenler.length; i++) {
      if (kabulBekleyenler[i].gec && !canli[kabulBekleyenler[i].id]) sahipsizGec.push(kabulBekleyenler[i]);
    }
    while (sahipsizGec.length > 8) listedenCikar(kabulBekleyenler, sahipsizGec.shift());
  }

  // Eski ve yeni değer arasındaki tek düzenleme bölgesi. İmleç biliniyorsa
  // imleçten sonraki metin değişmemiş sonek sayılır (silinen özdeş satırın
  // hangisi olduğu böyle bulunur); bilinmiyorsa ortak önek/sonek kullanılır.
  function duzenlemeBolgesi(eski, yeni, imlec) {
    let sonek = -1;
    if (typeof imlec === 'number' && imlec >= 0 && imlec <= yeni.length) {
      const kuyruk = yeni.slice(imlec);
      if (kuyruk.length <= eski.length && eski.endsWith(kuyruk)) sonek = kuyruk.length;
    }
    if (sonek < 0) {
      sonek = 0;
      const enFazla = Math.min(eski.length, yeni.length);
      while (sonek < enFazla && eski[eski.length - 1 - sonek] === yeni[yeni.length - 1 - sonek]) sonek++;
    }
    const eskiSon = eski.length - sonek;
    const yeniSon = yeni.length - sonek;
    let bas = 0;
    const sinir = Math.min(eskiSon, yeniSon);
    while (bas < sinir && eski[bas] === yeni[bas]) bas++;
    return { bas: bas, eskiSon: eskiSon, yeniSon: yeniSon, eklenen: yeni.slice(bas, yeniSon) };
  }

  // Girdinin bilinen son değerinden bu yana yapılan değişikliği bölümlere uygular.
  // Programatik atamalar (Escape, gönderim sonrası temizleme) da buradan geçer.
  function bolumleriEsitle(imlec) {
    const giris = girisAlani();
    if (!giris) return;
    const yeni = String(giris.value || '');
    const eski = sonDeger;
    const secim = oncekiSecim;
    oncekiSecim = null;
    sonDeger = yeni;
    if (yeni === eski || !geriYuklemeler.length) return;
    // Tüm girdi seçilip değiştirildiyse (Ctrl+A + yapıştır/yaz) eski geri
    // yükleme sahipliği tamamen düşer; yeni taslak önceki isteğe bağlanmaz.
    if (secim && eski.length > 0 && secim.uzunluk === eski.length &&
        secim.bas === 0 && secim.son === eski.length) {
      geriYuklemeler.length = 0;
      sahipsizleriBudala();
      return;
    }
    const d = duzenlemeBolgesi(eski, yeni, imlec);
    const fark = yeni.length - eski.length;
    const ekleme = d.bas === d.eskiSon;
    for (let i = 0; i < geriYuklemeler.length;) {
      const b = geriYuklemeler[i];
      let icinde;
      if (ekleme) {
        // Sınırdaki ekleme bölüme katılır; yalnızca satır sonuyla ayrılan ekleme
        // (ayrı satırdaki taslak) bölümün dışında kalır.
        const sonSinir = d.bas === b.son && eski[b.son - 1] !== '\n' && d.eklenen[0] !== '\n';
        const basSinir = d.bas === b.bas && d.eklenen[d.eklenen.length - 1] !== '\n';
        icinde = (d.bas > b.bas && d.bas < b.son) || sonSinir || basSinir;
      } else {
        icinde = d.bas < b.son && d.eskiSon > b.bas;
      }
      if (!icinde) {
        if (d.eskiSon <= b.bas) { b.bas += fark; b.son += fark; }
        i++;
        continue;
      }
      const bas = Math.min(b.bas, d.bas);
      const son = Math.max(b.son + fark, d.yeniSon);
      if (son <= bas) { geriYuklemeler.splice(i, 1); continue; }
      b.bas = bas;
      b.son = son;
      // Düzenleme geri alınıp özgün metne dönüldüyse geç kabul yine uzlaştırabilir.
      b.duzenlendi = (typeof b.ozgun === 'string') ? (yeni.slice(bas, son) !== b.ozgun) : true;
      i++;
    }
    sahipsizleriBudala();
  }

  // Seçilen sahiplerin bölümleri aralıklarıyla kesilir; diğer bölümler ve
  // taslak aynen kalır. Kesilen bölümün ayırıcı satır sonu da birlikte kalkar.
  function bolumleriKaldir(secici) {
    const giris = girisAlani();
    if (!giris) return;
    bolumleriEsitle();
    const secilen = geriYuklemeler.filter(secici);
    if (!secilen.length) return;
    const deger = sonDeger;
    const secBas = typeof giris.selectionStart === 'number' ? giris.selectionStart : null;
    const secSon = typeof giris.selectionEnd === 'number' ? giris.selectionEnd : null;
    const kalanlar = geriYuklemeler.filter(function(b) { return secilen.indexOf(b) < 0; });
    const araliklar = secilen.map(function(b) {
      let bas = b.bas;
      let son = b.son;
      if (b.ayirici || deger[son - 1] !== '\n') {
        const sonrakiBolum = kalanlar.some(function(k) { return k.bas <= son && son < k.son; });
        if (deger[son] === '\n' && !sonrakiBolum) son++;
        else if (son === deger.length && bas > 0 && deger[bas - 1] === '\n') bas--;
      }
      return [bas, son];
    }).sort(function(x, y) { return x[0] - y[0]; });
    const birlesik = [];
    araliklar.forEach(function(r) {
      const son = birlesik[birlesik.length - 1];
      if (son && r[0] <= son[1]) son[1] = Math.max(son[1], r[1]); else birlesik.push(r.slice());
    });
    // Eski konumu kesimden sonraki konuma eşler.
    const esle = function(konum) {
      let kayma = 0;
      for (let i = 0; i < birlesik.length; i++) {
        const r = birlesik[i];
        if (konum <= r[0]) break;
        kayma += Math.min(konum, r[1]) - r[0];
      }
      return konum - kayma;
    };
    let yeni = '';
    let imlec = 0;
    birlesik.forEach(function(r) { yeni += deger.slice(imlec, r[0]); imlec = r[1]; });
    yeni += deger.slice(imlec);
    geriYuklemeler.length = 0;
    kalanlar.forEach(function(b) {
      b.bas = esle(b.bas);
      b.son = esle(b.son);
      if (b.son > b.bas) geriYuklemeler.push(b);
    });
    giris.value = yeni;
    sonDeger = yeni;
    if (secBas !== null && secSon !== null && typeof giris.setSelectionRange === 'function') {
      try { giris.setSelectionRange(esle(secBas), esle(secSon)); } catch (e) {}
    }
    sahipsizleriBudala();
    girisiYenile(giris);
  }

  // Ret/bağlantı kopması: metin kaybolmaz. Bekleme sırasında yazılmış bir
  // taslak varsa üzerine yazılmaz; reddedilen istem taslağın önüne eklenir.
  // Eklenen bölüm istek kimliğiyle kaydedilir: geç kabulde yalnızca o bölüm
  // kalkar, taslak ve diğer isteklerin bölümleri korunur.
  function metniGeriYukle(kayit) {
    const giris = girisAlani();
    const ham = String(kayit.hamMetin || '');
    if (!giris || !ham.trim()) return false;
    bolumleriEsitle();
    const mevcut = sonDeger;
    const secBas = typeof giris.selectionStart === 'number' ? giris.selectionStart : null;
    const secSon = typeof giris.selectionEnd === 'number' ? giris.selectionEnd : null;
    if (!mevcut.trim()) {
      geriYuklemeler.length = 0;
      giris.value = ham;
      geriYuklemeler.unshift({ id: kayit.id, bas: 0, son: ham.length, duzenlendi: false, ozgun: ham, ayirici: false });
    } else if (mevcut.trim() === ham.trim() && !geriYuklemeler.length) {
      // Bağımsız yazılmış özdeş taslak: hiçbir şey eklenmez, sahiplik de alınmaz.
      return true;
    } else {
      // Ayırıcı satır sonu istem aralığına katılmaz: sınırda yeni satır ekleme
      // ilgisiz taslağı isteme bağlamaz; kaldırmada ayırıcı ayrı temizlenir.
      const ek = ham + '\n';
      giris.value = ek + mevcut;
      geriYuklemeler.forEach(function(b) { b.bas += ek.length; b.son += ek.length; });
      geriYuklemeler.unshift({ id: kayit.id, bas: 0, son: ham.length, duzenlendi: false, ozgun: ham, ayirici: true });
      if (secBas !== null && secSon !== null && typeof giris.setSelectionRange === 'function') {
        try { giris.setSelectionRange(secBas + ek.length, secSon + ek.length); } catch (e) {}
      }
    }
    sonDeger = String(giris.value || '');
    girisiYenile(giris);
    return true;
  }

  // Geç kabul (asıl balon DOM'dayken): yalnızca bu isteğin DÜZENLENMEMİŞ bölümü
  // kalkar; kullanıcının düzenlediği bölüm onun taslağı olarak kalır.
  function geriYuklemeyiUzlastir(kayit) {
    bolumleriKaldir(function(b) { return b.id === kayit.id && !b.duzenlendi; });
  }

  function reddet(kayit, bildirim) {
    const ayniGorunum = !kayit.ayrildi;
    balonuKaldir(kayit);
    const geriYuklendi = metniGeriYukle(kayit);
    // Karşılama yalnızca görünüm hâlâ aynıysa (kapta başka balon yoksa) geri gelir;
    // kullanıcı bu arada bir söyleşi açtıysa etkin söyleşi gizlenmez.
    const $karsilama = $('#welcome_fullscreen_container');
    if (ayniGorunum && kayit.karsilamaGizlendi && sohbetKabi && !sohbetKabi.children.length &&
        $karsilama.children().length > 0) {
      $karsilama.removeClass('hidden');
      $(sohbetKabi).hide();
    }
    let metin = bildirim || 'İstem gönderilemedi; metin giriş alanına geri yüklendi.';
    // Yalnız dosya istemi (metin yok): görünen ad dosya kimliğini kanıtlamaz
    // (aynı adlı yeni dosya seçilmiş olabilir); özgün ek kesinmiş gibi duyurulmaz.
    if (!geriYuklendi && !String(kayit.hamMetin || '').trim()) {
      const ek = document.querySelector('#file_prompt_indicator_ui');
      const ekVar = !!(ek && ek.children && ek.children.length > 0);
      const adDegisti = ekVar && !!kayit.ekImzasi && ekImzasi() !== kayit.ekImzasi;
      metin = 'Dosya istemi gönderilemedi ya da iletildiği doğrulanamadı. ' +
        (adDegisti ? 'Seçili dosya eki değişmiş olabilir; göndermeden önce dosya seçimini kontrol edin.'
          : (ekVar ? 'Göndermeden önce seçili dosya ekini kontrol edip tekrar deneyin.'
            : 'Lütfen dosyayı yeniden ekleyip tekrar deneyin.'));
    }
    // Daha yeni bir istem hâlâ gönderiliyorsa onun durumu silinmez: bildirim
    // önceki isteme ait olduğunu belirtir ve süren gönderimi yeniden duyurur.
    canliBildir(kilitliMi() ? 'Önceki istem: ' + metin + ' Yeni istem gönderiliyor…' : metin);
  }

  function kabulBekleyeniBitir(kayit, dugum) {
    listedenCikar(kabulBekleyenler, kayit);
    if (kayit.zamanlayici) clearTimeout(kayit.zamanlayici);
    if (dugum) solmayiKapat(dugum);
    balonuKaldir(kayit);
    // Geç kabulde geri yüklenen metin ancak asıl balon görünürken kalkar.
    if (dugum && kayit.gec) geriYuklemeyiUzlastir(kayit);
    dugmeDurumunuGuncelle();
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
      // Düzenlenmiş bölümler de kaldırılır; ilgisiz taslak aynen kalır.
      bolumleriKaldir(function() { return true; });
      geriYuklemeler.length = 0;
      canliBildir('');
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
    bolumleriEsitle();
    if (!mesajId || !geriYuklemeler.some(function(b) { return b.id === kayit.id; })) return;
    const dugum = typeof document.getElementById === 'function'
      ? document.getElementById('message_wrapper_' + mesajId) : null;
    if (dugum) { geriYuklemeyiUzlastir(kayit); return; }
    kayit.mesajId = mesajId;
    kayit.gec = true;
    kayit.sureDoldu = false;
    kabulBekleyenler.push(kayit);
    kayit.zamanlayici = setTimeout(function() {
      kayit.sureDoldu = true;
      dugmeDurumunuGuncelle();
    }, KABUL_DUGUM_BEKLEME_MS);
    dugmeDurumunuGuncelle();
    sahipsizleriBudala();
  }

  function sonucZamanAsimi(kayit) {
    if (bekleyenIstemler.indexOf(kayit) < 0) return;
    listedenCikar(bekleyenIstemler, kayit);
    zamanAsimlari.push(kayit);
    reddet(kayit, 'İstemin iletilip iletilmediği doğrulanamadı; metin giriş alanına geri yüklendi. Göndermeden önce söyleşiyi kontrol edin.');
    sahipsizleriBudala();
    dugmeDurumunuGuncelle();
  }

  // Bağlantı koptu: sonucu gelmemiş istemin kabul edilip edilmediği bilinemez.
  // Aynı metinli bir balon kabul kanıtı sayılmaz; istem kaybolmasın diye metin
  // girdiye geri yüklenir ve belirsizlik açıkça bildirilir (otomatik yeniden
  // gönderim yok; kabul edilmişse yeniden yüklemede kayıtlı söyleşide görünür).
  $(document).on('shiny:disconnected', function() {
    // Tüm istemler önce listeden çıkar: hepsi aynı anda düştüğü için bildirim
    // "yeni istem gönderiliyor" demez.
    bekleyenIstemler.splice(0).forEach(function(kayit) {
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

  // Kullanıcı düzenlemesi öncesi seçimi kaydet: tüm girdinin değiştirilmesi
  // (Ctrl+A + yapıştır/yaz) eski geri yükleme sahipliğini düşürür.
  if (typeof document.addEventListener === 'function') document.addEventListener('beforeinput', function(e) {
    if (!e.target || e.target !== girisAlani()) return;
    oncekiSecim = {
      bas: typeof e.target.selectionStart === 'number' ? e.target.selectionStart : -1,
      son: typeof e.target.selectionEnd === 'number' ? e.target.selectionEnd : -1,
      uzunluk: String(e.target.value || '').length
    };
  }, true);

  // Kullanıcı düzenlemesi bölüm aralıklarına imleç konumuyla uygulanır: silinen
  // bölümün sahipliği düşer, aynı metin sonradan yeniden yazılsa da geç kabul
  // onu silmez; düzenlenen bölüm sahip sıfırlamasına dek izlenir.
  if (typeof document.addEventListener === 'function') document.addEventListener('input', function(e) {
    if (!e.target || e.target !== girisAlani()) return;
    const imlec = typeof e.target.selectionEnd === 'number' ? e.target.selectionEnd : undefined;
    bolumleriEsitle(imlec);
    dugmeDurumunuGuncelle();
  }, true);

  window.MergenBekleyenIstem = {
    varMi: kilitliMi,
    // Girdi programatik olarak değiştiğinde (Escape ile temizleme gibi; 'input'
    // olayı yayılmaz) bölüm sahipliği ve düğme kilidi hemen uzlaştırılır.
    girdiDegisti: function() { bolumleriEsitle(); dugmeDurumunuGuncelle(); },
    ekle: function(hamMetin) {
      // Gönderim girdiyi tüketir: önceki geri yüklemelerin sahipliği biter.
      geriYuklemeler.length = 0;
      sahipsizleriBudala();
      const istemKimligi = 'istem_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 8);
      const gosterilecek = hamMetin.trim() || 'Seçili dosyaların özeti istendi.';
      const kayit = { id: istemKimligi, metin: gosterilecek, hamMetin: hamMetin, el: null,
                      karsilamaGizlendi: false, ayrildi: false, sunucuDugumu: null, ekImzasi: ekImzasi() };
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
