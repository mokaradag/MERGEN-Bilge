// www/js/bilge_savunmasi_menu.js
// Bilge Savunması menü/panel katmanı: kampanya harita kartları, haftalık
// meydan okuma + liderlik tablosu, oyuncu planları, topluluk operasyonu,
// kahraman galerisi, ilerleme/başarımlar, ayarlar ve yardım panelleri.
// Sunucudan gelen veriler BS.veri deposunda tutulur; tüm dinamik metinler
// htmlKacis süzgecinden geçer. Panel içerikleri yalnızca sayfa açıkken
// oluşturulur.

(function() {
  "use strict";

  var BS = window.BilgeSavunmasi = window.BilgeSavunmasi || {};
  var kacis = function(m) { return BS.yardimci.htmlKacis(m); };

  BS.veri = { init: null, liderlik: null, topluluk: null, planlar: null };

  var ayarKaydetZamanlayici = null;

  function yildizHtml(adet) {
    var html = "";
    for (var i = 1; i <= 3; i++) {
      html += '<i class="fa fa-star ' +
        (i <= adet ? "bs-yildiz-dolu" : "bs-yildiz-bos") +
        '" aria-hidden="true"></i>';
    }
    return '<span class="bs-yildizlar" aria-label="' + adet + ' yıldız">' +
      html + '</span>';
  }

  function kampanyaKaydi(haritaId, zorluk) {
    var veri = BS.veri.init;
    if (!veri || !veri.kampanya) return null;
    for (var i = 0; i < veri.kampanya.length; i++) {
      var satir = veri.kampanya[i];
      if (satir.MapID === haritaId && satir.Difficulty === zorluk) return satir;
    }
    return null;
  }

  function haritaKilitliMi(haritaId) {
    var katalog = BS.veri.init.haritalar;
    var kayit = katalog[haritaId];
    if (!kayit || !kayit.acilis_kosulu) return false;
    if (!BS.veri.init.kalicilik) return false;   // kalıcılık yokken serbest
    var onceki = kampanyaKaydi(kayit.acilis_kosulu, "normal");
    var oncekiGelismis = kampanyaKaydi(kayit.acilis_kosulu, "gelismis");
    var tamam = (onceki && onceki.CompletedCount > 0) ||
                (oncekiGelismis && oncekiGelismis.CompletedCount > 0);
    return !tamam;
  }

  BS.menu = {

    // ── Liderlik tablosu satırı (zengin: ad + rumuz + departman) ──────────────
    liderlikSatiri: function(g) {
      var madalya = "";
      if (g.sira === 1) madalya = '<span class="bs-madalya bs-madalya-altin" aria-hidden="true"><i class="fa fa-trophy"></i></span>';
      else if (g.sira === 2) madalya = '<span class="bs-madalya bs-madalya-gumus" aria-hidden="true"><i class="fa fa-medal"></i></span>';
      else if (g.sira === 3) madalya = '<span class="bs-madalya bs-madalya-bronz" aria-hidden="true"><i class="fa fa-medal"></i></span>';

      var harf = (g.oyuncu || "?").charAt(0).toLocaleUpperCase("tr-TR");
      return '<tr' + (g.benim ? ' class="bs-liderlik-benim"' : "") + '>' +
        '<td class="bs-liderlik-sira">' + madalya + g.sira + '</td>' +
        '<td><span class="bs-oyuncu-hucre">' +
          '<span class="bs-oyuncu-cip" aria-hidden="true">' + kacis(harf) + '</span>' +
          '<span class="bs-oyuncu-kimlik"><b>' + kacis(g.oyuncu) +
            (g.benim ? " (sen)" : "") + '</b>' +
            (g.rumuz ? '<small>@' + kacis(g.rumuz) + '</small>' : "") +
          '</span></span></td>' +
        '<td class="bs-liderlik-departman">' + kacis(g.departman || "—") + '</td>' +
        '<td class="bs-liderlik-puan">' + BS.yardimci.sayiBicimle(g.puan) + '</td>' +
        '<td>' + Math.round(g.cekirdek) + '</td>' +
        '<td>' + g.son_dalga + '</td>' +
        '<td>' + BS.yardimci.sureBicimle(g.sure_saniye) + '</td></tr>';
    },

    // ── Öncü Uzman seçim ekranı (koşu öncesi; premium tam sayfa kaplama) ──────
    secimEkraniHtml: function(baslamaBilgisi) {
      var veri = BS.veri.init;
      var harita = veri.haritalar[baslamaBilgisi.harita] ||
        { ad: "Haftalık Meydan Okuma" };
      var zorlukAd = baslamaBilgisi.zorluk === "gelismis" ? "Gelişmiş" : "Normal";
      if (baslamaBilgisi.mod === "haftalik") zorlukAd = "Haftalık · Gelişmiş";

      return '<div class="bs-secim-ekrani" role="dialog" ' +
        'aria-label="Öncü Uzman seçimi">' +
        '<div class="bs-secim-baslik-alani">' +
          '<p class="bs-secim-ust-etiket">GÖREV HAZIRLIĞI</p>' +
          '<h2>' + kacis(harita.ad || "") + '</h2>' +
          '<p class="bs-secim-alt-etiket">' + kacis(zorlukAd) +
          ' · Öncü Uzmanını seç: ilk konuşlandırması ücretsiz, yeteneği %20 ' +
          'daha hızlı dolar. Diğer dört uzman da görevde yanında.</p>' +
        '</div>' +
        '<div class="bs-secim-kartlari">' +
        (veri.personalar || []).map(function(persona) {
          var tanim = BS.denge.kahramanAl(persona.id) || {};
          return '<button type="button" class="bs-secim-karti" ' +
            'data-bs-oncu="' + kacis(persona.id) + '" ' +
            'style="--bs-aksan:' + kacis(persona.aksan) + '" ' +
            'aria-pressed="false" ' +
            'aria-label="' + kacis(persona.tam_ad + " - " + persona.rol) + '">' +
            '<span class="bs-secim-portre">' +
              '<img src="' + kacis(persona.portre || persona.avatar || "") + '" ' +
                   'alt="" loading="lazy" ' +
                   "onerror=\"this.style.display='none';" +
                   "this.parentElement.classList.add('bs-portre-yedek');" +
                   "this.parentElement.setAttribute('data-harf','" +
                   kacis((persona.ad || "?").charAt(0)) + "')\">" +
            '</span>' +
            '<span class="bs-secim-adi">' + kacis(persona.tam_ad) + '</span>' +
            '<span class="bs-secim-rolu">' + kacis(persona.rol) + ' · ' +
              kacis(persona.unvan) + '</span>' +
            '<span class="bs-secim-yetenegi"><i class="fa fa-bolt" ' +
              'aria-hidden="true"></i> ' + kacis(persona.yetenek_ad) + '</span>' +
            '<span class="bs-secim-istatistigi">Maliyet ' +
              (tanim.maliyet || "-") + ' · Menzil ' + (tanim.menzil || "-") +
            '</span>' +
            '<span class="bs-secim-onay" aria-hidden="true">' +
              '<i class="fa fa-check"></i> ÖNCÜ</span>' +
          '</button>';
        }).join("") +
        '</div>' +
        '<div class="bs-secim-eylemler">' +
          '<button type="button" class="bs-yan-dugme bs-yan-dugme-birincil ' +
                  'bs-secim-baslat" data-bs-secim="baslat" disabled>' +
            '<i class="fa fa-shield-halved" aria-hidden="true"></i> ' +
            'Savunmayı Başlat</button>' +
          '<button type="button" class="bs-yan-dugme" data-bs-secim="vazgec">' +
            'Vazgeç</button>' +
        '</div></div>';
    },

    // ── Öncü Uzman seçim kaplaması: aç/kapat ve seçim akışı ───────────────────
    secimEkraniAc: function(istek, onBaslat) {
      BS.menu.secimEkraniKapat();

      // Haftalık/plan modlarında başlık için gerçek harita gösterilir.
      var gosterim = Object.assign({}, istek);
      if (istek.mod === "haftalik" && BS.veri.init.haftalik) {
        gosterim.harita = BS.veri.init.haftalik.harita;
        gosterim.zorluk = "gelismis";
      }
      if (istek.mod === "plan" && istek.planBilgi) {
        gosterim.harita = istek.planBilgi.harita;
        gosterim.zorluk = istek.planBilgi.zorluk;
      }

      var kaplama = document.createElement("div");
      kaplama.className = "bs-secim-kaplamasi";
      kaplama.id = "bs-secim-kaplamasi";
      kaplama.innerHTML = BS.menu.secimEkraniHtml(gosterim);
      document.body.appendChild(kaplama);

      var secilen = null;
      kaplama.addEventListener("click", function(e) {
        var kart = e.target.closest("[data-bs-oncu]");
        if (kart) {
          secilen = kart.getAttribute("data-bs-oncu");
          kaplama.querySelectorAll("[data-bs-oncu]").forEach(function(k) {
            var aktif = k === kart;
            k.classList.toggle("bs-secim-secili", aktif);
            k.setAttribute("aria-pressed", aktif ? "true" : "false");
          });
          var baslat = kaplama.querySelector('[data-bs-secim="baslat"]');
          if (baslat) baslat.disabled = false;
          return;
        }
        var eylem = e.target.closest("[data-bs-secim]");
        if (!eylem) return;
        e.preventDefault();
        if (eylem.getAttribute("data-bs-secim") === "baslat" && secilen) {
          BS.menu.secimEkraniKapat();
          onBaslat(secilen);
        } else if (eylem.getAttribute("data-bs-secim") === "vazgec") {
          BS.menu.secimEkraniKapat();
        }
      });
    },

    secimEkraniKapat: function() {
      var eski = document.getElementById("bs-secim-kaplamasi");
      if (eski && eski.parentElement) eski.parentElement.removeChild(eski);
    },

    // ── Oyun ayarı değişikliği: uygula ve gecikmeli kalıcılaştır ──────────────
    ayarIsle: function(hedef) {
      var ad = hedef.getAttribute("data-bs-ayar");
      if (!ad) return;
      if (ad === "kalite") {
        BS.kalite.ayarla(hedef.value);
      } else if (ad === "sessiz") {
        BS.ses.ayarla({ sessiz: hedef.checked });
      } else if (ad === "muzik" || ad === "efekt") {
        var ayar = {};
        ayar[ad] = parseInt(hedef.value, 10) / 100;
        BS.ses.ayarla(ayar);
      }
      if (ayarKaydetZamanlayici) clearTimeout(ayarKaydetZamanlayici);
      ayarKaydetZamanlayici = setTimeout(function() {
        var ses = BS.ses.ayarlariAl();
        BS.kopru.ayarKaydet({
          kalite: BS.kalite.seviye,
          sessiz: ses.sessiz, muzik: ses.muzik, efekt: ses.efekt
        });
      }, 800);
    },

    // ── Profil özeti (menü üst sağ) ───────────────────────────────────────────
    profilOzetiCiz: function(kok) {
      var hedef = kok.querySelector(".bs-profil-ozeti");
      if (!hedef) return;
      var veri = BS.veri.init;
      if (!veri || !veri.kalicilik || !veri.profil) {
        hedef.innerHTML = "";
        return;
      }
      hedef.innerHTML =
        '<div class="bs-profil-karti">' +
          '<span class="bs-profil-seviye">Sv. ' + (veri.profil.seviye || 1) + '</span>' +
          '<span class="bs-profil-detay">' +
            BS.yardimci.sayiBicimle(veri.profil.xp || 0) + ' XP · ' +
            BS.yardimci.sayiBicimle(veri.profil.toplam_puan || 0) + ' toplam puan' +
          '</span>' +
        '</div>';
    },

    // ── Panel yönlendirme ─────────────────────────────────────────────────────
    panelGoster: function(kok, ad) {
      var alan = kok.querySelector(".bs-panel-alani");
      if (!alan) return;
      var cizenler = {
        kampanya: BS.menu.kampanyaPaneli,
        haftalik: BS.menu.haftalikPaneli,
        planlar: BS.menu.planlarPaneli,
        topluluk: BS.menu.toplulukPaneli,
        kahramanlar: BS.menu.kahramanlarPaneli,
        ilerleme: BS.menu.ilerlemePaneli,
        ayarlar: BS.menu.ayarlarPaneli,
        yardim: BS.menu.yardimPaneli
      };
      var cizen = cizenler[ad];
      alan.innerHTML = cizen ? cizen() : "";
      alan.setAttribute("data-bs-acik-panel", cizen ? ad : "");
      if (cizen) alan.scrollIntoView({ behavior: "smooth", block: "nearest" });
    },

    // ── Kampanya ──────────────────────────────────────────────────────────────
    kampanyaPaneli: function() {
      var veri = BS.veri.init;
      // Harita sırası tek kaynaktan (BS.haritalar) türetilir; yeni harita
      // eklendiğinde menü kendiliğinden genişler.
      var siralar = BS.haritalar.siraliListe().map(function(h) { return h.id; });

      return '<div class="bs-panel"><h3 class="bs-panel-baslik">Kampanya</h3>' +
        '<div class="bs-harita-kartlari">' +
        siralar.map(function(id) {
          var harita = veri.haritalar[id];
          var kilitli = haritaKilitliMi(id);
          var normalKayit = kampanyaKaydi(id, "normal");
          var gelismisKayit = kampanyaKaydi(id, "gelismis");
          var gelismisKilitli = veri.kalicilik &&
            !(normalKayit && normalKayit.CompletedCount > 0);

          var tema = BS.haritalar.haritaAl(id);
          var vurgu = (tema && tema.tema && tema.tema.vurgu) || "#4cc9f0";
          return '<div class="bs-harita-karti' +
                 (kilitli ? " bs-harita-kilitli" : "") + '" ' +
                 'style="--bs-aksan:' + kacis(vurgu) + '">' +
            '<div class="bs-harita-ust">' +
              '<h4>' + kacis(harita.ad) + '</h4>' +
              (kilitli
                ? '<span class="bs-kilit-rozeti"><i class="fa fa-lock" ' +
                  'aria-hidden="true"></i> Kilitli</span>'
                : yildizHtml(normalKayit ? normalKayit.Stars : 0)) +
            '</div>' +
            '<p class="bs-harita-aciklama">' + kacis(harita.aciklama) + '</p>' +
            '<p class="bs-harita-detay">' + harita.dalga_sayisi + ' dalga' +
              (normalKayit && normalKayit.BestScore > 0
                ? ' · En iyi: ' + BS.yardimci.sayiBicimle(normalKayit.BestScore)
                : "") + '</p>' +
            (kilitli
              ? '<p class="bs-harita-kilit-notu">Önce önceki haritayı tamamla.</p>'
              : '<div class="bs-harita-dugmeler">' +
                '<button type="button" class="bs-yan-dugme bs-yan-dugme-birincil" ' +
                        'data-bs-komut="harita-baslat" data-bs-arg="' +
                        kacis(id) + ':normal">Normal</button>' +
                '<button type="button" class="bs-yan-dugme" ' +
                        'data-bs-komut="harita-baslat" data-bs-arg="' +
                        kacis(id) + ':gelismis"' +
                        (gelismisKilitli ? " disabled title=\"Önce normal zorlukta tamamla\"" : "") +
                        '>Gelişmiş' +
                        (gelismisKayit && gelismisKayit.Stars > 0
                          ? " " + yildizHtml(gelismisKayit.Stars) : "") +
                '</button></div>')
          + '</div>';
        }).join("") + '</div></div>';
    },

    // ── Haftalık meydan okuma ─────────────────────────────────────────────────
    haftalikPaneli: function() {
      var veri = BS.veri.init;
      var meydan = veri.haftalik || {};
      var harita = veri.haritalar[meydan.harita] || { ad: meydan.harita };
      var tablo = BS.veri.liderlik;

      var tabloHtml = '<p class="bs-yan-notu">Liderlik tablosu yükleniyor...</p>';
      if (tablo && tablo.tablo) {
        var girisler = (tablo.tablo.ilkler || []).concat(tablo.tablo.yakinlar || []);
        tabloHtml = girisler.length === 0
          ? '<p class="bs-yan-notu">Bu hafta henüz giriş yok. İlk sen ol!</p>'
          : '<table class="bs-liderlik-tablosu">' +
            '<caption class="bs-gorsel-gizli">Haftalık liderlik tablosu</caption>' +
            '<thead><tr><th>#</th><th>Oyuncu</th><th>Departman</th><th>Puan</th>' +
            '<th>Çekirdek</th><th>Dalga</th><th>Süre</th></tr></thead><tbody>' +
            girisler.map(BS.menu.liderlikSatiri).join("") + '</tbody></table>';
        if (tablo.tablo.benim_sira) {
          tabloHtml += '<p class="bs-yan-notu">Sıran: ' +
            tablo.tablo.benim_sira + ' / ' + tablo.tablo.toplam_katilimci + '</p>';
        }
      } else if (!veri.kalicilik) {
        tabloHtml = '<p class="bs-yan-notu">Liderlik tablosu için oyun ' +
          'tablolarının kurulmuş olması gerekir.</p>';
      }

      return '<div class="bs-panel"><h3 class="bs-panel-baslik">' +
        'Haftalık Meydan Okuma · ' + kacis(meydan.hafta_kodu || "") + '</h3>' +
        '<div class="bs-haftalik-bilgi">' +
          '<p><b>' + kacis(harita.ad || "") + '</b> · Gelişmiş zorluk · ' +
          'Değiştirici: <b>' + kacis(meydan.degistirici ? meydan.degistirici.ad : "-") +
          '</b></p>' +
          '<p class="bs-yan-notu">' +
            kacis(meydan.degistirici ? meydan.degistirici.aciklama : "") +
          '</p>' +
          '<p class="bs-yan-notu">Herkes aynı haritada, aynı tohum ve dalga ' +
          'bileşimiyle yarışır. Sıralama: puan, kalan çekirdek, dalga, süre, ' +
          'erken gönderim.</p>' +
          '<button type="button" class="bs-yan-dugme bs-yan-dugme-birincil" ' +
                  'data-bs-komut="haftalik-baslat">' +
            '<i class="fa fa-trophy" aria-hidden="true"></i> Meydan Okumaya Başla' +
          '</button>' +
        '</div>' +
        '<div class="bs-liderlik-kabi">' + tabloHtml + '</div></div>';
    },

    // ── Oyuncu planları ───────────────────────────────────────────────────────
    planlarPaneli: function() {
      var veri = BS.veri.init;
      var planlar = BS.veri.planlar;

      var liste = '<p class="bs-yan-notu">Planlar yükleniyor...</p>';
      if (!veri.kalicilik) {
        liste = '<p class="bs-yan-notu">Savunma planları için oyun ' +
          'tablolarının kurulmuş olması gerekir.</p>';
      } else if (planlar) {
        liste = planlar.length === 0
          ? '<p class="bs-yan-notu">Henüz yayınlanmış plan yok. Bir koşuyu ' +
            'bitirdikten sonra sonuç ekranından planını yayınlayabilirsin.</p>'
          : planlar.map(function(plan) {
              var sonuc = plan.yaratici_sonucu || {};
              return '<div class="bs-plan-karti">' +
                '<div class="bs-plan-ust"><b>' + kacis(plan.baslik) + '</b>' +
                  yildizHtml(sonuc.yildiz || 0) + '</div>' +
                '<p class="bs-plan-detay">' + kacis(plan.yaratici) + ' · ' +
                  kacis(plan.harita_ad) + ' · ' +
                  (plan.zorluk === "gelismis" ? "Gelişmiş" : "Normal") +
                  (sonuc.puan ? ' · ' + BS.yardimci.sayiBicimle(sonuc.puan) +
                   ' puan' : "") + '</p>' +
                '<div class="bs-plan-dugmeler">' +
                  '<button type="button" class="bs-yan-dugme bs-yan-dugme-birincil" ' +
                    'data-bs-komut="plan-dene" data-bs-arg="' + plan.plan_id + '">' +
                    'Aynı Koşulda Dene</button>' +
                  (plan.benim
                    ? '<button type="button" class="bs-yan-dugme bs-yan-dugme-tehlike" ' +
                      'data-bs-komut="plan-sil" data-bs-arg="' + plan.plan_id + '">' +
                      'Kaldır</button>'
                    : "") +
                '</div></div>';
            }).join("");
      }

      return '<div class="bs-panel"><h3 class="bs-panel-baslik">Oyuncu Planları</h3>' +
        '<p class="bs-yan-notu">Bir plan; harita, tohum ve yaratıcısının sonucunu ' +
        'taşır. Aynı koşullarda oynayıp sonucunu kıyaslarsın.</p>' +
        '<div class="bs-plan-listesi">' + liste + '</div></div>';
    },

    // ── Topluluk operasyonu ───────────────────────────────────────────────────
    toplulukPaneli: function() {
      var veri = BS.veri.init;
      var topluluk = BS.veri.topluluk;

      var icerik = '<p class="bs-yan-notu">Topluluk verisi yükleniyor...</p>';
      if (!veri.kalicilik) {
        icerik = '<p class="bs-yan-notu">Topluluk operasyonu için oyun ' +
          'tablolarının kurulmuş olması gerekir.</p>';
      } else if (topluluk && topluluk.toplamlar) {
        var t = topluluk.toplamlar;
        var oran = BS.yardimci.kirp(
          (t.etkisizlestirilen || 0) / Math.max(1, t.hedef_etkisizlestirilen), 0, 1
        );
        icerik =
          '<div class="bs-topluluk-hedef">' +
            '<p><b>Haftalık hedef:</b> ' +
              BS.yardimci.sayiBicimle(t.hedef_etkisizlestirilen) +
              ' tehdit etkisizleştir</p>' +
            '<div class="bs-ilerleme-cubugu" role="progressbar" ' +
                 'aria-valuemin="0" aria-valuemax="100" aria-valuenow="' +
                 Math.round(oran * 100) + '">' +
              '<div class="bs-ilerleme-dolgu" style="width:' +
                (oran * 100).toFixed(1) + '%"></div>' +
            '</div>' +
            '<p class="bs-yan-notu">' + BS.yardimci.sayiBicimle(t.etkisizlestirilen) +
              ' / ' + BS.yardimci.sayiBicimle(t.hedef_etkisizlestirilen) +
              ' · ' + t.katilimci + ' katılımcı · ' +
              BS.yardimci.sayiBicimle(t.savunulan_dalga) + ' dalga savunuldu</p>' +
          '</div>' +
          (t.benim
            ? '<div class="bs-topluluk-benim"><b>Senin katkın:</b> ' +
              BS.yardimci.sayiBicimle(t.benim.etkisizlestirilen) +
              ' tehdit · ' + BS.yardimci.sayiBicimle(t.benim.savunulan_dalga) +
              ' dalga · ' + BS.yardimci.sayiBicimle(t.benim.toplam_puan) +
              ' puan</div>'
            : "");
      }

      return '<div class="bs-panel"><h3 class="bs-panel-baslik">' +
        'Topluluk Operasyonu</h3>' +
        '<p class="bs-yan-notu">Tamamlanan her koşu haftalık ortak hedefe katkı ' +
        'sağlar. Bu birlikte oynanan canlı bir mod değil, ortak bir hedeftir.</p>' +
        icerik + '</div>';
    },

    // ── Kahramanlar ───────────────────────────────────────────────────────────
    kahramanlarPaneli: function() {
      var veri = BS.veri.init;
      var ilerlemeler = {};
      (veri.kahraman_ilerlemesi || []).forEach(function(satir) {
        ilerlemeler[satir.HeroID] = satir;
      });

      return '<div class="bs-panel"><h3 class="bs-panel-baslik">Kahramanlar</h3>' +
        '<div class="bs-kahraman-galerisi">' +
        veri.personalar.map(function(persona) {
          var tanim = BS.denge.kahramanAl(persona.id) || {};
          var ilerleme = ilerlemeler[persona.id];
          return '<div class="bs-galeri-karti" style="--bs-aksan:' +
                 kacis(persona.aksan) + '">' +
            '<div class="bs-galeri-portre">' +
              '<img src="' + kacis(persona.portre || persona.avatar || "") + '" ' +
                   'alt="' + kacis(persona.tam_ad) + '" loading="lazy" ' +
                   "onerror=\"this.style.display='none';" +
                   "this.parentElement.classList.add('bs-portre-yedek');" +
                   "this.parentElement.setAttribute('data-harf','" +
                   kacis((persona.ad || "?").charAt(0)) + "')\">" +
            '</div>' +
            '<div class="bs-galeri-bilgi">' +
              '<h4>' + kacis(persona.tam_ad) + '</h4>' +
              '<p class="bs-galeri-rol">' + kacis(persona.rol) + ' · ' +
                kacis(persona.unvan) + '</p>' +
              '<p class="bs-galeri-aciklama">' + kacis(persona.rol_aciklama) + '</p>' +
              '<p class="bs-galeri-yetenek"><i class="fa fa-bolt" ' +
                'aria-hidden="true"></i> <b>' + kacis(persona.yetenek_ad) +
                ':</b> ' + kacis(persona.yetenek_aciklama) + '</p>' +
              '<p class="bs-galeri-istatistik">Maliyet ' + (tanim.maliyet || "-") +
                ' · Menzil ' + (tanim.menzil || "-") +
                (ilerleme
                  ? ' · ' + ilerleme.UsesCount + ' görev · ' +
                    BS.yardimci.sayiBicimle(ilerleme.MasteryXP) + ' ustalık'
                  : "") + '</p>' +
            '</div></div>';
        }).join("") + '</div></div>';
    },

    // ── İlerleme ve başarımlar ────────────────────────────────────────────────
    ilerlemePaneli: function() {
      var veri = BS.veri.init;
      var kazanilan = {};
      (veri.basarimlar || []).forEach(function(satir) {
        kazanilan[satir.ItemID] = satir;
      });

      var profilHtml = "";
      if (veri.kalicilik && veri.profil) {
        profilHtml = '<div class="bs-ilerleme-profil">' +
          '<span class="bs-profil-seviye">Seviye ' + veri.profil.seviye + '</span>' +
          '<span>' + BS.yardimci.sayiBicimle(veri.profil.xp) + ' XP · Toplam ' +
            BS.yardimci.sayiBicimle(veri.profil.toplam_puan) + ' puan</span></div>';
      } else {
        profilHtml = '<p class="bs-yan-notu">Kalıcı ilerleme için oyun ' +
          'tablolarının kurulmuş olması gerekir; şu an sonuçlar kaydedilmiyor.</p>';
      }

      return '<div class="bs-panel"><h3 class="bs-panel-baslik">' +
        'İlerleme ve Başarımlar</h3>' + profilHtml +
        '<div class="bs-basarim-listesi">' +
        (veri.basarim_katalogu || []).map(function(tanim) {
          var var_mi = !!kazanilan[tanim.id];
          return '<div class="bs-basarim-karti' +
                 (var_mi ? " bs-basarim-kazanildi" : "") + '">' +
            '<i class="fa ' + (tanim.tur === "acilim" ? "fa-unlock" : "fa-medal") +
              '" aria-hidden="true"></i>' +
            '<div><b>' + kacis(tanim.ad) + '</b>' +
            '<p>' + kacis(tanim.aciklama) + '</p></div>' +
            '<span class="bs-basarim-durum">' +
              (var_mi ? "Kazanıldı" : "Kilitli") + '</span>' +
          '</div>';
        }).join("") + '</div></div>';
    },

    // ── Ayarlar ───────────────────────────────────────────────────────────────
    ayarlarPaneli: function() {
      var ses = BS.ses.ayarlariAl();
      return '<div class="bs-panel"><h3 class="bs-panel-baslik">Oyun Ayarları</h3>' +
        '<div class="bs-ayar-grubu">' +
          '<label for="bs-ayar-kalite">Görsel kalite</label>' +
          '<select id="bs-ayar-kalite" data-bs-ayar="kalite">' +
            '<option value="yuksek"' +
              (BS.kalite.seviye === "yuksek" ? " selected" : "") + '>Yüksek</option>' +
            '<option value="dengeli"' +
              (BS.kalite.seviye === "dengeli" ? " selected" : "") + '>Dengeli</option>' +
            '<option value="performans"' +
              (BS.kalite.seviye === "performans" ? " selected" : "") +
              '>Performans</option>' +
          '</select></div>' +
        '<div class="bs-ayar-grubu">' +
          '<label for="bs-ayar-sessiz">' +
            '<input type="checkbox" id="bs-ayar-sessiz" data-bs-ayar="sessiz"' +
            (ses.sessiz ? " checked" : "") + '> Sesleri kapat</label></div>' +
        '<div class="bs-ayar-grubu">' +
          '<label for="bs-ayar-muzik">Müzik sesi</label>' +
          '<input type="range" id="bs-ayar-muzik" data-bs-ayar="muzik" ' +
                 'min="0" max="100" value="' + Math.round(ses.muzik * 100) + '">' +
        '</div>' +
        '<div class="bs-ayar-grubu">' +
          '<label for="bs-ayar-efekt">Efekt sesi</label>' +
          '<input type="range" id="bs-ayar-efekt" data-bs-ayar="efekt" ' +
                 'min="0" max="100" value="' + Math.round(ses.efekt * 100) + '">' +
        '</div>' +
        '<p class="bs-yan-notu">Ses dosyaları kurulu değilse oyun sessiz çalışır. ' +
        'Sistem "azaltılmış hareket" tercihine her zaman uyulur.</p></div>';
    },

    // ── Yardım ────────────────────────────────────────────────────────────────
    yardimPaneli: function() {
      return '<div class="bs-panel"><h3 class="bs-panel-baslik">Nasıl Oynanır</h3>' +
        '<ol class="bs-yardim-listesi">' +
        '<li><b>Savunucu yerleştir:</b> Alttaki kahraman kartına tıkla, sonra ' +
        'haritada uygun (yeşil) bir hücreye tıkla. Her uzmandan sahada tek ' +
        'örnek bulunur.</li>' +
        '<li><b>Dalgayı başlat:</b> Geri sayımı bekle ya da erken başlat bonusu ' +
        'için "Dalgayı Başlat"a bas. Rota üzerindeki tehditler Bilgi ' +
        'Çekirdeği\'ne ulaşırsa çekirdek hasar alır.</li>' +
        '<li><b>Kule inşa et:</b> Alt çubuğun sağındaki kule kartlarından ' +
        '(Gözcü Kulesi, Veri Topçusu, Kripto Işını) istediğin kadar kule kur; ' +
        'kuleler de üç kademelidir ve sökülebilir. Gözcü hızlı tekil atış, ' +
        'Topçu alan hasarı, Kripto zırh delme sağlar.</li>' +
        '<li><b>Kaynak yönet:</b> Etkisizleştirilen her tehdit kaynak verir. ' +
        'Kaynakla yeni savunucu/kule yerleştir veya kademe yükselt.</li>' +
        '<li><b>Yetenek kullan:</b> Her uzmanın güçlü bir aktif yeteneği vardır ' +
        '(kartın yanındaki şimşek). Patron dalgalarında fark yaratır.</li>' +
        '<li><b>Sinerji kur:</b> Emre yakın savunucuları hızlandırır; İpek ' +
        'menzil ve kaynak desteği verir; Can\'ın işaretlediği hedefe herkes ' +
        'daha çok hasar vurur; Deniz yavaşlatır, Selin çekirdeği onarır.</li>' +
        '<li><b>Kısayollar:</b> 1-5 savunucu seç, 6-8 kule seç, Q seçili ' +
        'yetenek, Boşluk duraklat, F hız, Esc iptal/menü. Üst çubuktaki ' +
        'genişletme düğmesi oyunu tam ekrana alır.</li>' +
        '</ol>' +
        '<p class="bs-yan-notu">Yıldızlar kalan çekirdeğe göre verilir: ' +
        '%90+ üç, %60+ iki, zafer bir yıldız. Puanı sunucu doğrular ve ' +
        'yeniden hesaplar.</p></div>';
    }
  };
})();
