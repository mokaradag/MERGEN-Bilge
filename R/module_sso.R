# Dosya Yolu: R/module_sso.R
# Açıklama: SSO (Tek Oturum Açma) Shiny modülü.
#            Keycloak token alımı, doğrulama ve oturum yönetimini gerçekleştirir.
#            SSO_ENABLED=FALSE ise bu modül devre dışı kalır.

# ==============================================================================
# SSO MODÜL UI
# ==============================================================================

#' SSO Kimlik Doğrulama UI Bileşenleri
#' @description SSO aktifken bekleme ekranı ve hata mesajlarını gösterir.
#'   SSO kapalıyken hiçbir şey göstermez.
#' @param id Modül ID
ssoAuthUI <- function(id) {
  ns <- NS(id)

  if (!isTRUE(SSO_ENABLED)) {
    # SSO kapalı - UI bileşeni gerekmez
    return(tags$div())
  }

  tagList(
    # SSO giriş bekleme/hata ekranı (JavaScript tarafından kontrol edilir)
    tags$div(
      id = ns("sso_overlay"),
      class = "sso-auth-overlay",
      tags$div(
        class = "sso-auth-container",
        # Yükleniyor durumu
        tags$div(
          id = ns("sso_loading"),
          class = "sso-loading-state",
          tags$div(class = "sso-spinner"),
          tags$h3("Kimlik Doğrulanıyor..."),
          tags$p("Keycloak sunucusuna yönlendiriliyorsunuz.")
        ),
        # Hata durumu (başlangıçta gizli)
        tags$div(
          id = ns("sso_error"),
          class = "sso-error-state",
          style = "display: none;",
          tags$div(class = "sso-error-icon", tags$i(class = "fas fa-exclamation-triangle")),
          tags$h3("Erişim Reddedildi"),
          tags$p(id = ns("sso_error_message"), "Kimlik doğrulama başarısız oldu."),
          tags$button(
            id = ns("sso_retry_btn"),
            class = "btn-modern btn-primary sso-retry-btn",
            onclick = "window.location.reload();",
            tags$i(class = "fas fa-redo"),
            " Tekrar Dene"
          )
        )
      )
    ),

    # Keycloak yapılandırmasını JavaScript'e aktar
    tags$script(type = "application/json", id = ns("sso_config_data"),
      jsonlite::toJSON(list(
        enabled          = TRUE,
        auth_endpoint    = SSO_CONFIG$auth_endpoint %||% "",
        client_id        = SSO_CONFIG$client_id,
        response_type    = SSO_CONFIG$response_type,
        scope            = SSO_CONFIG$scope,
        logout_endpoint  = SSO_CONFIG$logout_endpoint %||% "",
        overlay_id       = ns("sso_overlay"),
        loading_id       = ns("sso_loading"),
        error_id         = ns("sso_error"),
        error_msg_id     = ns("sso_error_message"),
        ns_prefix        = ns("")
      ), auto_unbox = TRUE)
    )
  )
}

# ==============================================================================
# SSO ÖN KAPI BETİĞİ
# ==============================================================================
#' SSO Ön Kapı Betiği
#' @description SSO aktifken, tarayıcıda geçerli token yoksa Shiny websocket
#'   kurulmadan önce Keycloak'a yönlendirme yapar. Böylece ilk yetkisiz sayfa
#'   geçişinde açılış yükleme ekranı ve ağır server observer'ları başlamaz.
#' @return Head içine yerleştirilecek script etiketi
ssoPreflightScriptUI <- function() {
  if (!isTRUE(SSO_ENABLED) || !nzchar(SSO_CONFIG$auth_endpoint %||% "")) {
    return(tags$script(HTML(
      "window.__mergenSsoPreflight = { enabled: false, redirecting: false };"
    )))
  }

  preflight_config <- list(
    enabled       = TRUE,
    auth_endpoint = SSO_CONFIG$auth_endpoint %||% "",
    client_id     = SSO_CONFIG$client_id %||% "",
    response_type = SSO_CONFIG$response_type %||% "token",
    scope         = SSO_CONFIG$scope %||% "openid"
  )

  tags$script(HTML(paste0(
"(function() {
  'use strict';

  var config = ", jsonlite::toJSON(preflight_config, auto_unbox = TRUE), ";

  window.__mergenSsoPreflight = {
    enabled: !!config.enabled,
    redirecting: false
  };

  if (!config.enabled || !config.auth_endpoint || !config.client_id) {
    return;
  }

  function extractTokenFromHash() {
    var hash = window.location.hash || '';
    if (hash.length < 2) return null;

    var parts = hash.substring(1).split('&');
    for (var i = 0; i < parts.length; i++) {
      var kv = parts[i].split('=');
      if (kv.length >= 2 && decodeURIComponent(kv[0]) === 'access_token') {
        return decodeURIComponent(kv.slice(1).join('='));
      }
    }
    return null;
  }

  function getStoredToken() {
    try {
      return localStorage.getItem('mergen_bilge_jwt_token');
    } catch (e) {
      return null;
    }
  }

  function clearStoredToken() {
    try {
      localStorage.removeItem('mergen_bilge_jwt_token');
    } catch (e) {}
  }

  function isTokenExpired(token) {
    try {
      var parts = String(token || '').split('.');
      if (parts.length !== 3) return true;

      var payload = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      while (payload.length % 4 !== 0) {
        payload += '=';
      }

      var decoded = JSON.parse(atob(payload));
      if (!decoded.exp) return false;

      var now = Math.floor(Date.now() / 1000);
      return now >= decoded.exp;
    } catch (e) {
      return true;
    }
  }

  function buildAuthUrl() {
    var baseUrl = window.location.origin + window.location.pathname;

    // Keycloak Valid Redirect URIs eşleşmesi için mevcut davranış korunur.
    if (!baseUrl.endsWith('/')) {
      baseUrl = baseUrl + '/';
    }

    return config.auth_endpoint +
      '?client_id='     + encodeURIComponent(config.client_id) +
      '&redirect_uri='  + encodeURIComponent(baseUrl) +
      '&response_type=' + encodeURIComponent(config.response_type || 'token') +
      '&scope='         + encodeURIComponent(config.scope || 'openid');
  }

  // Keycloak dönüşünde hash içinde token varsa sayfayı başlat; token daha sonra
  // www/js/sso_auth.js tarafından Shiny'ye iletilecek.
  var hashToken = extractTokenFromHash();
  if (hashToken) {
    return;
  }

  var storedToken = getStoredToken();
  if (storedToken && !isTokenExpired(storedToken)) {
    return;
  }

  if (storedToken) {
    clearStoredToken();
  }

  // Bu ilk yetkisiz geçiştir. Shiny bağlantısı ve açılış yükleme ekranı
  // başlamadan önce Keycloak'a git.
  window.__mergenSsoPreflight.redirecting = true;
  window.__mergenSsoPreflightRedirecting = true;
  document.documentElement.classList.add('mergen-sso-preflight-redirect');

  window.location.replace(buildAuthUrl());
})();"
  )))
}


# ==============================================================================
# SSO MODÜL SUNUCU
# ==============================================================================

#' SSO Kimlik Doğrulama Sunucu Mantığı
#' @description Keycloak token'ını alır, doğrular ve kullanıcı bilgilerini döndürür.
#'   SSO kapalıyken NULL döndürür (normal akış devam eder).
#' @param id Modül ID
#' @return Reaktif liste: sso_user_claims (kullanıcı bilgileri) veya NULL
ssoAuthServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    if (!isTRUE(SSO_ENABLED)) {
      # SSO kapalı - boş reaktif değer döndür
      return(reactiveValues(
        authenticated = TRUE,  # Yerel modda otomatik yetkilendirilmiş
        user_claims   = NULL,
        auth_level    = Sys.getenv("MERGEN_AUTH_LEVEL", "ADMIN"),
        raw_token     = NULL
      ))
    }

    # Reaktif durum değişkenleri
    sso_state <- reactiveValues(
      authenticated = FALSE,
      user_claims   = NULL,
      auth_level    = NULL,
      raw_token     = NULL
    )

    # --- JWT Token Gözlemcisi ---
    # JavaScript tarafından Shiny.setInputValue ile gönderilen token'ı dinle
    observeEvent(input$sso_jwt_token, {
      token <- input$sso_jwt_token

      if (is.null(token) || !nzchar(token)) {
        log_warn("SSO: Boş token alındı")
        return()
      }

      log_info("SSO: JWT token alındı (uzunluk={nchar(token)}), doğrulama başlatılıyor...")

      # Token doğrulama
      validation <- validate_jwt_token(token)

      if (!isTRUE(validation$valid)) {
        log_warn("SSO: Token doğrulama başarısız - {validation$error}")
        sso_state$authenticated <- FALSE

        # Hata mesajını UI'a gönder
        session$sendCustomMessage("sso_auth_error", list(
          message = validation$error %||% "Kimlik doğrulama başarısız oldu."
        ))
        return()
      }

      # Kullanıcı bilgilerini çıkar
      claims <- extract_user_claims(validation$payload)

      if (is.null(claims) || !nzchar(claims$username)) {
        log_warn("SSO: Kullanıcı bilgileri çıkarılamadı")
        sso_state$authenticated <- FALSE
        session$sendCustomMessage("sso_auth_error", list(
          message = "Kullanıcı bilgileri alınamadı."
        ))
        return()
      }

      # Veritabanından yetki kontrolü
      # preferred_username ile eşleşme yapılır, bulunamazsa sicil ile denenir
      auth_info <- check_user_authorization(claims$username, sicil = claims$sicil)

      if (!isTRUE(auth_info$authorized)) {
        log_warn("SSO: Kullanıcı yetkisiz - {claims$username}")
        sso_state$authenticated <- FALSE
        session$sendCustomMessage("sso_auth_error", list(
          message = paste0(
            "Bu uygulamaya erişim yetkiniz bulunmuyor. ",
            "Lütfen sistem yöneticinize başvurunuz."
          )
        ))
        return()
      }

      # Veritabanı bilgileriyle claim'leri zenginleştir
      claims$yetki           <- auth_info$yetki
      claims$masraf_yeri_kodu <- auth_info$masraf_yeri_kodu

      # DB'deki KaynakAdi ile Keycloak adını karşılaştır, DB'dekini tercih et
      if (!is.null(auth_info$kaynak_adi) && nzchar(auth_info$kaynak_adi)) {
        claims$full_name  <- auth_info$kaynak_adi
        claims$first_name <- extractFirstName(auth_info$kaynak_adi)
      }

      # Başarılı kimlik doğrulama
      sso_state$authenticated <- TRUE
      sso_state$user_claims   <- claims
      sso_state$auth_level    <- auth_info$yetki
      sso_state$raw_token     <- token

      log_info("SSO: Kimlik doğrulama başarılı - kullanıcı={claims$username}, yetki={auth_info$yetki}")

      # UI'a başarılı giriş bildir
      session$sendCustomMessage("sso_auth_success", list(
        username = claims$username
      ))

    }, ignoreNULL = TRUE, ignoreInit = TRUE)

    # --- Token yenileme zamanlayıcı ---
    # Token süresinin dolmasına yakın kullanıcıyı uyarır; süre GEÇTİĞİNDE ise
    # oturumu KAPALI-BAŞARISIZ biçimde yetkisizleştirir.
    #
    # Önceden burada yalnızca `remaining_secs > 0` iken uyarı gönderiliyordu;
    # `exp` geçtikten sonra hiçbir şey yapılmıyordu. Token doğrulaması sadece
    # `sso_jwt_token` girdisi geldiğinde çalıştığı için, doğrulanmış bir Shiny
    # bağlantısı açık kaldığı sürece süresi dolmuş kullanıcının kimliği, yetkisi
    # ve kişisel API anahtarı sonraki işlemlerde kullanılmaya devam ediyordu.
    observe({
      # invalidateLater() EN BAŞTA çağrılır: req() önce kısa devre yaparsa
      # zamanlayıcı hiç kaydedilmez ve gözlemci kalıcı olarak ölür.
      #
      # DİKKAT: burada önceden `observe(...) |> bindEvent(invalidateLater(...))`
      # kullanılıyordu. invalidateLater() invisible(NULL) döndürür ve bindEvent()
      # varsayılan olarak ignoreNULL = TRUE olduğu için gözlemci HİÇ çalışmıyordu;
      # yani süre dolum uyarısı da bu kontrol de üretimde hiçbir zaman tetiklenmedi.
      invalidateLater(60000, session)  # Her dakika kontrol et

      req(sso_state$authenticated)
      claims <- sso_state$user_claims

      # Liste/nesne biçimindeki claim `as.numeric()` içinde HATA veriyordu.
      token_exp <- sso_numeric_claim(claims$token_exp)

      # Geçerli bir `exp` yoksa oturum düşürülmez (saat/ayrıştırma kaynaklı
      # yanlış çıkışları önlemek için muhafazakâr davranış). Token doğrulaması
      # zaten `exp` taşımayan token'ı reddeder.
      if (!is.finite(token_exp)) {
        return(invisible(NULL))
      }

      remaining_secs <- token_exp - as.numeric(Sys.time())
      margin <- SSO_CONFIG$token_refresh_margin_secs

      if (remaining_secs <= 0) {
        log_warn("SSO: Token süresi doldu; oturum yetkisizleştiriliyor (exp={token_exp}).")

        sso_state$authenticated <- FALSE
        sso_state$auth_level    <- NULL
        sso_state$user_claims   <- NULL
        sso_state$raw_token     <- NULL

        # Kimlik hazır bayrağı, ETKİN KULLANICI KİMLİĞİ ve kişisel API anahtarı
        # temizlenir. `user_id` bırakılırsa canlı kimlik sağlayıcısını doğrudan
        # okuyan gözlemciler (ör. Ortak Oturum oda yazma yetkisi) süresi dolmuş
        # oturumla çalışmaya devam ediyordu.
        # Alan kümesi `set_auth_placeholder()` (R/helpers_user_session_identity.R)
        # ile AYNI olmalıdır: `user_identity` ve `system_username` bırakıldığında
        # bu alanları doğrudan okuyan tüketiciler yetkisizleştirmeden sonra
        # önceki kimliği kullanmaya devam ediyordu.
        try({
          session$userData$auth_initialized <- FALSE
          session$userData$user_id <- 0L
          session$userData$user_identity <- NULL
          session$userData$user_config <- NULL
          session$userData$user_first_name <- NULL
          session$userData$system_username <- NULL
          session$userData$ai_api_key <- NULL
        }, silent = TRUE)

        # İstemci tarafı `sso_auth_error` işleyicisi saklanan token'ı temizler ve
        # yeniden kimlik doğrulama ekranını gösterir.
        session$sendCustomMessage("sso_auth_error", list(
          message = "Oturum süreniz doldu. Lütfen sayfayı yenileyerek tekrar giriş yapınız."
        ))

        return(invisible(NULL))
      }

      if (remaining_secs <= margin) {
        # Token süresi dolmak üzere - kullanıcıyı uyar
        session$sendCustomMessage("sso_token_expiring", list(
          remaining_seconds = round(remaining_secs)
        ))
      }
    })

    return(sso_state)
  })
}