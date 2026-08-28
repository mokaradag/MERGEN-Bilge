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
  # v2 sonucu kanonik paket metni olmadan "başarılı" kabul edilmez. Böyle bir
  # durumda legacy `summary_text` alanına düşmek, tam da v2'nin grain/birim/
  # toplulaştırma ve olgu kökeni garantilerini kaybettiren P1 yolunu yeniden
  # açardı. v1 kayıtları ise aşağıda BİREBİR eski biçimini kullanmaya devam eder.
  query_results <- lapply(query_results, function(r) {
    v2 <- is.list(r) && identical(as.character(r$pk_engine_mode %||% "")[1], "v2")
    packet_text <- if (v2) tryCatch(as.character(r$pk_packet_text %||% "")[1],
                                    error = function(e) "") else ""
    if (isTRUE(r$success) && v2 && (is.na(packet_text) || !nzchar(packet_text))) {
      r$success <- FALSE
      r$error_msg <- paste0(
        "Kanonik v2 analiz paketi oluşturulamadı; legacy sayısal özete ",
        "güvenlik gereği geri düşülmedi."
      )
    }
    r
  })

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
  v2_present <- any(vapply(successful, function(r) {
    identical(as.character(r$pk_engine_mode %||% "")[1], "v2")
  }, logical(1)))

  if (query_count > 1) {
    scale_factor <- 1 + (query_count - 1) * 0.3
    max_tokens <- min(as.integer(base_max_tokens * scale_factor), 8192)
  } else {
    max_tokens <- base_max_tokens
  }

  data_blocks <- vapply(seq_along(successful), function(i) {
    r <- successful[[i]]
    header <- paste0(
      sprintf("\n\n==========================================\n"),
      sprintf("\U0001F4CA SORGU %d/%d: %s\n", i, query_count, r$query_name),
      sprintf("Açıklama: %s\n", r$query_desc),
      sprintf("Toplam Satır: %d | İlgililik: %.0f%%\n", r$row_count, r$relevance),
      sprintf("==========================================\n")
    )

    if (identical(as.character(r$pk_engine_mode %||% "")[1], "v2")) {
      # v2: doğrudan pk_packet_render() çıktısı. summary_text/preview_json
      # okunmaz; legacy özet üzerinden dolaylı bir geri düşüş yoktur.
      return(paste0(
        header,
        as.character(r$pk_packet_text)[1],
        sprintf("\n(Bu sorgu %d satırlık veri içermektedir)\n", r$row_count)
      ))
    }

    # v1: mevcut legacy sözleşme BİREBİR korunur.
    paste0(
      header,
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
    if (v2_present) paste0(
      "\n### v2 SAYISAL KÖKEN KURALI (ZORUNLU):\n",
      "- v2 ANALİZ PAKETİ içindeki her sayısal iddianın hemen ardına pakette basılı ilgili `[fact:...]` referansını AYNEN koy.\n",
      "- Yeni fact kimliği UYDURMA; pakette bulunmayan sayıyı yazma ve paketler arasında aritmetik HESAPLAMA.\n",
      "- `KULLANILAMAZ` durumundaki olgular için sayı üretme; sınırlılığı açıkça belirt.\n"
    ) else "",
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

  # İSTEK GENELİ İSTEM BÜTÇESİ (birleşik bağlam).
  #
  # Her sorgu özeti KENDİ sınırıyla bağlıydı ve her birinin ayrı
  # serileştirilmiş `preview_json` bloğu o sınıra hiç girmiyordu. Birkaç sorgu
  # seçildiğinde (ya da geniş/uzun önizleme değerlerinde) NİHAİ girdi
  # `MERGEN_PK_PROMPT_CHAR_BUDGET` / model bağlam sınırını aşabiliyor ve
  # geçerli bir derin analiz son LLM çağrısında TAMAMEN düşüyordu. Bütçe artık
  # sistem metni + soru + tüm sorgu blokları + başarısız/kısmi notları
  # EKLENDİKTEN SONRA, yani modelin gerçekten göreceği yük üzerinde uygulanır.
  #
  # Deterministik bozulma: v1 önizleme JSON blokları SONDAN başlayarak
  # düşürülür; v2 bloklarında önizleme yoktur çünkü kanonik paket doğrudan
  # kullanılır. Gerekirse ikinci aşama tam sorgu bloklarını düşürür ve bunu
  # AÇIKÇA ifşa eder. Hiçbir sorgu sessizce kaybolmaz.
  if (exists("pk_deep_fit_context_budget", mode = "function", inherits = TRUE)) {
    sigdirma <- tryCatch(
      pk_deep_fit_context_budget(system_prompt, user_context, data_blocks,
                                 detail_config = detail_config,
                                 query_meta = if (is.list(detail_config)) detail_config$query_meta else NULL),
      error = function(e) NULL
    )
    if (is.list(sigdirma) && is.character(sigdirma$user_context)) {
      user_context <- sigdirma$user_context

      # BÜTÇE AŞIMI SESSİZ GEÇMEZ.
      #
      # Tüm deterministik bozulmalara rağmen yük hâlâ bütçeyi aşıyorsa, onu
      # olduğu gibi göndermek yapılandırılan sınırı ETKİSİZ kılar ve model
      # bağlam sınırı reddine yol açabilir. Sondan kesme deterministiktir ve
      # kesildiği AÇIKÇA bildirilir.
      if (isTRUE(sigdirma$over_budget)) {
        hedef <- suppressWarnings(as.integer(sigdirma$budget)[1])
        sabit <- nchar(system_prompt, type = "chars")
        kalan <- if (length(hedef) == 1L && !is.na(hedef)) hedef - sabit else NA_integer_
        not <- paste0(
          "\n\n\U000026A0\U0000FE0F İSTEM BÜTÇESİ: bağlam yapılandırılan sınırı ",
          "aştığı için SONDAN KESİLDİ. Bu analiz EKSİKTİR; bulguları tam sonuç ",
          "gibi sunma."
        )
        if (!is.na(kalan) && kalan > nchar(not, type = "chars") + 200L) {
          user_context <- paste0(
            substr(user_context, 1L, kalan - nchar(not, type = "chars")), not
          )
        } else {
          # KESMEYE YER KALMASA BİLE İFŞA YAZILIR.
          #
          # `kalan` küçük ya da negatifse blok TAMAMEN atlanıyordu: model
          # bütçeyi aşan bir bağlam alıyor ve analizin EKSİK olduğunu belirten
          # HİÇBİR ifade görmüyordu. Bozulmanın görünür olması §5.11
          # sözleşmesidir; kesme yapılamaması onu görünmez kılmaz.
          user_context <- paste0(user_context, not)
        }
      }
    }
  }

  return(list(
    type = "data_analysis",
    prompt_context = system_prompt,
    user_context = user_context,
    query_count = query_count,
    max_tokens = max_tokens
  ))
}

#' Birleşik derin analiz bağlamını istek geneli istem bütçesine sığdır
#'
#' Saftır: Shiny/DB/ağ bağımlılığı yoktur. Bütçeye SIĞIYORSA metin aynen döner.
pk_deep_fit_context_budget <- function(system_prompt, user_context, data_blocks,
                                       detail_config = NULL, query_meta = NULL) {
  # BİRİNCİL SORGU METADATA'SI ÇÖZÜCÜYE ULAŞMALIDIR.
  #
  # `get_analysis_detail_config()` `query_meta` alanını DOLDURMAZ; bu yüzden
  # çözücüye `NULL` gidiyor ve sorgu kapsamlı `MERGEN_PK_PROMPT_CHAR_BUDGET`
  # geçersiz kılması YOK SAYILIP küresel yapılandırmaya düşülüyordu.
  # `query_meta` argümanı açıkça verildiğinde o kullanılır.
  butce <- if (exists("pk_prompt_char_budget", mode = "function", inherits = TRUE)) {
    suppressWarnings(as.integer(pk_prompt_char_budget(
      query_meta = query_meta %||%
        (if (is.list(detail_config)) detail_config$query_meta else NULL)
    ))[1])
  } else {
    NA_integer_
  }
  if (length(butce) != 1L || is.na(butce) || butce <= 0L) {
    return(list(user_context = user_context, trimmed = FALSE))
  }

  sabit <- nchar(system_prompt, type = "chars")
  toplam <- function(txt) sabit + nchar(txt, type = "chars")

  if (toplam(user_context) <= butce) {
    return(list(user_context = user_context, trimmed = FALSE))
  }

  # İFŞA METİNLERİ İÇİN YER AYRILIR.
  #
  # Kırpma döngüleri bütçeyi TAM sınırda bırakıyor, ardından eklenen
  # "İSTEM BÜTÇESİ: ... GÖNDERİLMEDİ" notları yükü YENİDEN sınırın üstüne
  # itiyordu. Not eklendikten sonra kırpılacak blok kalmadığında fonksiyon
  # `over_budget = TRUE` döndürüyor, çağıran ise bunu YOK SAYIP aşırı yükü
  # modele gönderiyordu. Kırpma hedefi bu yüzden ifşa payı KADAR daha
  # düşüktür ve nihai denetim aynı yerde kalır.
  ifsa_payi <- 400L
  kirpma_hedefi <- max(butce - ifsa_payi, as.integer(butce * 0.5))

  # Önizleme JSON bölümlerini sondan başlayarak düşür.
  kirpilmis <- user_context
  dusurulen <- 0L
  # DESEN TÜM ÖNİZLEME BLOĞUNU KAPSAR, YALNIZCA İLK SATIRINI DEĞİL.
  #
  # Eski `[^\n]*` kuyruğu ilk satır sonunda duruyordu; `preview_json` çok
  # satırlı olduğu için bloktan yalnızca açılış köşeli ayracı siliniyor, JSON
  # gövdesi bağlamda KALIYORDU. Yük anlamlı biçimde küçülmüyor, buna karşın
  # ifşa notu "GÖNDERİLMEDİ" diyordu; yani hem bütçe uygulanmıyor hem de
  # modele yanlış bilgi veriliyordu. Blok her zaman satır sayısı satırıyla
  # kapandığı için sınır ileri-bakışla ORAYA sabitlenir (kapanış yoksa hiç
  # düşürülmez; o durum 2. aşamanın işidir).
  desen <- paste0(
    "(?s)\n\n--- \u00d6RNEK VER\u0130 \\(JSON\\) ---\n.*?",
    "(?=\n\\(Bu sorgu )"
  )

  while (toplam(kirpilmis) > kirpma_hedefi && grepl(desen, kirpilmis, perl = TRUE)) {
    # Yerine konan metin desenle ESLESMEMELIDIR; aksi halde dongu ayni blogu
    # sonsuza kadar "dusurmeye" calisir ve metin hic kucullmez.
    konumlar <- gregexpr(desen, kirpilmis, perl = TRUE)[[1]]
    if (konumlar[1] < 1L) break
    son <- length(konumlar)
    bas <- konumlar[son]
    boy <- attr(konumlar, "match.length")[son]
    kirpilmis <- paste0(
      substr(kirpilmis, 1L, bas - 1L),
      "\n\n[ÖRNEK VERİ: istem bütçesi nedeniyle GÖNDERİLMEDİ]",
      substr(kirpilmis, bas + boy, nchar(kirpilmis))
    )
    dusurulen <- dusurulen + 1L
  }

  if (dusurulen > 0L) {
    kirpilmis <- paste0(
      kirpilmis,
      sprintf(paste0("\n\n\U000026A0\U0000FE0F İSTEM BÜTÇESİ: %d sorgunun örnek veri (JSON) ",
                     "bloğu bütçeye sığmadığı için GÖNDERİLMEDİ; istatistiksel özetler korundu."),
              dusurulen)
    )
  }

  # 2. AŞAMA — ÖNİZLEMELER GİTTİKTEN SONRA HÂLÂ AŞILIYORSA.
  #
  # Birinci aşama YALNIZCA önizleme JSON bloklarını düşürür. Sabit sistem
  # metni + kullanıcı bağlamı + istatistiksel özetler tek başına bütçeyi
  # aşıyorsa (ya da hiç önizleme bloğu yoksa) döngü sona erer ve fonksiyon
  # eskiden bütçe ÜSTÜ yükü SESSİZCE değişmeden döndürürdü; yani çok sorgulu
  # bir derin istek, yeni toplam muhafıza rağmen nihai LLM çağrısında
  # `MERGEN_PK_PROMPT_CHAR_BUDGET` sınırını aşabiliyordu.
  #
  # Deterministik ikinci bozulma: TÜM sorgu blokları SONDAN başlayarak
  # düşürülür. Hiçbir sorgu sessizce kaybolmaz; her düşürme AÇIKÇA ifşa edilir
  # ve model eksik analiz yaptığını bilir.
  blok_isareti <- "\n\n==========================================\n\U0001F4CA SORGU "
  sonuc_sonu <- "\n\n--- SONUÇLAR SONU ---"
  dusen_blok <- 0L

  # KIRPMA SINIRI SORGU BLOĞUNUN SONUNDA BİTER, SONUÇ SONLANDIRICISINDA DEĞİL.
  #
  # `user_context` sırası: sorgu blokları -> BAŞARISIZ SORGULAR notu -> EKSİK
  # ANALİZ UYARISI -> `--- SONUÇLAR SONU ---`. Silinen aralık son bloktan
  # doğrudan sonuç sonlandırıcısına kadar uzatıldığında ARADAKİ iki uyarı da
  # siliniyordu: model hangi sorguların veri döndüremediğini ve analizin EKSİK
  # olduğunu öğrenemiyor, kullanıcıya da bildirilmiyordu. Aralık bu yüzden
  # `bas` konumundan sonra gelen İLK sonlandırıcıda biter. Uyarı blokları
  # sorgu bloklarıyla AYNI ayraç çizgisini kullanır ama işaretleri farklıdır
  # (uyarı üçgeni / grafik simgesi), bu yüzden yapısal olarak ayırt edilir.
  uyari_isareti <- "\n\n==========================================\n\U000026A0\U0000FE0F "
  .ilk_sonlandirici <- function(metin, bas) {
    kuyruk_metni <- substr(metin, bas, nchar(metin))
    konum <- Inf
    for (aday in c(uyari_isareti, sonuc_sonu)) {
      k <- regexpr(aday, kuyruk_metni, fixed = TRUE)
      if (k[1] > 0L) konum <- min(konum, bas + k[1] - 1L)
    }
    if (is.finite(konum)) konum else nchar(metin) + 1L
  }

  while (toplam(kirpilmis) > kirpma_hedefi) {
    konumlar <- gregexpr(blok_isareti, kirpilmis, fixed = TRUE)[[1]]
    if (konumlar[1] < 1L) break

    bas <- konumlar[length(konumlar)]
    son <- .ilk_sonlandirici(kirpilmis, bas)

    # Yerine konan metin blok işaretiyle EŞLEŞMEZ; döngü her turda kısalır.
    kirpilmis <- paste0(
      substr(kirpilmis, 1L, bas - 1L),
      "\n\n[SORGU BLOĞU: istem bütçesi nedeniyle GÖNDERİLMEDİ]",
      substr(kirpilmis, son, nchar(kirpilmis))
    )
    dusen_blok <- dusen_blok + 1L
  }

  if (dusen_blok > 0L) {
    kirpilmis <- paste0(
      kirpilmis,
      sprintf(paste0("\n\n\U000026A0\U0000FE0F İSTEM BÜTÇESİ: %d sorgunun sonuç bloğu ",
                     "bütçeye sığmadığı için GÖNDERİLMEDİ. Bu analiz EKSİKTİR; ",
                     "bulguları tam sonuç gibi sunma."),
              dusen_blok)
    )
  }

  # Nihai denetim: sabit sistem metni tek başına bütçeyi aşıyorsa (operatör
  # yapılandırma hatası) daha fazla deterministik kırpma yapılamaz. Durum
  # SESSİZ geçmez; çağıran `over_budget` ile görür ve log'a yazılır.
  asildi <- toplam(kirpilmis) > butce
  if (asildi) {
    cat(sprintf(
      "[PK_DERIN] UYARI: Istem butcesi tum bozulmalara ragmen asiliyor: %d/%d karakter.\n",
      toplam(kirpilmis), butce
    ))
  }

  list(
    user_context = kirpilmis,
    trimmed = (dusurulen > 0L) || (dusen_blok > 0L),
    dropped_previews = dusurulen,
    dropped_blocks = dusen_blok,
    over_budget = asildi,
    chars = toplam(kirpilmis),
    budget = butce
  )
}
