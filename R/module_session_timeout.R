# R/module_session_timeout.R

sessionTimeoutServer <- function(id, idle_minutes = 30, activity_inputs = character()) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    last_activity <- reactiveVal(Sys.time())
    session_active <- reactiveVal(TRUE)

    # Bump activity on any of the provided inputs
    lapply(activity_inputs, function(id_) {
      observeEvent(session$input[[id_]], {
        last_activity(Sys.time())
      }, ignoreInit = TRUE)
    })

    # Periodic check
    observe({
      invalidateLater(60000, session)  # check every minute

      if (!isTRUE(session_active())) return()

      if (difftime(Sys.time(), last_activity(), units = "mins") > idle_minutes) {
        session_active(FALSE)
        showModal(modalDialog(
          title = "Oturum Zaman Aşımı",
          "Oturumunuz hareketsizlik nedeniyle sona erecek. Devam etmek için Tamam'a tıklayın.",
          footer = tagList(
            actionButton(ns("continue_session"), "Tamam"),
            actionButton(ns("logout_session"), "Çıkış Yap")
          )
        ))
      }
    })

    observeEvent(input$continue_session, {
      removeModal()
      last_activity(Sys.time())
      session_active(TRUE)
    })

    observeEvent(input$logout_session, {
      session$close()
    })
  })
}
