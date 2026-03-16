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
  // YILDIZ ARKA PLANI
  // -------------------------------------------------------------------------
  function initStars(count, width, height) {
    var stars = [];
    for (var i = 0; i < count; i++) {
      stars.push({
        x: Math.random() * width,
        y: Math.random() * height,
        size: Math.random() * 2 + 0.5,
        speed: Math.random() * 0.3 + 0.1,
        twinkle: Math.random() * Math.PI * 2
      });
    }
    return stars;
  }

  function drawStars(ctx, stars, frame, width, height) {
    for (var i = 0; i < stars.length; i++) {
      var s = stars[i];
      var alpha = 0.3 + Math.sin(s.twinkle + frame * 0.02) * 0.3;
      ctx.globalAlpha = alpha;
      ctx.fillStyle = '#ffffff';
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
  // ZEMİN ÇİZİMİ
  // -------------------------------------------------------------------------
  function drawGround(ctx, width, height, accentColor) {
    var groundY = height * 0.78;
    ctx.fillStyle = accentColor || '#7C4DFF';
    ctx.globalAlpha = 0.3;
    for (var i = 0; i < width; i += 4) {
      ctx.fillRect(i, groundY, 2, 2);
    }
    ctx.globalAlpha = 0.15;
    for (var j = 0; j < width; j += 8) {
      ctx.fillRect(j, groundY + 6, 4, 1);
    }
    ctx.globalAlpha = 1;
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
  function welcomeAnimLoop() {
    if (!welcomeCanvas || !welcomeCtx) return;

    // Mantıksal boyutları kullan (DPI ölçeklemesinden bağımsız)
    var dpr = window.devicePixelRatio || 1;
    var w = welcomeCanvas.width / dpr;
    var h = welcomeCanvas.height / dpr;

    // Arka planı temizle
    welcomeCtx.clearRect(0, 0, w, h);

    // Yıldızları çiz
    drawStars(welcomeCtx, welcomeStars, welcomeFrame, w, h);

    // Zemin
    drawGround(welcomeCtx, w, h, currentAccent);

    // Başlık metni
    var titleAlpha = 0.6 + Math.sin(welcomeFrame * 0.03) * 0.2;
    welcomeCtx.globalAlpha = titleAlpha;
    drawRetroText(welcomeCtx, 'CLAUDE CODE', w / 2, h * 0.15, Math.min(24, w / 20), currentAccent, 'rgba(0,0,0,0.5)');
    welcomeCtx.globalAlpha = 0.5;
    drawRetroText(welcomeCtx, 'Ajan Terminali', w / 2, h * 0.24, Math.min(14, w / 35), '#aaaaaa', null);
    welcomeCtx.globalAlpha = 1;

    // Alt bilgi metni
    welcomeCtx.globalAlpha = 0.3 + Math.sin(welcomeFrame * 0.05) * 0.15;
    drawRetroText(welcomeCtx, 'Bir komut yazarak basla...', w / 2, h * 0.92, Math.min(11, w / 45), '#888888', null);
    welcomeCtx.globalAlpha = 1;

    // Karakterleri güncelle ve çiz - ölçek canvas boyutuna göre ayarlanır
    var charScale = Math.max(3, Math.min(5, Math.min(w / 180, h / 80)));
    var charNames = { mergen: 'MERGEN', ulgen: 'ULGEN', kayra: 'KAYRA', erlik: 'ERLIK', umay: 'UMAY' };

    for (var i = 0; i < welcomeChars.length; i++) {
      var ch = welcomeChars[i];
      updateCharacter(ch, w, h, welcomeFrame);

      var pixels = ch.isWalking && ch.walkFrame % 30 < 15
        ? ch.charData.walk
        : ch.charData.idle;

      // Gölge
      welcomeCtx.globalAlpha = 0.2;
      welcomeCtx.fillStyle = ch.colors.dark;
      var shadowW = 16 * charScale * 0.6;
      welcomeCtx.fillRect(ch.x - shadowW / 2, ch.baseY + 2, shadowW, 3);
      welcomeCtx.globalAlpha = 1;

      drawPixelSprite(welcomeCtx, pixels, ch.x, ch.y, charScale, ch.colors, ch.facingRight);
      drawNameTag(welcomeCtx, charNames[ch.id] || ch.id, ch.x, ch.y, ch.colors.main);
    }

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
    welcomeStars = initStars(60, logicalW, logicalH);
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
  window.ccStartWelcome = startWelcomeScreen;
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

  // Sayfa ilk yüklendiğinde otomatik başlat (konteyner görünür olduğunda)
  $(document).on('shiny:connected', function() {
    var denemeSayisi = 0;
    var maxDeneme = 15;
    function dene() {
      denemeSayisi++;
      var welcomeEls = document.querySelectorAll('.cc-welcome-screen');
      var baslatildi = false;
      welcomeEls.forEach(function(el) {
        if (el.id && el.classList.contains('cc-welcome-active')) {
          var rect = el.getBoundingClientRect();
          if (rect.width > 0 && rect.height > 0) {
            startWelcomeScreen(el.id);
            baslatildi = true;
          }
        }
      });
      // Henüz başlatılamadıysa ve deneme hakkı varsa tekrar dene
      if (!baslatildi && denemeSayisi < maxDeneme) {
        setTimeout(dene, 500);
      }
    }
    // İlk denemeyi kısa gecikme ile başlat
    setTimeout(dene, 500);
  });

})();