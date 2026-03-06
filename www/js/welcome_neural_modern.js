// www/js/welcome_neural_modern.js
// Modern karsilama ekrani icin neural network canvas animasyonu

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

  // Animasyon rengi (varsayilan turuncu, karakter aksanina gore degisir)
  let pColor = { r: 255, g: 86, b: 32 };

  // Hex renk kodunu RGB objesine donustur
  function hexToRgb(hex) {
    var c = (hex || '').replace('#', '');
    if (!c || c.length < 6) return null;
    var n = parseInt(c, 16);
    return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
  }

  function init(canvasElement, accentHex) {
    if (!canvasElement) return;

    // Onceki animasyonlari temizle
    if (animationId) {
      cancelAnimationFrame(animationId);
      animationId = null;
    }

    // Karakter aksan rengi varsa kullan
    if (accentHex) {
      var rgb = hexToRgb(accentHex);
      if (rgb) pColor = rgb;
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
        size: Math.random() * 1.5 + 1.0
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

    // Renk degerlerini hazirla
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
      ctx.shadowBlur = 8;
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
          ctx.strokeStyle = 'rgba(' + pColor.r + ', ' + pColor.g + ', ' + pColor.b + ', ' + (opacity * 0.8) + ')';
          ctx.lineWidth = 0.6;
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

  return {
    init: init,
    destroy: destroy
  };
})();
