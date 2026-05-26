# ============================================================
# Başlık: Sidebar Kullanıcı Paneli Modülü
# Dosya: R/module_sidebar_user_panel.R
# Açıklama: Yan menünün alt kısmında kullanıcı kimliği, tema anahtarı ve
#           sürüm bilgisini gösteren kompakt panel. Kimlik bilgisi mevcut
#           SSO/yerel kimlik çözümünden alınır; tek bir resmi sürüm kaynağı
#           olan get_current_version() üzerinden sürüm gösterilir. Bu modül
#           uygulamada başka kimlik kopyası oluşturmaz.
#
# Düzen:
#   1. Kullanıcı avatarı + tam ad + Departman (MB_Users) satırı
#   2. Tema anahtarı (ikon + "Koyu Tema"/"Açık Tema" etiketi) ve
#      yanında küçük çıkış butonu (yalnızca SSO + logout endpoint varsa)
#   3. Sürüm satırı (tek doğru kaynak: get_current_version())
#
# Eski stil "switch track + thumb" görseli kaldırıldı; tek bir kompakt
# buton korunur. Departman değeri MB_Users tablosundan gelir (user_cfg
# üzerinden); "Mudurluk" görünür alan olarak gösterilmez.
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

#' Departman değerini güvenli şekilde çöz
#'
#' @description user_config nesnesinde MB_Users Departman alanını öncelikli
#'   olarak okur. Bilinen alternatif alan adlarını (`Departman`, `departman`,
#'   `department`) tolere eder. Değer yoksa boş dize döner.
#'
#'   Bu helper yeni bir DB sorgusu açmaz: kimlik kurulduğunda
#'   `build_user_session_config()` zaten Departman değerini user_config'e
#'   yerleştirir (SSO claim `department` veya `Departman`).
#'
#' @param user_cfg user_config listesi (NULL olabilir)
#' @return Karakter (boş dize olabilir)
mb_sidebar_user_department <- function(user_cfg = NULL) {
  if (is.null(user_cfg)) return("")
  if (!is.list(user_cfg)) return("")

  pick <- function(key) {
    val <- user_cfg[[key]]
    if (is.null(val)) return("")
    val <- as.character(val)[1]
    if (is.na(val)) return("")
    trimws(val)
  }

  # Tercih sırası: Departman -> departman -> department
  candidates <- c(pick("Departman"), pick("departman"), pick("department"))
  for (c in candidates) {
    if (nzchar(c)) {
      return(c)
    }
  }
  ""
}

#' Sidebar kullanıcı paneli için tema anahtarı bileşeni
#'
#' @description Kompakt tek-satır tema butonu. Eski "switch track + thumb"
#'   görseli kaldırıldı; ikon + etiket yeterli. Etiket "Koyu Tema" ile
#'   başlar; istemci tarafı tema durumuna göre "Açık Tema" olarak
#'   güncellenir.
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
    tags$span(class = "theme-switch-label", "Koyu Tema")
  )
}

#' Sidebar kompakt kontrol satırı (tema butonu + opsiyonel çıkış)
#'
#' @description Tema butonu büyük, çıkış butonu küçük; aynı satırda yer alır.
#'   Çıkış butonu yalnızca yapılandırılmış logout URL'si mevcutsa render
#'   edilir.
#'
#' Çıkış davranışı sözleşmesi:
#'   - Kullanıcı çıkış butonuna bastığında DOĞRUDAN `.Renviron` üzerinden
#'     gelen MERGEN_LOGOUT_URL adresine yönlendirilir.
#'   - Hiçbir ara Keycloak logout akışı çalıştırılmaz; aksi halde tarayıcı
#'     uygulamanın yükleme ekranına geri dönüyordu.
#'   - URL boşsa buton zaten render edilmez (server tarafı koşulu).
#'   - `window.ssoLogout` çağrılmaz çünkü o akış çıkıştan sonra uygulamayı
#'     yeniden açıyordu; istek bunu önlemektir.
#'
#' @param show_logout Mantıksal; çıkış URL'si yapılandırılmış mı?
#' @param logout_url .Renviron'dan çözümlenmiş hedef URL (boş olabilir)
#' @return Shiny div
mb_sidebar_controls_row <- function(show_logout = FALSE, logout_url = "") {
  logout_btn <- if (isTRUE(show_logout)) {
    # Çıkış URL'si .Renviron (MERGEN_LOGOUT_URL) tarafından kontrol edilir.
    # Buton tıklandığında SSO ara adımı atlanır; tarayıcı doğrudan URL'ye
    # yönlendirilir. Bu hem yerel kurumsal portal hem SSO/Keycloak hem de
    # özel bir landing sayfası senaryosunu basit ve öngörülebilir kılar.
    safe_url <- ""
    if (is.character(logout_url) && length(logout_url) == 1 &&
        !is.na(logout_url) && nzchar(logout_url)) {
      # JS string olarak gömerken tek tırnak ve geri eğik çizgi kaçırma
      safe_url <- gsub("'", "\\\\'",
                       gsub("\\\\", "\\\\\\\\", logout_url, fixed = FALSE),
                       fixed = FALSE)
    }
    onclick_js <- if (nzchar(safe_url)) {
      # Tarayıcı yönlendirmeden ÖNCE Shiny tarafına bir oturum-kapatma
      # olayı gönderilir. Sunucu tarafındaki observeEvent bu olayı görür,
      # konsola logout işlemini yazar ve mevcut Shiny oturumunu kapatır.
      # Bu sayede kullanıcı redirect olduktan sonra Shiny oturumu da
      # gerçekten sonlandırılır (sızıntı önlenir, doğrulama mümkün olur).
      paste0(
        "try{if(window.Shiny&&window.Shiny.setInputValue){",
        "Shiny.setInputValue('mergen_sidebar_logout',new Date().getTime(),{priority:'event'});",
        "console.log('[MERGEN] Logout button clicked, redirecting to logout URL.');",
        "}}catch(e){console.warn('[MERGEN] Logout signal failed:',e);}",
        "setTimeout(function(){window.location.href='", safe_url, "';},150);"
      )
    } else {
      # URL yoksa buton hiç render edilmemeli; emniyet için boş işlem.
      "void(0);"
    }

    tags$button(
      type = "button",
      class = "mb-sidebar-logout-btn",
      title = "Oturumu kapat",
      `aria-label` = "Oturumu kapat",
      `data-logout-url` = if (nzchar(safe_url)) logout_url else NULL,
      onclick = onclick_js,
      tags$i(class = "fas fa-right-from-bracket")
    )
  } else {
    NULL
  }

  tags$div(
    class = "mb-sidebar-controls-row",
    mb_sidebar_theme_switch(),
    logout_btn
  )
}

#' Sidebar kullanıcı paneli UI'sı
#'
#' @description Server tarafında dinamik render edilecek alanları içeren
#'   sabit kabuğu üretir. Tema butonu, kullanıcı iskeleti ve sürüm satırı
#'   SAYFA İLK YÜKLENDİĞİNDE statik olarak gösterilir; reaktif renderUI
#'   çıktısı geldikçe içerik güncellenir. Bu sayede oturum açıldığında
#'   tema/kullanıcı/çıkış kontrolleri gecikmesiz görünür.
#'
#' @param output_id Sunucu çıktısı için ID (varsayılan: "sidebar_user_panel")
#' @return Shiny div
mb_sidebar_user_panel_ui <- function(output_id = "sidebar_user_panel") {
  # Statik iskelet kullanıcı kartı — Shiny render edilene kadar görünür.
  # SSO modunda gerçek değerle değiştirilecektir.
  initial_user <- mb_sidebar_user_badge_ui(
    full_name = "",
    first_name = NULL,
    user_id = NULL,
    department = ""
  )

  # Tema butonu artık her zaman ilk renderda mevcut; controls uiOutput
  # daha sonra logout butonu için yenilenebilir. Bu, "tema butonu geç
  # geliyor" regresyonunu önler.
  initial_controls <- mb_sidebar_controls_row(show_logout = FALSE)

  tags$div(
    class = "sidebar-footer",
    id = "sidebar-footer-container",
    # Kullanıcı kimliği (server tarafında doldurulur; ilk yüklemede
    # iskelet kartı görünür).
    tags$div(
      class = "mb-sidebar-user-slot",
      uiOutput(output_id, inline = FALSE, container = function(...) {
        tags$div(..., class = "shiny-html-output mb-sidebar-user-slot-output")
      }),
      tags$div(class = "mb-sidebar-user-skeleton", initial_user)
    ),
    # Kontrol satırı (tema butonu + opsiyonel çıkış) - statik iskelet ilk
    # renderda görünür, server hazır olduğunda yerini güncel sürüm alır.
    tags$div(
      class = "mb-sidebar-controls-slot",
      uiOutput(paste0(output_id, "_controls"), inline = FALSE,
               container = function(...) {
                 tags$div(..., class = "shiny-html-output mb-sidebar-controls-slot-output")
               }),
      tags$div(class = "mb-sidebar-controls-skeleton", initial_controls)
    ),
    # Sürüm satırı (tek doğru kaynak: get_current_version)
    tags$p(
      class = "sidebar-version",
      tags$span(class = "sidebar-version-prefix", "MERGEN Bilge"),
      tags$span(class = "sidebar-version-value",
                get_app_version_label())
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
#'   UI fonksiyonudur. SSO/yerel ayrımı çağıran tarafta yapılır. Çıkış
#'   butonu burada değil, ayrı kontrol satırında gösterilir (alan tasarrufu).
#'
#' @param full_name Görünür tam ad
#' @param first_name İlk ad (yedek)
#' @param user_id Avatar URL'sini üretmek için ID
#' @param department Görünür Departman metni (uzun olabilir; CSS ile ellipsis)
#' @return Shiny div
mb_sidebar_user_badge_ui <- function(full_name = NULL,
                                     first_name = NULL,
                                     user_id = NULL,
                                     department = NULL) {
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

  dept_text <- if (is.null(department)) "" else trimws(as.character(department)[1])

  dept_tag <- if (nzchar(dept_text)) {
    tags$span(
      class = "mb-sidebar-user-department",
      title = dept_text,
      dept_text
    )
  } else {
    tags$span(
      class = "mb-sidebar-user-department mb-sidebar-user-department-empty",
      title = "Departman bilgisi yok",
      "Departman bilgisi yok"
    )
  }

  tags$div(
    class = "mb-sidebar-user",
    tags$div(
      class = "mb-sidebar-user-avatar",
      avatar_inner
    ),
    tags$div(
      class = "mb-sidebar-user-info",
      tags$span(class = "mb-sidebar-user-name", title = display_name, display_name),
      dept_tag
    )
  )
}

#' Sidebar çıkış (logout) olayı için sunucu tarafı işleyici
#'
#' @description Kullanıcı sidebar çıkış butonuna bastığında tarayıcı tarafı
#'   Shiny.setInputValue('mergen_sidebar_logout', ...) tetikler.
#'   `mb_sidebar_user_panel_server()` içindeki observer bu işleyiciyi çağırır;
#'   böylece:
#'     - sunucu konsolunda logout olayı doğrulanır (kullanıcı talebi),
#'     - mevcut Shiny oturumu kapatılır (tarayıcı redirect olduktan sonra
#'       sunucu tarafında oturum kalıntısı kalmaz),
#'     - log dosyasına da logout olayı yazılır (varsa).
#'
#'   Hata güvenliği için try(..., silent = TRUE) kullanılır; tryCatch ile
#'   ek anonymous handler tanımlamak dosya bakım fonksiyon sayısını
#'   gereksiz şişirirdi.
#'
#' @param identity runtime_ctx$identity benzeri kimlik sözleşmesi (uid + ad)
#' @param session Shiny session nesnesi (close() çağrısı için gerekli)
#' @return Görünmez NULL
mb_sidebar_handle_logout_event <- function(identity, session) {
  uid <- NA
  full_name <- ""

  if (!is.null(identity) &&
      is.function(identity$resolve_current_user_id %||% NULL)) {
    uid_try <- try(identity$resolve_current_user_id(), silent = TRUE)
    if (!inherits(uid_try, "try-error")) uid <- uid_try
  }

  if (!is.null(identity) &&
      is.function(identity$get_display_name %||% NULL)) {
    name_try <- try(identity$get_display_name(default = ""), silent = TRUE)
    if (!inherits(name_try, "try-error")) full_name <- name_try
  }

  msg <- sprintf(
    "[LOGOUT] Sidebar logout tetiklendi - kullanici_id=%s ad=%s zaman=%s",
    as.character(uid),
    full_name,
    format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  )
  message(msg)

  if (exists("log_info", mode = "function", inherits = TRUE)) {
    try(log_info(msg), silent = TRUE)
  }

  if (!is.null(session)) {
    try(session$close(), silent = TRUE)
  }

  invisible(NULL)
}

#' Sidebar kullanıcı paneli server tarafı
#'
#' @description Kimlik bilgilerini reaktif olarak render eder. user_session
#'   live provider'ları kullanılır; SSO başlangıç anında değer hazır değilse
#'   geçici bir "Hazırlanıyor..." baloncuk gösterilir, ardından kimlik
#'   hazır olunca otomatik güncellenir.
#'
#'   Departman bilgisi user_config üzerinden okunur (MB_Users -> SSO claim).
#'   Bu modül kendi DB sorgusunu açmaz.
#'
#' @param output Shiny output nesnesi
#' @param identity runtime_ctx$identity benzeri kimlik sözleşmesi
#' @param sso_state SSO durum reaktifi (opsiyonel)
#' @param output_id Sunucu çıktısı ID (varsayılan: "sidebar_user_panel")
#' @param session Shiny session (logout observer için gerekli, opsiyonel)
#' @param input Shiny input (logout observer için gerekli, opsiyonel)
mb_sidebar_user_panel_server <- function(output,
                                         identity,
                                         sso_state = NULL,
                                         output_id = "sidebar_user_panel",
                                         session = NULL,
                                         input = NULL) {
  if (is.null(output)) {
    return(invisible(NULL))
  }

  # Çıkış (logout) olayı dinleyicisi - kullanıcı sidebar çıkış butonuna
  # bastığında tarayıcı tarafı Shiny.setInputValue('mergen_sidebar_logout', ...)
  # tetikler. Burada bu olayı yakalayıp sunucu konsoluna logout olayını
  # yazıyoruz ve mevcut Shiny oturumunu kapatıyoruz. Bu, kullanıcı
  # tarayıcısı logout URL'sine yönlendirilmeden hemen önce çalışır;
  # 150ms'lik tarayıcı tarafı setTimeout bu observer'a yeterli süreyi
  # tanır.
  # Not: try(..., silent = TRUE) kullanılır; tryCatch(error = function(...))
  # yapısı dosya bakım fonksiyon sayısını gereksiz şişirirdi.
  if (!is.null(input) && !is.null(session)) {
    observer_try <- try(
      shiny::observeEvent(input$mergen_sidebar_logout, {
        mb_sidebar_handle_logout_event(identity, session)
      }, ignoreInit = TRUE),
      silent = TRUE
    )
    if (inherits(observer_try, "try-error")) {
      err_cond <- attr(observer_try, "condition")
      err_msg <- if (!is.null(err_cond) && !is.null(err_cond$message)) {
        err_cond$message
      } else "bilinmiyor"
      message(sprintf("[LOGOUT] Observer baglanamadi: %s", err_msg))
    }
  }

  # Çıkış butonu görünürlüğü artık merkezi logout URL helper'i (
  # R/helpers_logout_url.R) tarafından belirlenir. URL .Renviron
  # üzerinden gelir; yoksa SSO logout endpoint denenir. Helper boş URL
  # dönerse buton sidebar üzerinde gösterilmez (kırık link sergilememek
  # için).
  resolved_logout_url <- tryCatch({
    if (exists("mergen_resolve_logout_url", mode = "function", inherits = TRUE)) {
      mergen_resolve_logout_url()
    } else {
      ""
    }
  }, error = function(e) "")

  sso_logout_available <- nzchar(resolved_logout_url)

  # Kontrol satırı (tema + opsiyonel çıkış) — bir kez render edilir, SSO
  # durumu değişmediği için reaktif olmaya gerek yok.
  output[[paste0(output_id, "_controls")]] <- shiny::renderUI({
    mb_sidebar_controls_row(
      show_logout = isTRUE(sso_logout_available),
      logout_url = resolved_logout_url
    )
  })

  shiny::outputOptions(
    output,
    paste0(output_id, "_controls"),
    suspendWhenHidden = FALSE
  )

  if (is.null(identity) ||
      !is.function(identity$get_display_name %||% NULL)) {
    # Kimlik sözleşmesi yoksa basit yedek render
    output[[output_id]] <- shiny::renderUI({
      mb_sidebar_user_badge_ui(
        full_name = "Yerel Kullanıcı",
        first_name = NULL,
        user_id = NULL,
        department = ""
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
        department = "Kimlik doğrulanıyor..."
      ))
    }

    live_user_cfg <- NULL

    # ÖNEMLİ:
    # user_config_rv() burada doğrudan çağrılır; böylece SSO tamamlanıp
    # MB_Users ile zenginleştirilmiş app_user_config yazıldığında sidebar
    # kesin olarak yeniden render edilir.
    if (is.function(identity$user_config_rv %||% NULL)) {
      live_user_cfg <- tryCatch(
        identity$user_config_rv(),
        error = function(e) NULL
      )
    }

    full_name <- tryCatch(get_display_name(default = ""),
                          error = function(e) "")
    first_name <- tryCatch(get_first_name(default = ""),
                           error = function(e) "")
    uid <- tryCatch(resolve_uid(), error = function(e) 0L)

    user_cfg <- if (!is.null(live_user_cfg)) {
      live_user_cfg
    } else {
      tryCatch(get_user_config(default = NULL),
               error = function(e) NULL)
    }

    department_text <- mb_sidebar_user_department(user_cfg)

    sicil <- if (!is.null(user_cfg)) user_cfg$sicil else NULL
    avatar_id <- if (!is.null(sicil) && nzchar(as.character(sicil)[1])) sicil else uid

    if (!nzchar(full_name) && !nzchar(first_name)) {
      full_name <- "Yerel Kullanıcı"
    }

    mb_sidebar_user_badge_ui(
      full_name = full_name,
      first_name = first_name,
      user_id = avatar_id,
      department = department_text
    )
  })

  shiny::outputOptions(
    output,
    output_id,
    suspendWhenHidden = FALSE
  )

  invisible(NULL)
}