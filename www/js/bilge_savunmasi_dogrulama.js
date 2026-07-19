// www/js/bilge_savunmasi_dogrulama.js
// Bilge Savunması sonuç doğrulama yaşam döngüsü: koşu özetini sunucuya
// gönderir, sınırlı bir doğrulama beklemesi başlatır, zaman aşımında
// idempotent "Tekrar Dene" sunar ve sunucu yanıtını bayat/yinelenen yanıt
// korumalarıyla işler. Sonuçlandırma istemci jetonuyla idempotenttir;
// tekrar gönderim ödülleri asla çoğaltmaz (sunucu tarafı garanti).

(function() {
  "use strict";

  var BS = window.BilgeSavunmasi = window.BilgeSavunmasi || {};

  var ZAMAN_ASIMI_MS = 20000;

  function zamanlayiciDurdur(kosu) {
    if (kosu && kosu.dogrulamaZamanlayici) {
      clearTimeout(kosu.dogrulamaZamanlayici);
      kosu.dogrulamaZamanlayici = null;
    }
  }

  function baslikHtml(kosu) {
    return '<h3>' + (kosu.ozet && kosu.ozet.zafer
      ? "Zafer!" : "Çekirdek Düştü") + '</h3>';
  }

  // Özeti gönderir ve sınırlı doğrulama beklemesi başlatır. Zaman aşımında
  // kaplama terminal olmayan yükleme durumunda bırakılmaz; kullanıcıya
  // tekrar deneme ve menüye dönüş eylemleri sunulur.
  function gonder(kosu) {
    zamanlayiciDurdur(kosu);
    kosu.hud.kaplamaGoster(
      baslikHtml(kosu) +
      '<p class="bs-kaplama-notu">Sonuç sunucuda doğrulanıyor...</p>'
    );
    BS.kopru.kosuBitir(kosu.kosuId, kosu.jeton, kosu.ozet);
    kosu.dogrulamaZamanlayici = setTimeout(function() {
      kosu.dogrulamaZamanlayici = null;
      // Geç yanıt geldiyse ya da koşu değiştiyse zaman aşımı arayüzü açılmaz.
      if (BS.uygulama.kosu !== kosu || kosu.sonSonuc) return;
      kosu.hud.kaplamaGoster(
        baslikHtml(kosu) +
        '<p class="bs-kaplama-notu">Sonuç doğrulaması yanıt vermedi. ' +
        'Bağlantını kontrol edip tekrar deneyebilirsin; sonucun kaybolmaz.</p>' +
        '<div class="bs-sonuc-dugmeler">' +
          '<button type="button" class="bs-yan-dugme bs-yan-dugme-birincil" ' +
                  'data-bs-komut="dogrulama-tekrar">' +
            '<i class="fa fa-rotate-right" aria-hidden="true"></i> Tekrar Dene' +
          '</button>' +
          '<button type="button" class="bs-yan-dugme" data-bs-komut="menu-don">' +
            'Menüye Dön</button>' +
        '</div>'
      );
    }, ZAMAN_ASIMI_MS);
  }

  BS.dogrulama = {
    gonder: gonder,
    zamanlayiciDurdur: zamanlayiciDurdur
  };

  BS.olaylar.ekle("sunucu-kosu-sonuc", function(sonuc) {
    var kosu = BS.uygulama && BS.uygulama.kosu;
    if (!kosu || !sonuc) return;
    // Bayat yanıt koruması: yanıt koşu kimliği taşıyorsa aktif koşuyla
    // eşleşmelidir; eski bir koşunun geç yanıtı yeni koşuyu ezemez.
    if (sonuc.kosu_id != null && kosu.kosuId != null &&
        Number(sonuc.kosu_id) !== Number(kosu.kosuId)) return;
    // Yinelenen/geç yanıt: sonuç zaten işlendiyse yeniden uygulanmaz.
    if (kosu.sonSonuc) return;
    zamanlayiciDurdur(kosu);
    kosu.sonSonuc = sonuc;
    BS.sonuc.goster(kosu, sonuc);
  });
})();
