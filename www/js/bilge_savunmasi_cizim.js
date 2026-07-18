// www/js/bilge_savunmasi_cizim.js
// Bilge Savunması canvas çizim katmanı: katmanlı arka plan (zemin + ızgara +
// rota + dekor) offscreen'e bir kez çizilir; dinamik katman (tehditler,
// kahramanlar, mermiler, efektler, önizlemeler) her karede çizilir.
// Persona portreleri kanonik varlık yollarından yüklenir; yükleme başarısız
// olursa aksan renkli baş harf diski kullanılır (zarif geri düşüş).
// Kalite seviyeleri: yuksek / dengeli / performans.

(function() {
  "use strict";

  var BS = window.BilgeSavunmasi = window.BilgeSavunmasi || {};

  // ── Portre önbelleği (tüm sayfa için tek) ───────────────────────────────────
  var portreler = {};   // personaId -> { hazir, tuval }

  function portreYedekCiz(persona, boyut) {
    var tuval = document.createElement("canvas");
    tuval.width = boyut;
    tuval.height = boyut;
    var ctx = tuval.getContext("2d");
    var merkez = boyut / 2;

    var grd = ctx.createLinearGradient(0, 0, boyut, boyut);
    grd.addColorStop(0, persona.aksan || "#4cc9f0");
    grd.addColorStop(1, persona.aksan_koyu || "#1d3557");
    ctx.fillStyle = grd;
    ctx.beginPath();
    ctx.arc(merkez, merkez, merkez, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = "rgba(255,255,255,0.92)";
    ctx.font = "600 " + Math.round(boyut * 0.46) + "px 'Segoe UI', sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    var harf = (persona.ad || persona.id || "?").charAt(0).toLocaleUpperCase("tr-TR");
    ctx.fillText(harf, merkez, merkez + boyut * 0.03);
    return tuval;
  }

  function portreDairesel(resim, boyut) {
    var tuval = document.createElement("canvas");
    tuval.width = boyut;
    tuval.height = boyut;
    var ctx = tuval.getContext("2d");
    ctx.beginPath();
    ctx.arc(boyut / 2, boyut / 2, boyut / 2, 0, Math.PI * 2);
    ctx.clip();
    // Yüz oranı korunur: kapsayacak şekilde ortalanmış kırpma (cover),
    // esnetme/bozma yapılmaz.
    var oran = Math.max(boyut / resim.width, boyut / resim.height);
    var gw = resim.width * oran;
    var gh = resim.height * oran;
    ctx.drawImage(resim, (boyut - gw) / 2, (boyut - gh) / 2 - gh * 0.06, gw, gh);
    return tuval;
  }

  BS.cizim = {

    // Persona manifestinden portreleri hazırla (bir kez; idempotent).
    portreleriYukle: function(personalar) {
      (personalar || []).forEach(function(persona) {
        if (portreler[persona.id]) return;
        var kayit = {
          hazir: true,
          persona: persona,
          tuval: portreYedekCiz(persona, 96)
        };
        portreler[persona.id] = kayit;

        var adaylar = [persona.portre, persona.avatar].filter(Boolean);
        function dene(sira) {
          if (sira >= adaylar.length) return; // yedek disk zaten hazır
          var resim = new Image();
          resim.onload = function() {
            try {
              kayit.tuval = portreDairesel(resim, 96);
            } catch (hata) { /* yedek disk kalır */ }
          };
          resim.onerror = function() { dene(sira + 1); };
          resim.src = adaylar[sira];
        }
        dene(0);
      });
    },

    portreAl: function(personaId) {
      return portreler[personaId] || null;
    },

    // ── Çizici örneği ─────────────────────────────────────────────────────────
    olustur: function(kap, harita, secenekler) {
      var izgara = BS.haritalar.IZGARA;
      var tuval = document.createElement("canvas");
      tuval.className = "bs-oyun-tuvali";
      tuval.setAttribute("aria-hidden", "true");
      kap.appendChild(tuval);
      var ctx = tuval.getContext("2d");

      var arka = document.createElement("canvas");
      var arkaCtx = arka.getContext("2d");

      var cizici = {
        hucre: 34,
        kenarX: 0,
        kenarY: 0,
        zaman: 0
      };

      function hucreX(hx) { return cizici.kenarX + (hx + 0.5) * cizici.hucre; }
      function hucreY(hy) { return cizici.kenarY + (hy + 0.5) * cizici.hucre; }
      cizici.hucreX = hucreX;
      cizici.hucreY = hucreY;
      cizici.tuval = tuval;

      var dpr = 1;

      // İstemci (CSS piksel) koordinatını ızgara hücresine çevirir.
      cizici.pikseldenHucre = function(px, py) {
        var kutu = tuval.getBoundingClientRect();
        var icX = (px - kutu.left) * dpr;
        var icY = (py - kutu.top) * dpr;
        return {
          x: Math.floor((icX - cizici.kenarX) / cizici.hucre),
          y: Math.floor((icY - cizici.kenarY) / cizici.hucre)
        };
      };

      // ── Boyutlandırma ve statik arka plan ───────────────────────────────────
      cizici.boyutlandir = function() {
        var gen = Math.max(320, kap.clientWidth || 800);
        var yuk = Math.max(240, kap.clientHeight || 480);
        dpr = BS.yardimci.kirp(window.devicePixelRatio || 1, 1, 2);

        cizici.hucre = Math.floor(Math.min(
          (gen * dpr) / izgara.genislik,
          (yuk * dpr) / izgara.yukseklik
        ));
        var icGen = cizici.hucre * izgara.genislik;
        var icYuk = cizici.hucre * izgara.yukseklik;

        tuval.width = gen * dpr;
        tuval.height = yuk * dpr;
        tuval.style.width = gen + "px";
        tuval.style.height = yuk + "px";
        cizici.kenarX = Math.floor((tuval.width - icGen) / 2);
        cizici.kenarY = Math.floor((tuval.height - icYuk) / 2);

        arka.width = tuval.width;
        arka.height = tuval.height;
        arkaPlanCiz();
      };

      function arkaPlanCiz() {
        var tema = harita.tema;
        var c = arkaCtx;

        var grd = c.createLinearGradient(0, 0, 0, arka.height);
        grd.addColorStop(0, tema.zemin1);
        grd.addColorStop(1, tema.zemin2);
        c.fillStyle = grd;
        c.fillRect(0, 0, arka.width, arka.height);

        // Paralaks yıldız/veri noktaları (görsel tohum: harita kimliği).
        var rng = BS.rng.olustur(BS.rng.dizedenTohum(harita.id));
        c.fillStyle = "rgba(255,255,255,0.16)";
        for (var i = 0; i < 90; i++) {
          var px = rng.sonraki() * arka.width;
          var py = rng.sonraki() * arka.height;
          var b = rng.sonraki() * 1.6 + 0.4;
          c.globalAlpha = 0.05 + rng.sonraki() * 0.2;
          c.fillRect(px, py, b, b);
        }
        c.globalAlpha = 1;

        // Izgara çizgileri.
        c.strokeStyle = tema.izgara;
        c.lineWidth = 1;
        for (var gx = 0; gx <= izgara.genislik; gx++) {
          c.beginPath();
          c.moveTo(cizici.kenarX + gx * cizici.hucre, cizici.kenarY);
          c.lineTo(cizici.kenarX + gx * cizici.hucre,
                   cizici.kenarY + izgara.yukseklik * cizici.hucre);
          c.stroke();
        }
        for (var gy = 0; gy <= izgara.yukseklik; gy++) {
          c.beginPath();
          c.moveTo(cizici.kenarX, cizici.kenarY + gy * cizici.hucre);
          c.lineTo(cizici.kenarX + izgara.genislik * cizici.hucre,
                   cizici.kenarY + gy * cizici.hucre);
          c.stroke();
        }

        // Rotalar: kenarlıklı geniş şerit + orta çizgi.
        harita.yollar.forEach(function(yol) {
          c.lineCap = "round";
          c.lineJoin = "round";
          c.strokeStyle = tema.yolKenar;
          c.lineWidth = cizici.hucre * 0.78;
          yolCiz(c, yol);
          c.strokeStyle = tema.yol;
          c.lineWidth = cizici.hucre * 0.62;
          yolCiz(c, yol);
          c.strokeStyle = "rgba(255,255,255,0.07)";
          c.lineWidth = 2;
          c.setLineDash([cizici.hucre * 0.3, cizici.hucre * 0.35]);
          yolCiz(c, yol);
          c.setLineDash([]);

          // Giriş kapısı işareti.
          var giris = yol[0];
          c.fillStyle = tema.vurgu;
          c.globalAlpha = 0.7;
          c.beginPath();
          c.moveTo(hucreX(giris.x) - cizici.hucre * 0.32, hucreY(giris.y) - cizici.hucre * 0.3);
          c.lineTo(hucreX(giris.x) + cizici.hucre * 0.05, hucreY(giris.y));
          c.lineTo(hucreX(giris.x) - cizici.hucre * 0.32, hucreY(giris.y) + cizici.hucre * 0.3);
          c.closePath();
          c.fill();
          c.globalAlpha = 1;
        });

        // İnşa edilemez hücre dokusu.
        c.fillStyle = "rgba(0,0,0,0.25)";
        harita.insaEdilemez.forEach(function(h) {
          c.fillRect(cizici.kenarX + h.x * cizici.hucre,
                     cizici.kenarY + h.y * cizici.hucre,
                     cizici.hucre, cizici.hucre);
        });
      }

      function yolCiz(c, yol) {
        c.beginPath();
        c.moveTo(hucreX(yol[0].x), hucreY(yol[0].y));
        for (var i = 1; i < yol.length; i++) {
          c.lineTo(hucreX(yol[i].x), hucreY(yol[i].y));
        }
        c.stroke();
      }

      // ── Dinamik çizimler ────────────────────────────────────────────────────
      function cekirdekCiz(durum) {
        var x = hucreX(harita.cekirdek.x);
        var y = hucreY(harita.cekirdek.y);
        var r = cizici.hucre * 0.85;
        var nabiz = BS.kalite.azaltilmisHareket
          ? 0 : Math.sin(cizici.zaman * 2.2) * 0.06;

        if (BS.kalite.seviye !== "performans") {
          var halo = ctx.createRadialGradient(x, y, r * 0.2, x, y, r * 1.7);
          halo.addColorStop(0, harita.tema.vurgu + "55");
          halo.addColorStop(1, "rgba(0,0,0,0)");
          ctx.fillStyle = halo;
          ctx.fillRect(x - r * 2, y - r * 2, r * 4, r * 4);
        }

        ctx.fillStyle = harita.tema.vurgu;
        ctx.globalAlpha = 0.9;
        ctx.beginPath();
        ctx.arc(x, y, r * (0.52 + nabiz), 0, Math.PI * 2);
        ctx.fill();
        ctx.globalAlpha = 1;
        ctx.fillStyle = "#0b1020";
        ctx.beginPath();
        ctx.arc(x, y, r * 0.36, 0, Math.PI * 2);
        ctx.fill();
        ctx.strokeStyle = "rgba(255,255,255,0.8)";
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.arc(x, y, r * (0.52 + nabiz), 0, Math.PI * 2);
        ctx.stroke();

        // Can oranı yayı + kalkan yayı.
        var oran = durum.cekirdek / durum.tabanCekirdek;
        ctx.strokeStyle = oran > 0.6 ? "#7ae582" : (oran > 0.3 ? "#ffd166" : "#e63946");
        ctx.lineWidth = 4;
        ctx.beginPath();
        ctx.arc(x, y, r * 0.72, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * oran);
        ctx.stroke();
        if (durum.cekirdekKalkani > 0) {
          ctx.strokeStyle = "#90e0ef";
          ctx.lineWidth = 2.5;
          ctx.beginPath();
          ctx.arc(x, y, r * 0.85, -Math.PI / 2,
                  -Math.PI / 2 + Math.PI * 2 *
                  Math.min(1, durum.cekirdekKalkani / 20));
          ctx.stroke();
        }
      }

      function dusmanSekliCiz(dusman, x, y, r) {
        var sekil = dusman.tanim.sekil;
        ctx.beginPath();
        if (sekil === "ucgen" || sekil === "ok") {
          ctx.moveTo(x + r, y);
          ctx.lineTo(x - r * 0.7, y - r * 0.75);
          ctx.lineTo(x - r * 0.7, y + r * 0.75);
        } else if (sekil === "kare" || sekil === "yigin") {
          ctx.rect(x - r * 0.75, y - r * 0.75, r * 1.5, r * 1.5);
        } else if (sekil === "elmas" || sekil === "kalkan") {
          ctx.moveTo(x, y - r);
          ctx.lineTo(x + r * 0.8, y);
          ctx.lineTo(x, y + r);
          ctx.lineTo(x - r * 0.8, y);
        } else if (sekil === "altigen" || sekil === "kolos" ||
                   sekil === "firtina" || sekil === "kaos") {
          for (var i = 0; i < 6; i++) {
            var aci = Math.PI / 3 * i - Math.PI / 6;
            var px = x + Math.cos(aci) * r;
            var py = y + Math.sin(aci) * r;
            if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
          }
        } else {
          ctx.arc(x, y, r * 0.85, 0, Math.PI * 2);
        }
        ctx.closePath();
        ctx.fill();
      }

      function dusmanlariCiz(durum) {
        durum.dusmanlar.forEach(function(dusman) {
          var x = cizici.kenarX + (dusman.x + 0.5) * cizici.hucre;
          var y = cizici.kenarY + (dusman.y + 0.5) * cizici.hucre;
          var r = cizici.hucre * (dusman.patronMu ? 0.62 : 0.3);

          ctx.globalAlpha = dusman.gizliMi ? 0.22 : 1;

          if (BS.kalite.seviye === "yuksek" && !dusman.gizliMi) {
            ctx.shadowColor = dusman.tanim.renk;
            ctx.shadowBlur = dusman.patronMu ? 18 : 8;
          }
          ctx.fillStyle = dusman.tanim.renk;
          dusmanSekliCiz(dusman, x, y, r);
          ctx.shadowBlur = 0;

          // Durum halkaları: yavaş (mavi), işaretli (turuncu), kalkan (yay).
          if (dusman.yavasCarpan < 1) {
            ctx.strokeStyle = "#4cc9f0";
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.arc(x, y, r + 4, 0, Math.PI * 2);
            ctx.stroke();
          }
          if (dusman.isaretKalan > 0) {
            ctx.strokeStyle = "#f77f00";
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.moveTo(x, y - r - 7);
            ctx.lineTo(x + 5, y - r - 2);
            ctx.lineTo(x, y - r + 3);
            ctx.lineTo(x - 5, y - r - 2);
            ctx.closePath();
            ctx.stroke();
          }
          if (dusman.kalkan > 0) {
            ctx.strokeStyle = "#e5989b";
            ctx.lineWidth = 3;
            ctx.beginPath();
            ctx.arc(x, y, r + 3, -Math.PI * 0.8, -Math.PI * 0.2);
            ctx.stroke();
          }

          // Can çubuğu.
          var oran = BS.yardimci.kirp(dusman.can / dusman.maxCan, 0, 1);
          var cw = r * 2;
          ctx.fillStyle = "rgba(0,0,0,0.55)";
          ctx.fillRect(x - cw / 2, y - r - 12, cw, 4);
          ctx.fillStyle = oran > 0.5 ? "#7ae582" : (oran > 0.25 ? "#ffd166" : "#e63946");
          ctx.fillRect(x - cw / 2, y - r - 12, cw * oran, 4);

          ctx.globalAlpha = 1;
        });
      }

      function kahramanlariCiz(durum, arayuz) {
        Object.keys(durum.kahramanlar).forEach(function(id) {
          var kahraman = durum.kahramanlar[id];
          if (!kahraman.yerlesik) return;
          var x = cizici.kenarX + (kahraman.x + 0.5) * cizici.hucre;
          var y = cizici.kenarY + (kahraman.y + 0.5) * cizici.hucre;
          var r = cizici.hucre * 0.42;
          var portre = BS.cizim.portreAl(id);
          var aksan = portre && portre.persona ? portre.persona.aksan : "#4cc9f0";

          // Seçiliyken menzil çemberi.
          if (arayuz && arayuz.seciliKahraman === id) {
            var ist = BS.denge.kahramanIstatistik(id, kahraman.seviye);
            ctx.fillStyle = aksan + "14";
            ctx.strokeStyle = aksan + "66";
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            ctx.arc(x, y, ist.menzil * cizici.hucre, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
          }

          // Taban platformu + portre.
          ctx.fillStyle = "rgba(8, 12, 22, 0.9)";
          ctx.beginPath();
          ctx.arc(x, y, r + 4, 0, Math.PI * 2);
          ctx.fill();
          if (portre) {
            ctx.save();
            ctx.beginPath();
            ctx.arc(x, y, r, 0, Math.PI * 2);
            ctx.clip();
            ctx.drawImage(portre.tuval, x - r, y - r, r * 2, r * 2);
            ctx.restore();
          }
          ctx.strokeStyle = aksan;
          ctx.lineWidth = 2.5;
          ctx.beginPath();
          ctx.arc(x, y, r + 1, 0, Math.PI * 2);
          ctx.stroke();

          // Kademe noktaları.
          for (var s = 0; s < kahraman.seviye; s++) {
            ctx.fillStyle = "#ffd166";
            ctx.beginPath();
            ctx.arc(x - 8 + s * 8, y + r + 7, 2.6, 0, Math.PI * 2);
            ctx.fill();
          }

          // Yetenek bekleme yayı.
          var tanim = BS.denge.kahramanAl(id);
          if (kahraman.yetenekKalan > 0 && tanim) {
            var oran = 1 - kahraman.yetenekKalan / tanim.yetenek.beklemeSuresi;
            ctx.strokeStyle = "rgba(255,255,255,0.75)";
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.arc(x, y, r + 5, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * oran);
            ctx.stroke();
          } else if (kahraman.yetenekAktif > 0) {
            ctx.strokeStyle = aksan;
            ctx.lineWidth = 3;
            ctx.globalAlpha = 0.5 + 0.4 * Math.sin(cizici.zaman * 8);
            ctx.beginPath();
            ctx.arc(x, y, r + 6, 0, Math.PI * 2);
            ctx.stroke();
            ctx.globalAlpha = 1;
          }
        });
      }

      function mermileriCiz(durum) {
        durum.mermiler.forEach(function(mermi) {
          var x = cizici.kenarX + (mermi.x + 0.5) * cizici.hucre;
          var y = cizici.kenarY + (mermi.y + 0.5) * cizici.hucre;
          var renkler = {
            cozum: "#b8b8ff", sinyal: "#8ecae6", rota: "#4cc9f0",
            dogrulama: "#f77f00", rehber: "#ffc8dd"
          };
          ctx.fillStyle = renkler[mermi.tip] || "#fff";
          ctx.beginPath();
          ctx.arc(x, y, mermi.tip === "dogrulama" ? 4 : 3, 0, Math.PI * 2);
          ctx.fill();
          if (BS.kalite.seviye === "yuksek") {
            ctx.globalAlpha = 0.35;
            ctx.beginPath();
            ctx.arc(x, y, 7, 0, Math.PI * 2);
            ctx.fill();
            ctx.globalAlpha = 1;
          }
        });
      }

      function yerlesimOnizlemeCiz(durum, arayuz) {
        if (!arayuz || !arayuz.yerlesimKahraman || !arayuz.hucre) return;
        var hx = arayuz.hucre.x, hy = arayuz.hucre.y;
        var uygun = arayuz.hucreDurumu === "insa";
        var x = cizici.kenarX + (hx + 0.5) * cizici.hucre;
        var y = cizici.kenarY + (hy + 0.5) * cizici.hucre;

        ctx.fillStyle = uygun ? "rgba(122, 229, 130, 0.25)" : "rgba(230, 57, 70, 0.3)";
        ctx.fillRect(cizici.kenarX + hx * cizici.hucre,
                     cizici.kenarY + hy * cizici.hucre,
                     cizici.hucre, cizici.hucre);

        var tanim = BS.denge.kahramanAl(arayuz.yerlesimKahraman);
        if (tanim && uygun) {
          ctx.strokeStyle = "rgba(255,255,255,0.5)";
          ctx.setLineDash([6, 6]);
          ctx.lineWidth = 1.5;
          ctx.beginPath();
          ctx.arc(x, y, tanim.menzil * cizici.hucre, 0, Math.PI * 2);
          ctx.stroke();
          ctx.setLineDash([]);
        }
      }

      cizici.ciz = function(durum, arayuz, dt) {
        cizici.zaman += dt || 0.016;
        ctx.clearRect(0, 0, tuval.width, tuval.height);
        ctx.drawImage(arka, 0, 0);
        cekirdekCiz(durum);
        dusmanlariCiz(durum);
        kahramanlariCiz(durum, arayuz);
        mermileriCiz(durum);
        if (BS.efekt) BS.efekt.ciz(ctx, cizici);
        yerlesimOnizlemeCiz(durum, arayuz);
      };

      cizici.yokEt = function() {
        if (tuval.parentElement) tuval.parentElement.removeChild(tuval);
      };

      cizici.boyutlandir();
      return cizici;
    }
  };
})();
