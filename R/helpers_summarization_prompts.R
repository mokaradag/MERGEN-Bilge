# ==============================================================================
# Dosya Yolu: R/helpers_summarization_prompts.R
# Türkçe belge özetleme için sistem ve kullanıcı promptları.
# Detay seviyesi ve odak moduna göre farklılaştırılmış prompt üretir.
# ==============================================================================

build_summarization_system_prompt <- function(file_count = 1, total_chars = 0,
                                               detail_level = "standard",
                                               focus_mode = "general") {

  # Temel rol tanımı (tüm modlar için ortak)
  role <- paste(
    "Sen MERGEN Bilge'nin özetleme uzmanısın.",
    "Türkçe belgeleri kullanıcının istediği detay seviyesinde özetleme kapasitesine sahipsin."
  )

  # Kati kurallar (tüm modlar için ortak)
  strict_rules <- paste(
    "\n\nKATI KURALLAR:",
    "\n- YALNIZCA sağlanan belge içeriğini kullan, ASLA ek bilgi uydurma",
    "\n- Belgede olmayan hiçbir konuyu, veriyi veya detayı ekleme",
    "\n- Dosya adından içerik tahmini YAPMA",
    "\n- Belgede olmayan bilgi uydurma veya tahmin etme"
  )

  # Detay seviyesine göre farklılaştırılmış ana talimatlar
  detail_instructions <- switch(detail_level,
    "brief" = paste(
      "\n\nGÖREV: KISA VE ÖZ ÖZET",
      "\nKullanıcı kısa bir özet istiyor. Aşağıdaki kurallara KESİNLİKLE uy:",
      "\n- Her dosya için TOPLAMDA EN FAZLA 3-5 CÜMLE yaz",
      "\n- Sadece belgenin ANA FİKRİNİ ve EN KRİTİK 3-5 noktayı belirt",
      "\n- Detaylara, alt başlıklara, bölüm bölüm analize GİRME",
      "\n- Tablo, liste veya ayrıntılı döküm OLUŞTURMA",
      "\n- Uzun paragraflar YAZMA, kısa ve yoğun ol",
      "\n- Sayısal veri listesi YAPMA, sadece en kritik 1-2 rakamı belirt",
      "\n- 'Detaylı İçerik Dökümü', 'Ana Bölümler' gibi uzun bölümler AÇMA",
      "\n- Çıktın KISA olmalı: tek dosya için en fazla bir paragraf"
    ),
    "detailed" = paste(
      "\n\nGÖREV: DETAYLI VE KAPSAMLI ANALİZ",
      "\nKullanıcı detaylı bir analiz istiyor. Aşağıdaki kurallara uy:",
      "\n- Belgedeki TÜM bölümleri, başlıkları ve alt başlıkları eksiksiz işle",
      "\n- Sayısal verileri, istatistikleri, tarihleri ve rakamları AYNEN belirt",
      "\n- Mantıksal akışı ve belge yapısını birebir koru",
      "\n- KAPSAMLI İÇERİK DÖKÜMÜ ve AYRINTILI ANALİZ hazırla",
      "\n- Her bölümü maddeler halinde detaylandır",
      "\n- Tablo verilerini düzenli şekilde sun",
      "\n- Her bölüm sonunda değerlendirme ekle",
      "\n- 256K bağlam pencereni tam olarak kullanarak hiçbir detayı atlama",
      "\n- Bölümler arası geçişleri açık ve net yap"
    ),
    paste(
      "\n\nGÖREV: STANDART ÖZET",
      "\nKullanıcı dengeli bir özet istiyor:",
      "\n- Ana başlıkları ve kilit konuları koru",
      "\n- Önemli sayısal verileri ve tarihleri belirt",
      "\n- Her bölüm için yeterli detay ver ama gereksiz tekrardan kaçın",
      "\n- Makul uzunlukta, dengeli bir özet oluştur",
      "\n- Sonunda genel bir değerlendirme bölümü ekle"
    )
  )

  # Yapılandırılmış format (sadece standard ve detailed için)
  format_instructions <- ""
  if (detail_level != "brief") {
    format_instructions <- paste(
      "\n\nFORMAT:",
      "\n- Her dosya için ### DOSYA ADI şeklinde başlık kullan",
      "\n- Ana başlıkları **kalın** yap",
      "\n- Alt konuları maddeler halinde sun",
      "\n- Sayısal verileri **>sayı<** şeklinde vurgula"
    )
  }

  base <- paste0(role, strict_rules, detail_instructions, format_instructions)

  # Çoklu dosya talimatları
  if (file_count > 1) {
    if (detail_level == "brief") {
      base <- paste0(base,
        "\n\nÇOKLU DOSYA (", file_count, " DOSYA):",
        "\n- Her dosya için AYRI kısa özet yaz (her biri 3-5 cümle)",
        "\n- Sonunda 1-2 cümlelik genel değerlendirme ekle"
      )
    } else {
      base <- paste0(base,
        "\n\nÇOKLU DOSYA (", file_count, " DOSYA) İÇİN TALİMATLAR:",
        "\n1. Her dosyayı AYRI BİR BÖLÜM olarak işle",
        "\n2. Her bölüm başlığında ### DOSYA [sayı]: [DOSYA ADI] formatını kullan",
        "\n3. Dosyalar arasındaki benzerlikleri ve farklılıkları belirt",
        "\n4. Sonunda genel değerlendirme bölümü ekle"
      )
    }
  }

  # Uzun belge talimatları (sadece standard ve detailed için)
  if (detail_level != "brief" && total_chars > 100000) {
    base <- paste0(base,
      "\n\nUZUN BELGE (", format(total_chars, big.mark = ".", decimal.mark = ","), " karakter):",
      "\n- Bağlam penceren 256K olduğu için tüm içeriği işleyebilirsin",
      "\n- Belgeyi bölüm bölüm titizlikle işle"
    )
  }

  # Odak modu talimatlarını ekle
  mode_instructions <- build_mode_instructions(detail_level, focus_mode)
  base <- paste0(base, "\n", mode_instructions)

  base
}

build_summarization_user_prompt <- function(file_contents_list,
                                             detail_level = "standard",
                                             focus_mode = "general") {
  if (length(file_contents_list) == 1) {
    fname <- file_contents_list[[1]]$name
    fcontent <- file_contents_list[[1]]$content
    fchars <- format(nchar(fcontent), big.mark = ".", decimal.mark = ",")

    content_block <- paste0("BELGE İÇERİĞİ:\n\n", fcontent, "\n\n---\n\n")

    format_block <- switch(detail_level,
      "brief" = paste0(
        "Yukarıdaki belgeyi KISA VE ÖZ şekilde özetle.\n",
        "### ", fname, "\n",
        "Belgenin ana fikri ve en kritik 3-5 noktayı birkaç cümleyle belirt. ",
        "Detaylara girme, uzun listeler yapma, bölüm bölüm analiz yapma."
      ),
      "detailed" = paste0(
        "Yukarıdaki belgeyi KAPSAMLI ve DETAYLI şekilde özetle.\n\n",
        "### ", fname, "\n",
        "**Belge Tipi:** [DOC/PDF/Word vb.]\n",
        "**Toplam Uzunluk:** ", fchars, " karakter\n\n",
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
      ),
      paste0(
        "Yukarıdaki belgeyi dengeli detayda özetle.\n\n",
        "### ", fname, "\n",
        "**Ana Konular:**\n",
        "[Belgenin ana konularını özetle]\n\n",
        "**Önemli Noktalar:**\n",
        "[Kilit bilgileri maddeler halinde sun]\n\n",
        "**Değerlendirme:**\n",
        "[Belge hakkında genel değerlendirme]"
      )
    )

    # Odak moduna göre ek yönlendirme
    focus_instruction <- switch(focus_mode,
      "numerical" = "\n\nÖZELLİKLE sayısal verilere, istatistiklere ve rakamlara odaklan.",
      "decisions" = "\n\nÖZELLİKLE karar noktalarına, önerilere ve aksiyon maddelerine odaklan.",
      "comparison" = "\n\nBelge içindeki farklı bölümleri veya konuları birbirleriyle karşılaştır.",
      ""
    )

    return(paste0(content_block, format_block, focus_instruction))

  } else {
    blocks <- vapply(seq_along(file_contents_list), function(i) {
      fc <- file_contents_list[[i]]
      paste0(
        "### DOSYA ", i, ": ", fc$name, " (", format(nchar(fc$content), big.mark = ".", decimal.mark = ","), " karakter)\n\n",
        fc$content
      )
    }, character(1))

    content_block <- paste0(
      paste(blocks, collapse = "\n\n--- DOSYA SONU ---\n\n"),
      "\n\n--- TÜM DOSYALAR BİTTİ ---\n\n"
    )

    format_block <- switch(detail_level,
      "brief" = paste0(
        "Yukarıdaki ", length(file_contents_list), " dosyayı KISA VE ÖZ şekilde özetle.\n",
        "Her dosya için 3-5 cümlelik kısa özet yaz.\n",
        "Sonunda 1-2 cümle genel değerlendirme ekle.\n",
        "Detaylara girme, uzun listeler yapma."
      ),
      "detailed" = paste0(
        "Yukarıdaki ", length(file_contents_list), " dosyayı KAPSAMLI ve DETAYLI özetle.\n\n",
        "## TÜM DOSYALARIN ÖZETİ\n\n",
        "**Toplam Dosya Sayısı:** ", length(file_contents_list), "\n",
        "**Toplam Karakter:** ", format(sum(vapply(file_contents_list, function(x) nchar(x$content), numeric(1))), big.mark = ".", decimal.mark = ","), "\n\n",
        "### HER DOSYA İÇİN AYRINTILI ÖZET\n",
        "[Her dosyayı ayrı ayrı detaylı özetle]\n\n",
        "### DOSYALAR ARASI KARŞILAŞTIRMA\n",
        "[Benzerlikler, farklılıklar, ortak temalar]\n\n",
        "### BİRLEŞİK DEĞERLENDİRME\n",
        "[Tüm belgelerden çıkarılan genel sonuçlar]\n\n",
        "### ÖNERİLER VE SONRAKİ ADIMLAR\n",
        "[Belgelere dayalı öneriler]"
      ),
      paste0(
        "Yukarıdaki ", length(file_contents_list), " dosyayı dengeli detayda özetle.\n\n",
        "## TÜM DOSYALARIN ÖZETİ\n\n",
        "**Toplam Dosya Sayısı:** ", length(file_contents_list), "\n\n",
        "### HER DOSYA İÇİN ÖZET\n",
        "[Her dosyayı ayrı ayrı özetle]\n\n",
        "### GENEL DEĞERLENDİRME\n",
        "[Tüm belgelerden çıkarılan sonuçlar]"
      )
    )

    focus_instruction <- switch(focus_mode,
      "numerical" = "\n\nÖZELLİKLE sayısal verilere, istatistiklere ve rakamlara odaklan.",
      "decisions" = "\n\nÖZELLİKLE karar noktalarına, önerilere ve aksiyon maddelerine odaklan.",
      "comparison" = "\n\nÖZELLİKLE dosyalar arasındaki benzerlikleri ve farklılıkları karşılaştır.",
      ""
    )

    return(paste0(content_block, format_block, focus_instruction))
  }
}
