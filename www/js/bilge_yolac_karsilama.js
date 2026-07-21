// www/js/bilge_yolac_karsilama.js
// Bilge Yolaç "Çalışma Alanı" retro karşılama sahnesi: 8-bit piksel persona
// (www/js/claude_code_pixel_chars.js verisinden) ekran boyunca canlanır ve
// Claude Code CLI girişini andıran esprili bir terminal kutusu yazı yazar.
// Bu DEKORATİF bir sahnedir; oyun değildir: girdi yakalamaz, ses çalmaz,
// yalnızca karşılama görünürken (cc-welcome-active + claude_code sekmesi +
// görünür pencere) çalışır ve ayrılınca döngüyü tamamen durdurur.
// Azaltılmış hareket tercihinde tek kare + tam metin gösterilir.

(function() {
  "use strict";

  var WELCOME_ID = "claude_code_module-welcome_screen";
  var SAHNE_ID = "claude_code_module-karsilama_sahne";
  var IPUCU_ID = "claude_code_module-cli_ipucu";

  var IPUCLARI = [
    "İpucu: Klasörünü seç; Bilge Yolaç dosyaları okur, bahaneleri okumaz.",
    "İpucu: 'Çıktıyı Temizle' geçmişi siler; dünkü toplantıyı silemez.",
    "İpucu: Uzun komut yazmak serbest; Bilge Yolaç kahve molası istemez.",
    "İpucu: Can'a göre her hata bir 'doğrulama fırsatıdır'. Cidden.",
    "İpucu: Deniz önce yol haritası ister; sonra kod yazdırır.",
    "İpucu: Selin bozuk dosyayı görünce üzülmez, onarır.",
    "İpucu: İpek karmaşık işleri adım adım anlatır; panik opsiyoneldir.",
    "İpucu: Emre özet sever: 'Çalıştı mı? Evet. Sonraki adım?'",
    "İpucu: Türkçe dosya adları desteklenir; şifreli el yazısı henüz değil.",
    "İpucu: Ajan düşünürken piksel karakter de düşünüyormuş gibi yapar.",
    "İpucu: 'Durdur' düğmesi ajanı durdurur; ilhamı durduramaz.",
    "İpucu: Büyük dosya mı? Önce özet iste, sonra derin dalış yap.",
    "İpucu: Bilge Savunması'nda çekirdeği korumak buradaki koddan kolay.",
    "İpucu: Her şey yolundaysa bu satır sadece süs. Merhaba!"
  ];

  var BALONLAR = [
    "Merhaba!", "Klasör seçelim mi?", "Komut bekliyorum...",
    "Bugün ne inşa ediyoruz?", "Derin nefes, temiz kod.", "Hazırım!"
  ];

  var durum = {
    calisiyor: false,
    rafId: null,
    canvas: null,
    ctx: null,
    gozlemci: null,
    yazmaZamanlayici: null,
    ipucuSirasi: 0,
    personaSirasi: 0,
    kare: 0,
    x: 40,
    yon: 1,
    eylem: "yuru",
    eylemKalan: 4,
    balon: null,
    balonKalan: 0,
    sonZaman: 0
  };

  function azaltilmisHareket() {
    try {
      return window.matchMedia &&
        window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    } catch (hata) { return false; }
  }

  function personaListesi() {
    var veri = window.MergenClaudeCodePixelCharsMini || {};
    return ["emre", "selin", "deniz", "can", "ipek"].filter(function(id) {
      return veri[id] && veri[id].frames && veri[id].frames.length;
    });
  }

  function aktifPersona() {
    var liste = personaListesi();
    if (!liste.length) return null;
    return (window.MergenClaudeCodePixelCharsMini)[
      liste[durum.personaSirasi % liste.length]
    ];
  }

  // ── Sahne kurulumu ──────────────────────────────────────────────────────────
  function sahneKur() {
    var sahne = document.getElementById(SAHNE_ID);
    if (!sahne || durum.canvas) return !!durum.canvas;

    var canvas = document.createElement("canvas");
    canvas.className = "cc-karsilama-tuvali";
    canvas.setAttribute("aria-hidden", "true");
    canvas.title = "Tıkla: başka bir uzman sahneye gelsin";
    sahne.appendChild(canvas);
    durum.canvas = canvas;
    durum.ctx = canvas.getContext("2d");

    boyutlandir();

    // Tıklama: küçük bir sürpriz zıplama + sıradaki persona (zengin katalog).
    canvas.addEventListener("click", function() {
      durum.personaSirasi += 1;
      eylemAyarla("zipla", 1.2);
      balonGoster("Hop!");
    });

    return true;
  }

  function boyutlandir() {
    var sahne = document.getElementById(SAHNE_ID);
    if (!sahne || !durum.canvas) return;
    var gen = Math.max(280, sahne.clientWidth || 600);
    durum.canvas.width = gen;
    durum.canvas.height = 128;
    durum.canvas.style.width = "100%";
    durum.canvas.style.height = "128px";
    if (durum.ctx) durum.ctx.imageSmoothingEnabled = false;
  }

  // ── Eylem/animasyon kataloğu ────────────────────────────────────────────────
  function eylemAyarla(ad, sure) {
    durum.eylem = ad;
    durum.eylemKalan = sure;
  }

  function rasgeleEylem() {
    var aday = [
      ["yuru", 4 + Math.random() * 3],
      ["yuru", 4 + Math.random() * 3],
      ["kos", 2 + Math.random() * 2],
      ["dur", 1.6 + Math.random()],
      ["dusun", 2.2 + Math.random()],
      ["selamla", 1.6],
      ["zipla", 1.1],
      ["uyu", 3 + Math.random() * 2]
    ];
    var secim = aday[Math.floor(Math.random() * aday.length)];
    eylemAyarla(secim[0], secim[1]);
    if (secim[0] === "selamla") balonGoster(BALONLAR[Math.floor(Math.random() * BALONLAR.length)]);
    if (secim[0] === "uyu") balonGoster("Z z z...");
  }

  function balonGoster(metin) {
    durum.balon = metin;
    durum.balonKalan = 2.4;
  }

  // ── Piksel karakter çizimi ──────────────────────────────────────────────────
  function karakterCiz(dt) {
    var ctx = durum.ctx;
    var canvas = durum.canvas;
    var veri = aktifPersona();
    if (!ctx || !canvas || !veri) return;

    ctx.clearRect(0, 0, canvas.width, canvas.height);

    var taban = canvas.height - 14;

    // Zemin çizgisi + piksel dekor (deterministik yerleşim).
    ctx.fillStyle = "rgba(122, 229, 130, 0.35)";
    for (var zx = 0; zx < canvas.width; zx += 8) {
      ctx.fillRect(zx, taban + 8, 5, 2);
    }
    ctx.fillStyle = "rgba(76, 201, 240, 0.25)";
    for (var dx = 20; dx < canvas.width; dx += 130) {
      ctx.fillRect(dx, taban - 2, 6, 6);
      ctx.fillRect(dx + 60, taban - 6, 4, 10);
    }

    // Eylem süresi ve hareket.
    durum.eylemKalan -= dt;
    if (durum.eylemKalan <= 0) rasgeleEylem();

    var hiz = 0;
    var kareHizi = 0.1;
    if (durum.eylem === "yuru") { hiz = 26; }
    else if (durum.eylem === "kos") { hiz = 62; kareHizi = 0.2; }

    durum.x += hiz * durum.yon * dt;
    var kenar = 30;
    if (durum.x > canvas.width - kenar) { durum.x = canvas.width - kenar; durum.yon = -1; }
    if (durum.x < kenar) { durum.x = kenar; durum.yon = 1; }

    durum.kare += dt * 60;

    // Kare seçimi: yürüyüş/idle 0-1, düşünme 2-3 arası döner, selamlama 4.
    var kareSayisi = veri.frames.length;
    var kareIndex = 0;
    if (durum.eylem === "yuru" || durum.eylem === "kos") {
      kareIndex = (Math.floor(durum.kare / 16) % 2);   // idle <-> nefes
    } else if (durum.eylem === "dusun" && kareSayisi > 3) {
      kareIndex = 2 + (Math.floor(durum.kare / 24) % 2);
    } else if (durum.eylem === "selamla") {
      kareIndex = (Math.floor(durum.kare / 14) % 2) === 0 ? (kareSayisi - 1) : 0;
    } else if (durum.eylem === "dur" || durum.eylem === "uyu") {
      kareIndex = 1;
    }
    kareIndex = Math.min(kareIndex, kareSayisi - 1);

    // Dikey ofset: yürüyüş sallanması, zıplama parabolü, uyku çökmesi.
    var dikey = 0;
    var olcekY = 1;
    if (durum.eylem === "yuru" || durum.eylem === "kos") {
      dikey = Math.abs(Math.sin(durum.kare * (durum.eylem === "kos" ? 0.35 : 0.2))) * -4;
    } else if (durum.eylem === "zipla") {
      var t = 1 - Math.max(0, durum.eylemKalan / 1.2);
      dikey = -Math.sin(t * Math.PI) * 26;
      olcekY = t < 0.12 ? 0.82 : 1;
    } else if (durum.eylem === "dur") {
      olcekY = 1 + Math.sin(durum.kare * 0.08) * 0.02;
    } else if (durum.eylem === "uyu") {
      olcekY = 0.94;
    }

    var pikselBoyu = 4;
    var genislik = 16 * pikselBoyu;

    ctx.save();
    ctx.translate(durum.x, taban + dikey);
    ctx.scale(durum.yon, olcekY);
    ctx.globalAlpha = durum.eylem === "uyu" ? 0.75 : 1;

    // Genişletilmiş palet + açık/koyu temaya duyarlı kontur ortak yardımcıdadır.
    if (window.MergenPixelSprite) {
      window.MergenPixelSprite.ciz(ctx, veri, kareIndex, {
        pixelSize: pikselBoyu, offsetX: -8 * pikselBoyu, offsetY: -16 * pikselBoyu
      });
    } else {
      var pikseller = veri.frames[kareIndex];
      for (var y = 0; y < pikseller.length; y++) {
        for (var x = 0; x < pikseller[y].length; x++) {
          var deger = pikseller[y][x];
          if (deger === 0) continue;
          if (deger === 1) ctx.fillStyle = veri.color;
          else if (deger === 2) ctx.fillStyle = veri.darkColor;
          else ctx.fillStyle = veri.lightColor || veri.color;
          ctx.fillRect((x - 8) * pikselBoyu, (y - 16) * pikselBoyu,
                       pikselBoyu - 1, pikselBoyu - 1);
        }
      }
    }
    ctx.restore();

    // Konuşma balonu (8-bit çerçeveli).
    if (durum.balon && durum.balonKalan > 0) {
      durum.balonKalan -= dt;
      ctx.font = "12px 'Courier New', monospace";
      var metinGen = ctx.measureText(durum.balon).width;
      var bx = Math.min(canvas.width - metinGen - 26,
                        Math.max(6, durum.x - metinGen / 2));
      var by = taban - genislik - 26;
      ctx.fillStyle = "rgba(10, 15, 28, 0.92)";
      ctx.fillRect(bx, by, metinGen + 16, 20);
      ctx.strokeStyle = "#7ae582";
      ctx.lineWidth = 2;
      ctx.strokeRect(bx, by, metinGen + 16, 20);
      ctx.fillStyle = "#e8ecf4";
      ctx.fillText(durum.balon, bx + 8, by + 14);
    } else {
      durum.balon = null;
    }
  }

  // ── CLI ipucu daktilosu ─────────────────────────────────────────────────────
  function ipucuYaz() {
    var hedef = document.getElementById(IPUCU_ID);
    if (!hedef) return;
    if (durum.yazmaZamanlayici) {
      clearInterval(durum.yazmaZamanlayici);
      durum.yazmaZamanlayici = null;
    }

    var metin = IPUCLARI[durum.ipucuSirasi % IPUCLARI.length];
    durum.ipucuSirasi += 1;

    if (azaltilmisHareket()) {
      hedef.textContent = metin;
      return;
    }

    var i = 0;
    hedef.textContent = "";
    durum.yazmaZamanlayici = setInterval(function() {
      i += 1;
      hedef.textContent = metin.slice(0, i);
      if (i >= metin.length) {
        clearInterval(durum.yazmaZamanlayici);
        durum.yazmaZamanlayici = null;
      }
    }, 28);
  }

  // ── Yaşam döngüsü ───────────────────────────────────────────────────────────
  function gorunurMu() {
    if (document.hidden) return false;
    var welcome = document.getElementById(WELCOME_ID);
    if (!welcome || !welcome.classList.contains("cc-welcome-active")) return false;
    return welcome.offsetWidth > 0 && welcome.offsetHeight > 0;
  }

  function baslat() {
    if (durum.calisiyor || !gorunurMu()) return;
    if (!sahneKur()) return;
    if (!aktifPersona()) return;

    durum.calisiyor = true;
    boyutlandir();
    ipucuYaz();

    if (azaltilmisHareket()) {
      // Tek statik kare: döngü yok, hareket yok.
      eylemAyarla("dur", 9999);
      karakterCiz(0);
      durum.calisiyor = false;
      return;
    }

    durum.sonZaman = performance.now();
    if (!durum.ipucuDongusu) {
      durum.ipucuDongusu = setInterval(function() {
        if (durum.calisiyor) ipucuYaz();
      }, 9000);
    }

    function kare(simdi) {
      if (!durum.calisiyor) return;
      if (!gorunurMu()) { durdur(); return; }
      durum.rafId = requestAnimationFrame(kare);
      var dt = Math.min(0.05, (simdi - durum.sonZaman) / 1000);
      durum.sonZaman = simdi;
      karakterCiz(dt);
    }
    durum.rafId = requestAnimationFrame(kare);
  }

  function durdur() {
    durum.calisiyor = false;
    if (durum.rafId) {
      cancelAnimationFrame(durum.rafId);
      durum.rafId = null;
    }
    if (durum.ipucuDongusu) {
      clearInterval(durum.ipucuDongusu);
      durum.ipucuDongusu = null;
    }
    if (durum.yazmaZamanlayici) {
      clearInterval(durum.yazmaZamanlayici);
      durum.yazmaZamanlayici = null;
    }
  }

  function gorunurlukDegisti() {
    if (gorunurMu()) baslat(); else durdur();
  }

  // Karşılama sınıfı değişimlerini izle (mesaj gelince sahne durur; çıktı
  // temizlenince geri gelir). Gözlemci yalnızca bir kez kurulur.
  function gozlemciKur() {
    var welcome = document.getElementById(WELCOME_ID);
    if (!welcome || durum.gozlemci) return;
    durum.gozlemci = new MutationObserver(gorunurlukDegisti);
    durum.gozlemci.observe(welcome, {
      attributes: true, attributeFilter: ["class"]
    });
  }

  if (window.jQuery) {
    window.jQuery(document).on("shiny:connected", function() {
      setTimeout(function() { gozlemciKur(); gorunurlukDegisti(); }, 600);
    });
    window.jQuery(document).on("shiny:inputchanged", function(e) {
      if (e.name !== "tabs") return;
      setTimeout(function() { gozlemciKur(); gorunurlukDegisti(); }, 350);
    });
  }

  document.addEventListener("visibilitychange", gorunurlukDegisti);
  window.addEventListener("resize", function() {
    if (durum.calisiyor) boyutlandir();
  });

  // Küçük, adlandırılmış kontrol yüzeyi (test/teşhis için; oyun API'si değil).
  window.MergenBilgeYolacKarsilama = {
    baslat: baslat,
    durdur: durdur,
    calisiyorMu: function() { return durum.calisiyor; }
  };
})();
