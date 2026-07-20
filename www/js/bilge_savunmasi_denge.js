// www/js/bilge_savunmasi_denge.js
// Bilge Savunması merkezi denge yapılandırması: kahraman (persona) oyun
// istatistikleri, kule tanımları, tehdit (düşman) tanımları, patronlar,
// ekonomi, zorluk çarpanları ve haftalık değiştirici etkileri. TÜM sayısal
// denge buradadır; simülasyon ve HUD bu tablodan okur. Kimlik alanları
// (ad, renk, portre) sunucudan gelen persona manifesti ile birleştirilir —
// burada yeniden TANIMLANMAZ.

(function() {
  "use strict";

  var BS = window.BilgeSavunmasi = window.BilgeSavunmasi || {};

  BS.denge = {
    DENGE_SURUMU: "2026.07.2",

    ekonomi: {
      satisIadeOrani: 0.7,        // satışta geri dönen kaynak oranı
      dalgaTamamlamaBonusu: 18,   // her dalga sonunda verilen kaynak
      erkenBaslatmaBonusu: 8,     // geri sayımı atlayana ek kaynak
      baslangicKaynak: {
        baglam_kapisi: 160,
        celiski_kavsagi: 180,
        bilgi_cekirdegi: 200,
        veri_labirenti: 210,
        sinyal_vadisi: 220,
        karar_zirvesi: 240
      }
    },

    // Kule eklenmesiyle savunma gücü arttığı için tehdit dayanıklılığı
    // yükseltildi (Kingdom Rush tarzı baskı eğrisi).
    zorluklar: {
      normal:   { canCarpani: 1.18, hizCarpani: 1.0,  kaynakCarpani: 1.0 },
      gelismis: { canCarpani: 1.7,  hizCarpani: 1.14, kaynakCarpani: 0.9 }
    },

    // Haftalık meydan okuma değiştiricileri (R .bs_haftalik_degistiriciler
    // kimlikleriyle aynı).
    degistiriciler: {
      hizli_tehditler: { hizCarpani: 1.15 },
      kisitli_kaynak:  { baslangicKaynakCarpani: 0.8 },
      dirya_dalgalar:  { sayiCarpani: 1.2 }
    },

    // ════════════════════════════════════════════════════════════════════════
    //  KAHRAMANLAR — her persona benzersizdir ve haritada tek örneği bulunur.
    //  Rol ayrımı: komuta / onarım / kontrol / doğrulama / destek.
    // ════════════════════════════════════════════════════════════════════════
    kahramanlar: {
      emre: {
        maliyet: 60,
        menzil: 3.1,
        hasar: 16,
        atisAraligi: 0.75,        // saniye / atış
        mermiHizi: 9,
        mermiTipi: "cozum",
        aura: { yaricap: 2.4, atisHiziCarpani: 0.88 },  // yakınlara %12 hız
        yukseltmeler: [
          { maliyet: 55,  hasar: 24, menzil: 3.3, aciklama: "Komuta protokolü güçlenir" },
          { maliyet: 90,  hasar: 34, menzil: 3.5, auraCarpan: 0.82,
            aciklama: "Aura yakın savunucuları daha da hızlandırır" },
          { maliyet: 140, hasar: 50, menzil: 3.8, auraCarpan: 0.76,
            aciklama: "Tam koordinasyon: yüksek hasar ve geniş komuta" }
        ],
        yetenek: {
          id: "cozum_dalgasi", beklemeSuresi: 26, sure: 3.2,
          alanYaricapi: 3.4, alanHasari: 46, hizDestekCarpani: 0.6,
          aciklama: "Alan hasarı verir; kısa süre yakın savunucuları hızlandırır"
        }
      },

      selin: {
        maliyet: 55,
        menzil: 2.6,
        hasar: 9,
        atisAraligi: 0.9,
        mermiHizi: 8,
        mermiTipi: "sinyal",
        onarim: { aralik: 6, miktar: 1 },   // çekirdeğe periyodik onarım
        yukseltmeler: [
          { maliyet: 50,  hasar: 13, onarimMiktar: 1, onarimAralik: 5,
            aciklama: "Onarım protokolü hızlanır" },
          { maliyet: 85,  hasar: 18, onarimMiktar: 2, onarimAralik: 5,
            aciklama: "Çekirdek onarımı güçlenir" },
          { maliyet: 130, hasar: 26, onarimMiktar: 2, onarimAralik: 4,
            gizliGorur: true,
            aciklama: "Sinyal ağı gizli tehditleri de açığa çıkarır" }
        ],
        yetenek: {
          id: "sinyal_taramasi", beklemeSuresi: 30, sure: 6,
          onarimAni: 3, gizliAcigaCikar: true,
          aciklama: "Çekirdeğe anında onarım; gizli tehditleri görünür kılar"
        }
      },

      deniz: {
        maliyet: 65,
        menzil: 2.9,
        hasar: 7,
        atisAraligi: 1.0,
        mermiHizi: 7,
        mermiTipi: "rota",
        yavaslatma: { carpan: 0.62, sure: 1.8 },
        yukseltmeler: [
          { maliyet: 55,  hasar: 10, yavasCarpan: 0.55,
            aciklama: "Yavaşlatma etkisi derinleşir" },
          { maliyet: 95,  hasar: 14, yavasCarpan: 0.5, menzil: 3.2,
            aciklama: "Kontrol alanı genişler" },
          { maliyet: 145, hasar: 20, yavasCarpan: 0.44, alanYavas: true,
            aciklama: "Mermiler küçük alan yavaşlatması uygular" }
        ],
        yetenek: {
          id: "rota_projesi", beklemeSuresi: 32, sure: 5,
          alanYaricapi: 3.8, alanYavasCarpan: 0.4,
          aciklama: "Geniş bölgedeki tüm tehditleri belirgin yavaşlatır"
        }
      },

      can: {
        maliyet: 70,
        menzil: 3.6,
        hasar: 22,
        atisAraligi: 1.25,
        mermiHizi: 12,
        mermiTipi: "dogrulama",
        isaret: { sure: 4, kritCarpani: 1.6 },   // işaretliye kritik hasar
        zirhDelme: 0.5,                          // zırhın yarısını yok sayar
        oncelik: "guclu",                        // en yüksek canlıyı hedefler
        yukseltmeler: [
          { maliyet: 60,  hasar: 32, kritCarpan: 1.8,
            aciklama: "Doğrulama kritiği güçlenir" },
          { maliyet: 100, hasar: 44, zirhDelme: 0.75,
            aciklama: "Zırh ve sahte sinyaller daha da etkisizleşir" },
          { maliyet: 155, hasar: 62, kritCarpan: 2.1, menzil: 4.0,
            aciklama: "Uzun menzilli kesin tespit" }
        ],
        yetenek: {
          id: "dogrulama_isini", beklemeSuresi: 28, sure: 0,
          hedefHasari: 190, patronCarpani: 1.35,
          aciklama: "En güçlü tehdide yüksek hasarlı doğrulama ışını gönderir"
        }
      },

      ipek: {
        maliyet: 50,
        menzil: 2.4,
        hasar: 6,
        atisAraligi: 1.1,
        mermiHizi: 7,
        mermiTipi: "rehber",
        destek: {
          yaricap: 2.6,
          menzilBonusu: 0.35,       // yakın savunuculara menzil katkısı
          kaynakAraligi: 9,         // periyodik küçük kaynak üretimi
          kaynakMiktari: 6
        },
        yukseltmeler: [
          { maliyet: 45,  hasar: 8,  kaynakMiktari: 8,
            aciklama: "Kaynak desteği artar" },
          { maliyet: 80,  hasar: 11, menzilBonusu: 0.5,
            aciklama: "Rehberlik alanı güçlenir" },
          { maliyet: 120, hasar: 15, kalkanMiktari: 14,
            aciklama: "Rehber Halkası savunuculara kalkan yeniler" }
        ],
        yetenek: {
          id: "rehber_halkasi", beklemeSuresi: 30, sure: 6,
          kalkan: 20, kaynakAni: 18,
          aciklama: "Yakın savunuculara kalkan verir; küçük kaynak desteği sağlar"
        }
      }
    },

    // ════════════════════════════════════════════════════════════════════════
    //  KULELER — inşa edilebilir savunma yapıları (Kingdom Rush esinli).
    //  Kahramanların aksine aynı kuleden birden çok inşa edilebilir; üç
    //  kademelidir (taban + iki yükseltme) ve satılabilir.
    // ════════════════════════════════════════════════════════════════════════
    kuleler: {
      gozetleme: {
        ad: "Gözcü Kulesi",
        aciklama: "Hızlı tekil atış; kalabalık zayıf tehditlere karşı ideal",
        maliyet: 45,
        menzil: 2.6,
        hasar: 7,
        atisAraligi: 0.5,
        mermiHizi: 10,
        mermiTipi: "gozcu",
        yukseltmeler: [
          { maliyet: 40, hasar: 11, menzil: 2.8,
            aciklama: "Gözetleme optiği güçlenir" },
          { maliyet: 70, hasar: 16, menzil: 3.0, atisAraligi: 0.4,
            aciklama: "Çift namlu: atış temposu artar" }
        ]
      },
      veri_topu: {
        ad: "Veri Topçusu",
        aciklama: "Yavaş ama alan hasarlı gülle; sürülere karşı etkili",
        maliyet: 80,
        menzil: 3.2,
        hasar: 24,
        atisAraligi: 2.3,
        mermiHizi: 6,
        mermiTipi: "topcu",
        alanYaricapi: 1.1,
        yukseltmeler: [
          { maliyet: 65, hasar: 36, alanYaricapi: 1.25,
            aciklama: "Patlama alanı genişler" },
          { maliyet: 110, hasar: 52, alanYaricapi: 1.45, menzil: 3.5,
            aciklama: "Ağır veri güllesi: yüksek alan hasarı" }
        ]
      },
      kripto_isik: {
        ad: "Kripto Işını",
        aciklama: "Zırh delici enerji ışını; zırhlı ve kalkanlı tehditleri eritir",
        maliyet: 65,
        menzil: 3.0,
        hasar: 13,
        atisAraligi: 0.95,
        mermiHizi: 12,
        mermiTipi: "kripto",
        zirhDelme: 0.6,
        yukseltmeler: [
          { maliyet: 55, hasar: 19, zirhDelme: 0.75,
            aciklama: "Işın odaklaması zırhı daha derin deler" },
          { maliyet: 95, hasar: 27, zirhDelme: 0.9, menzil: 3.4,
            aciklama: "Tam çözünürlük: neredeyse tüm zırhı yok sayar" }
        ]
      }
    },

    kuleAl: function(id) {
      return BS.denge.kuleler[id] || null;
    },

    // Kule yükseltme sonrası etkin istatistikler (seviye: 0..2; 0 = taban).
    kuleIstatistik: function(id, seviye) {
      var taban = BS.denge.kuleAl(id);
      if (!taban) return null;
      var sonuc = {
        hasar: taban.hasar,
        menzil: taban.menzil,
        atisAraligi: taban.atisAraligi,
        alanYaricapi: taban.alanYaricapi || 0,
        zirhDelme: taban.zirhDelme || 0
      };
      for (var i = 0; i < seviye && i < taban.yukseltmeler.length; i++) {
        var yuk = taban.yukseltmeler[i];
        if (yuk.hasar != null) sonuc.hasar = yuk.hasar;
        if (yuk.menzil != null) sonuc.menzil = yuk.menzil;
        if (yuk.atisAraligi != null) sonuc.atisAraligi = yuk.atisAraligi;
        if (yuk.alanYaricapi != null) sonuc.alanYaricapi = yuk.alanYaricapi;
        if (yuk.zirhDelme != null) sonuc.zirhDelme = yuk.zirhDelme;
      }
      return sonuc;
    },

    // Bir kulenin o ana kadarki toplam yatırımı (satış iadesi hesabı).
    kuleYatirim: function(id, seviye) {
      var taban = BS.denge.kuleAl(id);
      if (!taban) return 0;
      var toplam = taban.maliyet;
      for (var i = 0; i < seviye && i < taban.yukseltmeler.length; i++) {
        toplam += taban.yukseltmeler[i].maliyet;
      }
      return toplam;
    },

    // ════════════════════════════════════════════════════════════════════════
    //  TEHDİTLER — bilgi/karar dünyasından modern kavramlar. "puan" değerleri
    //  sunucu tarafı dalga puan sınırıyla uyumludur (tekil tehdit <= 18).
    // ════════════════════════════════════════════════════════════════════════
    dusmanlar: {
      gurultu: {
        ad: "Gürültü", can: 26, hiz: 1.35, zirh: 0, puan: 4, kaynak: 5,
        renk: "#8d99ae", sekil: "ucgen",
        aciklama: "Zayıf ama kalabalık ilerleyen sinyal kirliliği"
      },
      yanlis_baglam: {
        ad: "Yanlış Bağlam", can: 44, hiz: 1.1, zirh: 1, puan: 6, kaynak: 7,
        renk: "#c77dff", sekil: "kare",
        aciklama: "Yanıltıcı çerçeve; orta dayanıklılıkta"
      },
      celiski: {
        ad: "Çelişki", can: 70, hiz: 0.95, zirh: 2, puan: 8, kaynak: 9,
        renk: "#f4845f", sekil: "altigen", ozellik: "bolunen",
        aciklama: "Yok edilince iki küçük Gürültü'ye bölünür"
      },
      belirsizlik: {
        ad: "Belirsizlik", can: 38, hiz: 1.2, zirh: 0, puan: 7, kaynak: 8,
        renk: "#90e0ef", sekil: "damla", ozellik: "gizli",
        aciklama: "Kısa aralıklarla görünmezleşir; Sinyal Taraması açığa çıkarır"
      },
      varsayim: {
        ad: "Doğrulanmamış Varsayım", can: 95, hiz: 0.8, zirh: 3,
        puan: 10, kaynak: 11, renk: "#e5989b", sekil: "kalkan",
        ozellik: "kalkanli",
        aciklama: "Ön kalkanı vardır; Doğrulama hasarı kalkanı hızla eritir"
      },
      bilgi_yuku: {
        ad: "Bilgi Aşırı Yükü", can: 160, hiz: 0.6, zirh: 2,
        puan: 13, kaynak: 14, renk: "#bc6c25", sekil: "yigin",
        aciklama: "Yavaş ama çok dayanıklı veri yığını"
      },
      bozuk_veri: {
        ad: "Bozuk Veri", can: 30, hiz: 1.6, zirh: 0, puan: 6, kaynak: 6,
        renk: "#6a994e", sekil: "kirik",
        aciklama: "Hızlı ve düzensiz ilerler"
      },
      yonlendirme: {
        ad: "Yönlendirme Saldırısı", can: 58, hiz: 1.15, zirh: 1,
        puan: 9, kaynak: 10, renk: "#e63946", sekil: "ok",
        ozellik: "hizlanan",
        aciklama: "Çekirdeğe yaklaştıkça hızlanır"
      },
      sahte_kesinlik: {
        ad: "Sahte Kesinlik", can: 120, hiz: 0.75, zirh: 4,
        puan: 12, kaynak: 13, renk: "#ffd166", sekil: "elmas",
        ozellik: "iyilestiren",
        aciklama: "Yakınındaki tehditleri yavaşça iyileştirir"
      },
      daginik_istek: {
        ad: "Dağınık İstek", can: 22, hiz: 1.45, zirh: 0, puan: 4, kaynak: 4,
        renk: "#a2d2ff", sekil: "nokta", ozellik: "surulu",
        aciklama: "Küçük gruplar hâlinde art arda gelir"
      },
      veri_solucani: {
        ad: "Veri Solucanı", can: 210, hiz: 0.7, zirh: 4,
        puan: 15, kaynak: 16, renk: "#9d4edd", sekil: "yigin",
        aciklama: "Ağır zırhlı, yavaş ilerleyen bozuk veri kümesi"
      },
      golge_istek: {
        ad: "Gölge İstek", can: 62, hiz: 1.5, zirh: 1,
        puan: 9, kaynak: 10, renk: "#577590", sekil: "damla", ozellik: "gizli",
        aciklama: "Hızlı ve aralıklı görünmez; Sinyal Taraması açığa çıkarır"
      }
    },

    patronlar: {
      bilgi_firtinasi: {
        ad: "Bilgi Fırtınası", can: 900, hiz: 0.5, zirh: 4, puan: 60,
        kaynak: 60, renk: "#4cc9f0", sekil: "firtina",
        aciklama: "Bağlam Kapısı'nı zorlayan yoğun veri fırtınası"
      },
      celiski_kolosu: {
        ad: "Çelişki Kolosu", can: 1500, hiz: 0.45, zirh: 5, puan: 80,
        kaynak: 80, renk: "#f72585", sekil: "kolos", ozellik: "bolunen",
        aciklama: "Yıkıldığında dört Çelişki'ye ayrılır"
      },
      kaos_cekirdegi: {
        ad: "Kaos Çekirdeği", can: 2400, hiz: 0.4, zirh: 6, puan: 110,
        kaynak: 110, renk: "#7209b7", sekil: "kaos", ozellik: "iyilestiren",
        aciklama: "Bilgi Çekirdeği'nin karanlık aynası; yanındakileri onarır"
      },
      veri_hortumu: {
        ad: "Veri Hortumu", can: 3200, hiz: 0.4, zirh: 6, puan: 100,
        kaynak: 100, renk: "#f9844a", sekil: "firtina", ozellik: "hizlanan",
        aciklama: "Çekirdeğe yaklaştıkça ivmelenen dev veri burgacı"
      }
    },

    kahramanAl: function(id) {
      return BS.denge.kahramanlar[id] || null;
    },

    dusmanAl: function(id) {
      return BS.denge.dusmanlar[id] || BS.denge.patronlar[id] || null;
    },

    // Yükseltme sonrası etkin istatistikler (seviye: 0..3; 0 = taban).
    kahramanIstatistik: function(id, seviye) {
      var taban = BS.denge.kahramanAl(id);
      if (!taban) return null;
      var sonuc = {
        hasar: taban.hasar,
        menzil: taban.menzil,
        atisAraligi: taban.atisAraligi,
        kritCarpan: taban.isaret ? taban.isaret.kritCarpani : 1,
        zirhDelme: taban.zirhDelme || 0,
        yavasCarpan: taban.yavaslatma ? taban.yavaslatma.carpan : 1,
        auraCarpan: taban.aura ? taban.aura.atisHiziCarpani : 1,
        onarimMiktar: taban.onarim ? taban.onarim.miktar : 0,
        onarimAralik: taban.onarim ? taban.onarim.aralik : 0,
        menzilBonusu: taban.destek ? taban.destek.menzilBonusu : 0,
        kaynakMiktari: taban.destek ? taban.destek.kaynakMiktari : 0,
        kalkanMiktari: 0,
        gizliGorur: false,
        alanYavas: false
      };
      for (var i = 0; i < seviye && i < taban.yukseltmeler.length; i++) {
        var yuk = taban.yukseltmeler[i];
        if (yuk.hasar != null) sonuc.hasar = yuk.hasar;
        if (yuk.menzil != null) sonuc.menzil = yuk.menzil;
        if (yuk.kritCarpan != null) sonuc.kritCarpan = yuk.kritCarpan;
        if (yuk.zirhDelme != null) sonuc.zirhDelme = yuk.zirhDelme;
        if (yuk.yavasCarpan != null) sonuc.yavasCarpan = yuk.yavasCarpan;
        if (yuk.auraCarpan != null) sonuc.auraCarpan = yuk.auraCarpan;
        if (yuk.onarimMiktar != null) sonuc.onarimMiktar = yuk.onarimMiktar;
        if (yuk.onarimAralik != null) sonuc.onarimAralik = yuk.onarimAralik;
        if (yuk.menzilBonusu != null) sonuc.menzilBonusu = yuk.menzilBonusu;
        if (yuk.kaynakMiktari != null) sonuc.kaynakMiktari = yuk.kaynakMiktari;
        if (yuk.kalkanMiktari != null) sonuc.kalkanMiktari = yuk.kalkanMiktari;
        if (yuk.gizliGorur) sonuc.gizliGorur = true;
        if (yuk.alanYavas) sonuc.alanYavas = true;
      }
      return sonuc;
    },

    // Bir kahramanın o ana kadarki toplam yatırımı (satış iadesi hesabı).
    kahramanYatirim: function(id, seviye) {
      var taban = BS.denge.kahramanAl(id);
      if (!taban) return 0;
      var toplam = taban.maliyet;
      for (var i = 0; i < seviye && i < taban.yukseltmeler.length; i++) {
        toplam += taban.yukseltmeler[i].maliyet;
      }
      return toplam;
    }
  };
})();
