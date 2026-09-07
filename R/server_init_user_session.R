# ==============================================================================
# Dosya Yolu: R/server_init_user_session.R
# Açıklama: server.R içindeki kullanıcı kimliği, SSO/local oturum kurulumu ve
#           canlı current_user_id provider sözleşmesini tek yerde toplar.
# ==============================================================================

local({
  gerekli_kimlik_yardimcilari <- c(
    "build_user_session_config",
    "merge_user_profile_into_identity",
    "apply_user_session_identity",
    "make_current_user_id_provider",
    "make_user_session_data_accessors"
  )

  eksik_kimlik_yardimcilari <- gerekli_kimlik_yardimcilari[!vapply(
    gerekli_kimlik_yardimcilari,
    function(ad) exists(ad, mode = "function", inherits = TRUE),
    logical(1)
  )]

  if (length(eksik_kimlik_yardimcilari) > 0L) {
    stop(
      sprintf(
        paste0(
          "server_init_user_session.R yüklenmeden önce ",
          "R/helpers_user_session_identity.R yüklenmelidir. Eksik: %s"
        ),
        paste(eksik_kimlik_yardimcilari, collapse = ", ")
      ),
      call. = FALSE
    )
  }
})

serverInitUserSession <- function(session,
                                  session_cache,
                                  sso_state,
                                  base_user_config,
                                  sso_enabled = SSO_ENABLED,
                                  resolve_identity_fn = resolveUserIdentity,
                                  get_or_create_user_fn = get_or_create_user,
                                  get_user_profile_fn = NULL,
                                  touch_session_fn = NULL) {
  user_config_rv <- shiny::reactiveVal(NULL)
  current_user_id <- 0L
  auth_ready <- FALSE
  last_cache_dir <- NULL
  session_data <- make_user_session_data_accessors(session)
  
  if (is.null(get_user_profile_fn) &&
      exists("get_user_profile_from_db", mode = "function", inherits = TRUE)) {
    get_user_profile_fn <- get("get_user_profile_from_db", mode = "function", inherits = TRUE)
  }

  if (!is.null(get_user_profile_fn) && !is.function(get_user_profile_fn)) {
    get_user_profile_fn <- NULL
  }

  set_current_user_id <- function(user_id) {
    current_user_id <<- .normalize_user_session_id(
      user_id,
      allow_zero = TRUE
    )

    invisible(current_user_id)
  }

  user_id_provider_bundle <- make_current_user_id_provider(
    session = session,
    current_user_id_ref = function() current_user_id
  )

  setup_user_identity <- function(user_identity, user_id, sso_active, auth_source) {
    uid <- set_current_user_id(user_id)

    user_profile <- NULL

    if (!is.null(get_user_profile_fn) && uid > 0L) {
      user_profile <- tryCatch(
        get_user_profile_fn(
          user_id = uid,
          username = user_identity$username %||% NULL
        ),
        error = function(e) {
          if (exists("log_warn", mode = "function", inherits = TRUE)) {
            log_warn("MB_Users kullanıcı profili okunamadı (UserID={uid}): {e$message}")
          }
          NULL
        }
      )
    }

    user_identity <- merge_user_profile_into_identity(
      user_identity = user_identity,
      user_profile = user_profile
    )

    app_user_config <- build_user_session_config(
      user_identity = user_identity,
      user_id = uid,
      base_user_config = base_user_config,
      auth_source = auth_source
    )

    apply_user_session_identity(
      session = session,
      user_identity = user_identity,
      user_id = uid,
      app_user_config = app_user_config,
      sso_active = sso_active,
      auth_source = auth_source,
      # `auth_initialized` doğrudan okuyan tüketiciler uid = 0 iken oturumu
      # hazır sayıyordu; yerel dalda get_or_create_user_fn() hata vermeden 0
      # döndürdüğünde bu yol hâlâ erişilebilirdi.
      auth_initialized = uid > 0L
    )

    user_config_rv(app_user_config)

    if (is.list(session_cache) && is.function(session_cache$setup_user_session)) {
      last_cache_dir <<- session_cache$setup_user_session(uid)
    }

    if (isTRUE(sso_active) && is.function(touch_session_fn)) {
      try(touch_session_fn(uid), silent = TRUE)
    }

    # auth_ready yalnızca GERÇEK bir kullanıcı kimliği çözüldüğünde TRUE olur;
    # uid = 0 iken TRUE dönmek kimlik doğrulamayı fail-open yapıyordu.
    auth_ready <<- uid > 0L

    invisible(list(
      user_id = uid,
      user_identity = user_identity,
      user_config = app_user_config,
      cache_dir = last_cache_dir
    ))
  }

  if (!isTRUE(sso_enabled)) {
    user_identity <- resolve_identity_fn()
    system_username <- user_identity$username
    uid <- get_or_create_user_fn(system_username)

    setup_user_identity(
      user_identity = user_identity,
      user_id = uid,
      sso_active = FALSE,
      auth_source = "local"
    )
  } else {
    # En son UYGULANAN (DB profili birleştirilmeden ÖNCEKİ) SSO kimliği.
    # Aynı kullanıcı adı için gelen İKİNCİ token yetki (`auth_level`) veya
    # görünür claim alanlarını değiştirdiğinde kimliğin yeniden uygulanması
    # gerekir; aksi hâlde oturum önceki (daha yüksek) yetkiyi koruyordu.
    son_uygulanan_kimlik <- NULL

    # Başarısız kimlik kurulumu oturumu ÖNCEKİ kullanıcıda bırakmamalıdır:
    # claim'ler A kullanıcısından B kullanıcısına geçtiğinde ve kurulum
    # başarısız olduğunda `current_user_id` / `auth_ready` / `session$userData`
    # hâlâ A kullanıcısını gösteriyor ve korumalı işlemler A adına sürüyordu.
    sso_kimligini_sifirla <- function() {
      set_current_user_id(0L)
      auth_ready <<- FALSE
      son_uygulanan_kimlik <<- NULL
      user_config_rv(NULL)
      session_data$set_auth_placeholder(
        sso_active = TRUE,
        auth_source = "keycloak"
      )
      invisible(NULL)
    }

    set_current_user_id(0L)
    session_data$set_auth_placeholder(
      sso_active = TRUE,
      auth_source = "keycloak"
    )

    # Önemli: Bu observer yüksek öncelikle çalışır. SSO doğrulandığında
    # (sso_state$authenticated FALSE -> TRUE) birden çok observer aynı
    # flush turunda tetiklenir: kayıtlı sohbetler, dosya yöneticisi
    # yenilemesi, geri bildirim yüklemesi, görsel galerisi. Bunların
    # hepsi kimlik kurulumunun (user_id ve auth_ready) tamamlanmış
    # olmasına bağlıdır. priority yüksek tutularak kimlik kurulumunun
    # her zaman diğer auth observer'larından ÖNCE çalışması garanti
    # edilir; aksi halde ilk girişte dosya/sohbet yüklemesi user_id=0
    # ile atlanabilir ve yalnızca tarayıcı yenilemesinde düzelir.
    # `user_claims` de izlenir: `authenticated` zaten TRUE iken gelen İKİNCİ
    # token claim'leri değiştiriyor ancak gözlemci çalışmıyordu; oturum kimliği
    # ilk kullanıcıda kalırken talepler ikinci kullanıcıyı gösteriyordu.
    observeEvent(list(sso_state$authenticated, sso_state$user_claims), {
      req(isTRUE(sso_state$authenticated))

      claims <- sso_state$user_claims
      user_identity <- resolve_identity_fn(sso_claims = claims)
      system_username <- as.character(user_identity$username %||% "")[1]

      # Hazır-kimlik guard'ı YALNIZCA aynı kullanıcı için erken döner: token
      # süresi dolup oturum sıfırlandıktan sonra yeniden doğrulama kimliği
      # tekrar kurabilmelidir (aksi hâlde oturum kalıcı olarak uid = 0 kalır).
      mevcut_kullanici <- as.character(session_data$get_system_username(default = "") %||% "")[1]
      if (isTRUE(auth_ready) && nzchar(system_username) &&
          identical(mevcut_kullanici, system_username)) {
        # Kimlik DEĞİŞMEDİYSE (aynı yetki/claim kümesi) DB'ye gitmeye gerek yok.
        if (identical(son_uygulanan_kimlik, user_identity)) {
          return(invisible(NULL))
        }

        # Yetki/claim değişti: mevcut kullanıcı kimliğiyle (yeni DB araması
        # yapılmadan) kimlik YENİDEN uygulanır, böylece düşürülen `yetki`
        # oturuma da yansır.
        setup_user_identity(
          user_identity = user_identity,
          user_id = current_user_id,
          sso_active = TRUE,
          auth_source = "keycloak"
        )
        son_uygulanan_kimlik <<- user_identity

        log_info(
          "SSO yetki talepleri yenilendi: kullanıcı={system_username}, yetki={user_identity$auth_level}"
        )
        return(invisible(NULL))
      }

      # Claim yokken kimlik "unauthenticated" döner; boş kullanıcı adıyla
      # DB'ye gitmek validate_username üzerinden hata fırlatıyordu. Oturum
      # yetkisiz durumda (uid = 0, auth_ready = FALSE) bırakılır.
      if (is.na(system_username) || !nzchar(system_username)) {
        log_warn("SSO doğrulandı ancak kullanıcı claim'leri yok; kimlik kurulmadı.")
        sso_kimligini_sifirla()
        return(invisible(NULL))
      }

      uid <- get_or_create_user_fn(system_username, sso_claims = claims)

      # Kimlik çözülemezse oturum uid = 0 / auth_ready = FALSE kalır ve
      # `authenticated` yeniden değişmediği için gözlemci tekrar tetiklenmez.
      # Sessiz kalmaz: operatör için açık hata kaydı bırakılır.
      if (!isTRUE(suppressWarnings(as.integer(uid[1]) > 0L))) {
        log_error(
          "SSO kullanıcı kimliği çözülemedi: kullanıcı={system_username}; oturum yetkisiz kalıyor."
        )
        # Kurulum burada durur: setup_user_identity() `auth_initialized = TRUE`
        # yazıyor ve akış başarısız kurulumu "SSO oturum kuruldu" olarak
        # raporluyordu.
        sso_kimligini_sifirla()
        return(invisible(NULL))
      }

      setup_user_identity(
        user_identity = user_identity,
        user_id = uid,
        sso_active = TRUE,
        auth_source = "keycloak"
      )
      son_uygulanan_kimlik <<- user_identity

      log_info(
        "SSO oturum kuruldu: kullanıcı={system_username}, id={uid}, yetki={user_identity$auth_level}"
      )
    }, ignoreInit = TRUE, priority = 1000L)

    # SSO oturumu YETKİSİZLEŞTİĞİNDE (token süresi doldu) etkin kimlik
    # sıfırlanır. Yalnızca session$userData temizlenirse canlı sağlayıcının
    # kapanış anlık görüntüsü (`current_user_id`) hâlâ kimliği doğrulanmış
    # kullanıcıyı döndürüyor ve korumalı gözlemciler çalışmaya devam ediyordu.
    observeEvent(sso_state$authenticated, {
      if (isTRUE(sso_state$authenticated)) return(invisible(NULL))

      sso_kimligini_sifirla()
    }, ignoreInit = TRUE, priority = 1000L)
  }

  get_user_config <- function(default = NULL) {
    cfg <- tryCatch(
      shiny::isolate(user_config_rv()),
      error = function(e) NULL
    )

    if (!is.null(cfg)) {
      return(cfg)
    }

    session_data$get_user_config(default = default)
  }

  get_first_name <- function(default = "") {
    cfg <- get_user_config()

    value <- cfg$first_name %||%
      session_data$get_first_name(default = NULL) %||%
      default

    value <- as.character(value %||% default)

    if (!nzchar(value)) {
      return(default)
    }

    value
  }

  get_display_name <- function(default = "Kullanıcı") {
    cfg <- get_user_config()

    value <- cfg$name %||%
      get_first_name(default = default) %||%
      default

    value <- as.character(value %||% default)

    if (!nzchar(value)) {
      return(default)
    }

    value
  }

  get_auth_source <- function(default = NULL) {
    fallback_source <- default %||%
      if (isTRUE(sso_enabled)) "keycloak" else "local"

    session_data$get_auth_source(default = fallback_source)
  }

  list(
    user_config_rv = user_config_rv,
    resolve_current_user_id = user_id_provider_bundle$resolve_current_user_id,
    current_user_id_provider = user_id_provider_bundle$current_user_id_provider,
    is_auth_ready = function() isTRUE(auth_ready),
    is_sso_active = function() isTRUE(sso_enabled),
    get_auth_source = get_auth_source,
    get_user_config = get_user_config,
    get_first_name = get_first_name,
    get_display_name = get_display_name,
    get_current_user_id_snapshot = function() current_user_id,
    get_cache_dir = function() last_cache_dir
  )
}