# ==============================================================================
# Dosya Yolu: R/config_claude_code.R
# Açıklama: Claude Code entegrasyonu için yapılandırma sabitleri ve varsayılan
#           ayarları tanımlar. API ucu noktaları, model katmanları, zaman aşımı
#           ve karakter temalı düşünme mesajları burada merkezi olarak yönetilir.
# ==============================================================================

# ------------------------------------------------------------------------------
# CLAUDE CODE YAPILANDIRMA SABİTLERİ
# ------------------------------------------------------------------------------

# .Renviron dosyasından Claude Code ayarlarını oku
claude_code_config <- list(
  # Claude Code CLI yolu (boş ise otomatik tespit edilir)
  cli_path = Sys.getenv("CLAUDE_CODE_CLI_PATH", ""),

  # Varsayılan çalışma dizini (kullanıcı değiştirebilir)
  default_workdir = Sys.getenv("CLAUDE_CODE_DEFAULT_WORKDIR", ""),

  # Maksimum istek süresi (saniye)
  timeout_seconds = as.integer(Sys.getenv("CLAUDE_CODE_TIMEOUT", "14400")),

  # Varsayılan model (boş ise settings.json'dan okunur)
  default_model = Sys.getenv("CLAUDE_CODE_MODEL", ""),

  # İzin verilen maksimum eş zamanlı işlem sayısı
  max_concurrent = as.integer(Sys.getenv("CLAUDE_CODE_MAX_CONCURRENT", "5")),

  # Oturum geçmişini sakla
  persist_sessions = as.logical(Sys.getenv("CLAUDE_CODE_PERSIST_SESSIONS", "TRUE")),

  # Tehlikeli izin atlama yalnızca açık yönetici/geliştirme onayıyla etkinleşir
  allow_dangerous_permissions = as.logical(Sys.getenv(
    "CLAUDE_CODE_ALLOW_DANGEROUS_PERMISSIONS",
    "FALSE"
  )),

  # Claude Code izin modu.
  # acceptEdits: kullanıcı zaten komutu verdiğinde dosya yazma/düzenleme için
  # tekrar tekrar onay sormaz; dangerous skip değildir.
  permission_mode = Sys.getenv("CLAUDE_CODE_PERMISSION_MODE", "acceptEdits"),

  # Ek izin istemeden kullanılabilecek Claude Code araçları.
  # MERGEN Bilge kurumsal/on-prem ortamda çalıştığı için Bash dahil tüm
  # standart araçlar varsayılan olarak izinlidir. Böylece model gerçek
  # zamanlı kabuk komutu çalıştırabilir ve ARAÇ KULLANIMLARI sayacı
  # gerçek araç kullanımlarını yansıtır. Kapatmak için .Renviron'da
  # CLAUDE_CODE_ALLOWED_TOOLS değerini istenen alt küme ile geçersiz kılın.
  allowed_tools = Sys.getenv(
    "CLAUDE_CODE_ALLOWED_TOOLS",
    "Read;Write;Edit;MultiEdit;Glob;Grep;LS;Bash"
  ),

  # Açıkça yasaklanacak Claude Code araçları.
  disallowed_tools = Sys.getenv("CLAUDE_CODE_DISALLOWED_TOOLS", ""),

  # Bilge Yolaç'ın çalışabileceği kök dizinler (; veya satır sonu ile ayrılır)
  allowed_workdir_roots = Sys.getenv("CLAUDE_CODE_ALLOWED_WORKDIR_ROOTS", ""),

  # Kullanıcının UI'da açıkça seçtiği mevcut çalışma dizinini bu çalışma için onayla
  allow_user_selected_workdirs = as.logical(Sys.getenv(
    "CLAUDE_CODE_ALLOW_USER_SELECTED_WORKDIRS",
    "TRUE"
  )),

  # İndirilebilir hale getirilecek çıktıların kabul edildiği kök dizinler
  allowed_output_roots = Sys.getenv("CLAUDE_CODE_ALLOWED_OUTPUT_ROOTS", "")
)

# ------------------------------------------------------------------------------
# BÜYÜK KLASÖR / EŞZAMANLILIK SINIRLARI
# Bilge Yolaç bir çalıştırmayı hazırlarken kaynak klasörün tamamını asla
# kopyalamaz ve asla sınırsız taramaz. Aşağıdaki sınırlar hem preflight
# taramasını hem de girdi/çıktı aktarımını çerçeveler. Tümü .Renviron
# üzerinden geçersiz kılınabilir.
# ------------------------------------------------------------------------------

.cc_limit_num <- function(env_name, default_value) {
  ham <- Sys.getenv(env_name, "")
  if (!nzchar(ham)) return(default_value)

  deger <- suppressWarnings(as.numeric(ham))
  if (length(deger) != 1L || is.na(deger) || deger < 0) {
    return(default_value)
  }

  deger
}

claude_code_runtime_limits <- list(
  # Preflight taraması (kaynak klasörün güvenli sınırlar içinde olup olmadığı)
  scan_max_files = .cc_limit_num("CLAUDE_CODE_SCAN_MAX_FILES", 2000),
  scan_max_dirs = .cc_limit_num("CLAUDE_CODE_SCAN_MAX_DIRS", 500),
  scan_max_depth = .cc_limit_num("CLAUDE_CODE_SCAN_MAX_DEPTH", 6),
  scan_max_total_bytes = .cc_limit_num(
    "CLAUDE_CODE_SCAN_MAX_TOTAL_MB", 512
  ) * 1024^2,
  scan_timeout_ms = .cc_limit_num("CLAUDE_CODE_SCAN_TIMEOUT_MS", 4000),

  # "Bu klasör güvenli sınırların dışında" kararının eşikleri
  preflight_max_files = .cc_limit_num("CLAUDE_CODE_PREFLIGHT_MAX_FILES", 1500),
  preflight_max_dirs = .cc_limit_num("CLAUDE_CODE_PREFLIGHT_MAX_DIRS", 400),
  preflight_max_total_bytes = .cc_limit_num(
    "CLAUDE_CODE_PREFLIGHT_MAX_TOTAL_MB", 256
  ) * 1024^2,

  # Runtime input klasörüne kopyalanacak dosya sınırları
  max_input_files = .cc_limit_num("CLAUDE_CODE_MAX_INPUT_FILES", 40),
  max_input_file_bytes = .cc_limit_num(
    "CLAUDE_CODE_MAX_INPUT_FILE_MB", 25
  ) * 1024^2,
  max_input_total_bytes = .cc_limit_num(
    "CLAUDE_CODE_MAX_INPUT_TOTAL_MB", 100
  ) * 1024^2,

  # Prompt hiçbir dosyayı işaret etmediğinde otomatik seçilecek üst sınır
  auto_select_max_files = .cc_limit_num("CLAUDE_CODE_AUTO_SELECT_MAX_FILES", 25),

  # Çıktı tarama / geri senkron sınırları
  output_scan_max_files = .cc_limit_num("CLAUDE_CODE_OUTPUT_SCAN_MAX_FILES", 1000),
  output_scan_max_depth = .cc_limit_num("CLAUDE_CODE_OUTPUT_SCAN_MAX_DEPTH", 8),
  max_output_file_bytes = .cc_limit_num(
    "CLAUDE_CODE_MAX_OUTPUT_FILE_MB", 100
  ) * 1024^2,
  max_output_total_bytes = .cc_limit_num(
    "CLAUDE_CODE_MAX_OUTPUT_TOTAL_MB", 400
  ) * 1024^2,

  # Doküman hazırlama sınırları
  max_documents = .cc_limit_num("CLAUDE_CODE_MAX_DOCUMENTS", 10),
  max_document_bytes = .cc_limit_num(
    "CLAUDE_CODE_MAX_DOCUMENT_MB", 25
  ) * 1024^2,
  max_documents_total_bytes = .cc_limit_num(
    "CLAUDE_CODE_MAX_DOCUMENTS_TOTAL_MB", 80
  ) * 1024^2,

  # Arka plan hazırlık zaman aşımı ve dosya kararlılık beklemesi
  prepare_timeout_sec = .cc_limit_num("CLAUDE_CODE_PREPARE_TIMEOUT_SEC", 180),
  file_settle_total_ms = .cc_limit_num("CLAUDE_CODE_FILE_SETTLE_TOTAL_MS", 1200),

  # Eski runtime / doküman destek klasörlerinin saklanma süresi (saniye)
  runtime_retention_sec = .cc_limit_num("CLAUDE_CODE_RUNTIME_RETENTION_SEC", 21600)
)

#' Bilge Yolaç çalışma zamanı sınırını güvenli biçimde okur
#'
#' @param name Sınır adı
#' @param default_value Sınır tanımlı değilse dönecek değer
#' @param limits Sınır listesi (varsayılan: claude_code_runtime_limits)
#' @return Sayısal sınır değeri
cc_runtime_limit <- function(name, default_value = Inf, limits = NULL) {
  if (is.null(limits)) {
    limits <- tryCatch(
      get("claude_code_runtime_limits", inherits = TRUE),
      error = function(e) list()
    )
  }

  deger <- tryCatch(limits[[name]], error = function(e) NULL)
  deger <- suppressWarnings(as.numeric(deger[1]))

  if (length(deger) != 1L || is.na(deger)) {
    return(default_value)
  }

  deger
}

# ------------------------------------------------------------------------------
# MODEL KATMANLARI
# settings.json'daki teknik model adları yerine kullanıcı dostu Türkçe
# etiketler gösterilir. Sıralama bu listedeki sıraya göre yapılır.
# ------------------------------------------------------------------------------

claude_code_model_tiers <- list(
  list(
    etiket   = "Hızlı",
    ikon     = "fa-bolt",
    ikon_unicode = "\u26A1",
    aciklama = "Hızlı yanıt, basit görevler için",
    anahtar_deseni = "HAIKU"
  ),
  list(
    etiket   = "Dengeli",
    ikon     = "fa-balance-scale",
    ikon_unicode = "\u2694",
    aciklama = "Hız ve kalite dengesi",
    anahtar_deseni = "SONNET"
  ),
  list(
    etiket   = "Güçlü",
    ikon     = "fa-brain",
    ikon_unicode = "\u2B50",
    aciklama = "Karmaşık görevler için en güçlü model",
    anahtar_deseni = "OPUS"
  )
)

# Varsayılan etiketleri
claude_code_varsayilan_etiket <- "Varsayılan"

# ------------------------------------------------------------------------------
# DÜŞÜNME MESAJLARI (Türkçe, persona temalı)
# Her persona için ayrı düşünme mesajları tanımlanır.
# 8-bit tema ile uyumlu kısa ve canlı mesajlar.
# ------------------------------------------------------------------------------

claude_code_thinking_messages <- list(
  # Genel (karakter bağımsız) mesajlar
  genel = c(
    "Kodlar arasında geziniyor...",
    "Dosyaları tarıyor...",
    "Algoritma dokuyor...",
    "Satırları çözümlüyor...",
    "Bit ve baytları harmanlıyor...",
    "Fonksiyonları birbirine bağlıyor...",
    "Değişkenleri takip ediyor...",
    "Derleme büyüsü yapıyor...",
    "Hata ayıklama modunda...",
    "Kod ormanında yol arıyor...",
    "Pikselleri hizaya getiriyor...",
    "Döngülerden geçiş yapıyor...",
    "Veri akışını izliyor...",
    "Sözdizimini kontrol ediyor...",
    "Modülleri yüklüyor...",
    "Bağımlılıkları çözüyor...",
    "Dallanma noktalarını inceliyor...",
    "İfadeleri ayrıştırıyor...",
    "Bellek haritasını okuyor...",
    "Yığın izini takip ediyor..."
  ),

  # Emre - Ana Asistan (dengeli ve pratik)
  emre = c(
    "Önce konuyu berraklaştırıyorum...",
    "Net bir özet hazırlıyorum...",
    "Uygulanabilir adımları sıralıyorum...",
    "Dengeli bir plan kuruyorum...",
    "Çözümü sadeleştiriyorum...",
    "Pratik yolu seçiyorum...",
    "Önceliği belirliyorum...",
    "Sonucu derleyip topluyorum..."
  ),

  # Selin - Yapıcı Uzman (çözüm odaklı)
  selin = c(
    "Sorunu doğru çerçeveye oturtuyorum...",
    "Seçenekleri tek tek çıkarıyorum...",
    "Artıları ve eksileri tartıyorum...",
    "En pratik çözümü arıyorum...",
    "Yapıcı bir yol öneriyorum...",
    "Alternatifleri kıyaslıyorum...",
    "Uygulama adımlarını netleştiriyorum...",
    "Çözüm taslağını hazırlıyorum..."
  ),

  # Deniz - Stratejist (uzun vadeli ve yapısal)
  deniz = c(
    "Büyük resmi kuruyorum...",
    "Hedefleri ve ilkeleri hizalıyorum...",
    "Karar matrisini çiziyorum...",
    "Yol haritasını fazlara bölüyorum...",
    "Riskleri ve seçenekleri tartıyorum...",
    "Kilometre taşlarını belirliyorum...",
    "Uzun vadeli planı oturtuyorum...",
    "Önceliklendirme yapıyorum..."
  ),

  # Can - Eleştirel Eş (risk ve varsayım odaklı)
  can = c(
    "Varsayımları görünür kılıyorum...",
    "Riskleri tarıyorum...",
    "Zayıf noktaları kontrol ediyorum...",
    "Karşı örnekleri düşünüyorum...",
    "Eksik verileri işaretliyorum...",
    "Doğrulama listesi hazırlıyorum...",
    "Kararı sağlamlaştırıyorum...",
    "Kanıtları gözden geçiriyorum..."
  ),

  # İpek - Rehber (sade ve öğretici)
  ipek = c(
    "Konuyu küçük adımlara bölüyorum...",
    "Sade bir anlatım hazırlıyorum...",
    "Örnekleri derliyorum...",
    "Sık yapılan hataları not ediyorum...",
    "Adım adım rehberi kuruyorum...",
    "Anlaşılır bir dil seçiyorum...",
    "Yeni başlayanlar için sadeleştiriyorum...",
    "Yol gösterici ipuçları ekliyorum..."
  )
)

# ------------------------------------------------------------------------------
# ÖN TANIMLI SENARYOLAR
# Kullanıcıların hızlıca kullanabileceği hazır komut şablonları.
# ------------------------------------------------------------------------------

claude_code_scenarios <- list(
  list(
    id = "kod_inceleme",
    baslik = "Kod İnceleme",
    ikon = "search",
    aciklama = "Seçilen dosya veya klasördeki kodu inceler ve iyileştirme önerileri sunar.",
    sablon = "Bu projedeki kodları incele. Kod kalitesi, güvenlik ve performans açısından iyileştirme önerileri sun."
  ),
  list(
    id = "hata_ayiklama",
    baslik = "Hata Ayıklama",
    ikon = "bug",
    aciklama = "Koddaki hataları bulur ve çözüm yollarını gösterir.",
    sablon = "Bu projedeki hataları bul ve düzelt. Her hata için açıklama ve çözüm önerisi ver."
  ),
  list(
    id = "dokumantasyon",
    baslik = "Dokümantasyon",
    ikon = "file-alt",
    aciklama = "Proje için dokümantasyon oluşturur veya mevcut dokümantasyonu günceller.",
    sablon = "Bu proje için kapsamlı bir dokümantasyon oluştur. Dosya yapısı, fonksiyonlar ve kullanım kılavuzunu içersin."
  ),
  list(
    id = "test_yazimi",
    baslik = "Test Yazımı",
    ikon = "vial",
    aciklama = "Mevcut kod için birim testleri oluşturur.",
    sablon = "Bu projedeki ana fonksiyonlar için birim testleri yaz. Kenar durumlarını da kapsasın."
  ),
  list(
    id = "refaktoring",
    baslik = "Kod Düzenleme",
    ikon = "broom",
    aciklama = "Kodu daha temiz ve sürdürülebilir hale getirir.",
    sablon = "Bu koddaki tekrarlayan kısımları, uzun fonksiyonları ve karmaşık yapıları sadeleştir."
  ),
  list(
    id = "serbest",
    baslik = "Serbest Komut",
    ikon = "terminal",
    aciklama = "Kendi komutunuzu yazarak Claude Code ile serbestçe etkileşime geçin.",
    sablon = ""
  )
)

# ------------------------------------------------------------------------------
# DURUM ÇUBUĞU DURUMLAR VE RENKLERİ
# Durum çubuğundaki metin ve renk eşleştirmeleri
# ------------------------------------------------------------------------------

claude_code_status_styles <- list(
  hazir       = list(metin = "Hazır",        renk = "#81C784", ikon = "circle"),
  calisiyor   = list(metin = "Çalışıyor",    renk = "#64B5F6", ikon = "spinner"),
  tamamlandi  = list(metin = "Tamamlandı",   renk = "#81C784", ikon = "check-circle"),
  hata        = list(metin = "Hata",         renk = "#E57373", ikon = "exclamation-triangle"),
  zaman_asimi = list(metin = "Zaman Aşımı",  renk = "#FFB74D", ikon = "clock"),
  bagli       = list(metin = "Bağlı",        renk = "#81C784", ikon = "check-circle"),
  bagli_degil = list(metin = "Bağlantı Yok", renk = "#E57373", ikon = "times-circle"),
  kontrol     = list(metin = "Kontrol Edilmedi", renk = "#9E9E9E", ikon = "question-circle")
)

# ------------------------------------------------------------------------------
# CANLI AKIŞ AYARLARI
# Kabuk komutları ve araç kullanımlarının gerçek zamanlı görüntülenmesi için.
# ------------------------------------------------------------------------------
claude_code_streaming_config <- list(
  # Akış yoklama aralığı (milisaniye) - processx çıktı okuma sıklığı
  poll_interval_ms = 200L,

  # Dosya önizleme satır sınırı (yazılan dosyaların ilk N satırı gösterilir)
  file_preview_lines = 10L,

  # Araç sonucu kısaltma karakter sınırı
  result_truncate_chars = 1000L,

  # Kabuk komutları varsayılan olarak görünür mü
  shell_visible_default = TRUE
)

# ------------------------------------------------------------------------------
# LOG AYARLARI
# ------------------------------------------------------------------------------
CLAUDE_CODE_LOG_PREFIX <- "[Bilge Yolaç]"