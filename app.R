# app.R

# This is the main entry point for the Shiny application.
# It sources the necessary files in the correct order and launches the app.

# 1. Source the global configuration and all helper/module files.
#    This makes all libraries, functions, and module definitions available.
source("global.R")

# 2. Source the user interface definition.
#    This loads the `ui` object.
source("ui.R")

# 3. Source the server logic.
#    This loads the `server` function.
source("server.R")

# 4. Run the application.
#    This function takes the UI and server components and starts the Shiny app.
shinyApp(ui = ui, server = server)
