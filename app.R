# app.R

# Bu, Shiny uygulaması için ana giriş noktasıdır.
# Gerekli dosyaları doğru sırayla yükler ve uygulamayı başlatır.

# safe_source() fonksiyonunu burada İLK olarak tanımla, herhangi bir dosya yüklenmeden önce.
# Türkçe yerel ayara sahip bazı Windows sanal makinelerinde source(encoding = "UTF-8")
# çok baytlı karakterleri hâlâ yanlış okuyarak INCOMPLETE_STRING parse hatalarına
# neden olabilir. Bu yöntem dosyayı önce UTF-8 metni olarak okur, sonra metin
# tamponunu parse eder; böylece dosya düzeyindeki encoding hatasını tamamen atlar.
safe_source <- function(file, encoding = "UTF-8", envir = globalenv()) {
  lines <- readLines(file, encoding = encoding, warn = FALSE)
  exprs <- parse(text = lines, keep.source = FALSE, encoding = encoding)
  eval(exprs, envir = envir)
  invisible(NULL)
}

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

# 4. Uygulamayı çalıştır.
#    Bu fonksiyon UI ve server bileşenlerini alır ve Shiny uygulamasını başlatır.
shinyApp(ui = ui, server = server)