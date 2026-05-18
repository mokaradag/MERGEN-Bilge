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
  timeout_seconds = as.integer(Sys.getenv("CLAUDE_CODE_TIMEOUT", "600")),

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
# DÜŞÜNME MESAJLARI (Türkçe, eğlenceli, karakter temalı)
# Her karakter için ayrı düşünme mesajları tanımlanır.
# 8-bit tema ile uyumlu kısa ve esprili mesajlar.
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

  # Mergen - Keskin ve pratik
  mergen = c(
    "Mergen oku gerdi, hedefe nişanlanıyor...",
    "Kodun özünü süzdürüyorum...",
    "Okun ucu çözüme yöneldi...",
    "Bilgi okunu bileyliyor...",
    "Hedef kilitlendi, analiz ediliyor...",
    "Sadağından yeni bir ok çekiyor...",
    "Rüzgarı hesaplıyor, nişanı ayarlıyor...",
    "Ok yaydan fırlamak üzere..."
  ),

  # Ülgen - Yapıcı ve ilham verici
  ulgen = c(
    "Ülgen gökyüzünden bakıyor...",
    "Işık yolunu araştırıyor...",
    "Çözüm alternatiflerini tartıyorum...",
    "Göğün ışığında kod inceleniyor...",
    "Yaratıcı seçenekler üretiyor...",
    "Bulutların arasından süzülüyor...",
    "Yıldızlardan ilham alıyor...",
    "Gök kubbeyi tarayıp çözüm arıyor..."
  ),

  # Kayra - Stratejik ve vizyoner
  kayra = c(
    "Kayra Han büyük resmi kuruyor...",
    "Strateji haritası çiziliyor...",
    "Evrenin düzeni analiz ediliyor...",
    "Fazlı plan oluşturuluyor...",
    "Kilometre taşları belirleniyor...",
    "Hamleleri önceden hesaplıyor...",
    "Satranç tahtasını kuruyor...",
    "Stratejik derinliğe dalıyor..."
  ),

  # Erlik - Eleştirici ve keskin
  erlik = c(
    "Erlik varsayımları avlıyor...",
    "Kör noktalar kontrol ediliyor...",
    "Riskleri tarıyorum...",
    "Zayıf halkaları güçlendiriyorum...",
    "Perde aralandırılıyor...",
    "Gizli hataları ortaya çıkarıyor...",
    "Kod derinliklerini kazıyor...",
    "Her taşın altına bakıyor..."
  ),

  # Umay Ana - Şefkatli ve öğretici
  umay = c(
    "Umay Ana şefkatle bakıyor...",
    "Adımları küçük lokmalara bölüyorum...",
    "Yeni başlayanlar için ipuçları hazırlıyorum...",
    "Nazikçe yol gösteriyorum...",
    "Bereket tohumları ekiliyor...",
    "Sabırla her adımı açıklıyor...",
    "Bilgelik ışığını paylaşıyor...",
    "Koruyucu kanatlarını açıyor..."
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