# R/module_tts_visualizer.R

#' TTS Visualizer UI
#' Creates the HTML structure for the header animation
ttsVisualizerUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$div(
      id = "tts_viz_container", 
      class = "tts-visualizer",
      # Name Label
      tags$div(class = "tts-char-name", ""),
      # Animated Bars
      tags$div(
        class = "tts-bars",
        tags$div(class = "tts-bar"),
        tags$div(class = "tts-bar"),
        tags$div(class = "tts-bar"),
        tags$div(class = "tts-bar"),
        tags$div(class = "tts-bar")
      )
    )
  )
}

#' TTS Visualizer Server
#' Handles the logic for triggering the animation with correct character themes
ttsVisualizerServer <- function(id, settings_data) {
  moduleServer(id, function(input, output, session) {
    
    # Helper to trigger animation
    trigger_animation <- function(duration = 5) {
      # Resolve current character details
      char_id <- settings_data$selected_character %||% "mergen"
      chars_list <- get_characters_data()$styles
      char_info <- Find(function(x) x$id == char_id, chars_list)
      
      # Defaults
      display_name <- if (!is.null(char_info)) char_info$display_name else "MERGEN"
      accent_color <- if (!is.null(char_info)) char_info$accent else "#7C4DFF"
      
      # Send to JS
      session$sendCustomMessage("updateTTSVisualizer", list(
        state = "play",
        duration = duration,
        name = display_name,
        color = accent_color
      ))
    }
    
    stop_animation <- function() {
      session$sendCustomMessage("updateTTSVisualizer", list(state = "stop"))
    }
    
    return(list(
      trigger = trigger_animation,
      stop = stop_animation
    ))
  })
}