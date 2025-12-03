# R/module_tts_visualizer.R

#' TTS Visualizer UI
#' Creates the HTML structure for the header animation
ttsVisualizerUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$div(
      id = "tts_viz_container", 
      class = "tts-visualizer-container",
      # Added Avatar and Name elements
      tags$div(
        class = "tts-char-info",
        tags$img(id = ns("char_avatar"), class = "tts-avatar-img", src = ""),
        tags$span(id = ns("char_name"), class = "tts-name-text", "")
      ),
      # The canvas for the wave animation
      tags$canvas(id = "tts_canvas", class = "tts-canvas"),
      # Keep overlay hidden or remove text as we now have explicit name
      tags$div(class = "tts-overlay-name", "", style = "display: none;")
    )
  )
}

#' TTS Visualizer Server
#' Handles the logic for triggering the animation with correct character themes
ttsVisualizerServer <- function(id, settings_data) {
  moduleServer(id, function(input, output, session) {
    
    # Helper to resolve namespace for JS calls
    ns <- session$ns

    # Resolve the current character style and send it to the client
    send_state <- function(state = "idle", duration = NULL) {
      char_id <- settings_data$selected_character %||% "mergen"
      chars_list <- get_characters_data()$styles
      char_info <- Find(function(x) x$id == char_id, chars_list)

      display_name <- if (!is.null(char_info)) char_info$display_name else "MERGEN"
      accent_color <- if (!is.null(char_info)) char_info$accent else "#7C4DFF"
      
      # Default avatar if missing
      avatar_src <- if (!is.null(char_info) && !is.null(char_info$avatar)) char_info$avatar else "mergen_avatar.png"

      # Update UI elements via JS (Avatar & Name)
      shinyjs::runjs(sprintf("$('#%s').attr('src', '%s');", ns("char_avatar"), avatar_src))
      shinyjs::runjs(sprintf("$('#%s').text('%s');", ns("char_name"), display_name))

      session$sendCustomMessage(
        "updateTTSVisualizer",
        list(
          state = state,
          duration = duration,
          name = display_name,
          color = accent_color
        )
      )
    }

    # Helper to trigger animation
    trigger_animation <- function(duration = 5) {
      send_state(state = "talking", duration = duration)
    }

    stop_animation <- function() {
      send_state(state = "stop")
    }

    # Keep the header themed when the character selection changes
    observeEvent(settings_data$selected_character, {
      send_state(state = "idle")
    }, ignoreNULL = FALSE)

    return(list(
      trigger = trigger_animation,
      stop = stop_animation
    ))
  })
}