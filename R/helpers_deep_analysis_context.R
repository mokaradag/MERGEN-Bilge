# ==============================================================================
# Dosya Yolu: R/helpers_deep_analysis_context.R
# Açıklama:   Derin Analiz çoklu sorgu sonuçlarının birleştirilmesi ve LLM
#             sistem promptu / kullanıcı bağlamı üretimi.
#
#             Bu dosya BİLİNÇLİ olarak saftır: yalnızca metin/prompt kurar;
#             Shiny/reactive/DB/LLM/ağ bağımlılığı yoktur, worker güvenlidir.
#             R/helpers_deep_analysis.R bakım borcu ratchet bütçesini aştığı
#             için buradan ayrılmıştır; bağlam kurucuyu tekrar orkestratör
#             dosyasına taşımayın.
#
#             Yükleme sırası: R/config_source_manifest.R içindeki
#             `analysis_helpers` bölümünde R/helpers_deep_analysis.R ÖNCESİNDE
#             yer alır. build_deep_analysis_context() fonksiyonunu yalıtılmış
#             olarak test eden dosyalar bu dosyayı source etmelidir.
# ==============================================================================

# ------------------------------------------------------------------------------
# ÇOKLU SONUÇ BİRLEŞTİRME VE GENEL YORUM OLUŞTURMA
# ------------------------------------------------------------------------------

#' Bireysel sorgu sonuçlarını birleştirip LLM bağlamı oluştur
#' @param query_results execute_single_deep_query sonuçlarının listesi
#' @param user_prompt Kullanıcı sorusu
#' @param detail_config Detay seviyesi yapılandırması
#' @return LLM'e gönderilecek sistem promptu ve kullanıcı bağlamı
build_deep_analysis_context <- function(query_results, user_prompt, detail_config) {
  successful <- Filter(function(r) isTRUE(r$success), query_results)
  failed <- Filter(function(r) !isTRUE(r$success), query_results)

  if (length(successful) == 0) {
    return(list(
      type = "error_message",
      content = paste0(
        "\U0001F50D **Derin Analiz Sonucu:** Hiçbir sorgu başarılı sonuç döndürmedi.\n\n",
        if (length(failed) > 0) {
          paste0("Başarısız sorgular:\n",
                 paste(vapply(failed, function(f) {
                   sprintf("- **%s**: %s", f$query_name, f$error_msg %||% "Bilinmeyen hata")
                 }, character(1)), collapse = "\n"))
        } else ""
      )
    ))
  }

  detail_instruction <- detail_config$instruction %||% ""
  base_max_tokens <- detail_config$max_tokens %||% 3000
  query_count <- length(successful)

  if (query_count > 1) {
    scale_factor <- 1 + (query_count - 1) * 0.3
    max_tokens <- min(as.integer(base_max_tokens * scale_factor), 8192)
  } else {
    max_tokens <- base_max_tokens
  }

  data_blocks <- vapply(seq_along(successful), function(i) {
    r <- successful[[i]]
    paste0(
      sprintf("\n\n==========================================\n"),
      sprintf("\U0001F4CA SORGU %d/%d: %s\n", i, query_count, r$query_name),
      sprintf("Açıklama: %s\n", r$query_desc),
      sprintf("Toplam Satır: %d | İlgililik: %.0f%%\n", r$row_count, r$relevance),
      sprintf("==========================================\n"),
      r$summary_text,
      "\n\n--- ÖRNEK VERİ (JSON) ---\n",
      r$preview_json,
      sprintf("\n(Bu sorgu %d satırlık veri içermektedir)\n", r$row_count)
    )
  }, character(1))

  combined_data <- paste(data_blocks, collapse = "\n")

  system_prompt <- paste0(
    "Sen MERGEN'in kıdemli veri analisti asistanısın. Primavera P6 ve SAP PS konusunda 15+ yıl deneyimin var.\n\n",
    "### DERİN ANALİZ MODU\n",
    "Bu istekte ÇOKLU SORGU sonuçları sunulmuştur. Görevin:\n",
    "1. HER SORGUYU BİREYSEL olarak analiz et - kendi bölümünde\n",
    "2. Sorgular arası İLİŞKİLERİ ve ORTAK PATERNLERİ tespit et\n",
    "3. GENEL BİR DEĞERLENDİRME ile bitir\n\n",
    "### DETAY SEVİYESİ TALİMATI:\n",
    detail_instruction, "\n\n",
    "### ZORUNLU YAPI:\n",
    "Her sorgu için:\n",
    "## \U0001F4CA [Sorgu Adı]\n",
    "- Temel bulgular ve istatistikler\n",
    "- Dikkat çeken noktalar\n\n",
    "Son bölüm:\n",
    "## \U0001F517 Genel Değerlendirme\n",
    "- Sorgular arası bağlantılar ve çapraz bulgular\n",
    "- Bütünsel öneriler\n",
    "- Uyarılar ve riskler\n\n",
    "### KRİTİK KURALLAR:\n",
    "- Sayıları DOĞRUDAN kullan, tahmin veya varsayım YAPMA\n",
    "- Her yorum veriye dayalı olmalı\n",
    "- Profesyonel, güvenilir ve net Türkçe kullan\n",
    "- \"Muhtemelen\", \"belki\" gibi belirsizliklerden kaçın\n",
    "- Markdown tablo formatını listeleme/sıralama için kullan\n",
    "- FİLTRELEME UYARISI varsa, oran belirtirken dikkatli ol\n",
    "- Başarısız sorgular varsa, bunları da raporla (hangileri ve neden başarısız olduklarını kısaca belirt)\n",
    "- TÜM başarılı sorguları mutlaka raporla - hiçbirini atlama!\n",
    # Faz 6 (D16, §10): paketler arası ARİTMETİK yasağı. "Sorgular arası
    # ilişkiler" DÜZYAZI sentezi içindir; sayıları birleştirmek için DEĞİL.
    # Eşleşen kırılım (grain) toplama izni değildir.
    "\n### PAKET SINIRI (ZORUNLU):\n",
    detail_config$pk_cross_query_instruction %||%
      get0("PK_DEEP_NO_CROSS_ARITHMETIC_INSTRUCTION", ifnotfound = ""),
    "\n"
  )

  failed_note <- ""
  if (length(failed) > 0) {
    failed_note <- paste0(
      "\n\n==========================================\n",
      sprintf("\U000026A0\U0000FE0F BAŞARISIZ SORGULAR (%d adet)\n", length(failed)),
      "==========================================\n",
      paste(vapply(failed, function(f) {
        sprintf("- **%s**: %s", f$query_name, f$error_msg %||% "Hata")
      }, character(1)), collapse = "\n"),
      "\n\nBu sorguları yanıtında kısaca belirt: hangi sorguların veri döndüremediğini ",
      "ve olası nedenlerini kullanıcıya bildir.\n"
    )
  }

  # KISMİ DURMA notu GERÇEKTEN prompta girer. Yalnızca `detail_config` içinde
  # taşımak, iptal/son tarih nedeniyle EKSİK kalmış bir analizin nihai LLM'e
  # SIRADAN ve TAM bir analiz gibi sunulması demekti (§5.11: sessizce başarı
  # gibi görünen bozulma yasak). Hem sistem hem kullanıcı bağlamına yazılır ki
  # model uyarıyı yanıtına taşımak zorunda kalsın.
  kismi_not <- as.character(detail_config$pk_partial_halt_note %||% "")[1]
  kismi_bolum <- if (nzchar(kismi_not)) {
    paste0("\n\n==========================================\n",
           "\U000026A0\U0000FE0F EKSİK ANALİZ UYARISI\n",
           "==========================================\n", kismi_not, "\n")
  } else {
    ""
  }
  if (nzchar(kismi_not)) {
    system_prompt <- paste0(
      system_prompt,
      "\n### EKSİK ANALİZ (ZORUNLU):\n",
      kismi_not,
      "\nYanıtının BAŞINDA bu analizin TAMAMLANMADIĞINI açıkça belirt; ",
      "bulguları kesin/tam sonuç gibi sunma.\n"
    )
  }

  user_context <- paste0(
    "KULLANICI SORUSU:\n",
    user_prompt,
    "\n\n--- R TARAFINDAN HAZIRLANAN ÇOKLU SORGU SONUÇLARI ---\n",
    sprintf("Toplam %d sorgu başarıyla çalıştırıldı.\n", query_count),
    combined_data,
    failed_note,
    kismi_bolum,
    "\n\n--- SONUÇLAR SONU ---\n\n",
    "Talimat: Yukarıdaki TÜM sorgu sonuçlarını bireysel ve bütünsel olarak analiz et. ",
    "Her sorguyu kendi bölümünde değerlendir, sonra genel bir sentez yap."
  )

  return(list(
    type = "data_analysis",
    prompt_context = system_prompt,
    user_context = user_context,
    query_count = query_count,
    max_tokens = max_tokens
  ))
}

