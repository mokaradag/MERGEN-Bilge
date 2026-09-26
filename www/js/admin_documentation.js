/* ==========================================================================
   Dosya Yolu: www/js/admin_documentation.js
   Aciklama: Yonetici paneli "Dokumantasyon" sayfasi icin kucuk, yerel,
             baimliliksiz tarayici davranisi.
               - Belge karti tiklamasi -> namespaced Shiny girdisi (doc_select)
               - Icindekiler baglantisi -> ilgili basliga yumusak kaydirma
               - Icindekiler ac/kapat dugmesi
               - Belge ici kayitli belge baglantisi -> ayni sayfada o belge
               - Baglantidaki #bolum (data-doc-anchor) -> belge acilinca basliga
             Tek delege click handler kullanilir. CDN / agir bagimlilik yoktur.
             Guvenlik: secilen ASCII slug id'leri CSS.escape ile kullanilir,
             dosya adi gibi degerler selector'a enjekte edilmez.
   ========================================================================== */
(function () {
  "use strict";

  // Belge kimligini ilgili namespaced Shiny girdisine yazar.
  function setDocInput(container, docId) {
    if (!container || !docId) {
      return;
    }
    if (!window.Shiny || typeof window.Shiny.setInputValue !== "function") {
      return;
    }
    var inputId = container.getAttribute("data-doc-input");
    if (!inputId) {
      return;
    }
    window.Shiny.setInputValue(inputId, docId, { priority: "event" });
  }

  // Baglantidaki #bolum, sunucuda baslik kimligiyle ayni ASCII slug'a
  // cevrilir (data-doc-anchor). Once birebir baslik kimligi aranir; noktalama
  // duyarsiz esleme yalniz TEK basligi gosteriyorsa kullanilir. Bekleyen
  // kaydirma hedef belge kimligiyle tutulur ve yalniz o belge cizilince uygulanir.
  var pendingAnchor = null;

  function scrollToAnchor(scope, key) {
    if (!key) {
      return false;
    }
    var root = scope || document;
    var hedef = root.querySelector(".mb-doc-body #" + escapeId("mbdoc-" + key));
    if (!hedef) {
      var sade = key.replace(/[^a-z0-9]/g, "");
      var heads = root.querySelectorAll(".mb-doc-body [id^='mbdoc-']");
      var bulunan = [];
      for (var i = 0; i < heads.length; i++) {
        if (heads[i].id.slice(6).replace(/[^a-z0-9]/g, "") === sade) {
          bulunan.push(heads[i]);
        }
      }
      hedef = bulunan.length === 1 ? bulunan[0] : null;
    }
    if (hedef && typeof hedef.scrollIntoView === "function") {
      hedef.scrollIntoView({ behavior: "smooth", block: "start" });
    }
    return !!hedef;
  }

  // Bir hedef id'yi guvenli bicimde CSS selector'a cevirir.
  function escapeId(id) {
    if (window.CSS && typeof window.CSS.escape === "function") {
      return window.CSS.escape(id);
    }
    return String(id).replace(/[^a-zA-Z0-9_-]/g, "");
  }

  document.addEventListener(
    "click",
    function (ev) {
      if (!ev.target || !ev.target.closest) {
        return;
      }

      // 1) Belge karti secimi
      var card = ev.target.closest(".mb-doc-card[data-doc-id]");
      if (card) {
        // Yeni gezinme bekleyen eski kaydirma hedefini iptal eder.
        pendingAnchor = null;
        var list = card.closest(".mb-doc-card-list");
        setDocInput(list, card.getAttribute("data-doc-id"));
        return;
      }

      // 2) Icindekiler baglantisi -> basliga kaydir
      var tocLink = ev.target.closest(".mb-doc-toc-link[data-target-id]");
      if (tocLink) {
        ev.preventDefault();
        var targetId = tocLink.getAttribute("data-target-id");
        if (targetId) {
          var scope = tocLink.closest(".mb-doc-wrapper") || document;
          var target = scope.querySelector("#" + escapeId(targetId));
          if (target && typeof target.scrollIntoView === "function") {
            target.scrollIntoView({ behavior: "smooth", block: "start" });
          }
        }
        return;
      }

      // 3) Belge govdesindeki kayitli belge baglantisi -> uygulama icinde acilir;
      //    #bolum varsa belge cizildikten sonra o basliga kaydirilir.
      var docLink = ev.target.closest(".mb-doc-body a[data-doc-id]");
      if (docLink) {
        ev.preventDefault();
        var wrap = docLink.closest(".mb-doc-wrapper") || document;
        var targetDoc = docLink.getAttribute("data-doc-id");
        var anchor = docLink.getAttribute("data-doc-anchor");
        var active = wrap.querySelector(".mb-doc-card-active[data-doc-id]");
        if (active && active.getAttribute("data-doc-id") === targetDoc) {
          pendingAnchor = null;
          scrollToAnchor(wrap, anchor);
          return;
        }
        pendingAnchor = anchor ? { doc: targetDoc, key: anchor } : null;
        setDocInput(wrap.querySelector(".mb-doc-card-list"), targetDoc);
        return;
      }

      // 3b) Ayni belgedeki #bolum baglantisi -> basliga kaydir
      var anchorLink = ev.target.closest(".mb-doc-body a[data-doc-anchor]");
      if (anchorLink) {
        ev.preventDefault();
        scrollToAnchor(anchorLink.closest(".mb-doc-wrapper"), anchorLink.getAttribute("data-doc-anchor"));
        return;
      }

      // 4) Icindekiler ac/kapat
      var toggle = ev.target.closest(".mb-doc-toc-toggle");
      if (toggle) {
        var wrapper = toggle.closest(".mb-doc-wrapper");
        if (wrapper) {
          wrapper.classList.toggle("mb-doc-toc-collapsed");
        }
        return;
      }
    },
    false
  );

  // Yapiskan baslik (.mb-doc-sticky-head) yuksekligini --mb-doc-head-offset
  // degiskenine yazar; Icindekiler (TOC) yapiskan ofseti bu degerden turetilir.
  // Sabit "sihirli sayi" yerine gercek yukseklik kullanilir; kart sarmasi /
  // tema / sekme degisikliklerinde guncel kalir.
  var headResizeObs = null;
  function syncDocHeadOffset() {
    var head = document.querySelector(".mb-doc-sticky-head");
    if (!head) {
      return;
    }
    var wrapper = head.closest(".mb-doc-wrapper");
    if (!wrapper) {
      return;
    }
    wrapper.style.setProperty("--mb-doc-head-offset", head.offsetHeight + "px");
    if (window.ResizeObserver) {
      if (headResizeObs) {
        headResizeObs.disconnect();
      }
      headResizeObs = new ResizeObserver(function () {
        wrapper.style.setProperty(
          "--mb-doc-head-offset",
          head.offsetHeight + "px"
        );
      });
      headResizeObs.observe(head);
    }
  }

  window.addEventListener("resize", syncDocHeadOffset, { passive: true });

  // Dokumantasyon icerigi yeniden render edildikce (uiOutput) yeniden olcer.
  // Yalnizca admin icerik ciktisi guncellemelerinde calisir (ucuz erken cikis).
  document.addEventListener("shiny:value", function (ev) {
    if (!ev || !ev.name || ev.name.indexOf("tab_content_area") === -1) {
      return;
    }
    setTimeout(function () {
      syncDocHeadOffset();
      var govde = document.querySelector(".mb-doc-body[data-rendered-doc-id]");
      if (pendingAnchor && govde &&
          govde.getAttribute("data-rendered-doc-id") === pendingAnchor.doc) {
        scrollToAnchor(document, pendingAnchor.key);
        pendingAnchor = null;
      }
    }, 0);
  });

  setTimeout(syncDocHeadOffset, 0);
})();
