// www/js/modern_welcome_handler.js
// Modern welcome ekranı Shiny init mesajı ve görünür DOM lifecycle bağlayıcısı

$(document).ready(function() {

  var modernWelcomeBootTimer = null;
  var laneDeferredBootPending = false;
  var laneDeferredBootMessage = null;

	function clearModernWelcomeBootTimer() {
	  if (modernWelcomeBootTimer) {
		clearTimeout(modernWelcomeBootTimer);
		modernWelcomeBootTimer = null;
	  }
	}

	function bootModernWelcome(message, attempt) {
	  attempt = attempt || 0;

	  // Başlangıç şeridi henüz seçilmediyse (ilk açılış seçicisi açık) ağır
	  // karşılama medyası BAŞLATILMAZ: çözülmemiş şerit zengin gibi ele alınıp
	  // video/neural seçicinin arkasında yüklenirse, kullanıcı Hızlı Başlangıç
	  // seçtiğinde ilk hızlı açılış medyayı gerçekten atlamamış olurdu. Boot,
	  // şerit çözüldüğünde EN SON mesajla bir kez yeniden denenir.
	  var laneApi = window.MergenStartupLane;
	  if (laneApi &&
		  typeof laneApi.needsSelection === 'function' && laneApi.needsSelection() &&
		  typeof laneApi.whenResolved === 'function') {
		laneDeferredBootMessage = message;
		if (!laneDeferredBootPending) {
		  laneDeferredBootPending = true;
		  laneApi.whenResolved(function() {
			laneDeferredBootPending = false;
			bootModernWelcome(laneDeferredBootMessage, 0);
		  });
		}
		return;
	  }

	  const MAX_ATTEMPTS = 80;
	  const RETRY_DELAY_MS = 50;

	  const welcomeContainer = document.querySelector('.modern-welcome-root');
	  const videoContainer = document.querySelector('.modern-welcome-video-container');
	  const neuralCanvas = document.querySelector('.modern-welcome-neural-canvas');
	  const greetingText = document.getElementById('dynamic-greeting-text');

	  const domReady = !!(
		welcomeContainer &&
		welcomeContainer.offsetParent !== null &&
		videoContainer &&
		neuralCanvas &&
		greetingText
	  );

	  const depsReady = !!(
		window.WelcomeVideoPlayer &&
		window.WelcomeNeuralNetwork &&
		window.WelcomeGreeting
	  );

	  if ((!domReady || !depsReady) && attempt < MAX_ATTEMPTS) {
		modernWelcomeBootTimer = setTimeout(function() {
		  bootModernWelcome(message, attempt + 1);
		}, RETRY_DELAY_MS);
		return;
	  }

	  modernWelcomeBootTimer = null;

	  if (!domReady || !depsReady) {
		console.warn('[WELCOME] Modern welcome bileşenleri zamanında hazır olmadı.');
		return;
	  }

	  // Hızlı Başlangıç şeridi: sinematik arka plan videosu ve neural animasyon
	  // varsayılan olarak başlatılmaz (statik premium koyu zemin CSS ile gelir).
	  // Karşılama metni/selamlama normal şekilde çalışır. Özellik silinmez;
	  // Zengin Deneyim'de tam davranış korunur.
	  var fastLaneWelcome = document.documentElement.classList.contains('mergen-fast-lane');
	  if (fastLaneWelcome) {
		if (window.WelcomeVideoPlayer && window.WelcomeVideoPlayer.destroy) {
		  try { window.WelcomeVideoPlayer.destroy(); } catch (e) {}
		}
		if (window.WelcomeNeuralNetwork && window.WelcomeNeuralNetwork.destroy) {
		  try { window.WelcomeNeuralNetwork.destroy(); } catch (e) {}
		}
		if (window.WelcomeGreeting && window.WelcomeGreeting.destroy) {
		  try { window.WelcomeGreeting.destroy(); } catch (e) {}
		}
		if (greetingText) {
		  window.WelcomeGreeting.init(greetingText);
		}
		return;
	  }

	  // Video oynatıcı, aynı konteyner yeniden gönderildiğinde (kullanıcı
	  // başka sekmeden Ana Söyleşi'ye dönerken) yeniden başlatılmamalıdır.
	  // WelcomeVideoPlayer.init() aynı konteyner ile çağrıldığında otomatik
	  // olarak mevcut videoyu sürdürür (ensureActiveVideoPlaying). Bu yüzden
	  // burada zorla destroy çağırmıyoruz; sadece yeni konteyner için
	  // gerekli olduğunda iç tarafta yeniden kurulum yapılır.
	  if (window.WelcomeNeuralNetwork && window.WelcomeNeuralNetwork.destroy) {
		window.WelcomeNeuralNetwork.destroy();
	  }
	  if (window.WelcomeGreeting && window.WelcomeGreeting.destroy) {
		window.WelcomeGreeting.destroy();
	  }

	  if (videoContainer) {
		// Aynı konteyner için init() içinde "halen çalışıyor" yolu devreye
		// girer; videoyu yeniden başlatmak yerine yumuşak biçimde sürdürür.
		// Farklı konteyner için ise dahili olarak destroy + setup zinciri
		// otomatik tetiklenir.
		window.WelcomeVideoPlayer.init(videoContainer);
		// Tarayıcı autoplay politikası ilk play çağrısını sessizce
		// reddedebilir. Kısa süre sonra video gerçekten oynamıyor mu diye
		// bak; sadece o durumda iddiasız bir resume denemesi yap. Yeniden
		// init çağırırken aynı konteyner kullanılır; bu sayede init()
		// içindeki ensureActiveVideoPlaying yolu çalışır ve sahnede aktif
		// olan video kesilmez (çift video oynatımı önlenir).
		setTimeout(function() {
		  if (!videoContainer || !document.contains(videoContainer)) return;
		  // Çapraz geçişli iki videodan herhangi biri oynuyor mu?
		  // (data-index 0 ve 1 dönüşümlü olur; sadece index=0 üzerinden
		  // karar verirsek çalışan videoyu durdurabiliriz.)
		  var oynuyorMu = false;
		  var videos = videoContainer.querySelectorAll('.modern-welcome-video');
		  for (var i = 0; i < videos.length; i++) {
			if (!videos[i].paused && videos[i].currentTime > 0) {
			  oynuyorMu = true;
			  break;
			}
		  }
		  if (!oynuyorMu) {
			if (window.WelcomeVideoPlayer && window.WelcomeVideoPlayer.init) {
			  window.WelcomeVideoPlayer.init(videoContainer);
			}
		  }
		}, 800);
	  }

      if (neuralCanvas) {
        var accentColor = message && message.accentColor ? message.accentColor : null;

        // Ana Söyleşi neural animasyonu yalnızca kaydedilmiş karakter rengini kullanmalı.
        // .character-btn.active okunmaz; çünkü Yapılandırma/Kişiselleştirme sayfasındaki
        // kaydedilmemiş önizleme de bu sınıfı geçici olarak değiştirebilir.
        if (!accentColor && window.MERGEN_SAVED_CHARACTER_ACCENT) {
          accentColor = window.MERGEN_SAVED_CHARACTER_ACCENT;
        }

        // Geriye dönük güvenli fallback: yeni kodda MERGEN_ACTIVE_CHARACTER_ACCENT
        // artık sadece committed seçimlerde güncellenir.
        if (!accentColor && window.MERGEN_ACTIVE_CHARACTER_ACCENT) {
          accentColor = window.MERGEN_ACTIVE_CHARACTER_ACCENT;
        }

        window.WelcomeNeuralNetwork.init(neuralCanvas, accentColor);
      }

	  if (greetingText) {
		window.WelcomeGreeting.init(greetingText);
	  }
	}

	Shiny.addCustomMessageHandler('initModernWelcome', function(message) {
	  clearModernWelcomeBootTimer();

	  const welcomeContainer = document.querySelector('.modern-welcome-root');
	  if (!welcomeContainer || welcomeContainer.offsetParent === null) {
		modernWelcomeBootTimer = setTimeout(function() {
		  bootModernWelcome(message || {}, 0);
		}, 50);
		return;
	  }

	  requestAnimationFrame(function() {
		bootModernWelcome(message || {}, 0);
	  });
	});


});
