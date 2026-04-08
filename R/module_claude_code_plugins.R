# ==============================================================================
# Dosya Yolu: R/module_claude_code_plugins.R
# Açıklama: Claude Code Plugin yönetim modülü. Bilge Yolaç sidebar'ına
#           entegre edilen plugin paneli UI ve server mantığını içerir.
#           Plugin listeleme, kurulum, kaldırma, marketplace yönetimi ve
#           plugin detay görüntüleme işlevlerini kapsar.
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
    class = "cc-settings-card cc-plugins-card",

    # Panel Başlığı (tıklanabilir, daraltılabilir)
    div(
      class = "cc-card-title cc-plugins-header",
      onclick = sprintf(
        "document.getElementById('%s').classList.toggle('cc-plugins-collapsed');",
        ns("plugins_panel")
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

      # Yüklü Plugin Listesi
      div(
        class = "cc-plugins-list-section",
        div(
          class = "cc-plugins-list-header",
          tags$small(class = "cc-plugins-section-label", "Yüklü Eklentiler"),
          actionButton(
            ns("refresh_plugins"),
            label = NULL,
            icon = icon("sync"),
            class = "btn-sm cc-plugins-refresh-btn",
            title = "Eklenti listesini yenile"
          )
        ),
        # Plugin kartları buraya render edilir
        uiOutput(ns("plugins_list_ui"))
      ),

      # Marketplace İşlemleri
      div(
        class = "cc-plugins-marketplace-section",
        tags$small(class = "cc-plugins-section-label", "Marketplace"),

        # Marketplace URL girişi
        div(
          class = "cc-plugins-marketplace-row",
          tags$input(
            id = ns("marketplace_url_input"),
            type = "text",
            class = "cc-plugins-input",
            placeholder = "Marketplace URL girin..."
          ),
          actionButton(
            ns("add_marketplace"),
            label = NULL,
            icon = icon("plus"),
            class = "btn-sm cc-plugins-action-btn",
            title = "Marketplace ekle"
          )
        ),

        # Plugin Kurulum
        div(
          class = "cc-plugins-install-row",
          tags$input(
            id = ns("plugin_install_input"),
            type = "text",
            class = "cc-plugins-input",
            placeholder = "Eklenti adı (ör: code-review)"
          ),
          actionButton(
            ns("install_plugin"),
            label = NULL,
            icon = icon("download"),
            class = "btn-sm cc-plugins-action-btn cc-plugins-install-btn",
            title = "Eklentiyi kur"
          )
        )
      ),

      # Yerel Plugin Bilgisi
      div(
        class = "cc-plugins-local-section",
        tags$small(class = "cc-plugins-section-label", "Yerel Eklentiler"),
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
#' @param rv Ana modülün reaktif değerleri (cli_path_resolved erişimi için)
claudeCodePluginsServer <- function(input, output, session, ns, rv) {

  # Plugin reaktif değerleri
  plugin_rv <- reactiveValues(
    installed_plugins = list(),
    local_plugins     = list(),
    last_refresh      = NULL,
    is_loading        = FALSE
  )

  # --- Plugin listesini yenile ---
  refresh_plugin_list <- function() {
    cli_yolu <- rv$cli_path_resolved
    if (is.null(cli_yolu)) return()

    plugin_rv$is_loading <- TRUE

    # Yüklü pluginleri sorgula
    sonuc <- tryCatch(
      list_installed_plugins(cli_yolu),
      error = function(e) list(success = FALSE, plugins = list(), error = conditionMessage(e))
    )

    if (sonuc$success) {
      plugin_rv$installed_plugins <- sonuc$plugins
    }

    # Yerel pluginleri tara
    yerel_sonuc <- tryCatch(
      scan_local_plugins(),
      error = function(e) list(success = FALSE, plugins = list(), error = conditionMessage(e))
    )

    if (yerel_sonuc$success) {
      plugin_rv$local_plugins <- yerel_sonuc$plugins
    }

    plugin_rv$last_refresh <- Sys.time()
    plugin_rv$is_loading <- FALSE

    # Sayaç rozetini güncelle
    toplam <- length(plugin_rv$installed_plugins) + length(plugin_rv$local_plugins)
    session$sendCustomMessage(
      type = "cc-plugins-update-count",
      message = list(
        badgeId = ns("plugins_count_badge"),
        count   = toplam
      )
    )
  }

  # --- CLI hazır olduğunda ilk yükleme ---
  observe({
    req(!is.null(rv$cli_path_resolved))
    req(isTRUE(rv$connection_ok))
    req(is.null(plugin_rv$last_refresh))
    refresh_plugin_list()
  })

  # --- Yenile düğmesi ---
  observeEvent(input$refresh_plugins, {
    refresh_plugin_list()
  })

  # --- Yüklü Plugin Listesi UI ---
  output$plugins_list_ui <- renderUI({
    plugins <- plugin_rv$installed_plugins

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
        tags$small("Henüz yüklü eklenti yok.")
      ))
    }

    div(
      class = "cc-plugins-list",
      lapply(seq_along(plugins), function(i) {
        plugin <- plugins[[i]]
        plugin_adi <- plugin$name %||% ""
        plugin_aciklama <- plugin$description %||% ""
        plugin_durum <- if (isTRUE(plugin$enabled)) "aktif" else "pasif"
        durum_bilgi <- claude_code_plugin_status[[plugin_durum]]

        div(
          class = paste0("cc-plugin-card cc-plugin-", plugin_durum),
          `data-plugin-name` = plugin_adi,

          # Plugin Başlığı
          div(
            class = "cc-plugin-card-header",
            span(class = "cc-plugin-name", plugin_adi),
            tags$span(
              class = "cc-plugin-status-badge",
              style = paste0("color:", durum_bilgi$renk, ";"),
              icon(durum_bilgi$ikon),
              durum_bilgi$metin
            )
          ),

          # Plugin Açıklaması
          if (nzchar(plugin_aciklama)) {
            div(class = "cc-plugin-desc", tags$small(plugin_aciklama))
          },

          # Plugin İşlem Düğmeleri
          div(
            class = "cc-plugin-actions",
            # Etkinleştir/Devre dışı bırak düğmesi
            if (isTRUE(claude_code_plugins_config$allow_toggle)) {
              actionButton(
                ns(paste0("toggle_plugin_", i)),
                label = if (isTRUE(plugin$enabled)) icon("toggle-on") else icon("toggle-off"),
                class = "btn-sm cc-plugin-toggle-btn",
                title = if (isTRUE(plugin$enabled)) "Devre dışı bırak" else "Etkinleştir",
                onclick = sprintf(
                  "Shiny.setInputValue('%s', {name: '%s', enable: %s, nonce: Math.random()}, {priority: 'event'});",
                  ns("toggle_plugin_action"),
                  gsub("'", "\\\\'", plugin_adi),
                  if (isTRUE(plugin$enabled)) "false" else "true"
                )
              )
            },
            # Kaldır düğmesi
            if (isTRUE(claude_code_plugins_config$allow_uninstall)) {
              actionButton(
                ns(paste0("uninstall_plugin_", i)),
                label = icon("trash"),
                class = "btn-sm cc-plugin-remove-btn",
                title = "Eklentiyi kaldır",
                onclick = sprintf(
                  "Shiny.setInputValue('%s', {name: '%s', nonce: Math.random()}, {priority: 'event'});",
                  ns("uninstall_plugin_action"),
                  gsub("'", "\\\\'", plugin_adi)
                )
              )
            }
          )
        )
      })
    )
  })

  # --- Yerel Plugin Listesi UI ---
  output$local_plugins_ui <- renderUI({
    plugins <- plugin_rv$local_plugins

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
        bilesenler <- plugin$components %||% character(0)

        div(
          class = "cc-plugin-card cc-plugin-local",
          div(
            class = "cc-plugin-card-header",
            icon("folder"),
            span(class = "cc-plugin-name", plugin_adi)
          ),

          # Bileşen rozetleri
          if (length(bilesenler) > 0) {
            div(
              class = "cc-plugin-components",
              lapply(bilesenler, function(b) {
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

  # --- Plugin Etkinleştirme/Devre Dışı Bırakma İşlemi ---
  observeEvent(input$toggle_plugin_action, {
    req(input$toggle_plugin_action)
    veri <- input$toggle_plugin_action
    cli_yolu <- rv$cli_path_resolved
    req(!is.null(cli_yolu))

    plugin_adi <- veri$name
    etkinlestir <- isTRUE(veri$enable)

    sonuc <- toggle_plugin(cli_yolu, plugin_adi, enable = etkinlestir)

    if (sonuc$success) {
      islem <- if (etkinlestir) "etkinleştirildi" else "devre dışı bırakıldı"
      showNotification(
        paste0("Eklenti ", islem, ": ", plugin_adi),
        type = "message",
        duration = 4
      )
      refresh_plugin_list()
    } else {
      showNotification(
        paste0("Hata: ", sonuc$error),
        type = "error",
        duration = 6
      )
    }
  })

  # --- Plugin Kaldırma İşlemi ---
  observeEvent(input$uninstall_plugin_action, {
    req(input$uninstall_plugin_action)
    veri <- input$uninstall_plugin_action
    cli_yolu <- rv$cli_path_resolved
    req(!is.null(cli_yolu))

    plugin_adi <- veri$name

    sonuc <- uninstall_plugin(cli_yolu, plugin_adi)

    if (sonuc$success) {
      showNotification(
        paste0("Eklenti kaldırıldı: ", plugin_adi),
        type = "message",
        duration = 4
      )
      refresh_plugin_list()
    } else {
      showNotification(
        paste0("Kaldırma hatası: ", sonuc$error),
        type = "error",
        duration = 6
      )
    }
  })

  # --- Plugin Kurulum İşlemi ---
  observeEvent(input$install_plugin, {
    cli_yolu <- rv$cli_path_resolved
    req(!is.null(cli_yolu))

    # JavaScript'ten giriş değerini al
    plugin_adi <- input$plugin_install_value
    if (is.null(plugin_adi) || !nzchar(trimws(plugin_adi))) {
      showNotification("Eklenti adı girin.", type = "warning", duration = 3)
      return()
    }

    plugin_adi <- trimws(plugin_adi)

    showNotification(
      paste0("Eklenti kuruluyor: ", plugin_adi),
      type = "message",
      duration = 3
    )

    sonuc <- install_plugin(cli_yolu, plugin_adi)

    if (sonuc$success) {
      showNotification(
        paste0("Eklenti kuruldu: ", plugin_adi),
        type = "message",
        duration = 5
      )
      # Giriş alanını temizle
      session$sendCustomMessage(
        type = "cc-plugins-clear-input",
        message = list(inputId = ns("plugin_install_input"))
      )
      refresh_plugin_list()
    } else {
      showNotification(
        paste0("Kurulum hatası: ", sonuc$error),
        type = "error",
        duration = 6
      )
    }
  })

  # --- Marketplace Ekleme İşlemi ---
  observeEvent(input$add_marketplace, {
    cli_yolu <- rv$cli_path_resolved
    req(!is.null(cli_yolu))

    marketplace_url <- input$marketplace_url_value
    if (is.null(marketplace_url) || !nzchar(trimws(marketplace_url))) {
      showNotification("Marketplace URL'si girin.", type = "warning", duration = 3)
      return()
    }

    marketplace_url <- trimws(marketplace_url)

    showNotification(
      paste0("Marketplace ekleniyor..."),
      type = "message",
      duration = 3
    )

    sonuc <- add_marketplace(cli_yolu, marketplace_url)

    if (sonuc$success) {
      showNotification(
        "Marketplace başarıyla eklendi.",
        type = "message",
        duration = 5
      )
      # Giriş alanını temizle
      session$sendCustomMessage(
        type = "cc-plugins-clear-input",
        message = list(inputId = ns("marketplace_url_input"))
      )
    } else {
      showNotification(
        paste0("Marketplace hatası: ", sonuc$error),
        type = "error",
        duration = 6
      )
    }
  })

  # Reaktif değerleri döndür (ana modülden erişim için)
  plugin_rv
}
