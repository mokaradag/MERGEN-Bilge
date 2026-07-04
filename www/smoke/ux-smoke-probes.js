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

  // ---------------------------------------------------------------------------
  // Bilge Yolaç Oturumlar (kalıcı oturum) yüzey probe'u.
  //
  // Gerçek filtre <select> öğeleri (selectize = FALSE => yerel select) doğrudan
  // app DOM'undan okunur; böylece "Tümü" seçeneğinin seçim sonrası da kalıcı
  // kaldığı GERÇEK tarayıcıda doğrulanır. Oturum kartları ve detay modalı
  // gerçek DB gerektirdiğinden aynı CSS sınıf/etiketleriyle sentetik
  // (smoke-only) fixture üretilir; bu fixture kart eylem yüzeyini (aktif ↔
  // arşiv) ve detay modalı kaydırma/max-height sözleşmesini korur.
  // ---------------------------------------------------------------------------

  var CCS_MODULE_NS = "claude_code_sessions_module";

  function ccsFindFilterSelect(doc, suffix) {
    return (
      doc.getElementById(CCS_MODULE_NS + "-" + suffix) ||
      doc.querySelector("select[id$='-" + suffix + "']")
    );
  }

  function ccsSelectOptionValues(select) {
    if (!select || !select.options) return [];
    return Array.prototype.map.call(select.options, function(opt) {
      return opt.value;
    });
  }

  function ccsSelectOptionTexts(select) {
    if (!select || !select.options) return [];
    return Array.prototype.map.call(select.options, function(opt) {
      return String(opt.textContent || "").trim();
    });
  }

  function ccsSelectHasValue(select, value) {
    return ccsSelectOptionValues(select).indexOf(value) >= 0;
  }

  function ccsSelectOptionSignature(select) {
    return ccsSelectOptionValues(select).join("\u001f");
  }

  function ccsFirstNonEmptySelectValue(select) {
    if (!select || !select.options) return "";

    for (var i = 0; i < select.options.length; i++) {
      var value = String(select.options[i].value || "");
      if (value !== "") {
        return value;
      }
    }

    return "";
  }

  async function ccsWaitForSelectOptionsToSettle(select, wait, timeoutMs, stableMs) {
    var timeout = timeoutMs || 5000;
    var requiredStableMs = stableMs || 800;
    var startedAt = Date.now();
    var lastSignature = ccsSelectOptionSignature(select);
    var stableSince = Date.now();

    while (Date.now() - startedAt < timeout) {
      await wait(150);

      var currentSignature = ccsSelectOptionSignature(select);
      if (currentSignature !== lastSignature) {
        lastSignature = currentSignature;
        stableSince = Date.now();
        continue;
      }

      if (Date.now() - stableSince >= requiredStableMs) {
        return true;
      }
    }

    return false;
  }

  // Yerel (native) <select> mı, yoksa selectize sarmalayıcısı mı? Selectize
  // orijinal select'e 'selectized' sınıfı ekler ve kardeş .selectize-control
  // üretir; "Tümü" placeholder davranışı sorununu doğuran budur.
  function ccsIsNativeSelect(select) {
    if (!select || String(select.tagName).toUpperCase() !== "SELECT") return false;
    if (select.classList.contains("selectized")) return false;
    var container = select.closest(".shiny-input-container") || select.parentNode;
    if (container && container.querySelector(".selectize-control")) return false;
    return true;
  }

  // Gerçek kullanıcı seçimini taklit eder: yalnızca select.value atamak Shiny'nin
  // input binding'ini tetiklemez; bu yüzden bubble eden input+change olayları
  // gönderilir. Böylece sunucudaki debounce'lı filtre observer'ı
  // (R/module_claude_code_sessions.R) gerçekten çalışır ve "Tümü" kalıcılığı
  // yalnızca istemci tarafında değil, gerçek etkileşim yolunda doğrulanır.
  function ccsSetSelectValue(win, select, value) {
    select.value = value;
    select.dispatchEvent(new win.Event("input", { bubbles: true }));
    select.dispatchEvent(new win.Event("change", { bubbles: true }));
  }

  function ccsBuildSessionCardMarkup(kind) {
    var acButonu =
      '<button type="button" class="ccs-card-btn ccs-open-btn">' +
      '<i class="fas fa-eye"></i><span>Aç</span></button>';

    if (kind === "archived") {
      return (
        '<div class="ccs-card-top">' +
        '<div class="ccs-card-title">Arşivlenmiş smoke oturumu</div>' +
        '<span class="ccs-status-badge ccs-badge-archived">Arşivlendi</span>' +
        "</div>" +
        '<div class="ccs-card-actions">' +
        acButonu +
        '<button type="button" class="ccs-card-btn ccs-restore-btn">' +
        '<i class="fas fa-box-open"></i><span>Geri Yükle</span></button>' +
        '<button type="button" class="ccs-card-btn ccs-delete-btn">' +
        '<i class="fas fa-trash"></i><span>Kalıcı Sil</span></button>' +
        "</div>"
      );
    }

    return (
      '<div class="ccs-card-top">' +
      '<div class="ccs-card-title">Aktif smoke oturumu</div>' +
      '<span class="ccs-status-badge ccs-badge-success">Tamamlandı</span>' +
      "</div>" +
      '<div class="ccs-card-actions">' +
      acButonu +
      '<button type="button" class="ccs-card-btn ccs-resume-btn">' +
      '<i class="fas fa-play"></i><span>Devam Et</span></button>' +
      '<button type="button" class="ccs-card-btn ccs-archive-btn">' +
      '<i class="fas fa-box-archive"></i><span>Arşivle</span></button>' +
      "</div>"
    );
  }

  function ccsBuildDetailTimelineMarkup() {
    var items = "";
    for (var i = 1; i <= 24; i++) {
      items +=
        '<div class="ccs-run-item">' +
        '<div class="ccs-run-head">' +
        '<span class="ccs-run-order">#' + i + "</span>" +
        '<span class="ccs-status-badge ccs-badge-success">Tamamlandı</span>' +
        "</div>" +
        '<div class="ccs-run-prompt">' +
        '<span class="ccs-run-label">Komut</span>' +
        '<pre class="ccs-run-pre">Uzun oturum geçmişi satırı ' + i +
        " - detay modalı kaydırma sözleşmesini zorlamak için yeterli metin." +
        "\nSatir 2 icerigi.\nSatir 3 icerigi.</pre>" +
        "</div>" +
        "</div>";
    }

    return (
      '<div class="ccs-detail-resume-note">' +
      '<span class="ccs-status-badge ccs-badge-warning">not</span></div>' +
      '<div class="ccs-detail-meta"></div>' +
      '<h5 class="ccs-detail-timeline-title">Çalıştırma Zaman Çizelgesi</h5>' +
      '<div class="ccs-run-timeline">' + items + "</div>"
    );
  }

  function removeSyntheticSessionsSurface(doc) {
    var existing = doc.getElementById("ux_smoke_ccs_synthetic");
    if (existing && existing.parentNode) {
      existing.parentNode.removeChild(existing);
    }
  }

  function renderSyntheticSessionsSurface(doc) {
    removeSyntheticSessionsSurface(doc);

    var host = doc.createElement("div");
    host.id = "ux_smoke_ccs_synthetic";
    host.setAttribute("data-ux-smoke", "bilge-yolac-sessions");

    var grid = doc.createElement("div");
    grid.className = "ccs-sessions-grid";

    var aktif = doc.createElement("div");
    aktif.className = "ccs-session-card";
    aktif.setAttribute("data-ux-smoke-card", "active");
    aktif.innerHTML = ccsBuildSessionCardMarkup("active");

    var arsiv = doc.createElement("div");
    arsiv.className = "ccs-session-card";
    arsiv.setAttribute("data-ux-smoke-card", "archived");
    arsiv.innerHTML = ccsBuildSessionCardMarkup("archived");

    grid.appendChild(aktif);
    grid.appendChild(arsiv);

    // Detay modalı: gerçek Bootstrap .modal-body sarmalayıcısı içinde gerçek
    // .ccs-detail-modal-content sınıfı; böylece kaydırma/max-height hesaplanmış
    // stil sözleşmesi gerçek CSS ile (nesnel getComputedStyle) ölçülür.
    var modalBody = doc.createElement("div");
    modalBody.className = "modal-body";

    var modalContent = doc.createElement("div");
    modalContent.className = "ccs-detail-modal-content";
    modalContent.setAttribute("data-ux-smoke", "ccs-detail");
    modalContent.innerHTML = ccsBuildDetailTimelineMarkup();

    modalBody.appendChild(modalContent);

    host.appendChild(grid);
    host.appendChild(modalBody);
    doc.body.appendChild(host);

    return {
      host: host,
      active: aktif,
      archived: arsiv,
      modalBody: modalBody,
      modalContent: modalContent
    };
  }

  async function runBilgeYolacSessionsSurfaceSmoke(app, helpers) {
    var win = app.win;
    var doc = app.doc;
    var assert = helpers.assert;
    var pass = helpers.pass;
    var wait = helpers.wait;
    var waitFor = helpers.waitFor;

    // --- Gerçek rota/sekme aktivasyon yolu -----------------------------------
    // Gizli ön-render DOM'u okumak yerine Oturumlar sekmesine tıklanır ve aktif
    // olması beklenir. Bu, kenar çubuğu rota/sekme aktivasyonunu VE sekme
    // aktivasyonunda tetiklenen sunucu tarafı yenilemesini
    // (server_module_wiring.R: input$tabs == 'claude_code_sessions' ->
    // claude_code_sessions$refresh('tab')) de kapsar.
    assert(
      clickDashboardTab(doc, "claude_code_sessions"),
      "Bilge Yolaç Oturumlar sekme linki tıklanabilir"
    );

    await waitFor(function() {
      var panel = doc.querySelector(".claude-code-sessions-container");
      var tab = doc.querySelector("#shiny-tab-claude_code_sessions");
      return isVisible(panel) || (tab && tab.classList.contains("active"));
    }, "Oturumlar sekmesi aktif/görünür", 10000);

    var tabPane = doc.querySelector("#shiny-tab-claude_code_sessions");
    assert(
      isVisible(doc.querySelector(".claude-code-sessions-container")) ||
        (tabPane && tabPane.classList.contains("active")),
      "Oturumlar sekmesi aktivasyon sonrası görünür"
    );

    // --- Gerçek filtre <select> öğeleri (yerel select => "Tümü" kalıcı) -------
    await waitFor(function() {
      return !!ccsFindFilterSelect(doc, "filter_status");
    }, "Oturumlar Durum filtresi DOM'da", 10000);

    var statusSelect = ccsFindFilterSelect(doc, "filter_status");
    var modelSelect = ccsFindFilterSelect(doc, "filter_model");

    assert(!!statusSelect, "Oturumlar Durum filtresi DOM'da bulunur");
    assert(!!modelSelect, "Oturumlar Model filtresi DOM'da bulunur");

    if (!statusSelect || !modelSelect) {
      return;
    }

    // Yerel select (selectize = FALSE): selectize placeholder davranışı yok;
    // bu, "Tümü" seçeneğinin kaybolmasına yol açan asıl regresyonun panzehridir.
    assert(
      ccsIsNativeSelect(statusSelect),
      "Oturumlar Durum filtresi yerel <select> öğesidir (selectize değil)"
    );
    assert(
      ccsIsNativeSelect(modelSelect),
      "Oturumlar Model filtresi yerel <select> öğesidir (selectize değil)"
    );

    var statusValues = ccsSelectOptionValues(statusSelect);
    var beklenenDurumlar = ["", "resumable", "completed", "failed", "stopped", "archived"];
    var eksikDurum = beklenenDurumlar.filter(function(v) {
      return statusValues.indexOf(v) < 0;
    });
    assert(
      eksikDurum.length === 0,
      "Oturumlar Durum filtresi tüm durum seçeneklerini içerir"
    );

    var statusTexts = ccsSelectOptionTexts(statusSelect).join(" | ");
    var beklenenEtiketler = [
      "Tümü", "Devam Edilebilir", "Tamamlandı", "Başarısız", "Durduruldu", "Arşivlenmiş"
    ];
    var eksikEtiket = beklenenEtiketler.filter(function(t) {
      return statusTexts.indexOf(t) < 0;
    });
    assert(
      eksikEtiket.length === 0,
      "Oturumlar Durum filtresi Türkçe etiketleri içerir"
    );

    // "Tümü" kalıcılığı: boş-olmayan bir durum GERÇEK bir change olayıyla
    // seçildikten (sunucu debounce'lı filtre observer'ı çalıştıktan) sonra "Tümü"
    // hâlâ erişilebilir VE yeniden seçilebilir olmalı (yerel select bunu garanti
    // eder; selectize placeholder davranışı sessizce "Tümü"yü kaybediyordu).
    ccsSetSelectValue(win, statusSelect, "completed");
    await wait(600); // debounce (400ms) + olası sunucu round-trip payı
    assert(
      statusSelect.value === "completed",
      "Oturumlar Durum filtresi boş-olmayan seçimi kabul eder"
    );
    assert(
      ccsSelectHasValue(statusSelect, ""),
      "Oturumlar Durum filtresinde seçim sonrası 'Tümü' seçeneği kaybolmaz"
    );
    ccsSetSelectValue(win, statusSelect, "");
    await wait(600);
    assert(
      statusSelect.value === "",
      "Oturumlar Durum filtresinde seçim sonrası 'Tümü' yeniden seçilebilir"
    );

    // Model filtresi: "Tümü" her zaman mevcut; model seçimi sonrası da kalıcı.
    assert(
      ccsSelectHasValue(modelSelect, ""),
      "Oturumlar Model filtresi 'Tümü' seçeneğini içerir"
    );

    // Model seçenekleri sunucu tarafında birikimli doldurulur. Bu smoke burada
    // client-only sentetik option enjekte etmez; varsa sunucunun gerçekten
    // ürettiği boş-olmayan bir model seçeneğini kullanır. Böylece Shiny
    // updateSelectInput(...) ile seçenekleri yeniden yazdığında doğru sayfa
    // yanlış negatif üretmez.
    await ccsWaitForSelectOptionsToSettle(modelSelect, wait, 5000, 800);

    var realModelValue = ccsFirstNonEmptySelectValue(modelSelect);

    if (realModelValue) {
      ccsSetSelectValue(win, modelSelect, realModelValue);
      await wait(600);
      await ccsWaitForSelectOptionsToSettle(modelSelect, wait, 5000, 800);

      assert(
        modelSelect.value === realModelValue,
        "Oturumlar Model filtresi mevcut gerçek model seçimini kabul eder"
      );
      assert(
        ccsSelectHasValue(modelSelect, ""),
        "Oturumlar Model filtresinde model seçimi sonrası 'Tümü' seçeneği kaybolmaz"
      );

      ccsSetSelectValue(win, modelSelect, "");
      await wait(600);
      await ccsWaitForSelectOptionsToSettle(modelSelect, wait, 5000, 800);

      assert(
        modelSelect.value === "",
        "Oturumlar Model filtresinde model seçimi sonrası 'Tümü' yeniden seçilebilir"
      );
    } else {
      pass(
        "Oturumlar Model filtresinde gerçek model seçeneği yok; model seçimi adımı atlandı"
      );
    }

    // Filtre id yüzeyinde çift render / çift DOM id üretilmemeli.
    assert(
      doc.querySelectorAll("#" + CCS_MODULE_NS + "-filter_status").length === 1,
      "Oturumlar Durum filtresi id'si tam olarak bir kez render edilir"
    );
    assert(
      doc.querySelectorAll("#" + CCS_MODULE_NS + "-filter_model").length === 1,
      "Oturumlar Model filtresi id'si tam olarak bir kez render edilir"
    );

    var ccsIds = Array.prototype.map.call(
      doc.querySelectorAll("[id^='" + CCS_MODULE_NS + "-']"),
      function(el) { return el.id; }
    );
    var ccsDup = ccsIds.filter(function(id, idx) {
      return ccsIds.indexOf(id) !== idx;
    });
    assert(
      ccsDup.length === 0,
      "Oturumlar modül id yüzeyinde çift DOM id üretilmez"
    );

    // --- Sentetik kart eylem yüzeyi (aktif ↔ arşiv) ve detay modalı -----------
    var fixture = renderSyntheticSessionsSurface(doc);
    var active = fixture.active;
    var archived = fixture.archived;

    assert(
      !!active.querySelector(".ccs-open-btn") &&
        !!active.querySelector(".ccs-resume-btn") &&
        !!active.querySelector(".ccs-archive-btn"),
      "Aktif oturum kartı Aç / Devam Et / Arşivle eylemlerini gösterir"
    );
    assert(
      active.textContent.indexOf("Aç") >= 0 &&
        active.textContent.indexOf("Devam Et") >= 0 &&
        active.textContent.indexOf("Arşivle") >= 0,
      "Aktif oturum kartı eylem etiketleri Türkçe ve okunur"
    );
    assert(
      !active.querySelector(".ccs-delete-btn") &&
        !active.querySelector(".ccs-restore-btn"),
      "Aktif oturum kartı arşiv-özel (Geri Yükle / Kalıcı Sil) eylemleri göstermez"
    );

    assert(
      !!archived.querySelector(".ccs-open-btn") &&
        !!archived.querySelector(".ccs-restore-btn") &&
        !!archived.querySelector(".ccs-delete-btn"),
      "Arşivlenmiş oturum kartı Aç / Geri Yükle / Kalıcı Sil eylemlerini gösterir"
    );
    assert(
      archived.textContent.indexOf("Geri Yükle") >= 0 &&
        archived.textContent.indexOf("Kalıcı Sil") >= 0,
      "Arşivlenmiş oturum kartı eylem etiketleri Türkçe ve okunur"
    );
    assert(
      !archived.querySelector(".ccs-resume-btn") &&
        !archived.querySelector(".ccs-archive-btn"),
      "Arşivlenmiş oturum kartı aktif-özel (Devam Et / Arşivle) eylemleri göstermez"
    );

    // Detay modalı kaydırma / max-height sözleşmesi (uzun geçmiş taşmaz, kısa
    // oturum cimri görünmez): içerik alanı görünüm-yüksekliğine bağlı bir üst
    // sınırla KENDİ İÇİNDE kaydırılabilir olmalı.
    var content = fixture.modalContent;
    var styles = win.getComputedStyle(content);
    var maxH = parseFloat(styles.maxHeight);
    var overflowY = styles.overflowY;

    assert(
      styles.maxHeight !== "none" && !isNaN(maxH) && maxH > 0,
      "Oturum detay modalı içeriği görünüm-yüksekliğine bağlı max-height taşır"
    );
    assert(
      overflowY === "auto" || overflowY === "scroll" || overflowY === "overlay",
      "Oturum detay modalı içeriği kaydırılabilir overflow sözleşmesi taşır"
    );
    assert(
      content.scrollHeight > content.clientHeight,
      "Oturum detay modalı uzun geçmişte kendi içinde kayar (cimri/taşkın değil)"
    );

    removeSyntheticSessionsSurface(doc);

    // Temiz son durum: Ana Söyleşi'ye geri dön (best-effort; başarısızlık
    // bloklayıcı değil, çünkü bu probe smoke dizisinin son gerçek adımıdır).
    clickDashboardTab(doc, "chat");
    await waitFor(function() {
      var tab = doc.querySelector("#shiny-tab-chat");
      return !!doc.querySelector(".modern-welcome-root") ||
        (tab && tab.classList.contains("active"));
    }, "Ana Söyleşi dönüşü", 8000, { failOnTimeout: false });

    pass("Bilge Yolaç Oturumlar smoke probe tamamlandı");
  }

  window.MergenUxSmokeProbes = {
    snapshotTransientState: snapshotTransientState,
    snapshotToolState: snapshotToolState,
    renderSyntheticFileManagerListing: renderSyntheticFileManagerListing,
    runFileManagerDisplayNameSmoke: runFileManagerDisplayNameSmoke,
    renderSyntheticSessionsSurface: renderSyntheticSessionsSurface,
    runBilgeYolacSessionsSurfaceSmoke: runBilgeYolacSessionsSurfaceSmoke,
    runNavigationAndFileManagerSmoke: runNavigationAndFileManagerSmoke
  };
})();