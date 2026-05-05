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
  explicit_display <- ""

  if (is.list(file_info)) {
    explicit_display <- file_info$display_name %||%
      file_info$display %||%
      file_info$original_name %||%
      ""
  }

  explicit_display <- as.character(explicit_display %||% "")[1]
  if (!is.na(explicit_display) && nzchar(explicit_display)) {
    return(explicit_display)
  }

  display_name <- as.character(file_name %||% "")[1]
  if (is.na(display_name)) {
    display_name <- ""
  }

  if (exists("recover_display_name_from_storage_name", mode = "function", inherits = TRUE)) {
    display_name <- tryCatch(
      recover_display_name_from_storage_name(display_name),
      error = function(e) display_name
    )
  }

  display_name
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