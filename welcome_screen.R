# welcome_screen.R
# Split-out helpers for the welcome screen

welcome_capability_card <- function(title, description, icon_class, gradient_class, message, model_value) {
  div(
    class = "capability-card",
    onclick = sprintf("sendCapabilityMessage('%s', '%s')", message, model_value),
    `data-model` = model_value,
    div(class = paste("capability-icon-wrapper", gradient_class), tags$i(class = icon_class)),
    h3(title),
    p(description)
  )
}

welcome_capabilities_grid <- function() {
  div(
    class = "capabilities-grid",
    style = "gap: 12px;",
    welcome_capability_card(
      title = "Proje Yönetimi",
      description = "Proje planlama, takip ve yönetim",
      icon_class = "fas fa-tasks",
      gradient_class = "gradient-pink",
      message = "Proje yönetimi konusunda bana rehberlik edebilir misin?",
      model_value = "technical name 2"
    ),
    welcome_capability_card(
      title = "Analiz ve Mantık",
      description = "Karmaşık problemleri çözer, analizler yapar",
      icon_class = "fas fa-brain",
      gradient_class = "gradient-blue",
      message = "Karmaşık bir problemin çözümünde bana yardım eder misin?",
      model_value = "technical name 1"
    ),
    welcome_capability_card(
      title = "Yazma ve Düzenleme",
      description = "Metin yazımı, düzenleme ve çeviri",
      icon_class = "fas fa-pen-fancy",
      gradient_class = "gradient-green",
      message = "Profesyonel bir metin yazımında bana rehberlik eder misin?",
      model_value = "technical name 3"
    ),
    welcome_capability_card(
      title = "Kodlama Desteği",
      description = "Programlama ve kod inceleme",
      icon_class = "fas fa-code",
      gradient_class = "gradient-purple",
      message = "Bir programlama projemde kod yazımında yardıma ihtiyacım var.",
      model_value = "technical name 4"
    )
  )
}

welcome_recent_chats_ui <- function(saved_chats) {
  sorted_chats <- Filter(Negate(is.null), saved_chats)
  if (length(sorted_chats) > 0) {
    timestamps <- sapply(sorted_chats, function(x) {
      if (inherits(x$timestamp, "POSIXct")) x$timestamp else as.POSIXct(NA)
    })
    sorted_chats <- sorted_chats[order(timestamps, decreasing = TRUE)]
  }

  if (length(sorted_chats) == 0) return(NULL)

  tagList(
    h4("Son Söyleşiler", class = "welcome-subtitle",
       style = "margin-top: 85px; margin-bottom: 0;"),
    div(
      class = "recent-chats-container",
      style = "margin-top: 0;",
      lapply(head(names(sorted_chats), 3), function(chat_id) {
        chat <- sorted_chats[[chat_id]]
        card_id <- paste0("recent_chat_", gsub("[^[:alnum:]]", "_", chat_id))
        div(
          id = card_id,
          class = "template-card",
          `data-chat-id` = chat_id,
          style = "cursor: pointer;",
          onclick = sprintf("
            if (!this.dataset.loading) {
              this.dataset.loading = 'true';
              Shiny.setInputValue('saved_chats_module-load_chat_id', '%s', {priority: 'event'});
              setTimeout(() => delete this.dataset.loading, 1000);
            }
          ", chat_id),
          p(class = "template-text", tags$strong(chat$title)),
          span(
            style = "font-size: 12px; color: var(--text-muted);",
            paste(chat$message_count, "mesaj -", format(chat$timestamp, "%d.%m.%Y"))
          )
        )
      })
    )
  )
}

# New: pure function (no access to `values`), pass saved_chats explicitly
createWelcomeScreen <- function(saved_chats) {
  div(
    class = "welcome-container animate-fadeIn",
    div(class = "welcome-header",
        div(class = "welcome-title-container",
            tags$h1(
              span("MERGEN", class = "brand-text-primary"),
              span("Bilge", class = "brand-text-secondary"),
              class = "welcome-title"
            )
        )
    ),
    p("Size nasıl yardımcı olabilirim?", class = "welcome-subtitle", style = "margin-bottom: 20px;"),
    welcome_capabilities_grid(),
    welcome_recent_chats_ui(saved_chats)
  )
}
