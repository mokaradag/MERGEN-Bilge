# ==============================================================================
# Dosya Yolu: R/helpers_file_manager_table.R
# Açıklama: Dosya Yönetimi tablo şeması ve satır HTML yardımcıları.
# ==============================================================================

fm_empty_files_df <- function() {
  data.frame(
    Dosya_Adi = character(0),
    Boyut = character(0),
    Tur = character(0),
    Yuklenme_Tarihi = character(0),
    Islemler = character(0),
    Model_Baglam = character(0),
    stringsAsFactors = FALSE
  )
}

fm_clean_file_display_name <- function(file_name, file_info = NULL) {
  normalized_info <- if (is.list(file_info)) file_info else list()
  normalized_info$name <- file_name

  normalized <- fm_normalize_uploaded_file_info(normalized_info)

  normalized$file_name
}

fm_normalize_uploaded_file_info <- function(file_info) {
  normalized_info <- file_info %||% list()
  raw_file_name <- as.character(normalized_info$name %||% "")[1]

  if (is.na(raw_file_name)) {
    raw_file_name <- ""
  }

  file_name <- raw_file_name

  if (exists("normalize_file_display_name", mode = "function", inherits = TRUE)) {
    file_name <- tryCatch(
      normalize_file_display_name(raw_file_name, file_info = normalized_info),
      error = function(e) raw_file_name
    )
  } else if (exists("recover_display_name_from_storage_name", mode = "function", inherits = TRUE)) {
    file_name <- tryCatch(
      recover_display_name_from_storage_name(raw_file_name),
      error = function(e) raw_file_name
    )
  }

  file_name <- as.character(file_name %||% "")[1]
  if (is.na(file_name)) {
    file_name <- ""
  }

  if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    file_name <- normalize_text_utf8(file_name, repair_mojibake = TRUE)
  } else {
    file_name <- enc2utf8(file_name)
  }

  if (nzchar(file_name)) {
    normalized_info$name <- file_name
  }

  list(
    file_info = normalized_info,
    file_name = file_name
  )
}

fm_build_file_actions_html <- function(file_id, ns) {
  hidden_dl <- as.character(
    htmltools::tags$span(
      style = "display:none;",
      shiny::downloadLink(outputId = ns(paste0("download_", file_id)), label = "")
    )
  )

  as.character(htmltools::tags$div(
    class = "file-actions",
    htmltools::tags$button(
      class = "file-action-btn file-view js-file-action",
      title = "Görüntüle",
      `data-action` = "view",
      `data-file-id` = file_id,
      shiny::icon("eye")
    ),
    htmltools::tags$button(
      class = "file-action-btn file-download js-download-btn",
      title = "İndir",
      `data-download-id` = file_id,
      shiny::icon("download")
    ),
    htmltools::tags$button(
      class = "file-action-btn file-delete js-file-action",
      title = "Sil",
      `data-action` = "delete",
      `data-file-id` = file_id,
      shiny::icon("trash")
    ),
    htmltools::HTML(hidden_dl)
  ))
}

fm_build_attach_cell_html <- function(file_id, file_name, ns) {
  as.character(htmltools::tags$div(
    class = "attach-cell",
    htmltools::tags$input(
      id = ns(paste0("attach_", file_id)),
      type = "checkbox",
      class = "attach-checkbox",
      `data-file-id` = file_id,
      `data-filename` = file_name,
      title = "Bu dosyayı model bağlamına ekle/çıkar",
      `aria-label` = "Model bağlamına ekle veya çıkar"
    )
  ))
}

# Desteklenmeyen (ör. ajan tarafından üretilmiş .doc) ama kullanıcının kalıcı
# klasöründe FİZİKSEL olarak var olan dosyalar için sınırlı işlem seti:
# yalnızca indirme ve silme. Önizleme/özetleme/model bağlamı sunulmaz; dosya
# içeriği hiçbir zaman ayrıştırılmaz.
fm_build_unsupported_file_actions_html <- function(file_id, ns) {
  hidden_dl <- as.character(
    htmltools::tags$span(
      style = "display:none;",
      shiny::downloadLink(outputId = ns(paste0("download_", file_id)), label = "")
    )
  )

  as.character(htmltools::tags$div(
    class = "file-actions",
    htmltools::tags$button(
      class = "file-action-btn file-download js-download-btn",
      title = "İndir",
      `data-download-id` = file_id,
      shiny::icon("download")
    ),
    htmltools::tags$button(
      class = "file-action-btn file-delete js-file-action",
      title = "Sil",
      `data-action` = "delete",
      `data-file-id` = file_id,
      shiny::icon("trash")
    ),
    htmltools::HTML(hidden_dl)
  ))
}

# Desteklenmeyen dosya satırı: dosya tabloda GÖRÜNÜR kalır (gizlenmez), durum
# rozeti "Desteklenmeyen dosya türü" bilgisini taşır ve Model Bağlamı hücresi
# ekleme kutusu yerine açıklayıcı bir işaret gösterir. Böylece kullanıcı
# dosyayı yönetebilir (indirme/silme) ama yapay zekâ akışlarına ekleyemez.
fm_build_unsupported_file_table_row <- function(file_name, file_size, file_id, ns, datapath = NULL) {
  display_name <- fm_clean_file_display_name(file_name, list(name = file_name))
  ext <- tolower(tools::file_ext(display_name))

  status_html <- paste0(
    fm_file_ext_icon_html(ext),
    " <span class='fm-unsupported-badge' title='Bu dosya türü uygulama akışlarında desteklenmiyor; yalnızca indirebilir veya silebilirsiniz.'>",
    "Desteklenmeyen dosya türü</span>"
  )

  data.frame(
    Dosya_Adi = display_name,
    Boyut = paste(round((file_size %||% 0) / 1024, 2), "KB"),
    Tur = status_html,
    Yuklenme_Tarihi = fm_format_file_timestamp(path = datapath),
    Islemler = fm_build_unsupported_file_actions_html(file_id = file_id, ns = ns),
    Model_Baglam = "<span class='fm-unsupported-dash' title='Desteklenmeyen dosyalar model bağlamına eklenemez.'>&mdash;</span>",
    stringsAsFactors = FALSE
  )
}

fm_build_file_table_row <- function(file_name, file_size, file_info, file_id, ns) {
  display_name <- fm_clean_file_display_name(file_name, file_info)
  ext <- tolower(tools::file_ext(display_name))
  datapath <- if (is.null(file_info)) NULL else file_info$datapath

  data.frame(
    Dosya_Adi = display_name,
    Boyut = paste(round((file_size %||% 0) / 1024, 2), "KB"),
    Tur = fm_file_ext_icon_html(ext),
    Yuklenme_Tarihi = fm_format_file_timestamp(path = datapath),
    Islemler = fm_build_file_actions_html(file_id = file_id, ns = ns),
    Model_Baglam = fm_build_attach_cell_html(
      file_id = file_id,
      file_name = display_name,
      ns = ns
    ),
    stringsAsFactors = FALSE
  )
}