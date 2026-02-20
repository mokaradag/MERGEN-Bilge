// Dosya Yolu: www/js/citation_handler.js
// Açıklama: Satır içi atıf referanslarını ([n]) tıklanabilir hâle getirir.
//           Kullanıcı [n]'e tıkladığında aynı mesajdaki Kaynakça bölümünün
//           ilgili girişine kayar ve kısa süreli vurgulama animasyonu uygular.

(function () {
  'use strict';

  // İşlem kuyruğunda bekleyen sarmalayıcıları takip et (gereksiz tekrarları önle)
  var pendingWrappers = new WeakSet();

  // ─── Mesaj sarmalayıcısındaki atıfları işle ───────────────────────────────
  // Kaynakça girişi (.kaynakca-entry) yoksa erken çıkar — model kaynaksız
  // yanıt vermiş veya akış henüz bitmemiş demektir.
  function processMessageCitations(wrapper) {
    var msgContent = wrapper.querySelector('.message-content');
    if (!msgContent) return;

    // Kaynakça girişi yoksa işlem yapma
    if (!msgContent.querySelector('.kaynakca-entry')) return;

    // Metin düğümlerinde [n] kalıplarını tıklanabilir atıf düğmelerine çevir
    processTextNodes(msgContent);
  }

  // ─── Öğenin metin düğümlerini özyinelemeli şekilde tara ──────────────────
  // Kod blokları, mevcut atıf düğmeleri ve Kaynakça girişleri atlanır.
  function processTextNodes(element) {
    // Bu etiket türlerini tamamen atla
    var skipTags = { CODE: true, PRE: true, SCRIPT: true, STYLE: true, TEXTAREA: true };
    if (skipTags[element.tagName]) return;

    // Kaynakça ve atıf öğelerinin içine girme
    if (element.classList && (
      element.classList.contains('kaynakca-entry') ||
      element.classList.contains('source-link')    ||
      element.classList.contains('citation-ref')
    )) return;

    // childNodes'un anlık kopyasını al (DOM değişikliği sırasında güvenli iterasyon)
    var children = Array.from(element.childNodes);
    children.forEach(function (node) {
      if (node.nodeType === Node.TEXT_NODE) {
        // Metin düğümünde [n] kalıbı var mı?
        if (/\[\d+\]/.test(node.textContent)) {
          replaceTextNodeWithCitations(node, node.textContent);
        }
      } else if (node.nodeType === Node.ELEMENT_NODE) {
        processTextNodes(node);
      }
    });
  }

  // ─── Tek metin düğümündeki [n] kalıplarını span'lara böl ─────────────────
  function replaceTextNodeWithCitations(textNode, text) {
    var frag  = document.createDocumentFragment();
    var regex = /\[(\d+)\]/g;
    var last  = 0;
    var match;

    while ((match = regex.exec(text)) !== null) {
      // Eşleşmeden önceki saf metin parçası
      if (match.index > last) {
        frag.appendChild(document.createTextNode(text.slice(last, match.index)));
      }

      // Tıklanabilir atıf düğmesi
      var span = document.createElement('span');
      span.className  = 'citation-ref';
      span.dataset.ref = match[1];
      span.title      = 'Kaynağa git: [' + match[1] + ']';
      span.textContent = '[' + match[1] + ']';
      frag.appendChild(span);

      last = regex.lastIndex;
    }

    // Kalan saf metin parçası
    if (last < text.length) {
      frag.appendChild(document.createTextNode(text.slice(last)));
    }

    textNode.parentNode.replaceChild(frag, textNode);
  }

  // ─── Atıf düğmesine tıklanma olayı ──────────────────────────────────────
  // İlgili Kaynakça girişini bulur, kaydırır ve vurgular.
  $(document).on('click', '.citation-ref', function (e) {
    e.preventDefault();
    e.stopPropagation();

    var refNum     = $(this).data('ref');
    var msgWrapper = $(this).closest('[id^="message_wrapper_"]');
    if (!msgWrapper.length) return;

    // Aynı mesajdaki ilgili Kaynakça girişini bul
    var entry = msgWrapper.find('.kaynakca-entry[data-entry="' + refNum + '"]');
    if (!entry.length) return;

    // Görünür alana kaydır
    entry[0].scrollIntoView({ behavior: 'smooth', block: 'nearest' });

    // Önceki vurgulamaları temizle, yeni vurguyu başlat
    msgWrapper.find('.kaynakca-entry').removeClass('citation-highlight');
    entry.addClass('citation-highlight');
    setTimeout(function () {
      entry.removeClass('citation-highlight');
    }, 2200);
  });

  // ─── MutationObserver: yeni ve güncellenen mesajları izle ────────────────
  // Hem doğrudan eklenen mesaj sarmalayıcılarını (non-streaming) hem de
  // akış sonrası HTML değişimini (finalizeStreamingMessage) yakalar.
  function observeChatContainer() {
    var container = document.getElementById('chat_content_container');
    if (!container) return;

    var observer = new MutationObserver(function (mutations) {
      // Bu toplu döngüde işlenecek sarmalayıcıları grupla
      var batchWrappers = new Set();

      mutations.forEach(function (mutation) {
        var wrapper = null;

        // Doğrudan eklenen mesaj sarmalayıcısı mı?
        if (mutation.addedNodes.length) {
          mutation.addedNodes.forEach(function (node) {
            if (node.nodeType === Node.ELEMENT_NODE &&
                node.id && node.id.startsWith('message_wrapper_')) {
              wrapper = node;
            }
          });
        }

        // Değişikliğin ait olduğu sarmalayıcıyı DOM ağacından yukarı doğru ara
        // (finalizeStreamingMessage .message-content içeriğini değiştirdiğinde)
        if (!wrapper) {
          var el = (mutation.target.nodeType === Node.ELEMENT_NODE)
            ? mutation.target
            : mutation.target.parentElement;
          while (el && el !== container) {
            if (el.id && el.id.startsWith('message_wrapper_')) {
              wrapper = el;
              break;
            }
            el = el.parentElement;
          }
        }

        if (wrapper) {
          batchWrappers.add(wrapper);
        }
      });

      // Her sarmalayıcıyı yalnızca bir kez sıraya al
      batchWrappers.forEach(function (wrapper) {
        if (!pendingWrappers.has(wrapper)) {
          pendingWrappers.add(wrapper);
          (function (w) {
            // Kısa gecikme: DOM yerleşiminin tamamlanmasını bekle
            setTimeout(function () {
              pendingWrappers.delete(w);
              processMessageCitations(w);
            }, 80);
          })(wrapper);
        }
      });
    });

    observer.observe(container, { childList: true, subtree: true });
  }

  // ─── Başlangıç ───────────────────────────────────────────────────────────
  $(document).ready(function () {
    observeChatContainer();

    // Sayfa yüklendiğinde hâlihazırda görünen mesajları işle
    // (kayıtlı sohbet yüklemelerinde gerekli)
    setTimeout(function () {
      document.querySelectorAll('[id^="message_wrapper_"]').forEach(function (wrapper) {
        processMessageCitations(wrapper);
      });
    }, 600);
  });

  // Dışa açık API: diğer modüllerden çağrılabilir
  window.processMessageCitations = processMessageCitations;

}());
