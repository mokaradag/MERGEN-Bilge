# ==============================================================================
# Dosya Yolu: R/module_health_storage.R
# Açıklama: Sistem Durumu panelinin Depolama sekmesi için UI yardımcıları.
# ==============================================================================

health_storage_path_item <- function(name, value, tooltip) {
  div(
    `data-toggle` = "tooltip",
    `data-placement` = "top",
    title = tooltip,
    strong(name),
    span(health_render_value(value, paste0("storage.path.", name)))
  )
}

health_storage_ui <- function(checks) {
  ids <- c("storage.files_root", "storage.uploads_root", "storage.index_json", "storage.log_dir", "storage.mcp_base", "storage.disk_free", "storage.upload_disk_free")
  subset <- checks[checks$id %in% ids, , drop = FALSE]
  tagList(
    div(
      class = "health-path-summary",
      health_storage_path_item("MERGEN_FILES_ROOT", Sys.getenv("MERGEN_FILES_ROOT", "—"), "Kalıcı dosya deposu kök dizini."),
      health_storage_path_item("MERGEN_UPLOADS_DIR", Sys.getenv("MERGEN_UPLOADS_DIR", "—"), "Kullanıcı yüklemelerinin saklandığı kök dizin."),
      health_storage_path_item("MERGEN_INDEX_PATH", Sys.getenv("MERGEN_INDEX_PATH", "—"), "Dosya indeks JSON dosyasının yolu."),
      health_storage_path_item("MERGEN_MCP_BASE_DIR", Sys.getenv("MERGEN_MCP_BASE_DIR", "—"), "MCP/dosya analizi çalışma alanı kök dizini.")
    ),
    health_section_card(
      "Dosya Sistemi ve Disk",
      "folder-open",
      health_checks_table(subset, max_height = 420),
      tooltip = "Dosya kökleri, yazma izinleri, index JSON ve boş disk alanı kontrolleri."
    )
  )
}
