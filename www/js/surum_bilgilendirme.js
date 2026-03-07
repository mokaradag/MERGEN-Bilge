// www/js/surum_bilgilendirme.js
// Dosya Yolu: www/js/surum_bilgilendirme.js
// Açıklama: Sürüm bilgilendirme modalı ve destek sayfası etkileşim mantığı.
// Giriş ekranındaki bildirim ikonu, sürüm modalı ve
// destek sayfasındaki sürüm içeriğini yönetir.

(function() {
  'use strict';

  // ============================================================
  // SÜRÜM KARTI HTML OLUŞTURMA
  // ============================================================
  function buildVersionCardHTML(version, isCurrent) {
    var html = '<div class="surum-card' + (isCurrent ? ' current' : '') + '">';

    // Başlık satırı
    html += '<div class="surum-card-header">';
    html += '<span class="surum-card-version">v' + escapeHtml(version.version) + '</span>';
    if (version.badge) {
      html += '<span class="surum-card-badge">' + escapeHtml(version.badge) + '</span>';
    }
    html += '<span class="surum-card-date">' + formatDate(version.date) + '</span>';
    html += '</div>';

    // Başlık
    html += '<h4 class="surum-card-title">' + escapeHtml(version.title) + '</h4>';

    // Öne çıkan özellikler
    if (version.highlights && version.highlights.length > 0) {
      html += '<div class="surum-highlights">';
      version.highlights.forEach(function(h) {
        html += '<span class="surum-highlight-tag">' + escapeHtml(h) + '</span>';
      });
      html += '</div>';
    }

    // Detay kategorileri
    if (version.details && version.details.length > 0) {
      version.details.forEach(function(section) {
        html += '<div class="surum-detail-section">';
        html += '<div class="surum-detail-title">';
        html += '<i class="fas fa-' + escapeHtml(section.icon || 'circle') + '"></i>';
        html += escapeHtml(section.category);
        html += '</div>';
        html += '<ul class="surum-detail-list">';
        if (section.items) {
          section.items.forEach(function(item) {
            html += '<li>' + escapeHtml(item) + '</li>';
          });
        }
        html += '</ul>';
        html += '</div>';
      });
    }

    html += '</div>';
    return html;
  }

  // ============================================================
  // SÜRÜM MODALI (GİRİŞ EKRANINDAN)
  // ============================================================
  function openVersionModal() {
    var overlay = document.getElementById('surum-modal-overlay');
    if (overlay) {
      overlay.classList.add('active');
      // Confetti animasyonu
      launchConfetti();
    }
  }

  function closeVersionModal() {
    var overlay = document.getElementById('surum-modal-overlay');
    if (overlay) {
      overlay.classList.remove('active');
    }
  }

  // ============================================================
  // CONFETTI ANİMASYONU
  // ============================================================
  function launchConfetti() {
    var canvas = document.createElement('canvas');
    canvas.className = 'confetti-canvas';
    document.body.appendChild(canvas);
    var ctx = canvas.getContext('2d');
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;

    var particles = [];
    var colors = ['#818cf8', '#34d399', '#f59e0b', '#ec4899', '#8b5cf6', '#06b6d4'];

    // Parçacık oluştur
    for (var i = 0; i < 80; i++) {
      particles.push({
        x: Math.random() * canvas.width,
        y: -20 - Math.random() * 200,
        w: Math.random() * 8 + 4,
        h: Math.random() * 4 + 2,
        color: colors[Math.floor(Math.random() * colors.length)],
        vx: (Math.random() - 0.5) * 3,
        vy: Math.random() * 3 + 2,
        rotation: Math.random() * 360,
        rotSpeed: (Math.random() - 0.5) * 8,
        opacity: 1
      });
    }

    var startTime = Date.now();

    function animateConfetti() {
      var elapsed = Date.now() - startTime;
      // 3 saniye sonra solmaya başla
      if (elapsed > 4000) {
        canvas.remove();
        return;
      }

      ctx.clearRect(0, 0, canvas.width, canvas.height);

      particles.forEach(function(p) {
        p.x += p.vx;
        p.y += p.vy;
        p.vy += 0.05; // Yerçekimi
        p.rotation += p.rotSpeed;

        // 3 saniyeden sonra soldur
        if (elapsed > 3000) {
          p.opacity = Math.max(0, 1 - (elapsed - 3000) / 1000);
        }

        ctx.save();
        ctx.translate(p.x, p.y);
        ctx.rotate(p.rotation * Math.PI / 180);
        ctx.globalAlpha = p.opacity;
        ctx.fillStyle = p.color;
        ctx.fillRect(-p.w / 2, -p.h / 2, p.w, p.h);
        ctx.restore();
      });

      requestAnimationFrame(animateConfetti);
    }

    requestAnimationFrame(animateConfetti);
  }

  // ============================================================
  // DESTEK SAYFASI İÇERİĞİ
  // ============================================================
  function initSurumPage(data) {
    if (!data || !data.versions) return;

    var tabsContainer = document.getElementById(data.tabsId);
    var contentContainer = document.getElementById(data.contentId);
    if (!tabsContainer || !contentContainer) return;

    var versions = data.versions;
    var currentVersion = data.current_version;

    // Sekmeleri oluştur
    tabsContainer.innerHTML = '';
    versions.forEach(function(v, idx) {
      var tab = document.createElement('button');
      tab.className = 'destek-surum-tab' + (idx === 0 ? ' active' : '');
      tab.setAttribute('data-version-id', v.id);
      tab.textContent = 'v' + v.version;
      tab.onclick = function() {
        // Tüm sekmeleri pasif yap
        tabsContainer.querySelectorAll('.destek-surum-tab').forEach(function(t) {
          t.classList.remove('active');
        });
        tab.classList.add('active');
        // İçeriği güncelle
        showVersionContent(contentContainer, v, v.version === currentVersion);
      };
      tabsContainer.appendChild(tab);
    });

    // İlk sürümü göster
    if (versions.length > 0) {
      showVersionContent(contentContainer, versions[0], versions[0].version === currentVersion);
    }
  }

  function showVersionContent(container, version, isCurrent) {
    container.innerHTML = buildVersionCardHTML(version, isCurrent);
  }

  // ============================================================
  // GİRİŞ EKRANI MODAL İÇERİĞİ
  // ============================================================
  function initVersionModal(data) {
    if (!data || !data.versions) return;

    var modalContent = document.getElementById('surum-modal-content');
    if (!modalContent) return;

    var versions = data.versions;
    var currentVersion = data.current_version;

    // Sürüm sekmeleri
    var tabsHTML = '<div class="destek-surum-tabs" id="surum-modal-tabs">';
    versions.forEach(function(v, idx) {
      tabsHTML += '<button class="destek-surum-tab' + (idx === 0 ? ' active' : '') + '" ';
      tabsHTML += 'data-version-id="' + v.id + '">';
      tabsHTML += 'v' + escapeHtml(v.version);
      tabsHTML += '</button>';
    });
    tabsHTML += '</div>';

    // İlk sürümün içeriğini göster
    var contentHTML = '<div id="surum-modal-version-content">';
    if (versions.length > 0) {
      contentHTML += buildVersionCardHTML(versions[0], versions[0].version === currentVersion);
    }
    contentHTML += '</div>';

    modalContent.innerHTML = tabsHTML + contentHTML;

    // Sekme tıklamalarını dinle
    var tabs = modalContent.querySelectorAll('.destek-surum-tab');
    tabs.forEach(function(tab) {
      tab.addEventListener('click', function() {
        tabs.forEach(function(t) { t.classList.remove('active'); });
        tab.classList.add('active');

        var vId = tab.getAttribute('data-version-id');
        var v = versions.find(function(ver) { return ver.id === vId; });
        if (v) {
          var vc = document.getElementById('surum-modal-version-content');
          if (vc) vc.innerHTML = buildVersionCardHTML(v, v.version === currentVersion);
        }
      });
    });
  }

  // ============================================================
  // YARDIMCI FONKSİYONLAR
  // ============================================================
  function escapeHtml(str) {
    if (!str) return '';
    var div = document.createElement('div');
    div.appendChild(document.createTextNode(str));
    return div.innerHTML;
  }

  function formatDate(dateStr) {
    if (!dateStr) return '';
    try {
      var parts = dateStr.split('-');
      var months = [
        'Ocak', 'Subat', 'Mart', 'Nisan', 'Mayis', 'Haziran',
        'Temmuz', 'Agustos', 'Eylul', 'Ekim', 'Kasim', 'Aralik'
      ];
      var day = parseInt(parts[2], 10);
      var month = months[parseInt(parts[1], 10) - 1] || parts[1];
      var year = parts[0];
      return day + ' ' + month + ' ' + year;
    } catch(e) {
      return dateStr;
    }
  }

  // ============================================================
  // OLAY DİNLEYİCİLERİ
  // ============================================================
  $(document).ready(function() {

    // Giriş ekranı bildirim ikonu tıklaması
    $(document).on('click', '.deep-space-version-badge', function(e) {
      e.stopPropagation();
      openVersionModal();
    });

    // Modal kapatma
    $(document).on('click', '.surum-modal-overlay', function(e) {
      if (e.target === this) closeVersionModal();
    });

    $(document).on('click', '.surum-modal-close', function() {
      closeVersionModal();
    });

    // ESC ile kapat
    $(document).on('keydown', function(e) {
      if (e.key === 'Escape') {
        var overlay = document.getElementById('surum-modal-overlay');
        if (overlay && overlay.classList.contains('active')) {
          closeVersionModal();
        }
      }
    });

    // Shiny mesaj dinleyicileri
    if (typeof Shiny !== 'undefined') {
      Shiny.addCustomMessageHandler('initSurumPage', function(data) {
        initSurumPage(data);
      });

      Shiny.addCustomMessageHandler('initVersionModal', function(data) {
        initVersionModal(data);
      });
    }
  });

  // Global erişim
  window.SurumBilgilendirme = {
    openModal: openVersionModal,
    closeModal: closeVersionModal,
    launchConfetti: launchConfetti
  };

})();