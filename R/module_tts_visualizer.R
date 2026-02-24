# R/module_tts_visualizer.R

#' TTS Visualizer UI
ttsVisualizerUI <- function(id) {
  ns <- NS(id)
  
  tags$div(
    class = "tts-outer-wrapper",
    
    # 1. Main Container (Left)
    tags$div(
      id = ns("container"), 
      class = "tts-visualizer-container shiny-visual-hidden", 
      
      # Avatar and Name
      tags$div(
        class = "tts-char-info",
        tags$img(id = ns("char_avatar"), class = "tts-avatar-img", src = ""),
        tags$span(id = ns("char_name"), class = "tts-name-text", "")
      ),
      
      # Canvas
      tags$canvas(id = "tts_canvas", class = "tts-canvas"),
      
	  # Tooltip (Hidden by default, shown via CSS when 'talking-mode' + hover)
      tags$div(
        class = "tts-tooltip", 
        tags$i(class = "fa-solid fa-circle-stop"), 
        tags$span("Seslendirmeyi durdur")
      )
    )
  )
}

#' TTS Visualizer Server
ttsVisualizerServer <- function(id, settings_data) {
  moduleServer(id, function(input, output, session) {
    
    ns <- session$ns

    # Update visualizer state
    send_state <- function(state = "idle", duration = NULL) {
      char_id <- settings_data$selected_character %||% "mergen"
      chars_list <- get_characters_data()$styles
      char_info <- Find(function(x) x$id == char_id, chars_list)

      display_name <- if (!is.null(char_info)) char_info$display_name else "MERGEN"
      accent_color <- if (!is.null(char_info)) char_info$accent else "#7C4DFF"
      avatar_src <- if (!is.null(char_info) && !is.null(char_info$avatar)) char_info$avatar else "mergen_avatar.png"

      # 1. Update Content (Image, Text, Colors)
      shinyjs::runjs(sprintf("$('#%s').attr('src', '%s');", ns("char_avatar"), avatar_src))
      shinyjs::runjs(sprintf("$('#%s').text('%s');", ns("char_name"), display_name))
      shinyjs::runjs(sprintf("$('#%s').css('border-color', '%s');", ns("char_avatar"), accent_color))
      shinyjs::runjs(sprintf("$('#%s').css('color', '%s');", ns("char_name"), accent_color))

      # 2. FORCE Class Toggling via ShinyJS (Guaranteed approach)
      # If talking, add class to container immediately. If not, remove it.
      if (state == "talking") {
        shinyjs::addClass(id = "container", class = "talking-mode")
      } else {
        shinyjs::removeClass(id = "container", class = "talking-mode")
      }

      # 3. Send Animation Message to JS
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

    # Helpers
    trigger_animation <- function(duration = 5) {
      send_state(state = "talking", duration = duration)
    }

    stop_animation <- function() {
      send_state(state = "stop")
    }

    # Görünürlük mantığı
    observe({
      is_enabled <- isTRUE(settings_data$enable_tts_audio)
      shinyjs::toggleClass(id = "container", class = "shiny-visual-hidden", condition = !is_enabled)

      if (is_enabled) {
        # Birden fazla gecikmeyle boyutlandırma dene (sekme gizli olabilir)
        shinyjs::delay(200, {
          session$sendCustomMessage("resizeTTSVisualizer", list())
          send_state(state = "idle")
        })
        shinyjs::delay(800, {
          session$sendCustomMessage("resizeTTSVisualizer", list())
        })
      } else {
        stop_animation()
      }
    })

    # Theme update on character change
    observeEvent(settings_data$selected_character, {
      send_state(state = "idle")
    }, ignoreNULL = FALSE)

    return(list(
      trigger = trigger_animation,
      stop = stop_animation
    ))
  })
}