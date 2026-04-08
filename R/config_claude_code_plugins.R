# ==============================================================================
# Dosya Yolu: R/config_claude_code_plugins.R
# Açıklama: Claude Code Plugin sistemi için yapılandırma sabitleri.
#           Marketplace URL'leri, plugin durumları, varsayılan ayarlar ve
#           UI etiketleri burada merkezi olarak yönetilir.
# ==============================================================================

# ------------------------------------------------------------------------------
# PLUGIN YAPILANDIRMA SABİTLERİ
# .Renviron dosyasından okunabilir, aksi halde varsayılanlar kullanılır.
# ------------------------------------------------------------------------------

claude_code_plugins_config <- list(
  # Marketplace URL (kurumsal iç ağ marketplace adresi)
  marketplace_url = Sys.getenv("CLAUDE_CODE_PLUGINS_MARKETPLACE_URL", ""),

  # Plugin yenileme aralığı (saniye) - yüklü pluginlerin listesi ne sıklıkla güncellenir
  refresh_interval_sec = as.integer(Sys.getenv("CLAUDE_CODE_PLUGINS_REFRESH_INTERVAL", "300")),

  # Pluginlerin etkinleştirilebilir/devre dışı bırakılabilir olması
  allow_toggle = as.logical(Sys.getenv("CLAUDE_CODE_PLUGINS_ALLOW_TOGGLE", "TRUE")),

  # Kurulum izni (yönetici kısıtlaması varsa FALSE yapılabilir)
  allow_install = as.logical(Sys.getenv("CLAUDE_CODE_PLUGINS_ALLOW_INSTALL", "TRUE")),

  # Kaldırma izni
  allow_uninstall = as.logical(Sys.getenv("CLAUDE_CODE_PLUGINS_ALLOW_UNINSTALL", "TRUE")),

  # Plugin işlemleri için zaman aşımı (saniye)
  operation_timeout = as.integer(Sys.getenv("CLAUDE_CODE_PLUGINS_OPERATION_TIMEOUT", "120"))
)

# ------------------------------------------------------------------------------
# PLUGIN DURUM ETİKETLERİ (Türkçe)
# UI'da gösterilecek durum metinleri ve renkleri.
# ------------------------------------------------------------------------------

claude_code_plugin_status <- list(
  yuklu = list(
    metin = "Yüklü",
    renk  = "#81C784",
    ikon  = "check-circle"
  ),
  aktif = list(
    metin = "Aktif",
    renk  = "#64B5F6",
    ikon  = "toggle-on"
  ),
  pasif = list(
    metin = "Pasif",
    renk  = "#FFB74D",
    ikon  = "toggle-off"
  ),
  yukleniyor = list(
    metin = "Yükleniyor",
    renk  = "#90CAF9",
    ikon  = "spinner"
  ),
  hata = list(
    metin = "Hata",
    renk  = "#E57373",
    ikon  = "exclamation-triangle"
  ),
  mevcut_degil = list(
    metin = "Mevcut Değil",
    renk  = "#9E9E9E",
    ikon  = "question-circle"
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
# PLUGIN KATEGORI ETİKETLERİ
# Marketplace'te pluginleri kategorize etmek için kullanılır.
# ------------------------------------------------------------------------------

claude_code_plugin_kategoriler <- list(
  gelistirme   = list(etiket = "Geliştirme",      ikon = "code"),
  analiz       = list(etiket = "Analiz",           ikon = "chart-bar"),
  dokumantasyon = list(etiket = "Dokümantasyon",   ikon = "file-alt"),
  test         = list(etiket = "Test",             ikon = "vial"),
  tasarim      = list(etiket = "Tasarım",          ikon = "palette"),
  altyapi      = list(etiket = "Altyapı",          ikon = "server"),
  diger        = list(etiket = "Diğer",            ikon = "puzzle-piece")
)

# ------------------------------------------------------------------------------
# LOG ÖNEKİ
# ------------------------------------------------------------------------------
CLAUDE_CODE_PLUGINS_LOG_PREFIX <- "[Bilge Yolaç Eklentiler]"
