// www/js/bilge_savunmasi_sim.js
// Bilge Savunması saf simülasyon çekirdeği. Çizimden tamamen bağımsızdır:
// canvas/DOM erişimi YOKTUR; durum + tick(dt) modeliyle çalışır ve görsel
// katmana fx kuyruğu üzerinden olay bildirir. Simülasyon deterministiktir:
// dalga programları tohumdan üretilir, savaş çözümü rastgelelik içermez.
// Çekirdek onarımı dalga başına +3 ile SINIRLIDIR (sunucu doğrulama
// toleransıyla birebir aynı kural).

(function() {
  "use strict";

  var BS = window.BilgeSavunmasi = window.BilgeSavunmasi || {};

  var ONARIM_DALGA_SINIRI = 3;     // R tarafındaki onarim_toleransi ile aynı
  var OLAY_KAYIT_SINIRI = 240;     // olay özeti üst sınırı (kompakt kalır)
  var CEKIRDEK_KALKAN_SINIRI = 20; // İpek kalkanının üst sınırı

  // ── Yol geometrisi yardımcıları ─────────────────────────────────────────────
  function yolUzunluklari(yol) {
    var parcalar = [];
    var toplam = 0;
    for (var i = 1; i < yol.length; i++) {
      var uz = BS.yardimci.mesafe(yol[i - 1].x, yol[i - 1].y, yol[i].x, yol[i].y);
      parcalar.push(uz);
      toplam += uz;
    }
    return { parcalar: parcalar, toplam: toplam };
  }

  function yolNoktasi(yol, geo, t) {
    var kalan = BS.yardimci.kirp(t, 0, geo.toplam);
    for (var i = 0; i < geo.parcalar.length; i++) {
      if (kalan <= geo.parcalar[i] || i === geo.parcalar.length - 1) {
        var oran = geo.parcalar[i] > 0 ? kalan / geo.parcalar[i] : 0;
        return {
          x: BS.yardimci.dogrusal(yol[i].x, yol[i + 1].x, oran),
          y: BS.yardimci.dogrusal(yol[i].y, yol[i + 1].y, oran)
        };
      }
      kalan -= geo.parcalar[i];
    }
    var son = yol[yol.length - 1];
    return { x: son.x, y: son.y };
  }

  function yolHucreleri(harita) {
    var hucreler = {};
    harita.yollar.forEach(function(yol) {
      for (var i = 1; i < yol.length; i++) {
        var a = yol[i - 1], b = yol[i];
        var adim = Math.max(Math.abs(b.x - a.x), Math.abs(b.y - a.y));
        for (var s = 0; s <= adim; s++) {
          var x = Math.round(BS.yardimci.dogrusal(a.x, b.x, adim ? s / adim : 0));
          var y = Math.round(BS.yardimci.dogrusal(a.y, b.y, adim ? s / adim : 0));
          hucreler[x + "," + y] = true;
        }
      }
    });
    return hucreler;
  }

  // ── Simülasyon fabrikası ────────────────────────────────────────────────────
  BS.sim = {
    olustur: function(secenekler) {
      var harita = BS.haritalar.haritaAl(secenekler.haritaId);
      if (!harita) return null;

      var zorluk = BS.denge.zorluklar[secenekler.zorluk] ||
        BS.denge.zorluklar.normal;
      var degistirici = secenekler.degistirici || null;
      var degistiriciEtki = (degistirici && BS.denge.degistiriciler[degistirici]) || {};

      var baslangicKaynak = BS.denge.ekonomi.baslangicKaynak[harita.id] || 140;
      if (degistiriciEtki.baslangicKaynakCarpani) {
        baslangicKaynak = Math.round(
          baslangicKaynak * degistiriciEtki.baslangicKaynakCarpani
        );
      }

      var hizCarpani = zorluk.hizCarpani * (degistiriciEtki.hizCarpani || 1);

      var durum = {
        haritaId: harita.id,
        harita: harita,
        zorluk: secenekler.zorluk,
        tohum: secenekler.tohum,
        mod: secenekler.mod || "kampanya",
        degistirici: degistirici,
        // Öncü Uzman: koşu başında seçilen lider persona. İlk konuşlandırması
        // ücretsizdir ve yetenek beklemesi %20 kısalır (kimlik doğrulaması
        // kanonik kahraman tablosu üzerinden yapılır).
        oncu: (secenekler.oncu && BS.denge.kahramanlar[secenekler.oncu])
          ? secenekler.oncu : null,

        kaynak: baslangicKaynak,
        cekirdek: harita.tabanCekirdek,
        tabanCekirdek: harita.tabanCekirdek,
        cekirdekKalkani: 0,

        dalgaNo: 0,
        dalgaDurumu: "hazirlik",   // hazirlik | aktif | tamamlandi
        dalgalar: BS.dalga.kosuPlani(harita, secenekler.zorluk,
                                     secenekler.tohum, degistirici),
        bekleyenGirisler: [],
        dalgaZamani: 0,
        dalgaOnarimi: 0,

        dusmanlar: [],
        mermiler: [],
        kahramanlar: {},

        dalgaOzetleri: [],
        guncelDalga: null,
        toplamOlduruldu: 0,
        toplamPuan: 0,

        olaylar: [],
        fxKuyrugu: [],
        sure: 0,
        sonrakiVarlikNo: 1,
        bitti: false,
        zafer: false,

        hizCarpani: hizCarpani,
        kaynakCarpani: zorluk.kaynakCarpani,
        canCarpani: zorluk.canCarpani,
        yolGeo: harita.yollar.map(yolUzunluklari),
        yolHucre: yolHucreleri(harita)
      };

      Object.keys(BS.denge.kahramanlar).forEach(function(id) {
        durum.kahramanlar[id] = {
          id: id, yerlesik: false, x: -1, y: -1, seviye: 0,
          atisSayaci: 0, yetenekKalan: 0, yetenekAktif: 0,
          onarimSayaci: 0, kaynakSayaci: 0, kalkanSayaci: 0
        };
      });

      var sim = { durum: durum };

      // ── Olay kaydı (kompakt; sunucuya özetle gider) ─────────────────────────
      function olayEkle(tip, ek) {
        if (durum.olaylar.length >= OLAY_KAYIT_SINIRI) return;
        var kayit = { t: Math.round(durum.sure * 10) / 10, tip: tip };
        if (ek) Object.keys(ek).forEach(function(k) { kayit[k] = ek[k]; });
        durum.olaylar.push(kayit);
      }

      function fx(tip, ek) {
        var kayit = { tip: tip };
        if (ek) Object.keys(ek).forEach(function(k) { kayit[k] = ek[k]; });
        durum.fxKuyrugu.push(kayit);
      }

      // ── Hücre sorgusu ───────────────────────────────────────────────────────
      sim.hucreDurumu = function(hx, hy) {
        var izgara = BS.haritalar.IZGARA;
        if (hx < 0 || hy < 0 || hx >= izgara.genislik || hy >= izgara.yukseklik) {
          return "disi";
        }
        if (durum.yolHucre[hx + "," + hy]) return "yol";
        if (Math.abs(hx - harita.cekirdek.x) <= 1 &&
            Math.abs(hy - harita.cekirdek.y) <= 1) {
          return "yol";
        }
        var yasak = harita.insaEdilemez.some(function(h) {
          return h.x === hx && h.y === hy;
        });
        if (yasak) return "disi";
        var dolu = Object.keys(durum.kahramanlar).some(function(id) {
          var k = durum.kahramanlar[id];
          return k.yerlesik && k.x === hx && k.y === hy;
        });
        if (!dolu && sim.kuleBul && sim.kuleBul(hx, hy)) dolu = true;
        return dolu ? "dolu" : "insa";
      };

      // ── Kahraman etkin istatistikleri (aura/destek dahil) ───────────────────
      function etkinIstatistik(kahraman) {
        var ist = BS.denge.kahramanIstatistik(kahraman.id, kahraman.seviye);
        if (!ist) return null;

        var emre = durum.kahramanlar.emre;
        if (emre.yerlesik && kahraman.id !== "emre") {
          var emreIst = BS.denge.kahramanIstatistik("emre", emre.seviye);
          var auraYaricap = BS.denge.kahramanlar.emre.aura.yaricap;
          if (BS.yardimci.mesafe(kahraman.x, kahraman.y, emre.x, emre.y) <= auraYaricap) {
            ist.atisAraligi *= emreIst.auraCarpan;
          }
        }
        if (emre.yerlesik && emre.yetenekAktif > 0 && kahraman.id !== "emre") {
          var etkiYaricap = BS.denge.kahramanlar.emre.yetenek.alanYaricapi;
          if (BS.yardimci.mesafe(kahraman.x, kahraman.y, emre.x, emre.y) <= etkiYaricap) {
            ist.atisAraligi *= BS.denge.kahramanlar.emre.yetenek.hizDestekCarpani;
          }
        }

        var ipek = durum.kahramanlar.ipek;
        if (ipek.yerlesik && kahraman.id !== "ipek") {
          var ipekIst = BS.denge.kahramanIstatistik("ipek", ipek.seviye);
          if (BS.yardimci.mesafe(kahraman.x, kahraman.y, ipek.x, ipek.y) <=
              BS.denge.kahramanlar.ipek.destek.yaricap) {
            ist.menzil += ipekIst.menzilBonusu;
          }
        }
        return ist;
      }
      sim.etkinIstatistik = etkinIstatistik;

      // ── Yerleştirme / yükseltme / satış ─────────────────────────────────────
      // Öncü Uzman'ın İLK konuşlandırması ücretsizdir (satıp yeniden
      // yerleştirme normal maliyete döner).
      sim.yerlesimMaliyeti = function(kahramanId) {
        var tanim = BS.denge.kahramanAl(kahramanId);
        if (!tanim) return 0;
        if (durum.oncu === kahramanId && !durum.kahramanlar[kahramanId].oncuKullanildi) {
          return 0;
        }
        return tanim.maliyet;
      };

      sim.yerlestir = function(kahramanId, hx, hy) {
        var kahraman = durum.kahramanlar[kahramanId];
        var tanim = BS.denge.kahramanAl(kahramanId);
        if (!kahraman || !tanim || durum.bitti) return { tamam: false, neden: "gecersiz" };
        if (kahraman.yerlesik) return { tamam: false, neden: "zaten_sahada" };
        if (sim.hucreDurumu(hx, hy) !== "insa") return { tamam: false, neden: "hucre" };
        var maliyet = sim.yerlesimMaliyeti(kahramanId);
        if (durum.kaynak < maliyet) return { tamam: false, neden: "kaynak" };

        durum.kaynak -= maliyet;
        if (durum.oncu === kahramanId) kahraman.oncuKullanildi = true;
        kahraman.yerlesik = true;
        kahraman.x = hx;
        kahraman.y = hy;
        olayEkle("yerlestir", { k: kahramanId, x: hx, y: hy, d: durum.dalgaNo });
        fx("yerlestir", { x: hx, y: hy, kahraman: kahramanId });
        return { tamam: true };
      };

      sim.yukselt = function(kahramanId) {
        var kahraman = durum.kahramanlar[kahramanId];
        var tanim = BS.denge.kahramanAl(kahramanId);
        if (!kahraman || !tanim || !kahraman.yerlesik || durum.bitti) {
          return { tamam: false, neden: "gecersiz" };
        }
        if (kahraman.seviye >= tanim.yukseltmeler.length) {
          return { tamam: false, neden: "azami" };
        }
        var maliyet = tanim.yukseltmeler[kahraman.seviye].maliyet;
        if (durum.kaynak < maliyet) return { tamam: false, neden: "kaynak" };

        durum.kaynak -= maliyet;
        kahraman.seviye += 1;
        olayEkle("yukselt", { k: kahramanId, s: kahraman.seviye, d: durum.dalgaNo });
        fx("yukselt", { x: kahraman.x, y: kahraman.y, kahraman: kahramanId });
        return { tamam: true, seviye: kahraman.seviye };
      };

      sim.sat = function(kahramanId) {
        var kahraman = durum.kahramanlar[kahramanId];
        if (!kahraman || !kahraman.yerlesik || durum.bitti) {
          return { tamam: false, neden: "gecersiz" };
        }
        var iade = Math.round(
          BS.denge.kahramanYatirim(kahramanId, kahraman.seviye) *
          BS.denge.ekonomi.satisIadeOrani
        );
        durum.kaynak += iade;
        fx("sat", { x: kahraman.x, y: kahraman.y, kahraman: kahramanId, iade: iade });
        olayEkle("sat", { k: kahramanId, d: durum.dalgaNo });
        kahraman.yerlesik = false;
        kahraman.x = -1;
        kahraman.y = -1;
        kahraman.seviye = Math.max(0, kahraman.seviye - 1); // satış bedeli: bir kademe
        return { tamam: true, iade: iade };
      };

      // ── Yetenekler ──────────────────────────────────────────────────────────
      function cekirdekOnar(miktar) {
        var izin = Math.max(0, ONARIM_DALGA_SINIRI - durum.dalgaOnarimi);
        var uygulanan = Math.min(miktar, izin,
                                 durum.tabanCekirdek - durum.cekirdek);
        if (uygulanan > 0) {
          durum.cekirdek += uygulanan;
          durum.dalgaOnarimi += uygulanan;
          fx("onarim", { miktar: uygulanan });
        }
        return uygulanan;
      }

      sim.yetenek = function(kahramanId) {
        var kahraman = durum.kahramanlar[kahramanId];
        var tanim = BS.denge.kahramanAl(kahramanId);
        if (!kahraman || !tanim || !kahraman.yerlesik || durum.bitti ||
            kahraman.yetenekKalan > 0) {
          return { tamam: false, neden: "hazir_degil" };
        }

        var yetenek = tanim.yetenek;
        kahraman.yetenekKalan = yetenek.beklemeSuresi *
          (durum.oncu === kahramanId ? 0.8 : 1);
        kahraman.yetenekAktif = yetenek.sure || 0;
        olayEkle("yetenek", { k: kahramanId, d: durum.dalgaNo });
        fx("yetenek", { x: kahraman.x, y: kahraman.y, kahraman: kahramanId,
                        yetenekId: yetenek.id });

        if (yetenek.id === "cozum_dalgasi") {
          durum.dusmanlar.forEach(function(dusman) {
            if (BS.yardimci.mesafe(dusman.x, dusman.y, kahraman.x, kahraman.y) <=
                yetenek.alanYaricapi) {
              hasarVer(dusman, yetenek.alanHasari, "emre", false);
            }
          });
        } else if (yetenek.id === "sinyal_taramasi") {
          cekirdekOnar(yetenek.onarimAni);
        } else if (yetenek.id === "dogrulama_isini") {
          var hedef = null;
          durum.dusmanlar.forEach(function(dusman) {
            if (!hedef || dusman.can > hedef.can) hedef = dusman;
          });
          if (hedef) {
            hedef.isaretKalan = 5;
            var hasar = yetenek.hedefHasari *
              (hedef.patronMu ? yetenek.patronCarpani : 1);
            hasarVer(hedef, hasar, "can", true);
            fx("isin", { x: kahraman.x, y: kahraman.y,
                         hx: hedef.x, hy: hedef.y });
          }
        } else if (yetenek.id === "rehber_halkasi") {
          durum.cekirdekKalkani = Math.min(
            CEKIRDEK_KALKAN_SINIRI, durum.cekirdekKalkani + yetenek.kalkan
          );
          durum.kaynak += yetenek.kaynakAni;
        }
        // rota_projesi etkisi tick içinde alan yavaşlatması olarak uygulanır.
        return { tamam: true };
      };

      // ── Hasar çözümü ────────────────────────────────────────────────────────
      // secenek: isteğe bağlı { zirhDelme } — kule kaynaklı hasar için
      // (kaynakKahraman null iken) zırh delme oranı buradan uygulanır.
      function hasarVer(dusman, hamHasar, kaynakKahraman, dogrulamaMi, secenek) {
        if (dusman.can <= 0) return;

        var ist = null;
        var kahraman = kaynakKahraman ? durum.kahramanlar[kaynakKahraman] : null;
        if (kahraman && kahraman.yerlesik) {
          ist = BS.denge.kahramanIstatistik(kaynakKahraman, kahraman.seviye);
        }

        var hasar = hamHasar;
        if (dusman.isaretKalan > 0) {
          hasar *= (kaynakKahraman === "can" && ist) ? ist.kritCarpan : 1.25;
        }

        var zirh = dusman.zirh;
        if (dogrulamaMi && ist) zirh *= (1 - ist.zirhDelme);
        else if (secenek && secenek.zirhDelme > 0) zirh *= (1 - secenek.zirhDelme);
        hasar = Math.max(1, hasar - zirh);

        if (dusman.kalkan > 0) {
          var kalkanHasari = dogrulamaMi ? hasar * 2 : hasar;
          var emilen = Math.min(dusman.kalkan, kalkanHasari);
          dusman.kalkan -= emilen;
          hasar = Math.max(0, hasar - emilen);
          if (hasar <= 0) return;
        }

        dusman.can -= hasar;
        if (dusman.can <= 0) {
          dusmanOldu(dusman);
        }
      }

      function dusmanOldu(dusman) {
        dusman.olu = true;
        durum.toplamOlduruldu += 1;
        durum.guncelDalga.olduruldu += 1;
        var puan = dusman.tanim.puan;
        var kaynak = Math.round(dusman.tanim.kaynak * durum.kaynakCarpani);
        durum.guncelDalga.puan += puan;
        durum.toplamPuan += puan;
        durum.kaynak += kaynak;
        fx("olum", { x: dusman.x, y: dusman.y, renk: dusman.tanim.renk,
                     patronMu: dusman.patronMu, kaynak: kaynak });

        if (dusman.tanim.ozellik === "bolunen") {
          var cocukId = dusman.patronMu ? "celiski" : "gurultu";
          var adet = dusman.patronMu ? 4 : 2;
          for (var i = 0; i < adet; i++) {
            dusmanDogur(cocukId, dusman.yolIndex, dusman.t - i * 0.3, false);
          }
        }
      }

      function dusmanDogur(tanimId, yolIndex, baslangicT, patronMu) {
        var tanim = BS.denge.dusmanAl(tanimId);
        if (!tanim) return;
        var nokta = yolNoktasi(harita.yollar[yolIndex],
                               durum.yolGeo[yolIndex],
                               Math.max(0, baslangicT));
        durum.dusmanlar.push({
          no: durum.sonrakiVarlikNo++,
          tanimId: tanimId,
          tanim: tanim,
          patronMu: !!patronMu,
          can: Math.round(tanim.can * durum.canCarpani),
          maxCan: Math.round(tanim.can * durum.canCarpani),
          zirh: tanim.zirh,
          yolIndex: yolIndex,
          t: Math.max(0, baslangicT),
          x: nokta.x, y: nokta.y,
          yavasCarpan: 1, yavasKalan: 0,
          isaretKalan: 0,
          gizliSayac: 0, gizliMi: false,
          iyilestirmeSayaci: 0,
          kalkan: tanim.ozellik === "kalkanli" ? Math.round(30 * durum.canCarpani) : 0,
          olu: false
        });
        if (patronMu) {
          fx("patron", { ad: tanim.ad });
        }
      }

      // ── Dalga akışı ─────────────────────────────────────────────────────────
      sim.dalgaBaslat = function(erken) {
        if (durum.bitti || durum.dalgaDurumu === "aktif") return false;
        if (durum.dalgaNo >= harita.dalgaSayisi) return false;

        durum.dalgaNo += 1;
        durum.dalgaDurumu = "aktif";
        durum.dalgaZamani = 0;
        durum.dalgaOnarimi = 0;
        durum.guncelDalga = { dalga: durum.dalgaNo, olduruldu: 0, sizinti: 0, puan: 0 };
        durum.bekleyenGirisler =
          durum.dalgalar[durum.dalgaNo - 1].girisler.slice();
        if (erken) {
          durum.kaynak += BS.denge.ekonomi.erkenBaslatmaBonusu;
        }
        olayEkle("dalga_basladi", { d: durum.dalgaNo });
        fx("dalga_basladi", {
          dalga: durum.dalgaNo,
          patronMu: durum.dalgalar[durum.dalgaNo - 1].patronMu
        });
        return true;
      };

      function dalgaBitti() {
        durum.guncelDalga.cekirdek = durum.cekirdek;
        durum.guncelDalga.kaynak = durum.kaynak;
        durum.dalgaOzetleri.push(durum.guncelDalga);
        durum.kaynak += BS.denge.ekonomi.dalgaTamamlamaBonusu;
        olayEkle("dalga_bitti", { d: durum.dalgaNo, p: durum.guncelDalga.puan });
        fx("dalga_bitti", { dalga: durum.dalgaNo });

        if (durum.dalgaNo >= harita.dalgaSayisi) {
          durum.bitti = true;
          durum.zafer = durum.cekirdek > 0;
          durum.dalgaDurumu = "tamamlandi";
          fx("kosu_bitti", { zafer: durum.zafer });
        } else {
          durum.dalgaDurumu = "hazirlik";
        }
      }

      function yenilgi() {
        durum.guncelDalga.cekirdek = 0;
        durum.guncelDalga.kaynak = durum.kaynak;
        durum.dalgaOzetleri.push(durum.guncelDalga);
        durum.bitti = true;
        durum.zafer = false;
        durum.dalgaDurumu = "tamamlandi";
        fx("kosu_bitti", { zafer: false });
      }

      function sizintiIsle(dusman) {
        dusman.olu = true;
        durum.guncelDalga.sizinti += 1;
        var hasar = dusman.patronMu ? 3 : 1;
        if (durum.cekirdekKalkani > 0) {
          var emilen = Math.min(durum.cekirdekKalkani, hasar);
          durum.cekirdekKalkani -= emilen;
          hasar -= emilen;
        }
        durum.cekirdek = Math.max(0, durum.cekirdek - hasar);
        fx("sizinti", { patronMu: dusman.patronMu });
        if (durum.cekirdek <= 0 && !durum.bitti) {
          yenilgi();
        }
      }

      // ── Ana adım ────────────────────────────────────────────────────────────
      sim.tick = function(dt) {
        if (durum.bitti || dt <= 0) return;
        durum.sure += dt;

        // Bekleme sayaçları her durumda akar (hazırlıkta da).
        Object.keys(durum.kahramanlar).forEach(function(id) {
          var k = durum.kahramanlar[id];
          if (k.yetenekKalan > 0) k.yetenekKalan = Math.max(0, k.yetenekKalan - dt);
          if (k.yetenekAktif > 0) k.yetenekAktif = Math.max(0, k.yetenekAktif - dt);
        });

        // Selin pasif onarımı ve İpek kaynak/kalkan üretimi.
        var selin = durum.kahramanlar.selin;
        if (selin.yerlesik && durum.dalgaDurumu === "aktif") {
          var selinIst = BS.denge.kahramanIstatistik("selin", selin.seviye);
          selin.onarimSayaci += dt;
          if (selin.onarimSayaci >= selinIst.onarimAralik) {
            selin.onarimSayaci = 0;
            cekirdekOnar(selinIst.onarimMiktar);
          }
        }
        var ipek = durum.kahramanlar.ipek;
        if (ipek.yerlesik && durum.dalgaDurumu === "aktif") {
          var ipekIst = BS.denge.kahramanIstatistik("ipek", ipek.seviye);
          ipek.kaynakSayaci += dt;
          if (ipek.kaynakSayaci >= BS.denge.kahramanlar.ipek.destek.kaynakAraligi) {
            ipek.kaynakSayaci = 0;
            durum.kaynak += ipekIst.kaynakMiktari;
            fx("kaynak", { x: ipek.x, y: ipek.y, miktar: ipekIst.kaynakMiktari });
          }
          if (ipekIst.kalkanMiktari > 0) {
            ipek.kalkanSayaci += dt;
            if (ipek.kalkanSayaci >= 12) {
              ipek.kalkanSayaci = 0;
              durum.cekirdekKalkani = Math.min(
                CEKIRDEK_KALKAN_SINIRI,
                durum.cekirdekKalkani + ipekIst.kalkanMiktari
              );
            }
          }
        }

        if (durum.dalgaDurumu !== "aktif") return;
        durum.dalgaZamani += dt;

        // Doğuşlar.
        while (durum.bekleyenGirisler.length > 0 &&
               durum.bekleyenGirisler[0].gecikme <= durum.dalgaZamani) {
          var giris = durum.bekleyenGirisler.shift();
          dusmanDogur(giris.dusmanId, giris.yolIndex, 0, giris.patronMu);
        }

        // Selin 3. kademe / Sinyal Taraması gizli görünürlüğü.
        var gizliGorunur = false;
        if (selin.yerlesik) {
          var selinIst2 = BS.denge.kahramanIstatistik("selin", selin.seviye);
          gizliGorunur = selinIst2.gizliGorur || selin.yetenekAktif > 0;
        }

        // Deniz Rota Projesi alanı.
        var deniz = durum.kahramanlar.deniz;
        var rotaAlani = null;
        if (deniz.yerlesik && deniz.yetenekAktif > 0) {
          rotaAlani = {
            x: deniz.x, y: deniz.y,
            yaricap: BS.denge.kahramanlar.deniz.yetenek.alanYaricapi,
            carpan: BS.denge.kahramanlar.deniz.yetenek.alanYavasCarpan
          };
        }

        // Düşman hareketi ve özellikleri.
        durum.dusmanlar.forEach(function(dusman) {
          if (dusman.olu) return;

          if (dusman.yavasKalan > 0) {
            dusman.yavasKalan -= dt;
            if (dusman.yavasKalan <= 0) dusman.yavasCarpan = 1;
          }
          if (dusman.isaretKalan > 0) dusman.isaretKalan -= dt;

          if (dusman.tanim.ozellik === "gizli") {
            dusman.gizliSayac += dt;
            var dongu = dusman.gizliSayac % 3.5;
            dusman.gizliMi = dongu > 2 && !gizliGorunur;
          }

          if (dusman.tanim.ozellik === "iyilestiren") {
            dusman.iyilestirmeSayaci += dt;
            if (dusman.iyilestirmeSayaci >= 2.5) {
              dusman.iyilestirmeSayaci = 0;
              durum.dusmanlar.forEach(function(komsu) {
                if (komsu !== dusman && !komsu.olu &&
                    BS.yardimci.mesafe(dusman.x, dusman.y, komsu.x, komsu.y) <= 1.8) {
                  komsu.can = Math.min(komsu.maxCan, komsu.can + 4);
                }
              });
              fx("iyilestirme", { x: dusman.x, y: dusman.y });
            }
          }

          var geo = durum.yolGeo[dusman.yolIndex];
          var hiz = dusman.tanim.hiz * durum.hizCarpani * dusman.yavasCarpan;
          if (dusman.tanim.ozellik === "hizlanan") {
            hiz *= 1 + 0.6 * (dusman.t / geo.toplam);
          }
          if (rotaAlani &&
              BS.yardimci.mesafe(dusman.x, dusman.y, rotaAlani.x, rotaAlani.y) <=
              rotaAlani.yaricap) {
            hiz *= rotaAlani.carpan;
          }

          dusman.t += hiz * dt;
          var nokta = yolNoktasi(harita.yollar[dusman.yolIndex], geo, dusman.t);
          dusman.x = nokta.x;
          dusman.y = nokta.y;

          if (dusman.t >= geo.toplam) {
            sizintiIsle(dusman);
          }
        });
        if (durum.bitti) return;

        // Kahraman atışları.
        Object.keys(durum.kahramanlar).forEach(function(id) {
          var kahraman = durum.kahramanlar[id];
          if (!kahraman.yerlesik) return;
          var ist = etkinIstatistik(kahraman);
          kahraman.atisSayaci += dt;
          if (kahraman.atisSayaci < ist.atisAraligi) return;

          var tanim = BS.denge.kahramanAl(id);
          var hedef = null;
          var enIyi = -1;
          durum.dusmanlar.forEach(function(dusman) {
            if (dusman.olu || dusman.gizliMi) return;
            var uzaklik = BS.yardimci.mesafe(kahraman.x, kahraman.y,
                                             dusman.x, dusman.y);
            if (uzaklik > ist.menzil) return;
            var deger = (tanim.oncelik === "guclu") ? dusman.can : dusman.t;
            if (dusman.isaretKalan > 0 && tanim.oncelik === "guclu") {
              deger += 100000; // Can işaretli hedefe kilitlenir
            }
            if (deger > enIyi) { enIyi = deger; hedef = dusman; }
          });
          if (!hedef) return;

          kahraman.atisSayaci = 0;
          durum.mermiler.push({
            x: kahraman.x, y: kahraman.y,
            hedefNo: hedef.no,
            hiz: tanim.mermiHizi,
            hasar: ist.hasar,
            tip: tanim.mermiTipi,
            sahip: id,
            yavasCarpan: id === "deniz" ? ist.yavasCarpan : 0,
            alanYavas: !!ist.alanYavas,
            isaretle: id === "can"
          });
          fx("atis", { x: kahraman.x, y: kahraman.y, kahraman: id });
        });

        // Kule atışları (uzantı katmanı; dalga aktifken çalışır).
        if (sim.kuleTik) sim.kuleTik(dt);

        // Mermiler.
        durum.mermiler = durum.mermiler.filter(function(mermi) {
          var hedef = null;
          for (var i = 0; i < durum.dusmanlar.length; i++) {
            if (durum.dusmanlar[i].no === mermi.hedefNo) {
              hedef = durum.dusmanlar[i];
              break;
            }
          }
          if (!hedef || hedef.olu) return false;

          var uzaklik = BS.yardimci.mesafe(mermi.x, mermi.y, hedef.x, hedef.y);
          var adim = mermi.hiz * dt;
          if (uzaklik <= adim + 0.15) {
            if (mermi.sahipTip === "kule") {
              sim.kuleVurusUygula(mermi, hedef);
              fx("vurus", { x: hedef.x, y: hedef.y, tip: mermi.tip });
              return false;
            }
            if (mermi.isaretle) hedef.isaretKalan = BS.denge.kahramanlar.can.isaret.sure;
            if (mermi.yavasCarpan > 0) {
              hedef.yavasCarpan = Math.min(
                hedef.yavasCarpan === 1 ? mermi.yavasCarpan : hedef.yavasCarpan,
                mermi.yavasCarpan
              );
              hedef.yavasKalan = BS.denge.kahramanlar.deniz.yavaslatma.sure;
              if (mermi.alanYavas) {
                durum.dusmanlar.forEach(function(komsu) {
                  if (!komsu.olu &&
                      BS.yardimci.mesafe(hedef.x, hedef.y, komsu.x, komsu.y) <= 1.2) {
                    komsu.yavasCarpan = Math.min(
                      komsu.yavasCarpan === 1 ? mermi.yavasCarpan : komsu.yavasCarpan,
                      mermi.yavasCarpan
                    );
                    komsu.yavasKalan = BS.denge.kahramanlar.deniz.yavaslatma.sure;
                  }
                });
              }
            }
            hasarVer(hedef, mermi.hasar, mermi.sahip, mermi.sahip === "can");
            fx("vurus", { x: hedef.x, y: hedef.y, tip: mermi.tip });
            return false;
          }
          mermi.x += (hedef.x - mermi.x) / uzaklik * adim;
          mermi.y += (hedef.y - mermi.y) / uzaklik * adim;
          return true;
        });

        // Ölüleri ayıkla ve dalga sonunu kontrol et.
        durum.dusmanlar = durum.dusmanlar.filter(function(d) { return !d.olu; });
        if (durum.bekleyenGirisler.length === 0 && durum.dusmanlar.length === 0) {
          dalgaBitti();
        }
      };

      // ── Kontrol noktası serileştirme ────────────────────────────────────────
      sim.seriDurum = function() {
        return {
          surum: BS.SURUM,
          sema: BS.SEMA,
          dalgaNo: durum.dalgaNo,
          kaynak: Math.round(durum.kaynak),
          cekirdek: durum.cekirdek,
          sure: Math.round(durum.sure),
          kahramanlar: Object.keys(durum.kahramanlar)
            .filter(function(id) { return durum.kahramanlar[id].yerlesik; })
            .map(function(id) {
              var k = durum.kahramanlar[id];
              return { id: id, x: k.x, y: k.y, seviye: k.seviye };
            }),
          dalgaOzetleri: durum.dalgaOzetleri,
          toplamPuan: durum.toplamPuan,
          toplamOlduruldu: durum.toplamOlduruldu,
          kuleler: sim.kuleSeriDurum ? sim.kuleSeriDurum() : []
        };
      };

      sim.seriYukle = function(kayit) {
        if (!kayit || kayit.sema !== BS.SEMA) return false;
        durum.dalgaNo = kayit.dalgaNo || 0;
        durum.kaynak = kayit.kaynak || durum.kaynak;
        durum.cekirdek = BS.yardimci.kirp(
          kayit.cekirdek != null ? kayit.cekirdek : durum.cekirdek,
          0, durum.tabanCekirdek
        );
        durum.sure = kayit.sure || 0;
        durum.dalgaOzetleri = kayit.dalgaOzetleri || [];
        durum.toplamPuan = kayit.toplamPuan || 0;
        durum.toplamOlduruldu = kayit.toplamOlduruldu || 0;
        (kayit.kahramanlar || []).forEach(function(k) {
          var kahraman = durum.kahramanlar[k.id];
          var tanim = BS.denge.kahramanAl(k.id);
          if (kahraman && tanim) {
            kahraman.yerlesik = true;
            kahraman.x = k.x;
            kahraman.y = k.y;
            kahraman.seviye = BS.yardimci.kirp(k.seviye || 0, 0,
                                               tanim.yukseltmeler.length);
          }
        });
        // Eski kontrol noktalarında kuleler alanı olmayabilir (geriye uyum).
        if (sim.kuleSeriYukle) sim.kuleSeriYukle(kayit.kuleler);
        durum.dalgaDurumu = durum.dalgaNo >= harita.dalgaSayisi
          ? "tamamlandi" : "hazirlik";
        olayEkle("devam", { d: durum.dalgaNo });
        return true;
      };

      // ── Sunucu özeti ────────────────────────────────────────────────────────
      sim.ozetPaketi = function() {
        var kullanilan = Object.keys(durum.kahramanlar).filter(function(id) {
          return durum.kahramanlar[id].yerlesik;
        });
        // Olay kaydındaki yerleşmiş ama sonra satılmış kahramanlar da sayılır.
        durum.olaylar.forEach(function(olay) {
          if (olay.tip === "yerlestir" && kullanilan.indexOf(olay.k) < 0) {
            kullanilan.push(olay.k);
          }
        });
        // Kule kullanım özeti: analitik amaçlıdır; sunucu puanlamasına girmez.
        var kule_tipleri = [];
        durum.olaylar.forEach(function(olay) {
          if (olay.tip === "kule" && kule_tipleri.indexOf(olay.t) < 0) {
            kule_tipleri.push(olay.t);
          }
        });
        return {
          sema: BS.SEMA,
          oyun_surumu: BS.SURUM,
          harita: durum.haritaId,
          zorluk: durum.zorluk,
          tohum: durum.tohum,
          mod: durum.mod,
          dalga_ozetleri: durum.dalgaOzetleri,
          son_dalga: durum.dalgaNo,
          son_cekirdek: durum.cekirdek,
          zafer: durum.zafer,
          sure_saniye: Math.round(durum.sure),
          kullanilan_kahramanlar: kullanilan,
          kullanilan_kuleler: kule_tipleri,
          olay_ozeti: durum.olaylar
        };
      };

      // Kule uzantısını bağla (yerleştirme/atış/seri yardımcıları sim'e eklenir).
      if (BS.simKuleler && BS.simKuleler.bagla) {
        BS.simKuleler.bagla(sim, {
          durum: durum, olayEkle: olayEkle, fx: fx, hasarVer: hasarVer
        });
      }

      return sim;
    }
  };
})();
