// www/js/character_manager.js

$(document).ready(function() {
  // Karakter butonu yönetimi
  Shiny.addCustomMessageHandler('updateCharacterButtons', function(data) {
    // Tüm butonları sıfırla
    document.querySelectorAll('.character-btn').forEach(btn => {
      btn.classList.remove('active');
      btn.style.removeProperty('--character-active-border');
      btn.style.removeProperty('--character-active-glow');
      btn.style.removeProperty('--character-accent');
      btn.style.removeProperty('--character-accent-strong');
      btn.style.removeProperty('--character-accent-outline');
      btn.style.removeProperty('--character-accent-soft');
      btn.style.removeProperty('--character-accent-glow');
    });

    const activeBtn = document.querySelector(`.character-btn[data-character="${data.character}"]`);
    if (!activeBtn) return;

    activeBtn.classList.add('active');

    const accentBase = data.accent || '#ff8c42';
    const accentActive = data.accent_active || accentBase;
    const accentHover = data.accent_hover || accentActive;

    const hexToRgba = (hex, a) => {
      let c = (hex || '').replace('#', '');
      if (!c) return `rgba(255,140,66,${a})`;
      if (c.length === 3) c = c.split('').map(ch => ch + ch).join('');
      const n = parseInt(c, 16);
      const r = (n >> 16) & 255,
        g = (n >> 8) & 255,
        b = n & 255;
      return `rgba(${r}, ${g}, ${b}, ${a})`;
    };

    activeBtn.style.setProperty('--character-accent', accentBase);
    activeBtn.style.setProperty('--character-accent-strong', accentActive);
    activeBtn.style.setProperty('--character-accent-outline', accentHover);
    activeBtn.style.setProperty('--character-accent-soft', hexToRgba(accentBase, 0.24));
    activeBtn.style.setProperty('--character-accent-glow', hexToRgba(accentHover, 0.48));

    // Neural network animasyonunu karakter rengine gore guncelle
    var neuralCanvas = document.querySelector('.modern-welcome-neural-canvas');
    if (neuralCanvas && window.WelcomeNeuralNetwork) {
      window.WelcomeNeuralNetwork.destroy();
      window.WelcomeNeuralNetwork.init(neuralCanvas, accentBase);
    }
  });

  // Karakter resmi geçişi - video aktifse atla
  Shiny.addCustomMessageHandler('transitionCharacterImage', function(data) {
    const container = document.getElementById(data.containerId);
    if (!container) return;

    // Video overlay aktifse resim geçişini atla
    const videoOverlay = container.querySelector('.character-video-overlay');
    if (videoOverlay && videoOverlay.classList.contains('is-active')) {
      console.log('[Image] Video aktif, resim geçişi atlandı');
      return;
    }

    if (!container.__characterImageState) {
      container.__characterImageState = {
        pendingImage: null
      };
    }

    const state = container.__characterImageState;

    if (state.pendingImage) {
      state.pendingImage.onload = null;
      state.pendingImage.onerror = null;
      state.pendingImage = null;
    }

    const existingImages = Array.from(container.querySelectorAll('.character-image'));
    const incoming = document.createElement('img');
    incoming.className = 'character-image';
    incoming.alt = data.displayName || '';
    if ('decoding' in incoming) {
      incoming.decoding = 'async';
    }

    state.pendingImage = incoming;

    incoming.onload = function() {
      if (state.pendingImage !== incoming) return;
      state.pendingImage = null;

      // Video hala aktifse resmi gösterme
      const currentOverlay = container.querySelector('.character-video-overlay');
      if (currentOverlay && currentOverlay.classList.contains('is-active')) {
        console.log('[Image] Video hala aktif, resim gizli kalacak');
        incoming.style.opacity = '0';
        incoming.style.visibility = 'hidden';
      }

      container.appendChild(incoming);

      existingImages.forEach(function(img) {
        img.classList.remove('is-visible');
        img.classList.add('is-exiting');
      });

      requestAnimationFrame(function() {
        // Video aktif değilse resmi göster
        if (!currentOverlay || !currentOverlay.classList.contains('is-active')) {
          incoming.classList.add('is-visible');
        }

        setTimeout(function() {
          existingImages.forEach(function(img) {
            if (img.parentNode) img.parentNode.removeChild(img);
          });
        }, 1100);
      });
    };

    incoming.onerror = function() {
      if (state.pendingImage === incoming) {
        state.pendingImage = null;
      }
      console.warn('[Image] Yükleme hatası:', data.imageUrl);
    };

    incoming.src = data.imageUrl;
  });

  // Kelime kelime yazma efekti ile karakter bilgisi güncelleme
  Shiny.addCustomMessageHandler('updateCharacterInfoTyping', function(data) {
    const infoArea = document.getElementById(data.infoAreaId);
    if (!infoArea) return;

    const accent = data.accentColor || getComputedStyle(document.documentElement).getPropertyValue('--primary-color');
    infoArea.innerHTML = '';

    const titleDiv = document.createElement('div');
    titleDiv.className = 'character-title';
    titleDiv.style.color = accent;
    titleDiv.style.opacity = '0';
    titleDiv.textContent = data.title || '';
    infoArea.appendChild(titleDiv);

    const bodyWrapper = document.createElement('div');
    bodyWrapper.className = 'character-info-body';

    const loreId = 'character_lore_' + Date.now();
    const loreDiv = document.createElement('div');
    loreDiv.id = loreId;
    loreDiv.className = 'character-lore';
    loreDiv.style.opacity = '0';
    loreDiv.textContent = '';

    const extrasContainer = document.createElement('div');
    extrasContainer.className = 'character-extra-sections is-pending';

    bodyWrapper.appendChild(loreDiv);
    bodyWrapper.appendChild(extrasContainer);
    infoArea.appendChild(bodyWrapper);

    const renderExtras = () => {
      extrasContainer.innerHTML = '';
      const revealables = [];
      const metricFills = [];
      const typingTargets = [];
      let uniqueSeed = Date.now();

      if (typeof data.style === 'string' && data.style.trim().length) {
        const styleCard = document.createElement('div');
        styleCard.className = 'character-style-card';
        styleCard.dataset.reveal = 'block';

        const styleHeading = document.createElement('h5');
        styleHeading.className = 'character-style-heading';
        styleHeading.textContent = 'Yanıt stratejisi';

        const styleBody = document.createElement('p');
        styleBody.className = 'character-style-body';
        const styleId = `character_style_${uniqueSeed++}`;
        styleBody.id = styleId;
        styleBody.textContent = '';
        typingTargets.push({
          id: styleId,
          text: data.style,
          mode: 'word',
          duration: 3200
        });

        styleCard.appendChild(styleHeading);
        styleCard.appendChild(styleBody);
        extrasContainer.appendChild(styleCard);
        revealables.push(styleCard);
      }

      if (Array.isArray(data.metrics) && data.metrics.length) {
        const metricsGrid = document.createElement('div');
        metricsGrid.className = 'character-metrics-grid';

        data.metrics.forEach(metric => {
          if (!metric) return;
          const label = metric.label || '';
          const rawValue = Number(metric.value);
          const value = Number.isFinite(rawValue) ? Math.max(0, Math.min(100, rawValue)) : 0;

          const metricCard = document.createElement('div');
          metricCard.className = 'character-metric';
          metricCard.dataset.reveal = 'metric';

          const header = document.createElement('div');
          header.className = 'character-metric-header';

          const labelSpan = document.createElement('span');
          labelSpan.className = 'character-metric-label';
          labelSpan.textContent = label;

          const valueSpan = document.createElement('span');
          valueSpan.className = 'character-metric-value';
          valueSpan.textContent = `${Math.round(value)}%`;

          header.appendChild(labelSpan);
          header.appendChild(valueSpan);

          const bar = document.createElement('div');
          bar.className = 'character-metric-bar';

          const fill = document.createElement('div');
          fill.className = 'character-metric-bar-fill';
          fill.style.width = '0%';
          fill.dataset.targetWidth = `${value}%`;
          if (accent) {
            fill.style.background = accent;
            fill.style.boxShadow = `0 0 18px ${accent}55`;
          }

          bar.appendChild(fill);

          metricCard.appendChild(header);
          metricCard.appendChild(bar);
          metricsGrid.appendChild(metricCard);
          revealables.push(metricCard);
          metricFills.push(fill);
        });

        extrasContainer.appendChild(metricsGrid);
      }

      if (Array.isArray(data.signatureMoves) && data.signatureMoves.length) {
        const signatureWrapper = document.createElement('div');
        signatureWrapper.className = 'character-signature-wrapper';
        signatureWrapper.dataset.reveal = 'block';

        const signatureHeading = document.createElement('h5');
        signatureHeading.className = 'character-style-heading';
        signatureHeading.textContent = 'Karakterin imzası';

        const list = document.createElement('ul');
        list.className = 'character-signature-list';

        data.signatureMoves.forEach(move => {
          if (!move) return;
          const item = document.createElement('li');
          const span = document.createElement('span');
          const sigId = `character_signature_${uniqueSeed++}`;
          span.id = sigId;
          span.textContent = '';
          typingTargets.push({
            id: sigId,
            text: move,
            mode: 'word',
            duration: 3200
          });
          item.appendChild(span);
          list.appendChild(item);
        });

        signatureWrapper.appendChild(signatureHeading);
        signatureWrapper.appendChild(list);
        extrasContainer.appendChild(signatureWrapper);
        revealables.push(signatureWrapper);
      }

      return {
        revealables,
        metricFills,
        typingTargets
      };
    };

    const extrasState = renderExtras();

    const startExtrasSequence = (() => {
      let started = false;
      return () => {
        if (started) return;
        started = true;
        extrasContainer.classList.remove('is-pending');
        extrasContainer.classList.add('is-ready');

        extrasState.revealables.forEach((el, index) => {
          if (!el) return;
          const delay = Math.min(120, index * 35);
          el.style.transitionDelay = `${delay}ms`;
          requestAnimationFrame(() => {
            el.classList.add('is-visible');
          });
        });

        extrasState.metricFills.forEach((fill) => {
          if (!fill) return;
          const target = fill.dataset.targetWidth || '0%';
          requestAnimationFrame(() => {
            fill.style.width = target;
          });
        });

        extrasState.typingTargets.forEach((target) => {
          const text = target.text || '';
          if (!target.id) return;
          const desiredDuration = Math.max(1200, Number(target.duration) || 2200);
          if (target.mode === 'word' && window.typeCharacterLore) {
            const words = text.match(/\S+/g) || [];
            const delay = words.length > 0 ? Math.max(12, Math.min(40, Math.round(desiredDuration / words.length))) : 0;
            window.typeCharacterLore(text, target.id, delay);
          } else if (window.typeCharacterText) {
            const charCount = text.length;
            const delay = charCount > 0 ? Math.max(8, Math.min(30, Math.round(desiredDuration / charCount))) : 0;
            window.typeCharacterText(target.id, text, delay);
          } else {
            const el = document.getElementById(target.id);
            if (el) el.textContent = text;
          }
        });
      };
    })();

    requestAnimationFrame(() => {
      titleDiv.style.transition = 'opacity 0.4s ease';
      titleDiv.style.opacity = '1';
    });

    const startLoreTyping = () => {
      loreDiv.style.opacity = '1';
      const loreText = data.lore || '';
      startExtrasSequence();

      if (!loreText) {
        loreDiv.textContent = '';
        return;
      }

      const wordCount = (loreText.match(/\S+/g) || []).length;
      const targetDuration = 2200;
      const loreDelay = wordCount > 0 ? Math.max(10, Math.min(32, Math.round(targetDuration / wordCount))) : 0;

      if (window.typeCharacterLore) {
        window.typeCharacterLore(loreText, loreId, loreDelay);
      } else if (window.typeCharacterText) {
        const charDelay = loreText.length > 0 ? Math.max(6, Math.min(20, Math.round(targetDuration / loreText.length))) : 0;
        window.typeCharacterText(loreId, loreText, charDelay);
      } else {
        loreDiv.textContent = loreText;
      }
    };

    setTimeout(startLoreTyping, 280);
  });
});