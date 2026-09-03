# ==============================================================================
# Dosya Yolu: R/module_file_manager_ui.R
# Açıklama: Dosya Yönetimi modülünün UI tanımı.
# ==============================================================================

#' File Manager UI Module
#'
#' @param id A character string, the namespace ID for the module.
#'
#' @return A UI definition for the file manager tab.
fileManagerUI <- function(id) {
  ns <- NS(id)

  # Dosya yükleme boyut sınırı UI tarafında da kullanılacak.
  upload_limit_mb <- fm_upload_limit_mb()
  upload_limit_bytes <- fm_upload_limit_bytes(upload_limit_mb)

  tagList(
    # 32\U00D732 attach checkbox + center it in its cell
    tags$head(tags$style(HTML("
      .files-table-card .attach-cell { display:flex; align-items:center; justify-content:center; }
      .files-table-card input.attach-checkbox { width:32px; height:32px; margin:0; }
      /* center the header cell of the last column (Model Bağlamı) */
      .files-table-card table.dataTable thead th:last-child { text-align: center !important; }
    "))),
    # JS to translate progress bar text and apply success class
    tags$script(HTML("
      $(document).ready(function() {
        var observer = new MutationObserver(function(mutations) {
          mutations.forEach(function(mutation) {
            if (mutation.type === 'childList' || mutation.type === 'characterData') {
              var $bar = $(mutation.target).closest('.progress-bar');
              if ($bar.length && $bar.text().indexOf('Upload complete') > -1) {
                $bar.text('Aktarım için hazır');
                $bar.addClass('upload-complete-success');
              }
            }
          });
        });
        var target = document.getElementById('bulk_upload_div');
        if (target) {
          observer.observe(target, { childList: true, subtree: true, characterData: true });
        }
      });
    ")),

    # Büyük dosyaları Shiny upload başlamadan önce tarayıcı tarafında reddet.
    tags$script(HTML(sprintf("
      (function() {
        var inputId = %s;
        var maxBytes = %d;
        var maxMb = %d;
        var messageInputId = %s;

        function formatMb(bytes) {
          return (bytes / 1024 / 1024).toFixed(1);
        }

        function clearFileInput(input) {
          try {
            input.value = '';
          } catch (e) {}

          try {
            var $wrap = $(input).closest('.form-group');
            $wrap.find('.progress').remove();
          } catch (e) {}
        }

        $(document).off('change.mergenUploadLimit', '#' + inputId);
        $(document).on('change.mergenUploadLimit', '#' + inputId, function(evt) {
          var input = evt.target;
          var files = input.files || [];
          var rejected = [];

          for (var i = 0; i < files.length; i++) {
            if (files[i].size > maxBytes) {
              rejected.push({
                name: files[i].name,
                size: files[i].size
              });
            }
          }

          if (rejected.length > 0) {
            clearFileInput(input);

            if (window.Shiny && Shiny.setInputValue) {
              Shiny.setInputValue(messageInputId, {
                nonce: Math.random(),
                max_mb: maxMb,
                files: rejected.map(function(f) {
                  return {
                    name: f.name,
                    size_mb: formatMb(f.size)
                  };
                })
              }, {priority: 'event'});
            }

            alert('Dosya yüklenmedi. Dosya başına en fazla ' + maxMb + ' MB yükleyebilirsiniz.');
            return false;
          }
        });
      })();
    ",
    jsonlite::toJSON(ns("bulk_upload"), auto_unbox = TRUE),
    upload_limit_bytes,
    upload_limit_mb,
    jsonlite::toJSON(ns("bulk_upload_client_error"), auto_unbox = TRUE)
    ))),

    div(
      class = "content-container",
      div(
        class = "files-header",
        h3("Toplu Dosya Yükleme", class = "page-title"),
        div(
          class = "files-header-actions",
          actionButton(
            ns("refresh_files"),
            label = tagList(icon("sync-alt"), "Yenile"),
            class = "btn-modern btn-refresh"
          ),
          actionButton(
            ns("clear_files"),
            label = tagList(icon("trash-alt"), "Tümünü Temizle"),
            class = "btn-modern btn-danger"
          )
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
                placeholder = "Henüz dosya seçilmedi",
                accept = c(".txt", ".pdf", ".docx", ".xlsx", ".xls", ".csv", ".json", ".R", ".r", ".py", ".md", ".log", ".xml", ".html", ".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".svg")
              )
            ),
            p(class = "upload-hint", "Birden fazla dosya seçebilirsiniz"),
            p(
              class = "upload-hint",
              style = "margin-top: 8px; font-size: 12px;",
              sprintf("Dosya başına en fazla %d MB yükleyebilirsiniz.", upload_limit_mb)
            ),
            p(
              class = "upload-hint",
              style = "margin-top: 8px; font-size: 12px;",
              "Desteklenen dosya türleri: TXT, PDF, DOCX, XLSX, XLS, CSV, JSON, R, PY, MD, LOG, XML, HTML, JPG, JPEG, PNG, GIF, WEBP, BMP, SVG"
            ),
            div(
              id = ns("execute_bulk_upload_container"),
              style = "display: none; margin-top: 20px;"
            )
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
          DT::DTOutput(ns("files_table"))
        )
      )
    ),
    shinyjs::useShinyjs()
  )
}
