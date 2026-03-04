# Dosya Yolu: R/module_destek_hata_bildir.R
# Açıklama: Hata Bildirimi alt modülü.
#            Hata konuları, kategoriler, öncelik seviyesi, açıklama ve
#            dosya ekleri (ekler) yönetimini sağlar.

# ==============================================================================
# HATA BİLDİR UI
# ==============================================================================

destekHataBildirUI <- function(id) {
  ns <- NS(id)
  tagList(
    div(
      class = "destek-form-card",

      # Konu (Zorunlu - Çoklu giriş) - Dinamik etiket JS ile güncellenir
      div(
        class = "destek-form-group",
        tags$label(
          class = "destek-form-label destek-label-required",
          id = ns("konu_label"),
          "Konu"
        ),
        div(
          id = ns("konular_container"),
          class = "destek-konular-container",
          # İlk konu girişi
          div(
            class = "destek-konu-row",
            `data-index` = "1",
            tags$input(
              type = "text",
              class = "destek-text-input destek-konu-input",
              id = ns("konu_1"),
              placeholder = "Örn: Profil resmi yüklenmiyor",
              maxlength = "200",
              oninput = sprintf("destekCollectKonular('%s')", ns(""))
            )
          )
        ),
        # Yeni konu ekleme butonu
        div(
          class = "destek-add-btn-wrapper",
          tags$button(
            id = ns("konu_ekle_btn"),
            class = "destek-add-btn",
            type = "button",
            onclick = sprintf("destekAddKonu('%s')", ns("")),
            icon("plus"),
            "Konu Ekle"
          )
        ),
        div(id = ns("hata_konular"), class = "destek-error-msg", style = "display:none;",
          icon("circle-exclamation"),
          "Lütfen en az bir konu girin."
        )
      ),

      # Kategori (Zorunlu - Çoklu seçim) - Animasyonlu ikonlar
      div(
        class = "destek-form-group",
        tags$label(
          class = "destek-form-label destek-label-required",
          "Kategori"
        ),
        div(
          class = "destek-category-container",
          id = ns("kategori_container"),
          lapply(list(
            list(id = "arayuz", label = "Arayüz / Tasarım", icon = "palette", renk = "purple"),
            list(id = "fonksiyonellik", label = "Fonksiyonellik", icon = "wrench", renk = "blue"),
            list(id = "performans", label = "Performans", icon = "bolt", renk = "amber"),
            list(id = "cokme", label = "Çökme / Hata", icon = "triangle-exclamation", renk = "red"),
            list(id = "diger", label = "Diğer", icon = "ellipsis", renk = "cyan")
          ), function(kat) {
            div(
              class = paste0("destek-category-btn destek-cat-", kat$renk),
              `data-category` = kat$id,
              onclick = sprintf(
                "destekToggleCategory(this, '%s')",
                ns("secili_kategoriler")
              ),
              div(class = paste0("destek-cat-icon-wrapper destek-cat-icon-", kat$renk),
                icon(kat$icon)
              ),
              span(kat$label)
            )
          })
        ),
        tags$input(
          type = "hidden",
          id = ns("secili_kategoriler"),
          name = ns("secili_kategoriler"),
          value = ""
        ),
        div(id = ns("hata_kategoriler"), class = "destek-error-msg", style = "display:none;",
          icon("circle-exclamation"),
          "Lütfen en az bir kategori seçin."
        )
      ),

      # Öncelik Seviyesi (Opsiyonel - seçim iptal edilebilir)
      div(
        class = "destek-form-group",
        tags$label(class = "destek-form-label", "Öncelik Seviyesi"),
        div(
          class = "destek-priority-container",
          id = ns("oncelik_container"),
          lapply(list(
            list(id = "dusuk", label = "Düşük", renk = "blue"),
            list(id = "orta", label = "Orta", renk = "amber"),
            list(id = "yuksek", label = "Yüksek", renk = "orange"),
            list(id = "kritik", label = "Kritik", renk = "red")
          ), function(onc) {
            div(
              class = "destek-priority-btn",
              `data-priority` = onc$id,
              onclick = sprintf(
                "destekSelectPriority(this, '%s')",
                ns("secili_oncelik")
              ),
              span(class = paste0("destek-priority-dot destek-dot-", onc$renk)),
              span(onc$label)
            )
          })
        ),
        tags$input(
          type = "hidden",
          id = ns("secili_oncelik"),
          name = ns("secili_oncelik"),
          value = ""
        )
      ),

      # Açıklama & Yeniden Üretme Adımları (Zorunlu)
      div(
        class = "destek-form-group",
        tags$label(
          class = "destek-form-label destek-label-required",
          "Açıklama & Yeniden Üretme Adımları"
        ),
        div(
          class = "destek-textarea-wrapper",
          tags$textarea(
            id = ns("hata_aciklama"),
            class = "destek-textarea destek-textarea-lg",
            placeholder = "Sorunu nasıl yaşadığınızı adım adım anlatın...",
            maxlength = "500",
            rows = 6,
            oninput = sprintf("destekUpdateCharCount(this, '%s')", ns("aciklama_counter"))
          ),
          span(id = ns("aciklama_counter"), class = "destek-char-counter", "0 / 500")
        ),
        div(id = ns("hata_aciklama_msg"), class = "destek-error-msg", style = "display:none;",
          icon("circle-exclamation"),
          "Lütfen açıklama alanını doldurun."
        )
      ),

      # Ekler (Opsiyonel - Sürükle-Bırak)
      div(
        class = "destek-form-group",
        tags$label(class = "destek-form-label", "Ekler"),
        div(
          id = ns("upload_zone"),
          class = "destek-upload-zone",
          ondragover = "event.preventDefault(); this.classList.add('destek-drag-over');",
          ondragleave = "this.classList.remove('destek-drag-over');",
          ondrop = sprintf("destekHandleDrop(event, '%s')", ns("")),
          onclick = sprintf("document.getElementById('%s').click();", ns("dosya_input")),
          div(class = "destek-upload-content",
            icon("cloud-arrow-up", class = "destek-upload-icon"),
            p(class = "destek-upload-text",
              "Dosyaları sürükleyin veya ",
              tags$span(class = "destek-upload-link", "göz atın")
            ),
            p(class = "destek-upload-hint",
              "PNG, JPG, GIF, MP4 \u2022 Maks. 10MB")
          )
        ),
        # Gizli dosya girişi
        tags$input(
          type = "file",
          id = ns("dosya_input"),
          style = "display:none;",
          multiple = "multiple",
          accept = "image/png,image/jpeg,image/gif,video/mp4"
        ),
        # Yüklenen dosya listesi
        div(
          id = ns("dosya_listesi"),
          class = "destek-file-list"
        )
      ),

      # Gönder butonu
      div(
        class = "destek-form-actions",
        div(
          class = "destek-submit-wrapper",
          actionButton(
            ns("gonder_hata"),
            label = tagList(icon("paper-plane"), "Gönder"),
            class = "destek-submit-btn",
            title = "Ctrl + Enter ile gönder"
          )
        )
      )
    )
  )
}

# ==============================================================================
# HATA BİLDİR SERVER
# ==============================================================================

destekHataBildirServer <- function(id, current_user_id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Yüklenen dosyaları takip et
    yuklenen_dosyalar <- reactiveVal(list())

    # Başarılı gönderim sinyali
    basarili_trigger <- reactiveVal(0)

    # Dosya yükleme gözlemcisi (JS tarafından tetiklenir)
    observeEvent(input$dosya_bilgisi, {
      dosya_verisi <- input$dosya_bilgisi
      if (is.null(dosya_verisi)) return()

      mevcut <- yuklenen_dosyalar()

      # Dosya boyutu kontrolü (10MB)
      if (!is.null(dosya_verisi$size) && dosya_verisi$size > 10 * 1024 * 1024) {
        showToast(session, "Dosya boyutu 10MB'dan büyük olamaz.", "error")
        return()
      }

      mevcut[[length(mevcut) + 1]] <- dosya_verisi
      yuklenen_dosyalar(mevcut)
    }, ignoreInit = TRUE)

    # Dosya silme gözlemcisi
    observeEvent(input$dosya_sil, {
      idx <- as.integer(input$dosya_sil)
      if (is.null(idx) || is.na(idx)) return()

      mevcut <- yuklenen_dosyalar()
      if (idx >= 1 && idx <= length(mevcut)) {
        # Fiziksel dosyayı da sil
        if (!is.null(mevcut[[idx]]$path) && file.exists(mevcut[[idx]]$path)) {
          file.remove(mevcut[[idx]]$path)
        }
        mevcut[[idx]] <- NULL
        yuklenen_dosyalar(mevcut)
        # Dosya listesini JS ile güncelle
        shinyjs::runjs(sprintf(
          "destekUpdateFileList('%s', %s);",
          ns(""),
          jsonlite::toJSON(lapply(mevcut, function(d) {
            list(name = d$name, size = d$size)
          }), auto_unbox = TRUE)
        ))
      }
    }, ignoreInit = TRUE)

    # Shiny file input ile dosya yükleme
    observeEvent(input$dosya_input, {
      dosyalar <- input$dosya_input
      if (is.null(dosyalar)) return()

      # datapath, name, size, type alanlarını işle
      if (is.data.frame(dosyalar)) {
        for (i in seq_len(nrow(dosyalar))) {
          dosya <- dosyalar[i, ]
          if (dosya$size > 10 * 1024 * 1024) {
            showToast(session, paste0(dosya$name, " dosyası 10MB sınırını aşıyor."), "error")
            next
          }

          # Dosyayı destek_uploads klasörüne kopyala
          hedef_dir <- file.path("destek_uploads", as.character(current_user_id))
          if (!dir.exists(hedef_dir)) dir.create(hedef_dir, recursive = TRUE)
          hedef_yol <- file.path(hedef_dir, paste0(
            format(Sys.time(), "%Y%m%d%H%M%S"), "_", dosya$name
          ))
          file.copy(dosya$datapath, hedef_yol)

          mevcut <- yuklenen_dosyalar()
          mevcut[[length(mevcut) + 1]] <- list(
            name = dosya$name,
            size = dosya$size,
            path = hedef_yol
          )
          yuklenen_dosyalar(mevcut)
        }

        # Dosya listesini JS ile güncelle
        mevcut <- yuklenen_dosyalar()
        shinyjs::runjs(sprintf(
          "destekUpdateFileList('%s', %s);",
          ns(""),
          jsonlite::toJSON(lapply(mevcut, function(d) {
            list(name = d$name, size = d$size)
          }), auto_unbox = TRUE)
        ))
      }
    }, ignoreInit = TRUE)

    # Hata bildirimi formu gönderimi
    observeEvent(input$gonder_hata, {
      hatalar <- FALSE

      # Konuları topla (JS oninput ile sürekli güncelleniyor)
      konular_text <- input$konular_birlesik
      if (is.null(konular_text) || !nzchar(trimws(konular_text %||% ""))) {
        shinyjs::show("hata_konular")
        hatalar <- TRUE
      } else {
        shinyjs::hide("hata_konular")
      }

      # Kategorileri kontrol et
      kategoriler <- input$secili_kategoriler
      if (is.null(kategoriler) || kategoriler == "") {
        shinyjs::show("hata_kategoriler")
        hatalar <- TRUE
      } else {
        shinyjs::hide("hata_kategoriler")
      }

      # Açıklama kontrol et
      aciklama <- input$hata_aciklama
      if (is.null(aciklama) || !nzchar(trimws(aciklama %||% ""))) {
        shinyjs::show("hata_aciklama_msg")
        hatalar <- TRUE
      } else {
        shinyjs::hide("hata_aciklama_msg")
      }

      if (hatalar) return(invisible(NULL))

      # Ek dosya yollarını topla
      dosyalar <- yuklenen_dosyalar()
      ek_yollari <- if (length(dosyalar) > 0) {
        paste(sapply(dosyalar, function(d) d$path %||% ""), collapse = ",")
      } else {
        NULL
      }

      # Veritabanına kaydet
      tryCatch({
        destek_hata_bildir_kaydet(
          user_id = current_user_id,
          konular = konular_text,
          kategoriler = kategoriler,
          oncelik = if (!is.null(input$secili_oncelik) && nzchar(input$secili_oncelik)) input$secili_oncelik else "belirtilmedi",
          aciklama = aciklama,
          ek_dosya_yollari = ek_yollari
        )

        # Formu sıfırla
        yuklenen_dosyalar(list())
        shinyjs::runjs(sprintf("destekResetBugForm('%s');", ns("")))

        # Başarı sinyali gönder
        basarili_trigger(basarili_trigger() + 1)

      }, error = function(e) {
        cat("[DESTEK] Hata bildirimi kaydedilemedi:", conditionMessage(e), "\n")
        showToast(session, "Hata bildirimi kaydedilemedi. Lütfen tekrar deneyin.", "error")
      })
    })

    # Dışa döndürülecek değerler
    return(list(
      basarili = reactive(basarili_trigger())
    ))
  })
}
