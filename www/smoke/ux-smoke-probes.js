// ==============================================================================
// Dosya Yolu: www/smoke/ux-smoke-probes.js
// Açıklama:
//   MERGEN UX smoke sayfası için küçük, üretime yüklenmeyen browser probe
//   yardımcıları. Gerçek uygulama DOM'una yalnızca smoke harness içinden dokunur.
// ==============================================================================

(function() {
  "use strict";

  function queryAny(doc, selectors) {
    for (var i = 0; i < selectors.length; i++) {
      var found = doc.querySelector(selectors[i]);
      if (found) return found;
    }
    return null;
  }

  function isVisible(element) {
    if (!element) return false;
    return !!(
      element.offsetWidth ||
      element.offsetHeight ||
      (element.getClientRects && element.getClientRects().length)
    );
  }

  function dashboardTabAnchor(doc, tabName) {
    return queryAny(doc, [
      ".sidebar-menu a[data-value='" + tabName + "']",
      "a[data-value='" + tabName + "']",
      "a[href='#shiny-tab-" + tabName + "']"
    ]);
  }

  function clickDashboardTab(doc, tabName) {
    var anchor = dashboardTabAnchor(doc, tabName);
    if (!anchor) return false;
    anchor.click();
    return true;
  }

  function getAudioLifecycle(win) {
    if (!win) return null;
    return win.MergenAudioLifecycleSmoke || win.MergenAudioLifecycle || null;
  }

  function activeDuckOwners(win) {
    var lifecycle = getAudioLifecycle(win);
    if (!lifecycle || typeof lifecycle.activeDuckOwners !== "function") {
      return [];
    }

    try {
      return lifecycle.activeDuckOwners() || [];
    } catch (e) {
      return [];
    }
  }

  function backgroundMusicSourceCount(win) {
    var count = 0;
    var manager = win && win.MusicManager;
    var doc = win && win.document;

    if (manager && manager._audio && manager._audio.src) {
      count += 1;
    }

    if (!doc) return count;

    Array.prototype.slice.call(doc.querySelectorAll("audio")).forEach(function(audio) {
      var src = audio.getAttribute("src") || audio.src || "";

      if (!src || !/(^|\/)music\//.test(src)) {
        return;
      }

      if (manager && audio === manager._audio) {
        return;
      }

      count += 1;
    });

    return count;
  }

  function snapshotTransientState(win) {
    var manager = win && win.MusicManager;
    var tts = win && win.mergenTTS;

    return {
      duckOwners: activeDuckOwners(win),
      backgroundMusicSourceCount: backgroundMusicSourceCount(win),
      musicDucked: !!(manager && manager.state && manager.state.isDucked),
      sttActive: !!(manager && manager.state && manager.state._sttActive),
      ttsQueueLength: tts && tts.queue ? tts.queue.length : 0,
      ttsPlaying: !!(tts && tts.isPlaying),
      hasTtsCurrentAudio: !!(tts && tts.currentAudio)
    };
  }

  function readToolSettingKeys(win) {
    if (!win || !win.localStorage) return [];

    try {
      var raw = win.localStorage.getItem("mergen_settings") || "{}";
      var settings = JSON.parse(raw);

      return Object.keys(settings).filter(function(key) {
        return /^enable_.*_tools$/.test(key) && settings[key] === true;
      }).sort();
    } catch (e) {
      return [];
    }
  }

  function snapshotToolState(win) {
    var doc = win && win.document;

    if (!doc) {
      return {
        activePaneId: "",
        activePaneLooksBilgeYolac: false,
        hash: "",
        openModalCount: 0,
        toolSettingKeys: []
      };
    }

    // Smoke-only sayfa/araç durumu: gerçek UI'ı değiştirmez, yalnızca
    // Bilge Yolaç ↔ Ana Söyleşi geçişinde stale panel/modal/hash sızıntısını yakalar.
    var activePane = queryAny(doc, [
      "#shiny-tab-chat.active",
      "#shiny-tab-claude_code.active",
      ".tab-pane.active[id^='shiny-tab-']",
      ".tab-content > .active[id^='shiny-tab-']"
    ]);

    var activePaneId = activePane ? (activePane.id || "") : "";
    var activeText = activePane ? (activePane.textContent || "") : "";
    var activeHtml = activePane ? (activePane.innerHTML || "") : "";
    var combined = activePaneId + " " + activeText + " " + activeHtml;

    return {
      activePaneId: activePaneId,
      activePaneLooksBilgeYolac: /shiny-tab-claude_code|claude-code-container|Bilge Yolaç/i.test(combined),
      hash: String((win.location && win.location.hash) || ""),
      openModalCount: doc.querySelectorAll(".modal.show, .modal.in, .modal-backdrop").length,
      toolSettingKeys: readToolSettingKeys(win)
    };
  }

  function normalizeSyntheticDisplayName(file) {
    var raw = String(
      (file && (file.displayName || file.originalName || file.name || file.storageName)) ||
      ""
    );

    // Storage-prefix sızıntısı smoke fixture'ında yakalansın diye yaygın
    // timestamp/hex öneklerini sentetik listede görünen addan ayır.
    raw = raw.replace(/^[0-9]{8,14}[-_][A-Fa-f0-9]{6,}[-_]/, "");
    raw = raw.replace(/^[0-9]+_[A-Fa-f0-9]{8,}_/, "");

    return raw;
  }

  function removeSyntheticFileManagerListing(doc) {
    var existing = doc.getElementById("ux_smoke_file_manager_synthetic");
    if (existing && existing.parentNode) {
      existing.parentNode.removeChild(existing);
    }
  }

  function renderSyntheticFileManagerListing(doc, files) {
    removeSyntheticFileManagerListing(doc);

    var host = doc.createElement("div");
    host.id = "ux_smoke_file_manager_synthetic";
    host.setAttribute("data-ux-smoke", "file-manager-display-name");

    var table = doc.createElement("table");
    table.className = "ux-smoke-file-manager-table";

    (files || []).forEach(function(file, index) {
      var displayName = normalizeSyntheticDisplayName(file);
      var row = doc.createElement("tr");

      var nameCell = doc.createElement("td");
      nameCell.className = "file-name";
      nameCell.textContent = displayName;

      var attachCell = doc.createElement("td");
      var checkbox = doc.createElement("input");
      checkbox.type = "checkbox";
      checkbox.className = "attach-checkbox";
      checkbox.setAttribute("data-file-id", file.id || ("synthetic_" + index));
      checkbox.setAttribute("data-filename", displayName);
      checkbox.setAttribute("title", "Bu dosyayı model bağlamına ekle/çıkar");
      checkbox.setAttribute("aria-label", "Model bağlamına ekle veya çıkar");

      attachCell.appendChild(checkbox);
      row.appendChild(nameCell);
      row.appendChild(attachCell);
      table.appendChild(row);
    });

    host.appendChild(table);
    doc.body.appendChild(host);

    return host;
  }

  function runFileManagerDisplayNameSmoke(doc, assertFn) {
    var turkishName = "Türkçe_çalışma_özeti_İstanbul.pdf";
    var storageName = "20260527_ab12cd34_" + turkishName;
    var mojibakePattern = /Ã|Ä|Å|�/;

    var host = renderSyntheticFileManagerListing(doc, [
      {
        id: "file_tr_1",
        storageName: storageName,
        displayName: turkishName
      }
    ]);

    var firstText = host.textContent || "";
    var firstCheckbox = host.querySelector("input.attach-checkbox");

    assertFn(
      firstText.indexOf(turkishName) >= 0,
      "File Manager synthetic listing Türkçe adı okunur tutar"
    );

    assertFn(
      !mojibakePattern.test(firstText),
      "File Manager synthetic listing mojibake üretmez"
    );

    assertFn(
      firstCheckbox && firstCheckbox.getAttribute("data-filename") === turkishName,
      "File Manager attach data-filename görünen Türkçe adı kullanır"
    );

    host = renderSyntheticFileManagerListing(doc, [
      {
        id: "file_tr_1",
        storageName: storageName,
        displayName: turkishName
      }
    ]);

    assertFn(
      (host.textContent || "").indexOf(turkishName) >= 0,
      "File Manager synthetic refresh sonrası Türkçe adı korur"
    );

    removeSyntheticFileManagerListing(doc);
  }

  async function runNavigationAndFileManagerSmoke(app, helpers) {
    var win = app.win;
    var doc = app.doc;
    var assert = helpers.assert;
    var pass = helpers.pass;
    var wait = helpers.wait;
    var waitFor = helpers.waitFor;

    var videoApi = win.MergenWelcomeVideoSmoke || null;

    assert(
      !!videoApi && typeof videoApi.getState === "function",
      "WelcomeVideoPlayer smoke state API var"
    );

    var beforeVideo = videoApi && videoApi.getState ? videoApi.getState() : null;

    assert(
      clickDashboardTab(doc, "claude_code"),
      "Bilge Yolaç sekme linki tıklanabilir"
    );

    await waitFor(function() {
      var panel = doc.querySelector(".claude-code-container");
      var tab = doc.querySelector("#shiny-tab-claude_code");
      return isVisible(panel) || (tab && tab.classList.contains("active"));
    }, "Bilge Yolaç görünür", 6000);

    var yolacSnapshot = snapshotTransientState(win);
    var yolacToolSnapshot = snapshotToolState(win);

    assert(
      yolacToolSnapshot.activePaneLooksBilgeYolac === true,
      "Bilge Yolaç geçişinde doğru tool paneli aktif görünür"
    );

    assert(
      yolacSnapshot.backgroundMusicSourceCount <= 1,
      "Bilge Yolaç geçişinde tek background music source kalır"
    );

    assert(
      yolacSnapshot.duckOwners.length === 0,
      "Bilge Yolaç geçişinde stale audio duck owner kalmaz"
    );

    assert(
      !yolacSnapshot.hasTtsCurrentAudio,
      "Bilge Yolaç geçişinde stale TTS audio kalmaz"
    );

    assert(
      clickDashboardTab(doc, "chat"),
      "Ana Söyleşi sekme linki tıklanabilir"
    );

    await waitFor(function() {
      return !!doc.querySelector(".modern-welcome-root");
    }, "Ana Söyleşi welcome dönüşü", 10000);

    await wait(250);

    var afterVideo = videoApi && videoApi.getState ? videoApi.getState() : null;

    if (beforeVideo && afterVideo) {
      assert(
        afterVideo.destroyCount === beforeVideo.destroyCount,
        "Ana Söyleşi dönüşü welcome video gereksiz destroy etmez"
      );

      assert(
        afterVideo.initCount === beforeVideo.initCount,
        "Ana Söyleşi dönüşü welcome video gereksiz reinit etmez"
      );
    }

    var finalToolSnapshot = snapshotToolState(win);

    assert(
      finalToolSnapshot.activePaneId === "shiny-tab-chat" ||
        !!doc.querySelector(".modern-welcome-root"),
      "Ana Söyleşi dönüşü chat paneli aktif kalır"
    );

    assert(
      finalToolSnapshot.activePaneLooksBilgeYolac === false,
      "Ana Söyleşi dönüşü stale Bilge Yolaç tool paneli aktif kalmaz"
    );

    assert(
      finalToolSnapshot.hash.indexOf("claude_code") < 0,
      "Ana Söyleşi dönüşü URL hash stale Bilge Yolaç state taşımaz"
    );

    assert(
      finalToolSnapshot.openModalCount === 0,
      "Ana Söyleşi dönüşü stale tool modal/backdrop kalmaz"
    );

    var finalSnapshot = snapshotTransientState(win);

    assert(
      finalSnapshot.backgroundMusicSourceCount <= 1,
      "Ana Söyleşi dönüşü tek background music source kalır"
    );

    assert(
      finalSnapshot.duckOwners.length === 0,
      "Ana Söyleşi dönüşü stale audio duck owner kalmaz"
    );

    runFileManagerDisplayNameSmoke(doc, assert);

    pass("Navigation/File Manager smoke probe tamamlandı");
  }

  window.MergenUxSmokeProbes = {
    snapshotTransientState: snapshotTransientState,
    snapshotToolState: snapshotToolState,
    renderSyntheticFileManagerListing: renderSyntheticFileManagerListing,
    runFileManagerDisplayNameSmoke: runFileManagerDisplayNameSmoke,
    runNavigationAndFileManagerSmoke: runNavigationAndFileManagerSmoke
  };
})();