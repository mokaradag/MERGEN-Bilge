// =============================================================================
// Dosya Yolu: www/js/bilge_yolac_varliklar.js
// Açıklama: Bilge Yolaç için çevrimdışı yerel varlık kayıt sistemi. Dünya
//           katmanları, set parçası çizimi, resim önbelleği ve eksik varlık
//           durumunda kullanılacak piksel uyumlu geri dönüş çizimleri içerir.
// =============================================================================

(function() {
  "use strict";

  var BY = window.BilgeYolac;
  if (!BY) return;

  var tabanKlasor = "assets/bilge_yolac";
  var resimOnbellek = Object.create(null);
  var yuklemeKuyrugu = [];

  function resimDurumuAl(yol) {
    if (!yol) return null;
    if (resimOnbellek[yol]) return resimOnbellek[yol];

    var kayit = {
      yol: yol,
      durum: "bekliyor",
      resim: null
    };

    var img = new Image();
    kayit.resim = img;
    kayit.durum = "yukleniyor";

    img.onload = function() {
      kayit.durum = "hazir";
    };

    img.onerror = function() {
      kayit.durum = "hata";
    };

    img.src = yol;
    resimOnbellek[yol] = kayit;
    yuklemeKuyrugu.push(kayit);
    return kayit;
  }

  function katmanYolu(dunyaId, katman, dosya) {
    return tabanKlasor + "/worlds/" + dunyaId + "/" + katman + "/" + dosya;
  }

  function dusmanYolu(tip, dosya) {
    return tabanKlasor + "/enemies/" + tip + "/" + dosya;
  }

  function bossYolu(dosya) {
    return tabanKlasor + "/enemies/bosses/" + dosya;
  }

  function mermiYolu(grup, dosya) {
    return tabanKlasor + "/projectiles/" + grup + "/" + dosya;
  }

  var DUNYA_PAKETLERI = {
    emre: {
      isim: "Emre Dünyası",
      arkaKatmanlar: [
        { dosya: "backgrounds/plateau_far_01.png", hiz: 0.08, saydamlik: 0.9, y: 0.18, olcek: 1.0, yedekTur: "plateau" },
        { dosya: "backgrounds/ridge_far_01.png", hiz: 0.14, saydamlik: 0.75, y: 0.28, olcek: 1.0, yedekTur: "ridge" }
      ],
      ortaKatmanlar: [
        { dosya: "midground/temple_frontier_01.png", hiz: 0.28, saydamlik: 0.95, y: 0.48, olcek: 1.0, yedekTur: "temple" },
        { dosya: "midground/radar_outpost_01.png", hiz: 0.34, saydamlik: 0.92, y: 0.52, olcek: 1.0, yedekTur: "radar" }
      ],
      onKatmanlar: [
        { dosya: "foreground/steppe_grass_01.png", hiz: 0.75, saydamlik: 0.95, y: 0.78, olcek: 1.0, yedekTur: "grass" },
        { dosya: "foreground/signal_pole_01.png", hiz: 0.88, saydamlik: 0.92, y: 0.72, olcek: 1.0, yedekTur: "pole" }
      ],
      kaplama: "steppe"
    },
    selin: {
      isim: "Selin Dünyası",
      arkaKatmanlar: [
        { dosya: "backgrounds/celestial_spires_01.png", hiz: 0.07, saydamlik: 0.88, y: 0.16, olcek: 1.0, yedekTur: "spire" },
        { dosya: "backgrounds/fortress_skyline_01.png", hiz: 0.14, saydamlik: 0.80, y: 0.24, olcek: 1.0, yedekTur: "fortress" }
      ],
      ortaKatmanlar: [
        { dosya: "midground/luminous_tower_01.png", hiz: 0.30, saydamlik: 0.95, y: 0.40, olcek: 1.0, yedekTur: "tower" },
        { dosya: "midground/energy_fort_01.png", hiz: 0.38, saydamlik: 0.94, y: 0.48, olcek: 1.0, yedekTur: "energy_gate" }
      ],
      onKatmanlar: [
        { dosya: "foreground/light_crystal_01.png", hiz: 0.78, saydamlik: 0.95, y: 0.76, olcek: 1.0, yedekTur: "crystal" },
        { dosya: "foreground/hover_relay_01.png", hiz: 0.90, saydamlik: 0.92, y: 0.68, olcek: 1.0, yedekTur: "relay" }
      ],
      kaplama: "light"
    },
    deniz: {
      isim: "Deniz Dünyası",
      arkaKatmanlar: [
        { dosya: "backgrounds/forest_canopy_01.png", hiz: 0.10, saydamlik: 0.88, y: 0.18, olcek: 1.0, yedekTur: "canopy" },
        { dosya: "backgrounds/runic_hills_01.png", hiz: 0.16, saydamlik: 0.76, y: 0.28, olcek: 1.0, yedekTur: "runic_hills" }
      ],
      ortaKatmanlar: [
        { dosya: "midground/sacred_tree_01.png", hiz: 0.30, saydamlik: 0.94, y: 0.42, olcek: 1.0, yedekTur: "sacred_tree" },
        { dosya: "midground/runic_ruin_01.png", hiz: 0.38, saydamlik: 0.92, y: 0.50, olcek: 1.0, yedekTur: "runic_ruin" }
      ],
      onKatmanlar: [
        { dosya: "foreground/fern_01.png", hiz: 0.78, saydamlik: 0.95, y: 0.78, olcek: 1.0, yedekTur: "fern" },
        { dosya: "foreground/rune_stone_01.png", hiz: 0.92, saydamlik: 0.92, y: 0.72, olcek: 1.0, yedekTur: "rune_stone" }
      ],
      kaplama: "forest"
    },
    can: {
      isim: "Can Dünyası",
      arkaKatmanlar: [
        { dosya: "backgrounds/abyss_spires_01.png", hiz: 0.08, saydamlik: 0.86, y: 0.18, olcek: 1.0, yedekTur: "abyss" },
        { dosya: "backgrounds/corrupted_depth_01.png", hiz: 0.14, saydamlik: 0.75, y: 0.26, olcek: 1.0, yedekTur: "corrupted_ridge" }
      ],
      ortaKatmanlar: [
        { dosya: "midground/glitch_temple_01.png", hiz: 0.30, saydamlik: 0.94, y: 0.44, olcek: 1.0, yedekTur: "glitch_temple" },
        { dosya: "midground/portal_rift_01.png", hiz: 0.38, saydamlik: 0.92, y: 0.48, olcek: 1.0, yedekTur: "rift" }
      ],
      onKatmanlar: [
        { dosya: "foreground/shadow_thorn_01.png", hiz: 0.80, saydamlik: 0.95, y: 0.78, olcek: 1.0, yedekTur: "thorn" },
        { dosya: "foreground/glitch_crystal_01.png", hiz: 0.92, saydamlik: 0.90, y: 0.72, olcek: 1.0, yedekTur: "glitch_crystal" }
      ],
      kaplama: "corruption"
    },
    ipek: {
      isim: "İpek Dünyası",
      arkaKatmanlar: [
        { dosya: "backgrounds/sanctuary_halo_01.png", hiz: 0.08, saydamlik: 0.88, y: 0.16, olcek: 1.0, yedekTur: "halo" },
        { dosya: "backgrounds/healing_garden_01.png", hiz: 0.16, saydamlik: 0.78, y: 0.26, olcek: 1.0, yedekTur: "garden_ridge" }
      ],
      ortaKatmanlar: [
        { dosya: "midground/sanctuary_gate_01.png", hiz: 0.30, saydamlik: 0.94, y: 0.42, olcek: 1.0, yedekTur: "sanctuary_gate" },
        { dosya: "midground/life_pool_01.png", hiz: 0.38, saydamlik: 0.92, y: 0.52, olcek: 1.0, yedekTur: "life_pool" }
      ],
      onKatmanlar: [
        { dosya: "foreground/luminous_flora_01.png", hiz: 0.80, saydamlik: 0.95, y: 0.78, olcek: 1.0, yedekTur: "flora" },
        { dosya: "foreground/healing_bloom_01.png", hiz: 0.92, saydamlik: 0.92, y: 0.72, olcek: 1.0, yedekTur: "bloom" }
      ],
      kaplama: "healing"
    }
  };

  var DUSMAN_GORUNUMLERI = {
    drone: {
      temelYol: dusmanYolu("drone", "drone_strip.png"),
      dunyaYollari: {
        emre: dusmanYolu("drone", "emre_drone_strip.png"),
        selin: dusmanYolu("drone", "selin_drone_strip.png"),
        deniz: dusmanYolu("drone", "deniz_drone_strip.png"),
        can: dusmanYolu("drone", "can_drone_strip.png"),
        ipek: dusmanYolu("drone", "ipek_drone_strip.png")
      }
    },
    jammer: {
      temelYol: dusmanYolu("jammer", "jammer_strip.png"),
      dunyaYollari: {}
    },
    sentinel: {
      temelYol: dusmanYolu("sentinel", "sentinel_strip.png"),
      dunyaYollari: {}
    },
    glitch: {
      temelYol: dusmanYolu("glitch", "glitch_strip.png"),
      dunyaYollari: {}
    }
  };

  // Boss'lar modern iş engellerini temsil eder; her dünya için bir engel.
  var BOSS_GORUNUMLERI = {
    emre: { yol: bossYolu("emre_boss_strip.png"), isim: "Karmaşa Çekirdeği" },
    selin: { yol: bossYolu("selin_boss_strip.png"), isim: "Belirsizlik Bloğu" },
    deniz: { yol: bossYolu("deniz_boss_strip.png"), isim: "Dağınık Plan Yığını" },
    can: { yol: bossYolu("can_boss_strip.png"), isim: "Gizli Varsayım" },
    ipek: { yol: bossYolu("ipek_boss_strip.png"), isim: "Bilgi Kalabalığı" }
  };

  var MERMI_GORUNUMLERI = {
    emre: { yol: mermiYolu("emre", "cozum_dalgasi_strip.png") },
    selin: { yol: mermiYolu("selin", "sinyal_taramasi_strip.png") },
    deniz: { yol: mermiYolu("deniz", "rota_projesi_strip.png") },
    can: { yol: mermiYolu("can", "dogrulama_isini_strip.png") },
    ipek: { yol: mermiYolu("ipek", "rehber_halkasi_strip.png") },
    drone: { yol: mermiYolu("enemies", "drone_bolt_strip.png") },
    jammer: { yol: mermiYolu("enemies", "jammer_pulse_strip.png") },
    sentinel: { yol: mermiYolu("enemies", "sentinel_lance_strip.png") },
    glitch: { yol: mermiYolu("enemies", "glitch_chaos_strip.png") },
    boss: { yol: mermiYolu("enemies", "boss_core_burst_strip.png") }
  };

  function mevcutDunyaIdAl() {
    if (BY.seviye && typeof BY.seviye.mevcutVeriAl === "function") {
      var veri = BY.seviye.mevcutVeriAl();
      if (veri && veri.dunyaId) return veri.dunyaId;
    }
    return "emre";
  }

  function dunyaPaketiAl(dunyaId) {
    return DUNYA_PAKETLERI[dunyaId] || DUNYA_PAKETLERI.emre;
  }

  function cizResim(ctx, kayit, x, y, g, h, saydamlik) {
    if (!kayit || !kayit.resim || kayit.durum !== "hazir") return false;
    ctx.save();
    if (typeof saydamlik === "number") ctx.globalAlpha = saydamlik;
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(kayit.resim, Math.floor(x), Math.floor(y), Math.floor(g), Math.floor(h));
    ctx.restore();
    return true;
  }

  function cizKatmanParcasi(ctx, katman, ekranX, tabanY, aksanRenk) {
    var kayit = resimDurumuAl(tabanKlasor + "/" + katman.dosya);
    var g = (katman.genislik || 192) * (katman.olcek || 1);
    var h = (katman.yukseklik || 96) * (katman.olcek || 1);
    var cizimY = tabanY - h;
    if (cizResim(ctx, kayit, ekranX, cizimY, g, h, katman.saydamlik)) return;
    cizYedekProp(ctx, katman.yedekTur, ekranX, cizimY, g, h, aksanRenk, katman.saydamlik);
  }

  function cizYedekProp(ctx, tur, x, y, g, h, aksanRenk, saydamlik) {
    saydamlik = typeof saydamlik === "number" ? saydamlik : 1;
    ctx.save();
    ctx.globalAlpha = saydamlik;
    ctx.imageSmoothingEnabled = false;

    var koyu = "rgba(0,0,0,0.35)";
    var acik = aksanRenk || "#9FD7FF";
    var ikincil = "rgba(255,255,255,0.16)";
    var govde = "rgba(27, 24, 38, 0.95)";
    var cam = "rgba(180, 230, 255, 0.35)";

    function blok(rx, ry, rg, rh, renk) {
      ctx.fillStyle = renk;
      ctx.fillRect(Math.floor(x + rx), Math.floor(y + ry), Math.floor(rg), Math.floor(rh));
    }

    function cizgi(x1, y1, x2, y2, renk, kalinlik) {
      ctx.strokeStyle = renk;
      ctx.lineWidth = kalinlik || 2;
      ctx.beginPath();
      ctx.moveTo(Math.floor(x + x1), Math.floor(y + y1));
      ctx.lineTo(Math.floor(x + x2), Math.floor(y + y2));
      ctx.stroke();
    }

    if (tur === "temple" || tur === "runic_ruin" || tur === "sanctuary_gate") {
      blok(g * 0.12, h * 0.22, g * 0.76, h * 0.12, koyu);
      blok(g * 0.20, h * 0.34, g * 0.10, h * 0.48, govde);
      blok(g * 0.45, h * 0.30, g * 0.10, h * 0.52, govde);
      blok(g * 0.70, h * 0.34, g * 0.10, h * 0.48, govde);
      blok(g * 0.10, h * 0.82, g * 0.80, h * 0.10, koyu);
      blok(g * 0.34, h * 0.48, g * 0.32, h * 0.34, cam);
      blok(g * 0.38, h * 0.52, g * 0.24, h * 0.05, acik);
    } else if (tur === "radar" || tur === "relay" || tur === "tower") {
      blok(g * 0.44, h * 0.22, g * 0.10, h * 0.62, govde);
      cizgi(g * 0.20, h * 0.42, g * 0.50, h * 0.24, acik, 3);
      cizgi(g * 0.80, h * 0.42, g * 0.50, h * 0.24, acik, 3);
      ctx.strokeStyle = acik;
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(x + g * 0.50, y + h * 0.22, g * 0.16, Math.PI * 1.1, Math.PI * 1.9);
      ctx.stroke();
      blok(g * 0.30, h * 0.84, g * 0.40, h * 0.08, koyu);
    } else if (tur === "sacred_tree") {
      blok(g * 0.44, h * 0.34, g * 0.12, h * 0.56, "rgba(71,48,27,0.95)");
      blok(g * 0.18, h * 0.12, g * 0.64, h * 0.20, acik);
      blok(g * 0.10, h * 0.28, g * 0.80, h * 0.18, "rgba(109, 227, 164, 0.65)");
      blok(g * 0.18, h * 0.46, g * 0.64, h * 0.12, "rgba(138, 241, 179, 0.55)");
    } else if (tur === "portal_rift" || tur === "rift") {
      ctx.strokeStyle = acik;
      ctx.lineWidth = 4;
      ctx.shadowColor = acik;
      ctx.shadowBlur = 10;
      ctx.beginPath();
      ctx.ellipse(x + g * 0.50, y + h * 0.50, g * 0.24, h * 0.36, 0, 0, Math.PI * 2);
      ctx.stroke();
      blok(g * 0.38, h * 0.22, g * 0.24, h * 0.56, "rgba(72, 0, 78, 0.35)");
      cizgi(g * 0.30, h * 0.24, g * 0.72, h * 0.70, "rgba(255,255,255,0.22)", 2);
      cizgi(g * 0.68, h * 0.20, g * 0.22, h * 0.66, "rgba(255,255,255,0.16)", 2);
    } else if (tur === "life_pool") {
      blok(g * 0.08, h * 0.60, g * 0.84, h * 0.18, koyu);
      ctx.fillStyle = "rgba(180, 250, 220, 0.55)";
      ctx.beginPath();
      ctx.ellipse(x + g * 0.50, y + h * 0.70, g * 0.28, h * 0.12, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = acik;
      ctx.lineWidth = 2;
      ctx.stroke();
    } else {
      blok(g * 0.10, h * 0.65, g * 0.80, h * 0.25, koyu);
      blok(g * 0.22, h * 0.28, g * 0.56, h * 0.40, govde);
      blok(g * 0.32, h * 0.40, g * 0.36, h * 0.08, acik);
    }

    ctx.restore();
  }

  function dunyaKatmaniCiz(ctx, katmanlar, oran, tabanY, aksanRenk) {
    var state = BY.state;
    if (!katmanlar || katmanlar.length === 0) return;

    for (var i = 0; i < katmanlar.length; i++) {
      var katman = katmanlar[i];
      var tekrarAralik = katman.tekrar || 280;
      var kayma = (state.kameraX * katman.hiz);
      var baslangic = -((kayma % tekrarAralik) + tekrarAralik);
      var g = (katman.genislik || 192) * (katman.olcek || 1);

      for (var x = baslangic; x < state.canvasGenislik + tekrarAralik; x += tekrarAralik) {
        cizKatmanParcasi(ctx, katman, x, tabanY, aksanRenk);
      }
    }
  }

  function setParcasiCiz(ctx, parca, aksanRenk) {
    var state = BY.state;
    var ekranX = parca.x - state.kameraX;
    var genislik = (parca.genislik || 160) * (parca.olcek || 1);
    var yukseklik = (parca.yukseklik || 96) * (parca.olcek || 1);
    var y = (typeof parca.y === "number") ? parca.y : Math.floor(state.canvasYukseklik * (parca.yOrani || 0.70));
    var cizimY = y - yukseklik;

    if (ekranX + genislik < -120 || ekranX > state.canvasGenislik + 120) return;

    if (parca.yol) {
      var kayit = resimDurumuAl(parca.yol);
      if (cizResim(ctx, kayit, ekranX, cizimY, genislik, yukseklik, parca.saydamlik)) return;
    }

    cizYedekProp(ctx, parca.tur, ekranX, cizimY, genislik, yukseklik, aksanRenk, parca.saydamlik);
  }

  function dusmanVarligiAl(tip, dunyaId) {
    var kayit = DUSMAN_GORUNUMLERI[tip];
    if (!kayit) return null;
    var yol = (kayit.dunyaYollari && kayit.dunyaYollari[dunyaId]) || kayit.temelYol;
    return {
      yol: yol,
      durum: resimDurumuAl(yol)
    };
  }

  function bossVarligiAl(dunyaId) {
    var kayit = BOSS_GORUNUMLERI[dunyaId] || BOSS_GORUNUMLERI.emre;
    return {
      isim: kayit.isim,
      yol: kayit.yol,
      durum: resimDurumuAl(kayit.yol)
    };
  }

  function mermiVarligiAl(id) {
    var kayit = MERMI_GORUNUMLERI[id];
    if (!kayit) return null;
    return {
      yol: kayit.yol,
      durum: resimDurumuAl(kayit.yol)
    };
  }

  BY.varliklar = {
    TABAN_KLASOR: tabanKlasor,
    DUNYA_PAKETLERI: DUNYA_PAKETLERI,
    DUSMAN_GORUNUMLERI: DUSMAN_GORUNUMLERI,
    BOSS_GORUNUMLERI: BOSS_GORUNUMLERI,
    MERMI_GORUNUMLERI: MERMI_GORUNUMLERI,

    baslat: function() {
      yuklemeKuyrugu = [];
    },

    dunyaPaketiAl: dunyaPaketiAl,
    mevcutDunyaIdAl: mevcutDunyaIdAl,
    dusmanVarligiAl: dusmanVarligiAl,
    bossVarligiAl: bossVarligiAl,
    mermiVarligiAl: mermiVarligiAl,
    resimDurumuAl: resimDurumuAl,
    cizResim: cizResim,
    cizYedekProp: cizYedekProp,
    setParcasiCiz: setParcasiCiz,

    dunyaArkaKatmanCiz: function(ctx, dunyaId, tabanY, aksanRenk) {
      var paket = dunyaPaketiAl(dunyaId);
      dunyaKatmaniCiz(ctx, paket.arkaKatmanlar, 0.20, tabanY, aksanRenk);
    },

    dunyaOrtaKatmanCiz: function(ctx, dunyaId, tabanY, aksanRenk) {
      var paket = dunyaPaketiAl(dunyaId);
      dunyaKatmaniCiz(ctx, paket.ortaKatmanlar, 0.45, tabanY, aksanRenk);
    },

    dunyaOnKatmanCiz: function(ctx, dunyaId, tabanY, aksanRenk) {
      var paket = dunyaPaketiAl(dunyaId);
      dunyaKatmaniCiz(ctx, paket.onKatmanlar, 0.82, tabanY, aksanRenk);
    }
  };

})();