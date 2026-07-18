# ==============================================================================
# Dosya Yolu: R/module_bilge_savunmasi_ui.R
# Açıklama: Bilge Savunması sayfası UI katmanı. Sayfa iskeleti, menü kartları,
#           oyun görünümü bağlama noktaları (canvas + HUD) ve kalıcılık uyarı
#           alanı burada kurulur. Oyun motoru SAYFA AÇILANA KADAR başlatılmaz;
#           bu dosya yalnızca statik iskelet üretir.
#
# Sözleşmeler:
#   * Saf UI: observer, reactiveVal, sendCustomMessage YOK.
#   * Persona kimliği tek kaynağı R/config_characters.R'dir; bu dosya persona
#     verisi tanımlamaz (istemciye manifest sunucudan bs-init ile gider).
#   * Oyun HUD içeriği www/js/bilge_savunmasi_hud.js tarafından bu iskeletin
#     bağlama noktalarına çizilir; burada yalnızca konteynerler bulunur.
#   * Özellik bayrağı kapalıyken sayfa sakin bir bilgi kartı gösterir.
# ==============================================================================

# Menü kartı: ikon + başlık + açıklama taşıyan tek eylem kartı.
.bs_ui_menu_karti <- function(ns, eylem, ikon, baslik, aciklama,
                              birincil = FALSE) {
  htmltools::tags$button(
    type = "button",
    class = paste(
      "bs-menu-karti",
      if (birincil) "bs-menu-karti-birincil" else ""
    ),
    `data-bs-eylem` = eylem,
    `aria-label` = baslik,
    htmltools::tags$span(class = "bs-menu-ikon", `aria-hidden` = "true",
                         shiny::icon(ikon)),
    htmltools::tags$span(
      class = "bs-menu-metin",
      htmltools::tags$span(class = "bs-menu-baslik", baslik),
      htmltools::tags$span(class = "bs-menu-aciklama", aciklama)
    )
  )
}

# Menü görünümü: oyun merkezi (kampanya, haftalık, planlar, topluluk, bilgi).
.bs_ui_menu_gorunumu <- function(ns) {
  htmltools::tags$div(
    id = ns("menu_gorunumu"),
    class = "bs-menu-gorunumu",

    htmltools::tags$div(
      class = "bs-menu-ust",
      htmltools::tags$div(
        class = "bs-menu-tanitim",
        htmltools::tags$h2(class = "bs-menu-hero-baslik", "Bilgi Çekirdeği'ni Savun"),
        htmltools::tags$p(
          class = "bs-menu-hero-metin",
          paste(
            "Gürültü, çelişki ve doğrulanmamış varsayımlar Bilgi Çekirdeği'ne",
            "ilerliyor. Beş MERGEN Bilge uzmanını konuşlandır, rotaları kontrol",
            "et ve dalgaları güvenle karşıla."
          )
        )
      ),
      htmltools::tags$div(id = ns("profil_ozeti"), class = "bs-profil-ozeti")
    ),

    htmltools::tags$div(
      class = "bs-menu-kartlari",
      .bs_ui_menu_karti(ns, "kampanya", "map", "Kampanya",
                        "Üç haritalık savunma seferi", birincil = TRUE),
      .bs_ui_menu_karti(ns, "haftalik", "trophy", "Haftalık Meydan Okuma",
                        "Herkes aynı tohumla yarışır"),
      .bs_ui_menu_karti(ns, "planlar", "compass-drafting", "Oyuncu Planları",
                        "Savunma planlarını yayınla ve dene"),
      .bs_ui_menu_karti(ns, "topluluk", "people-group", "Topluluk Operasyonu",
                        "Haftalık ortak savunma hedefi"),
      .bs_ui_menu_karti(ns, "kahramanlar", "user-shield", "Kahramanlar",
                        "Beş uzmanın rolleri ve yetenekleri"),
      .bs_ui_menu_karti(ns, "ilerleme", "star", "İlerleme ve Başarımlar",
                        "Yıldızlar, seviye ve açılımlar"),
      .bs_ui_menu_karti(ns, "ayarlar", "sliders-h", "Oyun Ayarları",
                        "Ses, kalite ve erişilebilirlik"),
      .bs_ui_menu_karti(ns, "yardim", "circle-question", "Nasıl Oynanır",
                        "Kısa öğretici ve kurallar")
    ),

    # Alt paneller: içerik JS tarafından bs-init verisiyle doldurulur.
    htmltools::tags$div(id = ns("panel_alani"), class = "bs-panel-alani")
  )
}

# Oyun görünümü: canvas + HUD bağlama noktaları (başlangıçta gizli).
.bs_ui_oyun_gorunumu <- function(ns) {
  htmltools::tags$div(
    id = ns("oyun_gorunumu"),
    class = "bs-oyun-gorunumu bs-gizli",

    htmltools::tags$div(id = ns("hud_ust"), class = "bs-hud-ust"),
    htmltools::tags$div(
      class = "bs-oyun-orta",
      htmltools::tags$div(
        id = ns("canvas_kabi"),
        class = "bs-canvas-kabi",
        role = "application",
        `aria-label` = "Bilge Savunması oyun alanı"
      ),
      htmltools::tags$div(id = ns("hud_yan"), class = "bs-hud-yan")
    ),
    htmltools::tags$div(id = ns("hud_alt"), class = "bs-hud-alt"),
    htmltools::tags$div(id = ns("oyun_kaplama"), class = "bs-oyun-kaplama")
  )
}

#' Bilge Savunması Sayfası UI
#'
#' @description Bilge Yolaç altındaki adanmış oyun sayfasının iskeletini
#' üretir. Oyun motoru yalnızca sayfa açıldığında (page_opened) başlatılır;
#' bu iskelet ağır iş yapmaz.
bilgeSavunmasiUI <- function(id) {
  ns <- shiny::NS(id)

  if (!bilge_savunmasi_enabled()) {
    return(
      htmltools::tags$div(
        class = "bs-sayfa bs-sayfa-kapali",
        htmltools::tags$div(
          class = "bs-kapali-karti",
          htmltools::tags$h3("Bilge Savunması şu anda kapalı"),
          htmltools::tags$p(paste(
            "Bu özellik yapılandırma ile devre dışı bırakılmış.",
            "Sistem yöneticinize başvurabilirsiniz."
          ))
        )
      )
    )
  }

  htmltools::tags$div(
    class = "bs-sayfa",
    id = ns("sayfa"),
    `data-bs-modul` = id,

    # Sayfa başlık bandı (uygulamanın standart sayfa başlığı diliyle).
    htmltools::tags$div(
      class = "bs-sayfa-baslik",
      htmltools::tags$div(
        class = "bs-baslik-sol",
        htmltools::tags$span(class = "bs-baslik-ikon", `aria-hidden` = "true",
                             shiny::icon("chess-rook")),
        htmltools::tags$h1(class = "bs-baslik-metin", "Bilge Savunması"),
        htmltools::tags$span(class = "bs-baslik-rozet", "OYUN")
      ),
      htmltools::tags$div(
        class = "bs-baslik-sag",
        htmltools::tags$span(id = ns("kalicilik_rozeti"),
                             class = "bs-kalicilik-rozeti")
      )
    ),

    # Kalıcılık / durum uyarı alanı (tablolar kurulu değilse açıklama).
    htmltools::tags$div(id = ns("kalicilik_notu"), class = "bs-kalicilik-notu"),

    .bs_ui_menu_gorunumu(ns),
    .bs_ui_oyun_gorunumu(ns),

    # Oyun betiği yüklenemezse görünen yedek açıklama (JS bunu gizler).
    htmltools::tags$div(
      id = ns("motor_bekleniyor"),
      class = "bs-motor-bekleniyor",
      "Oyun bileşenleri hazırlanıyor..."
    )
  )
}
