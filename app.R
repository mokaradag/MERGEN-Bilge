# app.R

# Bu, Shiny uygulaması için ana giriş noktasıdır.
# Gerekli dosyaları doğru sırayla yükler ve uygulamayı başlatır.

# safe_source() fonksiyonunu burada İLK olarak tanımla, herhangi bir dosya yüklenmeden önce.
# Önce mevcut ve çalışan source() yolunu dener.
# Yalnızca kaynak yükleme encoding/parse hatası verirse kontrollü bir yedek
# çözüm devreye girer ve dosya farklı kodlamalarla okunup parse edilmeye çalışılır.
source("R/utils_safe_source.R", encoding = "UTF-8", local = globalenv())

# 1. Global yapılandırmayı ve tüm yardımcı/modül dosyalarını yükle.
#    Böylece tüm kütüphaneler, fonksiyonlar ve modül tanımları kullanılabilir olur.
#    global.R ayrıca dokümantasyonun açık olması için safe_source() fonksiyonunu
#    (aynı kopya) tekrar tanımlar.
safe_source("global.R", encoding = "UTF-8")

# 2. Kullanıcı arayüzü tanımını yükle.
#    Bu işlem `ui` nesnesini yükler.
safe_source("ui.R", encoding = "UTF-8")

# 3. Sunucu (server) mantığını yükle.
#    Bu işlem `server` fonksiyonunu yükler.
safe_source("server.R", encoding = "UTF-8")

# 4. www/ alt klasörlerini kaynak yolu olarak kaydet.
#    "Run App" butonu runApp(appDir) kullanır ve www/ otomatik sunulur.
#    Ancak Ctrl+Enter ile çalıştırıldığında shinyApp(ui, server) uygulama
#    dizinini bilmez; bu yüzden www/ kaynakları bulunamaz.
#    runApp(".") kullanılamaz çünkü:
#      - app.R'ı tekrar source ederek özyineleme yaratır
#      - normalizePath ile uzun yolları (>260 karakter) çözemez (Windows VM sorunu)
#    Çözüm: Her www/ alt klasörünü kendi adıyla kaydet.
#    Örn: addResourcePath("css", "www/css") → /css/style.css URL'si çalışır.
for (subdir in list.dirs("www", recursive = FALSE, full.names = FALSE)) {
  addResourcePath(subdir, file.path("www", subdir))
}
# www/ kök dizinindeki dosyalar (mergen_avatar.png, company_logo.png vb.)
# boş prefix ile kaydedilemez. "img" prefix'i ile www/ kök dizinini kaydet.
# Kodda bu dosyalar "img/dosya.png" şeklinde referans edilir.
addResourcePath("img", "www")

# 5. Uygulamayı çalıştır.
runApp(shinyApp(ui = ui, server = server),
  host = "0.0.0.0",
  port = 8000,
  launch.browser = TRUE,
  quiet = TRUE
)