# welcome_screen.R
# Modern karşılama ekranı yardımcı fonksiyonları

if (!exists("createModernWelcomeScreen", mode = "function", inherits = TRUE)) {
  stop(
    "Welcome ekranı yükleme sırası hatalı: R/welcome_screen_modern.R önce yüklenmelidir.",
    call. = FALSE
  )
}

MAIN_ACTIONS_DATA <- build_main_actions_data_from_config(api_config)

createWelcomeScreen <- function(saved_chats) {
  createModernWelcomeScreen(saved_chats, MAIN_ACTIONS_DATA)
}