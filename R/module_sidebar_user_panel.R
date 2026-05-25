# ============================================================
# Başlık: Sidebar Kullanıcı Paneli Modülü
# Dosya: R/module_sidebar_user_panel.R
# Açıklama: Yan menünün alt kısmında kullanıcı kimliği, tema anahtarı ve
#           sürüm bilgisini gösteren kompakt panel. Kimlik bilgisi mevcut
#           SSO/yerel kimlik çözümünden alınır; tek bir resmi sürüm kaynağı
#           olan get_current_version() üzerinden sürüm gösterilir. Bu modül
#           uygulamada başka kimlik kopyası oluşturmaz.
# ============================================================

#' Kullanıcı baş harflerini güvenli şekilde üret
#'
#' @description SSO veya yerel kullanıcı tam adından/ad bilgisinden iki harfli
#'   güvenli bir kısaltma üretir. Türkçe karakterler büyütülürken
#'   bozulmamalıdır.
#'
#' @param full_name Tam ad (örn. "Mustafa Karadağ")
#' @param first_name Yedek olarak ilk ad (örn. "Mustafa")
#' @return Baş harf (örn. "MK")
mb_sidebar_user_initials <- function(full_name = NULL, first_name = NULL) {
  pick <- function(value) {
    if (is.null(value)) return("")
    value <- trimws(as.character(value)[1])
    if (is.na(value) || !nzchar(value)) return("")
    value
  }

  primary <- pick(full_name)
  if (!nzchar(primary)) {
    primary <- pick(first_name)
  }

  if (!nzchar(primary)) {
    return("MB")
  }

  parts <- strsplit(primary, "\\s+", perl = TRUE)[[1]]
  parts <- parts[nzchar(parts)]
  if (length(parts) == 0L) {
    return("MB")
  }

  first_char <- function(token) {
    if (!nzchar(token)) return("")
    # Tek karakterli baş harf; Türkçe karakter bozulmasın
    if (exists("turkish_toupper", mode = "function", inherits = TRUE)) {
      return(turkish_toupper(substring(token, 1L, 1L)))
    }
    toupper(substring(token, 1L, 1L))
  }

  if (length(parts) >= 2L) {
    initials <- paste0(first_char(parts[1L]), first_char(parts[length(parts)]))
  } else {
    initials <- first_char(parts[1L])
  }

  if (!nzchar(initials)) {
    return("MB")
  }
  substring(initials, 1L, 2L)
}

#' Kullanıcı görsel URL'sini güvenli şekilde çöz
#'
#' @description Sohbet baloncuklarında kullanılan kullanıcı avatar URL
#'   şablonu burada da paylaşılır. URL yüklenemezse istemci tarafında
#'   onerror ile baş harf yedek ekrana geçilir.
#'
#' @param user_id Sayısal/karakter kullanıcı kimliği (sicil veya iç ID)
#' @return Karakter URL ya da boş dize
mb_sidebar_user_avatar_url <- function(user_id) {
  if (is.null(user_id)) return("")
  user_id <- as.character(user_id)[1]
  if (is.na(user_id) || !nzchar(user_id) || user_id %in% c("0", "unknown")) {
    return("")
  }
  paste0("https://url......./", user_id, ".jpg")
}

#' Sidebar kullanıcı paneli için tema anahtarı bileşeni
#'
#' @return Shiny tag (button)
mb_sidebar_theme_switch <- function() {
  tags$button(
    type = "button",
    class = "mb-theme-switch-btn",
    `data-mergen-theme-toggle` = "true",
    `aria-pressed` = "false",
    `aria-label` = "Temayı değiştir",
    title = "Temayı değiştir",
    tags$span(
      class = "theme-switch-icons",
      tags$i(class = "fas fa-sun theme-switch-sun"),
      tags$i(class = "fas fa-moon theme-switch-moon is-active")
    ),
    tags$span(class = "theme-switch-label", "Koyu tema"),
    tags$span(
      class = "theme-switch-track",
      `aria-hidden` = "true",
      tags$span(class = "theme-switch-thumb", `data-active` = "dark")
    )
  )
}

#' Sidebar kullanıcı paneli UI'sı
#'
#' @description Server tarafında dinamik render edilecek alanları içeren
#'   sabit kabuğu üretir. Gerçek isim, baş harf ve avatar değerleri
#'   uiOutput("sidebar_user_panel") üzerinden döndürülür.
#'
#' @param output_id Sunucu çıktısı için ID (varsayılan: "sidebar_user_panel")
#' @return Shiny div
mb_sidebar_user_panel_ui <- function(output_id = "sidebar_user_panel") {
  tags$div(
    class = "sidebar-footer",
    id = "sidebar-footer-container",
    # Kullanıcı kimliği (server tarafında doldurulur)
    uiOutput(output_id, inline = FALSE),
    # Tema anahtarı (her zaman görünür; durumu istemci yönetir)
    tags$div(
      class = "mb-sidebar-theme-row",
      mb_sidebar_theme_switch()
    ),
    # Sürüm satırı (tek doğru kaynak: get_current_version)
    tags$p(
      class = "sidebar-version",
      tags$span(class = "sidebar-version-prefix", "MERGEN Bilge"),
      tags$span(class = "sidebar-version-value",
                paste0("v", get_current_version()))
    ),
    tags$p(
      class = "sidebar-copyright",
      sprintf("%s Tüm hakları saklıdır.", format(Sys.Date(), "%Y"))
    )
  )
}

#' Sidebar kullanıcı bilgisi render bileşeni
#'
#' @description Kullanıcı tam adı, baş harf ve avatar yedeğini üreten saf
#'   UI fonksiyonudur. SSO/yerel ayrımı çağıran tarafta yapılır.
#'
#' @param full_name Görünür tam ad
#' @param first_name İlk ad (yedek)
#' @param user_id Avatar URL'sini üretmek için ID
#' @param role_text Alt satır rol metni (örn. "ASELSAN" / "Yerel Kullanıcı")
#' @return Shiny div
mb_sidebar_user_badge_ui <- function(full_name = NULL,
                                     first_name = NULL,
                                     user_id = NULL,
                                     role_text = NULL) {
  display_name <- if (!is.null(full_name) && nzchar(as.character(full_name)[1])) {
    as.character(full_name)[1]
  } else if (!is.null(first_name) && nzchar(as.character(first_name)[1])) {
    as.character(first_name)[1]
  } else {
    "Yerel Kullanıcı"
  }

  initials <- mb_sidebar_user_initials(full_name = display_name,
                                       first_name = first_name)
  avatar_url <- mb_sidebar_user_avatar_url(user_id)

  avatar_inner <- if (nzchar(avatar_url)) {
    tagList(
      tags$img(
        src = avatar_url,
        alt = display_name,
        onerror = "this.style.display='none'; var p=this.parentElement; if(p){var f=p.querySelector('.mb-sidebar-user-avatar-fallback'); if(f){f.style.display='flex';}}"
      ),
      tags$span(class = "mb-sidebar-user-avatar-fallback",
                style = "display:none;",
                initials)
    )
  } else {
    tags$span(class = "mb-sidebar-user-avatar-fallback", initials)
  }

  show_logout <- isTRUE(getOption("mergen.sidebar_show_logout", FALSE))

  tags$div(
    class = "mb-sidebar-user",
    tags$div(
      class = "mb-sidebar-user-avatar",
      avatar_inner
    ),
    tags$div(
      class = "mb-sidebar-user-info",
      tags$span(class = "mb-sidebar-user-name", display_name),
      if (!is.null(role_text) && nzchar(role_text)) {
        tags$span(class = "mb-sidebar-user-role", role_text)
      }
    ),
    if (isTRUE(show_logout)) {
      tags$button(
        type = "button",
        class = "mb-sidebar-user-logout",
        title = "Oturumu kapat",
        `aria-label` = "Oturumu kapat",
        onclick = "if(window.ssoLogout){window.ssoLogout();}",
        tags$i(class = "fas fa-right-from-bracket")
      )
    }
  )
}

#' Sidebar kullanıcı paneli server tarafı
#'
#' @description Kimlik bilgilerini reaktif olarak render eder. user_session
#'   live provider'ları kullanılır; SSO başlangıç anında değer hazır değilse
#'   geçici bir "Hazırlanıyor..." baloncuk gösterilir, ardından kimlik
#'   hazır olunca otomatik güncellenir.
#'
#' @param output Shiny output nesnesi
#' @param identity runtime_ctx$identity benzeri kimlik sözleşmesi
#' @param sso_state SSO durum reaktifi (opsiyonel)
#' @param output_id Sunucu çıktısı ID (varsayılan: "sidebar_user_panel")
mb_sidebar_user_panel_server <- function(output,
                                         identity,
                                         sso_state = NULL,
                                         output_id = "sidebar_user_panel") {
  if (is.null(output)) {
    return(invisible(NULL))
  }

  # SSO modunda window.ssoLogout mevcuttur; o yüzden çıkış butonunu yalnızca
  # SSO aktifken göster. Yerel modda butona yer vermeyiz.
  sso_logout_available <- tryCatch({
    sso_on <- exists("SSO_ENABLED", inherits = TRUE) && isTRUE(get("SSO_ENABLED"))
    if (!isTRUE(sso_on)) {
      FALSE
    } else {
      cfg <- if (exists("SSO_CONFIG", inherits = TRUE)) get("SSO_CONFIG") else NULL
      ep <- if (is.list(cfg)) cfg$logout_endpoint else NULL
      !is.null(ep) && nzchar(as.character(ep)[1])
    }
  }, error = function(e) FALSE)
  options(mergen.sidebar_show_logout = isTRUE(sso_logout_available))

  if (is.null(identity) ||
      !is.function(identity$get_display_name %||% NULL)) {
    # Kimlik sözleşmesi yoksa basit yedek render
    output[[output_id]] <- shiny::renderUI({
      mb_sidebar_user_badge_ui(
        full_name = "Yerel Kullanıcı",
        first_name = NULL,
        user_id = NULL,
        role_text = "MERGEN Bilge"
      )
    })
    return(invisible(NULL))
  }

  get_first_name <- identity$get_first_name %||% function(default = "") default
  get_display_name <- identity$get_display_name %||% function(default = "") default
  resolve_uid <- identity$resolve_current_user_id %||% function() 0L
  is_auth_ready <- identity$is_auth_ready %||% function() TRUE
  is_sso_active <- identity$is_sso_active %||% function() FALSE
  get_user_config <- identity$get_user_config %||% function(default = NULL) default
  get_auth_source <- identity$get_auth_source %||% function(default = NULL) default

  output[[output_id]] <- shiny::renderUI({
    # SSO modunda authenticated reaktifini izle; yerel modda no-op
    if (!is.null(sso_state) && !is.null(sso_state$authenticated)) {
      tryCatch({
        # reaktif consumer içindeyiz; sso_state$authenticated'ı bağlamak
        # SSO oturum kurulduktan sonra panelin otomatik güncellenmesini sağlar
        sso_state$authenticated
      }, error = function(e) NULL)
    }

    auth_ready <- isTRUE(tryCatch(is_auth_ready(), error = function(e) FALSE))
    sso_active <- isTRUE(tryCatch(is_sso_active(), error = function(e) FALSE))

    # SSO açıkken kimlik hazır değilse hazırlanma rozetini göster
    if (isTRUE(sso_active) && !isTRUE(auth_ready)) {
      return(mb_sidebar_user_badge_ui(
        full_name = "Oturum hazırlanıyor",
        first_name = NULL,
        user_id = NULL,
        role_text = "Kimlik doğrulanıyor..."
      ))
    }

    full_name <- tryCatch(get_display_name(default = ""),
                          error = function(e) "")
    first_name <- tryCatch(get_first_name(default = ""),
                           error = function(e) "")
    uid <- tryCatch(resolve_uid(), error = function(e) 0L)
    user_cfg <- tryCatch(get_user_config(default = NULL),
                         error = function(e) NULL)
    src <- tryCatch(get_auth_source(default = NULL),
                    error = function(e) NULL)

    role_text <- NULL
    if (!is.null(user_cfg)) {
      role_text <- user_cfg$mudurluk %||% user_cfg$department %||%
                   user_cfg$sektor %||% NULL
    }
    if (is.null(role_text) || !nzchar(as.character(role_text)[1])) {
      role_text <- if (identical(src, "keycloak")) "ASELSAN" else "MERGEN Bilge"
    }

    sicil <- if (!is.null(user_cfg)) user_cfg$sicil else NULL
    avatar_id <- if (!is.null(sicil) && nzchar(as.character(sicil)[1])) sicil else uid

    if (!nzchar(full_name) && !nzchar(first_name)) {
      full_name <- "Yerel Kullanıcı"
    }

    mb_sidebar_user_badge_ui(
      full_name = full_name,
      first_name = first_name,
      user_id = avatar_id,
      role_text = role_text
    )
  })

  invisible(NULL)
}
