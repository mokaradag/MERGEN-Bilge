// www/js/audio_lifecycle_guard.js
// Dosya Yolu: www/js/audio_lifecycle_guard.js
// Açıklama: TTS, STT, AI Uzman ve intro/main müzik geçişleri için küçük
//           sahiplik tabanlı ses yaşam döngüsü koruması.

(function() {
  'use strict';

  var duckOwners = {};
  var lastLogAt = {};

  function normalizeOwner(owner) {
    owner = owner || 'external_audio';
    return String(owner);
  }

  function ownerList() {
    return Object.keys(duckOwners).filter(function(owner) {
      return duckOwners[owner];
    });
  }

  function getMusicManager() {
    return window.MusicManager || null;
  }

  function logThrottled(level, key, args, throttleMs) {
    throttleMs = throttleMs || 1200;
    var now = Date.now();
    if (lastLogAt[key] && (now - lastLogAt[key]) < throttleMs) {
      return;
    }
    lastLogAt[key] = now;

    var logger = console[level] || console.log;
    try {
      logger.apply(console, ['[AUDIO-LIFE]'].concat(args || []));
    } catch(e) {}
  }

  function applyMusicDuckState() {
    var manager = getMusicManager();
    if (!manager || !manager.state) return;

    var owners = ownerList();
    var hasOwners = owners.length > 0;
    var sttActive = owners.indexOf('stt') >= 0;

    manager.state._sttActive = sttActive;
    manager.state.isDucked = hasOwners;

    if (!manager._audio || !manager.state.enabled) return;

    var targetVolume = manager.state.normalVolume;
    var duration = 600;

    if (sttActive) {
      targetVolume = 0;
      duration = 300;
    } else if (hasOwners) {
      targetVolume = Math.max(
        0.02,
        manager.state.normalVolume * manager.config.duckedVolumeRatio
      );
    }

    if (typeof manager._fadeToVolume === 'function') {
      manager._fadeToVolume(manager._audio, targetVolume, duration);
    }
  }

  function duck(owner) {
    owner = normalizeOwner(owner);
    if (duckOwners[owner]) {
      return;
    }

    duckOwners[owner] = true;
    applyMusicDuckState();

    logThrottled('log', 'duck:' + owner, [
      'duck',
      owner,
      '| owners:',
      ownerList().join(',')
    ]);
  }

  function release(owner) {
    owner = normalizeOwner(owner);
    if (!duckOwners[owner]) {
      return;
    }

    delete duckOwners[owner];
    applyMusicDuckState();

    logThrottled('log', 'release:' + owner, [
      'release',
      owner,
      '| owners:',
      ownerList().join(',')
    ]);
  }

  function releaseMany(owners, reason) {
    var changed = false;
    owners.forEach(function(owner) {
      owner = normalizeOwner(owner);
      if (duckOwners[owner]) {
        delete duckOwners[owner];
        changed = true;
      }
    });

    if (changed) {
      applyMusicDuckState();
      logThrottled('log', 'releaseMany:' + reason, [
        'releaseMany',
        reason || '',
        '| owners:',
        ownerList().join(',')
      ]);
    }
  }

  function releaseAll(reason) {
    if (ownerList().length === 0) return;
    duckOwners = {};
    applyMusicDuckState();
    logThrottled('log', 'releaseAll:' + reason, ['releaseAll', reason || '']);
  }

  function stopIntroBeforeMain(callback) {
    var doneCalled = false;

    function done() {
      if (doneCalled) return;
      doneCalled = true;
      if (typeof callback === 'function') {
        callback();
      }
    }

    var intro = window.SpaceIntroMusic;
    if (intro &&
        typeof intro.isActive === 'function' &&
        intro.isActive() &&
        typeof intro.fadeOutAndStop === 'function') {
      logThrottled('log', 'intro_handoff', ['intro music stopping before main music']);
      intro.fadeOutAndStop(done);
      return;
    }

    done();
  }

  function markAudio(audio, owner) {
    if (audio && audio.dataset) {
      audio.dataset.mergenAudioOwner = normalizeOwner(owner);
    }
    return audio;
  }

  function getAudioOwner(audio) {
    if (audio && audio.dataset && audio.dataset.mergenAudioOwner) {
      return audio.dataset.mergenAudioOwner;
    }
    return 'external_audio';
  }

  function cleanupTransient(reason) {
    releaseMany(
      ['tts', 'ai_expert', 'stt', 'external_audio', 'tts_manual'],
      reason || 'cleanup'
    );
  }

  window.MergenAudioLifecycle = {
    duck: duck,
    release: release,
    releaseAll: releaseAll,
    releaseMany: releaseMany,
    activeDuckOwners: ownerList,
    applyMusicDuckState: applyMusicDuckState,
    stopIntroBeforeMain: stopIntroBeforeMain,
    markAudio: markAudio,
    getAudioOwner: getAudioOwner,
    cleanupTransient: cleanupTransient
  };

  // Browser smoke test seam:
  // Üretim davranışını değiştirmez; ux-smoke.html sadece mevcut sahiplik
  // durumunu sentetik olarak gözlemek ve temizlemek için kullanır.
  window.MergenAudioLifecycleSmoke = {
    duck: duck,
    release: release,
    releaseAll: releaseAll,
    activeDuckOwners: ownerList,
    applyMusicDuckState: applyMusicDuckState
  };

  window.addEventListener('pagehide', function() {
    cleanupTransient('pagehide');
  });

  if (window.jQuery) {
    $(document).on('shiny:disconnected', function() {
      cleanupTransient('shiny_disconnected');
    });
  }
})();