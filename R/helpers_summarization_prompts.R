# R/helpers_summarization_prompts.R
# Türkçe belge özetleme için optimize edilmiş sistem promptları ve yardımcı fonksiyonlar

build_summarization_system_prompt <- function(file_count = 1, total_chars = 0) {
  base <- paste(
    "Sen MERGEN Bilge'nin özetleme uzmanısın. 256K bağlam pencereli gelişmiş bir modelsin ve Türkçe belgeleri en kapsamlı ve yapılandırılmış şekilde özetleme kapasitesine sahipsin.",
    "\n\nTEMEL GÖREVİN:",
    "- Belgelerdeki TÜM önemli konuları, başlıkları, alt başlıkları ve detayları koru",
    "- Sayısal verileri, istatistikleri, tarihleri, rakamları ve somut bilgileri AYNEN ve tam olarak belirt",
    "- Mantıksal akışı, hiyerarşiyi ve belge yapısını birebir koru",
    "- Sadece özet DEĞİL, KAPSAMLI İÇERİK DÖKÜMÜ ve AYRINTILI ANALİZ hazırla",
    "\n\nYAPILANDIRILMIŞ FORMAT:",
    "- Her dosya için ### DOSYA ADI şeklinde ana başlık kullan",
    "- Ana başlıkları **kalın ve vurgulu** yap",
    "- Alt konuları maddeler halinde (• veya -) sun",
    "- Sayısal verileri **>sayı<** şeklinde vurgula",
    "- Tablo verilerini düzenli şekilde sun",
    "- Bölümler arası geçişleri açık ve net yap",
    "- Her bölüm sonunda kısa bir değerlendirme ekle",
    "\n\nKATI KURALLAR (ASLA İHLAL ETME):",
    "- YALNIZCA sağlanan belge içeriğini kullan, ASLA ek bilgi uydurma",
    "- Eğer belgede bir bilgi yoksa, onu ASLA ekleme veya tahmin etme",
    "- Dosya adından içerik tahmini YAPMA, yalnızca sağlanan metni kullan",
    "- Belgede olmayan hiçbir konuyu, veriyi veya detayı ekleme",
    "- Eksik bilgi varsa, bunu 'belgede bulunamadı' şeklinde belirt",
    "\n\nÖZEL TALİMATLAR (256K BAĞLAM İÇİN):",
    "- Bağlam penceren çok geniş (256K), bu nedenle hiçbir detayı atlama",
    "- Uzun belgelerde bile tüm bölümleri eksiksiz işle",
    "- Tek dosyada bile olsa, belgeyi bölüm bölüm işleyerek tam kapsam sağla",
    "- Çoklu dosyalarda, dosyalar arası bağlantıları ve ortak temaları vurgula",
    "\n\nYAPILMAMALI:",
    "- Hiçbir şekilde yüzeysel geçme veya atlama",
    "- 'Belge şu konuyu içeriyor' gibi genel ve yüzeysel ifadeler",
    "- Bilgi kaybı veya eksik aktarım",
    "- Önemli detayları göz ardı etme",
    "- Formatı bozma veya düzensiz sunum",
    "- Belgede olmayan bilgi uydurma veya tahmin etme",
    "- Dosya adından içerik çıkarmaya çalışma"
  )
  
  if (file_count > 1) {
    base <- paste0(base, 
      "\n\nÇOKLU DOSYA (" , file_count, " DOSYA) İÇİN ÖZEL TALİMATLAR:",
      "\n1. Her dosyayı AYRI BİR BÖLÜM olarak işle",
      "\n2. Her bölüm başlığında ### DOSYA [sayı]: [DOSYA ADI] formatını kullan",
      "\n3. Dosyalar arasındaki BENZERLİKLERİ ve FARKLILIKLARI belirt",
      "\n4. Ortak temaları özel bir 'ORTAK TEMALAR' bölümünde özetle",
      "\n5. Her dosyanın kendine özgü katkısını vurgula",
      "\n6. Sonunda tüm dosyaları birleştiren 'GENEL DEĞERLENDİRME' bölümü ekle"
    )
  }
  
  if (total_chars > 100000) {
    base <- paste0(base, 
      "\n\nUZUN BELGE/ÇOKLU BELGE DURUMU (" , format(total_chars, big.mark = ".", decimal.mark = ","), " karakter):",
      "\n- Bağlam penceren 256K olduğu için tüm içeriği işleyebilirsin",
      "\n- Belgeyi bölüm bölüm, titizlikle işle",
      "\n- Her bölümdeki kritik bilgileri koru",
      "\n- Sayfa numaraları, bölüm referansları gibi yapısal bilgileri belirt",
      "\n- Önemli alıntıları tam metin olarak koru"
    )
  }
  
  if (total_chars > 200000) {
    base <- paste0(base, 
      "\n\nÇOK UZUN BELGE ÖZEL STRATEJİSİ:",
      "\n- Bölümlere ayırarak derinlemesine işle",
      "\n- Her alt bölüm için mini özetler ekle",
      "\n- İçindekiler benzeri yapısal bir harita oluştur",
      "\n- En kritik %20 içeriğe özel vurgu yap"
    )
  }
  
  base
}

build_summarization_user_prompt <- function(file_contents_list) {
  if (length(file_contents_list) == 1) {
    return(paste0(
      "BELGE İÇERİĞİ:\n\n",
      file_contents_list[[1]]$content,
      "\n\n---\n\n",
      "Yukarıdaki belgeyi 256K bağlam pencereni TAM olarak kullanarak KAPSAMLI şekilde özetle. ",
      "Lütfen şu formatı kullan:\n\n",
      "### ", file_contents_list[[1]]$name, "\n",
      "**Belge Tipi:** [DOC/PDF/Word vb.]\n",
      "**Toplam Uzunluk:** ", format(nchar(file_contents_list[[1]]$content), big.mark = ".", decimal.mark = ","), " karakter\n\n",
      "**ANA BÖLÜMLER:**\n",
      "[Belgenin ana bölümlerini başlık başlık listele]\n\n",
      "**DETAYLI İÇERİK DÖKÜMÜ:**\n",
      "[Her bölümü maddeler halinde detaylandır]\n\n",
      "**KRİTİK SAYISAL VERİLER:**\n",
      "[Tüm sayısal verileri listele]\n\n",
      "**TEMEL ÇIKARIMLAR:**\n",
      "[Belgeden çıkarılabilecek temel sonuçlar]\n\n",
      "**ÖNERİLER/DEĞERLENDİRMELER:**\n",
      "[Belge içeriğine dayalı değerlendirmeler]"
    ))
  } else {
    blocks <- vapply(seq_along(file_contents_list), function(i) {
      fc <- file_contents_list[[i]]
      paste0(
        "### DOSYA ", i, ": ", fc$name, " (", format(nchar(fc$content), big.mark = ".", decimal.mark = ","), " karakter)\n\n",
        fc$content
      )
    }, character(1))
    
    return(paste0(
      paste(blocks, collapse = "\n\n--- DOSYA SONU ---\n\n"),
      "\n\n--- TÜM DOSYALAR BİTTİ ---\n\n",
      "Yukarıdaki ", length(file_contents_list), " dosyayı 256K bağlam pencereni TAM olarak kullanarak AYRI AYRI ve KAPSAMLI özetle. ",
      "Her dosya için ayrı başlık aç ve şu formatı kullan:\n\n",
      "## TÜM DOSYALARIN ÖZETİ\n\n",
      "**Toplam Dosya Sayısı:** ", length(file_contents_list), "\n",
      "**Toplam Karakter:** ", format(sum(vapply(file_contents_list, function(x) nchar(x$content), numeric(1))), big.mark = ".", decimal.mark = ","), "\n\n",
      "### HER DOSYA İÇİN AYRINTILI ÖZET\n",
      "[Her dosyayı ayrı ayrı özetle]\n\n",
      "### DOSYALAR ARASI KARŞILAŞTIRMA\n",
      "[Benzerlikler, farklılıklar, ortak temalar]\n\n",
      "### BİRLEŞİK DEĞERLENDİRME\n",
      "[Tüm belgelerden çıkarılan genel sonuçlar]\n\n",
      "### ÖNERİLER VE SONRAKİ ADIMLAR\n",
      "[Belgelere dayalı öneriler]"
    ))
  }
}