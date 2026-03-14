# ==============================================================================
# Dosya Yolu: R/config_claude_code.R
# Aciklama: Claude Code entegrasyonu icin yapilandirma sabitleri ve varsayilan
#           ayarlari tanimlar. API ucu noktalari, model listesi, zaman asimi
#           ve karakter temali dusunme mesajlari burada merkezi olarak yonetilir.
# ==============================================================================

# ------------------------------------------------------------------------------
# CLAUDE CODE YAPILANDIRMA SABiTLERi
# ------------------------------------------------------------------------------

# .Renviron dosyasindan Claude Code ayarlarini oku
claude_code_config <- list(
  # Claude Code CLI yolu (sunucuda kurulu olmalidir)
  cli_path = Sys.getenv("CLAUDE_CODE_CLI_PATH", "claude"),


  # Varsayilan calisma dizini (kullanici degistirebilir)
  default_workdir = Sys.getenv("CLAUDE_CODE_DEFAULT_WORKDIR", ""),

  # Maksimum istek suresi (saniye)
  timeout_seconds = as.integer(Sys.getenv("CLAUDE_CODE_TIMEOUT", "300")),

  # Maksimum token sayisi
  default_max_tokens = as.integer(Sys.getenv("CLAUDE_CODE_MAX_TOKENS", "4096")),

  # Varsayilan model
  default_model = Sys.getenv("CLAUDE_CODE_MODEL", ""),

  # Izin verilen maksimum es zamanli islem sayisi

  max_concurrent = as.integer(Sys.getenv("CLAUDE_CODE_MAX_CONCURRENT", "5")),

  # Oturum gecmisini sakla
  persist_sessions = as.logical(Sys.getenv("CLAUDE_CODE_PERSIST_SESSIONS", "TRUE"))
)

# ------------------------------------------------------------------------------
# DUSUNME MESAJLARI (Turkce, eglenceli, karakter temali)
# Her karakter icin ayri dusunme mesajlari tanimlanir.
# 8-bit tema ile uyumlu kisa ve esprili mesajlar.
# ------------------------------------------------------------------------------

claude_code_thinking_messages <- list(
  # Genel (karakter bagimsiz) mesajlar
  genel = c(
    "Kodlar arasinda geziniyor...",
    "Dosyalari taratiyor...",
    "Algoritma dokuyor...",
    "Satirlari cozumluyor...",
    "Bit ve baytlari harmanlatiyor...",
    "Fonksiyonlari birbirine baglatiyor...",
    "Degiskenleri takip ediyor...",
    "Derleme buyusu yapiyor...",
    "Hata ayiklama modunda...",
    "Kod ormaninda yol ariyor...",
    "Pikselleri hizaya getiriyor...",
    "Dongulerden gecis yapiyor...",
    "Veri akisini izliyor...",
    "Sozdizimini kontrol ediyor...",
    "Modulleri yukleniyor..."
  ),

  # Mergen - Keskin ve pratik
  mergen = c(
    "Mergen oku gerdi, hedefe nisanlaniyor...",
    "Kodun ozunu suzduruyorum...",
    "Okun ucu cozume yoneldi...",
    "Bilgi okunu bileyliyor...",
    "Hedef kilitlendi, analiz ediliyor..."
  ),

  # Ulgen - Yapici ve ilham verici
  ulgen = c(
    "Ulgen gokyuzunden bakiyor...",
    "Isik yolunu arasitiyor...",
    "Cozum alternatiflerini tartiyorum...",
    "Gogun isiginda kod inceleniyor...",
    "Yaratici secenekler uratiyor..."
  ),

  # Kayra - Stratejik ve vizyoner
  kayra = c(
    "Kayra Han buyuk resmi kuruyor...",
    "Strateji haritasi ciziliyor...",
    "Evrenin duzeni analiz ediliyor...",
    "Fazli plan olusturuluyor...",
    "Kilometre taslari belirleniyor..."
  ),

  # Erlik - Elestirici ve keskin
  erlik = c(
    "Erlik varsayimlari avliyor...",
    "Kor noktalar kontrol ediliyor...",
    "Riskleri tarayorum...",
    "Zayif halkalari guclandiriyorum...",
    "Perde aralandirilliyor..."
  ),

  # Umay Ana - Sefkatli ve ogretici
  umay = c(
    "Umay Ana sefkatle bakiyor...",
    "Adimlari kucuk lokmalara boluyorum...",
    "Yeni baslayanlar icin ipuclari hazirliyorum...",
    "Nazikce yol gosteriyorum...",
    "Bereket tohumlari ekiliyor..."
  )
)

# ------------------------------------------------------------------------------
# ON TANIMLI SENARYOLAR
# Kullanicilarin hizlica kullanabilecegi hazir komut sablonlari.
# ------------------------------------------------------------------------------

claude_code_scenarios <- list(
  list(
    id = "kod_inceleme",
    baslik = "Kod Inceleme",
    ikon = "search",
    aciklama = "Secilen dosya veya klasordeki kodu inceler ve iyilestirme onerileri sunar.",
    sablon = "Bu projedeki kodlari incele. Kod kalitesi, guvenlik ve performans acisindan iyilestirme onerileri sun."
  ),
  list(
    id = "hata_ayiklama",
    baslik = "Hata Ayiklama",
    ikon = "bug",
    aciklama = "Koddaki hatalari bulur ve cozum yollarini gosterir.",
    sablon = "Bu projedeki hatalari bul ve duzelt. Her hata icin aciklama ve cozum onerisi ver."
  ),
  list(
    id = "dokumantasyon",
    baslik = "Dokumantasyon",
    ikon = "file-alt",
    aciklama = "Proje icin dokumantasyon olusturur veya mevcut dokumantasyonu gunceller.",
    sablon = "Bu proje icin kapsamli bir dokumantasyon olustur. Dosya yapisi, fonksiyonlar ve kullanim kilavuzunu icersin."
  ),
  list(
    id = "test_yazimi",
    baslik = "Test Yazimi",
    ikon = "vial",
    aciklama = "Mevcut kod icin birim testleri olusturur.",
    sablon = "Bu projedeki ana fonksiyonlar icin birim testleri yaz. Kenar durumlarini da kapsasin."
  ),
  list(
    id = "refaktoring",
    baslik = "Kod Duzenleme",
    ikon = "broom",
    aciklama = "Kodu daha temiz ve surdurulebilir hale getirir.",
    sablon = "Bu koddaki tekrarlayan kisimlari, uzun fonksiyonlari ve karmasik yapilari sadelelestir."
  ),
  list(
    id = "serbest",
    baslik = "Serbest Komut",
    ikon = "terminal",
    aciklama = "Kendi komutunuzu yazarak Claude Code ile serbestce etkilesime gecin.",
    sablon = ""
  )
)

# ------------------------------------------------------------------------------
# LOG AYARLARI
# ------------------------------------------------------------------------------
CLAUDE_CODE_LOG_PREFIX <- "[Claude Code]"