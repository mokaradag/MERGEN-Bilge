// www/js/pixel_sprite_render.js
// Ortak piksel persona çizim yardımcısı. www/js/claude_code_pixel_chars.js
// verisini (genişletilmiş palet: 1-3 kıyafet, 4-5 deri, 6 saç, 7 detay,
// 8 aksesuar) açık/koyu temaya DUYARLI biçimde çizer: figürün etrafına ince
// bir kontur eklenir; kontur açık temada koyu, koyu temada açıktır; böylece
// sprite her iki tema arka planında da net okunur. Ayrıca genişletilmiş
// paleti olmayan eski veriyle (yalnızca color/darkColor/lightColor) geriye
// uyumlu kalır. Bu dosya www/js/claude_code.js ve
// www/js/bilge_yolac_karsilama.js tarafından kullanılır.

(function() {
  "use strict";

  // Aktif temayı çöz: <html data-theme="..."> yoksa koyu varsayılır.
  function aktifTema() {
    try {
      var t = document.documentElement.getAttribute("data-theme");
      return t === "light" ? "light" : "dark";
    } catch (hata) {
      return "dark";
    }
  }

  // Bir pikselin rengini palet ya da eski color/darkColor/lightColor'dan çöz.
  function pikselRengi(charData, deger) {
    if (charData.palette && charData.palette[deger]) {
      return charData.palette[deger];
    }
    if (deger === 1) return charData.color;
    if (deger === 2) return charData.darkColor;
    if (deger === 3) return charData.lightColor || charData.color;
    // Genişletilmiş değerler eski veride yoksa ana renge düşer.
    return charData.color;
  }

  // Bir karenin (16x16) belirli bir hücresi dolu mu (kontur hesabı için).
  function dolu(kare, x, y) {
    return y >= 0 && y < kare.length && x >= 0 && x < kare[y].length &&
      kare[y][x] !== 0;
  }

  window.MergenPixelSprite = {

    aktifTema: aktifTema,

    // ctx: 2D bağlam; charData: persona verisi; frameIdx: kare no;
    // secenekler: { pixelSize, offsetX, offsetY, kontur (bool, vars. true),
    //   tema ("light"/"dark", vars. otomatik) }
    ciz: function(ctx, charData, frameIdx, secenekler) {
      secenekler = secenekler || {};
      var kare = charData.frames[frameIdx % charData.frames.length];
      if (!kare) return;
      var ps = secenekler.pixelSize || 3;
      var ox = secenekler.offsetX || 0;
      var oy = secenekler.offsetY || 0;
      var tema = secenekler.tema || aktifTema();
      var konturVar = secenekler.kontur !== false;
      // Açık temada koyu kontur, koyu temada açık kontur (net okunurluk).
      var konturRenk = tema === "light"
        ? "rgba(20, 26, 40, 0.55)" : "rgba(240, 244, 250, 0.5)";

      // Önce kontur: her dolu pikselin boş komşularına ince kenar.
      if (konturVar) {
        ctx.fillStyle = konturRenk;
        for (var cy = 0; cy < kare.length; cy++) {
          for (var cx = 0; cx < kare[cy].length; cx++) {
            if (!dolu(kare, cx, cy)) continue;
            if (!dolu(kare, cx, cy - 1)) {
              ctx.fillRect(ox + cx * ps, oy + cy * ps - 1, ps, 1);
            }
            if (!dolu(kare, cx, cy + 1)) {
              ctx.fillRect(ox + cx * ps, oy + cy * ps + ps, ps, 1);
            }
            if (!dolu(kare, cx - 1, cy)) {
              ctx.fillRect(ox + cx * ps - 1, oy + cy * ps, 1, ps);
            }
            if (!dolu(kare, cx + 1, cy)) {
              ctx.fillRect(ox + cx * ps + ps, oy + cy * ps, 1, ps);
            }
          }
        }
      }

      // Sonra gövde piksellerini palet renkleriyle çiz.
      for (var y = 0; y < kare.length; y++) {
        for (var x = 0; x < kare[y].length; x++) {
          var deger = kare[y][x];
          if (deger === 0) continue;
          ctx.fillStyle = pikselRengi(charData, deger);
          ctx.fillRect(ox + x * ps, oy + y * ps, ps - 0.5, ps - 0.5);
        }
      }
    }
  };
})();
