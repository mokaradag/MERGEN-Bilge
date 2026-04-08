# ==============================================================================
# Dosya Yolu: R/config_claude_code_plugins.R
# Açıklama: Claude Code Plugin sistemi için yapılandırma sabitleri.
#           Yerel gömülü pluginler (bilge_yolac_plugins/) için durum etiketleri,
#           bileşen türleri ve UI sabitleri burada merkezi olarak yönetilir.
# ==============================================================================

# ------------------------------------------------------------------------------
# PLUGIN YAPILANDIRMA SABİTLERİ
# ------------------------------------------------------------------------------

claude_code_plugins_config <- list(
  # Pluginlerin etkinleştirilebilir/devre dışı bırakılabilir olması
  allow_toggle = as.logical(Sys.getenv("CLAUDE_CODE_PLUGINS_ALLOW_TOGGLE", "TRUE"))
)

# ------------------------------------------------------------------------------
# PLUGIN DURUM ETİKETLERİ (Türkçe)
# UI'da gösterilecek durum metinleri ve renkleri.
# ------------------------------------------------------------------------------

claude_code_plugin_status <- list(
  aktif = list(
    metin = "Aktif",
    renk  = "#81C784",
    ikon  = "check-circle"
  ),
  pasif = list(
    metin = "Pasif",
    renk  = "#FFB74D",
    ikon  = "toggle-off"
  )
)

# ------------------------------------------------------------------------------
# PLUGIN BİLEŞEN TÜRLERİ
# Bir plugin'in içerebileceği bileşen türleri ve Türkçe etiketleri.
# ------------------------------------------------------------------------------

claude_code_plugin_bilesenler <- list(
  commands = list(
    etiket = "Komutlar",
    ikon   = "terminal",
    aciklama = "Slash komutları (/komut)"
  ),
  agents = list(
    etiket = "Ajanlar",
    ikon   = "robot",
    aciklama = "Özelleştirilmiş alt ajanlar"
  ),
  skills = list(
    etiket = "Yetenekler",
    ikon   = "magic",
    aciklama = "Model tarafından kullanılan yetenekler"
  ),
  hooks = list(
    etiket = "Kancalar",
    ikon   = "link",
    aciklama = "Olay tabanlı otomasyon"
  ),
  mcp_servers = list(
    etiket = "MCP Sunucuları",
    ikon   = "server",
    aciklama = "Harici araç ve servis entegrasyonları"
  )
)

# ------------------------------------------------------------------------------
# LOG ÖNEKİ
# ------------------------------------------------------------------------------
CLAUDE_CODE_PLUGINS_LOG_PREFIX <- "[Bilge Yolaç Eklentiler]"