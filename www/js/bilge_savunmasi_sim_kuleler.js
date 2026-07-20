// www/js/bilge_savunmasi_sim_kuleler.js
// Bilge Savunması kule simülasyon uzantısı: inşa edilebilir kulelerin
// yerleştirme/yükseltme/satış kuralları, hedefleme ve atış üretimi ile alan
// hasarı çözümü. Saf sim katmanıdır: DOM/canvas erişimi ve Math.random
// KULLANMAZ (determinizm sözleşmesi). bilge_savunmasi_sim.js, iç bağlamını
// (durum + hasar/olay yardımcıları) buraya bagla() ile verir; kule verisi
// bilge_savunmasi_denge.js tablosundan okunur.

(function() {
  "use strict";

  var BS = window.BilgeSavunmasi = window.BilgeSavunmasi || {};

  BS.simKuleler = {

    // sim: dış API nesnesi; ic: { durum, olayEkle, fx, hasarVer }
    bagla: function(sim, ic) {
      var durum = ic.durum;
      durum.kuleler = durum.kuleler || [];
      durum.sonrakiKuleNo = durum.sonrakiKuleNo || 1;

      sim.kuleBul = function(hx, hy) {
        for (var i = 0; i < durum.kuleler.length; i++) {
          var kule = durum.kuleler[i];
          if (kule.x === hx && kule.y === hy) return kule;
        }
        return null;
      };

      sim.kuleNoIleBul = function(no) {
        for (var i = 0; i < durum.kuleler.length; i++) {
          if (durum.kuleler[i].no === no) return durum.kuleler[i];
        }
        return null;
      };

      sim.kuleYerlestir = function(tip, hx, hy) {
        var tanim = BS.denge.kuleAl(tip);
        if (!tanim || durum.bitti) return { tamam: false, neden: "gecersiz" };
        if (sim.hucreDurumu(hx, hy) !== "insa") {
          return { tamam: false, neden: "hucre" };
        }
        if (durum.kaynak < tanim.maliyet) {
          return { tamam: false, neden: "kaynak" };
        }

        durum.kaynak -= tanim.maliyet;
        var kule = {
          no: durum.sonrakiKuleNo++,
          tip: tip, x: hx, y: hy,
          seviye: 0, atisSayaci: 0
        };
        durum.kuleler.push(kule);
        ic.olayEkle("kule", { t: tip, x: hx, y: hy, d: durum.dalgaNo });
        ic.fx("yerlestir", { x: hx, y: hy, kule: tip });
        return { tamam: true, kuleNo: kule.no };
      };

      sim.kuleYukselt = function(kuleNo) {
        var kule = sim.kuleNoIleBul(kuleNo);
        var tanim = kule && BS.denge.kuleAl(kule.tip);
        if (!kule || !tanim || durum.bitti) {
          return { tamam: false, neden: "gecersiz" };
        }
        if (kule.seviye >= tanim.yukseltmeler.length) {
          return { tamam: false, neden: "azami" };
        }
        var maliyet = tanim.yukseltmeler[kule.seviye].maliyet;
        if (durum.kaynak < maliyet) return { tamam: false, neden: "kaynak" };

        durum.kaynak -= maliyet;
        kule.seviye += 1;
        ic.olayEkle("kule_yukselt", { n: kule.no, s: kule.seviye, d: durum.dalgaNo });
        ic.fx("yukselt", { x: kule.x, y: kule.y, kule: kule.tip });
        return { tamam: true, seviye: kule.seviye };
      };

      sim.kuleSat = function(kuleNo) {
        var kule = sim.kuleNoIleBul(kuleNo);
        if (!kule || durum.bitti) return { tamam: false, neden: "gecersiz" };
        var iade = Math.round(
          BS.denge.kuleYatirim(kule.tip, kule.seviye) *
          BS.denge.ekonomi.satisIadeOrani
        );
        durum.kaynak += iade;
        ic.fx("sat", { x: kule.x, y: kule.y, kule: kule.tip, iade: iade });
        ic.olayEkle("kule_sat", { n: kule.no, d: durum.dalgaNo });
        durum.kuleler = durum.kuleler.filter(function(k) { return k !== kule; });
        return { tamam: true, iade: iade };
      };

      // Kule atışları: en ilerideki hedefe kilitlenir (klasik kule savunma).
      sim.kuleTik = function(dt) {
        durum.kuleler.forEach(function(kule) {
          var ist = BS.denge.kuleIstatistik(kule.tip, kule.seviye);
          if (!ist) return;
          kule.atisSayaci += dt;
          if (kule.atisSayaci < ist.atisAraligi) return;

          var tanim = BS.denge.kuleAl(kule.tip);
          var hedef = null;
          var enIleri = -1;
          durum.dusmanlar.forEach(function(dusman) {
            if (dusman.olu || dusman.gizliMi) return;
            var uzaklik = BS.yardimci.mesafe(kule.x, kule.y, dusman.x, dusman.y);
            if (uzaklik > ist.menzil) return;
            if (dusman.t > enIleri) { enIleri = dusman.t; hedef = dusman; }
          });
          if (!hedef) return;

          kule.atisSayaci = 0;
          durum.mermiler.push({
            x: kule.x, y: kule.y,
            hedefNo: hedef.no,
            hiz: tanim.mermiHizi,
            hasar: ist.hasar,
            tip: tanim.mermiTipi,
            sahip: null,
            sahipTip: "kule",
            kuleTip: kule.tip,
            alanYaricapi: ist.alanYaricapi || 0,
            zirhDelme: ist.zirhDelme || 0
          });
          ic.fx("atis", { x: kule.x, y: kule.y, kule: kule.tip });
        });
      };

      // Kule mermisi isabeti: alan yarıçapı varsa çevredeki tehditler de
      // hasar alır; zırh delme kule istatistiğinden uygulanır.
      sim.kuleVurusUygula = function(mermi, hedef) {
        var secenek = { zirhDelme: mermi.zirhDelme || 0 };
        if (mermi.alanYaricapi > 0) {
          var hx = hedef.x, hy = hedef.y;
          durum.dusmanlar.forEach(function(dusman) {
            if (dusman.olu) return;
            if (BS.yardimci.mesafe(hx, hy, dusman.x, dusman.y) <=
                mermi.alanYaricapi) {
              ic.hasarVer(dusman, mermi.hasar, null, false, secenek);
            }
          });
          ic.fx("patlama_alani", { x: hx, y: hy, yaricap: mermi.alanYaricapi });
        } else {
          ic.hasarVer(hedef, mermi.hasar, null, false, secenek);
        }
      };

      // Kontrol noktası serileştirme yardımcıları (ek alan; şema geriye uyumlu).
      sim.kuleSeriDurum = function() {
        return durum.kuleler.map(function(kule) {
          return { tip: kule.tip, x: kule.x, y: kule.y, seviye: kule.seviye };
        });
      };

      sim.kuleSeriYukle = function(kayitlar) {
        if (!kayitlar || !kayitlar.length) return;
        kayitlar.forEach(function(kayit) {
          var tanim = BS.denge.kuleAl(kayit.tip);
          if (!tanim) return;
          durum.kuleler.push({
            no: durum.sonrakiKuleNo++,
            tip: kayit.tip,
            x: kayit.x, y: kayit.y,
            seviye: BS.yardimci.kirp(kayit.seviye || 0, 0,
                                     tanim.yukseltmeler.length),
            atisSayaci: 0
          });
        });
      };
    }
  };
})();
