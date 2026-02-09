# R/welcome_screen_modern.R
# Modern karşılama ekranı bileşenleri

create_modern_tooltip <- function(description) {
  tags$div(
    class = "modern-tooltip",
    style = "position: fixed; z-index: 9999; pointer-events: none; opacity: 0; transition: opacity 0.2s ease; display: none;",
    `data-tooltip-text` = description,
    tags$div(
      class = "modern-tooltip-content",
      style = paste(
        "background: rgba(0, 0, 0, 0.95);",
        "border: 1px solid rgba(255, 255, 255, 0.1);",
        "border-radius: 12px;",
        "padding: 12px 16px;",
        "max-width: 280px;",
        "font-size: 14px;",
        "color: #e5e7eb;",
        "line-height: 1.5;",
        "backdrop-filter: blur(24px);",
        "box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4);"
      )
    ),
    tags$div(
      class = "modern-tooltip-arrow",
      style = paste(
        "position: absolute;",
        "top: -8px;",
        "left: 50%;",
        "transform: translateX(-50%);",
        "width: 16px;",
        "height: 16px;",
        "background: rgba(0, 0, 0, 0.95);",
        "border-left: 1px solid rgba(255, 255, 255, 0.1);",
        "border-top: 1px solid rgba(255, 255, 255, 0.1);",
        "transform: translateX(-50%) rotate(45deg);"
      )
    )
  )
}

create_modern_welcome_action <- function(action_data) {
  theme_color <- action_data$themeColor
  rgb <- col2rgb(theme_color)
  
  tooltip_id <- paste0("tooltip_", action_data$id)
  
  # Tooltip HTML'ini doğrudan butonun title attribute'üne ekle
  # Bu, tarayıcıların yerleşik tooltip mekanizmasını kullanır
  tooltip_title <- sprintf("%s\n\n%s", action_data$title, action_data$description)
  
  tags$button(
    class = "modern-welcome-action-btn",
    title = tooltip_title, # Tooltip'i title attribute'üne ekle
    style = sprintf("--theme-r: %d; --theme-g: %d; --theme-b: %d;", rgb[1], rgb[2], rgb[3]),
	onclick = sprintf("Shiny.setInputValue('quick_template', {text: '%s', model: '%s', action_id: '%s'}, {priority: 'event'}); $('.custom-tooltip').remove(); $('#welcome_fullscreen_container').fadeOut(300); return false;",
				  gsub("'", "\\\\'", action_data$message),
				  action_data$model_value,
				  action_data$id),

    
    # Tooltip için özel CSS sınıfı ekle
    `data-toggle` = "tooltip",
    `data-placement` = "top",
    `data-html` = "true",
    
	# Snake trail SVG - yarı genişlik buton oranına uyarlandı
	div(class = "modern-welcome-action-border-trail",
		tags$svg(
		  class = "absolute inset-0 w-full h-full",
		  viewBox = "0 0 530.16 78",
		  preserveAspectRatio = "none",
		  style = "overflow: visible;",
			tags$rect(
			  x = "2.5", y = "2.5", width = "525.16", height = "73",
			  rx = "15.5", ry = "15.5", fill = "none",
			  stroke = theme_color, `stroke-width` = "4.5",
			  `stroke-linecap` = "round", pathLength = "100",
			  `stroke-dasharray` = "30 70",
			  style = sprintf("animation: borderTrail 12s linear infinite; filter: drop-shadow(0 0 6px %s);", theme_color)
			)
		)
	),
    
    div(class = "modern-welcome-action-bg"),
    
    div(class = "modern-welcome-action-inner",
        div(class = "modern-welcome-action-icon-area",
			tags$i(class = sprintf("fas fa-%s modern-welcome-action-icon", action_data$icon_name))
        ),
        div(class = "modern-welcome-action-text-area",
            span(class = "modern-welcome-action-label", "Hızlı İşlem"),
            div(class = "modern-welcome-action-title", action_data$title)
        ),
        div(class = "modern-welcome-action-arrow",
            tags$svg(
              width = "24", height = "24", viewBox = "0 0 24 24",
              fill = "none", stroke = "currentColor", `stroke-width` = "2",
              `stroke-linecap` = "round", `stroke-linejoin` = "round",
              tags$path(d = "M5 12h14"),
              tags$path(d = "m12 5 7 7-7 7")
            )
        )
    )
  )
}

create_modern_preview_button <- function(chat_data) {
  tags$button(
    class = "modern-welcome-preview-btn",
    `data-chat-id` = chat_data$id,
	# Karşılama ekranından doğrudan ana session'a sohbet yükleme isteği gönder
    # (modül eventReactive zincirini atlayarak ilk tıklama sorununu önler)
    onclick = sprintf("if (!this.dataset.loading) {
      this.dataset.loading = 'true';
      Shiny.setInputValue('welcome_load_chat_id', '%s', {priority: 'event'});
      setTimeout(() => delete this.dataset.loading, 1000);
    }", chat_data$id),
    
    div(class = "modern-welcome-preview-icon-box",
		tags$i(class = "fas fa-comment modern-welcome-preview-icon")
    ),
    div(class = "modern-welcome-preview-content",
        span(class = "modern-welcome-preview-title", chat_data$title),
        span(class = "modern-welcome-preview-snippet", chat_data$snippet)
    ),
    span(class = "modern-welcome-preview-time", chat_data$time)
  )
}

createModernWelcomeScreen <- function(saved_chats, main_actions) { 
  recent_chats <- if (length(saved_chats) > 0) {
    sorted_chats <- Filter(Negate(is.null), saved_chats)
    if (length(sorted_chats) > 0) {
      timestamps <- sapply(sorted_chats, function(x) {
        if (inherits(x$timestamp, "POSIXct")) x$timestamp else as.POSIXct(NA)
      })
      sorted_chats[order(timestamps, decreasing = TRUE)]
    } else {
      list()
    }
  } else {
    list()
  }
  
  # Son konuşmaları dinamik olarak oluştur - sadece gerçek sohbetleri göster
  preview_chats <- list()
  
  if (length(recent_chats) > 0) {
    # En fazla 3 sohbet göster
    max_preview <- min(3, length(recent_chats))
    
    for (i in seq_len(max_preview)) {
      chat <- recent_chats[[i]]
      chat_id <- names(recent_chats)[i]
      
      # Sohbet içeriğinden snippet oluştur
      snippet_text <- "..."
      if (!is.null(chat$messages) && length(chat$messages) > 0) {
        first_content <- chat$messages[[1]]$content %||% ""
        if (nzchar(first_content)) {
          snippet_text <- substr(first_content, 1, 50)
          if (nchar(first_content) > 50) {
            snippet_text <- paste0(snippet_text, "...")
          }
        }
      }
      
      # Zaman damgası formatla
      time_text <- tryCatch({
        if (inherits(chat$timestamp, "POSIXct")) {
          format(chat$timestamp, "%d.%m.%Y")
        } else {
          "..."
        }
      }, error = function(e) "...")
      
      preview_chats[[i]] <- list(
        id = chat_id,
        title = chat$title %||% "Başlıksız Söyleşi",
        snippet = snippet_text,
        time = time_text
      )
    }
  }
  
  div(
    class = "modern-welcome-root",
    
    div(class = "modern-welcome-bg-grid",
        div(class = "modern-welcome-video-side",
            div(class = "modern-welcome-video-container",
                tags$video(
                  class = "modern-welcome-video active",
                  `data-index` = "0",
                  muted = NA,
                  playsInline = NA
                ),
                tags$video(
                  class = "modern-welcome-video inactive",
                  `data-index` = "1",
                  muted = NA,
                  playsInline = NA
                ),
                div(class = "modern-welcome-video-texture"),
                div(class = "modern-welcome-video-overlay"),
                div(class = "modern-welcome-video-vignette")
            )
        ),
        
        div(class = "modern-welcome-neural-side",
            div(class = "modern-welcome-neural-canvas-wrapper",
                tags$canvas(class = "modern-welcome-neural-canvas")
            ),
            div(class = "modern-welcome-neural-vignette")
        )
    ),
    
    div(class = "modern-welcome-content",
        div(class = "modern-welcome-card",
            
            div(class = "modern-welcome-left-panel",
                div(class = "modern-welcome-header-section",
                    div(class = "modern-welcome-branding",
                        div(class = "modern-welcome-icon-box",
							tags$i(class = "fas fa-microchip modern-welcome-icon")
                        ),
                        div(class = "modern-welcome-title-group",
                            tags$h1(
                              "MERGEN ",
                              span("Bilge", class = "modern-welcome-title-accent")
                            )
                        )
                    ),
                    div(class = "modern-welcome-greeting-box",
                        div(class = "modern-welcome-greeting-container",
                            p(class = "modern-welcome-greeting-text",
                              span(class = "modern-welcome-greeting-dot"),
                              span(id = "dynamic-greeting-text", ""),
                              span(class = "modern-welcome-greeting-cursor")
                            )
                        )
                    )
                ),
                
				# Son Konuşmalar bölümü - sadece sohbet varsa göster
                if (length(preview_chats) > 0) {
                  div(class = "modern-welcome-footer-section",
                      div(class = "modern-welcome-recent-header",
                          tags$i(class = "fas fa-history modern-welcome-recent-icon"),
                          tags$h3(class = "modern-welcome-recent-title", "Son Konuşmalar")
                      ),
                      div(class = "modern-welcome-recent-list",
                          lapply(preview_chats, create_modern_preview_button)
                      )
                  )
                } else {
                  # Sohbet yoksa boş div
                  div(class = "modern-welcome-footer-section", style = "display: none;")
                }
            ),
            
            div(class = "modern-welcome-right-panel",
                div(class = "modern-welcome-texture-overlay"),
                
                div(class = "modern-welcome-actions-header",
                    div(class = "modern-welcome-actions-title-row",
                        div(class = "modern-welcome-actions-title-left",
                            tags$i(class = "fas fa-bolt modern-welcome-zap-icon"),
                            tags$h2(class = "modern-welcome-actions-title", "Hızlı Başlangıç")
                        )
                    )
                ),
                
                div(class = "modern-welcome-actions-scroll",
                    div(class = "modern-welcome-actions-grid",
                        lapply(main_actions, create_modern_welcome_action)
                    )
                )
            )
        )
    )
  )
}