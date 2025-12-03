# R/module_tts_visualizer.R

#' TTS Visualizer UI
#' Creates the HTML structure for the header animation
ttsVisualizerUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$div(
      id = ns("container"), 
      class = "tts-visualizer-container",
      style = "display: none;", # Hidden by default, toggled by settings
      
      # Avatar and Name Area
      tags$div(
        class = "tts-char-info",
        tags$img(id = ns("char_avatar"), class = "tts-avatar-img", src = ""),
        tags$span(id = ns("char_name"), class = "tts-name-text", "")
      ),
      
      # Wave Animation Canvas
      tags$canvas(id = "tts_canvas", class = "tts-canvas"),
      
      # Stop Button (Hidden by default, shown when talking)
      tags$div(
        id = ns("stop_btn_wrapper"),
        class = "tts-stop-wrapper",
        style = "display: none;", 
        actionButton(
          inputId = ns("stop_tts"),
          label = NULL,
          icon = icon("stop"),
          class = "btn-tts-stop",
          title = "Seslendirmeyi Durdur"
        )
      )
    )
  )
}

#' TTS Visualizer Server
#' Handles the logic for triggering the animation with correct character themes
ttsVisualizerServer <- function(id, settings_data) {
  moduleServer(id, function(input, output, session) {
    
    ns <- session$ns
    # Stop Button Logic
    observeEvent(input$stop_tts, {
      # MODIFIED: Use the correct JS object 'ttsVisualizerState'
      shinyjs::runjs("if(window.ttsVisualizerState) window.ttsVisualizerState.stop();")
    })

    # Resolve the current character style and send it to the client
    send_state <- function(state = "idle", duration = NULL) {
      char_id <- settings_data$selected_character %||% "mergen"
      chars_list <- get_characters_data()$styles
      char_info <- Find(function(x) x$id == char_id, chars_list)

      display_name <- if (!is.null(char_info)) char_info$display_name else "MERGEN"
      accent_color <- if (!is.null(char_info)) char_info$accent else "#7C4DFF"
      avatar_src <- if (!is.null(char_info) && !is.null(char_info$avatar)) char_info$avatar else "mergen_avatar.png"

      # Apply content updates
      shinyjs::runjs(sprintf("$('#%s').attr('src', '%s');", ns("char_avatar"), avatar_src))
      shinyjs::runjs(sprintf("$('#%s').text('%s');", ns("char_name"), display_name))
      
      # Apply Color Updates (Border & Font)
      shinyjs::runjs(sprintf("$('#%s').css('border-color', '%s');", ns("char_avatar"), accent_color))
      shinyjs::runjs(sprintf("$('#%s').css('color', '%s');", ns("char_name"), accent_color))

      # Send animation state
      session$sendCustomMessage(
        "updateTTSVisualizer",
        list(
          state = state,
          duration = duration,
          name = display_name,
          color = accent_color,
          stopBtnId = ns("stop_btn_wrapper") # Pass ID to JS to toggle stop button
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

    # Toggle container visibility based on settings and refresh client state
    observe({
      is_enabled <- isTRUE(settings_data$enable_tts_audio)
      shinyjs::toggle(id = "container", condition = is_enabled)

      if (is_enabled) {
        shinyjs::delay(200, {
          session$sendCustomMessage("resizeTTSVisualizer", list())
          send_state(state = "idle")
        })
      } else {
        stop_animation()
      }
    })

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