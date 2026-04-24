# ==============================================================================
# Dosya Yolu: R/module_health_security.R
# Açıklama: Sistem Durumu panelinin Güvenlik ve Yapılandırma sekmesi için UI yardımcıları.
# ==============================================================================

health_security_ui <- function(checks) {
  subset <- checks[grepl("^(security|env\\.|db\\.schema)", checks$id), , drop = FALSE]
  required <- subset[subset$id %in% paste0("env.", c("LOCAL_LLM_ENDPOINT", "DB_DSN", "AI_KEYS_MASTER")), , drop = FALSE]
  tagList(
    div(
      class = "health-metrics-grid",
      health_metric_tile("SSO", checks$value[match("security.sso", checks$id)] %||% "N/A", "user-shield", "ok"),
      health_metric_tile("Zorunlu Env", paste0(sum(required$status == "ok"), "/", nrow(required)), "key", if (all(required$status == "ok")) "ok" else "critical"),
      health_metric_tile("DB Şema", checks$value[match("db.schema", checks$id)] %||% "N/A", "table", checks$status[match("db.schema", checks$id)] %||% "unknown"),
      health_metric_tile("Secrets", "Maskeli", "lock", "ok", "Değerler gösterilmez")
    ),
    health_section_card("Güvenlik ve Yapılandırma", "shield-alt", health_checks_table(subset))
  )
}
