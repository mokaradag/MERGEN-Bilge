# R/welcome_screen_modern.R
# Modern karşılama ekranı bileşenleri

create_modern_welcome_action <- function(action_data) {
  theme_color <- action_data$themeColor
  rgb <- col2rgb(theme_color)
  
  tags$button(
    class = "modern-welcome-action-btn",
    style = sprintf("--theme-r: %d; --theme-g: %d; --theme-b: %d;", rgb[1], rgb[2], rgb[3]),
    onclick = sprintf("Shiny.setInputValue('quick_template', {text: '%s', model: '%s'}, {priority: 'event'}); return false;",
                      gsub("'", "\\\\'", action_data$message),
                      action_data$model_value),
    
    div(class = "modern-welcome-action-border-trail",
        tags$svg(
          class = "absolute inset-0 w-full h-full",
          viewBox = "0 0 530.16 80",
          preserveAspectRatio = "none",
			tags$rect(
			  x = "5", y = "5", width = "520.16", height = "70",
			  rx = "16", ry = "16", fill = "none",
			  stroke = theme_color, `stroke-width` = "6",
			  `stroke-linecap` = "round", pathLength = "100",
			  `stroke-dasharray` = "30 70",
			  style = sprintf("animation: borderTrail 3.5s linear infinite; filter: drop-shadow(0 0 4px %s);", theme_color)
			)
        )
    ),
    
    div(class = "modern-welcome-action-bg"),
    
    div(class = "modern-welcome-action-inner",
        div(class = "modern-welcome-action-icon-area",
            icon(action_data$icon_name, class = "modern-welcome-action-icon")
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
    onclick = sprintf("if (!this.dataset.loading) {
      this.dataset.loading = 'true';
      Shiny.setInputValue('saved_chats_module-load_chat_id', '%s', {priority: 'event'});
      setTimeout(() => delete this.dataset.loading, 1000);
    }", chat_data$id),
    
    div(class = "modern-welcome-preview-icon-box",
        icon("message-square", class = "modern-welcome-preview-icon")
    ),
    div(class = "modern-welcome-preview-content",
        span(class = "modern-welcome-preview-title", chat_data$title),
        span(class = "modern-welcome-preview-snippet", chat_data$snippet)
    ),
    span(class = "modern-welcome-preview-time", chat_data$time)
  )
}

createModernWelcomeScreen <- function(saved_chats, main_actions) {
  tags$style(HTML("
    .welcome-fullscreen-wrapper {
      position: fixed !important;
      top: 50px !important;
      left: 250px !important;
      right: 0 !important;
      bottom: 0 !important;
      z-index: 100 !important;
      background: #050505 !important;
      padding: 0 !important;
      margin: 0 !important;
    }
    .welcome-fullscreen-wrapper .modern-welcome-root {
      min-height: 100% !important;
      height: 100% !important;
    }
    .welcome-fullscreen-wrapper .modern-welcome-content {
      padding: 0 !important;
    }
    .welcome-fullscreen-wrapper .modern-welcome-card {
      border-radius: 0 !important;
      border: none !important;
      min-height: 100% !important;
    }
  "))
  
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
  
  preview_chats <- list(
    list(
      id = if (length(recent_chats) > 0) names(recent_chats)[1] else "prev-1",
      title = if (length(recent_chats) > 0) recent_chats[[1]]$title else "React Performans Optimizasyonu",
      snippet = if (length(recent_chats) > 0) {
        msgs <- recent_chats[[1]]$messages
        if (length(msgs) > 0) substr(msgs[[1]]$content, 1, 50) else "..."
      } else "Render döngülerini azaltmak için useMemo...",
      time = if (length(recent_chats) > 0) format(recent_chats[[1]]$timestamp, "%d.%m.%Y") else "2s önce"
    ),
    list(
      id = if (length(recent_chats) > 1) names(recent_chats)[2] else "prev-2",
      title = if (length(recent_chats) > 1) recent_chats[[2]]$title else "Q3 Pazarlama Stratejisi",
      snippet = if (length(recent_chats) > 1) {
        msgs <- recent_chats[[2]]$messages
        if (length(msgs) > 0) substr(msgs[[1]]$content, 1, 50) else "..."
      } else "Hedef kitle analizi tamamlandı, rapor...",
      time = if (length(recent_chats) > 1) format(recent_chats[[2]]$timestamp, "%d.%m.%Y") else "14dk önce"
    ),
    list(
      id = if (length(recent_chats) > 2) names(recent_chats)[3] else "prev-3",
      title = if (length(recent_chats) > 2) recent_chats[[3]]$title else "Python Veri Görselleştirme",
      snippet = if (length(recent_chats) > 2) {
        msgs <- recent_chats[[3]]$messages
        if (length(msgs) > 0) substr(msgs[[1]]$content, 1, 50) else "..."
      } else "Matplotlib ile oluşturulan grafikler...",
      time = if (length(recent_chats) > 2) format(recent_chats[[3]]$timestamp, "%d.%m.%Y") else "2sa önce"
    )
  )
  
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
                            icon("cpu", class = "modern-welcome-icon")
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
                
                div(class = "modern-welcome-footer-section",
                    div(class = "modern-welcome-recent-header",
                        icon("history", class = "modern-welcome-recent-icon"),
                        tags$h3(class = "modern-welcome-recent-title", "Son Konuşmalar")
                    ),
                    div(class = "modern-welcome-recent-list",
                        lapply(preview_chats, create_modern_preview_button)
                    )
                )
            ),
            
            div(class = "modern-welcome-right-panel",
                div(class = "modern-welcome-texture-overlay"),
                
                div(class = "modern-welcome-actions-header",
                    div(class = "modern-welcome-actions-title-row",
                        div(class = "modern-welcome-actions-title-left",
                            icon("zap", class = "modern-welcome-zap-icon"),
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