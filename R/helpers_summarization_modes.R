# ==============================================================================
# Dosya Yolu: R/helpers_summarization_modes.R
# Açıklama: Özetleme modları tanımları ve moda göre sistem promptu oluşturucu
# ==============================================================================

# Detay seviyesi tanımları
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

# Odak modu tanımları
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

# Detay seviyesine göre prompt talimatları
get_detail_level_instructions <- function(detail_level = "standard") {
  switch(detail_level,
    "brief" = paste(
      "\nDETAY SEVİYESİ: KISA ÖZET",
      "\n- Belgenin ana fikrini 2-3 cümleyle özetle",
      "\n- En kritik 3-5 maddeyi listele",
      "\n- Detaylara girme, sadece üst düzey bilgi ver",
      "\n- Toplam çıktı kısa ve yoğun olsun",
      "\n- Her dosya için en fazla birkaç paragraf yaz"
    ),
    "detailed" = paste(
      "\nDETAY SEVİYESİ: DETAYLI ANALİZ",
      "\n- Belgedeki TÜM bölümleri eksiksiz işle",
      "\n- Her alt başlığı ve paragrafı detaylandır",
      "\n- Sayısal verileri, tarihleri, isimleri tam olarak belirt",
      "\n- Tablo verilerini düzenli şekilde sun",
      "\n- Bölümler arası mantıksal bağlantıları açıkla",
      "\n- Her bölüm sonunda detaylı değerlendirme ekle",
      "\n- Bağlam pencereni tam olarak kullanarak hiçbir detayı atlama"
    ),
    paste(
      "\nDETAY SEVİYESİ: STANDART",
      "\n- Belgenin tüm önemli konularını dengeli detayda özetle",
      "\n- Ana başlıkları ve kilit alt başlıkları koru",
      "\n- Önemli sayısal verileri ve tarihleri belirt",
      "\n- Her bölüm için yeterli detay ver ama gereksiz tekrardan kaçın",
      "\n- Sonunda genel bir değerlendirme bölümü ekle"
    )
  )
}

# Odak moduna göre prompt talimatları
get_focus_mode_instructions <- function(focus_mode = "general") {
  switch(focus_mode,
    "numerical" = paste(
      "\nÖZEL ODAK: SAYISAL VERİ ANALİZİ",
      "\n- Tüm sayısal verileri, istatistikleri ve rakamları öne çıkar",
      "\n- Tablo ve grafik verilerini düzenli listele",
      "\n- Yüzdeleri, büyüme oranlarını, bütçe kalemlerini vurgula",
      "\n- Sayısal verileri **>değer<** formatıyla işaretle",
      "\n- Karşılaştırmalı verileri yan yana sun",
      "\n- Eğilim ve değişim oranlarını belirt"
    ),
    "decisions" = paste(
      "\nÖZEL ODAK: KARAR & ÖNERİ ANALİZİ",
      "\n- Karar noktalarını ve alınan kararları öne çıkar",
      "\n- Önerileri ve aksiyon maddelerini listele",
      "\n- Sorumluluk atamalarını ve zaman çizelgelerini belirt",
      "\n- Risk ve fırsatları vurgula",
      "\n- Her karar için bağlam ve gerekçeyi kısaca açıkla",
      "\n- Sonraki adımları ve takip gerektiren maddeleri listele"
    ),
    "comparison" = paste(
      "\nÖZEL ODAK: KARŞILAŞTIRMA ANALİZİ",
      "\n- Dosyalar/bölümler arası benzerlikleri tespit et",
      "\n- Farklılıkları net şekilde karşılaştır",
      "\n- Ortak temaları ve çelişen noktaları vurgula",
      "\n- Karşılaştırma tabloları oluştur",
      "\n- Tutarsızlıkları veya çelişkileri belirt",
      "\n- Sentez ve bütünleşik değerlendirme sun"
    ),
    paste(
      "\nÖZEL ODAK: GENEL ÖZET",
      "\n- Belgenin tamamına dengeli yaklaş",
      "\n- Tüm konuları ve temaları eşit derinlikte işle",
      "\n- Hem nitel hem nicel bilgileri koru"
    )
  )
}

# Mod bilgilerini birleştirerek ek prompt talimatı oluştur
build_mode_instructions <- function(detail_level = "standard", focus_mode = "general") {
  paste0(
    get_detail_level_instructions(detail_level),
    "\n",
    get_focus_mode_instructions(focus_mode)
  )
}
