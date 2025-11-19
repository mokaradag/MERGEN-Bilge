# R/module_file_manager.R
# New implementation: deterministic state handling + reliable persistence bridge

fileManagerUI <- function(id) {
  ns <- NS(id)

  tagList(
    tags$head(tags$style(HTML(paste(
      ".files-table-card .attach-cell { display:flex; align-items:center; justify-content:center; }",
      ".files-table-card input.attach-checkbox { width:32px; height:32px; margin:0; }",
      ".files-table-card table.dataTable thead th:last-child { text-align: center !important; }",
      sep = "\n"
    )))),
    div(
      class = "content-container",
      style = "padding-right: 20px;",
      div(
        class = "files-header",
        h3("Toplu Dosya Yükleme", class = "page-title"),
        actionButton(
          ns("clear_files"),
          label = tagList(icon("trash-alt"), "Tümünü Temizle"),
          class = "btn-modern btn-danger"
        )
      ),
      div(
        class = "scrollable-content",
        div(
          class = "file-upload-card",
          div(
            id = ns("main_drop_zone"),
            class = "main-drop-zone",
            tags$i(class = "fas fa-upload fa-3x"),
            h4("Dosyaları buraya sürükleyin veya göz atın"),
            div(
              id = "bulk_upload_div",
              fileInput(
                ns("bulk_upload"),
                label = NULL,
                multiple = TRUE,
                buttonLabel = tagList(icon("folder-open"), "Göz At"),
                placeholder = "Henüz dosya seçilmedi"
              )
            ),
            p(class = "upload-hint", "Birden fazla dosya seçebilirsiniz"),
            p(
              class = "upload-hint",
              style = "margin-top: 8px; font-size: 12px;",
              "Desteklenen dosya türleri: TXT, PDF, DOCX, DOC, XLSX, XLS, CSV, JSON, R, PY, MD, LOG, XML, HTML"
            ),
            div(id = ns("execute_bulk_upload_container"), style = "display:none; margin-top:20px;")
          )
        ),
        div(
          class = "files-table-card",
          h3("Yüklenen Dosyalar", class = "section-title"),
          div(
            id = ns("attach_rule_hint"),
            style = "margin: 6px 0 12px 0; font-size: 12px; color: #a3a3a3;",
            "Seçim kuralı: MCP açıkken yalnızca 1 dosya eklenebilir; kapalıyken birden fazla seçim yapabilirsiniz."
          ),
          DT::dataTableOutput(ns("files_table"))
        )
      )
    ),
    shinyjs::useShinyjs()
  )
}

fileManagerServer <- function(
  id,
  new_file_trigger = reactive(NULL),
  session_files_reactive = NULL,
  mcp_enabled_reactive = reactive({ FALSE }),
  user_id = NULL
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    module_user_id <- user_id %||% session$userData$user_id %||% "unknown"
    module_user_id_chr <- as.character(module_user_id)

    # -----------------------------------------------------------------------
    # Local state helpers ---------------------------------------------------
    empty_files_df <- function() {
      data.frame(
        Dosya_Adi = character(),
        Boyut = character(),
        Tur = character(),
        Yuklenme_Tarihi = character(),
        Islemler = character(),
        Model_Baglam = character(),
        stringsAsFactors = FALSE
      )
    }

    state <- reactiveValues(
      records = list(),
      files = empty_files_df(),
      attachments = list(),
      pending_delete = NULL
    )

    current_record_names <- function() {
      if (!length(state$records)) return(character(0))
      vapply(state$records, `[[`, character(1), "name", USE.NAMES = FALSE)
    }

    bulk_files_to_process <- reactiveVal(NULL)
    file_to_preview <- reactiveVal(NULL)
    file_removed <- reactiveVal(NULL)
    all_files_cleared <- reactiveVal(FALSE)
    files_added_to_context <- reactiveVal(NULL)
    message_trigger <- reactiveVal(0)
    message_data <- reactiveVal(NULL)

    ensure_session_registry <- function() {
      if (is.null(session$userData$current_session_files) ||
          !is.list(session$userData$current_session_files)) {
        session$userData$current_session_files <- list()
      }
    }

    register_session_file <- function(filename, fpath) {
      ensure_session_registry()
      fname <- as.character(filename %||% "")
      if (!nzchar(fname)) return(invisible(FALSE))
      norm_path <- tryCatch(
        normalizePath(fpath, winslash = "/", mustWork = FALSE),
        error = function(e) as.character(fpath %||% "")
      )
      if (!nzchar(norm_path)) return(invisible(FALSE))

      session$userData$current_session_files[[fname]] <- list(
        name = fname,
        datapath = norm_path,
        path = norm_path,
        persisted_path = norm_path
      )
      invisible(TRUE)
    }

    unregister_session_file <- function(filename) {
      ensure_session_registry()
      fname <- as.character(filename %||% "")
      if (!nzchar(fname)) return(invisible(FALSE))
      session$userData$current_session_files[[fname]] <- NULL
      invisible(TRUE)
    }

    if (is.null(session$userData$temp_files)) session$userData$temp_files <- list()

    allowed_extensions <- c("txt","pdf","doc","docx","xlsx","xls","csv","json","r","py","md","log","xml","html")

    format_size <- function(size) {
      sz <- suppressWarnings(as.numeric(size))
      if (is.na(sz) || sz <= 0) return("-")
      units <- c("B","KB","MB","GB")
      idx <- 1
      while (sz >= 1024 && idx < length(units)) {
        sz <- sz / 1024
        idx <- idx + 1
      }
      sprintf("%.2f %s", sz, units[idx])
    }

    format_timestamp <- function(ts) {
      if (inherits(ts, "POSIXct") || inherits(ts, "POSIXt")) {
        return(format(ts, "%Y-%m-%d %H:%M"))
      }
      format(Sys.time(), "%Y-%m-%d %H:%M")
    }

    ext_icon_html <- function(ext) {
      e <- tolower(ext %||% "")
      ico <- switch(
        e,
        "pdf"  = "<i class='fa-regular fa-file-pdf' style='margin-right:6px;color:#c00'></i>",
        "doc"  = "<i class='fa-regular fa-file-word' style='margin-right:6px;color:#2b579a'></i>",
        "docx" = "<i class='fa-regular fa-file-word' style='margin-right:6px;color:#2b579a'></i>",
        "xls"  = "<i class='fa-regular fa-file-excel' style='margin-right:6px;color:#217346'></i>",
        "xlsx" = "<i class='fa-regular fa-file-excel' style='margin-right:6px;color:#217346'></i>",
        "csv"  = "<i class='fa-regular fa-file-excel' style='margin-right:6px;color:#217346'></i>",
        "json" = "<i class='fa-regular fa-file-code' style='margin-right:6px;'></i>",
        "xml"  = "<i class='fa-regular fa-file-code' style='margin-right:6px;'></i>",
        "html" = "<i class='fa-regular fa-file-code' style='margin-right:6px;'></i>",
        "r"    = "<i class='fa-regular fa-file-code' style='margin-right:6px;'></i>",
        "py"   = "<i class='fa-regular fa-file-code' style='margin-right:6px;'></i>",
        "md"   = "<i class='fa-regular fa-file-lines' style='margin-right:6px;'></i>",
        "log"  = "<i class='fa-regular fa-file-lines' style='margin-right:6px;'></i>",
        "txt"  = "<i class='fa-regular fa-file-lines' style='margin-right:6px;'></i>",
        "<i class='fa-regular fa-file' style='margin-right:6px;'></i>"
      )
      paste0(ico, toupper(e))
    }

    generate_file_id <- function(seed = NULL) {
      if (!is.null(seed) && nzchar(seed)) {
        return(digest::digest(seed, algo = "xxhash64"))
      }
      paste0("file_", digest::digest(runif(1), algo = "xxhash64"))
    }

    register_download_handler <- function(record) {
      local_id <- record$id
      output[[paste0("download_", local_id)]] <- downloadHandler(
        filename = function() record$name,
        content = function(file) {
          if (path_exists_relaxed(record$datapath)) {
            file.copy(record$datapath, file, overwrite = TRUE)
          } else {
            stop("Dosya bulunamadı.")
          }
        },
        contentType = "application/octet-stream"
      )
      outputOptions(output, paste0("download_", local_id), suspendWhenHidden = FALSE)
    }

    build_action_buttons <- function(record_id) {
      hidden_dl <- as.character(tags$span(
        style = "display:none;",
        shiny::downloadLink(outputId = ns(paste0("download_", record_id)), label = "")
      ))

      as.character(tags$div(
        class = "file-actions",
        tags$button(
          class = "file-action-btn file-view js-file-action",
          title = "Görüntüle",
          `data-action` = "view",
          `data-file-id` = record_id,
          icon("eye")
        ),
        tags$button(
          class = "file-action-btn file-download js-download-btn",
          title = "İndir",
          `data-download-id` = record_id,
          icon("download")
        ),
        tags$button(
          class = "file-action-btn file-delete js-file-action",
          title = "Sil",
          `data-action` = "delete",
          `data-file-id` = record_id,
          icon("trash")
        ),
        HTML(hidden_dl)
      ))
    }

    build_attach_checkbox <- function(record) {
      as.character(tags$div(
        class = "attach-cell",
        tags$input(
          id = ns(paste0("attach_", record$id)),
          type = "checkbox",
          class = "attach-checkbox",
          `data-file-id` = record$id,
          `data-filename` = record$name,
          title = "Bu dosyayı model bağlamına ekle/çıkar",
          `aria-label` = "Model bağlamına ekle veya çıkar"
        )
      ))
    }

    update_table_data <- function() {
      if (!length(state$records)) {
        state$files <- empty_files_df()
        return()
      }

      record_list <- state$records
      rows <- lapply(record_list, function(rec) {
        data.frame(
          Dosya_Adi = rec$name,
          Boyut = format_size(rec$size),
          Tur = ext_icon_html(tools::file_ext(rec$name)),
          Yuklenme_Tarihi = format_timestamp(rec$uploaded_at %||% Sys.time()),
          Islemler = build_action_buttons(rec$id),
          Model_Baglam = build_attach_checkbox(rec),
          stringsAsFactors = FALSE
        )
      })

      timestamps <- vapply(record_list, function(x) {
        ts <- x$uploaded_at
        if (inherits(ts, "POSIXct") || inherits(ts, "POSIXt")) {
          return(as.numeric(ts))
        }
        as.numeric(Sys.time())
      }, numeric(1), USE.NAMES = FALSE)
      ord <- order(timestamps, decreasing = TRUE)
      state$files <- do.call(rbind, rows[ord])
    }

    store_record <- function(record) {
      state$records[[record$id]] <- record
      register_session_file(record$name, record$datapath)
      register_download_handler(record)
      update_table_data()
    }

    announce_upload <- function(record) {
      html_message <- sprintf(
        "📎 <b>%s</b> yüklendi. Yapay zekâya eklemek için <i>Model Bağlamı</i> kutucuğunu kullanabilirsiniz.",
        htmltools::htmlEscape(record$name)
      )
      message_data(list(content = paste(record$name, "yüklendi."), html = html_message, type = "system"))
      message_trigger(message_trigger() + 1)
    }

    ingest_upload <- function(file_info, announce = TRUE, force_id = NULL, uploaded_at = NULL) {
      file_name <- as.character(file_info$name %||% "")[1]
      file_path <- as.character(file_info$datapath %||% file_info$path %||% "")[1]
      if (!nzchar(file_name) || !nzchar(file_path) || !path_exists_relaxed(file_path)) {
        showToast(session, "Yüklenen dosya yolu okunamadı.", "error")
        return(NULL)
      }

      file_ext <- tolower(tools::file_ext(file_name))
      if (!file_ext %in% allowed_extensions) {
        showToast(session, sprintf("'%s' dosya türü desteklenmiyor!", file_ext), "error")
        return(NULL)
      }

      file_size <- suppressWarnings(as.numeric((file_info$size %||% file.info(file_path)$size)[1]))
      file_type <- (file_info$type %||% mime::guess_type(file_path) %||% file_ext)[1]
      record_id <- force_id %||% file_info$id %||% generate_file_id(paste(file_name, file_path))

      record <- list(
        id = record_id,
        name = file_name,
        datapath = file_path,
        persisted_path = file_path,
        size = file_size,
        type = file_type,
        uploaded_at = uploaded_at %||% Sys.time(),
        summary = file_info$summary %||% NULL
      )

      store_record(record)
      if (isTRUE(announce)) announce_upload(record)

      list(
        record = record,
        payload = list(
          name = record$name,
          datapath = record$datapath,
          size = record$size,
          type = record$type,
          id = record$id,
          persisted_path = record$persisted_path
        )
      )
    }

    load_persisted_records <- function() {
      df <- try(mergen_list_user_files(module_user_id_chr), silent = TRUE)
      if (inherits(df, "try-error") || is.null(df) || nrow(df) == 0) {
        update_table_data()
        return()
      }

      for (i in seq_len(nrow(df))) {
        file_path <- df$path[i]
        display_name <- df$name[i]
        if (!path_exists_relaxed(file_path)) next

        finfo <- list(
          name = display_name,
          datapath = file_path,
          size = suppressWarnings(file.info(file_path)$size),
          type = mime::guess_type(file_path) %||% tools::file_ext(display_name)
        )

        ingest_upload(
          finfo,
          announce = FALSE,
          force_id = generate_file_id(file_path),
          uploaded_at = suppressWarnings(file.info(file_path)$mtime)
        )
      }
      update_table_data()
    }

    update_session_files <- function(update_fn) {
      if (is.null(session_files_reactive)) return(invisible())
      try({
        cur <- session_files_reactive()
        session_files_reactive(update_fn(cur))
      }, silent = TRUE)
    }

    attach_in_parent <- function(record) {
      if (is.null(session_files_reactive)) return(invisible())
      update_session_files(function(cur) {
        cur <- cur %||% list()
        cur[[record$name]] <- cur[[record$name]] %||% list(name = record$name)
        cur
      })
    }

    detach_in_parent <- function(filename) {
      if (is.null(session_files_reactive)) return(invisible())
      update_session_files(function(cur) {
        cur <- cur %||% list()
        cur[[filename]] <- NULL
        cur
      })
    }

    set_attachment_checked <- function(filename, checked) {
      target_id <- NULL
      for (id in names(state$records)) {
        if (identical(state$records[[id]]$name, filename)) {
          target_id <- id
          break
        }
      }
      if (is.null(target_id)) return(invisible(FALSE))

      if (isTRUE(checked)) {
        state$attachments[[target_id]] <- TRUE
        attach_in_parent(state$records[[target_id]])
      } else {
        state$attachments[[target_id]] <- NULL
        detach_in_parent(filename)
      }

      session$sendCustomMessage(ns("setAttachState"), list(ids = target_id, checked = isTRUE(checked)))
      invisible(TRUE)
    }

    remove_record <- function(record_id, quiet = FALSE) {
      record <- state$records[[record_id]]
      if (is.null(record)) return(invisible(FALSE))

      state$attachments[[record_id]] <- NULL
      unregister_session_file(record$name)
      state$records[[record_id]] <- NULL
      update_table_data()

      if (!quiet) {
        message_data(list(type = "system", content = paste0("Silindi: ", record$name), html = NULL))
        message_trigger(message_trigger() + 1)
        showToast(session, paste("Dosya silindi:", record$name), "warning")
      }
      file_removed(record)
      TRUE
    }

    remove_file_by_name <- function(filename, quiet = FALSE) {
      target_id <- NULL
      for (id in names(state$records)) {
        if (identical(state$records[[id]]$name, filename)) {
          target_id <- id
          break
        }
      }
      if (is.null(target_id)) return(invisible(FALSE))
      remove_record(target_id, quiet = quiet)
    }

    update_attach_hint <- function() {
      txt <- if (isTRUE(mcp_enabled_reactive())) {
        "Seçim kuralı: MCP açıkken yalnızca 1 dosya eklenebilir."
      } else {
        "Seçim kuralı: MCP kapalıyken birden fazla dosya seçebilirsiniz."
      }
      shinyjs::html(id = ns("attach_rule_hint"), html = txt, add = FALSE)
    }

    # -----------------------------------------------------------------------
    # Startup load ----------------------------------------------------------
    observeEvent(TRUE, {
      load_persisted_records()
      update_attach_hint()
    }, once = TRUE)

    # -----------------------------------------------------------------------
    # UI events -------------------------------------------------------------
    observeEvent(input$bulk_upload, {
      shinyjs::runjs(sprintf("$('#%s').show();", ns("execute_bulk_upload_container")))
    }, ignoreInit = TRUE)

    observeEvent(input$clear_pending_files, {
      shinyjs::reset(ns("bulk_upload"))
      shinyjs::runjs(sprintf("$('#%s').hide();", ns("execute_bulk_upload_container")))
      session$sendCustomMessage('resetBulkUploadCaption', list())
      showToast(session, "Seçili dosyalar kaldırıldı.", "info")
    })

    observeEvent(mcp_enabled_reactive(), {
      update_attach_hint()
    })

    observeEvent(input$attach_toggled, {
      req(input$attach_toggled)
      file_id <- input$attach_toggled$id
      fname <- input$attach_toggled$filename
      checked <- isTRUE(input$attach_toggled$checked)
      record <- state$records[[file_id]]
      req(record)

      if (checked && isTRUE(mcp_enabled_reactive())) {
        others <- setdiff(names(state$attachments), file_id)
        if (length(others)) {
          state$attachments[others] <- NULL
          lapply(others, function(oid) {
            rec <- state$records[[oid]]
            if (!is.null(rec)) detach_in_parent(rec$name)
          })
          session$sendCustomMessage(ns("setAttachState"), list(ids = others, checked = FALSE))
          showToast(session, "MCP açıkken sadece 1 dosya eklenebilir.", "warning")
        }
      }

      if (checked) {
        state$attachments[[file_id]] <- TRUE
        attach_in_parent(record)
      } else {
        state$attachments[[file_id]] <- NULL
        detach_in_parent(fname)
      }

      update_attach_hint()
    }, ignoreNULL = TRUE)

    observeEvent(new_file_trigger(), {
      req(new_file_trigger())
      incoming <- new_file_trigger()
      existing_names <- current_record_names()
      if (incoming$name %in% existing_names) return()
      ingest_upload(incoming, announce = TRUE)
    }, ignoreInit = TRUE)

    observeEvent(input$execute_bulk_upload, {
      req(input$bulk_upload)
      files_df <- input$bulk_upload
      shinyjs::reset(ns("bulk_upload"))
      session$sendCustomMessage('resetBulkUploadCaption', list())
      shinyjs::runjs(sprintf("$('#%s').hide();", ns("execute_bulk_upload_container")))

      existing_names <- current_record_names()
      new_df <- files_df[!files_df$name %in% existing_names, , drop = FALSE]
      dup_df <- files_df[files_df$name %in% existing_names, , drop = FALSE]

      if (nrow(dup_df) > 0) {
        showToast(session, paste("Dosya(lar) zaten mevcut:", paste(dup_df$name, collapse = ", ")), "warning")
      }

      saved_infos <- list()
      if (nrow(new_df) > 0) {
        withProgress(message = 'Dosyalar yükleniyor...', value = 0, {
          for (i in seq_len(nrow(new_df))) {
            incProgress(1 / nrow(new_df), detail = new_df$name[i])
            added <- ingest_upload(new_df[i, , drop = FALSE], announce = FALSE)
            if (!is.null(added)) {
              saved_infos[[length(saved_infos) + 1]] <- added$payload
            }
          }
        })
      }

      if (length(saved_infos) > 0) {
        message_data(list(
          content = sprintf("%d dosya yüklendi.", length(saved_infos)),
          html = sprintf("📎 <b>%d dosya</b> yüklendi ve sohbete eklendi.", length(saved_infos)),
          type = "system"
        ))
        message_trigger(message_trigger() + 1)
        showToast(session, paste(length(saved_infos), "dosya başarıyla yüklendi!"), "success")
        files_added_to_context(saved_infos)
      }

      shinyjs::delay(100, session$sendCustomMessage('resetBulkUploadCaption', list()))
    }, ignoreNULL = TRUE)

    observeEvent(input$file_action, {
      req(input$file_action)
      info <- state$records[[input$file_action$id]]
      req(info)

      if (input$file_action$action == "view") {
        file_to_preview(info)
        message_data(list(type = "view_file", content = info$id, html = NULL))
        message_trigger(message_trigger() + 1)
      } else if (input$file_action$action == "delete") {
        state$pending_delete <- info$id
        showModal(modalDialog(
          title = "Dosyayı Sil",
          paste0("'", info$name, "' adlı dosyayı silmek istediğinizden emin misiniz?"),
          footer = tagList(
            actionButton(ns("confirm_delete_file"), "Evet, Sil", class = "btn-modern btn-danger"),
            modalButton("İptal", icon = icon("ban"))
          ),
          easyClose = TRUE
        ))
      }
    }, ignoreInit = TRUE)

    observeEvent(input$confirm_delete_file, {
      req(state$pending_delete)
      file_id <- state$pending_delete
      info <- state$records[[file_id]]
      removeModal()
      req(info)

      persisted <- try(resolve_uploaded_file(info$name, module_user_id_chr), silent = TRUE)
      if (!inherits(persisted, "try-error") && !is.null(persisted) && file.exists(persisted)) {
        try(unlink(persisted, force = TRUE), silent = TRUE)
      }
      try(mergen_remove_from_index(module_user_id_chr, info$name), silent = TRUE)

      if (!is.null(session$userData$temp_files[[file_id]])) {
        try(unlink(session$userData$temp_files[[file_id]]), silent = TRUE)
        session$userData$temp_files[[file_id]] <- NULL
      }

      remove_record(file_id)
      state$pending_delete <- NULL
    }, ignoreInit = TRUE)

    observeEvent(input$clear_files, {
      if (!length(state$records)) {
        showToast(session, "Temizlenecek dosya yok.", "info")
        return()
      }
      showModal(modalDialog(
        title = "Tüm Dosyaları Temizle",
        "Tüm yüklenmiş dosyaları silmek istediğinizden emin misiniz?",
        footer = tagList(
          actionButton(ns("confirm_clear_files"), "Evet, Tümünü Sil", class = "btn-modern btn-danger"),
          modalButton("İptal", icon = icon("ban"))
        ),
        easyClose = TRUE
      ))
    })

    observeEvent(input$confirm_clear_files, {
      removeModal()
      try(mergen_clear_user_bucket(module_user_id_chr), silent = TRUE)

      lapply(state$records, function(rec) file_removed(rec))

      for (p in session$userData$temp_files) try(unlink(p), silent = TRUE)
      session$userData$temp_files <- list()

      state$records <- list()
      state$attachments <- list()
      update_table_data()
      ensure_session_registry()
      session$userData$current_session_files <- list()

      all_files_cleared(TRUE)
      showToast(session, "Tüm dosyalar (diskten de) temizlendi.", "warning")
      session$sendCustomMessage('resetBulkUploadCaption', list())
      message_data(list(type = "system", content = "Tüm dosyalar kalıcı klasörden silindi.", html = NULL))
      message_trigger(message_trigger() + 1)
      shinyjs::delay(100, { all_files_cleared(FALSE) })
    }, ignoreInit = TRUE)

    output$files_table <- DT::renderDataTable({
      dat <- state$files
      if (nrow(dat) == 0) dat <- dat[0, ]
      DT::datatable(
        dat,
        escape = FALSE,
        rownames = FALSE,
        selection = "none",
        colnames = c("Dosya Adı", "Boyut", "Tür", "Yükleme Tarihi", "İşlemler", "Model Bağlamı"),
        options = list(
          pageLength = 10,
          lengthMenu = list(c(5, 10, 25, 50, 100), c('5', '10', '25', '50', '100')),
          language = list(
            lengthMenu = "Sayfa başına _MENU_ kayıt göster",
            info = "_TOTAL_ kayıttan _START_ - _END_ arası gösteriliyor",
            infoEmpty = "Gösterilecek kayıt yok",
            paginate = list(previous = "Önceki", `next` = "Sonraki")
          ),
          paging = TRUE,
          dom = 'l tip',
          columnDefs = list(
            list(orderable = FALSE, targets = c(ncol(dat) - 2, ncol(dat) - 1)),
            list(className = 'dt-center', targets = ncol(dat) - 1)
          ),
          drawCallback = DT::JS(sprintf(
            "function(settings){\n              var tbl = this.api().table().container();\n              try{Shiny.unbindAll(tbl);}catch(e){}\n              try{Shiny.bindAll(tbl);}catch(e){}\n              var ns = '%s';\n              var $tbl = $(tbl);\n              $tbl.find('input.attach-checkbox').off('change.attach').on('change.attach', function(){\n                var fid = this.getAttribute('data-file-id');\n                var fname = this.getAttribute('data-filename');\n                var checked = this.checked ? true : false;\n                Shiny.setInputValue(ns + 'attach_toggled', { id: fid, filename: fname, checked: checked, nonce: Math.random() }, {priority:'event'});\n              });\n              if ($.fn && $.fn.tooltip) {\n                $tbl.find('input.attach-checkbox').tooltip({container:'body', placement:'top', trigger:'hover'});\n              }\n            }",
            ns("")
          ))
        ),
        callback = DT::JS("var tbl = table.table().container(); try{Shiny.unbindAll(tbl);}catch(e){} try{Shiny.bindAll(tbl);}catch(e){}")
      )
    })

    observeEvent(TRUE, {
      session$sendCustomMessage("initAttachHandlerOnce", list(ns_prefix = ns("")))
    }, once = TRUE)

    session$onFlushed(function() {
      shinyjs::runjs(sprintf(
        "(function(){\n          if (window.__attachHandlerInit) return;\n          window.__attachHandlerInit = true;\n          Shiny.addCustomMessageHandler('initAttachHandlerOnce', function(x){});\n          Shiny.addCustomMessageHandler('%ssetAttachState', function(msg){\n            var ids = Array.isArray(msg.ids) ? msg.ids : [msg.ids];\n            ids.forEach(function(fid){\n              var el = document.getElementById('%s' + 'attach_' + fid);\n              if(el){ el.checked = !!msg.checked; }\n            });\n          });\n        })();",
        ns(""), ns("")
      ))
    })

    session$onSessionEnded(function() {
      tf <- session$userData$temp_files
      if (is.null(tf)) return()
      for (temp_path in tf) try(unlink(temp_path), silent = TRUE)
      session$userData$temp_files <- list()
    })

    sync_file_to_context <- function(filename, summary = NULL, persisted_path = NULL) {
      updated <- FALSE
      for (id in names(state$records)) {
        record <- state$records[[id]]
        if (!identical(record$name, filename)) next

        if (!is.null(summary)) {
          state$records[[id]]$summary <- summary
        }
        if (!is.null(persisted_path) && nzchar(persisted_path)) {
          norm_path <- tryCatch(normalizePath(persisted_path, winslash = "/", mustWork = FALSE), error = function(e) persisted_path)
          state$records[[id]]$persisted_path <- norm_path
          state$records[[id]]$datapath <- norm_path
          register_session_file(filename, norm_path)
        }
        updated <- TRUE
      }
      if (updated) update_table_data()
      invisible(updated)
    }

    list(
      get_bulk_files = reactive({ bulk_files_to_process() }),
      get_file_to_preview = reactive({ file_to_preview() }),
      message_trigger = reactive({ message_trigger() }),
      get_message = reactive({ message_data() }),
      file_contents = reactive({ state$records }),
      file_removed = reactive({ file_removed() }),
      all_files_cleared = reactive({ all_files_cleared() }),
      files_added_to_context = reactive({ files_added_to_context() }),
      remove_file_from_manager = function(filename) { remove_file_by_name(filename, quiet = TRUE) },
      set_attachment_checked = set_attachment_checked,
      sync_file_to_context = sync_file_to_context
    )
  })
}