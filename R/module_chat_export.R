# R/module_chat_export.R
# Moves "copy chat" and export .txt out of server.R

chatExportInit <- function(input, output, session, values, user_display_name) {

  shiny::observeEvent(input$copy_chat_btn, {
    req(length(values$messages) > 0)
    chat_text <- vapply(values$messages, function(msg) {
      author <- if (identical(msg$type, "user")) user_display_name else "MERGEN Bilge"
      sprintf("[%s] %s:\n%s", msg$timestamp, author, msg$content)
    }, "", USE.NAMES = FALSE)
    full <- paste(chat_text, collapse = "\n\n--------------------------------\n\n")
    js_string <- jsonlite::toJSON(full, auto_unbox = TRUE)
    shinyjs::runjs(paste0("navigator.clipboard.writeText(", js_string, ");"))

    original_html <- as.character(htmltools::tagList(icon("clipboard"), span("Sohbeti Kopyala", class = "btn-text")))
    shinyjs::html("copy_chat_btn", html = as.character(htmltools::tagList(icon("check"), "Kopyalandı!")), add = FALSE)
    shinyjs::disable("copy_chat_btn")
    shinyjs::delay(2000, {
      shinyjs::html("copy_chat_btn", html = original_html, add = FALSE)
      shinyjs::enable("copy_chat_btn")
    })
  }, ignoreInit = TRUE)

  output$export_current_chat_txt <- downloadHandler(
    filename = function() {
      paste0("mergen_sohbet_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".txt")
    },
    content = function(file) {
      chat_text <- vapply(values$messages, function(msg) {
        author <- if (identical(msg$type, "user")) user_display_name else "MERGEN Bilge"
        sprintf("[%s] %s:\n%s\n", msg$timestamp, author, msg$content)
      }, "", USE.NAMES = FALSE)
      writeLines(paste(chat_text, collapse = "\n--------------------------------\n"), file)
    }
  )
}
