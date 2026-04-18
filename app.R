# app.R

# Bu, Shiny uygulaması için ana giriş noktasıdır.
# Gerekli dosyaları doğru sırayla yükler ve uygulamayı başlatır.

# safe_source() fonksiyonunu burada İLK olarak tanımla, herhangi bir dosya yüklenmeden önce.
# Önce mevcut ve çalışan source() yolunu dener.
# Yalnızca kaynak yükleme encoding/parse hatası verirse kontrollü bir yedek
# çözüm devreye girer ve dosya farklı kodlamalarla okunup parse edilmeye çalışılır.
required_boot_files <- c(
  "R/utils_safe_source.R",
  "global.R",
  "ui.R",
  "server.R"
)

missing_boot_files <- required_boot_files[!file.exists(required_boot_files)]
if (length(missing_boot_files) > 0) {
  stop(sprintf(
    "Başlatma durduruldu. Eksik dosyalar: %s",
    paste(missing_boot_files, collapse = ", ")
  ))
}

source("R/utils_safe_source.R", encoding = "UTF-8", local = globalenv())

safe_source("global.R", encoding = "UTF-8")
safe_source("ui.R", encoding = "UTF-8")
safe_source("server.R", encoding = "UTF-8")

safe_add_resource_path <- function(prefix, directory) {
  if (!dir.exists(directory)) {
    warning(sprintf("Kaynak yolu atlandı; klasör bulunamadı: %s", directory))
    return(invisible(FALSE))
  }

  withCallingHandlers({
    shiny::addResourcePath(prefix, directory)
  }, warning = function(w) {
    if (grepl("already", conditionMessage(w), ignore.case = TRUE)) {
      invokeRestart("muffleWarning")
    }
  })

  invisible(TRUE)
}

if (dir.exists("www")) {
  for (subdir in list.dirs("www", recursive = FALSE, full.names = FALSE)) {
    safe_add_resource_path(subdir, file.path("www", subdir))
  }
  safe_add_resource_path("img", "www")
} else {
  warning("www klasörü bulunamadı; statik kaynaklar kaydedilmedi.")
}

# 5. Uygulamayı çalıştır.
runApp(shinyApp(ui = ui, server = server),
  host = "0.0.0.0",
  port = 8000,
  launch.browser = TRUE,
  quiet = TRUE
)