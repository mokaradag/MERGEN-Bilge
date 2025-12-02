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
        # Generate 30 bars for a high-resolution waveform
        lapply(1:30, function(i) tags$div(class = "tts-bar"))
      )
    )
  )
}

#' TTS Visualizer Server
#' Handles the logic for triggering the animation with correct character themes
ttsVisualizerServer <- function(id, settings_data) {
  moduleServer(id, function(input, output, session) {

    # Resolve the current character style and send it to the client
    send_state <- function(state = "idle", duration = NULL) {
      char_id <- settings_data$selected_character %||% "mergen"
      chars_list <- get_characters_data()$styles
      char_info <- Find(function(x) x$id == char_id, chars_list)

      display_name <- if (!is.null(char_info)) char_info$display_name else "MERGEN"
      accent_color <- if (!is.null(char_info)) char_info$accent else "#7C4DFF"

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