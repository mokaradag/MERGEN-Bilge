// Dosya Yolu: www/js/welcome_greeting_personal.js
// Açıklama: Kullanıcıya özel karşılama animasyonu.
// Günün saatine göre selamlama, ikon geçişleri (el sallama → zaman ikonu → mikroçip)
// ve döngüsel animasyonları yönetir. Keycloak entegrasyonuna hazır.

window.WelcomePersonalGreeting = (function() {
  'use strict';

  // --- Durum değişkenleri ---
  var _iconBox = null;
  var _titleGroup = null;
  var _greetingText = null;
  var _firstName = '';
  var _phase = 'idle';  // 'idle' | 'greeting' | 'time-icon' | 'intro' | 'cycling'
  var _timeouts = [];
  var _destroyed = false;
  var _isFirstTransition = true; // İlk geçişte küçülme animasyonunu atla
  var _greetingGen = 0;          // Yeniden tetiklemede eski bekleme döngülerini iptal eder

  // --- Saate göre selamlama mesajları ve FontAwesome ikon eşlemeleri ---
  function getTimeBasedGreeting() {
    var hour = new Date().getHours();

    if (hour >= 5 && hour < 12) {
      return {
        greeting: 'Günaydın',
        faIcon: 'fa-sun',              // Güneş ikonu
        iconColor: '#fbbf24',          // Altın sarısı
        iconGlow: 'rgba(251, 191, 36, 0.5)',
        period: 'morning'
      };
    } else if (hour >= 12 && hour < 17) {
      return {
        greeting: 'İyi günler',
        faIcon: 'fa-cloud-sun',        // Bulutlu güneş
        iconColor: '#f97316',          // Turuncu
        iconGlow: 'rgba(249, 115, 22, 0.5)',
        period: 'afternoon'
      };
    } else if (hour >= 17 && hour < 21) {
      return {
        greeting: 'İyi akşamlar',
        faIcon: 'fa-cloud-moon',       // Akşam bulut-ay
        iconColor: '#a78bfa',          // Mor
        iconGlow: 'rgba(167, 139, 250, 0.5)',
        period: 'evening'
      };
    } else {
      return {
        greeting: 'İyi geceler',
        faIcon: 'fa-moon',             // Ay ikonu
        iconColor: '#818cf8',          // İndigo
        iconGlow: 'rgba(129, 140, 248, 0.5)',
        period: 'night'
      };
    }
  }

  // --- İkon geçiş animasyonu ---
  function animateIconTransition(iconClass, extraClass, customColor, customGlow) {
    if (_destroyed || !_iconBox) return;

    var icon = _iconBox.querySelector('.modern-welcome-icon');
    if (!icon) return;

    // İlk geçişte küçülme gecikmesini atla — doğrudan ikonu değiştir
    if (_isFirstTransition) {
      _isFirstTransition = false;

      icon.className = 'modern-welcome-icon fas ' + iconClass;
      if (extraClass) {
        icon.classList.add(extraClass);
      }
      if (customColor) {
        icon.style.color = customColor;
        icon.style.filter = 'drop-shadow(0 0 10px ' + (customGlow || customColor) + ')';
      } else {
        icon.style.color = '';
        icon.style.filter = '';
      }

      _iconBox.classList.add('icon-transition-in');
      _setTimeout(function() {
        if (!_destroyed && _iconBox) {
          _iconBox.classList.remove('icon-transition-in');
        }
      }, 500);
      return;
    }

    // Sonraki geçişlerde: mevcut ikonu küçült, sonra değiştir
    _iconBox.classList.add('icon-transition-out');

    _setTimeout(function() {
      if (_destroyed || !icon) return;

      // İkon sınıflarını değiştir
      icon.className = 'modern-welcome-icon fas ' + iconClass;
      if (extraClass) {
        icon.classList.add(extraClass);
      }

      // Özel renk uygula (zaman ikonu için)
      if (customColor) {
        icon.style.color = customColor;
        icon.style.filter = 'drop-shadow(0 0 10px ' + (customGlow || customColor) + ')';
      } else {
        icon.style.color = '';
        icon.style.filter = '';
      }

      // Yeni ikonu büyüt
      _iconBox.classList.remove('icon-transition-out');
      _iconBox.classList.add('icon-transition-in');

      _setTimeout(function() {
        if (!_destroyed && _iconBox) {
          _iconBox.classList.remove('icon-transition-in');
        }
      }, 500);
    }, 350);
  }

  // --- Branding başlığını güncelle ---
  function updateBrandingTitle(html) {
    if (_destroyed || !_titleGroup) return;

    _titleGroup.classList.add('title-fade-out');

    _setTimeout(function() {
      if (_destroyed || !_titleGroup) return;
      _titleGroup.innerHTML = html;
      _titleGroup.classList.remove('title-fade-out');
      _titleGroup.classList.add('title-fade-in');

      _setTimeout(function() {
        if (!_destroyed && _titleGroup) {
          _titleGroup.classList.remove('title-fade-in');
        }
      }, 600);
    }, 400);
  }

  // --- Güvenli setTimeout sarmalayıcı ---
  function _setTimeout(fn, delay) {
    var id = setTimeout(function() {
      if (!_destroyed) fn();
    }, delay);
    _timeouts.push(id);
    return id;
  }

  // --- Karşılama HTML oluştur (virgül gradient renginde) ---
  function buildGreetingHtml(timeInfo, firstName) {
    // Virgül, selamlama metniyle birlikte gradient renginde
    var greetingWithComma = firstName
      ? (timeInfo.greeting + ',')
      : timeInfo.greeting;
    var nameText = firstName ? (' ' + firstName + '!') : '!';

    return '<h1 class="personal-greeting-title">' +
      '<span class="greeting-time-text">' + greetingWithComma + '</span>' +
      '<span class="greeting-name-text">' + nameText + '</span>' +
      '</h1>';
  }

  // --- MERGEN Bilge HTML ---
  function buildMergenHtml() {
    return '<h1>' +
      'MERGEN ' +
      '<span class="modern-welcome-title-accent">Bilge</span>' +
      '</h1>';
  }

  // --- Ana animasyon dizisi ---
  function startGreetingSequence(firstName) {
    if (_destroyed) return;
    _firstName = firstName || '';
    _phase = 'greeting';

    var timeInfo = getTimeBasedGreeting();

    // ═══════════════════════════════════════════
    // FAZ 1: El sallama + kullanıcı selamlama (0ms)
    // ═══════════════════════════════════════════
    animateIconTransition('fa-hand-sparkles', 'icon-wave-anim', null, null);
    updateBrandingTitle(buildGreetingHtml(timeInfo, _firstName));

    // ═══════════════════════════════════════════
    // FAZ 2: Zaman ikonu (2.5sn sonra) - başlık değişmez
    // ═══════════════════════════════════════════
    _setTimeout(function() {
      if (_destroyed) return;
      _phase = 'time-icon';

      animateIconTransition(
        timeInfo.faIcon,
        'icon-time-glow',
        timeInfo.iconColor,
        timeInfo.iconGlow
      );
      // Başlık değişmez, selamlama metni kalır
    }, 2500);

    // ═══════════════════════════════════════════
    // FAZ 3: Mikroçip + MERGEN Bilge (5.5sn sonra)
    // ═══════════════════════════════════════════
    _setTimeout(function() {
      if (_destroyed) return;
      _phase = 'intro';

      animateIconTransition('fa-microchip', 'icon-pulse-glow', null, null);
      updateBrandingTitle(buildMergenHtml());
    }, 5500);

    // ═══════════════════════════════════════════
    // FAZ 4: Döngüsel geçiş başlat (12sn sonra)
    // ═══════════════════════════════════════════
    _setTimeout(function() {
      if (_destroyed) return;
      _phase = 'cycling';
      startCycling();
    }, 12000);
  }

  // --- Döngüsel geçiş: Selamlama (el sallama→zaman ikonu) ↔ MERGEN Bilge ---
  function startCycling() {
    if (_destroyed || _phase !== 'cycling') return;

    var showGreeting = true;
    var timeInfo = getTimeBasedGreeting();

    function cycle() {
      if (_destroyed || _phase !== 'cycling') return;

      if (showGreeting) {
        // Selamlama fazı: önce el sallama
        animateIconTransition('fa-hand-sparkles', 'icon-wave-anim', null, null);
        updateBrandingTitle(buildGreetingHtml(timeInfo, _firstName));

        // 2.5sn sonra zaman ikonuna geç (başlık değişmez)
        _setTimeout(function() {
          if (_destroyed || _phase !== 'cycling') return;
          animateIconTransition(
            timeInfo.faIcon,
            'icon-time-glow',
            timeInfo.iconColor,
            timeInfo.iconGlow
          );
        }, 2500);

      } else {
        // MERGEN Bilge fazı
        animateIconTransition('fa-microchip', 'icon-pulse-glow', null, null);
        updateBrandingTitle(buildMergenHtml());
      }

      showGreeting = !showGreeting;
      _setTimeout(cycle, 8000);
    }

    cycle();
  }

  // --- Shiny mesaj işleyici ---
  function registerShinyHandler(attempt) {
    attempt = attempt || 0;

    if (window.MERGEN_PERSONAL_GREETING_HANDLER_REGISTERED) {
      return;
    }

    if (typeof Shiny === 'undefined' ||
        typeof Shiny.addCustomMessageHandler !== 'function') {
      if (attempt < 80) {
        window.setTimeout(function() {
          registerShinyHandler(attempt + 1);
        }, 50);
      }
      return;
    }

    window.MERGEN_PERSONAL_GREETING_HANDLER_REGISTERED = true;

    Shiny.addCustomMessageHandler('initPersonalGreeting', function(data) {
      destroy();
      _destroyed = false;

      var firstName = (data && data.first_name) ? data.first_name : '';
      _greetingGen++;
      var myGen = _greetingGen;

      // Karşılama ekranı görünür olana kadar bekle. Deep-space kapanışı
      // sırasında veya 0-boyutlu karşılama ekranında selamlama fazları
      // gizliyken akıp gitmemeli; kullanıcı 1. fazı (el sallama) kaçırmamalı.
      var attempts = 0;
      function beginGreeting() {
        if (_destroyed || myGen !== _greetingGen) return;

        var iconBox = document.querySelector('.modern-welcome-icon-box');
        var titleGroup = document.querySelector('.modern-welcome-title-group');
        var visible = !!(iconBox && titleGroup && iconBox.offsetParent !== null);

        if (!visible && attempts < 80) {
          attempts++;
          _setTimeout(beginGreeting, 60);
          return;
        }
        if (!iconBox || !titleGroup) return;

        _iconBox = iconBox;
        _titleGroup = titleGroup;
        _greetingText = document.getElementById('dynamic-greeting-text');

        _iconBox.classList.add('personal-icon-animated');
        _titleGroup.classList.add('personal-title-animated');

        startGreetingSequence(firstName);
      }

      beginGreeting();
    });
  }

  // --- Temizleme ---
  function destroy() {
    _destroyed = true;
    _phase = 'idle';

    _timeouts.forEach(function(id) { clearTimeout(id); });
    _timeouts = [];

    if (_iconBox) {
      _iconBox.classList.remove('personal-icon-animated', 'icon-transition-out', 'icon-transition-in');
      var icon = _iconBox.querySelector('.modern-welcome-icon');
      if (icon) {
        icon.style.color = '';
        icon.style.filter = '';
      }
    }
    if (_titleGroup) {
      _titleGroup.classList.remove('personal-title-animated', 'title-fade-out', 'title-fade-in');
    }

    _iconBox = null;
    _titleGroup = null;
    _greetingText = null;
	_firstName = '';
    _isFirstTransition = true;
  }

  // --- Başlatma ---
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() {
      registerShinyHandler(0);
    });
  } else {
    registerShinyHandler(0);
  }

  return {
    destroy: destroy,
    getTimeBasedGreeting: getTimeBasedGreeting
  };
})();