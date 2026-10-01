mergen_session_sync_settings_profile <- function(session, settings_data) {
  if (exists("mergen_session_on_owner_change", mode = "function"))
    mergen_session_on_owner_change(session, function(neden) settings_data$user_config <- NULL)
  if (exists("mergen_session_identity_signal", mode = "function")) {
    kimlik_sinyali <- mergen_session_identity_signal(session)
    shiny::observe({
      kimlik_sinyali()
      settings_data$user_config <- make_user_session_data_accessors(session)$get_user_config(NULL)
    })
  }
}
