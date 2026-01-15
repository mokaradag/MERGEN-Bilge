# R/module_feedback.R
# Geri bildirim modalı ve veritabanı işlemleri

feedbackUI <- function(id) {
  ns <- NS(id)
  
  tags$div(
    id = ns("feedback_modal_container"),
    class = "feedback-modal-overlay hidden",
    onclick = sprintf("if(event.target === this) Shiny.setInputValue('%s', true, {priority: 'event'})", ns("close_modal")),
    
    div(
      class = "feedback-modal-content",
      
      # Başlık
	  div(
        class = "feedback-modal-header",
        tags$h3(id = ns("modal_title"), icon("comment-dots"), " Geri Bildirim"),
        actionButton(ns("close_modal"), "", icon = icon("times"), class = "feedback-close-btn")
      ),
      
      div(
        class = "feedback-modal-body",
        
        div(
          class = "feedback-info-note",
          icon("info-circle"),
          span("Geri bildiriminiz MERGEN Bilge uygulamasının geliştirilmesi için kullanılacaktır.")
        ),
        
        div(
          class = "feedback-tags-section",
          h4("Bu yanıtla ilgili"),
          div(id = ns("tag_buttons"), class = "feedback-tag-buttons")
        ),
        
        div(
          class = "feedback-comment-section",
          h4("Ek yorumunuz"),
          tags$textarea(
            id = ns("feedback_comment"),
            class = "feedback-textarea",
            placeholder = "Düşüncelerinizi buraya yazabilirsiniz...",
            rows = 4
          )
        )
      ),
      
      # Alt butonlar
      div(
        class = "feedback-modal-footer",
        actionButton(ns("cancel"), "İptal", class = "btn-feedback-cancel"),
        actionButton(ns("submit"), "Gönder", class = "btn-feedback-submit")
      )
    )
  )
}

feedbackServer <- function(id, current_user_id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    # Reaktif değerler
    current_message_id <- reactiveVal(NULL)
    current_feedback_type <- reactiveVal(NULL)
    selected_tags <- reactiveVal(character(0))
    
    # Hızlı seçim etiketleri
	like_tags <- c("Açık ve net", "Detaylı", "Faydalı", "Hızlı yanıt", "Profesyonel", "Doğru Bilgi", "Diğer")
    dislike_tags <- c("Belirsiz", "Eksik bilgi", "Yanlış", "Konu dışı", "Karmaşık", "Yanıltıcı", "Diğer")
    
	# Modal açma fonksiyonu
	open_modal <- function(message_id, feedback_type, on_cancel = NULL) {
      current_message_id(message_id)
      current_feedback_type(feedback_type)
      selected_tags(character(0))
      
      session$userData$feedback_cancel_callback <- on_cancel
      
      # Modal başlığını güncelle
      title_text <- if (feedback_type == "like") "Bu Yanıtı Beğendiniz" else "Bu Yanıt Hakkında Geri Bildirim"
      session$sendCustomMessage("updateFeedbackTitle", list(
        ns = ns("modal_title"),
        text = title_text
      ))
      
      # Etiket butonlarını oluştur
      tags_to_use <- if (feedback_type == "like") like_tags else dislike_tags
      button_class <- if (feedback_type == "like") "tag-like" else "tag-dislike"
      
      buttons_html <- paste(
        sapply(tags_to_use, function(tag) {
          sprintf(
            '<button class="feedback-tag-btn %s" data-tag="%s" onclick="Shiny.setInputValue(\'%s\', \'%s\', {priority: \'event\'})">%s</button>',
            button_class, tag, ns("tag_clicked"), tag, tag
          )
        }),
        collapse = ""
      )
      
      session$sendCustomMessage("updateFeedbackTags", list(
        target = ns("tag_buttons"),
        html = buttons_html
      ))
      
      # Yorum alanını temizle
      updateTextAreaInput(session, "feedback_comment", value = "")
      
      # Modalı göster
      shinyjs::runjs(sprintf("document.getElementById('%s').classList.remove('hidden');", ns("feedback_modal_container")))
    }
    
    # Etiket tıklama
    observeEvent(input$tag_clicked, {
      tag <- input$tag_clicked
      current <- selected_tags()
      
      if (tag %in% current) {
        selected_tags(setdiff(current, tag))
      } else {
        selected_tags(c(current, tag))
      }
      
      # Butonu görsel olarak güncelle
      session$sendCustomMessage("toggleFeedbackTag", list(tag = tag))
    })
    
	# Gönder butonu
    observeEvent(input$submit, {
      req(current_message_id(), current_feedback_type())
      
      tags_str <- paste(selected_tags(), collapse = ",")
      comment <- trimws(input$feedback_comment %||% "")
      
      tryCatch({
        save_feedback_to_db_extended(
          user_id = current_user_id,
          message_id = current_message_id(),
          feedback_type = current_feedback_type(),
          tags = if (nchar(tags_str) > 0) tags_str else NULL,
          comment = if (nchar(comment) > 0) comment else NULL
        )
        
        session$sendCustomMessage("showToast", list(
          message = "Geri bildiriminiz kaydedildi. Teşekkür ederiz!",
          type = "success"
        ))
        
        shinyjs::runjs(sprintf("document.getElementById('%s').classList.add('hidden');", ns("feedback_modal_container")))
        
      }, error = function(e) {
        session$sendCustomMessage("showToast", list(
          message = paste("Hata:", e$message),
          type = "error"
        ))
      })
    })
    
	# İptal/Kapat
    observeEvent(input$cancel, {
      if (!is.null(session$userData$feedback_cancel_callback) && is.function(session$userData$feedback_cancel_callback)) {
        session$userData$feedback_cancel_callback()
      }
      shinyjs::runjs(sprintf("document.getElementById('%s').classList.add('hidden');", ns("feedback_modal_container")))
    })
    
    observeEvent(input$close_modal, {
      if (!is.null(session$userData$feedback_cancel_callback) && is.function(session$userData$feedback_cancel_callback)) {
        session$userData$feedback_cancel_callback()
      }
      shinyjs::runjs(sprintf("document.getElementById('%s').classList.add('hidden');", ns("feedback_modal_container")))
    })
    
    # Dışa açılan fonksiyon
    list(
      open = open_modal
    )
  })
}