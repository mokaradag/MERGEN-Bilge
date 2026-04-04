# welcome_screen.R
# Modern karşılama ekranı yardımcı fonksiyonları

safe_source("R/welcome_screen_modern.R", encoding = "UTF-8")

MAIN_ACTIONS_DATA <- build_main_actions_data_from_config(api_config)

createWelcomeScreen <- function(saved_chats) {
  createModernWelcomeScreen(saved_chats, MAIN_ACTIONS_DATA)
}