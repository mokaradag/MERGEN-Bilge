# ==============================================================================
# Dosya Yolu: R/module_api_key_choice_modal.R
# Açıklama:   Kişisel API anahtarı olmayan, kimliği doğrulanmış kullanıcıya
#             gösterilen premium "API Anahtarı Seçimi" onboarding modalının
#             saf UI yardımcıları. İki yol sunar:
#               1) Kişisel API anahtarı al/gir (mevcut güvenli kayıt akışı)
#               2) Varsayılan kurum anahtarıyla devam et (sunucu yönetimli)
#
#             Bu dosya yalnızca UI üretir ve modalı gösterir. Hiçbir API
#             anahtarı (kişisel veya varsayılan) burada saklanmaz, yazılmaz,
#             loglanmaz veya istemciye gönderilmez. Sahiplik/doğrulama/kayıt
#             mantığı R/module_api_key.R ve R/helpers_api_key_identity.R
#             içinde kalır.
# ==============================================================================

# Servis masası API anahtarı talep bağlantısını güvenle çözer.
# Bağlantı yoksa boş döner; çağıran taraf talep düğmesini gizler.
api_key_choice_request_url <- function(service_desk = NULL) {
  if (is.null(service_desk)) {
    return("")
  }

  url <- tryCatch(service_desk$api_key_request_url, error = function(e) NULL)
  url <- as.character(url %||% "")[1]

  if (is.na(url) || !nzchar(url)) {
    return("")
  }

  url
}

# Kişisel API anahtarı kartını üretir. Anahtar giriş alanı (passwordInput)
# her zaman DOM'da bulunur; böylece R/module_api_key.R içindeki mevcut
# kaydet/temizle observer'ları aynı namespace'li input id'lerine bağlanır.
# Görünürlük istemci tarafında .akc-entry-open sınıfıyla yönetilir.
.api_key_choice_personal_card <- function(ns,
                                          request_url = "",
                                          recommended = FALSE) {
  request_action <- if (nzchar(request_url)) {
    tags$a(
      href   = request_url,
      target = "_blank",
      rel    = "noopener noreferrer",
      class  = "akc-btn akc-btn--ghost",
      role   = "button",
      icon("external-link-alt"),
      tags$span("API Anahtarı Talep Et")
    )
  } else {
    NULL
  }

  div(
    class = "akc-card akc-card--personal",
    `data-akc-card` = "personal",
    div(class = "akc-card-glow", `aria-hidden` = "true"),
    if (isTRUE(recommended)) {
      div(class = "akc-ribbon", tags$span("Önerilen"))
    } else {
      NULL
    },
    div(
      class = "akc-card-head",
      div(class = "akc-card-icon akc-card-icon--personal", `aria-hidden` = "true"),
      div(
        class = "akc-card-title-wrap",
        tags$h3(class = "akc-card-title", "Kişisel API Anahtarı"),
        tags$p(
          class = "akc-card-sub",
          "Size özel kota, daha iyi izlenebilirlik ve daha yüksek kullanım kontrolü sağlar."
        )
      )
    ),
    tags$ul(
      class = "akc-list akc-list--pro",
      tags$li(icon("check-circle"), tags$span("Kişisel kullanım ve hesap verebilirlik")),
      tags$li(icon("check-circle"), tags$span("Yoğun kullanımda daha istikrarlı deneyim")),
      tags$li(icon("check-circle"), tags$span("Kurumsal güvenlik modeliyle uyumlu"))
    ),
    tags$ul(
      class = "akc-list akc-list--con",
      tags$li(icon("info-circle"), tags$span("Önce API anahtarı talep etmeniz gerekir"))
    ),
    # Anahtar giriş alanı her zaman görünür ve kullanıma hazırdır; JS'e
    # bağımlı bir "aç/kapa" davranışı yoktur. Böylece kullanıcı anahtarını
    # doğrudan girip kaydedebilir.
    div(
      class = "akc-key-entry",
      `data-akc-entry` = "personal",
      passwordInput(
        ns("api_key_plain_input"),
        label = "API Anahtarınızı buraya girin",
        width = "100%"
      ),
      tags$p(
        class = "akc-secure-note",
        icon("lock"),
        tags$span(
          "Anahtarınız AES-256-GCM ile şifrelenerek saklanır; ekranda gösterilmez."
        )
      )
    ),
    div(
      class = "akc-card-actions",
      request_action,
      actionButton(
        ns("api_key_clear_btn"),
        label = tagList(icon("eraser"), "Temizle"),
        class = "akc-btn akc-btn--ghost"
      ),
      actionButton(
        ns("api_key_save_btn"),
        label = tagList(icon("save"), "Kaydet ve Devam Et"),
        class = "akc-btn akc-btn--primary"
      )
    )
  )
}

# Varsayılan kurum anahtarı kartını üretir. Yalnızca varsayılan anahtar
# kullanılabilirken gösterilir. Hiçbir anahtar değeri içermez; yalnızca
# "devam et" eylemini açar.
.api_key_choice_corporate_card <- function(ns) {
  div(
    class = "akc-card akc-card--corporate",
    `data-akc-card` = "corporate",
    div(class = "akc-card-glow", `aria-hidden` = "true"),
    div(
      class = "akc-card-head",
      div(class = "akc-card-icon akc-card-icon--corporate", `aria-hidden` = "true"),
      div(
        class = "akc-card-title-wrap",
        tags$h3(class = "akc-card-title", "Varsayılan Kurum Anahtarı"),
        tags$p(
          class = "akc-card-sub",
          "API anahtarı talep etmeden hemen başlamanızı sağlar."
        )
      )
    ),
    tags$ul(
      class = "akc-list akc-list--pro",
      tags$li(icon("check-circle"), tags$span("Hemen kullanmaya başlayın")),
      tags$li(icon("check-circle"), tags$span("Yönetici ve hızlı deneme senaryoları için pratik")),
      tags$li(icon("check-circle"), tags$span("Anahtar cihazınıza veya tarayıcıya yazılmaz"))
    ),
    tags$ul(
      class = "akc-list akc-list--con",
      tags$li(icon("info-circle"), tags$span("Paylaşımlı kota nedeniyle yoğun saatlerde yavaşlama olabilir")),
      tags$li(icon("info-circle"), tags$span("Kişisel anahtar kadar ayrıntılı kullanıcı kontrolü sunmaz"))
    ),
    div(
      class = "akc-card-actions akc-card-actions--single",
      actionButton(
        ns("api_key_use_default_btn"),
        label = tagList(icon("bolt"), "Kurum Anahtarı ile Devam Et"),
        class = "akc-btn akc-btn--corporate"
      )
    )
  )
}

# Premium iki yollu (veya tek yollu) modal içeriğini üretir. Saf UI;
# yan etkisi yoktur. default_available FALSE iken yalnızca kişisel anahtar
# yolu gösterilir ve kurumsal seçenek sunulmaz.
api_key_choice_modal_dialog <- function(ns,
                                        service_desk = NULL,
                                        default_available = FALSE) {
  default_available <- isTRUE(default_available)
  request_url <- api_key_choice_request_url(service_desk)

  if (default_available) {
    title_text <- "MERGEN Bilge için API Anahtarı Seçimi"
    subtitle_text <- paste(
      "Başlamak için iki güvenli yolunuz var. İsterseniz kişisel anahtarınızı",
      "kullanabilir, isterseniz kurumun varsayılan anahtarıyla hemen devam",
      "edebilirsiniz."
    )
    close_label <- "Daha Sonra Karar Ver"
  } else {
    title_text <- "MERGEN Bilge için API Anahtarı Gerekli"
    subtitle_text <- paste(
      "Devam etmek için kişisel API anahtarınızı girin. Anahtarınız yoksa",
      "kurumsal süreç üzerinden hızlıca talep edebilirsiniz."
    )
    close_label <- "Kapat"
  }

  cards <- div(
    class = if (default_available) "akc-cards akc-cards--dual" else "akc-cards akc-cards--single",
    .api_key_choice_personal_card(
      ns,
      request_url = request_url,
      recommended = default_available
    ),
    if (default_available) .api_key_choice_corporate_card(ns) else NULL
  )

  shell <- div(
    class = "akc-shell",
    # Dekoratif katmanlar: tamamen yerel SVG/video + CSS gradyanları. Hepsi
    # eksik olsa bile CSS gradyan tabanı görünmeye devam eder (zarif geri
    # düşüş). Hiçbir uzak/CDN kaynağı kullanılmaz.
    #
    # Arka plan videosu OPSİYONEL ve YERELDİR. Dosya
    # www/assets/api-key-choice/backdrop.mp4 mevcutsa oynatılır; yoksa
    # poster (yerel SVG) ve altındaki gradyan katmanı görünür kalır.
    # Boolean video öznitelikleri açık string olarak verilir; bazı
    # htmltools/Shiny sürümlerinde NA öznitelik render'ı tutarsız olabilir.
    # autoplay + muted + playsinline tarayıcıların sessiz otomatik oynatma
    # kuralını karşılar.
    tags$video(
      class = "akc-video",
      `aria-hidden` = "true",
      tabindex = "-1",
      autoplay = "autoplay",
      muted = "muted",
      loop = "loop",
      playsinline = "playsinline",
      preload = "auto",
      poster = "assets/api-key-choice/backdrop-poster.svg",
      tags$source(
        src = "assets/api-key-choice/backdrop.mp4",
        type = "video/mp4"
      )
    ),
    div(class = "akc-bg", `aria-hidden` = "true"),
    div(class = "akc-aurora", `aria-hidden` = "true"),
    div(class = "akc-scrim", `aria-hidden` = "true"),
    tags$header(
      class = "akc-header",
      div(class = "akc-emblem", `aria-hidden` = "true"),
      tags$h2(id = ns("api_key_choice_title"), class = "akc-title", title_text),
      tags$p(class = "akc-subtitle", subtitle_text)
    ),
    cards,
    div(
      class = "akc-foot",
      # "Bu ekranı bir daha gösterme" yalnızca varsayılan kurum anahtarı
      # varken sunulur; aksi halde modalı bastırmak kullanıcıyı anahtarsız
      # bırakır. İşaretlenince tercih istemci tarafında mergen_settings
      # içine yazılır (yalnızca bayrak; ANAHTAR DEĞİL).
      if (default_available) {
        tags$label(
          class = "akc-dontshow",
          tags$input(
            type = "checkbox",
            class = "akc-dontshow-input",
            `data-akc-dontshow` = "1",
            `aria-label` = "Bu ekranı bir daha gösterme"
          ),
          tags$span(class = "akc-dontshow-box", `aria-hidden` = "true", icon("check")),
          tags$span(class = "akc-dontshow-text", "Bu ekranı bir daha gösterme")
        )
      } else {
        NULL
      },
      div(
        class = "akc-foot-end",
        tags$p(
          class = "akc-foot-note",
          icon("info-circle"),
          tags$span("Daha sonra Ayarlar > Yapılandırma üzerinden tekrar açabilirsiniz.")
        ),
        tags$button(
          type = "button",
          class = "akc-btn akc-btn--text",
          `data-dismiss` = "modal",
          close_label
        )
      )
    )
  )

  # showModal argümanı bir div ile sarılır; böylece kök sınıf .modal-content
  # atasında yer alır ve CSS hedeflemesi güvenli olur (feedback modalıyla
  # aynı desen).
  tags$div(
    class = "api-key-choice-modal-root",
    `data-akc-default` = if (default_available) "1" else "0",
    modalDialog(
      id = ns("api_key_choice_dialog"),
      title = NULL,
      footer = NULL,
      size = "l",
      easyClose = FALSE,
      shell
    )
  )
}

# Modalı gösterir ve istemci tarafı geliştirmeleri (odak yönetimi, anahtar
# giriş çekmecesi açma, yerel tercih hatırlama) tetikleyen güvenli mesajı
# yollar. Mesaj yalnızca davranışsal bayrak taşır; anahtar içermez.
show_api_key_choice_modal <- function(session,
                                      default_available = FALSE,
                                      service_desk = NULL) {
  if (is.null(session)) {
    return(invisible(FALSE))
  }

  ns <- session$ns
  default_available <- isTRUE(default_available)

  showModal(
    api_key_choice_modal_dialog(
      ns = ns,
      service_desk = service_desk,
      default_available = default_available
    )
  )

  session$sendCustomMessage(
    "mergenApiKeyChoiceInit",
    list(
      defaultAvailable = default_available,
      # Tercih, mergen_settings localStorage nesnesi içindeki bu anahtara
      # yazılır (yalnızca bayrak; ASLA API anahtarı değeri değil).
      settingsKey = "api_key_onboarding_suppressed"
    )
  )

  invisible(TRUE)
}