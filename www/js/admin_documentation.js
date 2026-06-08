/* ==========================================================================
   Dosya Yolu: www/js/admin_documentation.js
   Aciklama: Yonetici paneli "Dokumantasyon" sayfasi icin kucuk, yerel,
             baimliliksiz tarayici davranisi.
               - Belge karti tiklamasi -> namespaced Shiny girdisi (doc_select)
               - Icindekiler baglantisi -> ilgili basliga yumusak kaydirma
               - Icindekiler ac/kapat dugmesi
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

      // 3) Icindekiler ac/kapat
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
})();
