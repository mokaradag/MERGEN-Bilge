# Dosya Yolu: R/module_file_preview.R
# Açıklama: Dosya önizleme modülü sunucu (server) tarafı.
#            Yüklenen dosyaların (PDF, Excel, Word, Metin vb.) modal pencerelerde
#            önizlenmesini ve indirilmesini yönetir.

# ==============================================================================
# DOSYA ÖNİZLEME SERVER
# ==============================================================================

filePreviewServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Önizlenecek veriyi tutan reaktif değer
    preview_data <- reactiveVal(NULL)
    # Önizlenen dosyanın bilgilerini saklayan reaktif liste
    file_storage <- reactiveValues(preview_file = NULL)

    # Excel verilerini DataTables kullanarak render eden çıktı
    output$preview_excel_table <- DT::renderDataTable({
      req(preview_data())
      DT::datatable(preview_data(), options = list(
        pageLength = 10,
        scrollX = TRUE,
        scrollY = FALSE,
        dom = 'frtip',
        autoWidth = TRUE
      ))
    })

    # Önizlemesi yapılan dosyayı indirmeyi sağlayan handler
    output$download_preview_file <- downloadHandler(
      filename = function() {
        if (!is.null(file_storage$preview_file)) {
          return(file_storage$preview_file$name)
        }
        return("file.txt")
      },
      content = function(file) {
        # Dosya mevcutsa kopyalama işlemini gerçekleştir
        if (!is.null(file_storage$preview_file) &&
            !is.null(file_storage$preview_file$datapath) &&
            path_exists_relaxed(file_storage$preview_file$datapath)) {
          tryCatch(
            fs::file_copy(file_storage$preview_file$datapath, file, overwrite = TRUE),
            error = function(e) file.copy(file_storage$preview_file$datapath, file, overwrite = TRUE)
          )
        } else {
          # Dosya bulunamazsa uyarı yazdır
          writeLines("File not found", file)
        }
      }
    )

    # Dosya önizleme penceresini açan ana fonksiyon
    open <- function(file_info) {
      tryCatch({
        # Dosya yolunu belirle veya doğrula
        datapath <- file_info$datapath %||% file_info$path %||%
          resolve_uploaded_file(file_info$name, session$userData$user_id)

        # Dosya yolunun geçerliliğini kontrol et
        if (is.null(datapath) || !nzchar(datapath) || !path_exists_relaxed(datapath)) {
          showToast(session,
                    sprintf("Dosya bulunamadı veya erişilemiyor: %s", file_info$name %||% ""),
                    "error")
          return(invisible(NULL))
        }

        # Dosya yolundaki ters eğik çizgileri düzelt
        datapath <- gsub("\\\\", "/", datapath)

        # İndirme işlemi için dosya bilgilerini normalize edilmiş halde sakla
        file_storage$preview_file <- list(
          name     = file_info$name %||% basename(datapath),
          datapath = datapath,
          size     = file_info$size %||% suppressWarnings(file.info(datapath)$size)
        )

        # Dosya uzantısını al
        file_ext   <- tolower(tools::file_ext(file_storage$preview_file$name))

        # Dosya adındaki && ayırıcısını " - " ile değiştir ve başlık stili uygula
        display_name <- gsub("\\s*&&\\s*", " - ", file_storage$preview_file$name)
        modalTitle <- tags$span(
          tags$span("Dosya Önizleme:", style = "color: #a5b4fc; font-weight: 600;"),
          " ",
          tags$span(display_name, style = "color: #e5e7eb; font-weight: 400;")
        )

        # Modal alt bilgi (footer) tasarımı
        footer <- tagList(
          downloadButton(ns("download_preview_file"), "İndir", class = "btn-modern btn-primary"),
          modalButton("Kapat")
        )

        if (file_ext == "pdf") {
          # PDF Dosyaları İçin Önizleme
          # Modal hemen açılsın, src daha sonra ayarlansın
          showModal(modalDialog(
            title = modalTitle,
            tags$iframe(
              id = ns("pdf_iframe"),
              src = "about:blank",
              width = "100%", height = "500px", style = "border: none;"
            ),
            size = "l", easyClose = TRUE, footer = footer
          ))

          # PDF'i arka planda base64'e çevir ve iframe src değerini ayarla
          future::future({
            base64enc::base64encode(datapath)
          }) %...>% (function(b64){
            if (is.character(b64) && length(b64) > 0 && nzchar(b64[1])) {
              shinyjs::runjs(sprintf(
                "var el=document.getElementById('%s'); if(el){ el.src='data:application/pdf;base64,%s'; }",
                ns("pdf_iframe"), b64[1]
              ))
            } else {
              showToast(session, "PDF içeriği hazırlanamadı.", "error")
            }
          }) %...!% (function(e){
            showToast(session, paste("PDF okunamadı:", conditionMessage(e)), "error")
          })

        } else if (file_ext %in% c("xlsx", "xls")) {
          # Excel Dosyaları İçin Önizleme
          err <- NULL
          df <- tryCatch(
            safe_read_excel_table(datapath, n_max = 100),
            error = function(e) { err <<- e$message; NULL }
          )
          if (is.null(df)) {
            showModal(modalDialog(title = modalTitle,
                                  paste("Excel dosyası okunamadı:", err %||% "Bilinmeyen hata"),
                                  footer = footer))
            return()
          }
          preview_data(df)
          showModal(modalDialog(
            title = modalTitle,
            # Yalnız modal gövdesi kayacak; DataTables kendi yatay kaydırmasını yönetir (scrollX=TRUE)
            div(
              class = "excel-preview_container",
              style = "overflow: visible;",
              DT::dataTableOutput(ns("preview_excel_table"))
            ),
            size = "l", easyClose = TRUE, footer = footer
          ))

        } else if (file_ext %in% c("docx")) {
          # Word Dosyaları İçin Önizleme
          # Modal iskeleti (boş hedef; JS mesajı ile doldurulacak)
          showModal(modalDialog(
            title = modalTitle,
            # Tek dikey kaydırma modal gövdesine — iç kapsayıcı kaydırmasız
            tags$head(tags$style(HTML("
              /* Modal gövdesi tek kaydırma alanı olsun */
              .modal-body { max-height: 80vh; overflow-y: auto; }
              /* İçerik kapsayıcısında kaydırma olmasın */
              .modal-body #", ns("docx_preview_container"), " { overflow: visible !important; }
              /* İframe içinde kaydırma kapalı — içeriği iframe yüksekliği kadar göster */
              .modal-body #", ns("docx_preview_container"), " iframe { display:block; width:100%; border:0; overflow:hidden; }
            "))),
            tags$div(
              id = ns("docx_preview_container"),
              style = "overflow: visible; background: white; padding: 20px; border-radius: 8px;",
              HTML("<div style='padding:8px;font-size:12px;opacity:.7'>Yükleniyor…</div>")
            ),
            size = "l", easyClose = TRUE, footer = footer
          ))

          # İçeriği base64 olarak arka planda hazırla; modal hemen açılmış olacak
          future::future({
            base64enc::base64encode(datapath)
          }) %...>% (function(b64){
            if (is.character(b64) && length(b64) > 0 && nzchar(b64[1])) {
              session$sendCustomMessage(
                "openDocxPreview",
                list(base64 = b64, targetId = ns("docx_preview_container"))
              )
            } else {
              showToast(session, "DOCX içeriği hazırlanamadı.", "error")
            }
          }) %...!% (function(e){
            showToast(session, paste("DOCX okunamadı:", conditionMessage(e)), "error")
          })

        } else if (file_ext %in% c("txt", "csv", "json", "log", "md", "r", "py", "js", "html", "css")) {
          # Metin ve Kod Dosyaları İçin Önizleme
          content <- tryCatch(
            readLines(datapath, warn = FALSE, encoding = "UTF-8"),
            error = function(e) readLines(datapath, warn = FALSE)
          )
          # Eğer içerik 1000 satırdan fazlaysa kırp ve bilgi ekle
          if (length(content) > 1000) {
            content <- c(content[1:1000], "...", paste("(", length(content) - 1000, "satır daha)"))
          }
          showModal(modalDialog(
            title = modalTitle,
            div(style = "max-height: 500px; overflow-y: auto;",
                tags$pre(paste(content, collapse = "\n"), class = "file-preview-text")),
            size = "l", easyClose = TRUE, footer = footer
          ))

        } else {
          # Desteklenmeyen Dosya Türleri İçin Uyarı
          showModal(modalDialog(
            title = modalTitle,
            div(class = "unsupported-preview",
                tags$div(style = "text-align: center; padding: 40px;",
                         tags$i(class = "fas fa-file fa-4x", style = "color: #666; margin-bottom: 20px;"),
                         tags$h4("Desteklenmeyen Dosya Türü"),
                         tags$p("Bu dosya türü için önizleme desteklenmiyor."))),
            size = "m", easyClose = TRUE, footer = footer
          ))
        }

      }, error = function(e) {
        # Beklenmeyen bir hata oluştuğunda
        showToast(session, paste("Dosya önizleme hatası:", e$message), "error")
      })
    }

    # Dışarıya açılan (public) API (Kullanılabilir fonksiyonlar)
    list(open = open)
  })
}