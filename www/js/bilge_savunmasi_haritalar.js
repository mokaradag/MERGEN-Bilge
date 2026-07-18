// www/js/bilge_savunmasi_haritalar.js
// Bilge Savunması kampanya haritaları: ızgara ölçüleri, tehdit rotaları
// (hücre koordinatlı ara noktalar), inşa edilemez hücreler, tema renkleri ve
// dalga kompozisyon planları. Salt veri + küçük erişim yardımcıları; çizim ve
// simülasyon bu tanımları okur. Harita kimlikleri R tarafındaki
// bs_harita_katalogu() ile birebir aynıdır.

(function() {
  "use strict";

  var BS = window.BilgeSavunmasi = window.BilgeSavunmasi || {};

  // Ortak ızgara: 20 x 12 hücre. Rotalar hücre merkezlerinden geçer.
  var IZGARA = { genislik: 20, yukseklik: 12 };

  BS.haritalar = {
    IZGARA: IZGARA,

    liste: {
      // ── 1) BAĞLAM KAPISI — tek ana rota, öğretici ─────────────────────────
      baglam_kapisi: {
        id: "baglam_kapisi",
        ad: "Bağlam Kapısı",
        dalgaSayisi: 8,
        tabanCekirdek: 20,
        tema: {
          zemin1: "#101623", zemin2: "#0b101b",
          yol: "#233046", yolKenar: "#3d5a80",
          vurgu: "#4cc9f0", izgara: "rgba(76, 201, 240, 0.05)"
        },
        cekirdek: { x: 18, y: 6 },
        yollar: [
          [
            { x: 0, y: 2 }, { x: 5, y: 2 }, { x: 5, y: 6 },
            { x: 10, y: 6 }, { x: 10, y: 9 }, { x: 15, y: 9 },
            { x: 15, y: 6 }, { x: 18, y: 6 }
          ]
        ],
        insaEdilemez: [
          { x: 0, y: 0 }, { x: 1, y: 0 }, { x: 0, y: 11 }, { x: 1, y: 11 },
          { x: 19, y: 0 }, { x: 19, y: 11 }
        ],
        dekor: "kapi",
        // Dalga kompozisyonları: { dusman, adet } grupları. 4. ve son dalga
        // patron/baskı dalgasıdır (sunucu kuralıyla aynı).
        dalgaPlani: [
          [ { dusman: "gurultu", adet: 6 } ],
          [ { dusman: "gurultu", adet: 8 }, { dusman: "daginik_istek", adet: 4 } ],
          [ { dusman: "gurultu", adet: 6 }, { dusman: "yanlis_baglam", adet: 4 } ],
          [ { dusman: "yanlis_baglam", adet: 6 }, { dusman: "bozuk_veri", adet: 5 },
            { dusman: "patron:bilgi_firtinasi", adet: 1 } ],
          [ { dusman: "bozuk_veri", adet: 8 }, { dusman: "belirsizlik", adet: 3 } ],
          [ { dusman: "yanlis_baglam", adet: 7 }, { dusman: "celiski", adet: 3 } ],
          [ { dusman: "gurultu", adet: 10 }, { dusman: "yonlendirme", adet: 5 } ],
          [ { dusman: "celiski", adet: 5 }, { dusman: "yonlendirme", adet: 6 },
            { dusman: "patron:bilgi_firtinasi", adet: 1 } ]
        ]
      },

      // ── 2) ÇELİŞKİ KAVŞAĞI — çift rota, öncelik ve kontrol ────────────────
      celiski_kavsagi: {
        id: "celiski_kavsagi",
        ad: "Çelişki Kavşağı",
        dalgaSayisi: 10,
        tabanCekirdek: 20,
        tema: {
          zemin1: "#161020", zemin2: "#0f0a18",
          yol: "#2d2440", yolKenar: "#7b5ea7",
          vurgu: "#c77dff", izgara: "rgba(199, 125, 255, 0.05)"
        },
        cekirdek: { x: 18, y: 6 },
        yollar: [
          [
            { x: 0, y: 1 }, { x: 8, y: 1 }, { x: 8, y: 4 },
            { x: 13, y: 4 }, { x: 13, y: 6 }, { x: 18, y: 6 }
          ],
          [
            { x: 0, y: 10 }, { x: 6, y: 10 }, { x: 6, y: 8 },
            { x: 13, y: 8 }, { x: 13, y: 6 }, { x: 18, y: 6 }
          ]
        ],
        insaEdilemez: [
          { x: 0, y: 5 }, { x: 0, y: 6 }, { x: 1, y: 5 }, { x: 1, y: 6 },
          { x: 19, y: 0 }, { x: 19, y: 11 }
        ],
        dekor: "kavsak",
        dalgaPlani: [
          [ { dusman: "gurultu", adet: 8 } ],
          [ { dusman: "gurultu", adet: 6 }, { dusman: "bozuk_veri", adet: 6 } ],
          [ { dusman: "yanlis_baglam", adet: 6 }, { dusman: "daginik_istek", adet: 6 } ],
          [ { dusman: "celiski", adet: 5 }, { dusman: "belirsizlik", adet: 4 },
            { dusman: "patron:celiski_kolosu", adet: 1 } ],
          [ { dusman: "yonlendirme", adet: 7 }, { dusman: "bozuk_veri", adet: 6 } ],
          [ { dusman: "varsayim", adet: 4 }, { dusman: "yanlis_baglam", adet: 6 } ],
          [ { dusman: "celiski", adet: 6 }, { dusman: "belirsizlik", adet: 5 } ],
          [ { dusman: "varsayim", adet: 5 }, { dusman: "yonlendirme", adet: 7 },
            { dusman: "patron:celiski_kolosu", adet: 1 } ],
          [ { dusman: "sahte_kesinlik", adet: 3 }, { dusman: "celiski", adet: 6 },
            { dusman: "daginik_istek", adet: 8 } ],
          [ { dusman: "sahte_kesinlik", adet: 4 }, { dusman: "varsayim", adet: 5 },
            { dusman: "patron:celiski_kolosu", adet: 1 } ]
        ]
      },

      // ── 3) BİLGİ ÇEKİRDEĞİ — elit tehditler ve nihai baskı ────────────────
      bilgi_cekirdegi: {
        id: "bilgi_cekirdegi",
        ad: "Bilgi Çekirdeği",
        dalgaSayisi: 12,
        tabanCekirdek: 20,
        tema: {
          zemin1: "#0c1a17", zemin2: "#081210",
          yol: "#1d3833", yolKenar: "#2d6a4f",
          vurgu: "#52e0c4", izgara: "rgba(82, 224, 196, 0.05)"
        },
        cekirdek: { x: 17, y: 6 },
        yollar: [
          [
            { x: 0, y: 3 }, { x: 4, y: 3 }, { x: 4, y: 1 },
            { x: 9, y: 1 }, { x: 9, y: 5 }, { x: 13, y: 5 },
            { x: 13, y: 6 }, { x: 17, y: 6 }
          ],
          [
            { x: 0, y: 9 }, { x: 5, y: 9 }, { x: 5, y: 11 },
            { x: 11, y: 11 }, { x: 11, y: 7 }, { x: 13, y: 7 },
            { x: 13, y: 6 }, { x: 17, y: 6 }
          ]
        ],
        insaEdilemez: [
          { x: 19, y: 0 }, { x: 19, y: 1 }, { x: 19, y: 10 }, { x: 19, y: 11 },
          { x: 0, y: 0 }, { x: 0, y: 6 }
        ],
        dekor: "cekirdek",
        dalgaPlani: [
          [ { dusman: "gurultu", adet: 9 }, { dusman: "daginik_istek", adet: 5 } ],
          [ { dusman: "bozuk_veri", adet: 8 }, { dusman: "yanlis_baglam", adet: 5 } ],
          [ { dusman: "belirsizlik", adet: 6 }, { dusman: "yonlendirme", adet: 6 } ],
          [ { dusman: "celiski", adet: 6 }, { dusman: "varsayim", adet: 4 },
            { dusman: "patron:bilgi_firtinasi", adet: 1 } ],
          [ { dusman: "bilgi_yuku", adet: 4 }, { dusman: "bozuk_veri", adet: 8 } ],
          [ { dusman: "sahte_kesinlik", adet: 3 }, { dusman: "belirsizlik", adet: 6 } ],
          [ { dusman: "varsayim", adet: 6 }, { dusman: "yonlendirme", adet: 8 } ],
          [ { dusman: "bilgi_yuku", adet: 5 }, { dusman: "celiski", adet: 6 },
            { dusman: "patron:celiski_kolosu", adet: 1 } ],
          [ { dusman: "sahte_kesinlik", adet: 4 }, { dusman: "bilgi_yuku", adet: 4 },
            { dusman: "daginik_istek", adet: 10 } ],
          [ { dusman: "varsayim", adet: 7 }, { dusman: "yonlendirme", adet: 9 } ],
          [ { dusman: "sahte_kesinlik", adet: 5 }, { dusman: "celiski", adet: 8 } ],
          [ { dusman: "bilgi_yuku", adet: 6 }, { dusman: "sahte_kesinlik", adet: 4 },
            { dusman: "patron:kaos_cekirdegi", adet: 1 } ]
        ]
      }
    },

    haritaAl: function(id) {
      return BS.haritalar.liste[id] || null;
    },

    siraliListe: function() {
      return [
        BS.haritalar.liste.baglam_kapisi,
        BS.haritalar.liste.celiski_kavsagi,
        BS.haritalar.liste.bilgi_cekirdegi
      ];
    }
  };
})();
