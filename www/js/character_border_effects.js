// www/js/character_border_effects.js

const CharacterBorderEffects = {
    canvas: null,
    ctx: null,
    width: 0,
    height: 0,
    animationFrame: null,
    particles: [],
    
    // Default colors (will be updated by R)
    colors: {
        accent: '#7C4DFF',       // Default Purple
        accent_hover: '#9965f4',
        accent_active: '#6020ff'
    },

    config: {
        particleCount: 40,
        borderWidth: 2,
        glowBlur: 15
    },

    init: function(options) {
        // 1. Setup Canvas
        this.canvas = document.getElementById(options.canvasId || 'character-border-canvas');
        if (!this.canvas) return;
        
        this.ctx = this.canvas.getContext('2d');
        
        // 2. Setup Resize Observer to handle window changes
        const container = this.canvas.parentElement;
        this.resizeObserver = new ResizeObserver(() => this.resize());
        this.resizeObserver.observe(container);
        
        // 3. Initial Resize & Start
        this.resize();
        this.initParticles();
        this.startAnimation();

        // 4. Listen for Shiny messages to update colors
        if (window.Shiny) {
            Shiny.addCustomMessageHandler('updateCharacterBorderColors', (data) => {
                this.updateTheme(data);
            });
        }
    },

    resize: function() {
        if (!this.canvas) return;
        const rect = this.canvas.parentElement.getBoundingClientRect();
        this.canvas.width = rect.width;
        this.canvas.height = rect.height;
        this.width = rect.width;
        this.height = rect.height;
    },

    updateTheme: function(colorData) {
        if (colorData && colorData.accent) {
            this.colors.accent = colorData.accent;
            this.colors.accent_hover = colorData.accent_hover || colorData.accent;
            this.colors.accent_active = colorData.accent_active || colorData.accent;
        }
    },

    initParticles: function() {
        this.particles = [];
        for (let i = 0; i < this.config.particleCount; i++) {
            this.particles.push({
                x: Math.random() * this.width,
                y: Math.random() * this.height,
                vx: (Math.random() - 0.5) * 1.5,
                vy: (Math.random() - 0.5) * 1.5,
                size: Math.random() * 2 + 1,
                life: Math.random(),
                maxLife: 1 + Math.random()
            });
        }
    },

    draw: function() {
        if (!this.ctx) return;

        // Clear canvas
        this.ctx.clearRect(0, 0, this.width, this.height);

        // 1. Draw Glowing Border
        this.ctx.save();
        this.ctx.strokeStyle = this.colors.accent;
        this.ctx.lineWidth = this.config.borderWidth;
        this.ctx.lineJoin = "round";
        this.ctx.shadowColor = this.colors.accent;
        this.ctx.shadowBlur = this.config.glowBlur;
        
        // Draw rectangle path
        this.ctx.strokeRect(0, 0, this.width, this.height);
        
        // Double stroke for extra intensity
        this.ctx.globalAlpha = 0.5;
        this.ctx.strokeRect(0, 0, this.width, this.height);
        this.ctx.restore();

        // 2. Update & Draw Particles
        this.ctx.save();
        this.ctx.fillStyle = this.colors.accent;
        
        this.particles.forEach(p => {
            // Update position
            p.x += p.vx;
            p.y += p.vy;
            p.life -= 0.01;

            // Reset dead or out-of-bounds particles
            if (p.life <= 0 || p.x < 0 || p.x > this.width || p.y < 0 || p.y > this.height) {
                // Spawn near the border randomly
                if (Math.random() > 0.5) {
                    p.x = Math.random() > 0.5 ? 0 : this.width;
                    p.y = Math.random() * this.height;
                } else {
                    p.x = Math.random() * this.width;
                    p.y = Math.random() > 0.5 ? 0 : this.height;
                }
                p.vx = (this.width / 2 - p.x) * 0.002; // Drift towards center slightly
                p.vy = (this.height / 2 - p.y) * 0.002;
                p.life = p.maxLife;
            }

            // Draw particle
            this.ctx.globalAlpha = Math.max(0, p.life / p.maxLife) * 0.8;
            this.ctx.beginPath();
            this.ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
            this.ctx.fill();
        });
        
        this.ctx.restore();

        this.animationFrame = requestAnimationFrame(() => this.draw());
    },

    startAnimation: function() {
        if (!this.animationFrame) {
            this.draw();
        }
    }
};