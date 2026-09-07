# ==============================================================================
# Dosya Yolu: R/module_claude_code_plugins.R
# Açıklama: Claude Code Plugin yönetim modülü. Bilge Yolaç sidebar'ına
#           entegre edilen plugin paneli UI ve server mantığını içerir.
#           Yalnızca yerel gömülü pluginleri (bilge_yolac_plugins/) gösterir.
#           CLI veya internet bağlantısı gerektirmez.
# ==============================================================================

# ==============================================================================
# PLUGIN PANELİ UI
# Bilge Yolaç sidebar'ına yerleştirilen daraltılabilir/genişletilebilir panel.
# ==============================================================================

#' Plugin paneli UI bileşeni
#'
#' @param ns Namespace fonksiyonu (ana modülün ns'i)
#' @return tagList - Plugin paneli HTML yapısı
claudeCodePluginsUI <- function(ns) {
  div(
    # Varsayılan olarak daraltılmış başlat (yer tasarrufu)
    class = "cc-settings-card cc-plugins-card cc-plugins-collapsed",
    id = ns("plugins_wrapper"),

    # Panel Başlığı (tıklanabilir, daraltılabilir)
    div(
      class = "cc-card-title cc-plugins-header",
      onclick = sprintf(
        "document.getElementById('%s').classList.toggle('cc-plugins-collapsed');",
        ns("plugins_wrapper")
      ),
      icon("puzzle-piece"),
      span("Eklentiler"),
      tags$span(
        id = ns("plugins_count_badge"),
        class = "cc-plugins-count-badge cc-hidden"
      ),
      tags$i(class = "fas fa-chevron-down cc-plugins-toggle-icon")
    ),

    # Panel İçeriği
    div(
      id = ns("plugins_panel"),
      class = "cc-plugins-content",

      # Yerel Plugin Listesi
      div(
        class = "cc-plugins-list-section",
        div(
          class = "cc-plugins-list-header",
          tags$small(class = "cc-plugins-section-label", "Yerel Eklentiler"),
          actionButton(
            ns("refresh_plugins"),
            label = NULL,
            icon = icon("sync"),
            class = "btn-sm cc-plugins-refresh-btn",
            title = "Eklenti listesini yenile"
          )
        ),
        # Plugin kartları buraya render edilir
        uiOutput(ns("local_plugins_ui"))
      )
    )
  )
}

# ==============================================================================
# PLUGIN PANELİ SERVER
# ==============================================================================

#' Plugin paneli server mantığı
#'
#' @param input Shiny input
#' @param output Shiny output
#' @param session Shiny session
#' @param ns Namespace fonksiyonu
#' @param rv Ana modülün reaktif değerleri
claudeCodePluginsServer <- function(input, output, session, ns, rv) {

  # Plugin reaktif değerleri
  plugin_rv <- reactiveValues(
    local_plugins = list(),
    last_refresh  = NULL,
    is_loading    = FALSE
  )

  # --- Yerel pluginleri tara (CLI bağımsız) ---
  refresh_local_plugins <- function() {
    plugin_rv$is_loading <- TRUE

    yerel_sonuc <- tryCatch(
      scan_local_plugins(),
      error = function(e) {
        log_warn(paste(
          CLAUDE_CODE_PLUGINS_LOG_PREFIX,
          "Plugin tarama hatası:", conditionMessage(e)
        ))
        list(success = FALSE, plugins = list(), error = conditionMessage(e))
      }
    )

    if (yerel_sonuc$success) {
      plugin_rv$local_plugins <- yerel_sonuc$plugins
    }

    plugin_rv$last_refresh <- Sys.time()
    plugin_rv$is_loading <- FALSE

    # Sayaç rozetini güncelle
    toplam <- length(plugin_rv$local_plugins)
    session$sendCustomMessage(
      type = "cc-plugins-update-count",
      message = list(
        badgeId = ns("plugins_count_badge"),
        count   = toplam
      )
    )
  }

  # --- Sayfa yüklendiğinde otomatik ilk tarama (CLI durumundan bağımsız) ---
  observe({
    req(is.null(plugin_rv$last_refresh))
    refresh_local_plugins()
  }, priority = 40)

  # --- Yenile düğmesi ---
  observeEvent(input$refresh_plugins, {
    refresh_local_plugins()
  })

  # --- Yerel Plugin Listesi UI ---
  output$local_plugins_ui <- renderUI({
    plugins <- plugin_rv$local_plugins

    if (isTRUE(plugin_rv$is_loading)) {
      return(div(
        class = "cc-plugins-loading",
        icon("spinner", class = "fa-spin"),
        " Yükleniyor..."
      ))
    }

    if (length(plugins) == 0) {
      return(div(
        class = "cc-plugins-empty",
        tags$small("Yerel eklenti bulunamadı.")
      ))
    }

    div(
      class = "cc-plugins-list cc-local-plugins-list",
      lapply(plugins, function(plugin) {
        plugin_adi <- plugin$name %||% ""
        plugin_aciklama <- plugin$description %||% ""
        plugin_surum <- plugin$version %||% ""
        bilesenler <- plugin$components %||% character(0)

        div(
          class = "cc-plugin-card cc-plugin-local",
          `data-plugin-name` = plugin_adi,

          # Plugin Başlığı
          div(
            class = "cc-plugin-card-header",
            icon("puzzle-piece"),
            span(class = "cc-plugin-name", plugin_adi),
            # Sürüm rozeti
            if (nzchar(plugin_surum)) {
              tags$span(class = "cc-plugin-version-badge", plugin_surum)
            },
            tags$span(
              class = "cc-plugin-status-badge",
              style = paste0("color:", claude_code_plugin_status$aktif$renk, ";"),
              icon(claude_code_plugin_status$aktif$ikon),
              claude_code_plugin_status$aktif$metin
            )
          ),

          # Plugin Açıklaması
          if (nzchar(plugin_aciklama)) {
            div(class = "cc-plugin-desc", tags$small(plugin_aciklama))
          },

          # Bileşen rozetleri
          if (length(bilesenler) > 0) {
            div(
              class = "cc-plugin-components",
              lapply(bilesenler, function(b) {
                # Boş/NA bileşen adı `[[` erişiminde hata üretip panel render'ını
                # düşürüyordu.
                b <- as.character(b %||% "")[1]
                if (is.na(b) || !nzchar(b)) return(NULL)
                bilesen_bilgi <- claude_code_plugin_bilesenler[[b]]
                if (!is.null(bilesen_bilgi)) {
                  tags$span(
                    class = "cc-plugin-component-badge",
                    title = bilesen_bilgi$aciklama,
                    icon(bilesen_bilgi$ikon),
                    bilesen_bilgi$etiket
                  )
                }
              })
            )
          }
        )
      })
    )
  })

  # Reaktif değerleri döndür (ana modülden erişim için)
  plugin_rv
}