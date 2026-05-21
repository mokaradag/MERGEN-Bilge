// =============================================================================
// Dosya Yolu: www/js/welcome_tooltip_manager.js
// Açıklama: Ana Söyleşi hoş geldin ekranındaki hızlı işlem tooltip yönetimi.
// =============================================================================

$(document).ready(function() {
  window.clearAllTooltips = function() {
    $('.custom-tooltip').remove();
    $('.modern-welcome-action-btn').each(function() {
      var t = $(this).data('custom-tooltip');
      if (t) t.remove();
      $(this).removeData('custom-tooltip');
    });
  };

  function storeOriginalTitles() {
    $('.modern-welcome-action-btn').each(function() {
      var title = $(this).attr('title');
      if (title) {
        $(this).data('original-title', title);
        $(this).removeAttr('title');
      }
    });
  }

  storeOriginalTitles();

  var welcomeContainer = document.getElementById('welcome_fullscreen_container');

  var welcomeTitleObserver = new MutationObserver(function() {
    storeOriginalTitles();
  });

  if (welcomeContainer) {
    welcomeTitleObserver.observe(welcomeContainer, {
      childList: true,
      subtree: true
    });
  }

  $(document).on('mouseenter', '.modern-welcome-action-btn', function() {
    var $btn = $(this);

    if (!$btn.data('original-title') && $btn.attr('title')) {
      $btn.data('original-title', $btn.attr('title'));
      $btn.removeAttr('title');
    }

    var title = $btn.data('original-title');
    if (!title || title.trim() === '') return;

    var existing = $btn.data('custom-tooltip');
    if (existing) existing.remove();

    var parts = title.split('\n\n');
    var tooltipTitle = parts[0] || '';
    var tooltipDesc = parts.slice(1).join('\n\n') || '';

    var themeR = $btn.css('--theme-r') || getComputedStyle(this).getPropertyValue('--theme-r').trim();
    var themeG = $btn.css('--theme-g') || getComputedStyle(this).getPropertyValue('--theme-g').trim();
    var themeB = $btn.css('--theme-b') || getComputedStyle(this).getPropertyValue('--theme-b').trim();

    var themeColor = 'rgb(' + themeR + ',' + themeG + ',' + themeB + ')';
    var themeBorderColor = 'rgba(' + themeR + ',' + themeG + ',' + themeB + ', 0.25)';

    var tooltipHtml =
      '<div style="font-size:14px;font-weight:700;color:' + themeColor + ';margin-bottom:6px;letter-spacing:-0.01em;">' +
        $('<span>').text(tooltipTitle).html() +
      '</div>' +
      (tooltipDesc ? '<div style="font-size:12.5px;color:rgba(255,255,255,0.7);line-height:1.5;">' +
        $('<span>').text(tooltipDesc).html() +
      '</div>' : '');

    var tooltip = $('<div class="custom-tooltip"></div>')
      .html(tooltipHtml)
      .css({
        position: 'fixed',
        'z-index': '9999',
        background: 'linear-gradient(135deg, rgba(15, 15, 20, 0.97) 0%, rgba(10, 10, 15, 0.97) 100%)',
        padding: '12px 16px',
        'border-radius': '12px',
        'max-width': '300px',
        'word-wrap': 'break-word',
        border: '1px solid ' + themeBorderColor,
        'backdrop-filter': 'blur(20px)',
        'box-shadow': '0 12px 32px rgba(0, 0, 0, 0.5), 0 0 0 1px rgba(255,255,255,0.04), inset 0 1px 0 rgba(255,255,255,0.04)',
        'pointer-events': 'none'
      })
      .appendTo('body');

    var btnRect = this.getBoundingClientRect();
    tooltip.css({
      top: (btnRect.top - tooltip.outerHeight() - 12) + 'px',
      left: (btnRect.left + (btnRect.width / 2) - (tooltip.outerWidth() / 2)) + 'px'
    });

    $btn.data('custom-tooltip', tooltip);
  });

  $(document).on('mouseleave', '.modern-welcome-action-btn', function() {
    var tooltip = $(this).data('custom-tooltip');
    if (tooltip) {
      tooltip.remove();
      $(this).removeData('custom-tooltip');
    }
  });

  $(document).on('mousedown click', '.modern-welcome-action-btn', function() {
    window.clearAllTooltips();
  });

  $(document).on('click', '.sidebar-menu a, .nav-tabs a, [data-toggle="tab"]', function() {
    window.clearAllTooltips();
  });

  $(document).on('shiny:inputchanged', function(event) {
    if (event.name === 'quick_template' || event.name === 'tabs') {
      window.clearAllTooltips();
    }
  });

  $(document).on('shiny:visualchange', function() {
    var $welcome = $('#welcome_fullscreen_container');
    if ($welcome.length > 0 && $welcome.is(':visible')) {
      window.clearAllTooltips();
    }
  });

  var welcomeVisObserver = new MutationObserver(function(mutations) {
    mutations.forEach(function(mutation) {
      var target = mutation.target;
      if (target.classList && (target.classList.contains('hidden') || target.style.display === 'none')) {
        window.clearAllTooltips();
      }
    });
  });

  if (welcomeContainer) {
    welcomeVisObserver.observe(welcomeContainer, {
      attributes: true,
      attributeFilter: ['class', 'style']
    });
  }

  setInterval(function() {
    var tooltips = $('.custom-tooltip');
    if (tooltips.length === 0) return;

    var $welcome = $('#welcome_fullscreen_container');
    var welcomeHidden = $welcome.hasClass('hidden') ||
                        $welcome.css('display') === 'none' ||
                        $welcome.children().length === 0;

    if (welcomeHidden) {
      window.clearAllTooltips();
      return;
    }

    var hoveredBtn = $('.modern-welcome-action-btn:hover');
    if (hoveredBtn.length === 0) {
      window.clearAllTooltips();
    }
  }, 300);
});