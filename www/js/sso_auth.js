// Dosya Yolu: www/js/sso_auth.js
// Açıklama: Keycloak SSO istemci tarafı kimlik doğrulama mantığı.
//           Token kontrolü, Keycloak'a yönlendirme ve token'ı Shiny sunucusuna iletme.

(function() {
  'use strict';

  // ===========================================================================
  // ANA BAŞLATMA - DOM hazır olduktan sonra çalışır
  // ===========================================================================
  // ÖNEMLİ: Bu betik <head> içinde yüklenir ancak SSO yapılandırma verisi
  // <body> içinde oluşturulur. Bu nedenle DOM hazır olana kadar beklemeliyiz.
  function onDomReady(fn) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', fn);
    } else {
      fn();
    }
  }

  onDomReady(function() {
    // SSO yapılandırma verilerini HTML'den oku
    var configEl = document.getElementById('sso_module-sso_config_data');
    if (!configEl) {
      // SSO modülü yüklenmemiş - yerel geliştirme modunda
      console.log('[SSO] Yapılandırma elementi bulunamadı - yerel mod');
      return;
    }

    var config;
    try {
      config = JSON.parse(configEl.textContent);
    } catch (e) {
      console.error('[SSO] Yapılandırma ayrıştırma hatası:', e);
      return;
    }

    if (!config.enabled) {
      console.log('[SSO] SSO devre dışı');
      return;
    }

    // Yapılandırma doğrulaması
    if (!config.auth_endpoint) {
      console.error('[SSO] Keycloak auth_endpoint tanımlanmamış');
      return;
    }

    console.log('[SSO] Yapılandırma yüklendi, auth_endpoint:', config.auth_endpoint);

    var NS_PREFIX = config.ns_prefix || 'sso_module-';

    // ===========================================================================
    // TOKEN YÖNETİMİ
    // ===========================================================================

    /**
     * URL hash'inden access_token parametresini çıkar
     * Keycloak implicit flow: #access_token=eyJ...&token_type=bearer&expires_in=300
     */
    function extractTokenFromHash() {
      var hash = window.location.hash;
      if (!hash || hash.length < 2) return null;

      var params = {};
      hash.substring(1).split('&').forEach(function(part) {
        var kv = part.split('=');
        if (kv.length === 2) {
          params[decodeURIComponent(kv[0])] = decodeURIComponent(kv[1]);
        }
      });

      return params.access_token || null;
    }

    /**
     * localStorage'dan kaydedilmiş token'ı al
     */
    function getStoredToken() {
      try {
        return localStorage.getItem('mergen_bilge_jwt_token');
      } catch (e) {
        console.warn('[SSO] localStorage erişim hatası:', e);
        return null;
      }
    }

    /**
     * Token'ı localStorage'a kaydet
     */
    function storeToken(token) {
      try {
        localStorage.setItem('mergen_bilge_jwt_token', token);
      } catch (e) {
        console.warn('[SSO] localStorage kayıt hatası:', e);
      }
    }

    /**
     * Kaydedilmiş token'ı temizle
     */
    function clearStoredToken() {
      try {
        localStorage.removeItem('mergen_bilge_jwt_token');
      } catch (e) {
        // Sessiz hata
      }
    }

    /**
     * Token'ın süresinin dolup dolmadığını basitçe kontrol et
     * (Tam doğrulama sunucu tarafında yapılır)
     */
    function isTokenExpired(token) {
      try {
        var parts = token.split('.');
        if (parts.length !== 3) return true;

        var payload = parts[1]
          .replace(/-/g, '+')
          .replace(/_/g, '/');
        var decoded = JSON.parse(atob(payload));

        if (decoded.exp) {
          var now = Math.floor(Date.now() / 1000);
          return now >= decoded.exp;
        }
        return false;
      } catch (e) {
        return true;
      }
    }

    // ===========================================================================
    // KEYCLOAK YÖNLENDİRME
    // ===========================================================================

    /**
     * Kullanıcıyı Keycloak giriş sayfasına yönlendir
     */
    function redirectToKeycloak() {
      // redirect_uri: Keycloak kimlik doğrulama sonrası kullanıcıyı geri yönlendirir.
      // Bu URL'nin Keycloak client ayarlarında "Valid Redirect URIs" listesinde
      // tam olarak kayıtlı olması gerekir (örn: https://sunucu-adresi/ veya * ile wildcard).
      var baseUrl = window.location.origin + window.location.pathname;
      // Sondaki eğik çizgiyi normalize et (Keycloak eşleşme hassasiyeti için)
      if (!baseUrl.endsWith('/')) {
        baseUrl = baseUrl + '/';
      }
      var authUrl = config.auth_endpoint +
        '?client_id='     + encodeURIComponent(config.client_id) +
        '&redirect_uri='  + encodeURIComponent(baseUrl) +
        '&response_type=' + encodeURIComponent(config.response_type) +
        '&scope='         + encodeURIComponent(config.scope);

      console.log('[SSO] Keycloak\'a yönlendiriliyor:', authUrl);
      window.location.href = authUrl;
    }

    // ===========================================================================
    // UI KONTROL
    // ===========================================================================

    /**
     * SSO katman ekranını gizle (başarılı giriş sonrası)
     */
    function hideOverlay() {
      var overlay = document.getElementById(config.overlay_id);
      if (overlay) {
        overlay.classList.add('sso-auth-hidden');
        // Animasyon sonrası DOM'dan kaldır
        setTimeout(function() {
          overlay.style.display = 'none';
        }, 400);
      }
    }

    /**
     * Hata durumunu göster
     */
    function showError(message) {
      var loadingEl = document.getElementById(config.loading_id);
      var errorEl = document.getElementById(config.error_id);
      var errorMsgEl = document.getElementById(config.error_msg_id);

      if (loadingEl) loadingEl.style.display = 'none';
      if (errorEl) errorEl.style.display = 'block';
      if (errorMsgEl) errorMsgEl.textContent = message;
    }

    // ===========================================================================
    // SHINY MESAJ DİNLEYİCİLERİ
    // ===========================================================================

    /**
     * Shiny hazır olduğunda mesaj dinleyicilerini kaydet
     */
    function registerShinyHandlers() {
      // Başarılı giriş - katmanı gizle
      Shiny.addCustomMessageHandler('sso_auth_success', function(data) {
        console.log('[SSO] Kimlik doğrulama başarılı:', data.username);
        hideOverlay();
      });

      // Hata - hata mesajını göster
      Shiny.addCustomMessageHandler('sso_auth_error', function(data) {
        console.warn('[SSO] Kimlik doğrulama hatası:', data.message);
        clearStoredToken();
        showError(data.message);
      });

      // Token süresi dolmak üzere - uyarı göster
      Shiny.addCustomMessageHandler('sso_token_expiring', function(data) {
        console.warn('[SSO] Token süresi dolmak üzere:', data.remaining_seconds, 'saniye kaldı');
        // Kullanıcıya uyarı göster (mevcut toast sistemiyle)
        if (typeof showToast === 'function') {
          showToast(
            'Oturumunuzun süresi yakında dolacak. Lütfen sayfayı yenileyiniz.',
            'warning',
            8000
          );
        }
      });
    }

    // ===========================================================================
    // ANA AKIŞ
    // ===========================================================================

    /**
     * SSO kimlik doğrulama sürecini başlat
     */
    function initSSO() {
      console.log('[SSO] initSSO başlatılıyor...');

      // 1. URL hash'inden token kontrol et (Keycloak'tan dönüş)
      var hashToken = extractTokenFromHash();
      if (hashToken) {
        console.log('[SSO] URL hash\'inden token çıkarıldı');
        // URL'den token'ı temizle (güvenlik için)
        history.replaceState(null, '', window.location.pathname + window.location.search);
        storeToken(hashToken);
      }

      // 2. Kayıtlı token'ı kontrol et
      var token = hashToken || getStoredToken();

      if (!token) {
        console.log('[SSO] Token bulunamadı - Keycloak\'a yönlendiriliyor');
        clearStoredToken();
        redirectToKeycloak();
        return;
      }

      if (isTokenExpired(token)) {
        console.log('[SSO] Token süresi dolmuş - Keycloak\'a yönlendiriliyor');
        clearStoredToken();
        redirectToKeycloak();
        return;
      }

      // 3. Geçerli token var - Shiny'ye gönder
      console.log('[SSO] Geçerli token bulundu - Shiny\'ye gönderiliyor');
      sendTokenToShiny(token);
    }

    /**
     * Token'ı Shiny sunucusuna gönder
     * Shiny hazır olana kadar bekler
     */
    function sendTokenToShiny(token) {
      var inputName = NS_PREFIX + 'sso_jwt_token';
      var maxAttempts = 200;  // 200 * 100ms = 20 saniye (Shiny yüklenmesi için yeterli)
      var attempt = 0;

      function trySetInput() {
        attempt++;
        if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
          registerShinyHandlers();
          Shiny.setInputValue(inputName, token, { priority: 'event' });
          console.log('[SSO] Token Shiny sunucusuna gönderildi (deneme #' + attempt + ')');
        } else if (attempt < maxAttempts) {
          setTimeout(trySetInput, 100);
        } else {
          console.error('[SSO] Shiny bağlantısı kurulamadı (' + maxAttempts + ' deneme sonrası)');
          showError('Uygulama bağlantısı kurulamadı. Lütfen sayfayı yeniden yükleyiniz.');
        }
      }

      trySetInput();
    }

    // ===========================================================================
    // ÇIKIŞ (LOGOUT) DESTEĞİ
    // ===========================================================================

    /**
     * SSO oturumunu kapat
     * Hem yerel token'ı temizler hem Keycloak'tan çıkış yapar
     */
    window.ssoLogout = function() {
      clearStoredToken();

      if (config.logout_endpoint) {
        var baseUrl = window.location.origin + window.location.pathname;
        if (!baseUrl.endsWith('/')) {
          baseUrl = baseUrl + '/';
        }
        var logoutUrl = config.logout_endpoint +
          '?client_id=' + encodeURIComponent(config.client_id) +
          '&post_logout_redirect_uri=' + encodeURIComponent(baseUrl);
        window.location.href = logoutUrl;
      } else {
        window.location.reload();
      }
    };

    // SSO sürecini başlat
    initSSO();
  });

})();
