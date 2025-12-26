// www/js/typing_animation.js

// Gelişmiş Yazma Animasyonu Yöneticisi (FIX #5 ile: daha büyük metin)
window.TypingAnimationManager = {
  instance: null,
  timers: [],

  create: function(wrapper) {
    this.destroy();

    // FIX #5: Daha büyük metin içeren geliştirilmiş yapı
    const animationHTML = `
      <div class="stage" id="typing-stage">
        <div class="animation-container">
          <div class="ring ring-large" aria-hidden="true">
            <svg viewBox="0 0 100 100" preserveAspectRatio="xMidYMid meet">
              <circle class="track" cx="50" cy="50" r="44"></circle>
              <g class="rotator">
                <circle class="tail" cx="50" cy="50" r="44"></circle>
              </g>
            </svg>
            <div class="label label-large" role="status" aria-live="polite">
              <span>D</span><span>ü</span><span>ş</span><span>ü</span><span>n</span><span>ü</span><span>y</span><span>o</span><span>r</span><span>u</span><span>m</span>
            </div>
          </div>
        </div>
        <div class="name-wrap">
          <div class="name-particles" id="nameParticles" aria-hidden="true"></div>
          <div class="ai-name ai-name-large" id="filmRoll">
            <div class="word" aria-label="MERGEN">
              <span class="letter">M</span><span class="letter">E</span><span class="letter">R</span>
              <span class="letter">G</span><span class="letter">E</span><span class="letter">N</span>
            </div>
            <div class="word" aria-label="Bilge">
              <span class="letter">B</span><span class="letter">i</span><span class="letter">l</span>
              <span class="letter">g</span><span class="letter">e</span>
            </div>
          </div>
        </div>
      </div>
    `;

    wrapper.innerHTML = animationHTML;
    this.initAnimation();
  },

  initAnimation: function() {
    const prefersReduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (prefersReduced) return;

    const root = document.getElementById('filmRoll');
    const layer = document.getElementById('nameParticles');
    if (!root || !layer) return;

    const letters = Array.from(root.querySelectorAll('.letter'));
    const PARTICLES = 6;
    const IN_STAGGER = 80;
    const IN_DUR = 420;
    const HOLD_TIME = 1200;
    const OUT_STAGGER = 90;
    const OUT_DUR = 420;

    const self = this;

    function rand(min, max) { return Math.random() * (max - min) + min; }

    function resetSpark(el) {
      const rect = layer.getBoundingClientRect();
      const w = rect.width || layer.clientWidth;
      const h = rect.height || layer.clientHeight;

      const leftPct = (rand(0, w) / w) * 100;
      const topPct = (rand(0, h) / h) * 100;
      const size = rand(2, 4).toFixed(1) + 'px';
      const scale = (0.7 + Math.random() * 0.7).toFixed(2);
      const dx = rand(-18, 18).toFixed(1) + 'px';
      const dy = rand(-14, 14).toFixed(1) + 'px';
      const dur = rand(2.2, 3.6).toFixed(2) + 's';
      const delay = rand(0, 1.0).toFixed(2) + 's';

      el.style.setProperty('--left', leftPct + '%');
      el.style.setProperty('--top', topPct + '%');
      el.style.setProperty('--size', size);
      el.style.setProperty('--dx', dx);
      el.style.setProperty('--dy', dy);
      el.style.setProperty('--scale', scale);
      el.style.animationDuration = dur + ', 8s';
      el.style.animationDelay = delay + ', 0s';
    }

    function createSpark() {
      const s = document.createElement('span');
      s.className = 'spark';
      resetSpark(s);
      s.addEventListener('animationiteration', (e) => {
        if (e.animationName === 'sparkDrift') resetSpark(s);
      });
      return s;
    }

    function seedParticles() {
      layer.innerHTML = '';
      for (let i = 0; i < PARTICLES; i++) {
        layer.appendChild(createSpark());
      }
    }

    function setT(fn, ms) {
      const t = setTimeout(fn, ms);
      self.timers.push(t);
      return t;
    }

    function resetInState() {
      const shift = '40px';
      letters.forEach(el => {
        el.style.transition = 'none';
        el.style.transform = `translateX(${shift})`;
        el.style.opacity = '0';
      });
      void root.offsetHeight;
      letters.forEach(el => {
        el.style.transition = 'transform 420ms cubic-bezier(.22,.61,.36,1), opacity 300ms ease';
      });
    }

    function animateIn() {
      resetInState();
      letters.forEach((el, i) => {
        setT(() => {
          el.style.transform = 'translateX(0)';
          el.style.opacity = '1';
        }, i * IN_STAGGER);
      });
      return (letters.length - 1) * IN_STAGGER + IN_DUR;
    }

    function animateOut() {
      letters.forEach((el, i) => {
        setT(() => {
          el.style.transform = 'translateX(-150%)';
          el.style.opacity = '0';
        }, i * OUT_STAGGER);
      });
      return (letters.length - 1) * OUT_STAGGER + OUT_DUR;
    }

    function cycle() {
      const inTime = animateIn();
      setT(() => {
        setT(() => {
          const outTime = animateOut();
          setT(cycle, outTime + 200);
        }, HOLD_TIME);
      }, inTime + 50);
    }

    seedParticles();
    cycle();

    this.instance = { root, layer, letters };
  },

  destroy: function() {
    this.timers.forEach(clearTimeout);
    this.timers = [];
    this.instance = null;
  }
};