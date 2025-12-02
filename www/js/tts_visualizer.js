$(document).ready(function() {
  var ttsTimer = null;

  Shiny.addCustomMessageHandler('updateTTSVisualizer', function(message) {
    // message: { state: 'play'|'stop', duration: float, name: string, color: string }
    var $viz = $('#tts_viz_container');
    var $name = $viz.find('.tts-char-name');
    var $bars = $viz.find('.tts-bars');
    var $barElements = $viz.find('.tts-bar');
    
    if (message.state === 'play') {
      // 1. Update Content & Style
      if (message.name) $name.text(message.name);
      
      if (message.color) {
        $name.css('color', message.color);
        // Apply color to bars and their shadow
        $barElements.css({
          'background-color': message.color,
          'box-shadow': '0 0 6px ' + message.color
        });
        
        $viz.css({
          'border-color': message.color + '40', // 25% opacity
          'box-shadow': '0 0 15px ' + message.color + '15' // soft glow
        });
      }
      
      // 2. Activate
      $viz.addClass('active');
      
      // 3. Set Auto-Stop Timer based on audio duration
      if (ttsTimer) clearTimeout(ttsTimer);
      if (message.duration > 0) {
        // Add a small buffer (e.g., 0.5s) to the duration
        var timeoutMs = (message.duration * 1000) + 500;
        ttsTimer = setTimeout(function() {
          $viz.removeClass('active');
        }, timeoutMs);
      }
      
    } else {
      // Stop immediately
      $viz.removeClass('active');
      if (ttsTimer) clearTimeout(ttsTimer);
    }
  });
});