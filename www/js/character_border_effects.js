// www/js/character_border_effects.js

const CharacterBorderEffects = {
    canvas: null,
    ctx: null,
    particles: [],
    animationFrame: null,
    config: {
        particleCount: 50,
        particleSpeed: 0.3,
        particleSize: 2,
        glowIntensity: 0.8
    },
    currentColors: {
        accent: '#7C4DFF',
        accentHover: '#8E66FF',
        accentActive: '#6A3BE6'
    },

    init: function(canvasId, colors) {
        this.canvas = document.getElementById(canvasId);
        if (!this.canvas) return;

        this.ctx = this.canvas.getContext('2d');
        this.currentColors = colors || this.currentColors;
        
        this.resizeCanvas();
        this.initParticles();
        this.startAnimation();

        window.addEventListener('resize', () => this.resizeCanvas());
    },

    resizeCanvas: function() {
        if (!this.canvas) return;
        const container = this.canvas.parentElement;
        this.canvas.width = container.offsetWidth;
        this.canvas.height = container.offsetHeight;
    },

    initParticles: function() {
        this.particles = [];
        const perimeter = (this.canvas.width + this.canvas.height) * 2;
        const count = Math.floor(perimeter / 15);

        for (let i = 0; i < count; i++) {
            this.particles.push(this.createParticle());
        }
    },

    createParticle: function() {
        const side = Math.floor(Math.random() * 4);
        let x, y, vx, vy;

        switch(side) {
            case 0:
                x = Math.random() * this.canvas.width;
                y = 0;
                vx = (Math.random() - 0.5) * this.config.particleSpeed;
                vy = Math.random() * this.config.particleSpeed;
                break;
            case 1:
                x = this.canvas.width;
                y = Math.random() * this.canvas.height;
                vx = -Math.random() * this.config.particleSpeed;
                vy = (Math.random() - 0.5) * this.config.particleSpeed;
                break;
            case 2:
                x = Math.random() * this.canvas.width;
                y = this.canvas.height;
                vx = (Math.random() - 0.5) * this.config.particleSpeed;
                vy = -Math.random() * this.config.particleSpeed;
                break;
            default:
                x = 0;
                y = Math.random() * this.canvas.height;
                vx = Math.random() * this.config.particleSpeed;
                vy = (Math.random() - 0.5) * this.config.particleSpeed;
        }

        return {
            x: x,
            y: y,
            vx: vx,
            vy: vy,
            life: 1.0,
            maxLife: 1.0,
            size: this.config.particleSize + Math.random() * 2
        };
    },

    updateParticles: function() {
        const margin = 30;
        
        for (let i = this.particles.length - 1; i >= 0; i--) {
            const p = this.particles[i];
            
            p.x += p.vx;
            p.y += p.vy;
            p.life -= 0.005;

            if (p.x < -margin || p.x > this.canvas.width + margin ||
                p.y < -margin || p.y > this.canvas.height + margin ||
                p.life <= 0) {
                this.particles.splice(i, 1);
                this.particles.push(this.createParticle());
            }
        }
    },

    drawBorder: function() {
        const w = this.canvas.width;
        const h = this.canvas.height;
        const borderWidth = 4;
        const glowSize = 15;

        this.ctx.shadowBlur = glowSize;
        this.ctx.shadowColor = this.currentColors.accent;

        const gradient = this.ctx.createLinearGradient(0, 0, w, h);
        gradient.addColorStop(0, this.currentColors.accent);
        gradient.addColorStop(0.5, this.currentColors.accentHover);
        gradient.addColorStop(1, this.currentColors.accentActive);

        this.ctx.strokeStyle = gradient;
        this.ctx.lineWidth = borderWidth;
        this.ctx.strokeRect(borderWidth / 2, borderWidth / 2, 
                           w - borderWidth, h - borderWidth);

        this.ctx.shadowBlur = 0;
    },

    drawParticles: function() {
        this.particles.forEach(p => {
            const gradient = this.ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, p.size * 2);
            gradient.addColorStop(0, this.hexToRGBA(this.currentColors.accentHover, p.life));
            gradient.addColorStop(0.5, this.hexToRGBA(this.currentColors.accent, p.life * 0.5));
            gradient.addColorStop(1, this.hexToRGBA(this.currentColors.accent, 0));

            this.ctx.fillStyle = gradient;
            this.ctx.beginPath();
            this.ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
            this.ctx.fill();
        });
    },

    hexToRGBA: function(hex, alpha) {
        const r = parseInt(hex.slice(1, 3), 16);
        const g = parseInt(hex.slice(3, 5), 16);
        const b = parseInt(hex.slice(5, 7), 16);
        return `rgba(${r}, ${g}, ${b}, ${alpha})`;
    },

    animate: function() {
        if (!this.ctx) return;

        this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
        
        this.drawBorder();
        this.updateParticles();
        this.drawParticles();

        this.animationFrame = requestAnimationFrame(() => this.animate());
    },

    startAnimation: function() {
        this.animate();
    },

    stopAnimation: function() {
        if (this.animationFrame) {
            cancelAnimationFrame(this.animationFrame);
            this.animationFrame = null;
        }
    },

    updateColors: function(colors) {
        this.currentColors = colors;
    },

    destroy: function() {
        this.stopAnimation();
        this.particles = [];
        if (this.canvas) {
            this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
        }
    }
};

Shiny.addCustomMessageHandler('updateCharacterBorderColors', function(message) {
    const colors = {
        accent: message.accent,
        accentHover: message.accent_hover,
        accentActive: message.accent_active
    };
    
    CharacterBorderEffects.destroy();
    CharacterBorderEffects.init('character-border-canvas', colors);
});