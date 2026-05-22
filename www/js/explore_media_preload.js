// www/js/explore_media_preload.js
// Açıklama: Açılış ekranı kapanmadan Bütünleşik mod karakter videolarını
// tarayıcı önbelleğine alır ve boot readiness'e character_media_ready bildirir.

(function () {
  "use strict";

  var requested = false;
  var completed = false;
  var cachedUrls = {};

  window.MergenExploreMediaPreload = window.MergenExploreMediaPreload || {
    characters: {}
  };

  function rememberCharacters(characters) {
    (characters || []).forEach(function (data) {
      if (data && data.character) {
        window.MergenExploreMediaPreload.characters[data.character] = data;
      }
    });

    window.dispatchEvent(new CustomEvent("mergen:explore-media-preloaded", {
      detail: {
        characters: window.MergenExploreMediaPreload.characters
      }
    }));
  }

  function flattenVideoUrls(characters) {
    var urls = [];

    (characters || []).forEach(function (character) {
      var videos = character && character.videos ? character.videos : {};

      ["intro", "loop", "select"].forEach(function (type) {
        (videos[type] || []).forEach(function (url) {
          if (url && !cachedUrls[url]) {
            cachedUrls[url] = true;
            urls.push(url);
          }
        });
      });
    });

    return urls;
  }

  function preloadVideo(url) {
    return new Promise(function (resolve) {
      var settled = false;
      var video = document.createElement("video");

      var done = function () {
        if (settled) return;
        settled = true;

        try {
          video.pause();
          video.removeAttribute("src");
          video.load();
        } catch (e) {}

        if (video.parentNode) {
          video.parentNode.removeChild(video);
        }

        resolve();
      };

      video.preload = "auto";
      video.muted = true;
      video.playsInline = true;
      video.style.cssText =
        "position:absolute;width:1px;height:1px;opacity:0;pointer-events:none;";

      video.addEventListener("canplaythrough", done, { once: true });
      video.addEventListener("error", done, { once: true });
      video.addEventListener("loadeddata", function () {
        if (video.readyState >= 3) done();
      }, { once: true });

      window.setTimeout(done, 12000);

      document.body.appendChild(video);
      video.src = url;
      video.load();
    });
  }

  function sendReady(count) {
    if (completed) return;
    completed = true;

    if (window.Shiny && Shiny.setInputValue) {
      Shiny.setInputValue("character_media_preload_ready", {
        count: count,
        timestamp: Date.now()
      }, { priority: "event" });
    }
  }

  function requestAllCharacterVideos() {
    if (requested || !window.Shiny || !Shiny.setInputValue) return;
    requested = true;

    Shiny.setInputValue("explore_request_all_char_videos", {
      source: "app_loading",
      timestamp: Date.now()
    }, { priority: "event" });
  }

  function installHandlers() {
    if (!window.Shiny || !Shiny.addCustomMessageHandler) {
      window.setTimeout(installHandlers, 50);
      return;
    }

    Shiny.addCustomMessageHandler("loadExploreAllCharVideos", function (payload) {
      var characters = payload && payload.characters ? payload.characters : [];
      var urls = flattenVideoUrls(characters);

      rememberCharacters(characters);

      if (!urls.length) {
        sendReady(0);
        return;
      }

      Promise.all(urls.map(preloadVideo))
        .then(function () {
          sendReady(urls.length);
        })
        .catch(function () {
          sendReady(urls.length);
        });
    });

    requestAllCharacterVideos();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", installHandlers, { once: true });
  } else {
    installHandlers();
  }

  document.addEventListener("shiny:connected", requestAllCharacterVideos, { once: true });
})();