# ==============================================================================
# Dosya Yolu: R/config_claude_code.R
# Açıklama: Claude Code entegrasyonu için yapılandırma sabitleri ve varsayılan
#           ayarları tanımlar. API ucu noktaları, model listesi, zaman aşımı
#           ve karakter temalı düşünme mesajları burada merkezi olarak yönetilir.
# ==============================================================================

# ------------------------------------------------------------------------------
# CLAUDE CODE YAPILANDIRMA SABİTLERİ
# ------------------------------------------------------------------------------

# .Renviron dosyasından Claude Code ayarlarını oku
claude_code_config <- list(
  # Claude Code CLI yolu (bos ise otomatik tespit edilir)
  cli_path = Sys.getenv("CLAUDE_CODE_CLI_PATH", ""),

  # Varsayılan çalışma dizini (kullanıcı değiştirebilir)
  default_workdir = Sys.getenv("CLAUDE_CODE_DEFAULT_WORKDIR", ""),

  # Maksimum istek süresi (saniye)
  timeout_seconds = as.integer(Sys.getenv("CLAUDE_CODE_TIMEOUT", "300")),

  # Varsayilan model (bos ise settings.json'dan okunur)
  default_model = Sys.getenv("CLAUDE_CODE_MODEL", ""),

  # Izin verilen maksimum es zamanli islem sayisi
  max_concurrent = as.integer(Sys.getenv("CLAUDE_CODE_MAX_CONCURRENT", "5")),

  # Oturum geçmişini sakla
  persist_sessions = as.logical(Sys.getenv("CLAUDE_CODE_PERSIST_SESSIONS", "TRUE"))
)

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
    "Bit ve baytları harmanlatıyor...",
    "Fonksiyonları birbirine bağlatıyor...",
    "Değişkenleri takip ediyor...",
    "Derleme büyüsü yapıyor...",
    "Hata ayıklama modunda...",
    "Kod ormanında yol arıyor...",
    "Pikselleri hizaya getiriyor...",
    "Döngülerden geçiş yapıyor...",
    "Veri akışını izliyor...",
    "Sözdizimini kontrol ediyor...",
    "Modülleri yükleniyor..."
  ),

  # Mergen - Keskin ve pratik
  mergen = c(
    "Mergen oku gerdi, hedefe nişanlanıyor...",
    "Kodun özünü süzdürüyorum...",
    "Okun ucu çözüme yöneldi...",
    "Bilgi okunu bileyliyor...",
    "Hedef kilitlendi, analiz ediliyor..."
  ),

  # Ülgen - Yapıcı ve ilham verici
  ulgen = c(
    "Ülgen gökyüzünden bakıyor...",
    "Işık yolunu araştırıyor...",
    "Çözüm alternatiflerini tartıyorum...",
    "Göğün ışığında kod inceleniyor...",
    "Yaratıcı seçenekler üretiyor..."
  ),

  # Kayra - Stratejik ve vizyoner
  kayra = c(
    "Kayra Han büyük resmi kuruyor...",
    "Strateji haritası çiziliyor...",
    "Evrenin düzeni analiz ediliyor...",
    "Fazlı plan oluşturuluyor...",
    "Kilometre taşları belirleniyor..."
  ),

  # Erlik - Eleştirici ve keskin
  erlik = c(
    "Erlik varsayımları avlıyor...",
    "Kör noktalar kontrol ediliyor...",
    "Riskleri tarıyorum...",
    "Zayıf halkaları güçlendiriyorum...",
    "Perde aralandırılıyor..."
  ),

  # Umay Ana - Şefkatli ve öğretici
  umay = c(
    "Umay Ana şefkatle bakıyor...",
    "Adımları küçük lokmalara bölüyorum...",
    "Yeni başlayanlar için ipuçları hazırlıyorum...",
    "Nazikçe yol gösteriyorum...",
    "Bereket tohumları ekiliyor..."
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
# LOG AYARLARI
# ------------------------------------------------------------------------------
CLAUDE_CODE_LOG_PREFIX <- "[Claude Code]"