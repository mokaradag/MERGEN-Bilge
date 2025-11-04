# R/module_rdata_admin.R
rdataAdminServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    # Basit bir observer ile dışarıdan JS tetikleyebilirsiniz:
    # Shiny.setInputValue('rdata_admin-refresh_now', Math.random())
	observeEvent(input$`refresh_now`, {
	  try({
		helpers_rdata_lake$rdata_refresh_all()
		showNotification("RData Lake yenilendi.", type = "message")
	  }, silent = TRUE)
	})
  })
}
