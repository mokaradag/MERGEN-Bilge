// www/js/bilge_savunmasi_cizim.js
// Bilge Savunması canvas çizim katmanı: katmanlı arka plan offscreen'e bir kez
// çizilir (bilge_savunmasi_cizim_zemin.js); dinamik katman (dekor, tehditler,
// KULELER, kahramanlar, mermiler, efektler, önizlemeler) her karede çizilir.
// 2.5D derinlik: sahne varlıkları ızgara Y'sine göre sıralanır (alttaki üstte
// çizilir), gövdeler sahne derinliğine göre hafifçe ölçeklenir ve kule/dekor
// gövdeleri hücre tabanından yukarı uzanır. Persona portreleri kanonik varlık
// yollarından yüklenir; yükleme başarısız olursa aksan renkli baş harf diski
// kullanılır (zarif geri düşüş). Kalite: yuksek / dengeli / performans.

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

      // Dekor planı harita başına bir kez üretilir (deterministik).
      var dekorPlan = BS.varliklar ? BS.varliklar.dekorPlanla(harita) : [];

      // 2.5D derinlik ölçeği: sahnenin altındaki varlıklar biraz daha büyük.
      function derinlikOlcek(gy) {
        return 0.92 + 0.14 * BS.yardimci.kirp(gy / (izgara.yukseklik - 1), 0, 1);
      }

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
        BS.cizimZemin.ciz(arkaCtx, arka, cizici, harita);
      };

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

        // Dönen koruma halkası: çekirdeğin "canlı" hedef hissi.
        if (!BS.kalite.azaltilmisHareket &&
            BS.kalite.seviye !== "performans") {
          ctx.save();
          ctx.translate(x, y);
          ctx.rotate(cizici.zaman * 0.7);
          ctx.strokeStyle = harita.tema.vurgu + "77";
          ctx.lineWidth = 2;
          for (var seg = 0; seg < 3; seg++) {
            ctx.beginPath();
            ctx.arc(0, 0, r * 0.62, seg * Math.PI * 2 / 3,
                    seg * Math.PI * 2 / 3 + Math.PI * 0.42);
            ctx.stroke();
          }
          ctx.restore();
        }

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

      // Gövde yolu (0,0 merkezli): yön dönüşü ctx.rotate ile uygulanır.
      function dusmanYoluOlustur(sekil, r) {
        ctx.beginPath();
        if (sekil === "ucgen" || sekil === "ok") {
          ctx.moveTo(r, 0);
          ctx.lineTo(-r * 0.7, -r * 0.75);
          ctx.lineTo(-r * 0.35, 0);
          ctx.lineTo(-r * 0.7, r * 0.75);
        } else if (sekil === "kare" || sekil === "yigin") {
          ctx.rect(-r * 0.75, -r * 0.75, r * 1.5, r * 1.5);
        } else if (sekil === "elmas" || sekil === "kalkan") {
          ctx.moveTo(0, -r);
          ctx.lineTo(r * 0.8, 0);
          ctx.lineTo(0, r);
          ctx.lineTo(-r * 0.8, 0);
        } else if (sekil === "altigen" || sekil === "kolos" ||
                   sekil === "firtina" || sekil === "kaos") {
          for (var i = 0; i < 6; i++) {
            var aci = Math.PI / 3 * i - Math.PI / 6;
            var px = Math.cos(aci) * r;
            var py = Math.sin(aci) * r;
            if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
          }
        } else {
          ctx.arc(0, 0, r * 0.85, 0, Math.PI * 2);
        }
        ctx.closePath();
      }

      function patronCiz(dusman, x, y, r) {
        var donme = cizici.zaman * 0.9;
        // Dış tehdit halkası: yavaş dönen kesikli çember + diken uçları.
        ctx.save();
        ctx.translate(x, y);
        ctx.rotate(donme);
        ctx.strokeStyle = dusman.tanim.renk + "88";
        ctx.lineWidth = 2.5;
        ctx.setLineDash([r * 0.5, r * 0.32]);
        ctx.beginPath();
        ctx.arc(0, 0, r * 1.28, 0, Math.PI * 2);
        ctx.stroke();
        ctx.setLineDash([]);
        ctx.fillStyle = dusman.tanim.renk;
        for (var i = 0; i < 4; i++) {
          var a = Math.PI / 2 * i;
          ctx.beginPath();
          ctx.moveTo(Math.cos(a) * r * 1.44, Math.sin(a) * r * 1.44);
          ctx.lineTo(Math.cos(a + 0.22) * r * 1.2, Math.sin(a + 0.22) * r * 1.2);
          ctx.lineTo(Math.cos(a - 0.22) * r * 1.2, Math.sin(a - 0.22) * r * 1.2);
          ctx.closePath();
          ctx.fill();
        }
        ctx.restore();

        // İç çekirdek: nabız atan ikinci katman.
        var nabiz = BS.kalite.azaltilmisHareket
          ? 1 : 1 + Math.sin(cizici.zaman * 3.4) * 0.05;
        ctx.save();
        ctx.translate(x, y);
        ctx.rotate(-donme * 0.6);
        ctx.fillStyle = "rgba(8, 12, 22, 0.85)";
        dusmanYoluOlustur(dusman.tanim.sekil, r * 0.66 * nabiz);
        ctx.fill();
        ctx.strokeStyle = dusman.tanim.renk;
        ctx.lineWidth = 2;
        dusmanYoluOlustur(dusman.tanim.sekil, r * 0.66 * nabiz);
        ctx.stroke();
        ctx.restore();
      }

      function dusmanCizTek(dusman) {
        var yuksekKalite = BS.kalite.seviye === "yuksek";
        var performans = BS.kalite.seviye === "performans";

        var x = cizici.kenarX + (dusman.x + 0.5) * cizici.hucre;
        var y = cizici.kenarY + (dusman.y + 0.5) * cizici.hucre;
        var r = cizici.hucre * (dusman.patronMu ? 0.62 : 0.3) *
          derinlikOlcek(dusman.y);

        // Yön: bir önceki karedeki konumdan türetilir (çizim durumu
        // düşman nesnesinde saklanır; sim alanlarına dokunulmaz).
        var vx = x - (dusman._cx != null ? dusman._cx : x);
        var vy = y - (dusman._cy != null ? dusman._cy : y);
        if (vx * vx + vy * vy > 0.01) {
          dusman._aci = Math.atan2(vy, vx);
        }
        dusman._cx = x; dusman._cy = y;
        var aci = dusman._aci || 0;

        // Yürüyüş salınımı: gövde hafifçe iner/kalkar (kimlik no ile faz).
        var bob = (performans || BS.kalite.azaltilmisHareket || dusman.patronMu)
          ? 0 : Math.sin(cizici.zaman * 6 + dusman.no * 1.7) * r * 0.08;

        ctx.globalAlpha = dusman.gizliMi ? 0.22 : 1;

        // Zemin gölgesi: derinlik hissi (ucuz elips).
        if (!performans && !dusman.gizliMi) {
          ctx.fillStyle = "rgba(0,0,0,0.3)";
          ctx.beginPath();
          ctx.ellipse(x, y + r * 0.82, r * 0.7, r * 0.24, 0, 0, Math.PI * 2);
          ctx.fill();
        }

        if (yuksekKalite && !dusman.gizliMi) {
          ctx.shadowColor = dusman.tanim.renk;
          ctx.shadowBlur = dusman.patronMu ? 18 : 8;
        }

        // Operatör sprite'ı varsa gövde olarak kullanılır (dusmanlar/<id>.svg).
        var sprite = BS.varliklar
          ? BS.varliklar.dusmanGorsel(dusman.tanimId) : null;

        if (dusman.patronMu) {
          if (sprite) {
            ctx.save();
            ctx.translate(x, y);
            ctx.rotate(aci);
            ctx.drawImage(sprite, -r, -r, r * 2, r * 2);
            ctx.restore();
            ctx.shadowBlur = 0;
          } else {
            ctx.fillStyle = dusman.tanim.renk;
            ctx.save();
            ctx.translate(x, y);
            dusmanYoluOlustur(dusman.tanim.sekil, r);
            ctx.fill();
            ctx.restore();
            ctx.shadowBlur = 0;
          }
          patronCiz(dusman, x, y, r);
        } else if (sprite) {
          ctx.save();
          ctx.translate(x, y + bob);
          ctx.rotate(aci);
          ctx.drawImage(sprite, -r, -r, r * 2, r * 2);
          ctx.restore();
          ctx.shadowBlur = 0;
        } else {
          ctx.save();
          ctx.translate(x, y + bob);
          ctx.rotate(aci);
          ctx.fillStyle = dusman.tanim.renk;
          dusmanYoluOlustur(dusman.tanim.sekil, r);
          ctx.fill();
          ctx.shadowBlur = 0;
          // Gövde derinliği: koyu iç çekirdek + üst kenar ışığı + parlak
          // cam kubbe + ön vizör gözü + şekle özgü aksan (motor/perçin).
          if (!performans) {
            ctx.fillStyle = "rgba(0,0,0,0.32)";
            dusmanYoluOlustur(dusman.tanim.sekil, r * 0.55);
            ctx.fill();

            var kubbe = ctx.createRadialGradient(
              -r * 0.35, -r * 0.4, 0, 0, 0, r * 1.1
            );
            kubbe.addColorStop(0, "rgba(255,255,255,0.34)");
            kubbe.addColorStop(0.45, "rgba(255,255,255,0.06)");
            kubbe.addColorStop(1, "rgba(0,0,0,0.28)");
            ctx.fillStyle = kubbe;
            dusmanYoluOlustur(dusman.tanim.sekil, r);
            ctx.fill();

            ctx.strokeStyle = "rgba(255,255,255,0.35)";
            ctx.lineWidth = 1.2;
            dusmanYoluOlustur(dusman.tanim.sekil, r * 0.92);
            ctx.stroke();

            // Ön vizör gözü: yön hissi ve "yaratık" kimliği.
            ctx.fillStyle = "rgba(255,255,255,0.85)";
            ctx.beginPath();
            ctx.ellipse(r * 0.42, 0, r * 0.2, r * 0.12, 0, 0, Math.PI * 2);
            ctx.fill();
            ctx.fillStyle = "rgba(10,14,24,0.9)";
            ctx.beginPath();
            ctx.arc(r * 0.48, 0, r * 0.06, 0, Math.PI * 2);
            ctx.fill();

            // Şekle özgü aksan: ok/üçgen arkada motor ışıkları, karede perçinler.
            if (dusman.tanim.sekil === "ucgen" || dusman.tanim.sekil === "ok") {
              ctx.fillStyle = "rgba(255,255,255,0.5)";
              ctx.beginPath();
              ctx.arc(-r * 0.5, -r * 0.34, r * 0.09, 0, Math.PI * 2);
              ctx.arc(-r * 0.5, r * 0.34, r * 0.09, 0, Math.PI * 2);
              ctx.fill();
            } else if (dusman.tanim.sekil === "kare" || dusman.tanim.sekil === "yigin") {
              ctx.fillStyle = "rgba(255,255,255,0.4)";
              [[-1, -1], [1, -1], [-1, 1], [1, 1]].forEach(function(k) {
                ctx.beginPath();
                ctx.arc(k[0] * r * 0.52, k[1] * r * 0.52, r * 0.07, 0, Math.PI * 2);
                ctx.fill();
              });
            }
          }
          ctx.restore();
        }
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

        // Can çubuğu: yalnızca hasar almış tehditlerde (patron her zaman).
        var oran = BS.yardimci.kirp(dusman.can / dusman.maxCan, 0, 1);
        if (oran < 1 || dusman.patronMu) {
          var cw = r * 2;
          var ch = dusman.patronMu ? 6 : 4;
          var cy = y - r - (dusman.patronMu ? 16 : 12);
          ctx.fillStyle = "rgba(0,0,0,0.6)";
          ctx.fillRect(x - cw / 2 - 1, cy - 1, cw + 2, ch + 2);
          ctx.fillStyle = oran > 0.5 ? "#7ae582"
            : (oran > 0.25 ? "#ffd166" : "#e63946");
          ctx.fillRect(x - cw / 2, cy, cw * oran, ch);
          if (dusman.patronMu) {
            // Patron çubuğu çeyrek bölmeli: kalan güç okunaklı.
            ctx.strokeStyle = "rgba(0,0,0,0.5)";
            ctx.lineWidth = 1;
            for (var bq = 1; bq < 4; bq++) {
              ctx.beginPath();
              ctx.moveTo(x - cw / 2 + cw * bq / 4, cy);
              ctx.lineTo(x - cw / 2 + cw * bq / 4, cy + ch);
              ctx.stroke();
            }
          }
        }

        ctx.globalAlpha = 1;
      }

      function kahramanCizTek(durum, arayuz, id) {
        var kahraman = durum.kahramanlar[id];
        var x = cizici.kenarX + (kahraman.x + 0.5) * cizici.hucre;
        var y = cizici.kenarY + (kahraman.y + 0.5) * cizici.hucre;
        var r = cizici.hucre * 0.42 * derinlikOlcek(kahraman.y);
        var portre = BS.cizim.portreAl(id);
        var aksan = portre && portre.persona ? portre.persona.aksan : "#4cc9f0";

        // Zemin gölgesi (2.5D taban).
        ctx.fillStyle = "rgba(0,0,0,0.32)";
        ctx.beginPath();
        ctx.ellipse(x, y + r * 0.9, r * 0.85, r * 0.28, 0, 0, Math.PI * 2);
        ctx.fill();

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
      }

      // Seçili kahraman/kule menzil çemberleri varlıkların ALTINA çizilir.
      function menzilCemberleriCiz(durum, arayuz) {
        if (!arayuz) return;
        if (arayuz.seciliKahraman) {
          var kahraman = durum.kahramanlar[arayuz.seciliKahraman];
          if (kahraman && kahraman.yerlesik) {
            var ist = BS.denge.kahramanIstatistik(arayuz.seciliKahraman,
                                                  kahraman.seviye);
            var portre = BS.cizim.portreAl(arayuz.seciliKahraman);
            var aksan = portre && portre.persona
              ? portre.persona.aksan : "#4cc9f0";
            ctx.fillStyle = aksan + "14";
            ctx.strokeStyle = aksan + "66";
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            ctx.arc(hucreX(kahraman.x), hucreY(kahraman.y),
                    ist.menzil * cizici.hucre, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
          }
        }
        if (arayuz.seciliKule && durum.kuleler) {
          for (var i = 0; i < durum.kuleler.length; i++) {
            var kule = durum.kuleler[i];
            if (kule.no !== arayuz.seciliKule) continue;
            var kist = BS.denge.kuleIstatistik(kule.tip, kule.seviye);
            ctx.fillStyle = "rgba(142, 202, 230, 0.08)";
            ctx.strokeStyle = "rgba(142, 202, 230, 0.4)";
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            ctx.arc(hucreX(kule.x), hucreY(kule.y),
                    kist.menzil * cizici.hucre, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
            break;
          }
        }
      }

      // 2.5D derinlik sırası: tüm sahne varlıkları Y'ye göre sıralanır;
      // alttaki varlık üstte çizilir ve önündekini doğal biçimde örter.
      function varliklariDerinlikSirasiylaCiz(durum, arayuz) {
        var liste = [];
        durum.dusmanlar.forEach(function(dusman) {
          liste.push({ y: dusman.y, tur: "dusman", ref: dusman });
        });
        (durum.kuleler || []).forEach(function(kule) {
          liste.push({ y: kule.y, tur: "kule", ref: kule });
        });
        Object.keys(durum.kahramanlar).forEach(function(id) {
          if (durum.kahramanlar[id].yerlesik) {
            liste.push({ y: durum.kahramanlar[id].y, tur: "kahraman", ref: id });
          }
        });
        liste.sort(function(a, b) { return a.y - b.y; });

        liste.forEach(function(oge) {
          if (oge.tur === "dusman") {
            dusmanCizTek(oge.ref);
          } else if (oge.tur === "kule") {
            BS.varliklar.kuleCiz(ctx, cizici, oge.ref, {
              secili: arayuz && arayuz.seciliKule === oge.ref.no
            });
          } else {
            kahramanCizTek(durum, arayuz, oge.ref);
          }
        });
      }

      function mermileriCiz(durum) {
        var performans = BS.kalite.seviye === "performans";
        durum.mermiler.forEach(function(mermi) {
          var x = cizici.kenarX + (mermi.x + 0.5) * cizici.hucre;
          var y = cizici.kenarY + (mermi.y + 0.5) * cizici.hucre;
          var renkler = {
            cozum: "#b8b8ff", sinyal: "#8ecae6", rota: "#4cc9f0",
            dogrulama: "#f77f00", rehber: "#ffc8dd",
            gozcu: "#cde7ff", topcu: "#f4a261", kripto: "#b088f9"
          };
          var renk = renkler[mermi.tip] || "#fff";

          // İz: bir önceki kare konumundan mevcut konuma ışıklı kuyruk.
          if (!performans && mermi._cx != null) {
            var izGrd = ctx.createLinearGradient(mermi._cx, mermi._cy, x, y);
            izGrd.addColorStop(0, renk + "00");
            izGrd.addColorStop(1, renk + "aa");
            ctx.strokeStyle = izGrd;
            ctx.lineWidth = (mermi.tip === "dogrulama" || mermi.tip === "topcu")
              ? 3 : 2;
            ctx.lineCap = "round";
            ctx.beginPath();
            ctx.moveTo(mermi._cx, mermi._cy);
            ctx.lineTo(x, y);
            ctx.stroke();
          }
          mermi._cx = x; mermi._cy = y;

          ctx.fillStyle = renk;
          ctx.beginPath();
          ctx.arc(x, y,
                  (mermi.tip === "dogrulama" || mermi.tip === "topcu") ? 4 : 3,
                  0, Math.PI * 2);
          ctx.fill();
          if (!performans) {
            ctx.fillStyle = "#ffffff";
            ctx.globalAlpha = 0.85;
            ctx.beginPath();
            ctx.arc(x, y, 1.4, 0, Math.PI * 2);
            ctx.fill();
            ctx.globalAlpha = 1;
          }
          if (BS.kalite.seviye === "yuksek") {
            ctx.fillStyle = renk;
            ctx.globalAlpha = 0.3;
            ctx.beginPath();
            ctx.arc(x, y, 7, 0, Math.PI * 2);
            ctx.fill();
            ctx.globalAlpha = 1;
          }
        });
      }

      function yerlesimOnizlemeCiz(durum, arayuz) {
        if (!arayuz || !arayuz.hucre) return;
        var yerlesimTanim = null;
        if (arayuz.yerlesimKahraman) {
          yerlesimTanim = BS.denge.kahramanAl(arayuz.yerlesimKahraman);
        } else if (arayuz.yerlesimKule) {
          yerlesimTanim = BS.denge.kuleAl(arayuz.yerlesimKule);
        }
        if (!yerlesimTanim) return;

        var hx = arayuz.hucre.x, hy = arayuz.hucre.y;
        var uygun = arayuz.hucreDurumu === "insa";
        var x = cizici.kenarX + (hx + 0.5) * cizici.hucre;
        var y = cizici.kenarY + (hy + 0.5) * cizici.hucre;

        ctx.fillStyle = uygun ? "rgba(122, 229, 130, 0.25)" : "rgba(230, 57, 70, 0.3)";
        ctx.fillRect(cizici.kenarX + hx * cizici.hucre,
                     cizici.kenarY + hy * cizici.hucre,
                     cizici.hucre, cizici.hucre);

        if (uygun) {
          ctx.strokeStyle = "rgba(255,255,255,0.5)";
          ctx.setLineDash([6, 6]);
          ctx.lineWidth = 1.5;
          ctx.beginPath();
          ctx.arc(x, y, yerlesimTanim.menzil * cizici.hucre, 0, Math.PI * 2);
          ctx.stroke();
          ctx.setLineDash([]);
        }
      }

      cizici.ciz = function(durum, arayuz, dt) {
        cizici.zaman += dt || 0.016;
        ctx.clearRect(0, 0, tuval.width, tuval.height);
        ctx.drawImage(arka, 0, 0);
        if (BS.varliklar) BS.varliklar.dekorCiz(ctx, cizici, dekorPlan);
        cekirdekCiz(durum);
        menzilCemberleriCiz(durum, arayuz);
        varliklariDerinlikSirasiylaCiz(durum, arayuz);
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
