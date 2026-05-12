// www/js/welcome_neural_modern.js
// Modern karşılama ekranı için neural network canvas animasyonu

window.WelcomeNeuralNetwork = (function() {
  let canvas = null;
  let ctx = null;
  let particles = [];
  let animationId = null;
  let width = 0;
  let height = 0;
  let lastFrameTime = 0;
  const targetFPS = 60;
  const frameDuration = 1000 / targetFPS;
  const particleCount = 80;
  const connectionDistance = 140;
  const mouse = { x: -1000, y: -1000 };

  // Animasyon rengi (varsayılan turuncu, karakter aksanına göre değişir)
  let pColor = { r: 255, g: 86, b: 32 };

  // Hex renk kodunu RGB objesine dönüştür
  function hexToRgb(hex) {
    var c = (hex || '').replace('#', '');
    if (!c || c.length < 6) return null;
    var n = parseInt(c, 16);
    return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
  }

  // Renk doygunluğunu artırarak daha canlı renkler oluştur
  function boostSaturation(rgb, factor) {
    var avg = (rgb.r + rgb.g + rgb.b) / 3;
    return {
      r: Math.min(255, Math.round(avg + (rgb.r - avg) * factor)),
      g: Math.min(255, Math.round(avg + (rgb.g - avg) * factor)),
      b: Math.min(255, Math.round(avg + (rgb.b - avg) * factor))
    };
  }

  function init(canvasElement, accentHex) {
    if (!canvasElement) return;

    // Önceki animasyonları temizle
    if (animationId) {
      cancelAnimationFrame(animationId);
      animationId = null;
    }

    // Karakter aksan rengi varsa kullan (doygunluk arttırılmış)
    if (accentHex) {
      var rgb = hexToRgb(accentHex);
      if (rgb) pColor = boostSaturation(rgb, 1.35);
    }

    canvas = canvasElement;
    ctx = canvas.getContext('2d');

    resize();
    window.addEventListener('resize', resize);
    window.addEventListener('mousemove', handleMouseMove);

    createParticles();
    animate();
  }

  function resize() {
    if (!canvas) return;
    const parent = canvas.parentElement;
    if (!parent) return;

    width = parent.clientWidth;
    height = parent.clientHeight;
    canvas.width = width;
    canvas.height = height;
  }

  function handleMouseMove(e) {
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    mouse.x = e.clientX - rect.left;
    mouse.y = e.clientY - rect.top;
  }

  function createParticles() {
    particles = [];
    for (let i = 0; i < particleCount; i++) {
      particles.push({
        x: Math.random() * width,
        y: Math.random() * height,
        vx: (Math.random() - 0.5) * 0.4,
        vy: (Math.random() - 0.5) * 0.4,
        size: Math.random() * 2.0 + 1.2
      });
    }
  }

  function animate(currentTime) {
    if (!ctx || !canvas) return;

    if (!lastFrameTime) lastFrameTime = currentTime;
    const elapsed = currentTime - lastFrameTime;

    if (elapsed < frameDuration) {
      animationId = requestAnimationFrame(animate);
      return;
    }

    lastFrameTime = currentTime - (elapsed % frameDuration);

    ctx.clearRect(0, 0, width, height);

    // Renk değerlerini hazırla
    var fillStr = 'rgb(' + pColor.r + ', ' + pColor.g + ', ' + pColor.b + ')';
    var shadowStr = 'rgba(' + pColor.r + ', ' + pColor.g + ', ' + pColor.b + ', 0.8)';

    particles.forEach((p, i) => {
      p.x += p.vx;
      p.y += p.vy;

      if (p.x < 0 || p.x > width) p.vx *= -1;
      if (p.y < 0 || p.y > height) p.vy *= -1;

      const dx = mouse.x - p.x;
      const dy = mouse.y - p.y;
      const dist = Math.sqrt(dx * dx + dy * dy);
      if (dist < 200) {
        p.x += dx * 0.005;
        p.y += dy * 0.005;
      }

      ctx.beginPath();
      ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
      ctx.fillStyle = fillStr;
      ctx.shadowBlur = 12;
      ctx.shadowColor = shadowStr;
      ctx.fill();
      ctx.shadowBlur = 0;

      for (let j = i + 1; j < particles.length; j++) {
        const p2 = particles[j];
        const dx2 = p.x - p2.x;
        const dy2 = p.y - p2.y;
        const dist2 = Math.sqrt(dx2 * dx2 + dy2 * dy2);

        if (dist2 < connectionDistance) {
          ctx.beginPath();
          const opacity = 1 - dist2 / connectionDistance;
          ctx.strokeStyle = 'rgba(' + pColor.r + ', ' + pColor.g + ', ' + pColor.b + ', ' + (opacity * 0.95) + ')';
          ctx.lineWidth = 0.8;
          ctx.moveTo(p.x, p.y);
          ctx.lineTo(p2.x, p2.y);
          ctx.stroke();
        }
      }
    });

    animationId = requestAnimationFrame(animate);
  }

  function destroy() {
    if (animationId) {
      cancelAnimationFrame(animationId);
      animationId = null;
    }

    window.removeEventListener('resize', resize);
    window.removeEventListener('mousemove', handleMouseMove);

    canvas = null;
    ctx = null;
    particles = [];
    lastFrameTime = 0;
  }

  // Canlı olarak renk güncelle (karakter değiştiğinde)
  function updateColor(accentHex) {
    if (accentHex) {
      var rgb = hexToRgb(accentHex);
      if (rgb) pColor = boostSaturation(rgb, 1.35);
    }
  }

  return {
    init: init,
    destroy: destroy,
    updateColor: updateColor
  };
})();

// Shiny mesaj dinleyicisi: Neural network rengini güncelle.
// Deferred yüklemede shiny:connected olayı kaçmışsa bile handler kaybolmasın.
(function registerNeuralColorHandler(attempt) {
  attempt = attempt || 0;

  if (window.MERGEN_UPDATE_NEURAL_COLOR_HANDLER_REGISTERED) {
    return;
  }

  if (typeof Shiny === 'undefined' ||
      typeof Shiny.addCustomMessageHandler !== 'function') {
    if (attempt < 80) {
      window.setTimeout(function() {
        registerNeuralColorHandler(attempt + 1);
      }, 50);
    }
    return;
  }

  window.MERGEN_UPDATE_NEURAL_COLOR_HANDLER_REGISTERED = true;

  Shiny.addCustomMessageHandler('updateNeuralColor', function(data) {
    if (data && data.accent && window.WelcomeNeuralNetwork) {
      window.WelcomeNeuralNetwork.updateColor(data.accent);
    }
  });
})(0);