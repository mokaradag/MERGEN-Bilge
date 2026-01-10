# welcome_screen.R
# Modern karşılama ekranı yardımcı fonksiyonları

source("R/welcome_screen_modern.R", encoding = "UTF-8")

MAIN_ACTIONS_DATA <- list(
  list(
    id = "project-process",
    title = "Proje ve Süreç Yönetimi",
    message = "Proje yönetimi konusunda bana rehberlik edebilir misin?",
    description = "Proje planlama, görev atama, zaman çizelgesi oluşturma ve takip süreçlerinde uzman rehberlik alın. Agile, Scrum veya Waterfall metodolojileri hakkında detaylı bilgi ve öneriler.",
    icon_name = "briefcase",
    themeColor = "#3b82f6",
    model_value = "mergen-local-model"
  ),
  list(
    id = "app-expert",
    title = "Uygulama Uzmanı",
    message = "Uygulama mimarisi konusunda uzman desteğine ihtiyacım var.",
    description = "Mikroservis mimarisi, API tasarımı, veritabanı şemaları ve ölçeklenebilir uygulama yapıları oluşturma konusunda derinlemesine teknik danışmanlık.",
    icon_name = "window-maximize",
    themeColor = "#8b5cf6",
    model_value = "mergen-local-model"
  ),
  list(
    id = "resource-analysis",
    title = "Proje ve Kaynak Analizi",
    message = "Kaynak kullanımını analiz etmem konusunda yardıma ihtiyacım var.",
    description = "Excel, CSV veya RData dosyalarınızı analiz ederek veri görselleştirme, istatistiksel analiz ve anlamlı raporlar oluşturun.",
    icon_name = "chart-bar",
    themeColor = "#06b6d4",
    model_value = "mergen-local-model"
  ),
  list(
    id = "excel-analysis",
    title = "Excel Analizi",
    message = "Excel dosyamı analiz etmem için yardım eder misin?",
    description = "MCP Excel aracı ile karmaşık veri setlerini otomatik olarak analiz edin. Formüller, pivot tablolar, grafikler ve veri temizleme işlemleri.",
    icon_name = "file-excel",
    themeColor = "#10b981",
    model_value = "mergen-local-model"
  ),
  list(
    id = "image-creation",
    title = "Görsel Oluşturma",
    message = "Yapay zeka ile görsel oluşturmak istiyorum.",
    description = "Metin tabanlı açıklamalarla AI görüntü oluşturma modellerini kullanarak özel görseller tasarlayın.",
    icon_name = "image",
    themeColor = "#ec4899",
    model_value = "mergen-local-model"
  ),
  list(
    id = "coding-support",
    title = "Kodlama Desteği",
    message = "Yazılım geliştirme konusunda yardıma ihtiyacım var.",
    description = "Python, R, JavaScript ve diğer dillerde kod optimizasyonu, hata ayıklama, algoritma tasarımı ve best practice önerileri.",
    icon_name = "code",
    themeColor = "#f59e0b",
    model_value = "mergen-local-model"
  ),
  list(
    id = "summarization",
    title = "Özetleme Desteği",
    message = "Uzun bir belgeyi özetlemem gerekiyor.",
    description = "PDF, Word, metin dosyaları veya web içeriklerini özetleyin. Anahtar noktaları çıkarın ve yapılandırılmış özetler oluşturun.",
    icon_name = "file-alt",
    themeColor = "#6366f1",
    model_value = "mergen-local-model"
  )
)

createWelcomeScreen <- function(saved_chats) {
  createModernWelcomeScreen(saved_chats, MAIN_ACTIONS_DATA)
}