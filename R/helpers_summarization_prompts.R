# ==============================================================================
# Dosya Yolu: R/helpers_summarization_prompts.R
# Açıklama: Türkçe belge özetleme için sistem promptları ve yardımcı fonksiyonlar.
#           Detay seviyesi ve odak moduna göre tamamen farklı promptlar üretir.
# ==============================================================================

build_summarization_system_prompt <- function(file_count = 1, total_chars = 0,
                                               detail_level = "standard",
                                               focus_mode = "general") {

  base <- build_mode_instructions(detail_level, focus_mode, file_count)

  safety_rules <- paste0(
    "\n\nKATI KURALLAR (ASLA İHLAL ETME):",
    "\n- YALNIZCA sağlanan belge içeriğini kullan, ASLA ek bilgi uydurma.",
    "\n- Belgede olmayan hiçbir konuyu, veriyi veya detayı ekleme.",
    "\n- Dosya adından içerik tahmini YAPMA.",
    "\n- Eksik bilgi varsa 'belgede bulunamadı' şeklinde belirt."
  )
  base <- paste0(base, safety_rules)

  format_rules <- paste0(
    "\n\nFORMAT KURALLARI:",
    "\n- Ana başlıkları **kalın** yap.",
    "\n- Alt konuları maddeler halinde (- veya *) sun.",
    "\n- Türkçe yaz."
  )
  base <- paste0(base, format_rules)

  if (file_count > 1) {
    base <- paste0(base,
      "\n\nÇOKLU DOSYA (", file_count, " DOSYA) İÇİN:",
      "\n- Her dosyayı ayrı bir bölüm olarak işle.",
      "\n- Her bölüm başlığında ### DOSYA [sayı]: [DOSYA ADI] formatını kullan."
    )
  }

  if (detail_level == "detailed" && total_chars > 100000) {
    base <- paste0(base,
      "\n\nUZUN BELGE (", format(total_chars, big.mark = ".", decimal.mark = ","), " karakter):",
      "\n- 256K bağlam pencereni tam kullan.",
      "\n- Belgeyi bölüm bölüm, titizlikle işle."
    )
  }

  base
}

build_summarization_user_prompt <- function(file_contents_list,
                                             detail_level = "standard",
                                             focus_mode = "general") {
  file_count <- length(file_contents_list)

  if (file_count == 1) {
    file_block <- paste0(
      "BELGE İÇERİĞİ:\n\n",
      file_contents_list[[1]]$content,
      "\n\n---\n"
    )
    instruction <- build_single_file_instruction(
      file_contents_list[[1]]$name,
      nchar(file_contents_list[[1]]$content),
      detail_level, focus_mode
    )
    return(paste0(file_block, instruction))
  } else {
    blocks <- vapply(seq_along(file_contents_list), function(i) {
      fc <- file_contents_list[[i]]
      paste0(
        "### DOSYA ", i, ": ", fc$name,
        " (", format(nchar(fc$content), big.mark = ".", decimal.mark = ","), " karakter)\n\n",
        fc$content
      )
    }, character(1))

    file_block <- paste(blocks, collapse = "\n\n--- DOSYA SONU ---\n\n")
    instruction <- build_multi_file_instruction(
      file_count,
      sum(vapply(file_contents_list, function(x) nchar(x$content), numeric(1))),
      detail_level, focus_mode
    )
    return(paste0(file_block, "\n\n--- TÜM DOSYALAR BİTTİ ---\n\n", instruction))
  }
}

build_single_file_instruction <- function(file_name, char_count, detail_level, focus_mode) {
  header <- paste0("### ", file_name, "\n")

  if (detail_level == "brief") {
    return(paste0(
      header,
      "Yukarıdaki belgenin KISA ÖZETİNİ yaz. ",
      "En fazla 8-10 cümle. Sadece ana fikir ve en kritik noktalar."
    ))
  }

  if (detail_level == "detailed") {
    template <- paste0(
      header,
      "Yukarıdaki belgeyi EKSIKSIZ ve AYRINTILI şekilde özetle.\n\n"
    )
    if (focus_mode == "numerical") {
      return(paste0(template,
        "Odak: Tüm sayısal verileri, istatistikleri ve rakamları çıkar ve **>değer<** formatıyla vurgula. ",
        "Anlatım metni minimum olsun."
      ))
    }
    if (focus_mode == "decisions") {
      return(paste0(template,
        "Odak: Tüm karar noktalarını, önerileri ve aksiyon maddelerini listele. ",
        "Her karar için sorumlu ve zaman çizelgesi belirt. Genel anlatımı minimum tut."
      ))
    }
    if (focus_mode == "comparison") {
      return(paste0(template,
        "Odak: Belgenin kendi içindeki farklı bölümlerini karşılaştır. ",
        "Bölümler arası tutarsızlıkları ve farklılıkları vurgula."
      ))
    }
    return(paste0(template,
      "**Belge Tipi:** [DOC/PDF/Word vb.]\n",
      "**Toplam Uzunluk:** ", format(char_count, big.mark = ".", decimal.mark = ","), " karakter\n\n",
      "**ANA BÖLÜMLER:**\n[Başlık başlık listele]\n\n",
      "**DETAYLI İÇERİK DÖKÜMÜ:**\n[Her bölümü maddeler halinde detaylandır]\n\n",
      "**KRİTİK SAYISAL VERİLER:**\n[Tüm sayısal verileri listele]\n\n",
      "**TEMEL ÇIKARIMLAR:**\n[Temel sonuçlar]\n\n",
      "**DEĞERLENDİRMELER:**\n[İçeriğe dayalı değerlendirmeler]"
    ))
  }

  template <- paste0(header, "Yukarıdaki belgeyi dengeli şekilde özetle.\n\n")
  if (focus_mode == "numerical") {
    return(paste0(template,
      "Odak: Sayısal verilere ve istatistiklere ağırlık ver. Rakamları **>değer<** formatıyla vurgula."
    ))
  }
  if (focus_mode == "decisions") {
    return(paste0(template,
      "Odak: Karar noktalarına, önerilere ve aksiyon maddelerine ağırlık ver."
    ))
  }
  if (focus_mode == "comparison") {
    return(paste0(template,
      "Odak: Belgenin kendi içindeki farklı bölümlerini karşılaştır."
    ))
  }
  paste0(template, "Ana başlıkları koru. Önemli verileri belirt. Sonunda genel değerlendirme ekle.")
}

build_multi_file_instruction <- function(file_count, total_chars, detail_level, focus_mode) {

  if (detail_level == "brief") {
    base <- paste0(
      "Yukarıdaki ", file_count, " dosyanın her biri için EN FAZLA 8-10 CÜMLE ile KISA ÖZET yaz."
    )
    if (focus_mode == "comparison") {
      return(paste0(base, " Ayrıca dosyalar arası temel benzerlik ve farklılıkları 3-5 madde ile belirt."))
    }
    if (focus_mode == "numerical") {
      return(paste0(base, " Sadece en kritik sayısal verilere odaklan."))
    }
    if (focus_mode == "decisions") {
      return(paste0(base, " Sadece en kritik karar ve aksiyon maddelerine odaklan."))
    }
    return(base)
  }

  if (detail_level == "detailed") {
    base <- paste0(
      "Yukarıdaki ", file_count, " dosyayı AYRI AYRI EKSIKSIZ ve AYRINTILI özetle.\n",
      "**Toplam Dosya Sayısı:** ", file_count, "\n",
      "**Toplam Karakter:** ", format(total_chars, big.mark = ".", decimal.mark = ","), "\n\n"
    )
    if (focus_mode == "comparison") {
      return(paste0(base,
        "Her dosyayı özetle, ardından DOSYALAR ARASI KARŞILAŞTIRMA bölümü oluştur:\n",
        "- Benzerlikleri ve farklılıkları madde madde listele.\n",
        "- Mümkünse karşılaştırma tablosu oluştur.\n",
        "- Sentez ve bütünleşik değerlendirme sun."
      ))
    }
    if (focus_mode == "numerical") {
      return(paste0(base,
        "Her dosyadan tüm sayısal verileri çıkar ve **>değer<** formatıyla listele. ",
        "Anlatım metni minimum olsun."
      ))
    }
    if (focus_mode == "decisions") {
      return(paste0(base,
        "Her dosyadan tüm karar noktalarını ve aksiyon maddelerini çıkar. ",
        "Sorumlu ve zaman çizelgelerini belirt. Genel anlatımı minimum tut."
      ))
    }
    return(paste0(base,
      "### HER DOSYA İÇİN AYRINTILI ÖZET\n[Ayrı ayrı özetle]\n\n",
      "### DOSYALAR ARASI KARŞILAŞTIRMA\n[Benzerlikler, farklılıklar]\n\n",
      "### BİRLEŞİK DEĞERLENDİRME\n[Genel sonuçlar]"
    ))
  }

  base <- paste0(
    "Yukarıdaki ", file_count, " dosyayı dengeli şekilde özetle.\n"
  )
  if (focus_mode == "comparison") {
    return(paste0(base,
      "Bireysel özetleri kısa tut, asıl odak dosyalar arası KARŞILAŞTIRMA olsun."
    ))
  }
  if (focus_mode == "numerical") {
    return(paste0(base,
      "Sayısal verilere ve istatistiklere ağırlık ver. Rakamları **>değer<** formatıyla vurgula."
    ))
  }
  if (focus_mode == "decisions") {
    return(paste0(base,
      "Karar noktalarına ve aksiyon maddelerine ağırlık ver."
    ))
  }
  paste0(base, "Her dosya için ayrı bölüm oluştur. Sonunda genel değerlendirme ekle.")
}
