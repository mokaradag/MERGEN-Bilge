# app.R

# Bu, Shiny uygulaması için ana giriş noktasıdır.
# Gerekli dosyaları doğru sırayla yükler ve uygulamayı başlatır.

# safe_source() fonksiyonunu burada İLK olarak tanımla, herhangi bir dosya yüklenmeden önce.
# Önce mevcut ve çalışan source() yolunu dener.
# Yalnızca kaynak yükleme encoding/parse hatası verirse kontrollü bir yedek
# çözüm devreye girer ve dosya farklı kodlamalarla okunup parse edilmeye çalışılır.
safe_source <- function(file, encoding = "UTF-8", envir = globalenv()) {
  tryCatch({
    source(file, encoding = encoding, local = envir)
    invisible(NULL)
  }, error = function(e) {
    hata_metni <- conditionMessage(e)

    encoding_hatasi_mi <- grepl(
      "INCOMPLETE_STRING|invalid multibyte|unexpected input|EOF within quoted string|nul character|invalid input",
      hata_metni,
      ignore.case = TRUE
    )

    if (!isTRUE(encoding_hatasi_mi)) {
      stop(e)
    }

    raw_size <- file.info(file)$size
    if (is.na(raw_size) || raw_size <= 0) {
      stop(e)
    }

    raw_content <- readBin(file, what = "raw", n = raw_size)

    denenecek_kodlamalar <- c("UTF-8", "WINDOWS-1254", "latin1")
    son_hata <- NULL

    for (kodlama in denenecek_kodlamalar) {
      metin <- tryCatch(
        iconv(list(raw_content), from = kodlama, to = "UTF-8")[[1]],
        error = function(err) NA_character_
      )

      if (is.na(metin) || !nzchar(metin)) next

      metin <- sub("^\ufeff", "", metin, perl = TRUE)

      exprs <- tryCatch(
        parse(text = metin, keep.source = FALSE, encoding = "UTF-8"),
        error = function(err) {
          son_hata <<- err
          NULL
        }
      )

      if (is.null(exprs)) next

      eval(exprs, envir = envir)
      return(invisible(NULL))
    }

    if (!is.null(son_hata)) {
      stop(son_hata)
    }

    stop(e)
  })
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