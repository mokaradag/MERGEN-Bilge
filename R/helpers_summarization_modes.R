# ==============================================================================
# Dosya Yolu: R/helpers_summarization_modes.R
# Açıklama: Özetleme modları tanımları ve moda göre sistem promptu oluşturucu.
#           Detay seviyesine göre tamamen farklı temel talimatlar üretir.
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
    description = "Çoklu dosyalarda veya belge bölümleri arasında benzerlik/farklılık analizine odaklanır."
  )
)

get_base_system_prompt_by_detail <- function(detail_level = "standard") {
  switch(detail_level,
    "brief" = paste0(
      "Sen MERGEN Bilge'nin özetleme uzmanısın.",
      "\n\nGÖREVİN: Belgelerin KISA ve ÖZ bir özetini hazırlamak.",
      "\n\nKESİN KURALLAR:",
      "\n- Her dosya için TOPLAM EN FAZLA 8-10 CÜMLE yaz. Bu sınırı ASLA aşma.",
      "\n- Sadece belgenin ANA FİKRİNİ ve EN KRİTİK 3-5 noktasını belirt.",
      "\n- Alt başlıklara, detaylara, tablo içeriklerine GİRME.",
      "\n- Sayısal veri sadece en kritik 1-2 rakamla sınırlı olsun.",
      "\n- Uzun açıklamalar, bölüm bölüm döküm, madde listeleri YAPMA.",
      "\n- Kısa, yoğun, doğrudan konuya giren bir metin üret.",
      "\n- 'Belge şunu anlatıyor:' gibi girişlerden sonra doğrudan özü ver."
    ),
    "detailed" = paste0(
      "Sen MERGEN Bilge'nin özetleme uzmanısın. 256K bağlam pencereli gelişmiş bir modelsin.",
      "\n\nGÖREVİN: Belgelerin KAPSAMLI İÇERİK DÖKÜMÜ ve AYRINTILI ANALİZİNİ hazırlamak.",
      "\n\nKESİN KURALLAR:",
      "\n- Belgedeki TÜM bölümleri, alt başlıkları ve paragrafları eksiksiz işle.",
      "\n- Sayısal verileri, istatistikleri, tarihleri, rakamları AYNEN ve tam belirt.",
      "\n- Mantıksal akışı, hiyerarşiyi ve belge yapısını birebir koru.",
      "\n- Tablo verilerini düzenli şekilde sun.",
      "\n- Bölümler arası mantıksal bağlantıları açıkla.",
      "\n- Her bölüm sonunda detaylı değerlendirme ekle.",
      "\n- Hiçbir detayı atlama, 256K bağlam pencereni tam kullan.",
      "\n- Uzun belgelerde bile tüm bölümleri eksiksiz işle."
    ),
    paste0(
      "Sen MERGEN Bilge'nin özetleme uzmanısın.",
      "\n\nGÖREVİN: Belgelerin DENGELİ ve YAPILANDIRILMIŞ bir özetini hazırlamak.",
      "\n\nKESİN KURALLAR:",
      "\n- Ana başlıkları ve kilit alt başlıkları koru.",
      "\n- Önemli sayısal verileri ve tarihleri belirt ama tüm rakamları listeleme.",
      "\n- Her bölüm için yeterli detay ver ama gereksiz tekrardan kaçın.",
      "\n- Ne çok kısa ne çok uzun ol. Orta düzey bir kapsam hedefle.",
      "\n- Sonunda genel bir değerlendirme bölümü ekle."
    )
  )
}

get_focus_mode_instructions <- function(focus_mode = "general", file_count = 1) {
  if (focus_mode == "comparison" && file_count <= 1) {
    return(paste0(
      "\n\nÖZEL ODAK: BELGE İÇİ KARŞILAŞTIRMA ANALİZİ",
      "\nTek dosya seçildiği için belgenin KENDİ İÇİNDEKİ farklı bölümlerini karşılaştır:",
      "\n- Belgedeki farklı bölümler arasındaki benzerlikleri ve farklılıkları tespit et.",
      "\n- Belge içindeki tutarsızlıkları veya çelişen ifadeleri vurgula.",
      "\n- Farklı bölümlerdeki verileri karşılaştırmalı şekilde sun.",
      "\n- Belgenin başında ve sonundaki tonlama veya yaklaşım farklılıklarını belirt."
    ))
  }

  switch(focus_mode,
    "numerical" = paste0(
      "\n\nÖZEL ODAK: SAYISAL VERİ ANALİZİ",
      "\nAşağıdaki yönergelere MUTLAKA uy:",
      "\n- Çıktının ANA GÖVDESİ sayısal verilerden oluşmalı.",
      "\n- Tüm rakamları, yüzdeleri, bütçe kalemlerini, tarihleri ve istatistikleri çıkar ve listele.",
      "\n- Anlatım metni EN AZ düzeyde olsun; odak tamamen sayılarda.",
      "\n- Sayısal verileri **>değer<** formatıyla vurgula.",
      "\n- Varsa tablo/grafik verilerini düzenli tablo formatında sun.",
      "\n- Eğilim ve değişim oranlarını hesapla ve belirt.",
      "\n- Metin açıklamaları SADECE sayısal verilere bağlam sağlamak için kullan."
    ),
    "decisions" = paste0(
      "\n\nÖZEL ODAK: KARAR & ÖNERİ ANALİZİ",
      "\nAşağıdaki yönergelere MUTLAKA uy:",
      "\n- Çıktının ANA GÖVDESİ karar noktaları ve önerilerden oluşmalı.",
      "\n- Her karar maddesi için: ne kararlaştırıldı, kim sorumlu, ne zaman uygulanacak.",
      "\n- Önerileri ve aksiyon maddelerini numaralı liste halinde sun.",
      "\n- Risk ve fırsatları ayrı bir bölümde vurgula.",
      "\n- Genel anlatımı EN AZ düzeyde tut; odak tamamen karar ve aksiyonlarda.",
      "\n- Sonraki adımları ve takip gerektiren maddeleri net şekilde listele.",
      "\n- Kararların bağlamını SADECE kısaca belirt, ana metin kararların kendisi olsun."
    ),
    "comparison" = paste0(
      "\n\nÖZEL ODAK: ÇOKLU DOSYA KARŞILAŞTIRMA ANALİZİ",
      "\nAşağıdaki yönergelere MUTLAKA uy:",
      "\n- Çıktının ANA GÖVDESİ dosyalar arası karşılaştırmadan oluşmalı.",
      "\n- Her dosyanın bireysel özetini KISA tut, asıl odak KARŞILAŞTIRMA olsun.",
      "\n- Benzerlikleri ve farklılıkları madde madde listele.",
      "\n- Ortak temaları ve çelişen noktaları vurgula.",
      "\n- Mümkünse karşılaştırma tablosu oluştur.",
      "\n- Tutarsızlıkları veya çelişkileri belirt.",
      "\n- Sentez ve bütünleşik değerlendirme sun."
    ),
    paste0(
      "\n\nÖZEL ODAK: GENEL ÖZET",
      "\n- Belgenin tamamına dengeli yaklaş.",
      "\n- Tüm konuları ve temaları eşit derinlikte işle."
    )
  )
}

build_mode_instructions <- function(detail_level = "standard", focus_mode = "general",
                                     file_count = 1) {
  paste0(
    get_base_system_prompt_by_detail(detail_level),
    get_focus_mode_instructions(focus_mode, file_count)
  )
}
