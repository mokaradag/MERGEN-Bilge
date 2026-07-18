// www/js/bilge_savunmasi_kopru.js
// Bilge Savunması Shiny köprüsü: sunucudan gelen özel mesajları (bs-init,
// koşu yaşam döngüsü, liderlik, plan, topluluk) BS.olaylar yayınlarına
// çevirir; istemci isteklerini boyut sınırlı JSON olarak modül girdilerine
// gönderir. Nihai puanın kaynağı SUNUCUDUR; köprü yalnızca özet taşır.
// Tekrarlanan gönderimler istemci jetonuyla idempotenttir.

(function() {
  "use strict";

  var BS = window.BilgeSavunmasi = window.BilgeSavunmasi || {};

  var MODUL_ONEKI = "bilge_savunmasi_module-";
  var GONDERIM_SINIRI = 60000;   // R tarafındaki BS_MAX_YUK_KARAKTER ile uyumlu

  function gonder(girdiAdi, yuk) {
    if (typeof Shiny === "undefined" || !Shiny.setInputValue) return false;
    var metin;
    try {
      metin = JSON.stringify(yuk || {});
    } catch (hata) {
      return false;
    }
    if (metin.length > GONDERIM_SINIRI) {
      if (window.console && console.warn) {
        console.warn("[BilgeSavunmasi] gönderim boyut sınırını aştı:", girdiAdi);
      }
      return false;
    }
    Shiny.setInputValue(MODUL_ONEKI + girdiAdi, metin, { priority: "event" });
    return true;
  }

  BS.kopru = {

    // ── Sunucuya istekler ─────────────────────────────────────────────────────
    kosuBaslat: function(istek) {
      istek = istek || {};
      istek.istemci_jetonu = istek.istemci_jetonu || BS.yardimci.jetonUret();
      BS.kopru.sonJeton = istek.istemci_jetonu;
      return gonder("bs_kosu_baslat", istek) ? istek.istemci_jetonu : null;
    },

    kontrolNoktasi: function(kosuId, dalga, durum) {
      return gonder("bs_kontrol_noktasi", {
        kosu_id: kosuId, dalga: dalga, durum: durum
      });
    },

    kosuBitir: function(kosuId, jeton, ozet) {
      return gonder("bs_kosu_bitir", {
        kosu_id: kosuId, istemci_jetonu: jeton, mod: ozet.mod, ozet: ozet
      });
    },

    kosuBirak: function(kosuId) {
      return gonder("bs_kosu_birak", { kosu_id: kosuId });
    },

    ayarKaydet: function(ayarlar) {
      return gonder("bs_ayar_kaydet", ayarlar || {});
    },

    liderlikIste: function() {
      return gonder("bs_liderlik", { t: Date.now() });
    },

    toplulukIste: function() {
      return gonder("bs_topluluk", { t: Date.now() });
    },

    profilYenileIste: function() {
      return gonder("bs_profil_yenile", { t: Date.now() });
    },

    planYayinla: function(kosuId, baslik, plan) {
      return gonder("bs_plan_yayinla", {
        kosu_id: kosuId, baslik: baslik, plan: plan
      });
    },

    planListesiIste: function() {
      return gonder("bs_plan_listesi", { t: Date.now() });
    },

    planDene: function(planId) {
      return gonder("bs_plan_dene", { plan_id: planId });
    },

    planSil: function(planId) {
      return gonder("bs_plan_sil", { plan_id: planId });
    }
  };

  // ── Sunucu mesajları -> oyun olayları ───────────────────────────────────────
  if (typeof Shiny !== "undefined" && Shiny.addCustomMessageHandler) {
    var esle = [
      ["bs-init", "sunucu-init"],
      ["bs-kosu-basladi", "sunucu-kosu-basladi"],
      ["bs-kosu-sonuc", "sunucu-kosu-sonuc"],
      ["bs-liderlik", "sunucu-liderlik"],
      ["bs-topluluk", "sunucu-topluluk"],
      ["bs-plan-listesi", "sunucu-plan-listesi"],
      ["bs-plan-config", "sunucu-plan-config"],
      ["bs-plan-yaniti", "sunucu-plan-yaniti"],
      ["bs-profil", "sunucu-profil"],
      ["bs-hata", "sunucu-hata"]
    ];
    esle.forEach(function(cift) {
      Shiny.addCustomMessageHandler(cift[0], function(mesaj) {
        BS.olaylar.yay(cift[1], mesaj);
      });
    });
  }
})();
