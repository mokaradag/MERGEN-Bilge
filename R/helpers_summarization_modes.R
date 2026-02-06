# ==============================================================================
# Dosya Yolu: R/helpers_summarization_modes.R
# Özetleme modları tanımları ve moda göre sistem promptu oluşturucu
# ==============================================================================

SUMMARY_DETAIL_LEVELS <- list(
  brief = list(
    id = "brief",
    label = "Kısa Özet",
    description = "Belgenin ana fikrini ve kilit noktalarını kısa ve öz şekilde sunar."
  ),
  standard = list(
    id = "standard",
    label = "Standart",
    description = "Belgenin tüm önemli konularını dengeli detayda özetler."
  ),
  detailed = list(
    id = "detailed",
    label = "Detaylı",
    description = "Belgenin tüm bölümlerini ayrıntılı biçimde kapsamlı olarak analiz eder."
  )
)

SUMMARY_FOCUS_MODES <- list(
  general = list(
    id = "general",
    label = "Genel",
    description = "Belgenin tamamına yönelik dengeli bir özet sunar."
  ),
  numerical = list(
    id = "numerical",
    label = "Sayısal Veri",
    description = "Sayısal verilere, istatistiklere, tablolara ve rakamlara odaklanır."
  ),
  decisions = list(
    id = "decisions",
    label = "Karar & Öneri",
    description = "Karar noktalarına, önerilere ve aksiyon maddelerine odaklanır."
  ),
  comparison = list(
    id = "comparison",
    label = "Karşılaştırma",
    description = "Çoklu dosyalarda benzerlik/farklılık analizine odaklanır."
  )
)

get_detail_level_instructions <- function(detail_level = "standard") {
  switch(detail_level,
    "brief" = paste(
      "\n\n=== ZORUNLU: KISA ÖZET MODU ===",
      "\nBu talimat EN ÖNCELİKLİ talimattır ve diğer tüm talimatları geçersiz kılar.",
      "\nÇIKTI UZUNLUĞU SINIRI: Her dosya için EN FAZLA 3-5 CÜMLE.",
      "\nYASAKLAR:",
      "\n- Alt başlık, bölüm listesi, tablo OLUŞTURMA",
      "\n- 'Detaylı İçerik Dökümü', 'Ana Bölümler', 'Kritik Sayısal Veriler' gibi bölümler AÇMA",
      "\n- Madde madde uzun listeler YAPMA",
      "\n- Paragraflar halinde uzun analizler YAZMA",
      "\nYAPMAN GEREKEN: Belgenin özünü birkaç cümleyle aktar, hepsi bu."
    ),
    "detailed" = paste(
      "\n\n=== DETAYLI ANALİZ MODU ===",
      "\n- Belgedeki TÜM bölümleri eksiksiz ve derinlemesine işle",
      "\n- Her alt başlığı ve paragrafı ayrıntılı açıkla",
      "\n- Sayısal verileri, tarihleri, isimleri tam olarak belirt",
      "\n- Tablo verilerini düzenli şekilde sun",
      "\n- Bölümler arası mantıksal bağlantıları açıkla",
      "\n- Her bölüm sonunda detaylı değerlendirme ekle",
      "\n- Bağlam pencereni tam olarak kullanarak hiçbir detayı atlama"
    ),
    paste(
      "\n\n=== STANDART ÖZET MODU ===",
      "\n- Belgenin tüm önemli konularını dengeli detayda özetle",
      "\n- Ana başlıkları ve kilit alt başlıkları koru",
      "\n- Önemli sayısal verileri ve tarihleri belirt",
      "\n- Gereksiz tekrardan kaçın, orta uzunlukta bir çıktı üret",
      "\n- Sonunda genel bir değerlendirme bölümü ekle"
    )
  )
}

get_focus_mode_instructions <- function(focus_mode = "general") {
  switch(focus_mode,
    "numerical" = paste(
      "\n\n=== ODAK: SAYISAL VERİ ANALİZİ ===",
      "\nBu özetin ASIL AMACI sayısal verileri ön plana çıkarmaktır.",
      "\n- Metinsel açıklamaları KISALT, sayısal verilere AĞIRLIK VER",
      "\n- Tüm rakamları, yüzdeleri, bütçe kalemlerini, istatistikleri listele",
      "\n- Tablo ve grafik verilerini düzenli sun",
      "\n- Karşılaştırmalı verileri yan yana göster",
      "\n- Eğilim ve değişim oranlarını belirt",
      "\n- Sayısal veri içermeyen bölümleri KISA GEÇ"
    ),
    "decisions" = paste(
      "\n\n=== ODAK: KARAR & ÖNERİ ANALİZİ ===",
      "\nBu özetin ASIL AMACI karar ve önerileri çıkarmaktır.",
      "\n- Genel bilgileri KISALT, karar noktalarına AĞIRLIK VER",
      "\n- Alınan kararları net şekilde listele",
      "\n- Önerileri ve aksiyon maddelerini madde madde sun",
      "\n- Sorumluluk atamalarını ve zaman çizelgelerini belirt",
      "\n- Risk ve fırsatları ayrı ayrı listele",
      "\n- Sonraki adımları ve takip gerektiren maddeleri vurgula",
      "\n- Karar/öneri içermeyen bölümleri KISA GEÇ"
    ),
    "comparison" = paste(
      "\n\n=== ODAK: KARŞILAŞTIRMA ANALİZİ ===",
      "\nBu özetin ASIL AMACI karşılaştırma yapmaktır.",
      "\n- Her konuyu bağımsız özetlemek yerine KARŞILAŞTIRMALI sun",
      "\n- Benzerlikleri ve farklılıkları NET şekilde ayır",
      "\n- Ortak temaları ve çelişen noktaları vurgula",
      "\n- Mümkünse karşılaştırma tablosu oluştur",
      "\n- Tutarsızlıkları veya çelişkileri belirt",
      "\n- Sentez ve bütünleşik değerlendirme sun"
    ),
    paste(
      "\n\n=== ODAK: GENEL ===",
      "\n- Belgenin tamamına dengeli yaklaş",
      "\n- Tüm konuları eşit derinlikte işle",
      "\n- Hem nitel hem nicel bilgileri koru"
    )
  )
}

build_mode_instructions <- function(detail_level = "standard", focus_mode = "general") {
  paste0(
    get_detail_level_instructions(detail_level),
    "\n",
    get_focus_mode_instructions(focus_mode)
  )
}
