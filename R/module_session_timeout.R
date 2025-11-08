# R/module_session_timeout.R

sessionTimeoutServer <- function(id, idle_minutes = 30, activity_inputs = character()) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    last_activity <- reactiveVal(Sys.time())
    session_active <- reactiveVal(TRUE)
    warning_shown <- reactiveVal(FALSE)

    # Tüm input değişikliklerini izle
    lapply(activity_inputs, function(id_) {
      observeEvent(session$input[[id_]], {
        last_activity(Sys.time())
        warning_shown(FALSE)  # Aktivite varsa uyarıyı sıfırla
      }, ignoreInit = TRUE)
    })
    
    # Tab değişimlerini de izle (kullanıcı farklı sayfalara gidiyorsa aktiftir)
    observeEvent(session$input$tabs, {
      last_activity(Sys.time())
      warning_shown(FALSE)
    }, ignoreInit = TRUE)
    
    # Fare hareketini ve klavye girişini izle (JavaScript üzerinden)
    session$onFlushed(function() {
      shinyjs::runjs(sprintf("
        // Fare hareketi ve klavye aktivitesini izle
        var timeoutActivityHandler = function() {
          Shiny.setInputValue('%s', Math.random(), {priority: 'event'});
        };
        
        // Throttle: Her 30 saniyede bir aktivite bildirimi
        var lastActivityTime = 0;
        var throttledHandler = function() {
          var now = Date.now();
          if (now - lastActivityTime > 30000) {  // 30 saniye
            lastActivityTime = now;
            timeoutActivityHandler();
          }
        };
        
        document.addEventListener('mousemove', throttledHandler, {passive: true});
        document.addEventListener('keydown', throttledHandler, {passive: true});
        document.addEventListener('click', throttledHandler, {passive: true});
        document.addEventListener('scroll', throttledHandler, {passive: true});
      ", ns("user_activity")))
    }, once = TRUE)
    
    # JavaScript'ten gelen aktivite sinyalini dinle
    observeEvent(input$user_activity, {
      last_activity(Sys.time())
      warning_shown(FALSE)
    }, ignoreInit = TRUE)

    # Periyodik kontrol - her dakika
    observe({
      invalidateLater(60000, session)  # Her dakika kontrol

      if (!isTRUE(session_active())) return()
      
      idle_time <- difftime(Sys.time(), last_activity(), units = "mins")

      # Eğer hareketsizlik süresini aşmışsa ve henüz uyarı gösterilmemişse
      if (idle_time > idle_minutes && !warning_shown()) {
        session_active(FALSE)
        warning_shown(TRUE)
        showModal(modalDialog(
          title = "Oturum Zaman Aşımı",
          paste0("Oturumunuz ", round(idle_time, 1), " dakika hareketsizlik nedeniyle sona erecek. Devam etmek için Tamam'a tıklayın."),
          footer = tagList(
            actionButton(ns("continue_session"), "Tamam"),
            actionButton(ns("logout_session"), "Çıkış Yap")
          ),
          easyClose = FALSE
        ))
      }
    })

    observeEvent(input$continue_session, {
      removeModal()
      last_activity(Sys.time())
      session_active(TRUE)
      warning_shown(FALSE)
    })

    observeEvent(input$logout_session, {
      session$close()
    })
  })
}