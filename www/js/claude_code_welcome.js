// =============================================================================
// Dosya Yolu: www/js/claude_code_welcome.js
// Açıklama: Claude Code karşılama ekranı için retro 8-bit oyun animasyonu.
//           Beş karakter piksel sahnede dolaşır, fareyle etkileşime girer
//           ve birbirleriyle çarpıştığında zıplar. Retro yazı tipi efekti
//           ve yıldız arka planı içerir. Giriş alanını asla engellemez.
// =============================================================================

(function() {
  'use strict';

  // -------------------------------------------------------------------------
  // KARAKTER RENK TANIMLARI
  // -------------------------------------------------------------------------
  var CHAR_COLORS = {
    mergen: { main: '#7C4DFF', dark: '#5635B2', light: '#B388FF' },
    ulgen:  { main: '#2F6DF6', dark: '#1E4DB0', light: '#82B1FF' },
    kayra:  { main: '#12A97B', dark: '#0C7A58', light: '#69F0AE' },
    erlik:  { main: '#B66A2C', dark: '#8F5321', light: '#FFAB40' },
    umay:   { main: '#E98686', dark: '#C45E5E', light: '#FF8A80' }
  };

  // -------------------------------------------------------------------------
  // GELİŞMİŞ 16x16 PİKSEL KARAKTERLERİ
  // 0=boş, 1=ana renk, 2=koyu ton, 3=açık ton
  // -------------------------------------------------------------------------
  var WELCOME_CHARS = {
    mergen: {
      idle: [
        [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
        [0,0,0,0,1,1,3,3,3,1,1,0,0,0,0,0],
        [0,0,0,1,1,2,1,1,1,2,1,1,0,0,0,0],
        [0,0,0,1,1,1,2,2,2,1,1,1,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,0,1,2,1,2,1,0,0,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,1,1,1,2,2,2,1,1,1,0,0,0,0],
        [0,0,1,1,1,1,1,1,1,1,1,1,1,0,0,0],
        [0,0,3,0,1,1,1,1,1,1,1,0,3,0,0,0],
        [0,0,3,0,0,1,1,1,1,1,0,0,3,0,0,0],
        [0,0,0,0,0,1,1,0,1,1,0,0,0,0,0,0],
        [0,0,0,0,0,1,1,0,1,1,0,0,0,0,0,0],
        [0,0,0,0,1,2,1,0,1,2,1,0,0,0,0,0],
        [0,0,0,0,1,1,1,0,1,1,1,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
      ],
      walk: [
        [0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0],
        [0,0,0,0,1,1,3,3,3,1,1,0,0,0,0,0],
        [0,0,0,1,1,2,1,1,1,2,1,1,0,0,0,0],
        [0,0,0,1,1,1,2,2,2,1,1,1,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,0,1,2,1,2,1,0,0,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,1,1,1,2,2,2,1,1,1,0,0,0,0],
        [0,0,1,1,1,1,1,1,1,1,1,1,1,0,0,0],
        [0,0,3,0,1,1,1,1,1,1,1,0,3,0,0,0],
        [0,0,3,0,0,1,1,1,1,1,0,0,3,0,0,0],
        [0,0,0,0,0,1,1,0,1,1,0,0,0,0,0,0],
        [0,0,0,0,1,2,1,0,0,1,0,0,0,0,0,0],
        [0,0,0,0,1,1,1,0,0,1,2,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,1,1,1,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
      ]
    },
    ulgen: {
      idle: [
        [0,0,0,0,3,3,3,3,3,3,3,3,0,0,0,0],
        [0,0,0,3,0,0,1,1,1,1,0,0,3,0,0,0],
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,1,1,3,3,3,3,1,1,0,0,0,0],
        [0,0,0,0,1,2,1,1,1,1,2,1,0,0,0,0],
        [0,0,0,0,1,1,1,2,2,1,1,1,0,0,0,0],
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,0,0,1,2,2,1,0,0,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,1,1,2,1,1,1,1,2,1,1,0,0,0],
        [0,0,0,1,0,0,1,1,1,1,0,0,1,0,0,0],
        [0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0],
        [0,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0],
        [0,0,0,0,0,1,2,0,0,2,1,0,0,0,0,0],
        [0,0,0,0,0,1,1,0,0,1,1,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
      ],
      walk: [
        [0,0,0,0,3,3,3,3,3,3,3,3,0,0,0,0],
        [0,0,0,3,0,0,1,1,1,1,0,0,3,0,0,0],
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,1,1,3,3,3,3,1,1,0,0,0,0],
        [0,0,0,0,1,2,1,1,1,1,2,1,0,0,0,0],
        [0,0,0,0,1,1,1,2,2,1,1,1,0,0,0,0],
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,0,0,1,2,2,1,0,0,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,1,1,2,1,1,1,1,2,1,1,0,0,0],
        [0,0,0,1,0,0,1,1,1,1,0,0,1,0,0,0],
        [0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0],
        [0,0,0,0,0,1,2,0,0,1,0,0,0,0,0,0],
        [0,0,0,0,0,1,1,0,0,2,1,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,1,1,1,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
      ]
    },
    kayra: {
      idle: [
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,1,1,2,2,2,2,1,1,0,0,0,0],
        [0,0,0,1,1,2,1,1,1,1,2,1,1,0,0,0],
        [0,0,0,1,1,1,2,2,2,2,1,1,1,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,0,0,1,2,1,1,2,1,0,0,0,0,0],
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,1,2,2,2,2,2,2,1,0,0,0,0],
        [0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0],
        [0,0,1,2,1,1,2,1,1,2,1,1,2,1,0,0],
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,0,1,2,1,1,2,1,0,0,0,0,0],
        [0,0,0,0,0,1,1,0,0,1,1,0,0,0,0,0],
        [0,0,0,0,1,2,1,0,0,1,2,1,0,0,0,0],
        [0,0,0,0,1,1,1,0,0,1,1,1,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
      ],
      walk: [
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,1,1,2,2,2,2,1,1,0,0,0,0],
        [0,0,0,1,1,2,1,1,1,1,2,1,1,0,0,0],
        [0,0,0,1,1,1,2,2,2,2,1,1,1,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,0,0,1,2,1,1,2,1,0,0,0,0,0],
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,1,2,2,2,2,2,2,1,0,0,0,0],
        [0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0],
        [0,0,1,2,1,1,2,1,1,2,1,1,2,1,0,0],
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,0,1,2,1,1,2,1,0,0,0,0,0],
        [0,0,0,0,1,2,1,0,0,1,0,0,0,0,0,0],
        [0,0,0,0,1,1,1,0,0,1,2,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,1,1,1,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
      ]
    },
    erlik: {
      idle: [
        [0,0,0,0,2,2,1,1,1,1,2,2,0,0,0,0],
        [0,0,0,2,1,1,1,1,1,1,1,1,2,0,0,0],
        [0,0,0,2,1,2,1,1,1,1,2,1,2,0,0,0],
        [0,0,0,1,1,1,2,2,2,2,1,1,1,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,0,0,1,2,1,1,2,1,0,0,0,0,0],
        [0,0,0,0,0,1,1,2,2,1,1,0,0,0,0,0],
        [0,0,0,0,1,1,2,2,2,2,1,1,0,0,0,0],
        [0,0,0,1,2,1,1,1,1,1,1,2,1,0,0,0],
        [0,0,1,1,0,1,1,1,1,1,1,0,1,1,0,0],
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,0,1,2,0,0,2,1,0,0,0,0,0],
        [0,0,0,0,0,1,1,0,0,1,1,0,0,0,0,0],
        [0,0,0,0,1,2,1,0,0,1,2,1,0,0,0,0],
        [0,0,0,0,2,1,1,0,0,1,1,2,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
      ],
      walk: [
        [0,0,0,0,2,2,1,1,1,1,2,2,0,0,0,0],
        [0,0,0,2,1,1,1,1,1,1,1,1,2,0,0,0],
        [0,0,0,2,1,2,1,1,1,1,2,1,2,0,0,0],
        [0,0,0,1,1,1,2,2,2,2,1,1,1,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,0,0,1,2,1,1,2,1,0,0,0,0,0],
        [0,0,0,0,0,1,1,2,2,1,1,0,0,0,0,0],
        [0,0,0,0,1,1,2,2,2,2,1,1,0,0,0,0],
        [0,0,0,1,2,1,1,1,1,1,1,2,1,0,0,0],
        [0,0,1,1,0,1,1,1,1,1,1,0,1,1,0,0],
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,1,2,1,0,0,1,0,0,0,0,0,0],
        [0,0,0,0,1,1,1,0,0,1,2,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,1,1,1,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
      ]
    },
    umay: {
      idle: [
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,1,1,3,3,3,3,1,1,0,0,0,0],
        [0,0,0,0,1,2,1,1,1,1,2,1,0,0,0,0],
        [0,0,0,0,1,1,2,2,2,2,1,1,0,0,0,0],
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,0,1,1,2,2,1,1,0,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,3,1,1,2,1,1,1,1,2,1,1,3,0,0],
        [0,3,0,1,1,1,1,1,1,1,1,1,1,0,3,0],
        [3,0,0,0,1,1,1,1,1,1,1,1,0,0,0,3],
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,0,1,1,0,0,1,1,0,0,0,0,0],
        [0,0,0,0,0,1,1,0,0,1,1,0,0,0,0,0],
        [0,0,0,0,1,2,1,0,0,1,2,1,0,0,0,0],
        [0,0,0,0,1,1,1,0,0,1,1,1,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
      ],
      walk: [
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,1,1,3,3,3,3,1,1,0,0,0,0],
        [0,0,0,0,1,2,1,1,1,1,2,1,0,0,0,0],
        [0,0,0,0,1,1,2,2,2,2,1,1,0,0,0,0],
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,0,1,1,2,2,1,1,0,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,3,1,1,1,2,1,1,1,1,2,1,1,1,3,0],
        [3,0,0,1,1,1,1,1,1,1,1,1,1,0,0,3],
        [0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,0,1,1,0,0,1,1,0,0,0,0,0],
        [0,0,0,0,1,2,1,0,0,1,0,0,0,0,0,0],
        [0,0,0,0,1,1,1,0,0,1,2,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,1,1,1,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
      ]
    }
  };

  // -------------------------------------------------------------------------
  // SAHNE DURUM DEĞİŞKENLERİ
  // -------------------------------------------------------------------------
  var welcomeCanvas = null;
  var welcomeCtx = null;
  var welcomeAnimId = null;
  var welcomeChars = [];
  var welcomeStars = [];
  var mouseX = -100;
  var mouseY = -100;
  var welcomeFrame = 0;
  var currentAccent = '#7C4DFF';

  // -------------------------------------------------------------------------
  // YILDIZ ARKA PLANI (derinlik katmanlı)
  // -------------------------------------------------------------------------
  function initStars(count, width, height) {
    var stars = [];
    for (var i = 0; i < count; i++) {
      stars.push({
        x: Math.random() * width,
        y: Math.random() * (height * 0.65),
        size: Math.random() * 2.5 + 0.5,
        speed: Math.random() * 0.3 + 0.1,
        twinkle: Math.random() * Math.PI * 2,
        layer: Math.floor(Math.random() * 3)
      });
    }
    return stars;
  }

  function drawStars(ctx, stars, frame, width, height) {
    for (var i = 0; i < stars.length; i++) {
      var s = stars[i];
      var layerAlpha = [0.2, 0.4, 0.7][s.layer];
      var alpha = layerAlpha + Math.sin(s.twinkle + frame * 0.02) * 0.25;
      ctx.globalAlpha = Math.max(0, Math.min(1, alpha));
      var renk = s.layer === 2 ? '#E8E8FF' : (s.layer === 1 ? '#CCE0FF' : '#AABBDD');
      ctx.fillStyle = renk;
      ctx.fillRect(Math.floor(s.x), Math.floor(s.y), Math.ceil(s.size), Math.ceil(s.size));
      s.twinkle += s.speed * 0.05;
    }
    ctx.globalAlpha = 1;
  }

  // -------------------------------------------------------------------------
  // KARAKTER ÇİZİM VE FİZİK
  // -------------------------------------------------------------------------
  function initCharacters(width, height) {
    var charIds = ['mergen', 'ulgen', 'kayra', 'erlik', 'umay'];
    var chars = [];
    var spacing = width / (charIds.length + 1);
    // Karakter yüksekliği canvas yüksekliğine göre ölçeklenir
    var groundY = height * 0.72;

    for (var i = 0; i < charIds.length; i++) {
      var cid = charIds[i];
      chars.push({
        id: cid,
        x: spacing * (i + 1),
        y: groundY,
        baseY: groundY,
        vx: (Math.random() - 0.5) * 1.2,
        vy: 0,
        targetX: spacing * (i + 1),
        frame: 0,
        walkFrame: 0,
        isWalking: false,
        facingRight: Math.random() > 0.5,
        jumpCooldown: 0,
        pushForce: 0,
        idleTimer: Math.random() * 200,
        colors: CHAR_COLORS[cid],
        charData: WELCOME_CHARS[cid]
      });
    }
    return chars;
  }

  function drawPixelSprite(ctx, pixels, x, y, scale, colors, facingRight) {
    var rows = pixels.length;
    var cols = pixels[0].length;
    var offsetX = x - (cols * scale) / 2;
    var offsetY = y - (rows * scale);

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        var val = pixels[r][facingRight ? c : (cols - 1 - c)];
        if (val === 0) continue;

        if (val === 1) ctx.fillStyle = colors.main;
        else if (val === 2) ctx.fillStyle = colors.dark;
        else if (val === 3) ctx.fillStyle = colors.light;

        ctx.fillRect(
          Math.floor(offsetX + c * scale),
          Math.floor(offsetY + r * scale),
          Math.ceil(scale),
          Math.ceil(scale)
        );
      }
    }
  }

  function updateCharacter(ch, width, height, frame) {
    // Fare etkileşimi - fare yaklaştığında ittir
    var dx = ch.x - mouseX;
    var dy = ch.y - mouseY;
    var dist = Math.sqrt(dx * dx + dy * dy);

    if (dist < 80 && dist > 0) {
      var force = (80 - dist) / 80 * 3;
      ch.vx += (dx / dist) * force;
      if (ch.jumpCooldown <= 0) {
        ch.vy = -4 - Math.random() * 2;
        ch.jumpCooldown = 30;
      }
    }

    // Karakter-karakter çarpışması
    for (var i = 0; i < welcomeChars.length; i++) {
      var other = welcomeChars[i];
      if (other.id === ch.id) continue;
      var cx = ch.x - other.x;
      var cy = ch.y - other.y;
      var cd = Math.sqrt(cx * cx + cy * cy);
      if (cd < 30 && cd > 0) {
        ch.vx += (cx / cd) * 0.8;
        if (ch.jumpCooldown <= 0 && Math.random() < 0.3) {
          ch.vy = -3;
          ch.jumpCooldown = 20;
        }
      }
    }

    // Yerçekimi
    ch.vy += 0.25;

    // Sürtünme
    ch.vx *= 0.92;

    // Konumu güncelle
    ch.x += ch.vx;
    ch.y += ch.vy;

    // Zemin
    if (ch.y > ch.baseY) {
      ch.y = ch.baseY;
      ch.vy = 0;
    }

    // Kenar sınırları
    if (ch.x < 30) { ch.x = 30; ch.vx = Math.abs(ch.vx) * 0.5; }
    if (ch.x > width - 30) { ch.x = width - 30; ch.vx = -Math.abs(ch.vx) * 0.5; }

    // Yön
    if (Math.abs(ch.vx) > 0.3) {
      ch.facingRight = ch.vx > 0;
      ch.isWalking = true;
    } else {
      ch.isWalking = false;
    }

    // Boşta gezinme
    ch.idleTimer--;
    if (ch.idleTimer <= 0 && Math.abs(ch.vx) < 0.5) {
      ch.vx += (Math.random() - 0.5) * 1.5;
      ch.idleTimer = 150 + Math.random() * 200;
    }

    ch.jumpCooldown = Math.max(0, ch.jumpCooldown - 1);
    ch.walkFrame++;
  }

  // -------------------------------------------------------------------------
  // RETRO METİN ÇİZİMİ
  // -------------------------------------------------------------------------
  function drawRetroText(ctx, text, x, y, size, color, shadowColor) {
    ctx.save();
    ctx.font = 'bold ' + size + 'px monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    if (shadowColor) {
      ctx.fillStyle = shadowColor;
      ctx.fillText(text, x + 2, y + 2);
    }
    ctx.fillStyle = color;
    ctx.fillText(text, x, y);
    ctx.restore();
  }

  // -------------------------------------------------------------------------
  // ARKA PLAN MANZARA ÇİZİMİ (piksel sanat tarzı doğa)
  // -------------------------------------------------------------------------
  function drawLandscape(ctx, width, height, accentColor, frame) {
    var groundY = height * 0.78;

    // Gökyüzü gradyanı (koyu mor-mavi)
    var grad = ctx.createLinearGradient(0, 0, 0, groundY);
    grad.addColorStop(0, '#0a0a1a');
    grad.addColorStop(0.4, '#0f0f2e');
    grad.addColorStop(0.7, '#1a1535');
    grad.addColorStop(1, '#1e1040');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, width, groundY);

    // Arka plan dağlar (piksel tarzı siluet)
    ctx.fillStyle = '#151530';
    drawPixelMountains(ctx, width, groundY, 0.5, 0.18, 40);
    ctx.fillStyle = '#1a1a3d';
    drawPixelMountains(ctx, width, groundY, 0.65, 0.12, 30);

    // Zemin (piksel çimen tarzı)
    var groundGrad = ctx.createLinearGradient(0, groundY, 0, height);
    groundGrad.addColorStop(0, '#1a2810');
    groundGrad.addColorStop(0.3, '#152008');
    groundGrad.addColorStop(1, '#0d1505');
    ctx.fillStyle = groundGrad;
    ctx.fillRect(0, groundY, width, height - groundY);

    // Çimen detayları (piksel noktalar)
    var accent = accentColor || '#7C4DFF';
    ctx.globalAlpha = 0.15;
    ctx.fillStyle = '#2d4a1a';
    for (var i = 0; i < width; i += 4) {
      var h = Math.sin(i * 0.1 + frame * 0.01) * 2 + 2;
      ctx.fillRect(i, groundY - h, 2, h);
    }

    // Zemin çizgi (vurgu rengi ile)
    ctx.globalAlpha = 0.4;
    ctx.fillStyle = accent;
    for (var j = 0; j < width; j += 3) {
      ctx.fillRect(j, groundY, 2, 1);
    }
    ctx.globalAlpha = 0.12;
    for (var k = 0; k < width; k += 6) {
      ctx.fillRect(k, groundY + 4, 3, 1);
    }
    ctx.globalAlpha = 1;
  }

  // Piksel tarzı dağ silueti
  function drawPixelMountains(ctx, width, baseY, heightRatio, variance, stepSize) {
    var mountainH = baseY * heightRatio;
    ctx.beginPath();
    ctx.moveTo(0, baseY);
    for (var x = 0; x <= width; x += stepSize) {
      var noise = Math.sin(x * 0.008) * mountainH * 0.6 +
                  Math.sin(x * 0.02 + 1.5) * mountainH * 0.25 +
                  Math.sin(x * 0.05 + 3) * mountainH * 0.1;
      var y = baseY - mountainH * 0.3 - noise * variance * 3;
      // Piksel hizalama (doğru)
      ctx.lineTo(Math.floor(x), Math.floor(y));
    }
    ctx.lineTo(width, baseY);
    ctx.closePath();
    ctx.fill();
  }

  // -------------------------------------------------------------------------
  // KARAKTER İSİM ETİKETİ
  // -------------------------------------------------------------------------
  function drawNameTag(ctx, name, x, y, color) {
    ctx.save();
    ctx.font = 'bold 10px monospace';
    ctx.textAlign = 'center';
    ctx.fillStyle = color;
    ctx.globalAlpha = 0.8;
    ctx.fillText(name, x, y + 12);
    ctx.restore();
  }

  // -------------------------------------------------------------------------
  // ANA ANİMASYON DÖNGÜSÜ
  // -------------------------------------------------------------------------
  // Retro metinler (MERGEN Bilge hakkında bilgilendirici)
  var retroMetinler = [
    'MERGEN BİLGE',
    'Yapay Zekâ Asistanı',
    'Türkçe - Akıllı - Güvenilir'
  ];

  function welcomeAnimLoop() {
    if (!welcomeCanvas || !welcomeCtx) return;

    // Mantıksal boyutları kullan (DPI ölçeklemesinden bağımsız)
    var dpr = window.devicePixelRatio || 1;
    var w = welcomeCanvas.width / dpr;
    var h = welcomeCanvas.height / dpr;

    // Arka planı temizle
    welcomeCtx.clearRect(0, 0, w, h);

    // Manzara arka planı (gökyüzü, dağlar, zemin)
    drawLandscape(welcomeCtx, w, h, currentAccent, welcomeFrame);

    // Yıldızları çiz
    drawStars(welcomeCtx, welcomeStars, welcomeFrame, w, h);

    // Başlık metni - MERGEN BİLGE
    var titleSize = Math.min(28, Math.max(16, w / 18));
    var titleAlpha = 0.7 + Math.sin(welcomeFrame * 0.025) * 0.2;
    welcomeCtx.globalAlpha = titleAlpha;
    drawRetroText(welcomeCtx, retroMetinler[0], w / 2, h * 0.12, titleSize, currentAccent, 'rgba(0,0,0,0.6)');

    // Alt başlık
    welcomeCtx.globalAlpha = 0.55;
    var subSize = Math.min(14, Math.max(10, w / 40));
    drawRetroText(welcomeCtx, retroMetinler[1], w / 2, h * 0.20, subSize, '#cccccc', null);

    // Slogan
    welcomeCtx.globalAlpha = 0.4;
    var sloganSize = Math.min(11, Math.max(8, w / 50));
    drawRetroText(welcomeCtx, retroMetinler[2], w / 2, h * 0.27, sloganSize, '#999999', null);

    // Ajan Terminali etiketi
    welcomeCtx.globalAlpha = 0.45 + Math.sin(welcomeFrame * 0.04) * 0.15;
    drawRetroText(welcomeCtx, '[ AJAN TERMINALI ]', w / 2, h * 0.35, Math.min(12, w / 45), currentAccent, null);
    welcomeCtx.globalAlpha = 1;

    // Karakterleri güncelle ve çiz - ölçek canvas boyutuna göre ayarlanır
    var charScale = Math.max(3, Math.min(6, Math.min(w / 150, h / 70)));
    var charNames = { mergen: 'MERGEN', ulgen: 'ÜLGEN', kayra: 'KAYRA', erlik: 'ERLİK', umay: 'UMAY' };

    for (var i = 0; i < welcomeChars.length; i++) {
      var ch = welcomeChars[i];
      updateCharacter(ch, w, h, welcomeFrame);

      var pixels = ch.isWalking && ch.walkFrame % 30 < 15
        ? ch.charData.walk
        : ch.charData.idle;

      // Gölge
      welcomeCtx.globalAlpha = 0.25;
      welcomeCtx.fillStyle = ch.colors.dark;
      var shadowW = 16 * charScale * 0.7;
      welcomeCtx.fillRect(ch.x - shadowW / 2, ch.baseY + 2, shadowW, 4);
      welcomeCtx.globalAlpha = 1;

      drawPixelSprite(welcomeCtx, pixels, ch.x, ch.y, charScale, ch.colors, ch.facingRight);
      drawNameTag(welcomeCtx, charNames[ch.id] || ch.id, ch.x, ch.y, ch.colors.main);
    }

    // Alt bilgi metni (daha kompakt)
    welcomeCtx.globalAlpha = 0.3 + Math.sin(welcomeFrame * 0.05) * 0.1;
    var bottomSize = Math.min(10, Math.max(8, w / 55));
    drawRetroText(welcomeCtx, '> komut yaz, Enter\'a bas _', w / 2, h * 0.93, bottomSize, '#666666', null);
    welcomeCtx.globalAlpha = 1;

    welcomeFrame++;
    welcomeAnimId = requestAnimationFrame(welcomeAnimLoop);
  }

  // -------------------------------------------------------------------------
  // KARŞILAMA EKRANI BAŞLATMA / DURDURMA
  // -------------------------------------------------------------------------
  function startWelcomeScreen(containerId) {
    var container = document.getElementById(containerId);
    if (!container) return;

    // Mevcut animasyonu temizle
    stopWelcomeScreen();

    // Canvas oluştur
    welcomeCanvas = document.createElement('canvas');
    welcomeCanvas.className = 'cc-welcome-canvas';
    welcomeCanvas.style.width = '100%';
    welcomeCanvas.style.height = '100%';
    container.innerHTML = '';
    container.appendChild(welcomeCanvas);

    // Canvas boyutunu ayarla
    var resizeRetryCount = 0;
    function resizeCanvas() {
      if (!welcomeCanvas || !welcomeCanvas.parentElement) return;
      var rect = welcomeCanvas.parentElement.getBoundingClientRect();
      if (rect.width > 0 && rect.height > 0) {
        // Piksel oranını hesaba kat (yüksek DPI ekranlar için)
        var dpr = window.devicePixelRatio || 1;
        welcomeCanvas.width = Math.floor(rect.width * dpr);
        welcomeCanvas.height = Math.floor(rect.height * dpr);
        // CSS boyutu ayarla
        welcomeCanvas.style.width = rect.width + 'px';
        welcomeCanvas.style.height = rect.height + 'px';
        // Context ölçekleme (yüksek DPI desteği)
        if (welcomeCtx) {
          welcomeCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
        }
        // Boyut değiştiğinde karakterleri yeniden konumla
        // Mantıksal boyutları kullan (DPI ölçeklemeden önce)
        if (welcomeChars.length > 0) {
          var groundY = rect.height * 0.72;
          var spacing = rect.width / (welcomeChars.length + 1);
          for (var i = 0; i < welcomeChars.length; i++) {
            welcomeChars[i].baseY = groundY;
            if (welcomeChars[i].y > groundY) welcomeChars[i].y = groundY;
          }
        }
        resizeRetryCount = 0;
      } else if (resizeRetryCount < 10) {
        // Konteyner henüz görünür değilse tekrar dene
        resizeRetryCount++;
        setTimeout(resizeCanvas, 200);
      }
    }
    resizeCanvas();

    welcomeCtx = welcomeCanvas.getContext('2d');
    // DPI ölçeklemesini context'e uygula
    var dpr = window.devicePixelRatio || 1;
    welcomeCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
    // Mantıksal boyutlarla başlat
    var logicalW = welcomeCanvas.width / dpr;
    var logicalH = welcomeCanvas.height / dpr;
    welcomeStars = initStars(100, logicalW, logicalH);
    welcomeChars = initCharacters(logicalW, logicalH);
    welcomeFrame = 0;

    // Mevcut vurgu rengini al
    var ccContainer = document.querySelector('.claude-code-container');
    if (ccContainer) {
      var charId = ccContainer.getAttribute('data-character') || 'mergen';
      if (CHAR_COLORS[charId]) currentAccent = CHAR_COLORS[charId].main;
    }

    // Fare takibi
    welcomeCanvas.addEventListener('mousemove', function(e) {
      var rect = welcomeCanvas.getBoundingClientRect();
      mouseX = e.clientX - rect.left;
      mouseY = e.clientY - rect.top;
    });

    welcomeCanvas.addEventListener('mouseleave', function() {
      mouseX = -100;
      mouseY = -100;
    });

    // Tıklama ile tüm karakterleri zıplat
    welcomeCanvas.addEventListener('click', function(e) {
      var rect = welcomeCanvas.getBoundingClientRect();
      var cx = e.clientX - rect.left;
      var cy = e.clientY - rect.top;
      for (var i = 0; i < welcomeChars.length; i++) {
        var ch = welcomeChars[i];
        var d = Math.sqrt(Math.pow(ch.x - cx, 2) + Math.pow(ch.y - cy, 2));
        var force = Math.max(1, 5 - d / 40);
        ch.vy = -force - Math.random() * 3;
        ch.vx += (ch.x - cx) / Math.max(d, 1) * 3;
      }
    });

    // Boyut değişiminde canvas'ı güncelle
    window.addEventListener('resize', resizeCanvas);

    container.classList.add('cc-welcome-active');
    welcomeAnimLoop();
  }

  function stopWelcomeScreen() {
    if (welcomeAnimId) {
      cancelAnimationFrame(welcomeAnimId);
      welcomeAnimId = null;
    }
    welcomeCanvas = null;
    welcomeCtx = null;
    welcomeChars = [];
    welcomeStars = [];
  }

  // -------------------------------------------------------------------------
  // GENEL ERİŞİM FONKSİYONLARI (claude_code.js tarafından çağrılabilir)
  // -------------------------------------------------------------------------
  window.ccStartWelcome = function(containerId) {
    welcomeBaslatildi = false;
    startWelcomeScreen(containerId);
    welcomeBaslatildi = true;
  };
  window.ccStopWelcome = stopWelcomeScreen;
  window.ccUpdateWelcomeTheme = function(characterId, accent) {
    if (CHAR_COLORS[characterId]) {
      currentAccent = CHAR_COLORS[characterId].main;
    } else if (accent) {
      currentAccent = accent;
    }
  };

  // -------------------------------------------------------------------------
  // SHINY ENTEGRASYONU
  // -------------------------------------------------------------------------

  // Karşılama ekranını başlat (sayfa yüklendiğinde)
  Shiny.addCustomMessageHandler('cc-init-welcome', function(data) {
    startWelcomeScreen(data.containerId);
  });

  // Karşılama ekranını göster (çıktı temizlendiğinde)
  Shiny.addCustomMessageHandler('cc-show-welcome', function(data) {
    var container = document.getElementById(data.containerId);
    if (container) {
      container.classList.add('cc-welcome-active');
      if (!welcomeAnimId) {
        startWelcomeScreen(data.containerId);
      }
    }
  });

  // Karşılama ekranını gizle (mesaj eklendiğinde)
  Shiny.addCustomMessageHandler('cc-hide-welcome', function(data) {
    var container = document.getElementById(data.containerId);
    if (container) {
      container.classList.remove('cc-welcome-active');
    }
    stopWelcomeScreen();
  });

  // Karşılama ekranı ilk kez gösterildiğinde otomatik başlat
  // Sekme değişikliğini dinleyerek Claude Code sekmesi görünür olduğunda tetikler
  var welcomeBaslatildi = false;

  function karsilamaBaslat() {
    if (welcomeBaslatildi) return;
    var welcomeEls = document.querySelectorAll('.cc-welcome-screen.cc-welcome-active');
    welcomeEls.forEach(function(el) {
      if (el.id) {
        var rect = el.getBoundingClientRect();
        if (rect.width > 0 && rect.height > 0) {
          startWelcomeScreen(el.id);
          welcomeBaslatildi = true;
        }
      }
    });
  }

  // Sekme değişikliğinde kontrol et (shinydashboard sekme geçişleri)
  $(document).on('shiny:inputchanged', function(e) {
    if (e.name === 'tabs' && e.value === 'claude_code') {
      // Sekme geçiş animasyonu tamamlandıktan sonra başlat
      setTimeout(karsilamaBaslat, 300);
    }
  });

  // Shiny bağlandığında da dene (sayfa doğrudan Claude Code sekmesinde açılırsa)
  $(document).on('shiny:connected', function() {
    setTimeout(karsilamaBaslat, 800);
  });

})();