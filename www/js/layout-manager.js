// www/js/layout-manager.js
(function() {
  'use strict';

  let isWidescreenMode = false;
  
  function applyWidescreen(enabled, scopeEl) {
    isWidescreenMode = !!enabled;
  
    const $scope = scopeEl ? $(scopeEl) : $(document);
  
    const $chat = $scope.find('.chat-container').length ? $scope.find('.chat-container') : $('.chat-container');
    const $input = $scope.find('.input-container').length ? $scope.find('.input-container') : $('.input-container');
    const $content = $scope.find('.content-wrapper').length ? $scope.find('.content-wrapper') : $('.content-wrapper');
    const $chatContentWrapper = $scope.find('.chat-content-wrapper').length ? $scope.find('.chat-content-wrapper') : $('.chat-content-wrapper');
  
    if (enabled) {
      $chat.addClass('widescreen-mode');
      $input.addClass('widescreen-mode');
      $content.addClass('widescreen-mode');
      $chatContentWrapper.addClass('widescreen').removeClass('normal-screen');
    } else {
      $chat.removeClass('widescreen-mode');
      $input.removeClass('widescreen-mode');
      $content.removeClass('widescreen-mode');
      $chatContentWrapper.removeClass('widescreen').addClass('normal-screen');
    }
  
    updateMessageWrappersForWidescreen($scope);
  }
  
	function updateMessageWrappersForWidescreen(scopeEl) {
	  // Artık gerekli değil, CSS .chat-container sınıfına göre çalışıyor
	}

  // Export
  window.applyWidescreen = applyWidescreen;
  window.updateMessageWrappersForWidescreen = updateMessageWrappersForWidescreen;
  window.isWidescreenMode = function() { return isWidescreenMode; };
})();