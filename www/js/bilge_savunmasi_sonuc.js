// www/js/bilge_savunmasi_sonuc.js
// Bilge Savunması sonuç ekranı katmanı: zafer/yenilgi paneli, yıldız/puan/XP
// sunumu, yeni başarım rozetleri, plan (blueprint) kıyaslaması ve plan
// yayınlama akışı. Kalıcılık kapalıyken sunucu formülünün yerel aynasıyla
// yalnızca GÖSTERİM amaçlı puan üretir (ödül/kayıt yazılmaz; bağlayıcı puan
// her zaman sunucudur). bilge_savunmasi_uygulama.js bu katmanı çağırır.

(function() {
  "use strict";

  var BS = window.BilgeSavunmasi = window.BilgeSavunmasi || {};
  var kacis = function(m) { return BS.yardimci.htmlKacis(m); };

  BS.sonuc = {

    // Sunucu puan formülünün gösterim amaçlı yerel aynası.
    yerelPuan: function(ozet) {
      var ham = 0;
      (ozet.dalga_ozetleri || []).forEach(function(d) { ham += d.puan || 0; });
      var bonus = (ozet.son_cekirdek || 0) * 25 + (ozet.zafer ? 500 : 0);
      var carpan = ozet.zorluk === "gelismis" ? 1.35 : 1;
      var harita = BS.haritalar.haritaAl(ozet.harita);
      var oran = harita ? (ozet.son_cekirdek / harita.tabanCekirdek) : 0;
      return {
        puan: Math.round((ham + bonus) * carpan),
        yildiz: !ozet.zafer ? 0 : (oran >= 0.9 ? 3 : (oran >= 0.6 ? 2 : 1))
      };
    },

    // Eldeki son sunucu paketi yoksa yerel özetten sonuç üretir.
    sonPaket: function(kosu) {
      if (kosu.sonSonuc) return kosu.sonSonuc;
      var p = BS.sonuc.yerelPuan(kosu.ozet || kosu.sim.ozetPaketi());
      return {
        kabul: true, zafer: kosu.sim.durum.zafer,
        puan: p.puan, yildiz: p.yildiz, xp: 0, yerel: !kosu.kalici
      };
    },

    goster: function(kosu, sonuc) {
      if (!kosu || !sonuc) return;

      var basarimHtml = "";
      if (sonuc.yeni_basarimlar && sonuc.yeni_basarimlar.length) {
        var katalog = {};
        ((BS.veri.init && BS.veri.init.basarim_katalogu) || []).forEach(function(b) {
          katalog[b.id] = b;
        });
        basarimHtml = '<div class="bs-sonuc-basarimlar">' +
          sonuc.yeni_basarimlar.map(function(id) {
            var b = katalog[id] || { ad: id };
            return '<span class="bs-basarim-rozeti"><i class="fa fa-medal" ' +
              'aria-hidden="true"></i> ' + kacis(b.ad) + '</span>';
          }).join("") + '</div>';
      }

      var planHtml = "";
      var haftalikKosu = kosu.mod === "haftalik" ||
        (kosu.sim && kosu.sim.durum && kosu.sim.durum.mod === "haftalik");
      if (!haftalikKosu && !sonuc.yerel && sonuc.kabul && kosu.kosuId) {
        planHtml = '<button type="button" class="bs-yan-dugme" ' +
          'data-bs-komut="plan-yayinla">' +
          '<i class="fa fa-compass-drafting" aria-hidden="true"></i> ' +
          'Savunma Planını Yayınla</button>';
      }

      var kiyasHtml = "";
      if (kosu.planBilgi && kosu.planBilgi.yaratici_sonucu) {
        var hedefPuan = kosu.planBilgi.yaratici_sonucu.puan || 0;
        var fark = (sonuc.puan || 0) - hedefPuan;
        kiyasHtml = '<p class="bs-kaplama-notu">Plan sahibi: ' +
          BS.yardimci.sayiBicimle(hedefPuan) + ' puan · Sen: ' +
          BS.yardimci.sayiBicimle(sonuc.puan || 0) +
          (fark >= 0 ? ' — planı geçtin!' : ' — ' +
           BS.yardimci.sayiBicimle(-fark) + ' puan geride') + '</p>';
      }

      var yildizlar = "";
      for (var i = 1; i <= 3; i++) {
        yildizlar += '<i class="fa fa-star ' +
          (i <= (sonuc.yildiz || 0) ? "bs-yildiz-dolu" : "bs-yildiz-bos") +
          '" aria-hidden="true"></i>';
      }

      kosu.hud.kaplamaGoster(
        '<h3>' + (sonuc.zafer ? "Zafer!" : (sonuc.kabul ? "Çekirdek Düştü" :
          "Sonuç Doğrulanamadı")) + '</h3>' +
        (sonuc.kabul
          ? '<div class="bs-sonuc-yildizlar" aria-label="' + (sonuc.yildiz || 0) +
            ' yıldız">' + yildizlar + '</div>' +
            '<p class="bs-sonuc-puan">' + BS.yardimci.sayiBicimle(sonuc.puan || 0) +
            ' puan</p>' +
            (sonuc.yerel
              ? '<p class="bs-kaplama-notu">Kalıcılık kapalı: bu sonuç kaydedilmedi.</p>'
              : '<p class="bs-kaplama-notu">+' + (sonuc.xp || 0) + ' XP' +
                (sonuc.seviye ? ' · Seviye ' + sonuc.seviye : "") +
                (sonuc.tekrar ? ' · (daha önce kaydedilmişti)' : "") + '</p>') +
            kiyasHtml + basarimHtml
          : '<p class="bs-kaplama-notu">Neden: ' +
            kacis(String(sonuc.neden || "bilinmiyor")) + '</p>') +
        '<div class="bs-sonuc-dugmeler">' +
          '<button type="button" class="bs-yan-dugme bs-yan-dugme-birincil" ' +
                  'data-bs-komut="yeniden">Tekrar Oyna</button>' +
          planHtml +
          '<button type="button" class="bs-yan-dugme" data-bs-komut="menu-don">' +
            'Menüye Dön</button>' +
        '</div>',
        sonuc.zafer ? "bs-kaplama-zafer" : ""
      );
    },

    // ── Plan yayınlama akışı ──────────────────────────────────────────────────
    planYayinlaGoster: function(kosu) {
      var haftalikKosu = kosu && (kosu.mod === "haftalik" ||
        (kosu.sim && kosu.sim.durum && kosu.sim.durum.mod === "haftalik"));
      if (haftalikKosu) {
        kosu.hud.kaplamaGoster(
          '<h3>Plan Yayınlanamaz</h3>' +
          '<p class="bs-kaplama-notu">Haftalık meydan okuma koşuları özel ' +
          'değiştiriciyle oynandığı için savunma planı olarak yayınlanamaz.</p>' +
          '<div class="bs-sonuc-dugmeler"><button type="button" class="bs-yan-dugme" ' +
          'data-bs-komut="menu-don">Menüye Dön</button></div>'
        );
        return;
      }
      kosu.hud.kaplamaGoster(
        '<h3>Savunma Planını Yayınla</h3>' +
        '<p class="bs-kaplama-notu">Planın; harita, tohum ve yerleşim özetinle ' +
        'birlikte diğer oyunculara açılır.</p>' +
        '<input type="text" id="bs-plan-baslik" class="bs-plan-baslik-girdi" ' +
               'maxlength="80" placeholder="Plan başlığı" ' +
               'aria-label="Plan başlığı">' +
        '<div class="bs-sonuc-dugmeler">' +
          '<button type="button" class="bs-yan-dugme bs-yan-dugme-birincil" ' +
                  'data-bs-komut="plan-gonder">Yayınla</button>' +
          '<button type="button" class="bs-yan-dugme" data-bs-komut="menu-don">' +
            'Vazgeç</button></div>'
      );
    },

    planGonder: function(kosu) {
      var haftalikKosu = kosu && (kosu.mod === "haftalik" ||
        (kosu.sim && kosu.sim.durum && kosu.sim.durum.mod === "haftalik"));
      if (haftalikKosu) return;
      var girdiEl = document.getElementById("bs-plan-baslik");
      var baslik = girdiEl ? girdiEl.value : "";
      var yerlesimler = [];
      (kosu.sim.durum.olaylar || []).forEach(function(olay) {
        if (olay.tip === "yerlestir" && yerlesimler.length < 60) {
          yerlesimler.push({ kahraman: olay.k, x: olay.x, y: olay.y,
                             seviye: 1, dalga: Math.max(1, olay.d || 1) });
        } else if (olay.tip === "yukselt") {
          for (var i = yerlesimler.length - 1; i >= 0; i--) {
            if (yerlesimler[i].kahraman === olay.k) {
              yerlesimler[i].seviye = Math.min(3, olay.s || 1);
              break;
            }
          }
        }
      });

      kosu.planYayinBekliyor = true;
      BS.kopru.planYayinla(kosu.kosuId, baslik, {
        sema: BS.SEMA,
        harita: kosu.sim.durum.haritaId,
        zorluk: kosu.sim.durum.zorluk,
        tohum: kosu.sim.durum.tohum,
        baslik: baslik,
        yerlesimler: yerlesimler
      });
      BS.sonuc.goster(kosu, BS.sonuc.sonPaket(kosu));
    }
  };
})();
