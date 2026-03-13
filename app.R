# app.R

# This is the main entry point for the Shiny application.
# It sources the necessary files in the correct order and launches the app.

# Define safe_source() here FIRST, before sourcing anything.
# On some Windows VMs with Turkish locale, source(encoding = "UTF-8") still
# misreads multi-byte characters causing INCOMPLETE_STRING parse errors.
# This reads the file as UTF-8 text first, then parses the text buffer,
# which completely bypasses the file-level encoding bug.
safe_source <- function(file, encoding = "UTF-8", envir = globalenv()) {
  source(file, encoding = encoding, local = envir)
}

# 1. Source the global configuration and all helper/module files.
#    This makes all libraries, functions, and module definitions available.
#    global.R also defines safe_source() (identical copy) for documentation clarity.
safe_source("global.R", encoding = "UTF-8")

# 2. Source the user interface definition.
#    This loads the `ui` object.
safe_source("ui.R", encoding = "UTF-8")

# 3. Source the server logic.
#    This loads the `server` function.
safe_source("server.R", encoding = "UTF-8")

# 4. Run the application.
#    This function takes the UI and server components and starts the Shiny app.
shinyApp(ui = ui, server = server)
