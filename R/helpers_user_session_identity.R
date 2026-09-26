# ==============================================================================
# Dosya Yolu: R/helpers_user_session_identity.R
# Açıklama: Kullanıcı oturumu kimlik/config yardımcılarını saf ve test edilebilir
#           şekilde toplar. Shiny observer veya veritabanı işlemi içermez.
# ==============================================================================

.normalize_user_session_id <- function(user_id, allow_zero = TRUE) {
  # Kayıplı dönüşüm reddedilir (`as.integer(1.9)` -> 1): ortak kanonik
  # doğrulayıcı sıfır olmayan yalnızca tam sayı kimlikleri kabul eder.
  uid <- if (exists("mergen_canonical_user_id", mode = "function", inherits = TRUE)) {
    mergen_canonical_user_id(user_id %||% 0L)
  } else {
    # YEDEK YOL da kayıplı dönüşümü reddeder: `as.integer(1.9)` sessizce `1`
    # üretip oturumu BAŞKA bir geçerli kullanıcıya yönlendirebiliyordu.
    # `.Machine$integer.max` üstü değer `as.integer()` ile `NA` olur ve
    # aşağıdaki `if (uid <= 0L)` "missing value where TRUE/FALSE needed"
    # hatasına düşer; dönüşümden ÖNCE reddedilir.
    # TÜR DENETİMİ dönüşümden ÖNCE gelir (kanonik yardımcıyla aynı kural):
    # `as.numeric(TRUE)` değeri `1` üretiyor ve mantıksal bir kimlik oturumu
    # KULLANICI 1'e bağlayabiliyordu; liste biçimli bir değer ise dönüşüm
    # sırasında doğrulama hiç çalışmadan hata fırlatıyordu. Karakter kimlik
    # yalnızca SAF ONDALIK basamaklardan oluşabilir ("1e2" reddedilir).
    ham <- user_id %||% 0L
    deger <- if (is.character(ham) && length(ham) == 1L && !is.na(ham) &&
                 grepl("^[0-9]+$", trimws(ham))) {
      suppressWarnings(as.numeric(trimws(ham)))
    } else if (is.numeric(ham) && !is.logical(ham) && length(ham) == 1L) {
      suppressWarnings(as.numeric(ham))
    } else {
      NA_real_
    }
    if (length(deger) != 1L || is.na(deger) || !is.finite(deger) ||
        deger <= 0 || deger != trunc(deger) ||
        deger > .Machine$integer.max) {
      0L
    } else {
      suppressWarnings(as.integer(deger))
    }
  }

  if (uid <= 0L) return(0L)
  uid
}

merge_user_profile_into_identity <- function(user_identity, user_profile = NULL) {
  if (is.null(user_identity) || !is.list(user_identity)) {
    user_identity <- list()
  }

  if (is.null(user_profile) || !is.list(user_profile)) {
    return(user_identity)
  }

  pick_non_empty <- function(keys, fallback = NULL) {
    for (key in keys) {
      value <- user_profile[[key]]
      if (!is.null(value)) {
        value <- trimws(as.character(value)[1])
        if (!is.na(value) && nzchar(value)) {
          return(value)
        }
      }
    }

    fallback <- fallback %||% ""
    fallback <- trimws(as.character(fallback)[1])
    if (is.na(fallback)) "" else fallback
  }

  previous_full_name <- user_identity$full_name %||% ""

  user_identity$username <- pick_non_empty(
    c("KullaniciAdi", "username"),
    user_identity$username
  )

  user_identity$full_name <- pick_non_empty(
    c("KaynakAdi", "name", "full_name"),
    user_identity$full_name
  )

  user_identity$sicil <- pick_non_empty(
    c("Sicil", "sicil"),
    user_identity$sicil
  )

  user_identity$email <- pick_non_empty(
    c("Email", "email"),
    user_identity$email
  )

  user_identity$sektor <- pick_non_empty(
    c("Sektor", "sektor"),
    user_identity$sektor
  )

  user_identity$department <- pick_non_empty(
    c("Departman", "department", "departman"),
    user_identity$department
  )

  user_identity$mudurluk <- pick_non_empty(
    c("Mudurluk", "mudurluk"),
    user_identity$mudurluk
  )

  user_identity$masraf_yeri_kodu <- pick_non_empty(
    c("MasrafYeriKodu", "masraf_yeri_kodu"),
    user_identity$masraf_yeri_kodu
  )

  # DB'deki KaynakAdi geldiyse first_name de ona göre güncellensin.
  if (
    nzchar(user_identity$full_name %||% "") &&
    (
      !nzchar(user_identity$first_name %||% "") ||
      !identical(previous_full_name, user_identity$full_name)
    ) &&
    exists("extractFirstName", mode = "function", inherits = TRUE)
  ) {
    user_identity$first_name <- extractFirstName(user_identity$full_name)
  }

  user_identity
}

# Oturum sahibi geçişi (aynı Shiny oturumunda A -> B ya da kimlik kaybı).
# A -> B değişiminde kullanıcıya bağlı oturum depoları (dosya kayıt defteri,
# özetler, grafikler, MCP anlık görüntüsü) ve kişisel API anahtarı temizlenir;
# A'nın yolu/anahtarı B'nin isteğine taşınmaz. Değişimde ve kimlik kaybında
# kayıtlı kancalar (ör. süren özet işinin iptali) çalışır. Reaktif kimlik
# sinyali kullanıcı kimliği ya da yetki düzeyi her değiştiğinde artar.
mergen_session_owner_transition <- function(user_data, eski_uid, yeni_uid, yetki_degisti = FALSE) {
  if (!is.environment(user_data)) return(invisible(FALSE))
  eski <- .normalize_user_session_id(eski_uid)
  yeni <- .normalize_user_session_id(yeni_uid)
  sahip <- .normalize_user_session_id(user_data$kimlik_sahibi %||% 0L)
  degisti <- yeni > 0L && sahip > 0L && !identical(yeni, sahip)
  kayip <- yeni <= 0L && eski > 0L
  if (yeni > 0L) user_data$kimlik_sahibi <- yeni
  if (degisti) {
    anahtarlar <- if (exists("SESSION_RUNTIME_STORE_KEYS", inherits = TRUE)) {
      unname(SESSION_RUNTIME_STORE_KEYS)
    } else {
      c("current_session_files", "file_summaries", "chart_store", "mcp_registry_snapshot")
    }
    for (anahtar in anahtarlar) user_data[[anahtar]] <- list()
    user_data$ai_api_key <- NULL
  }
  kancalar <- user_data$kimlik_kancalari
  if ((degisti || kayip) && is.environment(kancalar)) {
    neden <- if (degisti) "sahip_degisti" else "kimlik_kaybi"
    for (ad in ls(kancalar, all.names = TRUE)) try(kancalar[[ad]](neden), silent = TRUE)
  }
  sinyal <- user_data$kimlik_sinyali
  if ((!identical(eski, yeni) || isTRUE(yetki_degisti)) && is.function(sinyal)) {
    try(sinyal(shiny::isolate(sinyal()) + 1L), silent = TRUE)
  }
  invisible(degisti)
}

# Sahip değişimi/kimlik kaybı kancası kaydeder; kaydı silen fonksiyon döner.
mergen_session_on_owner_change <- function(session, fn) {
  user_data <- tryCatch(session$userData, error = function(e) NULL)
  if (!is.environment(user_data) || !is.function(fn)) return(function() invisible(NULL))
  if (!is.environment(user_data$kimlik_kancalari)) user_data$kimlik_kancalari <- new.env(parent = emptyenv())
  kancalar <- user_data$kimlik_kancalari
  ad <- basename(tempfile("kanca_"))
  kancalar[[ad]] <- fn
  function() {
    if (exists(ad, envir = kancalar, inherits = FALSE)) rm(list = ad, envir = kancalar)
    invisible(NULL)
  }
}

# Oturum kimliği değişince artan reaktif sinyal: gözlemciler kimliği
# yoklamak yerine buna bağımlı olur.
mergen_session_identity_signal <- function(session) {
  user_data <- tryCatch(session$userData, error = function(e) NULL)
  if (!is.environment(user_data)) return(function() 0L)
  if (!is.function(user_data$kimlik_sinyali)) user_data$kimlik_sinyali <- shiny::reactiveVal(0L)
  user_data$kimlik_sinyali
}

make_user_session_data_accessors <- function(session) {
  if (is.null(session) || is.null(session$userData)) {
    stop(
      "make_user_session_data_accessors: session$userData bulunamadı.",
      call. = FALSE
    )
  }

  user_data <- session$userData

  get_value <- function(key, default = NULL) {
    if (exists(key, envir = user_data, inherits = FALSE)) {
      value <- get(key, envir = user_data, inherits = FALSE)

      if (!is.null(value)) {
        return(value)
      }
    }

    default
  }

  set_value <- function(key, value) {
    user_data[[key]] <- value
    invisible(value)
  }

  list(
    write_identity = function(user_identity,
                              user_id,
                              app_user_config,
                              sso_active,
                              auth_source,
                              auth_initialized = TRUE) {
      uid <- .normalize_user_session_id(user_id, allow_zero = TRUE)
      eski_uid <- get_value("user_id", 0L)
      eski_yetki <- get_value("user_config", list())$auth_level

      set_value("user_identity", user_identity)
      set_value("user_first_name", user_identity$first_name)
      set_value("system_username", user_identity$username)
      set_value("user_id", uid)
      set_value("sso_active", isTRUE(sso_active))
      set_value("auth_source", auth_source)
      set_value("auth_initialized", isTRUE(auth_initialized))
      set_value("user_config", app_user_config)
      # Aynı kullanıcının yetki düzeyi değişirse de sinyal artar (ör. ADMIN kaybı).
      mergen_session_owner_transition(user_data, eski_uid, uid,
                                      yetki_degisti = !identical(eski_yetki, app_user_config$auth_level))

      invisible(app_user_config)
    },

    set_auth_placeholder = function(sso_active = TRUE,
                                    auth_source = "keycloak") {
      eski_uid <- get_value("user_id", 0L)
      set_value("user_id", 0L)
      set_value("sso_active", isTRUE(sso_active))
      set_value("auth_source", auth_source)
      set_value("auth_initialized", FALSE)
      # Kimlik alanları da temizlenir: bunları doğrudan okuyan gözlemciler,
      # token süresi dolduktan sonra önceki kullanıcının adını/yapılandırmasını
      # kullanmaya devam ediyordu.
      set_value("user_identity", NULL)
      set_value("user_config", NULL)
      set_value("user_first_name", NULL)
      set_value("system_username", NULL)
      mergen_session_owner_transition(user_data, eski_uid, 0L)

      invisible(NULL)
    },

    get_user_id = function(default = 0L) {
      .normalize_user_session_id(
        get_value("user_id", default),
        allow_zero = TRUE
      )
    },

    get_user_config = function(default = NULL) {
      get_value("user_config", default)
    },

    get_first_name = function(default = "") {
      get_value("user_first_name", default)
    },

    # SSO claim DEĞİŞİMİNİ (aynı oturumda ikinci kullanıcı) saptamak için
    # gereklidir: gözlemci yalnızca aynı kullanıcı için erken dönebilmelidir.
    get_system_username = function(default = "") {
      get_value("system_username", default)
    },

    get_auth_source = function(default = NULL) {
      get_value("auth_source", default)
    }
  )
}

build_user_session_config <- function(user_identity,
                                      user_id,
                                      base_user_config,
                                      auth_source = NULL) {
  auth_source <- auth_source %||% user_identity$auth_source %||% "local"
  is_sso <- identical(auth_source, "keycloak")

  full_name <- user_identity$full_name %||% ""
  department <- user_identity$department %||% user_identity$Departman %||% ""
  sektor <- user_identity$sektor %||% user_identity$Sektor %||% ""
  mudurluk <- user_identity$mudurluk %||% user_identity$Mudurluk %||% ""
  masraf_yeri_kodu <- user_identity$masraf_yeri_kodu %||%
    user_identity$MasrafYeriKodu %||% ""

  list(
    name       = full_name,
    KaynakAdi  = full_name,
    icon       = base_user_config$icon,
    userId     = if (is_sso) {
      user_identity$sicil %||% as.character(user_id)
    } else {
      as.character(user_id)
    },
    KullaniciAdi = user_identity$username,
    auth_level = if (is_sso) {
      user_identity$auth_level %||% base_user_config$auth_level
    } else {
      base_user_config$auth_level
    },
    sicil             = user_identity$sicil,
    Sicil             = user_identity$sicil,
    email             = user_identity$email,
    Email             = user_identity$email,
    first_name        = user_identity$first_name,
    last_name         = user_identity$last_name,
    sektor            = sektor,
    Sektor            = sektor,
    department        = department,
    Departman         = department,
    mudurluk          = mudurluk,
    Mudurluk          = mudurluk,
    masraf_yeri_kodu  = masraf_yeri_kodu,
    MasrafYeriKodu    = masraf_yeri_kodu
  )
}

apply_user_session_identity <- function(session,
                                        user_identity,
                                        user_id,
                                        app_user_config,
                                        sso_active,
                                        auth_source,
                                        auth_initialized = TRUE) {
  session_data <- make_user_session_data_accessors(session)

  session_data$write_identity(
    user_identity = user_identity,
    user_id = user_id,
    app_user_config = app_user_config,
    sso_active = sso_active,
    auth_source = auth_source,
    auth_initialized = auth_initialized
  )
}

make_current_user_id_provider <- function(session, current_user_id_ref) {
  if (!is.function(current_user_id_ref)) {
    snapshot_user_id <- current_user_id_ref
    current_user_id_ref <- function() snapshot_user_id
  }

  resolve_current_user_id <- function() {
    resolve_effective_user_id(
      session = session,
      current_user_id = current_user_id_ref
    )
  }

  list(
    resolve_current_user_id = resolve_current_user_id,
    current_user_id_provider = resolve_current_user_id
  )
}