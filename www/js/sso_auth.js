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
      // Modül id'si değişmişse sonek eşleşmesi ile bul
      configEl = document.querySelector('[id$="sso_config_data"]');
    }
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
    var authResponseReceived = false;

    // ===========================================================================
    // TOKEN YÖNETİMİ
    // ===========================================================================

    /**
     * URL hash'inden access_token parametresini çıkar
     * Keycloak implicit flow: #access_token=eyJ...&token_type=bearer&expires_in=300
     */
    function parseUrlParams(paramString) {
      var out = {};
      if (!paramString) return out;

      paramString.split('&').forEach(function(part) {
        if (!part) return;
        var eqIndex = part.indexOf('=');
        if (eqIndex === -1) return;
        var key = decodeURIComponent(part.substring(0, eqIndex));
        var value = decodeURIComponent(part.substring(eqIndex + 1));
        out[key] = value;
      });

      return out;
    }

    function extractAuthParams() {
      var hash = window.location.hash;
      var search = window.location.search;
      var hashParams = (hash && hash.length > 1) ? parseUrlParams(hash.substring(1)) : {};
      var searchParams = (search && search.length > 1) ? parseUrlParams(search.substring(1)) : {};

      return {
        access_token: hashParams.access_token || searchParams.access_token || null,
        id_token: hashParams.id_token || searchParams.id_token || null,
        code: hashParams.code || searchParams.code || null,
        error: hashParams.error || searchParams.error || null,
        error_description: hashParams.error_description || searchParams.error_description || null
      };
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
      if (isRedirectLoopDetected()) {
        console.error('[SSO] Sürekli yönlendirme döngüsü tespit edildi');
        showError(
          'Kimlik doğrulama yönlendirmesi tekrar ediyor. Lütfen SSO redirect URI ayarını kontrol ediniz.'
        );
        return;
      }

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
      markRedirectAttempt();
      window.location.href = authUrl;
    }

    function markRedirectAttempt() {
      try {
        var now = Date.now();
        sessionStorage.setItem('mergen_sso_last_redirect_ts', String(now));
      } catch (e) {
        // Sessiz hata
      }
    }

    function clearRedirectAttempt() {
      try {
        sessionStorage.removeItem('mergen_sso_last_redirect_ts');
      } catch (e) {
        // Sessiz hata
      }
    }

    function isRedirectLoopDetected() {
      try {
        var lastRedirectTs = parseInt(
          sessionStorage.getItem('mergen_sso_last_redirect_ts') || '0',
          10
        );
        if (!lastRedirectTs) return false;
        return (Date.now() - lastRedirectTs) < 8000;
      } catch (e) {
        return false;
      }
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
        authResponseReceived = true;
        clearRedirectAttempt();
        console.log('[SSO] Kimlik doğrulama başarılı:', data.username);
        hideOverlay();
      });

      // Hata - hata mesajını göster
      Shiny.addCustomMessageHandler('sso_auth_error', function(data) {
        authResponseReceived = true;
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
      var authParams = extractAuthParams();
      var incomingToken = authParams.access_token || authParams.id_token;

      // Keycloak hata cevabı
      if (authParams.error) {
        var errMsg = authParams.error_description || authParams.error;
        console.error('[SSO] Keycloak hata dönüşü:', authParams.error, errMsg);
        clearStoredToken();
        history.replaceState(null, '', window.location.pathname);
        showError('Keycloak kimlik doğrulaması başarısız: ' + errMsg);
        return;
      }

      // Authorization code flow için açık uyarı (bu uygulama token bekler)
      if (authParams.code && !incomingToken) {
        console.error('[SSO] Authorization code alındı ancak access_token gelmedi');
        history.replaceState(null, '', window.location.pathname);
        showError(
          'Keycloak "code" döndürdü ancak uygulama "token" bekliyor. response_type ayarını kontrol ediniz.'
        );
        return;
      }

      if (incomingToken) {
        console.log('[SSO] URL hash\'inden token çıkarıldı');
        // URL'den token'ı temizle (güvenlik için)
        history.replaceState(null, '', window.location.pathname + window.location.search);
        storeToken(incomingToken);
      }

      // 2. Kayıtlı token'ı kontrol et
      var token = incomingToken || getStoredToken();

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
          setTimeout(function() {
            if (!authResponseReceived) {
              console.error('[SSO] Sunucudan auth yanıtı alınamadı (15sn timeout)');
              showError(
                'Kimlik doğrulama yanıtı alınamadı. Lütfen sunucu loglarını ve ağ bağlantısını kontrol ediniz.'
              );
            }
          }, 15000);
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
