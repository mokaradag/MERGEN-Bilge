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

    # Aynı dosya tekrar önizlendiğinde base64 üretimini tekrar yapmamak için önbellek
    preview_b64_cache <- reactiveVal(list())

    # DOCX önizleme modalı için sıra (oturum) belirteci. Büyük DOCX dosyaları
    # asenkron kodlandığı için, kullanıcı A dosyasını açıp kodlama bitmeden
    # B dosyasını açarsa, A'nın geç gelen geri çağrısı sabit hedef kapsayıcıya
    # (docx_preview_container) yazıp B'nin modalına yanlış belge basabilir.
    # Bu belirteç her DOCX modal açılışında artırılır; asenkron geri çağrı
    # yalnızca belirteç hâlâ kendi açılışıyla aynıysa UI mesajını gönderir.
    docx_preview_seq <- reactiveVal(0L)

    # Dosya yolu + boyut + değişiklik zamanına göre önbellek anahtarı üretir
    build_preview_cache_key <- function(path) {
      dp <- if (exists("resolve_readable_path", mode = "function")) {
        resolve_readable_path(path)
      } else {
        path
      }

      finfo <- tryCatch(file.info(dp), error = function(e) NULL)

      size_txt <- if (!is.null(finfo) && !is.na(finfo$size[1])) {
        as.character(finfo$size[1])
      } else {
        "nosize"
      }

      mtime_txt <- if (!is.null(finfo) && !is.na(finfo$mtime[1])) {
        format(finfo$mtime[1], "%Y%m%d%H%M%S")
      } else {
        "nomtime"
      }

      paste(dp, size_txt, mtime_txt, sep = "||")
    }

    # Önbellekten base64 değeri getirir
    get_cached_base64 <- function(path) {
      cache_key <- build_preview_cache_key(path)
      cache <- preview_b64_cache()
      val <- cache[[cache_key]]

      if (is.character(val) && length(val) > 0 && nzchar(val[1])) {
        return(val[1])
      }

      NULL
    }

    # Yeni base64 değerini önbelleğe yazar
    store_cached_base64 <- function(path, b64_value) {
      if (!is.character(b64_value) || length(b64_value) == 0 || !nzchar(b64_value[1])) {
        return(invisible(FALSE))
      }

      cache_key <- build_preview_cache_key(path)
      cache <- preview_b64_cache()
      cache[[cache_key]] <- b64_value[1]
      preview_b64_cache(cache)

      invisible(TRUE)
    }

    # Senkron/asenkron base64 kodlama eşiği (10 MB altı dosyalar senkron işlenir)
    SYNC_B64_THRESHOLD <- 10 * 1024 * 1024

    # 1.5 MB üzeri PDF dosyaları yeni sekmede açılır (base64 data URI yerine doğrudan sunulur)
    PDF_NEWTAB_THRESHOLD <- 1.5 * 1024 * 1024

    # Dosya yolunu çözümleyip base64 kodlayan yardımcı (senkron)
    encode_file_base64_sync <- function(path) {
      dp <- if (exists("resolve_readable_path", mode = "function")) {
        resolve_readable_path(path)
      } else {
        path
      }
      base64enc::base64encode(dp)
    }

    # Excel verilerini DataTables kullanarak render eden çıktı
    output$preview_excel_table <- DT::renderDT({
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
		  resolve_uploaded_file(
			file_info$name,
			user_id = session$userData$user_id
		  )

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
          # PDF dosyaları için önizleme
          fsize <- tryCatch(file.info(datapath)$size, error = function(e) NA_real_)

          if (!is.na(fsize) && fsize > PDF_NEWTAB_THRESHOLD) {
            # --- BÜYÜK PDF (> 1.5 MB): tarayıcının yerel PDF görüntüleyicisinde yeni sekmede aç ---
            # base64 kodlama yerine dosyayı doğrudan Shiny oturumu üzerinden sun
            pdf_obj_name <- paste0("pdf_", gsub("[^a-zA-Z0-9]", "_", basename(datapath)))
            pdf_url <- session$registerDataObj(
              name  = pdf_obj_name,
              data  = list(path = datapath, fname = file_storage$preview_file$name),
              filterFunc = function(data, req) {
                fpath <- data$path
                if (!file.exists(fpath)) {
                  return(shiny::httpResponse(
                    status = 404L,
                    content_type = "text/plain; charset=UTF-8",
                    content = "Dosya bulunamadi"
                  ))
                }
                raw_bytes <- readBin(fpath, "raw", file.info(fpath)$size)
                shiny::httpResponse(
                  status  = 200L,
                  content_type = "application/pdf",
                  headers = list(
                    "Content-Disposition" = paste0('inline; filename="', data$fname, '"')
                  ),
                  content = raw_bytes
                )
              }
            )

            # Bilgi modalı göster (İndir butonu devre dışı — dosya zaten yeni sekmede)
            showModal(modalDialog(
              title = modalTitle,
              div(
                style = "text-align: center; padding: 30px;",
                tags$i(class = "fas fa-external-link-alt fa-3x",
                       style = "color: #a5b4fc; margin-bottom: 15px; display: block;"),
                tags$h4(
                  "PDF yeni sekmede açıldı",
                  style = "color: #e5e7eb;"
                ),
                tags$p(
                  sprintf(
                    "Bu dosya (%.1f MB) boyutu nedeniyle tarayıcınızın PDF görüntüleyicisinde açıldı.",
                    fsize / (1024 * 1024)
                  ),
                  style = "color: #9ca3af; font-size: 14px;"
                ),
                tags$p(
                  tags$a(
                    href = pdf_url, target = "_blank",
                    style = "color: #a5b4fc; text-decoration: underline;",
                    "Sekme açılmadıysa buraya tıklayın"
                  ),
                  style = "margin-top: 10px; font-size: 13px;"
                )
              ),
              size = "m", easyClose = TRUE,
              footer = tagList(
                tags$button(
                  class = "btn btn-modern btn-primary",
                  disabled = "disabled",
                  style = "opacity: 0.5; cursor: not-allowed;",
                  tags$i(class = "fas fa-download"), " İndir"
                ),
                modalButton("Kapat")
              )
            ))

            # Yeni sekmede aç
            shinyjs::runjs(sprintf("window.open(%s, '_blank');",
                                  jsonlite::toJSON(pdf_url, auto_unbox = TRUE)))

          } else {
            # --- KÜÇÜK PDF (< 1.5 MB): iframe + base64 önbellek yaklaşımı ---
            showModal(modalDialog(
              title = modalTitle,
              tags$iframe(
                id = ns("pdf_iframe"),
                src = "about:blank",
                width = "100%",
                height = "500px",
                style = "border: none;"
              ),
              size = "l", easyClose = TRUE, footer = footer
            ))

            # iframe içine PDF verisini yerleştirir
            set_pdf_iframe_src <- function(b64_value) {
              pdf_src <- paste0("data:application/pdf;base64,", b64_value)
              shinyjs::runjs(sprintf(
                "setTimeout(function(){
                   var el = document.getElementById('%s');
                   if (el) { el.src = %s; }
                 }, 50);",
                ns("pdf_iframe"),
                jsonlite::toJSON(pdf_src, auto_unbox = TRUE)
              ))
            }

            cached_pdf <- get_cached_base64(datapath)
            if (!is.null(cached_pdf)) {
              # Önbellekte var; hemen göster
              set_pdf_iframe_src(cached_pdf)
            } else {
              # Küçük dosya: senkron kodlama
              tryCatch({
                b64 <- encode_file_base64_sync(datapath)
                if (is.character(b64) && length(b64) > 0 && nzchar(b64[1])) {
                  store_cached_base64(datapath, b64[1])
                  set_pdf_iframe_src(b64[1])
                } else {
                  showToast(session, "PDF içeriği hazırlanamadı.", "error")
                }
              }, error = function(e) {
                showToast(session, paste("PDF okunamadı:", conditionMessage(e)), "error")
              })
            }
          }

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
              DT::DTOutput(ns("preview_excel_table"))
            ),
            size = "l", easyClose = TRUE, footer = footer
          ))

        } else if (file_ext %in% c("docx")) {
          # Word Dosyaları İçin Önizleme
          # Modal iskeleti (boş hedef; JS mesajı ile doldurulacak)
          showModal(modalDialog(
            title = modalTitle,
            # Tek dikey kaydırma modal gövdesine — iç kapsayıcı kaydırmasız
            tags$head(
              # Mammoth'u modal açılırken doğrudan sayfaya yükle
              # Sürüm eki, tarayıcı önbelleğinde kalmış eski/başarısız yanıtları kırar
              tags$script(
                src = "lib/mammoth/mammoth.browser.min.js?v=20260416",
                id = ns("docx_mammoth_script")
              ),
              tags$style(HTML("
                /* Modal gövdesi tek kaydırma alanı olsun */
                .modal-body { max-height: 80vh; overflow-y: auto; }
                /* İçerik kapsayıcısında kaydırma olmasın */
                .modal-body #", ns("docx_preview_container"), " { overflow: visible !important; }
                /* İframe içinde kaydırma kapalı — içeriği iframe yüksekliği kadar göster */
                .modal-body #", ns("docx_preview_container"), " iframe { display:block; width:100%; border:0; overflow:hidden; }
              "))
            ),
            tags$div(
              id = ns("docx_preview_container"),
              style = "overflow: visible; background: white; padding: 20px; border-radius: 8px;",
              HTML("<div style='padding:8px;font-size:12px;opacity:.7'>Yükleniyor…</div>")
            ),
            size = "l", easyClose = TRUE, footer = footer
          ))

          # Bu DOCX açılışına ait belirteci üret ve yakala. Asenkron yol bu
          # yakalanan değeri, geri çağrı çalıştığında güncel belirteçle
          # karşılaştırarak eski sonucun yeni modalı ezmesini engeller.
          docx_preview_seq(docx_preview_seq() + 1L)
          docx_open_token <- docx_preview_seq()

          # Önbellekten kontrol et; varsa doğrudan göster
          cached_docx <- get_cached_base64(datapath)

          if (!is.null(cached_docx)) {
            # Önbellekte var; hemen mammoth'a gönder
            session$sendCustomMessage(
              "openDocxPreview",
              list(base64 = cached_docx, targetId = ns("docx_preview_container"))
            )
          } else {
            # Dosya boyutuna göre senkron veya asenkron kodla
            fsize <- tryCatch(file.info(datapath)$size, error = function(e) NA_real_)

            if (!is.na(fsize) && fsize <= SYNC_B64_THRESHOLD) {
              # Küçük dosya: senkron kodlama (future işçi başlatma yükünden kaçınır)
              tryCatch({
                b64 <- encode_file_base64_sync(datapath)
                if (is.character(b64) && length(b64) > 0 && nzchar(b64[1])) {
                  store_cached_base64(datapath, b64[1])
                  session$sendCustomMessage(
                    "openDocxPreview",
                    list(base64 = b64, targetId = ns("docx_preview_container"))
                  )
                } else {
                  showToast(session, "DOCX içeriği hazırlanamadı.", "error")
                }
              }, error = function(e) {
                showToast(session, paste("DOCX okunamadı:", conditionMessage(e)), "error")
              })
            } else {
              # Büyük dosya (>10 MB): asenkron kodlama
              future::future({
                encode_file_base64_sync(datapath)
              }) %...>% (function(b64){
                # Eski açılışın geç gelen sonucu, daha yeni bir DOCX modalını
                # ezmemeli. Belirteç değiştiyse bu sonucu sessizce yok say
                # (yalnızca önbelleğe yazılır, UI'a basılmaz).
                if (!identical(isolate(docx_preview_seq()), docx_open_token)) {
                  if (is.character(b64) && length(b64) > 0 && nzchar(b64[1])) {
                    store_cached_base64(datapath, b64[1])
                  }
                  return(invisible(NULL))
                }
                if (is.character(b64) && length(b64) > 0 && nzchar(b64[1])) {
                  store_cached_base64(datapath, b64[1])
                  session$sendCustomMessage(
                    "openDocxPreview",
                    list(base64 = b64, targetId = ns("docx_preview_container"))
                  )
                } else {
                  showToast(session, "DOCX içeriği hazırlanamadı.", "error")
                }
              }) %...!% (function(e){
                # Hata mesajını da yalnızca bu açılış hâlâ güncelse göster.
                if (!identical(isolate(docx_preview_seq()), docx_open_token)) {
                  return(invisible(NULL))
                }
                showToast(session, paste("DOCX okunamadı:", conditionMessage(e)), "error")
              })
            }
          }

        } else if (file_ext %in% c("txt", "csv", "json", "log", "md", "r", "py", "js", "html", "css")) {
          # Metin ve Kod Dosyaları İçin Önizleme.
          # Bilge Yolaç tarafından üretilen dosya_aciklamalari.txt gibi dosyalar
          # UTF-8 BOM ile yazılır. readLines bazı Windows yerel ayarlarında BOM
          # ve karışık satır sonları yüzünden boş içerik döndürebilir. Bu yüzden
          # önce ham baytları oku, BOM'u kaldır ve UTF-8'e güvenli şekilde çevir.
          raw_bytes <- tryCatch({
            finfo <- file.info(datapath)
            if (!is.null(finfo) && !is.na(finfo$size[1])) {
              readBin(datapath, what = "raw", n = as.integer(finfo$size[1]))
            } else {
              readBin(datapath, what = "raw", n = .Machine$integer.max)
            }
          }, error = function(e) raw(0))

          # UTF-8 BOM (EF BB BF) varsa kaldır
          if (length(raw_bytes) >= 3 &&
              identical(raw_bytes[1], as.raw(0xEF)) &&
              identical(raw_bytes[2], as.raw(0xBB)) &&
              identical(raw_bytes[3], as.raw(0xBF))) {
            raw_bytes <- raw_bytes[-(1:3)]
          }

          # NUL baytları rawToChar'ı kırdığı için temizle (metin dosyalarında
          # beklenmez; varsa kullanıcının okunabilirliğini bozmadan filtrele).
          raw_bytes <- raw_bytes[raw_bytes != as.raw(0L)]

          full_text <- tryCatch({
            txt <- rawToChar(raw_bytes)
            Encoding(txt) <- "UTF-8"
            valid_utf8 <- !is.na(iconv(txt, from = "UTF-8", to = "UTF-8"))
            if (isTRUE(valid_utf8)) {
              txt
            } else {
              # Yerel kodlamadan UTF-8'e çevir (Windows-1254 vb.). Bilinmeyen
              # baytları işarete dönüştür.
              iconv(
                rawToChar(raw_bytes),
                from = "",
                to = "UTF-8",
                sub = "byte"
              )
            }
          }, error = function(e) {
            tryCatch(
              iconv(
                rawToChar(raw_bytes),
                from = "",
                to = "UTF-8",
                sub = "byte"
              ),
              error = function(e2) ""
            )
          })

          content <- if (nzchar(full_text)) {
            strsplit(full_text, "\r\n|\r|\n", perl = TRUE)[[1]]
          } else {
            character(0)
          }

          # Eğer içerik 1000 satırdan fazlaysa kırp ve bilgi ekle
          if (length(content) > 1000) {
            content <- c(content[1:1000], "...", paste("(", length(content) - 1000, "satır daha)"))
          }

          preview_body <- if (length(content) > 0) {
            tags$pre(paste(content, collapse = "\n"), class = "file-preview-text")
          } else {
            tags$div(
              class = "file-preview-empty",
              style = "text-align:center; padding: 30px; color:#9ca3af;",
              tags$i(class = "fas fa-file-alt fa-2x", style = "margin-bottom:10px; display:block;"),
              tags$p("Dosya içeriği boş veya görüntülenemiyor.")
            )
          }

          showModal(modalDialog(
            title = modalTitle,
            div(style = "max-height: 500px; overflow-y: auto;", preview_body),
            size = "l", easyClose = TRUE, footer = footer
          ))

        } else if (file_ext %in% c("jpg", "jpeg", "png", "gif", "webp", "bmp", "svg")) {
          # Görsel dosyalar için önizleme: dosya doğrudan Shiny oturumu üzerinden
          # sunulur (base64 şişmesi olmadan) ve modalda <img> ile gösterilir.
          # Aynı registerDataObj deseni büyük PDF önizlemesinde de kullanılıyor.
          img_content_type <- switch(
            file_ext,
            "jpg" = , "jpeg" = "image/jpeg",
            "png"  = "image/png",
            "gif"  = "image/gif",
            "webp" = "image/webp",
            "bmp"  = "image/bmp",
            "svg"  = "image/svg+xml",
            "application/octet-stream"
          )
          img_obj_name <- paste0("img_", gsub("[^a-zA-Z0-9]", "_", basename(datapath)))
          img_url <- session$registerDataObj(
            name = img_obj_name,
            data = list(path = datapath, ctype = img_content_type),
            filterFunc = function(data, req) {
              fpath <- data$path
              if (!file.exists(fpath)) {
                return(shiny::httpResponse(
                  status = 404L,
                  content_type = "text/plain; charset=UTF-8",
                  content = "Dosya bulunamadi"
                ))
              }
              raw_bytes <- readBin(fpath, "raw", file.info(fpath)$size)
              shiny::httpResponse(
                status = 200L,
                content_type = data$ctype,
                content = raw_bytes
              )
            }
          )

          showModal(modalDialog(
            title = modalTitle,
            div(
              style = "text-align: center; max-height: 520px; overflow: auto;",
              tags$img(
                src = img_url,
                alt = display_name,
                style = "max-width: 100%; max-height: 500px; height: auto; border-radius: 8px;"
              )
            ),
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