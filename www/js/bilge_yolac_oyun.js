// www/js/bilge_yolac_oyun.js
// Ana oyun mantığı: durum yönetimi, takım koordinasyonu, mermi çarpışmaları, seviye ilerleme, boss savaşı, zafer akışı

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  // ── Dahili durum değişkenleri ────────────────────────────────────────────
  var takimYurumeHizi = 0.5;        // Takımın otomatik yürüme hızı
  var sonYetenekZamani = 0;          // Son bireysel yetenek kullanım zamanı
  var zaferBaslangic = 0;            // Zafer animasyonunun başladığı an
  var bossOlusturuldu = false;       // Boss düşmanı oluşturuldu mu
  var oyunBitisSayaci = 0;           // Oyun sonu gecikmesi

  // Zamanlama sabitleri
  var ZAFER_SURESI = 3000;           // 3 saniye zafer gösterimi
  var BIREYSEL_YETENEK_ARASI = 6000; // 6 saniyede bir rastgele yetenek
  var TAKIM_CARPMA_GENISLIK = 80;    // Takım çarpışma alanı yarı genişliği
  var TAKIM_CARPMA_YUKSEKLIK = 40;   // Takım çarpışma alanı yarı yüksekliği

  // ════════════════════════════════════════════════════════════════════════
  //  TAKIM MERKEZİ HESAPLAMA
  // ════════════════════════════════════════════════════════════════════════

  function takimMerkeziHesapla() {
    var state = BY.state;
    var karakterler = state.karakterler;
    if (karakterler.length === 0) return { x: 0, y: state.zeminY };

    var topX = 0;
    var topY = 0;
    for (var i = 0; i < karakterler.length; i++) {
      topX += karakterler[i].x + karakterler[i].genislik / 2;
      topY += karakterler[i].y + karakterler[i].yukseklik / 2;
    }
    return {
      x: topX / karakterler.length,
      y: topY / karakterler.length
    };
  }

  // ════════════════════════════════════════════════════════════════════════
  //  BEKLEME DURUMU GÜNCELLEMESİ
  // ════════════════════════════════════════════════════════════════════════

  function beklemeGuncelle(zaman) {
    var state = BY.state;
    var karakterler = state.karakterler;

    // Karakterler bekleme formasyonunda idle animasyonu
    for (var i = 0; i < karakterler.length; i++) {
      var k = karakterler[i];
      if (k.animasyonDurumu !== "hover") {
        k.animasyonDurumu = "idle";
      }

      // Hafif sallantı animasyonu
      var sallanma = Math.sin(zaman * 0.001 + i * 0.7) * 0.3;
      k.hizX += sallanma * 0.02;
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  OYNUYOR DURUMU GÜNCELLEMESİ
  // ════════════════════════════════════════════════════════════════════════

  function oynuyorGuncelle(zaman) {
    var state = BY.state;
    var karakterler = state.karakterler;

    // Takımı sağa doğru otomatik yürüt
    for (var i = 0; i < karakterler.length; i++) {
      var k = karakterler[i];
      // Formasyon pozisyonunu hesapla
      var formasyonX = takimMerkeziHesapla().x - (karakterler.length - 1) * 20 + i * 40;

      // Hedefe doğru yumuşak hareket
      k.hedefX = formasyonX + takimYurumeHizi * 50;
      k.animasyonDurumu = "walk";
      k.yon = 1; // Sağa bak

      // Otomatik ilerleme kuvveti
      k.hizX += takimYurumeHizi * 0.05;
    }

    // Çıkış noktasını kontrol et (seviye sonu)
    var cikisX = state.dunyaGenislik * 0.85;
    if (BY.seviye && typeof BY.seviye.cikisNoktasiAl === "function") {
      var cikis = BY.seviye.cikisNoktasiAl();
      if (cikis && cikis.x) cikisX = cikis.x;
    }

    var takimMerkez = takimMerkeziHesapla();

    // Boss alanına ulaştı mı kontrol et (çıkış noktasının %70'i)
    var bossBaslangicX = cikisX * 0.7;
    if (takimMerkez.x > bossBaslangicX) {
      state.oyunDurumu = "boss";
      bossOlusturuldu = false;
      return;
    }

    // Mermi çarpışmalarını kontrol et
    mermiCarpismalariKontrol();

    // Periyodik bireysel yetenek kullanımı
    bireyselYetenekKontrol(zaman);
  }

  // ════════════════════════════════════════════════════════════════════════
  //  BOSS DURUMU GÜNCELLEMESİ
  // ════════════════════════════════════════════════════════════════════════

  function bossGuncelle(zaman) {
    var state = BY.state;
    var karakterler = state.karakterler;

    // Takımı durdur (boss savaşında yerinde kal)
    for (var i = 0; i < karakterler.length; i++) {
      var k = karakterler[i];
      k.animasyonDurumu = "idle";
      // Formasyonu koru ama ilerleme
      k.hizX *= 0.9;
    }

    // Boss henüz oluşturulmadıysa oluştur
    if (!bossOlusturuldu) {
      bossOlustur();
      bossOlusturuldu = true;
    }

    // Boss'un ölüp ölmediğini kontrol et
    var bossHayatta = false;
    var dusmanlar = state.dusmanlar;
    for (var j = 0; j < dusmanlar.length; j++) {
      if (dusmanlar[j].tur === "boss" && dusmanlar[j].can > 0) {
        bossHayatta = true;
        break;
      }
    }

    if (!bossHayatta && bossOlusturuldu) {
      // Boss yenildi - zafer durumuna geç
      seviyeTamamla();
      return;
    }

    // Mermi çarpışmalarını kontrol et
    mermiCarpismalariKontrol();

    // Periyodik bireysel yetenek kullanımı (boss savaşında daha sık)
    bireyselYetenekKontrol(zaman, 3000);
  }

  // Boss düşmanı oluştur
  function bossOlustur() {
    var state = BY.state;
    var takimMerkez = takimMerkeziHesapla();

    // Boss'u takımın sağında oluştur
    var bossX = takimMerkez.x + 200;
    var bossY = state.zeminY - 48; // Boss biraz daha büyük

    var bossRenkler = BY.config.DUSMAN_RENKLERI.boss;

    var boss = {
      tur: "boss",
      isim: "MUHAFIZ",
      x: bossX,
      y: bossY,
      genislik: 48,
      yukseklik: 48,
      hizX: 0,
      hizY: 0,
      can: 200,
      maxCan: 200,
      hasar: 8,
      renkler: bossRenkler,
      animasyonDurumu: "idle",
      sonSaldiriZamani: 0,
      saldiriAraligi: 2000 // 2 saniyede bir saldırı
    };

    state.dusmanlar.push(boss);

    // Boss ortaya çıkış efekti
    if (BY.efektler) {
      BY.efektler.patlamaEfektiOlustur(bossX + 24, bossY + 24);
      BY.efektler.radarDarbesiEkle(bossX + 24, bossY + 24, "#FFD700");
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  ZAFER DURUMU GÜNCELLEMESİ
  // ════════════════════════════════════════════════════════════════════════

  function zaferGuncelle(zaman) {
    var state = BY.state;
    var karakterler = state.karakterler;

    // Zafer zamanını kaydet
    if (zaferBaslangic === 0) {
      zaferBaslangic = zaman;

      // Zafer efekti
      if (BY.efektler && BY.efektler.zaferEfektiOlustur) {
        BY.efektler.zaferEfektiOlustur();
      }
    }

    // Karakterleri zafer animasyonuna al
    for (var i = 0; i < karakterler.length; i++) {
      var k = karakterler[i];
      k.animasyonDurumu = "victory";
      k.zaferAktif = true;

      // Rastgele zafer zıplaması
      if (Math.random() > 0.96 && k.hizY === 0) {
        k.hizY = -4 - Math.random() * 2;
      }
    }

    // Zafer süresi doldu mu
    var gecenSure = zaman - zaferBaslangic;
    if (gecenSure > ZAFER_SURESI) {
      // Karakterleri normale döndür
      for (var j = 0; j < karakterler.length; j++) {
        karakterler[j].animasyonDurumu = "idle";
        karakterler[j].zaferAktif = false;
      }

      // Seviye geçişini başlat
      zaferBaslangic = 0;
      seviyeIlerlet();
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  MERMİ ÇARPIŞMA KONTROLÜ
  // ════════════════════════════════════════════════════════════════════════

  function mermiCarpismalariKontrol() {
    var state = BY.state;
    var mermiler = state.mermiler;
    var dusmanlar = state.dusmanlar;
    var takimMerkez = takimMerkeziHesapla();

    for (var i = mermiler.length - 1; i >= 0; i--) {
      var m = mermiler[i];

      if (m.sahip === "takim") {
        // Takım mermisi → düşmanlara çarpma kontrolü
        for (var j = 0; j < dusmanlar.length; j++) {
          var d = dusmanlar[j];
          if (d.can <= 0) continue;

          // Basit kutucuk çarpışma
          var carpisti = kutuCarpismasi(
            m.x, m.y, m.genislik || 4, m.yukseklik || 4,
            d.x, d.y, d.genislik, d.yukseklik
          );

          if (carpisti) {
            // Düşmana hasar ver
            var hasar = m.hasar || 10;
            d.can -= hasar;

            // Hasar efekti
            if (BY.efektler) {
              BY.efektler.hasarEfektiOlustur(
                d.x + d.genislik / 2,
                d.y + d.yukseklik / 2,
                "#FF4444"
              );
            }

            // Düşman öldü mü
            if (d.can <= 0) {
              // Patlama efekti
              if (BY.efektler) {
                BY.efektler.patlamaEfektiOlustur(
                  d.x + d.genislik / 2,
                  d.y + d.yukseklik / 2
                );
              }

              // Skor ekle
              var skorBonus = d.tur === "boss" ? 500 : 100;
              skoreEkle(skorBonus);
            }

            // Mermiyi kaldır
            mermiler.splice(i, 1);
            break;
          }
        }
      } else if (m.sahip === "dusman") {
        // Düşman mermisi → takım alanına çarpma kontrolü
        var takimCarpisti = kutuCarpismasi(
          m.x, m.y, m.genislik || 4, m.yukseklik || 4,
          takimMerkez.x - TAKIM_CARPMA_GENISLIK,
          takimMerkez.y - TAKIM_CARPMA_YUKSEKLIK,
          TAKIM_CARPMA_GENISLIK * 2,
          TAKIM_CARPMA_YUKSEKLIK * 2
        );

        if (takimCarpisti) {
          // Takıma hasar ver
          var takimHasari = m.hasar || 5;
          state.takimCan = Math.max(0, state.takimCan - takimHasari);

          // Hasar efekti
          if (BY.efektler) {
            BY.efektler.hasarEfektiOlustur(
              takimMerkez.x,
              takimMerkez.y,
              "#FF8800"
            );
          }

          // Mermiyi kaldır
          mermiler.splice(i, 1);

          // Oyun bitti mi kontrol
          if (state.takimCan <= 0) {
            oyunuSifirla();
            return;
          }
        }
      }
    }
  }

  // Basit kutucuk çarpışma kontrolü
  function kutuCarpismasi(ax, ay, ag, ayu, bx, by, bg, byu) {
    return ax < bx + bg &&
           ax + ag > bx &&
           ay < by + byu &&
           ay + ayu > by;
  }

  // ════════════════════════════════════════════════════════════════════════
  //  PERİYODİK BİREYSEL YETENEK KULLANIMI
  // ════════════════════════════════════════════════════════════════════════

  function bireyselYetenekKontrol(zaman, aralik) {
    aralik = aralik || BIREYSEL_YETENEK_ARASI;
    if (zaman - sonYetenekZamani < aralik) return;
    sonYetenekZamani = zaman;

    var state = BY.state;
    var karakterler = state.karakterler;
    if (karakterler.length === 0) return;

    // Rastgele bir karakter seç ve yetenek kullandır
    var rastgeleIndex = Math.floor(Math.random() * karakterler.length);
    var karakter = karakterler[rastgeleIndex];

    if (!karakter.yetenekAktif && BY.karakterler && BY.karakterler.yetenekCalistir) {
      BY.karakterler.yetenekCalistir(karakter);
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  SEVİYE TAMAMLAMA VE İLERLEME
  // ════════════════════════════════════════════════════════════════════════

  // Seviyeyi tamamla: yıldız derecesi hesapla, bonus skor ekle
  function seviyeTamamla() {
    var state = BY.state;

    // Yıldız derecelendirmesi (kalan sağlığa göre)
    var saglikOrani = state.takimCan / state.takimMaxCan;
    var yildizSayisi;
    if (saglikOrani > 0.8) {
      yildizSayisi = 3;
    } else if (saglikOrani > 0.5) {
      yildizSayisi = 2;
    } else {
      yildizSayisi = 1;
    }

    // Bonus skor: yıldız başına 200 puan
    skoreEkle(yildizSayisi * 200);

    // Zafer durumuna geç
    state.oyunDurumu = "zafer";
    zaferBaslangic = 0;
  }

  // Sonraki seviyeye ilerle
  function seviyeIlerlet() {
    var state = BY.state;

    // Sonraki seviye numarası
    var sonrakiSeviye = (state.mevcutSeviye + 1) % 5;

    // Seviye geçişini motor üzerinden başlat
    if (BY.motor && typeof BY.motor.gecisBaslat === "function") {
      BY.motor.gecisBaslat();
    } else {
      // Motor geçişi yoksa doğrudan yükle
      state.mevcutSeviye = sonrakiSeviye;
      state.oyunDurumu = "oynuyor";
      seviyeSifirla();
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  SKOR YÖNETİMİ
  // ════════════════════════════════════════════════════════════════════════

  function skoreEkle(miktar) {
    var state = BY.state;
    state.skor += miktar;

    // Yüzen skor metni efekti (opsiyonel)
    if (BY.efektler && BY.efektler.parcacikOlustur) {
      var takimMerkez = takimMerkeziHesapla();
      BY.efektler.parcacikOlustur(
        takimMerkez.x,
        takimMerkez.y - 30,
        "#FFD700",
        "yukari",
        3
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  OYUN SIFIRLAMA
  // ════════════════════════════════════════════════════════════════════════

  // Takım canı bittiğinde aynı seviyeyi yeniden yükle
  function oyunuSifirla() {
    var state = BY.state;

    // Sağlığı sıfırla
    state.takimCan = state.takimMaxCan;

    // Mermileri ve düşmanları temizle
    state.mermiler = [];
    state.dusmanlar = [];

    // Kamerayı sıfırla
    state.kameraX = 0;

    // Karakterleri başlangıç pozisyonuna al
    var karakterler = state.karakterler;
    for (var i = 0; i < karakterler.length; i++) {
      karakterler[i].x = 60 + i * 40;
      karakterler[i].hizX = 0;
      karakterler[i].hizY = 0;
      karakterler[i].animasyonDurumu = "idle";
    }

    // Seviyeyi yeniden yükle
    if (BY.seviye && typeof BY.seviye.yukle === "function") {
      BY.seviye.yukle(state.mevcutSeviye);
    }

    // Oyun durumunu oynuyor'a geri al
    state.oyunDurumu = "oynuyor";
    bossOlusturuldu = false;
  }

  // Seviye verilerini sıfırla (yeni seviyeye geçerken)
  function seviyeSifirla() {
    var state = BY.state;

    state.mermiler = [];
    state.dusmanlar = [];
    state.kameraX = 0;
    bossOlusturuldu = false;

    // Karakterleri başlangıç noktasına al
    var karakterler = state.karakterler;
    for (var i = 0; i < karakterler.length; i++) {
      karakterler[i].x = 60 + i * 40;
      karakterler[i].hizX = 0;
      karakterler[i].hizY = 0;
    }

    // Seviye verilerini yükle
    if (BY.seviye && typeof BY.seviye.yukle === "function") {
      BY.seviye.yukle(state.mevcutSeviye);
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  DIŞ ARAYÜZ
  // ════════════════════════════════════════════════════════════════════════

  BY.oyun = {
    baslat: function() {
      var state = BY.state;

      // Başlangıç değerlerini ayarla
      state.skor = 0;
      state.takimCan = state.takimMaxCan;
      state.mermiler = [];
      state.dusmanlar = [];
      state.kameraX = 0;
      state.oyunDurumu = "oynuyor";

      sonYetenekZamani = performance.now();
      zaferBaslangic = 0;
      bossOlusturuldu = false;
      oyunBitisSayaci = 0;

      // İlk seviyeyi yükle
      if (BY.seviye && typeof BY.seviye.yukle === "function") {
        BY.seviye.yukle(state.mevcutSeviye);
      }

      // Karakterleri başlangıç pozisyonuna yerleştir
      var karakterler = state.karakterler;
      for (var i = 0; i < karakterler.length; i++) {
        karakterler[i].x = 60 + i * 40;
        karakterler[i].hizX = 0;
        karakterler[i].hizY = 0;
        karakterler[i].animasyonDurumu = "idle";
        karakterler[i].yon = 1;
      }
    },

    guncelle: function(zaman) {
      var state = BY.state;

      switch (state.oyunDurumu) {
        case "bekleme":
          beklemeGuncelle(zaman);
          break;

        case "oynuyor":
          oynuyorGuncelle(zaman);
          break;

        case "boss":
          bossGuncelle(zaman);
          break;

        case "zafer":
          zaferGuncelle(zaman);
          break;

        case "gecis":
          // Geçiş motor.js tarafından yönetilir, burada bekliyoruz
          break;
      }
    },

    skoreEkle: skoreEkle,

    seviyeTamamla: seviyeTamamla,

    getTakimDurumu: function() {
      return BY.state.oyunDurumu;
    }
  };

})();