# welcome_screen.R
# Modern karşılama ekranı yardımcı fonksiyonları

source("R/welcome_screen_modern.R", encoding = "UTF-8")

MAIN_ACTIONS_DATA <- list(
  list(
    id = "project-process",
    title = "Proje ve Süreç Yönetimi",
    message = "Proje yönetimi konusunda bana rehberlik edebilir misin?",
    icon_name = "briefcase",
    themeColor = "#3b82f6",
    model_value = "mergen-local-model"
  ),
  list(
    id = "app-expert",
    title = "Uygulama Uzmanı",
    message = "Uygulama mimarisi konusunda uzman desteğine ihtiyacım var.",
    icon_name = "window-maximize",
    themeColor = "#8b5cf6",
    model_value = "mergen-local-model"
  ),
  list(
    id = "resource-analysis",
    title = "Proje ve Kaynak Analizi",
    message = "Kaynak kullanımını analiz etmem konusunda yardıma ihtiyacım var.",
    icon_name = "chart-bar",
    themeColor = "#06b6d4",
    model_value = "mergen-local-model"
  ),
  list(
    id = "excel-analysis",
    title = "Excel Analizi",
    message = "Excel dosyamı analiz etmem için yardım eder misin?",
    icon_name = "file-excel",
    themeColor = "#10b981",
    model_value = "mergen-local-model"
  ),
  list(
    id = "image-creation",
    title = "Görsel Oluşturma",
    message = "Yapay zeka ile görsel oluşturmak istiyorum.",
    icon_name = "image",
    themeColor = "#ec4899",
    model_value = "mergen-local-model"
  ),
  list(
    id = "coding-support",
    title = "Kodlama Desteği",
    message = "Yazılım geliştirme konusunda yardıma ihtiyacım var.",
    icon_name = "code",
    themeColor = "#f59e0b",
    model_value = "mergen-local-model"
  ),
  list(
    id = "summarization",
    title = "Özetleme Desteği",
    message = "Uzun bir belgeyi özetlemem gerekiyor.",
    icon_name = "file-alt",
    themeColor = "#6366f1",
    model_value = "mergen-local-model"
  )
)

createWelcomeScreen <- function(saved_chats) {
  createModernWelcomeScreen(saved_chats, MAIN_ACTIONS_DATA)
}