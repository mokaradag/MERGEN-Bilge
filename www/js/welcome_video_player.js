// www/js/welcome_video_player.js
// Modern karşılama ekranı için sinematik video oynatıcı

window.WelcomeVideoPlayer = (function() {
  const VIDEO_URLS = [
    "videos/cinematic/video1.mp4",
    "videos/cinematic/video2.mp4",
    "videos/cinematic/video3.mp4",
    "videos/cinematic/video4.mp4",
    "videos/cinematic/video5.mp4",
    "videos/cinematic/video6.mp4"
  ];

  let container = null;
  let videoElements = [null, null];
  let activeIndex = 0;
  let currentSources = ["", ""];
  let isInitialized = false;

  function shuffleArray(array) {
    const arr = [...array];
    for (let i = arr.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [arr[i], arr[j]] = [arr[j], arr[i]];
    }
    return arr;
  }

  function init(containerElement) {
    if (isInitialized) return;
    
    container = containerElement;
    if (!container) return;

    const shuffled = shuffleArray(VIDEO_URLS);
    currentSources = [shuffled[0], shuffled[1]];

    videoElements[0] = container.querySelector('.modern-welcome-video[data-index="0"]');
    videoElements[1] = container.querySelector('.modern-welcome-video[data-index="1"]');

    if (!videoElements[0] || !videoElements[1]) return;

    videoElements[0].src = currentSources[0];
    videoElements[1].src = currentSources[1];

    videoElements[0].classList.add('active');
    videoElements[1].classList.add('inactive');

    videoElements[0].addEventListener('ended', () => handleVideoEnd(0));
    videoElements[1].addEventListener('ended', () => handleVideoEnd(1));

    videoElements[0].addEventListener('error', (e) => {
      console.warn('Video yükleme hatası:', currentSources[0]);
      handleVideoEnd(0);
    });

    videoElements[1].addEventListener('error', (e) => {
      console.warn('Video yükleme hatası:', currentSources[1]);
      handleVideoEnd(1);
    });

    attemptPlay(0);
    isInitialized = true;
  }

  function attemptPlay(index) {
    const video = videoElements[index];
    if (!video) return;

    video.currentTime = 0;
    const playPromise = video.play();
    
    if (playPromise !== undefined) {
      playPromise.catch(err => {
        console.warn('Otomatik oynatma engellendi:', err);
      });
    }
  }

  function handleVideoEnd(endedIndex) {
    if (endedIndex !== activeIndex) return;

    const nextIndex = activeIndex === 0 ? 1 : 0;
    const nextVideo = videoElements[nextIndex];

    if (nextVideo) {
      nextVideo.currentTime = 0;
      attemptPlay(nextIndex);
    }

    videoElements[activeIndex].classList.remove('active');
    videoElements[activeIndex].classList.add('inactive');
    videoElements[nextIndex].classList.remove('inactive');
    videoElements[nextIndex].classList.add('active');

    activeIndex = nextIndex;

    setTimeout(() => {
      const currentPlayingSrc = currentSources[nextIndex];
      let nextVideo = VIDEO_URLS[Math.floor(Math.random() * VIDEO_URLS.length)];
      
      let attempts = 0;
      while (nextVideo === currentPlayingSrc && VIDEO_URLS.length > 1 && attempts < 10) {
        nextVideo = VIDEO_URLS[Math.floor(Math.random() * VIDEO_URLS.length)];
        attempts++;
      }
      
      currentSources[endedIndex] = nextVideo;
      if (videoElements[endedIndex]) {
        videoElements[endedIndex].src = nextVideo;
      }
    }, 1500);
  }

  function destroy() {
    if (videoElements[0]) {
      videoElements[0].pause();
      videoElements[0].src = '';
    }
    if (videoElements[1]) {
      videoElements[1].pause();
      videoElements[1].src = '';
    }
    videoElements = [null, null];
    container = null;
    isInitialized = false;
  }

  return {
    init: init,
    destroy: destroy
  };
})();