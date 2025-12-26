// www/js/intro_animation.js

$(document).ready(function() {
  // Sinematik Giriş Animasyonu
  function initIntro() {
    const introContainer = document.getElementById('intro-container');
    if (!introContainer) return;

    let canvas = document.getElementById('neural-canvas');
    if (!canvas) {
      canvas = document.createElement('canvas');
      canvas.id = 'neural-canvas';
      canvas.className = 'neural-canvas';
      introContainer.insertBefore(canvas, introContainer.firstChild);
    }

    const finishIntro = () => {
      document.body.classList.add('app-ready');
      const $intro = $('#intro-container');
      $intro.addClass('fade-out');
      setTimeout(() => {
        if ($intro.length) {
          $intro.remove();
        }
      }, 1000);
    };

    let ctx = null;
    try {
      ctx = canvas.getContext('2d');
    } catch (err) {
      console.error('Giriş canvas bağlam hatası:', err);
    }

    if (!ctx) {
      setTimeout(finishIntro, 300);
      return;
    }

    const sizeCanvas = () => {
      canvas.width = window.innerWidth;
      canvas.height = window.innerHeight;
    };

    sizeCanvas();
    window.addEventListener('resize', sizeCanvas, { passive: true });

    const particles = [];
    const particleCount = 300;

    class Particle {
      constructor() {
        this.reset();
      }

      reset() {
        this.x = Math.random() * canvas.width;
        this.y = Math.random() * canvas.height;
        this.vx = (Math.random() - 0.5) * 0.2;
        this.vy = (Math.random() - 0.5) * 0.2;
        this.radius = Math.random() * 1.5 + 0.5;
        const colors = ['rgba(255, 255, 255, 0.9)', 'rgba(200, 220, 255, 0.8)', 'rgba(150, 180, 255, 0.7)'];
        this.color = colors[Math.floor(Math.random() * colors.length)];
      }

      update() {
        this.x += this.vx;
        this.y += this.vy;
        if (this.x < 0 || this.x > canvas.width) this.vx *= -1;
        if (this.y < 0 || this.y > canvas.height) this.vy *= -1;
      }

      draw() {
        ctx.beginPath();
        ctx.arc(this.x, this.y, this.radius, 0, Math.PI * 2);
        ctx.fillStyle = this.color;
        ctx.fill();
      }
    }

    for (let i = 0; i < particleCount; i++) {
      particles.push(new Particle());
    }

    const animate = () => {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      particles.forEach(p => { p.update(); p.draw(); });

      for (let i = 0; i < particles.length; i++) {
        for (let j = i + 1; j < particles.length; j++) {
          const distance = Math.hypot(particles[i].x - particles[j].x, particles[i].y - particles[j].y);
          if (distance < 150) {
            ctx.beginPath();
            ctx.moveTo(particles[i].x, particles[i].y);
            ctx.lineTo(particles[j].x, particles[j].y);
            ctx.strokeStyle = `rgba(150, 180, 255, ${(1 - distance / 150) * 0.5})`;
            ctx.lineWidth = 1.2;
            ctx.stroke();
          }
        }
      }
      requestAnimationFrame(animate);
    };

    animate();

    setTimeout(finishIntro, 500);
  }

  initIntro();
});