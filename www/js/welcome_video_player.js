// www/js/welcome_video_player.js
// Modern karşılama ekranı için sinematik video oynatıcı

window.WelcomeVideoPlayer = (function() {
  const VIDEO_URLS = [
    "videos/cinematic/video1.mp4",
    "videos/cinematic/video2.mp4",
    "videos/cinematic/video3.mp4",
    "videos/cinematic/video4.mp4",
    "videos/cinematic/video5.mp4",
    "videos/cinematic/video6.mp4",
    "videos/cinematic/video7.mp4",
    "videos/cinematic/video8.mp4",
    "videos/cinematic/video9.mp4",
    "videos/cinematic/video10.mp4"
  ];

  let container = null;
  let videoElements = [null, null];
  let activeIndex = 0;
  let currentSources = ["", ""];
  let isInitialized = false;
  let smokeInitCount = 0;
  let smokeDestroyCount = 0;

  // İsimlendirilmiş olay dinleyicileri (temizlik için)
  let _endHandlers = [null, null];
  let _errorHandlers = [null, null];

  function shuffleArray(array) {
    const arr = [...array];
    for (let i = arr.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [arr[i], arr[j]] = [arr[j], arr[i]];
    }
    return arr;
  }

  function init(containerElement) {
    if (!containerElement) return;

    // Aynı görünür konteyner zaten bağlıysa, mevcut aktif videoyu kontrol et:
    // pause durumdaysa yeniden oynatmayı dene. Bu, Kişiselleştirme veya başka bir
    // sayfaya geçip Ana Söyleşi'ye dönüldüğünde videonun bazen donmuş kalmasını
    // önler (örn. tarayıcı autoplay politikası, görünürlük geçişi).
    if (isInitialized && container === containerElement && document.contains(containerElement)) {
      ensureActiveVideoPlaying();
      return;
    }

    // Önceki instance'ları temizle
    if (isInitialized || videoElements[0] || videoElements[1]) {
      destroy();
    }

    container = containerElement;
    if (!container) return;

    smokeInitCount++;

    const shuffled = shuffleArray(VIDEO_URLS);
    currentSources = [shuffled[0], shuffled[1]];

    videoElements[0] = container.querySelector('.modern-welcome-video[data-index="0"]');
    videoElements[1] = container.querySelector('.modern-welcome-video[data-index="1"]');

    if (!videoElements[0] || !videoElements[1]) return;

    videoElements[0].src = currentSources[0];
    videoElements[1].src = currentSources[1];

    videoElements[0].classList.add('active');
    videoElements[1].classList.add('inactive');

    // İsimlendirilmiş fonksiyonlar oluştur (removeEventListener için)
    _endHandlers[0] = function() { handleVideoEnd(0); };
    _endHandlers[1] = function() { handleVideoEnd(1); };
    _errorHandlers[0] = function() {
      // Konteyner DOM'dan kaldırıldıysa hata yoksay
      if (!container || !container.parentNode || !document.contains(container)) return;
      handleVideoEnd(0);
    };
    _errorHandlers[1] = function() {
      if (!container || !container.parentNode || !document.contains(container)) return;
      handleVideoEnd(1);
    };

    videoElements[0].addEventListener('ended', _endHandlers[0]);
    videoElements[1].addEventListener('ended', _endHandlers[1]);
    videoElements[0].addEventListener('error', _errorHandlers[0]);
    videoElements[1].addEventListener('error', _errorHandlers[1]);

    attemptPlay(0);
    isInitialized = true;

    // İlk attemptPlay tarayıcı autoplay politikası, hazırlık veya görünürlük
    // gecikmesi nedeniyle başarısız olabilir. Birkaç kez kısa aralıklarla
    // tekrar denenir; bu, neural canvas her zaman görünürken videonun bazen
    // başlamamasının önüne geçer.
    scheduleAutoplayRecovery(0);
  }

  // Aktif video pause durumdaysa oynatmayı yeniden dene
  function ensureActiveVideoPlaying() {
    var video = videoElements[activeIndex];
    if (!video) return;
    if (!container || !document.contains(container)) return;
    if (video.paused || video.ended) {
      attemptPlay(activeIndex);
      scheduleAutoplayRecovery(activeIndex);
    }
  }

  // Birkaç kez kısa aralıklarla video.play()'i tekrar dener.
  // Bu, tarayıcı autoplay politikası, video buffer hazırlığı ve görünürlük
  // değişimleri nedeniyle ilk play çağrısının sessizce başarısız olmasına
  // karşı savunma katmanıdır. Neural canvas zaten her zaman çizilir; bu
  // mekanizma videonun da aynı tutarlılıkta görünmesini sağlar.
  function scheduleAutoplayRecovery(index) {
    var attempts = 0;
    var maxAttempts = 6;
    var timer = setInterval(function() {
      attempts += 1;
      var video = videoElements[index];
      if (!video || !container || !document.contains(container)) {
        clearInterval(timer);
        return;
      }
      // İlgili index artık aktif değilse kurtarmayı durdur; aksi halde
      // arka plana çekilmiş (inactive) videoyu tekrar oynatmaya çalışırız.
      if (index !== activeIndex) {
        clearInterval(timer);
        return;
      }
      // Video oynamaya başladıysa kurtarmayı durdur
      if (!video.paused && video.currentTime > 0) {
        clearInterval(timer);
        return;
      }
      if (attempts >= maxAttempts) {
        clearInterval(timer);
        return;
      }
      // Tekrar oynatmayı dene
      attemptPlay(index);
    }, 350);
  }

  function attemptPlay(index) {
    var video = videoElements[index];
    if (!video) return;

    // Konteyner DOM'da değilse oynatma yapma
    if (!container || !document.contains(container)) return;

    // currentTime'ı sadece video henüz oynamadıysa sıfırla; aksi halde
    // çalışan video tekrar başa sarılır ve görsel sıçrama oluşur.
    if (video.paused && video.currentTime === 0) {
      // Hazır - oynatmayı dene
    } else if (video.paused) {
      // Önceden duraklatılmış video; bulunduğu yerden devam etsin
    }

    var playPromise = video.play();

    if (playPromise !== undefined) {
      playPromise.catch(function(err) {
        // AbortError: video kaynağı değişti veya durduruldu - güvenle yoksay
        if (err.name === 'AbortError') return;
        // Konteyner artık DOM'da değilse yoksay
        if (!container || !document.contains(container)) return;
        // NotAllowedError vs. autoplay politikası: scheduleAutoplayRecovery
        // birkaç kez daha tekrar deneyecek.
        console.warn('[WELCOME_VIDEO] Otomatik oynatma engellendi:', err.name);
      });
    }
  }

  function handleVideoEnd(endedIndex) {
    if (endedIndex !== activeIndex) return;

    // Konteyner DOM'da değilse işlem yapma
    if (!container || !document.contains(container)) return;

    var nextIndex = activeIndex === 0 ? 1 : 0;
    var nextVideo = videoElements[nextIndex];
    var currentVideo = videoElements[activeIndex];

    // Null kontrolleri - elemanlar yok edilmiş olabilir
    if (!currentVideo || !nextVideo) return;

    if (nextVideo) {
      nextVideo.currentTime = 0;
      attemptPlay(nextIndex);
    }

    currentVideo.classList.remove('active');
    currentVideo.classList.add('inactive');
    nextVideo.classList.remove('inactive');
    nextVideo.classList.add('active');

    activeIndex = nextIndex;

    setTimeout(function() {
      // Zaman aşımı sonrası tekrar kontrol et
      if (!container || !document.contains(container)) return;

      var currentPlayingSrc = currentSources[nextIndex];
      var nextSrc = VIDEO_URLS[Math.floor(Math.random() * VIDEO_URLS.length)];

      var attempts = 0;
      while (nextSrc === currentPlayingSrc && VIDEO_URLS.length > 1 && attempts < 10) {
        nextSrc = VIDEO_URLS[Math.floor(Math.random() * VIDEO_URLS.length)];
        attempts++;
      }

      currentSources[endedIndex] = nextSrc;
      if (videoElements[endedIndex]) {
        videoElements[endedIndex].src = nextSrc;
      }
    }, 1500);
  }

  function destroy() {
    if (isInitialized || videoElements[0] || videoElements[1]) {
      smokeDestroyCount++;
    }

    // İsimlendirilmiş dinleyicileri temizle
    for (var i = 0; i < 2; i++) {
      if (videoElements[i]) {
        videoElements[i].pause();
        if (_endHandlers[i]) videoElements[i].removeEventListener('ended', _endHandlers[i]);
        if (_errorHandlers[i]) videoElements[i].removeEventListener('error', _errorHandlers[i]);
        videoElements[i].src = '';
        videoElements[i].load();
      }
    }
    videoElements = [null, null];
    _endHandlers = [null, null];
    _errorHandlers = [null, null];
    container = null;
    isInitialized = false;
    activeIndex = 0;
    currentSources = ["", ""];
  }

  function getSmokeState() {
    return {
      isInitialized: isInitialized,
      activeIndex: activeIndex,
      currentSources: currentSources.slice(),
      initCount: smokeInitCount,
      destroyCount: smokeDestroyCount,
      hasContainer: !!(container && document.contains(container))
    };
  }

  return {
    init: init,
    destroy: destroy,
    getSmokeState: getSmokeState
  };
})();

window.MergenWelcomeVideoSmoke = {
  getState: window.WelcomeVideoPlayer.getSmokeState
};