# ==============================================================================
# Dosya Yolu: R/module_health_storage.R
# Açıklama: Sistem Durumu panelinin Depolama sekmesi için UI yardımcıları.
# ==============================================================================

health_storage_ui <- function(checks) {
  ids <- c("storage.files_root", "storage.uploads_root", "storage.index_json", "storage.log_dir", "storage.mcp_base", "storage.disk_free", "storage.upload_disk_free")
  subset <- checks[checks$id %in% ids, , drop = FALSE]
  tagList(
    div(
      class = "health-path-summary",
      div(strong("MERGEN_FILES_ROOT"), span(Sys.getenv("MERGEN_FILES_ROOT", "—"))),
      div(strong("MERGEN_UPLOADS_DIR"), span(Sys.getenv("MERGEN_UPLOADS_DIR", "—"))),
      div(strong("MERGEN_INDEX_PATH"), span(Sys.getenv("MERGEN_INDEX_PATH", "—"))),
      div(strong("MERGEN_MCP_BASE_DIR"), span(Sys.getenv("MERGEN_MCP_BASE_DIR", "—")))
    ),
    health_section_card("Dosya Sistemi ve Disk", "folder-open", health_checks_table(subset))
  )
}
