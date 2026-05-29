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
  const MOUSE_OFFSCREEN = -1000;
  const POINTER_EXIT_EDGE_PX = 2;
  const mouse = { x: MOUSE_OFFSCREEN, y: MOUSE_OFFSCREEN };

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
	resetMouseTarget();

	window.addEventListener('resize', resize);
	window.addEventListener('mousemove', handleMouseMove);
	window.addEventListener('mouseleave', resetMouseTarget);
	window.addEventListener('blur', resetMouseTarget);
	document.addEventListener('mouseout', handleDocumentMouseOut);

	createParticles();
	animate();
  }

  function resize() {
    if (!canvas) return;
    const parent = canvas.parentElement;
    if (!parent) return;

    width = parent.clientWidth;
    height = parent.clientHeight;

    // Welcome DOM'u henüz ölçülemiyorsa 0x0 canvas ile partikül üretme.
    // Kısa gecikmeyle tekrar ölçerek neural animasyonun boş başlamasını engelle.
    if (width <= 0 || height <= 0) {
      window.setTimeout(resize, 80);
      return;
    }

    canvas.width = width;
    canvas.height = height;
  }

	function resetMouseTarget() {
	  mouse.x = MOUSE_OFFSCREEN;
	  mouse.y = MOUSE_OFFSCREEN;
	}

	function isPointerLeavingBrowser(e) {
	  // Çoklu ekran kullanımında imleç tarayıcıdan sağ/sol/üst/alt yönde
	  // çıkarken son geçerli koordinat bazen içeride kalabiliyor. Kenara çok
	  // yakın son koordinatı da çıkış kabul ederek nöral çekimi sıfırla.
	  return (
		e.clientX <= POINTER_EXIT_EDGE_PX ||
		e.clientY <= POINTER_EXIT_EDGE_PX ||
		e.clientX >= window.innerWidth - POINTER_EXIT_EDGE_PX ||
		e.clientY >= window.innerHeight - POINTER_EXIT_EDGE_PX
	  );
	}

	function handleDocumentMouseOut(e) {
	  // İmleç başka bir DOM elemanına değil de tarayıcı penceresinin dışına
	  // gidiyorsa relatedTarget null olur. Özellikle sağdaki ikinci ekrana
	  // geçişte kalan son nöral hedefi temizler.
	  if (!e.relatedTarget && !e.toElement) {
		resetMouseTarget();
	  }
	}

	function isPointerInsideNeuralRegion(e) {
	  if (!canvas) return false;

	  // Etkileşim alanı yalnızca nöral animasyonun sağ arka plan bölgesidir.
	  // Kart, hızlı başlangıç butonları ve video tarafı bu etkileşime dahil değildir.
	  const neuralSide = canvas.closest('.modern-welcome-neural-side');
	  const regionRect = (neuralSide || canvas).getBoundingClientRect();

	  const insideNeuralSide =
		e.clientX >= regionRect.left &&
		e.clientX <= regionRect.right &&
		e.clientY >= regionRect.top &&
		e.clientY <= regionRect.bottom;

	  if (!insideNeuralSide) {
		return false;
	  }

	  // Modern karşılama kartı cam olsa bile, kartın üstündeki buton/başlık
	  // bölgeleri nöral ağın doğrudan hover alanı sayılmamalıdır.
	  const welcomeCard = document.querySelector('.modern-welcome-card');
	  if (welcomeCard) {
		const cardRect = welcomeCard.getBoundingClientRect();
		const insideWelcomeCard =
		  e.clientX >= cardRect.left &&
		  e.clientX <= cardRect.right &&
		  e.clientY >= cardRect.top &&
		  e.clientY <= cardRect.bottom;

		if (insideWelcomeCard) {
		  return false;
		}
	  }

	  return true;
	}

	function handleMouseMove(e) {
	  if (!canvas) return;

	  if (isPointerLeavingBrowser(e) || !isPointerInsideNeuralRegion(e)) {
		resetMouseTarget();
		return;
	  }

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
	window.removeEventListener('mouseleave', resetMouseTarget);
	window.removeEventListener('blur', resetMouseTarget);
	document.removeEventListener('mouseout', handleDocumentMouseOut);

	resetMouseTarget();

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