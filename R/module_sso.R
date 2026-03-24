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
        normalized_kaynak_adi <- ensure_utf8(fixTurkishEncoding(auth_info$kaynak_adi))
        claims$full_name  <- normalized_kaynak_adi
        claims$first_name <- extractFirstName(normalized_kaynak_adi)
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
    # Token süresinin dolmasına yakın kullanıcıyı uyar
    observe({
      req(sso_state$authenticated)
      claims <- sso_state$user_claims

      if (!is.null(claims$token_exp)) {
        remaining_secs <- claims$token_exp - as.numeric(Sys.time())
        margin <- SSO_CONFIG$token_refresh_margin_secs

        if (remaining_secs > 0 && remaining_secs <= margin) {
          # Token süresi dolmak üzere - kullanıcıyı uyar
          session$sendCustomMessage("sso_token_expiring", list(
            remaining_seconds = round(remaining_secs)
          ))
        }
      }
    }) |> bindEvent(invalidateLater(60000, session))  # Her dakika kontrol et

    return(sso_state)
  })
}