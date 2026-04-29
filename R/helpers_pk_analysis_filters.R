# ==============================================================================
# Dosya Yolu: R/helpers_pk_analysis_filters.R
# Açıklama: Proje/Kaynak Analizi için AI filtre çıkarımı ve veri filtreleme
#           yardımcıları. Bu dosya Shiny observer başlatmaz ve canlı DB
#           bağlantısı açmaz; çağıran akışın verdiği conn/session nesnelerini
#           kullanır.
# ==============================================================================

extract_filter_criteria_from_prompt <- function(user_prompt, data_context, available_columns, conn, session = NULL, stop_check = NULL) {

  if (is.function(stop_check) && isTRUE(stop_check())) {
    cat("[FILTER_AI] Durdurma talebi alindi (AI filtreleme oncesi)\n")
    return(list(filters = list(), aggregation = NULL))
  }

  cols_summary <- summarize_columns_for_ai(data_context)

  system_instruction <- paste0(
    "Sen Primavera P6 ve SAP Project System verileri konusunda uzman, kıdemli bir veri analistisin. ",
    "Kullanıcının Türkçe sorduğu doğal dil sorularını analiz ederek yapılandırılmış bir JSON filtreleme sorgusuna dönüştürmekle görevlisin.\n\n",

    "### KRİTİK: GENEL SORULAR VS SPESİFİK FİLTRELER\n",
    "\U00002757\U00002757\U00002757 ÇOĞU SORGU ZATEN BELİRLİ BİR KONUYA ÖZELDIR - GEREKSİZ FİLTRE EKLEME!\n",
    "Örnek: 'Rolden kaynağa çevrilmemiş aktiviteler' sorgusu zaten bu konuya özgüdür. 'çevrilmemiş' kelimesini filtre olarak kullanma!\n",
    "Örnek: 'Bütçesi aşan projeler' sorgusu zaten bütçe aşımı içerir. 'aşan' kelimesini filtre olarak kullanma!\n\n",

    "\U00002757 Kullanıcı GENEL bir analiz istiyorsa (tüm projeler, tüm kaynaklar, özet istatistikler), FİLTRE KULLANMA!\n",
    "\U00002705 Sadece kullanıcı BELİRLİ bir VARLIK belirtirse filtre ekle:\n",
    "   - Proje kodu: 'P1234', 'PROJE-001'\n",
    "   - Proje adı: 'Malzeme Üretim Projesi', 'Elektronik Tasarım'\n",
    "   - Kişi adı: 'Ahmet Yılmaz', 'Mehmet'\n",
    "   - Departman: 'Elektronik Tasarım Müdürlüğü', 'PGRM'\n",
    "   - Masraf yeri kodu: '12345678'\n",
    "   - Tarih aralığı: '2024', 'Ocak', 'son 3 ay'\n\n",

    "\U0000274C FİLTRE YAPILMAMASI GEREKEN DURUMLAR:\n",
    "- Kullanıcı sorgu konusunu tekrar ediyor: 'aktiviteler', 'kaynaklar', 'projeler' gibi genel terimler\n",
    "- Kullanıcı analiz türü belirtiyor: 'özetle', 'listele', 'kaç tane', 'var mı'\n",
    "- Kullanıcı sorgu kriterini tekrar ediyor: Sorgu zaten 'çevrilmemiş aktiviteler'i getiriyorsa, 'çevrilmemiş' filtresiz bırak\n\n",

    "**GENEL SORU ÖRNEKLERİ (FİLTRE YOK):**\n",
    "- 'Kaç proje var?', 'Toplam kaç kaynak?', 'Hangi departmanlarda çalışma var?'\n",
    "- 'Projelerin dağılımı nedir?', 'En büyük projeler hangileri?', 'Aktif proje sayısı?'\n",
    "- 'Yıllara göre proje dağılımı', 'Departman bazında kaynak analizi'\n",
    "- 'Ortalama proje süresi', 'Toplam bütçe', 'Maliyet özeti'\n\n",

    "**SPESİFİK SORU ÖRNEKLERİ (FİLTRE EKLE):**\n",
    "- 'P1234 projesinin durumu nedir?' -> filter: ProjeKodu='P1234'\n",
    "- 'Malzeme Üretim projesinin durumu nedir?' -> filter: ProjeAdi='Malzeme Üretim'\n",
    "- 'Ahmet Yılmaz hangi projelerde?' -> filter: KaynakAdi contains 'Ahmet Yılmaz'\n",
    "- 'PGRM program müdürlüğündeki projeler' -> filter: ProgMdlKodu='4_PGRM'\n",
    "- 'Elektronik Tasarım Müdürlüğündeki çalışanlar' -> filter: MasrafYeri='Elektronik Tasarım Müdürlüğü'\n",
    "- '12345678 masraf yerindeki çalışanlar' -> filter: MasrafYeriKodu='12345678'\n",
    "- 'Aktif durumdaki projeler' -> filter: Durum='1'\n\n",

    "### ANALİZ EVRENİ VE TERMİNOLOJİ\n",
    "**Proje Yönetimi Terimleri:**\n",
    "- **Projeler:** Proje Kodu, Proje Adı, Durum, EPS, Program Müdürlüğü, Program Direktörlüğü, İDA, İş Dağılım Ağacı, WBS\n",
    "- **Kaynaklar:** Kaynak Adı, Kaynak Kodu, Çalışan, Personel, Rol, Unvan, Sicil Numarası, Sicil No\n",
    "- **Organizasyon:** Masraf Yeri, Masraf Yeri Kodu, Bölüm, Müdürlük, Direktörlük, Birim\n",
    "- **Finansal:** Bütçe, Gerçekleşen, Kalan, Maliyet Merkezi\n",
    "- **Zaman:** Başlangıç/Bitiş Tarihleri, Süre, Planlanan/Gerçekleşen\n",
    "- **Durum Kodları:** 1=Aktif, 0=Pasif\n\n",

    "### MEVCUT SÜTUNLAR VE DEĞER ÖZETLERİ (Filtre degerlerini buradaki gercek verilere gore sec):\n",
    cols_summary, "\n\n",

    "### GÖREV KURALLARI:\n",
    "1. **GENEL SORULARDA FİLTRE KULLANMA:** \n",
    "   - Kullanıcı 'kaç proje var', 'toplam', 'tüm', 'hepsi', 'dağılım', 'liste' gibi kelimeler kullanıyorsa,\n",
    "   - VE spesifik bir kod/isim BELİRTMİYORSA,\n",
    "   - -> filters: [] (BOŞ DİZİ döndür)\n",
    "   - Aggregation olarak 'count' veya 'group_by' kullanabilirsin.\n\n",

    "2. **SPESİFİK SORULARDA FİLTRE EKLE:**\n",
    "   - Proje kodu (P123), masraf yeri (M1), kişi adı (Ahmet Yılmaz) gibi BELİRLİ varlıklar belirtilmişse,\n",
    "   - -> Bu varlıkları filters dizisine ekle.\n\n",

    "3. **Çoklu Filtreleme:** Kullanıcı birden fazla koşul belirtirse (örn: 'M1 masraf yerinde unvanı mühendis olanlar'), bunların hepsini 'filters' listesine ekle.\n",
    "4. **Esnek Eşleştirme:** Kullanıcının 'Mühendisler' dediği şeyi veride 'Mühendis' veya 'Engineer' olarak bulabilirsin. 'operation' alanını buna göre seç.\n",
    "5. **Büyük/Küçük Harf Duyarsız:** Filtre değerlerini olduğu gibi al, kod tarafında case-insensitive arama yapılacaktır.\n\n",

    "### MANTIKSAL OPERATÖRLER VE KOMPLEKS FİLTRELER:\n",
    "Standart 'filters' listesi her zaman 'AND' (VE) ile birleştirilir. Eğer 'OR' (VEYA) mantığı gerekiyorsa veya karmaşık parantezli işlemler varsa (A ve (B veya C)):\n",
    "- 'filter_expression' alanını doldur. Bu alan geçerli bir R data.table filtreleme stringi olmalıdır.\n",
    "- Örnek: \"(Durum == 'In Progress') & (KalanIscilik_sa > 5000 | MasrafYeri == 'IT')\"\n",
    "- String içinde sütun isimlerini aynen kullan.\n",
    "- String operatörleri: ==, !=, >, <, >=, <=, &, |, %in%\n",
    "- 'contains' benzeri işler için: grepl('değer', SutunAdi, ignore.case=TRUE)\n",
    "\U000026A0\U0000FE0F KRİTİK KURALLAR:\n",
    "1. Parantezleri mutlaka dengele! Açılan her '(' kapatılmalıdır.\n",
    "2. String içindeki değerler için TEK TIRNAK (') kullan. Çift tırnak (\") JSON yapısını bozar.\n",
    "3. Örnek: \"(Durum == 'Completed') | (grepl('Analiz', Aciklama))\"\n\n",

    "### ÇIKTI FORMATI (JSON):\n",
    "{\n",
    "  \"filters\": [ ... ], \n",
    "  \"filter_expression\": null, // Karmaşık mantık (OR/AND) gerekiyorsa string ifade. Örn: \"(A==1 | B==2)\". Yoksa null.\n",
    "  \"aggregation\": \"count\",\n",
    "  \"group_column\": null\n",
    "}\n\n",

    "### ALAN DEĞERLERİ (DOMAIN MAPPINGS):\n",
    "Bazı alanlar sayısal veya kodlanmış değerler kullanır:\n",
    "- **AktifKaynak, Durum, Status**: 1 (aktif/yes), 0 (pasif/no)\n",
    "- **Onay, Approval**: 1 (onaylı), 0 (onaysız)\n",
    "Kullanıcı 'aktif', 'Y', 'yes' derse -> value: '1' kullan.\n",
    "Kullanıcı 'pasif', 'N', 'no' derse -> value: '0' kullan.\n\n",

    "### OPERATÖRLER ('operation'):\n",
    "- 'exact_match': Kodlar ve ID'ler için (örn: P101, M1).\n",
    "- 'contains': İsimler, açıklamalar ve metin aramaları için (örn: 'İnşaat içeren projeler').\n",
    "- 'greater_than', 'less_than': Sayısal değerler ve tarihler için (örn: 'Bütçesi 1000'den büyük').\n\n",

    "### AGGREGATION TİPLERİ ('aggregation'):\n",
    "- 'list': Kayıtları listele (Varsayılan).\n",
    "- 'count': Kayıt sayısını ver (Kaç adet?).\n",
    "- 'sum': Sayısal sütunu topla (Toplam bütçe).\n",
    "- 'group_by': Gruplayarak özetle (Departman bazında dağılım).\n\n",

    "### ÖRNEKLER:\n",
    "Soru: 'P1111 proje kodlu projeyi özetle'\n",
    "-> {\"filters\":[{\"column\":\"ProjeKodu\",\"value\":\"P1111\",\"operation\":\"exact_match\"}], \"aggregation\":\"list\", \"group_column\":null}\n\n",

    "Soru: 'M1 masraf yerinde unvanı mühendis olan çalışanları listele'\n",
    "-> {\"filters\":[{\"column\":\"MasrafYeri\",\"value\":\"M1\",\"operation\":\"exact_match\"}, {\"column\":\"Unvan\",\"value\":\"Mühendis\",\"operation\":\"contains\"}], \"aggregation\":\"list\", \"group_column\":null}\n\n",

    "Soru: 'Hangi departmanlarda kaç proje var?'\n",
    "-> {\"filters\":[], \"aggregation\":\"group_by\", \"group_column\":\"Departman\"}\n\n",

    "Soru: 'Ali Demir hangi projeleri yönetiyor?'\n",
    "-> {\"filters\":[{\"column\":\"ProjeYoneticisi\",\"value\":\"Ali Demir\",\"operation\":\"contains\"}], \"aggregation\":\"list\", \"group_column\":null}\n\n",

    "Soru: 'Aktif kaynakları göster'\n",
    "-> {\"filters\":[{\"column\":\"AktifKaynak\",\"value\":\"1\",\"operation\":\"exact_match\"}], \"aggregation\":\"list\", \"group_column\":null}\n\n",

    "Soru: 'Pasif projeleri listele'\n",
    "-> {\"filters\":[{\"column\":\"Durum\",\"value\":\"0\",\"operation\":\"exact_match\"}], \"aggregation\":\"list\", \"group_column\":null}\n\n",

    "SADECE GEÇERLİ JSON DÖNDÜR. YORUM EKLEME."
  )

  messages <- list(
    list(role = "system", content = system_instruction),
    list(role = "user", content = user_prompt)
  )

  tryCatch({
    if (is.function(stop_check) && isTRUE(stop_check())) {
      cat("[FILTER_AI] Durdurma talebi alindi (LLM cagrisinin hemen oncesi)\n")
      return(list(filters = list(), aggregation = NULL))
    }

    filter_model <- getOption("mergen.filter_model", api_config$local_models[1])
    creds <- resolve_local_llm_credentials(filter_model)

    api_key_val <- NULL
    if (!is.null(session) && !is.null(session$userData$ai_api_key)) {
      api_key_val <- as.character(session$userData$ai_api_key)[1]
    }

    if (is.null(api_key_val) || !nzchar(api_key_val)) {
      default_key <- creds$default_api_key %||% ""
      if (nzchar(default_key)) {
        api_key_val <- as.character(default_key)[1]
      }
    }

    filter_timeout <- 8
    result <- tryCatch({
      R.utils::withTimeout({
        call_local_llm(messages, list(
          model_selection = filter_model,
          temperature = 0.0,
          max_output_tokens = 4000,
          enable_mcp_tools = FALSE,
          shiny_session = session,
          api_key_override = api_key_val
        ))
      }, timeout = filter_timeout, onTimeout = "silent")
    }, error = function(e) {
      cat("[FILTER_AI] Timeout veya hata, AI filtreleme atlanıyor\n")
      NULL
    })

    if (is.function(stop_check) && isTRUE(stop_check())) {
      cat("[FILTER_AI] Durdurma talebi alindi (LLM cagrisi sonrasinda)\n")
      return(list(filters = list(), aggregation = NULL))
    }

    if (is.null(result)) return(list(filters = list(), aggregation = NULL))

    ai_content <- if (is.list(result)) result$content else result
    if (is.null(ai_content) || length(ai_content) == 0) return(list(filters = list(), aggregation = NULL))

    ai_text <- as.character(ai_content)[1]
    ai_text <- gsub("```json|```", "", ai_text)
    ai_text <- trimws(ai_text)

    if (nchar(ai_text) < 50) {
      cat(sprintf("[FILTER_AI] Yanit cok kisa (%d karakter), iptal ediliyor.\n", nchar(ai_text)))
      return(list(filters = list(), aggregation = NULL))
    }

    if (!grepl("\\{.*\\}", ai_text)) {
      cat("[FILTER_AI] JSON format algilanamadi.\n")
      return(list(filters = list(), aggregation = NULL))
    }

    parsed <- tryCatch({
      temp_parse <- jsonlite::fromJSON(ai_text, simplifyVector = FALSE)
      if (is.null(temp_parse)) {
        ai_text_fixed <- paste0(ai_text, ']}' )
        jsonlite::fromJSON(ai_text_fixed, simplifyVector = FALSE)
      } else {
        temp_parse
      }
    }, error = function(e) {
      cat(sprintf("[FILTER_AI] JSON parse hatasi: %s\n", e$message))
      NULL
    })

    if (is.null(parsed)) return(list(filters = list(), aggregation = NULL))

    filters <- parsed$filters
    if (is.null(filters) || !is.list(filters)) filters <- list()

    if (length(filters) > 0) {
      filters <- lapply(filters, function(f) {
        col_lower <- tolower(f$column %||% "")
        val_raw <- f$value %||% ""

        if (grepl("aktif|active|durum|status", col_lower, perl = TRUE)) {
          val_lower <- tolower(as.character(val_raw))
          if (val_lower %in% c("y", "yes", "evet", "aktif", "active", "1", "true")) {
            f$value <- "1"
            f$operation <- "exact_match"
          } else if (val_lower %in% c("n", "no", "hayır", "pasif", "passive", "inactive", "0", "false")) {
            f$value <- "0"
            f$operation <- "exact_match"
          }
        }

        f
      })
    }

    if (!is.null(parsed$filter_column)) {
      filters <- list(list(
        column = parsed$filter_column,
        value = parsed$filter_value,
        operation = parsed$operation
      ))
    }

    if (length(filters) > 0) {
      valid_filters <- Filter(function(f) {
        !is.null(f$column) && nzchar(f$column) && !is.null(f$value)
      }, filters)

      if (length(valid_filters) == 0) {
        cat("[FILTER_AI] Tum filtreler gecersiz, iptal ediliyor.\n")
        return(list(filters = list(), aggregation = NULL))
      }

      cat(sprintf("[FILTER_AI] %d gecerli filtre algilandi.\n", length(valid_filters)))
      filters <- valid_filters
    }

    return(list(
      filters = filters,
      filter_expression = parsed$filter_expression,
      aggregation = parsed$aggregation,
      group_column = parsed$group_column
    ))

  }, error = function(e) {
    cat(sprintf("[FILTER_AI] Error: %s\n", e$message))
    return(list(filters = list(), aggregation = NULL))
  })
}

apply_smart_filters <- function(data, filter_instructions, user_prompt) {
  cat(sprintf("[SMART_FILTER] Baslangic satir: %d\n", nrow(data)))

  if (nrow(data) == 0) return(data.frame())

  dt <- data.table::as.data.table(data)

  filters <- filter_instructions$filters
  aggregation <- filter_instructions$aggregation
  group_col <- filter_instructions$group_column

  genel_soru_kaliplari <- c(
    "kaç", "toplam", "sayı", "adet", "hangi", "dağılım", "özet",
    "analiz", "liste", "göster", "tüm", "hepsi", "en fazla",
    "en az", "ortalama", "maksimum", "minimum"
  )

  prompt_lower <- tolower(user_prompt)
  genel_soru_mu <- any(sapply(genel_soru_kaliplari, function(pattern) {
    grepl(pattern, prompt_lower, fixed = TRUE)
  }))

  spesifik_varlik_var <- grepl("\\b[A-Z][0-9]{3,}\\b|\\b[A-Z]{1,3}[0-9]{1,}\\b", user_prompt, perl = TRUE) ||
    grepl("[A-ZÜĞIŞÖÇ][a-züğışöç]+ [A-ZÜĞIŞÖÇ][a-züğışöç]+", user_prompt, perl = TRUE)

  if (genel_soru_mu && !spesifik_varlik_var && (is.null(filters) || length(filters) == 0)) {
    cat("[SMART_FILTER] GENEL SORU tespit edildi, filtre UYGULANMAYACAK.\n")
    filters <- list()
  }

  cat(sprintf(
    "[SMART_FILTER] Filtre sayisi: %d (Genel soru: %s, Spesifik varlik: %s)\n",
    length(filters %||% list()),
    genel_soru_mu,
    spesifik_varlik_var
  ))

  cat(sprintf("[SMART_FILTER] Filtre sayisi: %d\n", length(filters %||% list())))
  if (length(filters) > 0) {
    for (i in seq_along(filters)) {
      f <- filters[[i]]
      cat(sprintf(
        "[SMART_FILTER] Filtre #%d: sutun='%s', deger='%s', islem='%s'\n",
        i,
        f$column %||% "NULL",
        f$value %||% "NULL",
        f$operation %||% "NULL"
      ))
    }
  }

  applied_expression_success <- FALSE

  if (!is.null(filter_instructions$filter_expression) && nzchar(filter_instructions$filter_expression)) {
    cat(sprintf("[SMART_FILTER] Kompleks İfade Tespit Edildi: %s\n", filter_instructions$filter_expression))

    tryCatch({
      expr_str <- filter_instructions$filter_expression
      dt <- subset(dt, eval(parse(text = expr_str)))

      cat(sprintf("[SMART_FILTER] İfade başarıyla uygulandı. Kalan satır: %d\n", nrow(dt)))
      applied_expression_success <- TRUE
    }, error = function(e) {
      cat(sprintf("[SMART_FILTER] HATA: İfade uygulanamadı (%s). Standart filtre listesine (AND) dönülüyor.\n", e$message))
      applied_expression_success <- FALSE
    })
  }

  if (!applied_expression_success) {
    if (!is.null(filters) && length(filters) > 0) {
      cat("[SMART_FILTER] Standart filtre listesi uygulanıyor (AND mantığı)...\n")

      for (f in filters) {
        col <- f$column
        val <- f$value
        op <- f$operation %||% "exact_match"

        if (!is.null(col) && nzchar(as.character(col)[1]) && col %in% names(dt)) {
          col_vals <- dt[[col]]
          val_str <- as.character(val)[1]

          if (is.character(col_vals) || is.factor(col_vals)) {
            val_regex <- gsub("([.|()\\^{}+$*?]|\\[|\\])", "\\\\\\1", val_str)
            col_vals_char <- as.character(col_vals)

            if (op == "exact_match") {
              dt <- dt[grepl(paste0("^", val_regex, "$"), col_vals_char, ignore.case = TRUE), ]
            } else if (op == "contains") {
              dt <- dt[grepl(val_regex, col_vals_char, ignore.case = TRUE), ]
            } else {
              dt <- dt[grepl(paste0("^", val_regex, "$"), col_vals_char, ignore.case = TRUE), ]
            }
          } else if (is.numeric(col_vals)) {
            val_num <- suppressWarnings(as.numeric(val_str))
            if (!is.na(val_num)) {
              if (op == "greater_than") {
                dt <- dt[col_vals > val_num, ]
              } else if (op == "less_than") {
                dt <- dt[col_vals < val_num, ]
              } else {
                dt <- dt[col_vals == val_num, ]
              }
            }
          }
        }
      }
    } else {
      if (is.null(aggregation) || !tolower(aggregation) %in% c("count", "sum", "group_by")) {
        cat(sprintf(
          "[SMART_FILTER] Ne filtre ne aggregation var. GENEL SORU olarak işleniyor - tüm veri döndürülecek (%d satır).\n",
          nrow(dt)
        ))
      } else {
        cat("[SMART_FILTER] Aggregation mevcut, filtre yok - tüm veri üzerinde aggregation yapılacak\n")
      }
    }
  }

  if (!is.null(aggregation)) {
    agg_str <- tolower(aggregation)

    if (agg_str == "count") {
      aciklama <- if (length(filters) > 0) "Filtrelenen Kayıt Sayısı" else "Toplam Kayıt Sayısı"
      return(data.frame(Sonuc = aciklama, Adet = nrow(dt)))
    } else if (agg_str == "sum") {
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      if (length(num_cols) > 0) {
        sums <- lapply(num_cols, function(nc) sum(dt[[nc]], na.rm = TRUE))
        return(as.data.frame(sums))
      }
    } else if (agg_str == "group_by" && !is.null(group_col) && group_col %in% names(dt)) {
      return(as.data.frame(dt[, .N, by = group_col]))
    }
  }

  as.data.frame(dt)
}