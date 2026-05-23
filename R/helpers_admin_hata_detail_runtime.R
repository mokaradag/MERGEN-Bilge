# ==============================================================================
# Dosya Yolu: R/helpers_admin_hata_detail_runtime.R
# Açıklama: Yönetici Hata Analizi detay tablosu, ek dosya önizleme ve
#           durum güncelleme runtime yardımcıları.
#           Grafikler ve sekme UI yönlendirmesi module_admin_hata_analizi.R
#           içinde kalmaz; detay runtime sorumluluğu burada sınırlandırılır.
# ==============================================================================

admin_ha_badge_text_color <- function(bg_hex) {
  rgb_vals <- col2rgb(bg_hex)
  parlaklik <- (0.299 * rgb_vals[1] + 0.587 * rgb_vals[2] + 0.114 * rgb_vals[3]) / 255
  if (parlaklik > 0.55) "#1a1a1a" else "#ffffff"
}

admin_ha_badge_html <- function(value, colors, labels) {
  renk <- if (value %in% names(colors)) colors[[value]] else "#94a3b8"
  metin_renk <- admin_ha_badge_text_color(renk)
  label <- ifelse(value %in% names(labels), labels[[value]], value)

  sprintf(
    '<span style="background:%s; color:%s; padding:2px 8px; border-radius:4px; font-size:11px; font-weight:600;">%s</span>',
    renk,
    metin_renk,
    label
  )
}

admin_ha_prepare_detail_table_data <- function(data,
                                               ns,
                                               kategori_cevirisi,
                                               oncelik_cevirisi,
                                               durum_cevirisi) {
  if (is.null(data) || !is.data.frame(data) || nrow(data) == 0) {
    return(data.frame())
  }

  oncelik_renkler <- c(
    "dusuk" = "#3b82f6",
    "orta" = "#f59e0b",
    "yuksek" = "#f97316",
    "kritik" = "#ef4444"
  )

  durum_renkler <- c(
    "acik" = "#f59e0b",
    "inceleme" = "#3b82f6",
    "cozuldu" = "#10b981",
    "kapandi" = "#64748b",
    "reddedildi" = "#ef4444"
  )

  data$row_num <- seq_len(nrow(data))

  data$oncelik_display <- vapply(
    data$Oncelik,
    admin_ha_badge_html,
    character(1),
    colors = oncelik_renkler,
    labels = oncelik_cevirisi
  )

  data$durum_display <- vapply(
    data$Durum,
    admin_ha_badge_html,
    character(1),
    colors = durum_renkler,
    labels = durum_cevirisi
  )

  data$tarih <- format(as.POSIXct(data$OlusturmaTarihi), "%d.%m.%Y %H:%M")
  data$tarih_sort <- as.numeric(as.POSIXct(data$OlusturmaTarihi))
  data$kullanici <- ifelse(
    !is.na(data$KullaniciAdi) & nzchar(data$KullaniciAdi),
    data$KullaniciAdi,
    "-"
  )
  data$konular_display <- ifelse(nzchar(data$Konular), data$Konular, "-")

  data$kategori_display <- vapply(data$Kategoriler, function(k) {
    if (is.na(k) || !nzchar(k)) {
      return("-")
    }

    parcalar <- trimws(strsplit(k, ",")[[1]])
    paste(
      ifelse(parcalar %in% names(kategori_cevirisi), kategori_cevirisi[parcalar], parcalar),
      collapse = ", "
    )
  }, character(1))

  data$aciklama_display <- ifelse(
    nchar(data$Aciklama) > 100,
    paste0(substr(data$Aciklama, 1, 100), "..."),
    data$Aciklama
  )

  data$dosya_display <- vapply(seq_len(nrow(data)), function(i) {
    if (!is.na(data$EkDosyaYollari[i]) && nzchar(data$EkDosyaYollari[i])) {
      dosya_sayisi <- length(strsplit(data$EkDosyaYollari[i], ",")[[1]])
      sprintf(
        '<a href="#" onclick="Shiny.setInputValue(\'%s\', %d, {priority: \'event\'}); return false;" style="color: #06b6d4; text-decoration: underline;">%d dosya</a>',
        ns("dosya_goster"),
        data$HataBildirimID[i],
        dosya_sayisi
      )
    } else {
      "-"
    }
  }, character(1))

  data$islem_display <- vapply(seq_len(nrow(data)), function(i) {
    sprintf(
      '<a href="#" onclick="Shiny.setInputValue(\'%s\', %d, {priority: \'event\'}); return false;" style="color: #f59e0b;" title="Durum güncelle"><i class="fas fa-edit"></i></a>',
      ns("durum_guncelle"),
      data$HataBildirimID[i]
    )
  }, character(1))

  display_data <- data[, c(
    "row_num",
    "kullanici",
    "konular_display",
    "kategori_display",
    "oncelik_display",
    "durum_display",
    "aciklama_display",
    "dosya_display",
    "islem_display",
    "tarih",
    "tarih_sort"
  )]

  colnames(display_data) <- c(
    "#",
    "Kullanıcı",
    "Konular",
    "Kategori",
    "Öncelik",
    "Durum",
    "Açıklama",
    "Dosyalar",
    "İşlem",
    "Tarih",
    "tarih_sort"
  )

  display_data
}

admin_ha_detail_datatable <- function(display_data) {
  if (is.null(display_data) || !is.data.frame(display_data) || nrow(display_data) == 0) {
    return(DT::datatable(data.frame()))
  }

  DT::datatable(
    display_data,
    escape = FALSE,
    options = list(
      dom = "frtip",
      pageLength = 15,
      ordering = TRUE,
      order = list(list(9, "desc")),
      language = admin_turkish_dt_language,
      columnDefs = list(
        list(className = "dt-center", targets = c(0, 4, 5, 7, 8, 9)),
        list(className = "row-number-col", targets = 0),
        list(width = "40px", targets = 0),
        list(width = "120px", targets = c(4, 5)),
        list(width = "60px", targets = 8),
        list(orderable = FALSE, targets = c(0, 7, 8)),
        list(orderData = 10, targets = 9),
        list(visible = FALSE, targets = 10)
      ),
      headerCallback = admin_dt_header_callback
    ),
    class = "admin-datatable",
    rownames = FALSE
  )
}

admin_ha_attachment_download_button <- function(gorsel_yol, dosya_adi) {
  shiny::tags$a(
    href = gorsel_yol,
    download = dosya_adi,
    target = "_blank",
    class = "btn btn-sm",
    style = paste(
      "display: inline-flex; align-items: center; gap: 6px;",
      "margin-top: 10px; padding: 6px 16px;",
      "background: linear-gradient(135deg, #06b6d4, #3b82f6);",
      "color: #fff; border: none; border-radius: 8px;",
      "font-size: 12px; font-weight: 600; text-decoration: none;",
      "transition: all 0.3s ease;"
    ),
    shiny::icon("download"),
    dosya_adi
  )
}

admin_ha_attachment_public_path <- function(dosya_yolu) {
  if (grepl("^destek_uploads/", dosya_yolu)) {
    paste0("/", dosya_yolu)
  } else {
    paste0("/destek_uploads/", dosya_yolu)
  }
}

admin_ha_attachment_item <- function(dosya_yolu) {
  uzanti <- tolower(tools::file_ext(dosya_yolu))
  dosya_adi <- basename(dosya_yolu)
  gorsel_yol <- admin_ha_attachment_public_path(dosya_yolu)
  indir_btn <- admin_ha_attachment_download_button(gorsel_yol, dosya_adi)

  header <- shiny::div(
    style = "display: flex; align-items: center; justify-content: space-between; margin-bottom: 10px;",
    shiny::h5(
      shiny::icon(if (uzanti %in% c("png", "jpg", "jpeg", "gif")) "image" else if (uzanti == "mp4") "video" else "file"),
      " ",
      dosya_adi,
      style = "color: #ccc; margin: 0;"
    ),
    indir_btn
  )

  if (uzanti %in% c("png", "jpg", "jpeg", "gif")) {
    return(shiny::div(
      class = "admin-attachment-item",
      header,
      shiny::div(
        class = "admin-attachment-zoom-container",
        style = "position: relative; overflow: hidden; border-radius: 8px; border: 1px solid #333; cursor: zoom-in;",
        onclick = "this.classList.toggle('zoomed'); this.style.cursor = this.classList.contains('zoomed') ? 'zoom-out' : 'zoom-in';",
        shiny::tags$img(
          src = gorsel_yol,
          style = "width: 100%; max-height: 70vh; object-fit: contain; border-radius: 8px; transition: transform 0.3s ease;",
          alt = dosya_adi
        )
      )
    ))
  }

  if (identical(uzanti, "mp4")) {
    return(shiny::div(
      class = "admin-attachment-item",
      header,
      shiny::tags$video(
        src = gorsel_yol,
        controls = "controls",
        style = "width: 100%; max-height: 70vh; border-radius: 8px; background: #000;",
        type = "video/mp4"
      )
    ))
  }

  shiny::div(
    class = "admin-attachment-item",
    header,
    shiny::p(style = "color: #999;", "Bu dosya türü önizlenemez.")
  )
}

admin_ha_attachment_content <- function(dosyalar) {
  dosya_elements <- lapply(dosyalar, admin_ha_attachment_item)
  do.call(shiny::tagList, dosya_elements)
}

admin_ha_show_modal <- function(ns, modal_id) {
  shinyjs::runjs(sprintf("
    var modal = $('#%s');
    if (!modal.data('moved-to-body')) {
      modal.appendTo('body');
      modal.data('moved-to-body', true);
    }
    modal.modal('show');
  ", ns(modal_id)))
}

admin_ha_register_detail_runtime <- function(input,
                                             output,
                                             session,
                                             ha_data,
                                             refresh,
                                             kategori_cevirisi,
                                             oncelik_cevirisi,
                                             durum_cevirisi) {
  ns <- session$ns

  output$ha_detay_tablo <- DT::renderDT({
    data <- ha_data()$tumu
    display_data <- admin_ha_prepare_detail_table_data(
      data = data,
      ns = ns,
      kategori_cevirisi = kategori_cevirisi,
      oncelik_cevirisi = oncelik_cevirisi,
      durum_cevirisi = durum_cevirisi
    )

    admin_ha_detail_datatable(display_data)
  })

  observeEvent(input$dosya_goster, {
    bildirim_id <- input$dosya_goster
    data <- ha_data()$tumu
    bildirim <- data[data$HataBildirimID == bildirim_id, ]

    if (nrow(bildirim) == 0) return()

    dosya_yollari <- bildirim$EkDosyaYollari[1]
    if (is.na(dosya_yollari) || !nzchar(dosya_yollari)) return()

    dosyalar <- trimws(strsplit(dosya_yollari, ",")[[1]])

    output$ek_dosya_content <- renderUI({
      admin_ha_attachment_content(dosyalar)
    })

    admin_ha_show_modal(ns, "ek_dosya_modal")
  })

  observeEvent(input$durum_guncelle, {
    bildirim_id <- input$durum_guncelle
    data <- ha_data()$tumu
    bildirim <- data[data$HataBildirimID == bildirim_id, ]

    if (nrow(bildirim) == 0) return()

    mevcut_durum <- bildirim$Durum[1]
    updateSelectInput(session, "yeni_durum", selected = mevcut_durum)

    shinyjs::runjs(sprintf(
      "$('#%s').val(%d);",
      ns("durum_bildirim_id"),
      bildirim_id
    ))

    admin_ha_show_modal(ns, "durum_modal")
  })

  observeEvent(input$durum_kaydet, {
    shinyjs::runjs(sprintf(
      "Shiny.setInputValue('%s', parseInt($('#%s').val()), {priority: 'event'});",
      ns("durum_bildirim_id_val"),
      ns("durum_bildirim_id")
    ))
  })

  observeEvent(input$durum_bildirim_id_val, {
    req(input$durum_bildirim_id_val)

    bildirim_id <- as.integer(input$durum_bildirim_id_val)
    yeni_durum <- input$yeni_durum

    tryCatch({
      destek_hata_durum_guncelle(bildirim_id, yeni_durum)
      showToast(session, "Durum başarıyla güncellendi", "success")
      refresh$trigger(refresh$trigger() + 1)
      shinyjs::runjs(sprintf(
        "$('#%s').modal('hide'); $('.modal-backdrop').remove();",
        ns("durum_modal")
      ))
    }, error = function(e) {
      showToast(session, paste("Hata:", conditionMessage(e)), "error")
    })
  })

  invisible(TRUE)
}