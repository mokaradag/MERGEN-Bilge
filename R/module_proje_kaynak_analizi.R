# R/module_proje_kaynak_analizi.R

# ==============================================================================
# 0. AKıLLı FİLTRELEME MOTORü (AI-Guided Filtering Engine)
# ==============================================================================

extract_filter_criteria_from_prompt <- function(user_prompt, available_columns, conn) {
  cat(sprintf("[FILTER_AI] Prompt analiz ediliyor: '%s'\n", user_prompt))
  
  cols_str <- paste(available_columns, collapse = ", ")
  
  system_instruction <- paste0(
    "Sen Primavera P6 proje yönetim sisteminde veri filtreleme uzmanısın.\n\n",
    "MEVCUT SÜTUNLAR: ", cols_str, "\n\n",
    "ÇIKTI FORMATI (SADECE JSON, HİÇBİR EK AÇIKLAMA YOK):\n",
    "{\n",
    "  \"filter_column\": \"SütunAdı\",\n",
    "  \"filter_value\": \"AranacakDeğer\",\n",
    "  \"operation\": \"exact_match\",\n",
    "  \"aggregation\": \"count\",\n",
    "  \"group_column\": null\n",
    "}\n\n",
    "SÜTUN SEÇİMİ KURALLARI:\n",
    "- Proje kodu (P1111, PRJ-001): ProjeKodu, Proje_Kodu, ProjectCode, project_id\n",
    "- Proje adı: ProjeAdi, Proje_Adi, ProjeIsmi, ProjectName, project_name\n",
    "- Kaynak kodu/adı: KaynakKodu, Kaynak_Kodu, KaynakAdi, ResourceCode, resource_name\n",
    "- Faaliyet kodu/adı: FaaliyetKodu, Faaliyet_Kodu, ActivityCode, task_name\n",
    "- Departman: Departman, Department, Birim\n",
    "- Durum: Durum, Status, ProjectStatus, proje_durumu\n",
    "- Bütçe: Butce, Budget, BütçeTutarı, budget_amount\n",
    "- Tarih: BaslangicTarihi, BitisTarihi, StartDate, FinishDate\n",
    "- Yönetici: ProjeYoneticisi, Yönetici, ProjectManager, manager_name\n",
    "- WBS: WBSKodu, WBS_Kodu, WBSAdi\n",
    "\n",
    "OPERATION SEÇİMİ:\n",
    "- Kod/ID eşleşmesi (P1111, RES-001): exact_match\n",
    "- Ad/metin araması (içeren): contains\n",
    "- Sayısal karşılaştırma (büyük/küçük): greater_than, less_than\n",
    "\n",
    "AGGREGATION SEÇİMİ:\n",
    "- 'kaç', 'toplam sayı', 'adet': count\n",
    "- 'listele', 'göster', 'özetle': list\n",
    "- 'topla', 'sum', 'toplam tutar': sum\n",
    "- 'grupla', 'kırılımında', 'dağılımı': group_by (group_column belirt)\n",
    "- 'ortalama': mean\n",
    "\n",
    "GROUP_COLUMN SEÇİMİ (aggregation='group_by' ise):\n",
    "- 'departman bazında': Departman\n",
    "- 'durum bazında': Durum\n",
    "- 'yönetici bazında': ProjeYoneticisi\n",
    "- 'kaynak bazında': KaynakAdi\n",
    "\n",
    "ÖRNEKLER:\n",
    "Soru: 'P1111 proje kodlu projeyi özetle'\n",
    "→ {\"filter_column\":\"ProjeKodu\",\"filter_value\":\"P1111\",\"operation\":\"exact_match\",\"aggregation\":\"list\",\"group_column\":null}\n\n",
    "Soru: 'Kaç proje aktif durumda?'\n",
    "→ {\"filter_column\":\"Durum\",\"filter_value\":\"Aktif\",\"operation\":\"exact_match\",\"aggregation\":\"count\",\"group_column\":null}\n\n",
    "Soru: 'Ali Veli isimli kaynak hangi projelerde çalışıyor?'\n",
    "→ {\"filter_column\":\"KaynakAdi\",\"filter_value\":\"Ali Veli\",\"operation\":\"contains\",\"aggregation\":\"list\",\"group_column\":null}\n\n",
    "Soru: 'Departman bazında toplam bütçe nedir?'\n",
    "→ {\"filter_column\":null,\"filter_value\":null,\"operation\":\"exact_match\",\"aggregation\":\"group_by\",\"group_column\":\"Departman\"}\n\n",
    "Soru: 'İnşaat kelimesini içeren projeleri listele'\n",
    "→ {\"filter_column\":\"ProjeAdi\",\"filter_value\":\"İnşaat\",\"operation\":\"contains\",\"aggregation\":\"list\",\"group_column\":null}\n\n",
    "SADECE JSON DÖNDÜR, BAŞKA HİÇBİR ŞEY YAZMA."
  )
  
  messages <- list(
    list(role = "system", content = system_instruction),
    list(role = "user", content = user_prompt)
  )
  
  tryCatch({
    result <- call_local_llm(messages, list(
      model_selection = getOption("mergen.filter_model", api_config$local_models[1]),
      temperature = 0.05,
      max_output_tokens = 300,
      enable_mcp_tools = FALSE,
      shiny_session = NULL
    ))
    
    if (is.null(result)) {
      cat("[FILTER_AI] LLM call returned NULL\n")
      return(list(filter_column = NULL, aggregation = NULL, error = "AI cagirimi basarisiz"))
    }
    
    if (!is.list(result)) {
      cat("[FILTER_AI] LLM result not a list, class:", class(result), "\n")
      return(list(filter_column = NULL, aggregation = NULL, error = "Gecersiz AI yanitı"))
    }
    
    ai_content <- if (is.list(result)) result$content else result
    
    if (is.null(ai_content) || !is.character(ai_content) || length(ai_content) == 0) {
      cat("[FILTER_AI] content NULL veya invalid, fallback\n")
      return(list(filter_column = NULL, aggregation = NULL))
    }
    
    ai_text <- as.character(ai_content)[1]
    ai_text <- gsub("```json|```", "", ai_text)
    ai_text <- trimws(ai_text)
    
    if (!nzchar(ai_text)) {
      cat("[FILTER_AI] AI boş yanıt verdi, fallback\n")
      return(list(filter_column = NULL, aggregation = NULL))
    }
    
    cat(sprintf("[FILTER_AI] AI yanıtı: %s\n", substr(ai_text, 1, 200)))
    
	parsed <- tryCatch(
      jsonlite::fromJSON(ai_text, simplifyVector = FALSE),
      error = function(e) {
        cat(sprintf("[FILTER_AI] JSON parse hatasi: %s\n", e$message))
        cat(sprintf("[FILTER_AI] Problematic text: %s\n", substr(ai_text, 1, 500)))
        NULL
      }
    )
    
    if (is.null(parsed) || !is.list(parsed)) {
      cat("[FILTER_AI] Parsed NULL veya liste degil\n")
      cat("[FILTER_AI] AI TEXT:", substr(ai_text, 1, 300), "\n")
      return(list(filter_column = NULL, aggregation = NULL, error = "JSON parse hatasi"))
    }
    
    required_keys <- c("filter_column", "operation", "aggregation")
    missing_keys <- setdiff(required_keys, names(parsed))
    if (length(missing_keys) > 0) {
      cat("[FILTER_AI] Eksik anahtarlar:", paste(missing_keys, collapse = ", "), "\n")
    }
    
    fc <- parsed$filter_column
    fv <- parsed$filter_value
    op <- parsed$operation
    ag <- parsed$aggregation
    gc <- parsed$group_column
    
    if (!is.null(fc) && is.character(fc) && length(fc) > 0) {
      fc <- as.character(fc)[1]
    } else {
      fc <- NULL
    }
    
    if (!is.null(fv) && length(fv) > 0) {
      fv <- as.character(fv)[1]
    } else {
      fv <- NULL
    }
    
    if (!is.null(op) && is.character(op) && length(op) > 0) {
      op <- as.character(op)[1]
    } else {
      op <- "exact_match"
    }
    
    if (!is.null(ag) && is.character(ag) && length(ag) > 0) {
      ag <- as.character(ag)[1]
    } else {
      ag <- NULL
    }
    
    if (!is.null(gc) && is.character(gc) && length(gc) > 0) {
      gc <- as.character(gc)[1]
    } else {
      gc <- NULL
    }
    
    result_list <- list(
      filter_column = fc,
      filter_value = fv,
      operation = op,
      aggregation = ag,
      group_column = gc
    )
    
    cat(sprintf("[FILTER_AI] Başarılı: filter_column=%s, value=%s, op=%s, agg=%s\n",
                fc %||% "NULL", fv %||% "NULL", op %||% "NULL", ag %||% "NULL"))
    
    return(result_list)
    
  }, error = function(e) {
    cat(sprintf("[FILTER_AI] Genel hata: %s\n", e$message))
    cat(sprintf("[FILTER_AI] Stack trace:\n"))
    print(sys.calls())
    return(list(filter_column = NULL, aggregation = NULL))
  })
}

apply_smart_filters <- function(data, filter_instructions, user_prompt) {
  cat(sprintf("[SMART_FILTER] Başlangıç satır: %d\n", nrow(data)))
  
  if (nrow(data) == 0) return(data.frame())
  
  dt <- data.table::as.data.table(data)
  
  filter_col <- filter_instructions$filter_column
  filter_val <- filter_instructions$filter_value
  operation <- filter_instructions$operation %||% "exact_match"
  aggregation <- filter_instructions$aggregation
  group_col <- filter_instructions$group_column
  
  if (is.null(filter_col) || !nzchar(as.character(filter_col)[1])) {
    cat("[SMART_FILTER] AI filtresi yok, keyword fallback\n")
    
    matches <- regmatches(user_prompt, gregexpr("\\b[A-Za-z0-9-]{3,}\\b", user_prompt))
    search_terms <- unique(unlist(matches))
    
    filtered_terms <- c()
    for (term in search_terms) {
      if ((grepl("[A-Za-z]", term) && grepl("[0-9]", term)) || 
          (nchar(term) >= 4 && grepl("^[A-Z0-9-]+$", toupper(term)))) {
        filtered_terms <- c(filtered_terms, term)
      }
    }
    
    if (!length(filtered_terms)) {
      cat("[SMART_FILTER] Keyword bulunamadı, tüm veri döndürülüyor\n")
      return(as.data.frame(head(dt, 500)))
    }
    
    cat(sprintf("[SMART_FILTER] Aranan: %s\n", paste(filtered_terms, collapse = ", ")))
    
    match_rows <- apply(dt, 1, function(row) {
      any(sapply(filtered_terms, function(term) {
        any(grepl(term, row, ignore.case = TRUE))
      }))
    })
    
    filtered <- dt[match_rows, ]
    
    if (nrow(filtered) == 0) {
      cat("[SMART_FILTER] Eşleşme yok, ilk 100 satır\n")
      return(as.data.frame(head(dt, 100)))
    }
    
    cat(sprintf("[SMART_FILTER] Keyword sonuç: %d satır\n", nrow(filtered)))
    return(as.data.frame(head(filtered, 500)))
  }
  
  filter_col_str <- as.character(filter_col)[1]
  
  if (!filter_col_str %in% names(dt)) {
    cat(sprintf("[SMART_FILTER] '%s' sütunu yok, tüm sütunlarda ara\n", filter_col_str))
    
    if (!is.null(filter_val) && nzchar(as.character(filter_val)[1])) {
      fv_str <- as.character(filter_val)[1]
      match_rows <- apply(dt, 1, function(row) {
        any(grepl(fv_str, row, ignore.case = TRUE))
      })
      dt <- dt[match_rows, ]
      cat(sprintf("[SMART_FILTER] Tüm sütunlarda '%s' arandı: %d satır\n", fv_str, nrow(dt)))
    }
    
    if (nrow(dt) == 0) {
      return(data.frame())
    }
  } else {
    if (!is.null(filter_val) && nzchar(as.character(filter_val)[1])) {
      fv_str <- as.character(filter_val)[1]
      
      cat(sprintf("[SMART_FILTER] '%s' sütununda '%s' aranıyor (op: %s)\n", 
                  filter_col_str, fv_str, operation))
      
      if (operation == "exact_match") {
        dt <- dt[get(filter_col_str) == fv_str]
      } else if (operation == "contains") {
        dt <- dt[grepl(fv_str, get(filter_col_str), ignore.case = TRUE)]
      } else if (operation == "greater_than") {
        dt <- dt[get(filter_col_str) > as.numeric(fv_str)]
      } else if (operation == "less_than") {
        dt <- dt[get(filter_col_str) < as.numeric(fv_str)]
      } else {
        dt <- dt[grepl(fv_str, get(filter_col_str), ignore.case = TRUE)]
      }
      
      cat(sprintf("[SMART_FILTER] Filtreleme sonrası: %d satır\n", nrow(dt)))
    }
  }
  
  if (nrow(dt) == 0) {
    cat("[SMART_FILTER] Filtre sonucu boş\n")
    return(data.frame())
  }
  
if (!is.null(aggregation) && nzchar(as.character(aggregation)[1])) {
    agg_str <- as.character(aggregation)[1]
    
    if (agg_str == "count") {
      if (!is.null(group_col) && nzchar(as.character(group_col)[1]) && 
          as.character(group_col)[1] %in% names(dt)) {
        gc_str <- as.character(group_col)[1]
        result <- dt[, .N, by = gc_str]
        setnames(result, "N", "Adet")
        result <- result[order(-Adet)]
        cat(sprintf("[SMART_FILTER] COUNT+GROUP: %d grup (siralanmis)\n", nrow(result)))
        return(as.data.frame(result))
      } else {
        result <- data.frame(
          Metrik = "Toplam Kayit Sayisi",
          Deger = nrow(dt)
        )
        cat(sprintf("[SMART_FILTER] COUNT: %d kayit\n", nrow(dt)))
        return(result)
      }
    } else if (agg_str == "sum" || agg_str == "mean" || agg_str == "avg") {
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      if (length(num_cols) == 0) {
        cat("[SMART_FILTER] UYARI: Sayisal sutun yok, toplama/ortalama yapilamaz\n")
        return(as.data.frame(head(dt, 100)))
      }
      
      target_col <- num_cols[1]
      
      if (!is.null(group_col) && nzchar(as.character(group_col)[1]) && 
          as.character(group_col)[1] %in% names(dt)) {
        gc_str <- as.character(group_col)[1]
        
        if (agg_str %in% c("sum")) {
          result <- dt[, .(Toplam = sum(get(target_col), na.rm = TRUE)), by = gc_str]
        } else {
          result <- dt[, .(Ortalama = mean(get(target_col), na.rm = TRUE)), by = gc_str]
        }
        result <- result[order(-get(names(result)[2]))]
        cat(sprintf("[SMART_FILTER] %s+GROUP: %d grup\n", toupper(agg_str), nrow(result)))
        return(as.data.frame(result))
      } else {
        val <- if (agg_str == "sum") sum(dt[[target_col]], na.rm = TRUE) else mean(dt[[target_col]], na.rm = TRUE)
        result <- data.frame(
          Metrik = paste0(ifelse(agg_str == "sum", "Toplam", "Ortalama"), " (", target_col, ")"),
          Deger = val
        )
        cat(sprintf("[SMART_FILTER] %s: %.2f\n", toupper(agg_str), val))
        return(result)
      }
    } else if (agg_str == "group_by" && !is.null(group_col) && 
               nzchar(as.character(group_col)[1]) && 
               as.character(group_col)[1] %in% names(dt)) {
      gc_str <- as.character(group_col)[1]
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      
      if (length(num_cols) > 0) {
        agg_expr <- lapply(num_cols, function(col) {
          list(sum(get(col), na.rm = TRUE), mean(get(col), na.rm = TRUE))
        })
        agg_names <- unlist(lapply(num_cols, function(col) c(paste0("Toplam_", col), paste0("Ort_", col))))
        names(agg_expr) <- agg_names
        result <- dt[, c(.N, unlist(agg_expr, recursive = FALSE)), by = gc_str]
        setnames(result, "N", "Kayit_Sayisi")
      } else {
        result <- dt[, .N, by = gc_str]
        setnames(result, "N", "Kayit_Sayisi")
      }
      
      result <- result[order(-Kayit_Sayisi)]
      cat(sprintf("[SMART_FILTER] GROUP_BY: %d grup (siralanmis)\n", nrow(result)))
      return(as.data.frame(result))
    }
  }
  
  result <- head(dt, 500)
  cat(sprintf("[SMART_FILTER] Sonuç: %d satır (limit: 500)\n", nrow(result)))
  return(as.data.frame(result))
}

# ==============================================================================
# 1. RLS ve YETKİ YÖNETİMİ (SECURITY ENGINE)
# ==============================================================================

get_user_rls_info <- function(username, conn) {
  cat(sprintf("[PK_ANALIZ] get_user_rls_info calistiriliyor. Kullanici: %s\n", username))
  
  # 1. DC01_user_base tablosundan temel yetkileri çek
  base_query <- "SELECT TOP 1 * FROM DC01_user_base WHERE KullaniciAdi = ?"
  user_base <- tryCatch({
    DBI::dbGetQuery(conn, base_query, params = list(username))
  }, error = function(e) {
    cat(sprintf("[PK_ANALIZ] HATA (DC01_user_base): %s\n", e$message))
    return(data.frame())
  })
  
  if (nrow(user_base) == 0) {
    cat("[PK_ANALIZ] Kullanici DC01 tablosunda bulunamadi.\n")
    return(list(authorized = FALSE, reason = "Kullanıcı DC01 tablosunda bulunamadı."))
  }
  
  info <- as.list(user_base[1, ])
  info$authorized <- TRUE
  cat(sprintf("[PK_ANALIZ] Yetki Tipi: %s, MasrafYeri: %s\n", info$Yetki, info$MasrafYeriKodu))
  
  # Masraf Yeri (Department) Parse Et
  if (!is.na(info$MasrafYeriKodu) && info$MasrafYeriKodu != "ADMIN") {
    info$allowed_depts <- trimws(unlist(strsplit(as.character(info$MasrafYeriKodu), ",")))
  } else {
    info$allowed_depts <- NULL # ADMIN veya hepsi
  }
  
  # 2. Yetki Tipine Göre Ek Kısıtlamaları (PY, KY-P, DIR-P) Çek
  info$allowed_projects <- NULL
  info$allowed_eps <- NULL
  
  if (info$Yetki == "PY") {
    cat("[PK_ANALIZ] PY yetkisi kontrol ediliyor...\n")
    py_res <- tryCatch(DBI::dbGetQuery(conn, sql_permission_py), error = function(e) NULL)
    if (!is.null(py_res)) {
      user_rows <- py_res[py_res$KullaniciAdi == username, ]
      if (nrow(user_rows) > 0) {
        all_projs <- paste(user_rows$ProjeKodu, collapse = ",")
        info$allowed_projects <- unique(trimws(unlist(strsplit(all_projs, ","))))
        cat(sprintf("[PK_ANALIZ] PY Projeleri: %s\n", paste(info$allowed_projects, collapse=",")))
      }
    }
  }
  
  if (info$Yetki %in% c("KY-P", "DIR-P")) {
    cat("[PK_ANALIZ] Program (EPS) yetkisi kontrol ediliyor...\n")
    eps_res <- tryCatch(DBI::dbGetQuery(conn, sql_permission_eps), error = function(e) NULL)
    if (!is.null(eps_res)) {
      user_rows <- eps_res[eps_res$KullaniciAdi == username, ]
      if (nrow(user_rows) > 0) {
        all_eps <- paste(user_rows$EPSKodu, collapse = ",")
        info$allowed_eps <- unique(trimws(unlist(strsplit(all_eps, ","))))
        cat(sprintf("[PK_ANALIZ] EPS Kodlari: %s\n", paste(info$allowed_eps, collapse=",")))
      }
    }
  }
  
  return(info)
}

apply_rls_to_data <- function(data, user_info, rls_cols) {
  if (nrow(data) == 0) return(data)
  
  cat(sprintf("[PK_ANALIZ] RLS Uygulaniyor. Ham satir sayisi: %d\n", nrow(data)))
  filtered_data <- data
  yetki <- user_info$Yetki
  
  if (yetki == "ADMIN") {
    cat("[PK_ANALIZ] Rol ADMIN -> Filtre uygulanmadi.\n")
    return(filtered_data)
  }
  
  # Masraf Yeri Filtresi
  if (!is.null(user_info$allowed_depts) && !is.null(rls_cols$masraf_yeri_col)) {
    col_name <- rls_cols$masraf_yeri_col
    if (col_name %in% names(filtered_data)) {
      filtered_data <- filtered_data[filtered_data[[col_name]] %in% user_info$allowed_depts, ]
      cat(sprintf("[PK_ANALIZ] Masraf Yeri Filtresi Sonrasi: %d satir\n", nrow(filtered_data)))
    }
  }
  
  # PY Filtresi
  if (yetki == "PY" && !is.null(user_info$allowed_projects) && !is.null(rls_cols$proje_kodu_col)) {
    col_name <- rls_cols$proje_kodu_col
    if (col_name %in% names(filtered_data)) {
      filtered_data <- filtered_data[filtered_data[[col_name]] %in% user_info$allowed_projects, ]
      cat(sprintf("[PK_ANALIZ] PY Filtresi Sonrasi: %d satir\n", nrow(filtered_data)))
    }
  }
  
  # EPS Filtresi
  if (yetki %in% c("KY-P", "DIR-P") && !is.null(user_info$allowed_eps) && !is.null(rls_cols$eps_kodu_col)) {
    col_name <- rls_cols$eps_kodu_col
    if (col_name %in% names(filtered_data)) {
      filtered_data <- filtered_data[filtered_data[[col_name]] %in% user_info$allowed_eps, ]
      cat(sprintf("[PK_ANALIZ] EPS Filtresi Sonrasi: %d satir\n", nrow(filtered_data)))
    }
  }
  
  return(filtered_data)
}

generate_statistical_summary <- function(data, max_preview_rows = 20) {
  if (is.null(data) || nrow(data) == 0) {
    return(list(
      summary_text = "Veri yok.",
      row_count = 0,
      preview_data = NULL
    ))
  }
  
  total_rows <- nrow(data)
  total_cols <- ncol(data)
  col_names <- names(data)
  
  dt <- data.table::as.data.table(data)
  
  num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
  cat_cols <- names(dt)[vapply(dt, function(x) is.character(x) || is.factor(x), logical(1))]
  
  summary_parts <- list()
  summary_parts[[1]] <- sprintf("TOPLAM SATIR: %d | TOPLAM SUTUN: %d", total_rows, total_cols)
  
  if (length(num_cols) > 0) {
    num_summary_list <- lapply(num_cols, function(col) {
      vals <- dt[[col]]
      vals <- vals[!is.na(vals)]
      if (length(vals) == 0) return(NULL)
      
      data.frame(
        Sutun = col,
        Toplam = sum(vals, na.rm = TRUE),
        Ortalama = mean(vals, na.rm = TRUE),
        Medyan = median(vals, na.rm = TRUE),
        Min = min(vals, na.rm = TRUE),
        Max = max(vals, na.rm = TRUE),
        StdSapma = sd(vals, na.rm = TRUE),
        Kayit = length(vals),
        stringsAsFactors = FALSE
      )
    })
    
    num_summary_df <- do.call(rbind, Filter(Negate(is.null), num_summary_list))
    
    if (!is.null(num_summary_df) && nrow(num_summary_df) > 0) {
      summary_parts[[length(summary_parts) + 1]] <- "\n\nSAYISAL SUTUNLAR OZETI:"
      summary_parts[[length(summary_parts) + 1]] <- paste(capture.output(print(num_summary_df, row.names = FALSE)), collapse = "\n")
    }
  }
  
  if (length(cat_cols) > 0) {
    cat_summary_list <- lapply(head(cat_cols, 5), function(col) {
      tbl <- sort(table(dt[[col]], useNA = "no"), decreasing = TRUE)
      top5 <- head(tbl, 5)
      
      data.frame(
        Sutun = col,
        EnSikDeger = names(top5)[1],
        Adet = as.integer(top5[1]),
        BenzerSayi = length(unique(dt[[col]])),
        stringsAsFactors = FALSE
      )
    })
    
    cat_summary_df <- do.call(rbind, cat_summary_list)
    
    if (!is.null(cat_summary_df) && nrow(cat_summary_df) > 0) {
      summary_parts[[length(summary_parts) + 1]] <- "\n\nKATEGORIK SUTUNLAR OZETI:"
      summary_parts[[length(summary_parts) + 1]] <- paste(capture.output(print(cat_summary_df, row.names = FALSE)), collapse = "\n")
    }
  }
  
  preview_data <- NULL
  if (total_rows > max_preview_rows) {
    preview_data <- head(data, max_preview_rows)
    summary_parts[[length(summary_parts) + 1]] <- sprintf("\n\n(İlk %d satir gosteriliyor; toplam %d satir mevcut)", max_preview_rows, total_rows)
  } else {
    preview_data <- data
  }
  
  summary_text <- paste(summary_parts, collapse = "\n")
  
  return(list(
    summary_text = summary_text,
    row_count = total_rows,
    preview_data = preview_data
  ))
}

# ==============================================================================
# 2. SORGULAMA MOTORU (EXECUTION ENGINE)
# ==============================================================================

pk_analiz_process_request <- function(user_prompt, chat_history, session) {
  cat("\n[PK_ANALIZ] >>> pk_analiz_process_request BASLATILDI <<<\n")
  cat(sprintf("[PK_ANALIZ] Kullanici Prompt: '%s'\n", user_prompt))
  
  # A. Bağlantı Kur
  cat("[PK_ANALIZ] DB Baglantisi aliniyor...\n")
  conn_list <- get_connection()
  conn <- conn_list$conn
  on.exit({
    cat("[PK_ANALIZ] DB Baglantisi serbest birakiliyor.\n")
    release_connection(conn_list)
  })
  
  username <- session$userData$system_username %||% "Unknown"
  
  # B. Kullanıcı RLS Bilgisini Çek
  rls_info <- get_user_rls_info(username, conn)
  if (!isTRUE(rls_info$authorized)) {
    cat("[PK_ANALIZ] Yetki Hatasi: Kullanici bulunamadi.\n")
    return("⚠️ **Yetki Hatası:** Sistemde kullanıcı kaydınız (DC01_user_base) bulunamadı. Lütfen yönetici ile iletişime geçin.")
  }
  
  # C. Doğru Sorguyu Seç
  cat("[PK_ANALIZ] Akilli sorgu secimi yapiliyor (select_smart_query)...\n")
  selected_query <- select_smart_query(user_prompt, query_library, chat_history)
  
  if (is.null(selected_query)) {
    cat("[PK_ANALIZ] UYARI: Uygun bir sorgu ESLESMESI BULUNAMADI.\n")
    return("🤔 Aradığınız bilgi mevcut analiz kütüphanesinde bulunamadı. (Sorgu kütüphanesinde eşleşen anahtar kelime yok).")
  }
  
  cat(sprintf("[PK_ANALIZ] Secilen Sorgu: '%s' (Table: %s)\n", selected_query$name, selected_query$description))
   
  # 1. SQL İçeriğini Belirle (sql string veya sql_file dosyasından)
  sql_query_text <- ""

  # Oncelik: sql_file (Dosyadan oku)
  # Eger sql_file tanimliysa, sql metni yerine dosya icerigini kullanmayi zorla.
  if (!is.null(selected_query$sql_file) && nzchar(selected_query$sql_file)) {
    fpath <- selected_query$sql_file
    
    if (file.exists(fpath)) {
      cat(sprintf("[PK_ANALIZ] SQL dosyadan okunuyor: %s\n", fpath))
      
# Dosya içeriğini Binary (Raw) olarak oku
      f_con <- file(fpath, open = "rb")
      f_size <- file.info(fpath)$size
      if (is.na(f_size)) f_size <- 0
      raw_content <- readBin(f_con, "raw", n = f_size)
      close(f_con)
      
      sql_query_text <- ""
      
      if (length(raw_content) > 0) {
        # BOM Kontrolü (UTF-16 LE/BE)
        has_bom_le <- length(raw_content) >= 2 && raw_content[1] == as.raw(0xff) && raw_content[2] == as.raw(0xfe)
        has_bom_be <- length(raw_content) >= 2 && raw_content[1] == as.raw(0xfe) && raw_content[2] == as.raw(0xff)
        
        # Null Byte Varlığı (UTF-16 tespiti için)
        has_nulls <- any(raw_content == as.raw(0))
        
        if (has_bom_le) {
           sql_query_text <- iconv(list(raw_content), from = "UTF-16LE", to = "UTF-8")[[1]]
        } else if (has_bom_be) {
           sql_query_text <- iconv(list(raw_content), from = "UTF-16BE", to = "UTF-8")[[1]]
        } else if (has_nulls) {
           # BOM yok ama NULL var -> UTF-16. LE mi BE mi tahmini:
           # Eğer ilk byte NULL ise (ve ikincisi değilse) bu Big Endian (00 XX) yapısıdır.
           if (length(raw_content) >= 2 && raw_content[1] == as.raw(0) && raw_content[2] != as.raw(0)) {
              cat("[PK_ANALIZ] Dosya NULL byte içeriyor (BE tespiti), UTF-16BE deneniyor...\n")
              sql_query_text <- iconv(list(raw_content), from = "UTF-16BE", to = "UTF-8")[[1]]
           } else {
              cat("[PK_ANALIZ] Dosya NULL byte içeriyor, UTF-16LE deneniyor...\n")
              sql_query_text <- iconv(list(raw_content), from = "UTF-16LE", to = "UTF-8")[[1]]
           }
        } else {
           # UTF-8 veya WINDOWS-1254 (Türkçe) Kontrolü
           text_utf8 <- iconv(list(raw_content), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
           
           if (grepl("<[0-9a-fA-F]{2}>", text_utf8)) {
              cat("[PK_ANALIZ] Dosya UTF-8 değil (TR karakterler). WINDOWS-1254 kullanılıyor...\n")
              converted <- iconv(list(raw_content), from = "WINDOWS-1254", to = "UTF-8")
              sql_query_text <- if (length(converted) > 0 && !is.na(converted[[1]])) converted[[1]] else text_utf8
           } else {
              sql_query_text <- text_utf8
           }
        }
      }
      
      # Sadece UTF-8 BOM temizliği (Null temizliği kaldırıldı)
      sql_query_text <- gsub("^\ufeff", "", sql_query_text)
      
      cat(sprintf("[PK_ANALIZ] Okunan SQL uzunlugu: %d karakter\n", nchar(sql_query_text)))
      cat(sprintf("[PK_ANALIZ] SQL baslangici:\n%s\n[...]\n", substr(sql_query_text, 1, 200)))
      
    } else {
      cat(sprintf("[PK_ANALIZ] HATA: Belirtilen SQL dosyasi bulunamadi: %s\n", fpath))
      return(paste0("⚠️ **Yapılandırma Hatası:** SQL dosyası bulunamadı: ", fpath))
    }
  } 
  
  # Alternatif: sql (Direkt metin) - Sadece dosya tanimi yoksa ve metin bos ise buraya bak
  if (!nzchar(sql_query_text) && !is.null(selected_query$sql)) {
    sql_query_text <- selected_query$sql
  }

  # Hata Kontrolü: İçerik hala boş mu?
  if (!nzchar(sql_query_text)) {
    cat("[PK_ANALIZ] HATA: Ne sql_file ne de sql metni gecerli!\n")
    return("⚠️ **Yapılandırma Hatası:** Sorgu için SQL kodu bulunamadı.")
  }

	if (grepl("^[a-zA-Z]:[\\\\/]|^[\\\\/]{2}|^\\./|^\\.\\./|^[^/\\\\]+[\\\\/]", sql_query_text)) {
	  cat(sprintf("[PK_ANALIZ] KRITIK HATA: sql_query_text dosya yolu iceriyor!\n"))
	  cat(sprintf("[PK_ANALIZ] Icerik: %s\n", substr(sql_query_text, 1, 300)))
	  return("⚠️ **Sistem Hatası:** SQL sorgusu yüklenemedi (dosya yolu algılandı).")
	}

	if (nchar(sql_query_text) < 10 || !grepl("SELECT|INSERT|UPDATE|DELETE|EXEC", sql_query_text, ignore.case = TRUE)) {
	  cat(sprintf("[PK_ANALIZ] HATA: Gecersiz SQL icerigi!\n"))
	  cat(sprintf("[PK_ANALIZ] Icerik: %s\n", substr(sql_query_text, 1, 200)))
	  return("⚠️ **Sistem Hatası:** Geçersiz SQL sorgusu yüklendi.")
	}

	target_db <- selected_query$db_target

	if (!is.null(target_db) && target_db != "primary") {
	   cat(sprintf("[PK_ANALIZ] Hedef DB 'primary' degil (%s). Baglanti degistiriliyor...\n", target_db))
	   
	   release_connection(conn_list)
	   
	   conn_list <- get_connection(target = target_db)
	   conn <- conn_list$conn
	}

	final_sql <- trimws(sql_query_text)

	cat(sprintf("[PK_ANALIZ] SQL DB'ye gonderiliyor (Ilk 100 kar.):\n--> %s...\n", substr(final_sql, 1, 100)))

  raw_data <- tryCatch({
    # Güvenlik Kontrolü
    if (grepl("\\b(DELETE|DROP|TRUNCATE|ALTER)\\b", toupper(final_sql))) {
      stop("Guvenlik ihlali: Yasakli SQL komutu.")
    }
    
    # Sorguyu Çalıştır
    DBI::dbGetQuery(conn, final_sql)
    
  }, error = function(e) {
    cat(sprintf("[PK_ANALIZ] SQL HATASI: %s\n", e$message))
    return(paste0("⚠️ **Veritabanı Hatası:** Sorgu çalıştırılırken hata oluştu.\n`", e$message, "`"))
  })
  
  if (is.character(raw_data) && startsWith(raw_data, "⚠️")) return(raw_data)
  
  cat(sprintf("[PK_ANALIZ] SQL Basarili. Dönen Satir: %d\n", nrow(raw_data)))
  
  secure_data <- apply_rls_to_data(raw_data, rls_info, selected_query$rls_columns)
  cat(sprintf("[PK_ANALIZ] RLS sonrasi: %d satir\n", nrow(secure_data)))
  
  if (nrow(secure_data) == 0) {
    return(paste0("🔍 **Sonuc:** Sorgu calistirildi ancak yetkiniz dahilinde veri bulunamadi."))
  }
  
  filter_criteria <- extract_filter_criteria_from_prompt(
    user_prompt,
    available_columns = names(secure_data),
    conn = conn
  )
  
  if (!is.null(filter_criteria$error)) {
    cat(sprintf("[PK_ANALIZ] AI filtreleme hatasi: %s\n", filter_criteria$error))
  }
  
  cat(sprintf("[PK_ANALIZ] AI Filter Sonucu -> column: %s, value: %s, operation: %s, aggregation: %s\n",
              filter_criteria$filter_column %||% "NULL",
              filter_criteria$filter_value %||% "NULL",
              filter_criteria$operation %||% "NULL",
              filter_criteria$aggregation %||% "NULL"))
  
  filtered_data <- apply_smart_filters(secure_data, filter_criteria, user_prompt)
  
  cat(sprintf("[PK_ANALIZ] Filtreleme sonrası: %d satır (Orijinal: %d)\n", 
              nrow(filtered_data), nrow(secure_data)))
  
  if (nrow(filtered_data) == 0) {
    return(paste0("🔍 **Sonuç:** Filtreleme sonrası veri bulunamadı."))
  }
  
  stat_summary <- generate_statistical_summary(filtered_data, max_preview_rows = 15)
  
  cat(sprintf("[PK_ANALIZ] Istatistiksel ozet olusturuldu: %d satir, %d onizleme\n",
              stat_summary$row_count,
              if (!is.null(stat_summary$preview_data)) nrow(stat_summary$preview_data) else 0))
  
  preview_json <- if (!is.null(stat_summary$preview_data) && nrow(stat_summary$preview_data) > 0) {
    jsonlite::toJSON(stat_summary$preview_data, auto_unbox = TRUE, pretty = FALSE)
  } else {
    "{}"
  }
  
  data_str <- paste0(
    stat_summary$summary_text,
    "\n\n--- ORNEK SATIRLAR (JSON) ---\n",
    preview_json,
    "\n\n(Not: Yukaridaki istatistikler ", stat_summary$row_count, " satirdan olusturulmustur)"
  )
  
  if (nrow(secure_data) > nrow(filtered_data)) {
    data_str <- paste0(
      data_str,
      sprintf("\n\n(RLS ve filtreleme oncesi toplam %d satir vardi)", nrow(secure_data))
    )
  }
  
  system_prompt <- paste0(
    "Sen MERGEN Bilge veri analiz asistanisin. Kullanicinin sorusuna, R tarafindan hazirlanan ISTATISTIKSEL OZET'e dayanarak cevap ver.\n\n",
    "Kullanilan Sorgu: ", selected_query$name, "\n",
    "Sorgu Aciklamasi: ", selected_query$description, "\n\n",
    "KRITIK: Sana gonderilen veri R tarafindan ZATEN FILTRELENMIS ve ISTATISTIKSEL OLARAK OZETLENMISTIR.\n",
    "Bu ozet SAYISAL SUTUNLAR icin toplam/ortalama/min/max, KATEGORIK SUTUNLAR icin en sik degerleri icerir.\n\n",
    "GOREVLER:\n",
    "1. Istatistiksel ozeti incele (sayisal istatistikler, kategorik dagilimlar)\n",
    "2. Kullanicinin sorusuna DOGRUDAN, NET ve TURKCE cevap ver\n",
    "3. Sayilari ozetten AYNEN kullan (yuvarlama, tahminde bulunma)\n",
    "4. Trendleri ve onemlı bulgulari vurgula\n",
    "5. Markdown formatinda yaz\n",
    "6. SADECE OZETTEKI VERILERE DAYAN - baska bilgi uydurma\n",
    "7. Eger ornek satirlar varsa, bunlari destekleyici olarak kullan\n"
  )
  
  user_msg <- paste0(
    "KULLANICI SORUSU:\n",
    user_prompt,
    "\n\n--- R TARAFINDAN HAZIRLANAN ISTATISTIKSEL OZET ---\n",
    data_str,
    "\n\n--- OZET SONU ---\n\n",
    "Talımat: Yukaridaki istatistikleri kullanarak kullanicinin sorusuna DOGRUDAN cevap ver. ",
    "Sayilari AYNEN kullan. Trendleri ve onemli bulgulari vurgula."
  )
  
  cat("[PK_ANALIZ] AI baglami hazirlandi. List donduruluyor.\n")
  
  return(list(
    type = "data_analysis",
    data = secure_data,
    prompt_context = system_prompt,
    user_context = user_msg,
    query_name = selected_query$name
  ))
}

# ==============================================================================
# 3. AKILLI SORGU SEÇİMİ (HEURISTIC)
# ==============================================================================

select_smart_query <- function(prompt, library, history) {
  cat("[PK_ANALIZ] Sorgu kütüphanesi taranıyor...\n")
  
  scores <- sapply(library, function(q) {
    desc_words <- unlist(strsplit(tolower(q$description), "\\W+"))
    prompt_words <- unlist(strsplit(tolower(prompt), "\\W+"))
    name_words <- unlist(strsplit(tolower(q$name), "\\W+"))
    
    # Basit eşleşme skoru
    match_count <- sum(prompt_words %in% c(desc_words, name_words))
    return(match_count)
  })
  
  # Skorları yazdır (Debugging)
  for(i in seq_along(library)) {
    if(scores[i] > 0) {
      cat(sprintf("   - Aday: %s | Skor: %d\n", library[[i]]$name, scores[i]))
    }
  }
  
  best_idx <- which.max(scores)
  
  if (length(best_idx) > 0 && scores[best_idx] > 0) {
    cat(sprintf("[PK_ANALIZ] EN IYI ESLESME: %s (Skor: %d)\n", library[[best_idx]]$name, scores[best_idx]))
    return(library[[best_idx]])
  }
  
  cat("[PK_ANALIZ] Hicbir sorgu ile eslesme saglanamadi.\n")
  return(NULL)
}