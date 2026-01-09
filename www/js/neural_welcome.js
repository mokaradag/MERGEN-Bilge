// www/js/neural_welcome.js

// Hoşgeldin Ekranı İçin Sinir Ağı Animasyonu
window.NeuralWelcomeAnimation = {
  canvas: null,
  ctx: null,
  wrapper: null,
  particles: [],
  animationId: null,
  particleCount: 100,
  primaryRGB: { r: 255, g: 107, b: 53 },
  resizeHandler: null,

  init: function(attempt = 0) {
    const container = document.querySelector('.welcome-container');
    if (!container) {
      if (attempt < 10) {
        setTimeout(() => this.init(attempt + 1), 120);
      }
      return;
    }

    if (this.animationId || this.wrapper) {
      this.destroy(true);
    }

    let wrapper = container.querySelector('.neural-background');
    if (!wrapper) {
      wrapper = document.createElement('div');
      wrapper.className = 'neural-background';
      container.insertBefore(wrapper, container.firstChild);
    } else {
      wrapper.className = 'neural-background';
    }

    let canvas = wrapper.querySelector('canvas.neural-canvas-welcome');
    if (!canvas) {
      canvas = document.createElement('canvas');
      canvas.className = 'neural-canvas-welcome';
      wrapper.appendChild(canvas);
    } else {
      canvas.className = 'neural-canvas-welcome';
    }

    this.wrapper = wrapper;
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');

    const cssPrimary = getComputedStyle(document.documentElement).getPropertyValue('--primary-color').trim();
    const hexToRgb = (hex) => {
      let c = (hex || '').replace('#', '');
      if (!c) return { r: 255, g: 107, b: 53 };
      if (c.length === 3) c = c.split('').map(ch => ch + ch).join('');
      const n = parseInt(c, 16);
      if (Number.isNaN(n)) return { r: 255, g: 107, b: 53 };
      return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
    };
    this.primaryRGB = hexToRgb(cssPrimary);

    this.resize();

    if (this.resizeHandler) {
      window.removeEventListener('resize', this.resizeHandler);
    }
    this.resizeHandler = () => this.resize();
    window.addEventListener('resize', this.resizeHandler, { passive: true });

    this.createParticles();
    this.animate();
  },

  resize: function() {
    if (!this.canvas || !this.wrapper) return;
    this.canvas.width = this.wrapper.clientWidth;
    this.canvas.height = this.wrapper.clientHeight;
  },

  createParticles: function() {
    this.particles = [];
    if (!this.canvas) return;
    for (let i = 0; i < this.particleCount; i++) {
      this.particles.push({
        x: Math.random() * this.canvas.width,
        y: Math.random() * this.canvas.height,
        vx: (Math.random() - 0.5) * 0.2,
        vy: (Math.random() - 0.5) * 0.2,
        radius: Math.random() * 1.5 + 0.5,
        opacity: Math.random() * 0.5 + 0.3
      });
    }
  },

  animate: function() {
    if (!this.ctx || !this.canvas) return;
    if (!this.wrapper || !document.body.contains(this.wrapper)) {
      this.destroy(true);
      return;
    }

    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

    this.particles.forEach((p, i) => {
      p.x += p.vx;
      p.y += p.vy;

      if (p.x < 0 || p.x > this.canvas.width) p.vx *= -1;
      if (p.y < 0 || p.y > this.canvas.height) p.vy *= -1;

      this.ctx.beginPath();
      this.ctx.arc(p.x, p.y, p.radius, 0, Math.PI * 2);
      this.ctx.fillStyle = `rgba(${this.primaryRGB.r}, ${this.primaryRGB.g}, ${this.primaryRGB.b}, ${p.opacity})`;
      this.ctx.fill();

      for (let j = i + 1; j < this.particles.length; j++) {
        const p2 = this.particles[j];
        const distance = Math.hypot(p.x - p2.x, p.y - p2.y);

        if (distance < 100) {
          this.ctx.beginPath();
          this.ctx.moveTo(p.x, p.y);
          this.ctx.lineTo(p2.x, p2.y);
          const opacity = (1 - distance / 100) * 0.3;
          this.ctx.strokeStyle = `rgba(${this.primaryRGB.r}, ${this.primaryRGB.g}, ${this.primaryRGB.b}, ${opacity})`;
          this.ctx.lineWidth = 0.5;
          this.ctx.stroke();
        }
      }
    });

    this.animationId = requestAnimationFrame(() => this.animate());
  },

  destroy: function(skipFade) {
    if (this.animationId) {
      cancelAnimationFrame(this.animationId);
      this.animationId = null;
    }

    if (this.resizeHandler) {
      window.removeEventListener('resize', this.resizeHandler);
      this.resizeHandler = null;
    }

    const wrapper = this.wrapper;
    this.wrapper = null;

    if (wrapper) {
      if (skipFade) {
        wrapper.remove();
      } else {
        wrapper.classList.add('fade-out');
        setTimeout(() => {
          if (wrapper.parentNode) {
            wrapper.remove();
          }
        }, 500);
      }
    }

    this.canvas = null;
    this.ctx = null;
    this.particles = [];
  }
};

// Hoşgeldin ekranı göründüğünde sinir ağı animasyonunu başlat
if (window.Shiny) {
  Shiny.addCustomMessageHandler('showNeuralAnimation', function(message) {
    setTimeout(() => {
      if (window.NeuralWelcomeAnimation) window.NeuralWelcomeAnimation.init();
    }, 120);
  });
}

// Sohbet mesajlarını izle ve sohbet başladığında animasyonu sonlandır
document.addEventListener('DOMContentLoaded', function() {
  const chatContainer = document.querySelector('#chat_content_container');
  if (!chatContainer) return;

  let welcomeActive = false;
  const mutationHandler = () => {
    const hasMessages = chatContainer.querySelector('.message-bubble');
    if (hasMessages) {
      welcomeActive = false;
      if (window.NeuralWelcomeAnimation) window.NeuralWelcomeAnimation.destroy();
      return;
    }

    const hasWelcome = !!chatContainer.querySelector('.welcome-container');
    if (hasWelcome && !welcomeActive) {
      welcomeActive = true;
      if (window.NeuralWelcomeAnimation) window.NeuralWelcomeAnimation.init();
    } else if (!hasWelcome && welcomeActive) {
      welcomeActive = false;
      if (window.NeuralWelcomeAnimation) window.NeuralWelcomeAnimation.destroy(true);
    }
  };

	const observer = new MutationObserver(function() {
    mutationHandler();
    
    const hasMessages = chatContainer.querySelector('.message-bubble');
    if (hasMessages) {
      if (window.WelcomeVideoPlayer) window.WelcomeVideoPlayer.destroy();
      if (window.WelcomeNeuralNetwork) window.WelcomeNeuralNetwork.destroy();
      if (window.WelcomeGreeting) window.WelcomeGreeting.destroy();
    }
  });
  
  observer.observe(chatContainer, {
    childList: true,
    subtree: true
  });
});