$(document).ready(function() {
  var ttsTimer = null;
  var $viz = $('#tts_viz_container');
  var $name = $viz.find('.tts-char-name');
  var $barElements = $viz.find('.tts-bar');

  function setState(state) {
    $viz.removeClass('is-talking is-paused is-idle');

    if (state === 'talking') {
      $viz.addClass('is-talking is-ready');
    } else if (state === 'paused') {
      $viz.addClass('is-paused is-ready');
    } else if (state === 'idle') {
      $viz.addClass('is-idle is-ready');
    }
  }

  // Expose a lightweight helper to manage state from other scripts
  window.ttsVisualizerState = {
    setTalking: function() { setState('talking'); },
    setPaused: function() { setState('paused'); },
    setIdle: function() { setState('idle'); },
    stop: function() {
      $viz.removeClass('is-talking is-paused is-idle is-ready');
      if (ttsTimer) clearTimeout(ttsTimer);
    }
  };

  Shiny.addCustomMessageHandler('updateTTSVisualizer', function(message) {
    // message: { state: 'talking'|'stop'|'idle'|'paused', duration: float, name: string, color: string }
    if (!$viz.length) return;

    // Update content & style
    if (message.name) $name.text(message.name);

    if (message.color) {
      $viz.css('--tts-accent', message.color);
    }

    // Set state classes
    if (message.state === 'talking') {
      setState('talking');

      if (ttsTimer) clearTimeout(ttsTimer);
      if (message.duration > 0) {
        var timeoutMs = (message.duration * 1000) + 500;
        ttsTimer = setTimeout(function() {
          setState('idle');
        }, timeoutMs);
      }
    } else if (message.state === 'paused') {
      setState('paused');
    } else if (message.state === 'idle') {
      setState('idle');
      if (ttsTimer) clearTimeout(ttsTimer);
    } else {
      // stop
      window.ttsVisualizerState.stop();
    }
  });
});