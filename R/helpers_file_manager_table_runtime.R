# ==============================================================================
# Dosya Yolu: R/helpers_file_manager_table_runtime.R
# Açıklama: Dosya Yönetimi DT tablo render ve ek işaretleme runtime yardımcıları.
# ==============================================================================

fm_register_file_manager_table_runtime <- function(session,
                                                   output,
                                                   ns,
                                                   module_values_provider) {
  output$files_table <- DT::renderDT({
    module_values <- module_values_provider()
    dat <- module_values$files

    if (nrow(dat) == 0) {
      dat <- dat[0, ]
    }

    DT::datatable(
      dat,
      escape = FALSE,
      rownames = FALSE,
      selection = "none",
      colnames = c(
        "Dosya Adı",
        "Boyut",
        "Tür",
        "Yükleme Tarihi",
        "İşlemler",
        "Model Bağlamı"
      ),
      options = list(
        pageLength = 10,
        lengthMenu = list(
          c(5, 10, 25, 50, 100),
          c("5", "10", "25", "50", "100")
        ),
        language = list(
          lengthMenu = "Sayfa başına _MENU_ kayıt göster",
          info = "_TOTAL_ kayıttan _START_ - _END_ arası gösteriliyor",
          infoEmpty = "Gösterilecek kayıt yok",
          paginate = list(previous = "Önceki", `next` = "Sonraki")
        ),
        paging = TRUE,
        dom = "l tip",
        columnDefs = list(
          list(orderable = FALSE, targets = c(ncol(dat) - 2, ncol(dat) - 1)),
          list(className = "dt-center", targets = ncol(dat) - 1)
        ),
        drawCallback = DT::JS(
          sprintf(
            "
            function(settings){
              var tbl = this.api().table().container();
              var ns = '%s';
              var $tbl = $(tbl);

              // Bu kutular ayrı Shiny inputları değildir. Tek sunucu girdisi
              // attach_toggled olduğundan yalnızca delege change handler bağlanır.
              // DataTables yeniden çiziminde önceki handler kaldırılarak aynı
              // olayın birden fazla kez gönderilmesi engellenir.
              $tbl.find('input.attach-checkbox')
                .off('change.attach')
                .on('change.attach', function(){
                  var fid = this.getAttribute('data-file-id');
                  var fname = this.getAttribute('data-filename');
                  var checked = this.checked ? true : false;

                  Shiny.setInputValue(
                    ns + 'attach_toggled',
                    {
                      id: fid,
                      filename: fname,
                      checked: checked,
                      nonce: Math.random()
                    },
                    {priority:'event'}
                  );
                });

              if ($.fn && $.fn.tooltip) {
                $tbl.find('input.attach-checkbox').tooltip({
                  container: 'body',
                  placement: 'top',
                  trigger: 'hover'
                });
              }
            }
            ",
            ns("")
          )
        )
      )
    )
  })

  shiny::observeEvent(TRUE, {
    session$sendCustomMessage(
      "initAttachHandlerOnce",
      list(ns_prefix = ns(""))
    )
  }, once = TRUE)

  fm_register_attach_state_client_handler(session = session, ns = ns)

  invisible(TRUE)
}

fm_create_file_manager_attachment_setter <- function(session,
                                                     ns,
                                                     module_values_provider,
                                                     attach_in_parent,
                                                     detach_in_parent) {
  force(session)
  force(ns)
  force(module_values_provider)
  force(attach_in_parent)
  force(detach_in_parent)

  function(filename, checked) {
    module_values <- module_values_provider()

    fid <- NULL
    for (id in names(module_values$file_contents)) {
      if (identical(module_values$file_contents[[id]]$name, filename)) {
        fid <- id
        break
      }
    }

    if (is.null(fid)) {
      return(invisible(FALSE))
    }

    if (isTRUE(checked)) {
      module_values$files_in_context[[fid]] <- TRUE
      attach_in_parent(module_values$file_contents[[fid]])
    } else {
      module_values$files_in_context[[fid]] <- NULL
      detach_in_parent(filename)
    }

    session$sendCustomMessage(
      ns("setAttachState"),
      list(ids = fid, checked = isTRUE(checked))
    )

    invisible(TRUE)
  }
}